import Foundation

struct AppError: LocalizedError {
    let message: String
    init(_ message: String) { self.message = message }
    var errorDescription: String? { message }
}

/// 运行命令行工具。标准输出原样返回，失败时把标准错误放进错误信息。
nonisolated enum Shell {
    struct Failure: LocalizedError {
        let tool: String
        let status: Int32
        let output: String
        var errorDescription: String? {
            let detail = output.trimmingCharacters(in: .whitespacesAndNewlines)
            return "\(tool) 失败（\(status)）" + (detail.isEmpty ? "" : "：\(detail)")
        }
    }

    private final class Buffer: @unchecked Sendable { var data = Data() }

    @discardableResult
    static func run(_ tool: String, _ arguments: [String], environment: [String: String] = [:]) async throws -> Data {
        try await Task.detached { try execute(tool, arguments, environment: environment) }.value
    }

    private static func execute(_ tool: String, _ arguments: [String], environment: [String: String]) throws -> Data {
        let process = Process()
        process.executableURL = URL(filePath: tool)
        process.arguments = arguments
        process.environment = ProcessInfo.processInfo.environment.merging(environment) { $1 }
        process.standardInput = FileHandle.nullDevice
        let output = Pipe()
        let errors = Pipe()
        process.standardOutput = output
        process.standardError = errors
        try process.run()
        // 两个管道分开读，避免其中一个写满后进程卡住。
        let stderr = Buffer()
        let group = DispatchGroup()
        group.enter()
        DispatchQueue.global().async {
            stderr.data = errors.fileHandleForReading.readDataToEndOfFile()
            group.leave()
        }
        let stdout = output.fileHandleForReading.readDataToEndOfFile()
        group.wait()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            let text = String(decoding: stderr.data.isEmpty ? stdout : stderr.data, as: UTF8.self)
            throw Failure(tool: URL(filePath: tool).lastPathComponent, status: process.terminationStatus, output: text)
        }
        return stdout
    }

    static func text(_ tool: String, _ arguments: [String], environment: [String: String] = [:]) async throws -> String {
        String(decoding: try await run(tool, arguments, environment: environment), as: UTF8.self)
    }
}

/// Homebrew 的 OpenSSL 3。系统自带的 LibreSSL 读不了新格式的 .p12。
nonisolated enum OpenSSL {
    static let passwordVariable = "IPA_INSTALLER_P12_PASSWORD"

    static func executable() throws -> String {
        let candidates = ["/opt/homebrew/opt/openssl@3/bin/openssl", "/usr/local/opt/openssl@3/bin/openssl"]
        guard let path = candidates.first(where: FileManager.default.isExecutableFile(atPath:)) else {
            throw AppError("需要 OpenSSL 3。请在终端运行：brew install openssl@3")
        }
        return path
    }

    /// 用密码解开 .p12。传入 `pem` 时把证书和私钥写到那里，否则只检查密码。
    /// OpenSSL 3 默认不读 RC2 等旧算法，失败时再加 -legacy 试一次。
    static func unpack(_ p12: URL, password: String, to pem: URL? = nil) async throws {
        let tool = try executable()
        let arguments = ["pkcs12", "-in", p12.path, "-nodes", "-passin", "env:\(passwordVariable)"]
            + (pem.map { ["-out", $0.path] } ?? ["-noout"])
        let environment = [passwordVariable: password]
        do {
            try await Shell.run(tool, arguments, environment: environment)
        } catch {
            do { try await Shell.run(tool, arguments + ["-legacy"], environment: environment) }
            catch { throw AppError("证书密码不对，或证书格式无法读取。") }
        }
    }

    /// 重新导出为旧格式（3DES / RC2），macOS 钥匙串只认这种。
    static func exportLegacy(_ pem: URL, to p12: URL, password: String) async throws {
        try await Shell.run(try executable(),
                            ["pkcs12", "-export", "-legacy", "-in", pem.path, "-out", p12.path, "-passout", "env:\(passwordVariable)"],
                            environment: [passwordVariable: password])
    }
}
