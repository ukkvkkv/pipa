import SwiftUI

// MARK: - Библиотека

struct LibraryView: View {
    @Environment(AppModel.self) private var model
    @State private var filter = ""
    @State private var selection: URL?
    @State private var confirmTrash: IPAFile?

    private var files: [IPAFile] {
        guard !filter.isEmpty else { return model.library }
        return model.library.filter { $0.name.localizedCaseInsensitiveContains(filter) || $0.bundleID.localizedCaseInsensitiveContains(filter) }
    }

    var body: some View {
        VStack(spacing: 0) {
            if model.library.isEmpty {
                if model.libraryLoading {
                    ProgressView().frame(maxHeight: .infinity)
                } else {
                    ContentUnavailableView {
                        Label("Пусто", systemImage: "square.grid.2x2")
                    } description: {
                        Text("Скачанные .ipa появятся здесь.")
                    } actions: {
                        Button("Открыть папку") { NSWorkspace.shared.open(Paths.apps) }
                            .buttonStyle(.glass)
                    }
                }
            } else {
                List(files, selection: $selection) { file in
                    IPARow(file: file)
                        .tag(file.url)
                        .draggable(file.url)
                        .contextMenu { menu(file) }
                }
            }
        }
        .task { await model.reloadLibrary() }
        .confirmationDialog("Переместить «\(confirmTrash?.name ?? "")» в Корзину?",
                            isPresented: Binding(get: { confirmTrash != nil }, set: { if !$0 { confirmTrash = nil } }),
                            presenting: confirmTrash) { f in
            Button("В Корзину", role: .destructive) { model.trash(f) }
        }
    }

    @ViewBuilder
    private func menu(_ file: IPAFile) -> some View {
        Button("Установить на iPhone") { Task { await model.install(file) } }
            .disabled(model.device == nil || !model.canInstall)
        Button("Показать в Finder") { NSWorkspace.shared.activateFileViewerSelecting([file.url]) }
        ShareLink("Поделиться…", item: file.url)
        Button("Скопировать bundle ID") {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(file.bundleID, forType: .string)
        }
        Divider()
        Button("В Корзину", role: .destructive) { confirmTrash = file }
    }
}

struct IPARow: View {
    var file: IPAFile
    @Environment(AppModel.self) private var model

    private var tooNew: Bool {
        guard let d = model.device, file.minIOS != "—" else { return false }
        return d.iOS.versionCompare(file.minIOS) == .orderedAscending
    }

    var body: some View {
        HStack(spacing: 12) {
            AppIcon(id: file.itemID, bundle: file.bundleID, name: file.name, size: 46)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 5) {
                    Text(file.name).font(.system(size: 15, weight: .medium)).lineLimit(1)
                    Text(file.version).font(.system(size: 15)).foregroundStyle(.secondary).lineLimit(1)
                }
                HStack(spacing: 4) {
                    Text("iOS \(file.minIOS)+").foregroundStyle(tooNew ? AnyShapeStyle(.orange) : AnyShapeStyle(.secondary))
                    Text("· \(ByteCountFormatter.string(fromByteCount: file.size, countStyle: .file))")
                    if let acc = file.account { Text("· \(acc)").truncationMode(.middle) }
                }
                .font(.system(size: 12)).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer(minLength: 6)
            if model.installing.contains(file.url) {
                ProgressView().controlSize(.small).padding(.horizontal, 8)
            } else {
                RowCapsule {
                    Button { NSWorkspace.shared.activateFileViewerSelecting([file.url]) } label: {
                        Label("Показать в Finder", systemImage: "folder")
                    }
                    .toolTip("Показать в Finder")
                    Button { Task { await model.install(file) } } label: {
                        Label("На iPhone", systemImage: "iphone.and.arrow.forward")
                    }
                    .disabled(model.device == nil || !model.canInstall || tooNew)
                    .toolTip(model.device == nil ? "Подключите iPhone кабелем"
                             : tooNew ? "Нужна iOS \(file.minIOS) или новее" : "Установить на \(model.device?.name ?? "iPhone")")
                }
            }
        }
        .padding(.vertical, 5)
    }
}

// MARK: - Загрузки

struct DownloadsPopover: View {
    @Environment(AppModel.self) private var model

    /// Строки одной высоты в любом состоянии — как в Safari: окно не
    /// прыгает, когда полоска загрузки сменяется размером файла.
    static let rowHeight: CGFloat = 60

    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                Text("Загрузки").font(.headline)
                HStack {
                    Spacer()
                    Button("Очистить") { model.clearFinishedJobs() }
                        .buttonStyle(.glass)
                        .controlSize(.small)
                        .disabled(!model.jobs.contains(where: { !$0.isActive }))
                }
            }
            .padding(.horizontal, 12).padding(.top, 12).padding(.bottom, 6)
            if model.jobs.isEmpty {
                Text("Загрузок нет").foregroundStyle(.secondary)
                    .frame(height: Self.rowHeight)
            } else {
                ScrollView {
                    VStack(spacing: 0) {
                        ForEach(model.jobs) { JobRow(job: $0) }
                    }
                }
                .scrollBounceBehavior(.basedOnSize)
                .frame(height: min(CGFloat(model.jobs.count), 6) * Self.rowHeight)
            }
        }
        .padding(.bottom, 6)
        .frame(width: 380)
    }
}

struct JobRow: View {
    var job: DownloadJob
    @Environment(AppModel.self) private var model

