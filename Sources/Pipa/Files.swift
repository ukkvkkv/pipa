import AppKit

enum Paths {
    static let fm = FileManager.default

    static var support: URL {
        let u = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Pipa", isDirectory: true)
        try? fm.createDirectory(at: u, withIntermediateDirectories: true)
        return u
    }

    static var appsList: URL { support.appendingPathComponent("AppsList.txt") }
    static var customList: URL { support.appendingPathComponent("AppsListCustom.txt") }
    static var downloaded: URL { support.appendingPathComponent("DownloadedAppsList.json") }
    static var purchased: URL { support.appendingPathComponent("PurchasedAppsList.json") }
    static var warning: URL { support.appendingPathComponent("Warning.txt") }

    static var ipatoolHome: URL { URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent(".ipatool") }
    static var loginMarker: URL { ipatoolHome.appendingPathComponent("login") }
    static let authFiles = ["account", "cookies", "login"]

    /// ~/Pipa, а не «Загрузки»/«Документы»: те macOS охраняет и спрашивает
    /// доступ, а у сборки без сертификата разрешение слетает с каждой версией.
    static var defaultApps: URL {
        URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Pipa", isDirectory: true)
    }

    static var apps: URL {
        let u = UserDefaults.standard.string(forKey: "appsFolder").map { URL(fileURLWithPath: $0) } ?? defaultApps
        try? fm.createDirectory(at: u, withIntermediateDirectories: true)
        return u
    }

    /// Приложение звалось «IPA Downloader» (до 08.10.2026): переносит его
    /// данные, логи и настройки под имя Pipa. Вызывать до
    /// первого обращения к `support` — он сам создаёт пустую папку.
    static func migrateOldName() {
        let lib = fm.urls(for: .libraryDirectory, in: .userDomainMask)[0]
        for (old, new) in [
            (lib.appendingPathComponent("Application Support/IPA Downloader"), lib.appendingPathComponent("Application Support/Pipa")),
            (lib.appendingPathComponent("Logs/IPA Downloader"), lib.appendingPathComponent("Logs/Pipa")),
        ] where fm.fileExists(atPath: old.path) && !fm.fileExists(atPath: new.path) {
            try? fm.moveItem(at: old, to: new)
        }
        let defaults = UserDefaults.standard
        // Настройки прежних идентификаторов приложения.
        for suite in ["com.kda2495.pipa", "com.kda2495.ipadownloader"] {
            guard let old = UserDefaults(suiteName: suite) else { continue }
            for key in ["appsFolder", "debug"] where defaults.object(forKey: key) == nil {
                if let v = old.object(forKey: key) { defaults.set(v, forKey: key) }
            }
        }
        // Старая папка по умолчанию (~/Downloads/IPA Downloader) — не выбор
        // пользователя: забываем, чтобы взялась новая.
        if defaults.string(forKey: "appsFolder")?.hasSuffix("/Downloads/IPA Downloader") == true {
            defaults.removeObject(forKey: "appsFolder")
        }
    }
}

enum Log {
    static var url: URL {
        let dir = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Logs/Pipa", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("app.log")
    }

    static func write(_ text: String) {
        let line = "[\(Date().formatted(.iso8601))] \(text)\n"
        guard let data = line.data(using: .utf8) else { return }
        if let h = try? FileHandle(forWritingTo: url) {
            h.seekToEndOfFile(); h.write(data); try? h.close()
        } else {
            try? data.write(to: url)
        }
    }
}

// MARK: - Списки приложений

struct ListEntry: Identifiable, Hashable {
    var id: String
    var name: String
}

enum AppLists {
    /// Формат «Название: ID» по строке, как в Files/AppsList.txt.
    static func read(_ url: URL) -> [ListEntry] {
        guard let raw = try? String(contentsOf: url, encoding: .utf8) else { return [] }
        var seen = Set<String>()
        var out: [ListEntry] = []
        let re = try! NSRegularExpression(pattern: "^(.+?):\\s*(\\d+)")
        for line in raw.components(separatedBy: .newlines) {
            let ns = line as NSString
            guard let m = re.firstMatch(in: line, range: NSRange(location: 0, length: ns.length)) else { continue }
            let name = ns.substring(with: m.range(at: 1)).trimmingCharacters(in: .whitespaces)
            let id = ns.substring(with: m.range(at: 2))
            if seen.insert(id).inserted { out.append(ListEntry(id: id, name: name)) }
        }
        return out
    }

    static func write(_ entries: [ListEntry], to url: URL) {
        let text = entries.map { "\($0.name): \($0.id)" }.joined(separator: "\n")
        try? text.write(to: url, atomically: true, encoding: .utf8)
    }

    static let remoteBase = "https://raw.githubusercontent.com/kda2495/IPA_Downloader/refs/heads/main/Files/"

    /// Обновляет AppsList.txt и Warning.txt из репозитория автора скрипта.
    static func refreshRemote() async {
        for name in ["AppsList.txt", "Warning.txt"] {
            guard let url = URL(string: remoteBase + name) else { continue }
            var req = URLRequest(url: url)
            req.timeoutInterval = 6
            guard let (data, resp) = try? await URLSession.shared.data(for: req),
                  (resp as? HTTPURLResponse)?.statusCode == 200 else { continue }
            try? data.write(to: Paths.support.appendingPathComponent(name), options: .atomic)
        }
    }
}

