import SwiftUI

enum Section: String, Hashable, CaseIterable {
    case search, library

    var title: String {
        switch self {
        case .search: "Поиск"
        case .library: "Библиотека"
        }
    }

    var symbol: String {
        switch self {
        case .search: "magnifyingglass"
        case .library: "square.grid.2x2"
        }
    }
}

@MainActor
@Observable
final class DownloadJob: Identifiable {
    enum State: Equatable { case queued, running, done(URL), failed(String), cancelled }

    let id = UUID()
    let appID: String
    let name: String
    let version: String?       // externalVersionID или nil = последняя
    let versionLabel: String?
    var state: State = .queued
    var progress: Double = 0
    /// Скачано байт (по размеру временного файла ipatool).
    var bytes: Int64 = 0
    let box = ProcessBox()

    init(appID: String, name: String, version: String?, versionLabel: String?) {
        self.appID = appID; self.name = name; self.version = version; self.versionLabel = versionLabel
    }

    var isActive: Bool { state == .queued || state == .running }

    /// Полный размер: ipatool сообщает только проценты, а файл растёт ровно
    /// вместе с ними — делим одно на другое, когда процент уже не ноль.
    var totalBytes: Int64? {
        progress >= 0.02 && bytes > 0 ? Int64(Double(bytes) / progress) : nil
    }

    /// Следит за размером файла, пока идёт загрузка.
    func watch(_ file: URL) -> Task<Void, Never> {
        Task { @MainActor [weak self] in
            while !Task.isCancelled, let self {
                let size = (try? FileManager.default.attributesOfItem(atPath: file.path)[.size] as? Int64) ?? nil
                if let size, size > 0 { bytes = size }
                try? await Task.sleep(for: .milliseconds(700))
            }
        }
    }
}

struct Toast: Identifiable, Equatable {
    let id = UUID()
    var text: String
    var symbol: String = "checkmark.circle.fill"
    var isError = false
}

struct ConnectedDevice: Equatable {
    var name: String
    var iOS: String
}

@MainActor
@Observable
final class AppModel {
    var section: Section = .search

    // Аккаунт
    var account: AccountInfo?
    var savedAccounts: [String] = []
    var checkingAuth = true
    var showLogin = false
    /// Аккаунт, отложенный на время входа в новый — вернётся, если вход отменят.
    private var parkedAccount: String?

    // Списки
    var mainList: [ListEntry] = []
    var customList: [ListEntry] = []
    var downloaded: [String: [ListEntry]] = [:]
    var purchased: [String: [ListEntry]] = [:]
    var warning: String = ""

    // Библиотека и устройство
    var library: [IPAFile] = []
    var libraryLoading = false
    var device: ConnectedDevice?
    var installing: Set<URL> = []

    // Загрузки
    var jobs: [DownloadJob] = []
    private var queueRunning = false

    var toasts: [Toast] = []

    var activeJobs: Int { jobs.filter(\.isActive).count }
    var overallProgress: Double? {
        let active = jobs.filter(\.isActive)
        guard !active.isEmpty else { return nil }
        return active.map(\.progress).reduce(0, +) / Double(active.count)
    }

    var myDownloaded: [ListEntry] { account.map { downloaded[$0.email] ?? [] } ?? [] }
    var myPurchased: [ListEntry] { account.map { purchased[$0.email] ?? [] } ?? [] }

    // MARK: - Запуск

    func start() async {
        reloadLists()
        Task { await refreshAuth() }
        Task {
            await AppLists.refreshRemote()
            reloadLists()
        }
        Task { await reloadLibrary() }
        Task { await pollDevice() }
    }