    var body: some View {
        HStack(spacing: 12) {
            AppIcon(id: job.appID, name: job.name, size: 36)
            VStack(alignment: .leading, spacing: 4) {
                Text(job.name + (job.versionLabel.map { " \($0)" } ?? ""))
                    .font(.system(size: 13, weight: .medium)).lineLimit(1)
                if job.state == .running {
                    ProgressView(value: job.progress).progressViewStyle(.linear).controlSize(.small)
                }
                subtitle.font(.system(size: 11)).monospacedDigit().lineLimit(1)
            }
            Spacer(minLength: 4)
            action
                .buttonStyle(.borderless)
                .foregroundStyle(.secondary)
                .font(.title3)
        }
        .padding(.horizontal, 16)
        .frame(height: DownloadsPopover.rowHeight)
    }

    @ViewBuilder private var subtitle: some View {
        switch job.state {
        case .queued: Text("В очереди").foregroundStyle(.secondary)
        case .running: Text(job.statusLine).foregroundStyle(.secondary)
        case .done(let url): Text(Self.size(of: url)).foregroundStyle(.secondary)
        case .failed(let msg): Text(msg).foregroundStyle(.red).help(msg)
        case .cancelled: Text("Отменено").foregroundStyle(.secondary)
        }
    }

    @ViewBuilder private var action: some View {
        switch job.state {
        case .queued, .running:
            Button { model.cancel(job) } label: { Image(systemName: "xmark.circle.fill") }
                .help("Отменить")
        case .done(let url):
            Button { NSWorkspace.shared.activateFileViewerSelecting([url]) } label: { Image(systemName: "magnifyingglass.circle.fill") }
                .help("Показать в Finder")
        case .failed, .cancelled:
            Button {
                model.enqueue(ListEntry(id: job.appID, name: job.name), version: job.version, versionLabel: job.versionLabel)
            } label: { Image(systemName: "arrow.clockwise.circle.fill") }
                .help("Повторить")
        }
    }

    static func size(of url: URL) -> String {
        let bytes = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize).flatMap { $0 } ?? 0
        return bytes > 0 ? ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .file) : "Готово"
    }
}

extension DownloadJob {
    /// «42 % · 38 МБ из 91 МБ»
    var statusLine: String {
        var parts = ["\(Int(progress * 100)) %"]
        let mb = { (b: Int64) in ByteCountFormatter.string(fromByteCount: b, countStyle: .file) }
        if let total = totalBytes { parts.append("\(mb(bytes)) из \(mb(total))") }
        else if bytes > 0 { parts.append(mb(bytes)) }
        return parts.joined(separator: " · ")
    }
}

// MARK: - Настройки

struct SettingsView: View {
    @Environment(AppModel.self) private var model
    @State private var folder = Paths.apps.path(percentEncoded: false)
    @State private var showLogin = false
    @State private var confirmLogout = false

    var body: some View {
        Form {
            SwiftUI.Section("Аккаунт Apple") {
                if let a = model.account {
                    HStack(spacing: 12) {
                        Image(systemName: "person.crop.circle.fill")
                            .font(.system(size: 34))
                            .foregroundStyle(.secondary)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(a.name.isEmpty ? a.email : a.name).font(.headline)
                            Text("\(a.email) · \(a.storefront)").font(.callout).foregroundStyle(.secondary)
                                .textSelection(.enabled)
                        }
                        Spacer()
                        Button("Выйти", role: .destructive) { confirmLogout = true }
                    }
                } else if model.checkingAuth {
                    ProgressView().controlSize(.small)
                } else {
                    LabeledContent("Нет входа") {
                        Button("Войти…") { showLogin = true }
                    }
                }

                ForEach(model.savedAccounts, id: \.self) { email in
                    LabeledContent(email) {
                        HStack {
                            Button("Сделать текущим") { Task { await model.switchTo(email) } }
                            Button(role: .destructive) { model.removeSaved(email) } label: { Image(systemName: "xmark") }
                                .help("Забыть аккаунт")
                        }
                    }
                }

                if model.account != nil {
                    Button("Добавить аккаунт…") {
                        model.beginAddAccount(present: false)
                        showLogin = true
                    }
                }
            }

            SwiftUI.Section("Файлы") {
                HStack(spacing: 8) {
                    Text("Папка для .ipa").fixedSize()
                    Spacer(minLength: 8)
                    Text((folder as NSString).abbreviatingWithTildeInPath)
                        .lineLimit(1).truncationMode(.middle)
                        .foregroundStyle(.secondary)
                        .help(folder)
                    Button("Изменить…", action: chooseFolder).fixedSize()
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 460)
        .fixedSize(horizontal: false, vertical: true)
        .sheet(isPresented: $showLogin) { LoginSheet() }
        .confirmationDialog("Выйти из \(model.account?.email ?? "")?", isPresented: $confirmLogout) {
            Button("Выйти", role: .destructive) { Task { await model.logoutCurrent() } }
        } message: {
            Text("Для повторного входа понадобится код подтверждения.")
        }
    }

    private func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.directoryURL = Paths.apps
        panel.prompt = "Выбрать"
        if panel.runModal() == .OK, let url = panel.url {
            UserDefaults.standard.set(url.path, forKey: "appsFolder")
            folder = url.path(percentEncoded: false)
            Task { await model.reloadLibrary() }
        }
    }
}