/// Истории покупок и загрузок: { "почта": [ {Name, AppID} ] } — тот же файл,
/// что вёл скрипт, чтобы его можно было перенести туда и обратно.
enum History {
    static func read(_ url: URL) -> [String: [ListEntry]] {
        guard let data = try? Data(contentsOf: url),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return [:] }
        var out: [String: [ListEntry]] = [:]
        for (account, value) in obj {
            let items: [[String: Any]]
            if let arr = value as? [[String: Any]] { items = arr }
            else if let one = value as? [String: Any] { items = [one] }
            else { continue }
            out[account] = items.compactMap { d in
                guard let id = d["AppID"].map({ "\($0)" }) else { return nil }
                return ListEntry(id: id, name: d["Name"] as? String ?? id)
            }
        }
        return out
    }

    static func add(_ entry: ListEntry, account: String, to url: URL) {
        var all = read(url)
        var list = all[account] ?? []
        if !list.contains(where: { $0.id == entry.id }) { list.append(entry) }
        list.sort { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        all[account] = list
        save(all, to: url)
    }

    static func save(_ all: [String: [ListEntry]], to url: URL) {
        let obj = all.mapValues { $0.map { ["Name": $0.name, "AppID": $0.id] } }
        if let data = try? JSONSerialization.data(withJSONObject: obj, options: [.prettyPrinted, .sortedKeys]) {
            try? data.write(to: url, options: .atomic)
        }
    }
}

// MARK: - Файлы .ipa

struct IPAFile: Identifiable, Hashable {
    var url: URL
    var name: String
    var itemID: String?     // ID в App Store из iTunesMetadata.plist
    var artwork: URL?       // иконка, вынутая из .ipa в кэш
    var version: String
    var minIOS: String
    var bundleID: String
    var size: Int64
    var date: Date

    var id: URL { url }
    var account: String? {
        let base = url.deletingPathExtension().lastPathComponent
        guard let at = base.lastIndex(of: "_") else { return nil }
        let tail = String(base[base.index(after: at)...])
        return tail.contains("@") ? tail : nil
    }
}

enum IPAReader {
    /// Info.plist из Payload/*.app — через системный unzip, без сторонних библиотек.
    static func read(_ url: URL) -> IPAFile? {
        let attrs = try? FileManager.default.attributesOfItem(atPath: url.path)
        let size = (attrs?[.size] as? NSNumber)?.int64Value ?? 0
        let date = attrs?[.modificationDate] as? Date ?? .distantPast
        // Точное имя Info.plist главного приложения: шаблон «Payload/*.app/…»
        // в unzip захватил бы и вложенные .app (часы, расширения).
        let entries = String(decoding: run(["-Z1", url.path]), as: UTF8.self).split(separator: "\n")
        let plistEntry = entries.first { line in
            let parts = line.split(separator: "/", omittingEmptySubsequences: false)
            return parts.count == 3 && parts[0] == "Payload" && parts[1].hasSuffix(".app") && parts[2] == "Info.plist"
        }.map(String.init)
        let info = plistEntry.flatMap {
            try? PropertyListSerialization.propertyList(from: unzip(url, $0), format: nil) as? [String: Any]
        } ?? [:]
        let name = (info["CFBundleDisplayName"] as? String) ?? (info["CFBundleName"] as? String)
            ?? url.deletingPathExtension().lastPathComponent
        let bundle = info["CFBundleIdentifier"] as? String ?? ""
        let meta = (try? PropertyListSerialization.propertyList(from: unzip(url, "iTunesMetadata.plist"), format: nil)) as? [String: Any]
        let itemID = meta?["itemId"].map { "\($0)" }
        return IPAFile(url: url, name: name, itemID: itemID, artwork: artwork(url, key: bundle.isEmpty ? (itemID ?? name) : bundle),
                       version: info["CFBundleShortVersionString"] as? String ?? "—",
                       minIOS: info["MinimumOSVersion"] as? String ?? "—",
                       bundleID: bundle,
                       size: size, date: date)
    }

    static func unzip(_ url: URL, _ entry: String) -> Data {
        // unzip понимает имя как шаблон — скобки экранируем.
        let pattern = entry.replacingOccurrences(of: "[", with: "\\[").replacingOccurrences(of: "]", with: "\\]")
        return run(["-p", url.path, pattern])
    }

    private static func run(_ args: [String]) -> Data {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
        p.arguments = args
        let pipe = Pipe()
        p.standardOutput = pipe
        p.standardError = FileHandle.nullDevice
        guard (try? p.run()) != nil else { return Data() }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        return data
    }

    static var iconCache: URL {
        let u = Paths.support.appendingPathComponent("Icons", isDirectory: true)
        try? FileManager.default.createDirectory(at: u, withIntermediateDirectories: true)
        return u
    }

    /// iTunesArtwork (600×600), который App Store кладёт в каждую .ipa, — в кэш.
    /// Так у скачанного приложения иконка есть, даже если его сняли с витрины.
    static func artwork(_ url: URL, key: String) -> URL? {
        let dst = iconCache.appendingPathComponent(safeName(key) + ".png")
        if FileManager.default.fileExists(atPath: dst.path) { return dst }
        let data = unzip(url, "iTunesArtwork")
        guard !data.isEmpty, NSImage(data: data) != nil else { return nil }
        try? data.write(to: dst, options: .atomic)
        return dst
    }

    static func safeName(_ s: String) -> String {
        s.replacingOccurrences(of: "[\\\\/:*?\"<>|]", with: "", options: .regularExpression)
            .replacingOccurrences(of: "\\s+", with: "_", options: .regularExpression)
    }
}

extension String {
    /// Сравнение версий iOS вида 15.2 / 17.6.1.
    func versionCompare(_ other: String) -> ComparisonResult {
        let a = split(separator: ".").map { Int($0) ?? 0 }
        let b = other.split(separator: ".").map { Int($0) ?? 0 }
        for i in 0..<max(a.count, b.count) {
            let x = i < a.count ? a[i] : 0, y = i < b.count ? b[i] : 0
            if x != y { return x < y ? .orderedAscending : .orderedDescending }
        }
        return .orderedSame
    }
}
