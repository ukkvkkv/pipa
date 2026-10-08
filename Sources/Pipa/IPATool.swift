import Foundation

struct StoreApp: Identifiable, Hashable {
    var id: String          // trackId
    var name: String
    var bundleID: String = ""
    var version: String = ""
    var price: Double? = nil
}

struct AccountInfo: Equatable {
    var email: String
    var name: String
    var storefront: String
}

/// Обёртка над ipatool-cpp: те же вызовы, что делал IPA_Downloader.ps1.
enum IPATool {
    static var debug: Bool { UserDefaults.standard.bool(forKey: "debug") }

    static func run(_ args: [String], process: ProcessBox? = nil,
                    onStderrLine: (@Sendable (String) -> Void)? = nil) async -> ToolResult {
        var args = args
        if debug { args.append("--debug") }
        let r = await Tools.run(Tools.ipatool, args, process: process, onStderrLine: onStderrLine)
        if debug { Log.write("ipatool \(args.filter { !$0.isEmpty }.prefix(3).joined(separator: " ")) → \(r.code)\n\(r.message)") }
        return r
    }

    static func authInfo() async -> AccountInfo? {
        let r = await run(["auth", "info", "--format", "json"])
        guard let j = r.json, j["success"] as? Bool == true, let email = j["email"] as? String else { return nil }
        return AccountInfo(email: email, name: j["name"] as? String ?? "", storefront: j["storefront"] as? String ?? "")
    }

    enum LoginOutcome {
        case success
        case needsCode
        case failure(String)
    }

    static func login(email: String, password: String, code: String?) async -> LoginOutcome {
        var args = ["auth", "login", "-e", email, "-p", password, "--format", "json"]
        if let code, !code.isEmpty { args += ["-a", code] }
        let r = await Tools.run(Tools.ipatool, args)
        let msg = r.message
        if msg.localizedCaseInsensitiveContains("two-factor") || msg.localizedCaseInsensitiveContains("auth code is required") {
            return .needsCode
        }
        if let j = r.json, j["success"] as? Bool == true { return .success }
        if r.ok && !msg.localizedCaseInsensitiveContains("error") { return .success }
        return .failure(friendly(msg))
    }

    static func kbsyncRefresh() async {
        _ = await run(["kbsync", "--refresh"])
    }

    static func revoke() async {
        _ = await run(["auth", "revoke"])
    }

    static func search(_ term: String, limit: Int = 25) async throws -> [StoreApp] {
        let r = await run(["search", term, "--limit", "\(limit)", "--format", "json", "--non-interactive"])
        guard let j = r.json else {
            if r.message.isEmpty { return [] }
            throw ToolError(message: friendly(r.message))
        }
        let apps = j["apps"] as? [[String: Any]] ?? []
        return apps.compactMap { a in
            guard let id = a["id"].map({ "\($0)" }) else { return nil }
            return StoreApp(id: id, name: a["name"] as? String ?? id,
                            bundleID: a["bundleID"] as? String ?? "",
                            version: a["version"] as? String ?? "",
                            price: a["price"] as? Double)
        }
    }

    static func purchase(_ id: String) async throws {
        let r = await run(["purchase", "-i", id])
        let msg = r.message
        if !r.ok || msg.range(of: "error", options: .caseInsensitive) != nil {
            // Уже купленное приложение ipatool считает ошибкой лицензии — для нас это успех.
            if msg.localizedCaseInsensitiveContains("already") { return }
            throw ToolError(message: friendly(msg))
        }
    }

    /// ID версий, от старых к новым.
    static func versions(_ id: String) async throws -> [String] {
        let r = await run(["list-versions", "-i", id, "--purchase", "--format", "json"])
        guard let j = r.json, let ids = j["externalVersionIdentifiers"] as? [String] else {
            throw ToolError(message: friendly(r.message.isEmpty ? "Версии приложения не найдены." : r.message))
        }
        return ids
    }

    /// Есть ли у аккаунта лицензия: без --purchase Apple отдаёт версии
    /// только купленного приложения.
    static func owns(_ id: String) async -> Bool {
        let r = await run(["list-versions", "-i", id, "--format", "json"])
        return (r.json?["externalVersionIdentifiers"] as? [String])?.isEmpty == false
    }

    static func download(_ id: String, version: String?, to output: URL, process: ProcessBox,
                         progress: @escaping @Sendable (Double) -> Void) async throws {
        var args = ["download", "-i", id, "-o", output.path]
        if let version { args += ["--external-version-id", version] } else { args.append("--purchase") }
        let r = await run(args, process: process) { line in
            if line.hasPrefix("PROGRESS:"), let v = Double(line.dropFirst(9)) { progress(v / 100) }
        }
        if process.isCancelled { throw CancellationError() }
        guard r.ok, FileManager.default.fileExists(atPath: output.path) else {
            throw ToolError(message: friendly(r.message.isEmpty ? "ipatool завершился с кодом \(r.code)" : r.message))
        }
    }

    /// Переводит самые частые ответы ipatool на человеческий язык.
    static func friendly(_ msg: String) -> String {
        let table: [(String, String)] = [
            ("you must purchase this app first", "Приложение не приобретено этим аккаунтом."),
            ("Not logged in", "Нет входа в аккаунт Apple."),
            ("account is disabled", "Apple отклонил вход: неверная почта или пароль, либо аккаунт заблокирован."),
            ("2FA code rejected", "Код двухфакторной аутентификации не подошёл."),
            ("Session expired", "Сессия истекла — войдите в аккаунт заново."),
            ("password token is expired", "Сессия истекла — войдите в аккаунт заново."),
            ("license not found", "Нет лицензии на приложение — сначала получите его."),
        ]
        for (needle, text) in table where msg.localizedCaseInsensitiveContains(needle) {
            return text
        }
        return msg.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