    func reloadLists() {
        mainList = AppLists.read(Paths.appsList)
        customList = AppLists.read(Paths.customList)
        downloaded = History.read(Paths.downloaded)
        purchased = History.read(Paths.purchased)
        warning = ((try? String(contentsOf: Paths.warning, encoding: .utf8)) ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func displayName(for id: String) -> String? {
        customList.first { $0.id == id }?.name ?? mainList.first { $0.id == id }?.name
    }

    func toast(_ text: String, symbol: String = "checkmark.circle.fill", error: Bool = false) {
        let t = Toast(text: text, symbol: error ? "exclamationmark.triangle.fill" : symbol, isError: error)
        withAnimation(.spring(duration: 0.35)) { toasts.append(t) }
        Task {
            try? await Task.sleep(for: .seconds(error ? 6 : 3.5))
            withAnimation(.spring(duration: 0.35)) { toasts.removeAll { $0.id == t.id } }
        }
    }

    // MARK: - Аккаунты (та же раскладка ~/.ipatool, что у скрипта)

    func refreshAuth() async {
        checkingAuth = true
        defer { checkingAuth = false }
        savedAccounts = listSavedAccounts()
        if FileManager.default.fileExists(atPath: Paths.loginMarker.path), let info = await IPATool.authInfo() {
            account = info
            Artwork.shared.country = info.storefront
            // Аккаунт активен — его старая отложенная копия не нужна.
            let stale = Paths.ipatoolHome.appendingPathComponent(info.email)
            if FileManager.default.fileExists(atPath: stale.path) { try? FileManager.default.removeItem(at: stale) }
            savedAccounts = listSavedAccounts()
        } else {
            // Файлы не трогаем: без сети auth info тоже не отвечает, а
            // стирать вход из-за этого нельзя.
            account = nil
        }
    }

    private func listSavedAccounts() -> [String] {
        let fm = FileManager.default
        guard let items = try? fm.contentsOfDirectory(at: Paths.ipatoolHome, includingPropertiesForKeys: [.isDirectoryKey]) else { return [] }
        return items.filter { (try? $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true }
            .map(\.lastPathComponent).filter { $0.contains("@") }.sorted()
    }

    private func parkActive(as email: String) {
        let fm = FileManager.default
        let dir = Paths.ipatoolHome.appendingPathComponent(email)
        try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        for f in Paths.authFiles {
            let src = Paths.ipatoolHome.appendingPathComponent(f)
            let dst = dir.appendingPathComponent(f)
            if fm.fileExists(atPath: src.path) {
                try? fm.removeItem(at: dst)
                try? fm.moveItem(at: src, to: dst)
            }
        }
    }

    private func unpark(_ email: String) {
        let fm = FileManager.default
        let dir = Paths.ipatoolHome.appendingPathComponent(email)
        for f in Paths.authFiles {
            let src = dir.appendingPathComponent(f)
            let dst = Paths.ipatoolHome.appendingPathComponent(f)
            if fm.fileExists(atPath: src.path) {
                try? fm.removeItem(at: dst)
                try? fm.moveItem(at: src, to: dst)
            }
        }
        try? fm.removeItem(at: dir)
    }

    private func clearActiveFiles() {
        for f in Paths.authFiles {
            try? FileManager.default.removeItem(at: Paths.ipatoolHome.appendingPathComponent(f))
        }
    }

    func beginAddAccount(present: Bool = true) {
        if let current = account?.email {
            parkActive(as: current)
            parkedAccount = current
            account = nil
        }
        if present { showLogin = true }
    }

    func cancelLogin() async {
        showLogin = false
        if let parked = parkedAccount {
            clearActiveFiles()
            unpark(parked)
            parkedAccount = nil
            await refreshAuth()
        }
    }

    func login(email: String, password: String, code: String?) async -> IPATool.LoginOutcome {
        let outcome = await IPATool.login(email: email, password: password, code: code)
        if case .success = outcome {
            FileManager.default.createFile(atPath: Paths.loginMarker.path, contents: nil)
            await IPATool.kbsyncRefresh()
            parkedAccount = nil
            showLogin = false
            await refreshAuth()
            if let a = account { toast("Вход выполнен: \(a.email)") }
        }
        return outcome
    }

    func switchTo(_ email: String) async {
        if let current = account?.email { parkActive(as: current) }
        unpark(email)
        await refreshAuth()
        if account == nil {
            toast("Сессия \(email) истекла — войдите заново.", error: true)
        } else {
            toast("Текущий аккаунт: \(email)", symbol: "person.crop.circle.badge.checkmark")
        }
    }

    func logoutCurrent() async {
        await IPATool.revoke()
        clearActiveFiles()
        let left = listSavedAccounts()
        account = nil
        if let next = left.first {
            await switchTo(next)
        } else {
            savedAccounts = []
        }
    }

    func removeSaved(_ email: String) {
        try? FileManager.default.removeItem(at: Paths.ipatoolHome.appendingPathComponent(email))
        savedAccounts = listSavedAccounts()
    }

    // MARK: - Покупка и загрузка

    func purchase(_ apps: [ListEntry]) async {
        guard let email = account?.email else { return }
        for app in apps {
            do {
                try await IPATool.purchase(app.id)
                History.add(app, account: email, to: Paths.purchased)
                toast("Получено: \(app.name)", symbol: "bag.fill.badge.plus")
            } catch {
                toast("\(app.name): \(error.localizedDescription)", error: true)
            }
        }
        reloadLists()
    }

    func enqueue(_ app: ListEntry, version: String? = nil, versionLabel: String? = nil) {
        if jobs.contains(where: { $0.appID == app.id && $0.version == version && $0.isActive }) { return }
        jobs.insert(DownloadJob(appID: app.id, name: app.name, version: version, versionLabel: versionLabel), at: 0)
        toast("В очереди: \(app.name)\(versionLabel.map { " \($0)" } ?? "")", symbol: "arrow.down.circle.fill")
        Task { await runQueue() }
    }

    func cancel(_ job: DownloadJob) {
        if job.state == .queued { job.state = .cancelled } else { job.box.cancel() }
    }

    func clearFinishedJobs() {
        jobs.removeAll { !$0.isActive }
    }

    private func runQueue() async {
        guard !queueRunning else { return }
        queueRunning = true
        defer { queueRunning = false }
        while let job = jobs.last(where: { $0.state == .queued }) {
            await run(job)
        }
    }

    private func run(_ job: DownloadJob) async {
        guard let email = account?.email else {
            job.state = .failed("Нет входа в аккаунт Apple."); return
        }
        job.state = .running
        let folder = Paths.apps
        let tmp = folder.appendingPathComponent(".download-\(job.appID)-\(job.id.uuidString.prefix(8)).ipa")
        let watcher = job.watch(tmp.appendingPathExtension("tmp"))
        defer { watcher.cancel() }
        do {
            try await IPATool.download(job.appID, version: job.version, to: tmp, process: job.box) { p in
                Task { @MainActor in job.progress = max(job.progress, p) }
            }
            job.progress = 1
            let meta = IPAReader.read(tmp)
            let base = displayName(for: job.appID) ?? job.name
            let name = IPAReader.safeName("\(base)_\(meta?.version ?? "0")_iOS_\(meta?.minIOS ?? "NA")+_\(email)") + ".ipa"
            let final = folder.appendingPathComponent(name)
            try? FileManager.default.removeItem(at: final)
            try FileManager.default.moveItem(at: tmp, to: final)
            History.add(ListEntry(id: job.appID, name: base), account: email, to: Paths.downloaded)
            job.state = .done(final)
            reloadLists()
            toast("Скачано: \(base) \(meta?.version ?? "")", symbol: "checkmark.circle.fill")
            await reloadLibrary()
        } catch is CancellationError {
            job.state = .cancelled
        } catch {
            job.state = .failed(error.localizedDescription)
            toast("\(job.name): \(error.localizedDescription)", error: true)
        }
        for leftover in [tmp, tmp.appendingPathExtension("tmp")] {
            try? FileManager.default.removeItem(at: leftover)
        }
    }

    // MARK: - Библиотека

    func reloadLibrary() async {
        libraryLoading = true
        defer { libraryLoading = false }
        let folder = Paths.apps
        let files = await Task.detached(priority: .userInitiated) { () -> [IPAFile] in
            let urls = (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? []
            return urls.filter { $0.pathExtension.lowercased() == "ipa" && !$0.lastPathComponent.hasPrefix(".") }
                .compactMap(IPAReader.read)
                .sorted { $0.date > $1.date }
        }.value
        for f in files {
            if let art = f.artwork { Artwork.shared.register(id: f.itemID, bundle: f.bundleID, file: art) }
        }
        library = files
    }

    func trash(_ file: IPAFile) {
        do {
            try FileManager.default.trashItem(at: file.url, resultingItemURL: nil)
            library.removeAll { $0.url == file.url }
            toast("Перемещено в Корзину: \(file.name)", symbol: "trash.fill")
        } catch {
            toast(error.localizedDescription, error: true)
        }
    }

    // MARK: - iPhone по USB

    private func pollDevice() async {
        while true {
            device = await readDevice()
            try? await Task.sleep(for: .seconds(4))
        }
    }

    private func readDevice() async -> ConnectedDevice? {
        guard let info = Tools.idevice("ideviceinfo") else { return nil }
        let r = await Tools.run(info, ["-s"])
        guard r.ok else { return nil }
        var d: [String: String] = [:]
        for line in r.stdout.split(separator: "\n") {
            let parts = line.split(separator: ":", maxSplits: 1)
            if parts.count == 2 { d[String(parts[0])] = parts[1].trimmingCharacters(in: .whitespaces) }
        }
        guard let ver = d["ProductVersion"] else { return nil }
        return ConnectedDevice(name: d["DeviceName"] ?? "iPhone", iOS: ver)
    }

    var canInstall: Bool { Tools.idevice("ideviceinstaller") != nil }

    func install(_ file: IPAFile) async {
        guard let tool = Tools.idevice("ideviceinstaller") else {
            toast("ideviceinstaller не найден — установка по USB недоступна.", error: true); return
        }
        installing.insert(file.url)
        defer { installing.remove(file.url) }
        // Кириллица и пробелы в пути ideviceinstaller не любит — ставим из временной копии, как скрипт.
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("Temp-\(UUID().uuidString.prefix(6)).ipa")
        do { try FileManager.default.copyItem(at: file.url, to: tmp) } catch {
            toast(error.localizedDescription, error: true); return
        }
        defer { try? FileManager.default.removeItem(at: tmp) }
        var r = await Tools.run(tool, ["install", tmp.path])
        if !r.ok { r = await Tools.run(tool, ["upgrade", tmp.path]) }
        if r.ok {
            toast("Установлено на \(device?.name ?? "iPhone"): \(file.name)", symbol: "iphone.gen3.badge.checkmark")
        } else {
            let msg = r.message.split(separator: "\n").suffix(2).joined(separator: " ")
            toast("Не удалось установить \(file.name). \(msg)", error: true)
        }
    }
}
