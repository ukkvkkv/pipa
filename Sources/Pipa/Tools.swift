import Foundation

/// Результат запуска внешней программы.
struct ToolResult {
    var code: Int32
    var stdout: String
    var stderr: String

    var ok: Bool { code == 0 }

    /// Весь вывод без ANSI-кодов, строк прогресса и меток времени ipatool.
    var message: String {
        let text = (stdout + "\n" + stderr)
            .replacingOccurrences(of: "\u{1B}\\[[0-9;]*[a-zA-Z]", with: "", options: .regularExpression)
        return text
            .split(separator: "\n")
            .map { String($0).trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty && !$0.hasPrefix("PROGRESS:") }
            .map { $0.replacingOccurrences(of: "^\\d{2}:\\d{2}:\\d{2} [A-Z]{3} ", with: "", options: .regularExpression) }
            .joined(separator: "\n")
    }

    var json: [String: Any]? {
        for line in stdout.split(separator: "\n").reversed() {
            let s = line.trimmingCharacters(in: .whitespaces)
            guard s.hasPrefix("{"), let data = s.data(using: .utf8) else { continue }
            if let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] { return obj }
        }
        return nil
    }
}

struct ToolError: LocalizedError {
    var message: String
    var errorDescription: String? { message }
}

/// Пути к вшитым в .app программам. В отладочном запуске (swift run) — к
/// vendor/ рядом с исходниками и Homebrew.
enum Tools {
    static var helpers: URL {
        Bundle.main.bundleURL.appendingPathComponent("Contents/Helpers")
    }

    static var ipatool: URL {
        let bundled = helpers.appendingPathComponent("ipatool")
        if FileManager.default.isExecutableFile(atPath: bundled.path) { return bundled }
        let arch = ProcessInfo.processInfo.machineArch == "arm64" ? "arm64" : "amd64"
        return URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("vendor/ipatool/ipatool-cpp-macOS-\(arch)")
    }

    static func idevice(_ name: String) -> URL? {
        let candidates = [
            helpers.appendingPathComponent(name).path,
            "/opt/homebrew/bin/\(name)",
            "/usr/local/bin/\(name)",
        ]
        return candidates.first { FileManager.default.isExecutableFile(atPath: $0) }.map(URL.init(fileURLWithPath:))
    }

    /// Запускает программу и ждёт завершения. `onStderrLine` получает строки
    /// stderr по мере появления (для прогресса загрузки).
    static func run(
        _ exe: URL,
        _ args: [String],
        process: ProcessBox? = nil,
        onStderrLine: (@Sendable (String) -> Void)? = nil
    ) async -> ToolResult {
        await withCheckedContinuation { cont in
            let p = Process()
            p.executableURL = exe
            p.arguments = args
            p.standardInput = FileHandle.nullDevice
            p.currentDirectoryURL = FileManager.default.temporaryDirectory
            let outPipe = Pipe(), errPipe = Pipe()
            p.standardOutput = outPipe
            p.standardError = errPipe

            let buffers = OutputBuffers()
            outPipe.fileHandleForReading.readabilityHandler = { h in
                let d = h.availableData
                if !d.isEmpty { buffers.appendOut(d) }
            }
            errPipe.fileHandleForReading.readabilityHandler = { h in
                let d = h.availableData
                guard !d.isEmpty else { return }
                for line in buffers.appendErr(d) { onStderrLine?(line) }
            }
            p.terminationHandler = { proc in
                outPipe.fileHandleForReading.readabilityHandler = nil
                errPipe.fileHandleForReading.readabilityHandler = nil
                buffers.appendOut(outPipe.fileHandleForReading.readDataToEndOfFile())
                _ = buffers.appendErr(errPipe.fileHandleForReading.readDataToEndOfFile())
                cont.resume(returning: ToolResult(code: proc.terminationStatus, stdout: buffers.out, stderr: buffers.err))
            }
            do {
                try p.run()
                process?.set(p)
            } catch {
                cont.resume(returning: ToolResult(code: -1, stdout: "", stderr: error.localizedDescription))
            }
        }
    }
}

/// Ссылка на запущенный процесс, чтобы его можно было отменить.
final class ProcessBox: @unchecked Sendable {
    private let lock = NSLock()
    private var process: Process?
    private var cancelled = false

    func set(_ p: Process) {
        lock.lock(); defer { lock.unlock() }
        process = p
        if cancelled { p.terminate() }
    }

    func cancel() {
        lock.lock(); defer { lock.unlock() }
        cancelled = true
        process?.terminate()
    }

    var isCancelled: Bool {
        lock.lock(); defer { lock.unlock() }
        return cancelled
    }
}

private final class OutputBuffers: @unchecked Sendable {
    private let lock = NSLock()
    private var outData = Data()
    private var errData = Data()
    private var errLine = Data()

    func appendOut(_ d: Data) {
        lock.lock(); outData.append(d); lock.unlock()
    }

    /// Возвращает завершённые строки stderr.
    func appendErr(_ d: Data) -> [String] {
        lock.lock(); defer { lock.unlock() }
        errData.append(d)
        errLine.append(d)
        var lines: [String] = []
        while let nl = errLine.firstIndex(of: 0x0A) {
            lines.append(String(decoding: errLine[errLine.startIndex..<nl], as: UTF8.self))
            errLine.removeSubrange(errLine.startIndex...nl)
        }
        return lines
    }

    var out: String { lock.lock(); defer { lock.unlock() }; return String(decoding: outData, as: UTF8.self) }
    var err: String { lock.lock(); defer { lock.unlock() }; return String(decoding: errData, as: UTF8.self) }
}

extension ProcessInfo {
    var machineArch: String {
        var info = utsname()
        uname(&info)
        return withUnsafeBytes(of: &info.machine) { buf in
            String(decoding: buf.prefix { $0 != 0 }, as: UTF8.self)
        }
    }
}
