import Foundation

enum Env {
    static var home: URL { FileManager.default.homeDirectoryForCurrentUser }

    static func value(_ key: String) -> String? {
        guard let v = ProcessInfo.processInfo.environment[key], !v.isEmpty else { return nil }
        return v
    }

    /// GUI apps start with a minimal PATH; add the usual places CLIs get installed.
    static var searchPath: [String] {
        let extra = [
            home.appendingPathComponent(".local/bin").path,
            "/opt/homebrew/bin",
            "/usr/local/bin",
            home.appendingPathComponent(".bun/bin").path,
            home.appendingPathComponent(".npm-global/bin").path,
        ]
        let current = (value("PATH") ?? "/usr/bin:/bin:/usr/sbin:/sbin").split(separator: ":").map(String.init)
        var seen = Set<String>()
        return (extra + current).filter { seen.insert($0).inserted }
    }

    static func which(_ name: String) -> URL? {
        for dir in searchPath {
            let url = URL(fileURLWithPath: dir).appendingPathComponent(name)
            if FileManager.default.isExecutableFile(atPath: url.path) { return url }
        }
        return nil
    }
}

struct ShellResult {
    var status: Int32
    var stdout: Data
    var stderr: String
}

enum Shell {
    /// Runs a process with a timeout. Output is drained concurrently so large output can't deadlock the pipe.
    static func run(_ executable: URL, _ args: [String], timeout: TimeInterval = 60) async throws -> ShellResult {
        try await withCheckedThrowingContinuation { cont in
            DispatchQueue.global().async {
                let p = Process()
                p.executableURL = executable
                p.arguments = args
                var env = ProcessInfo.processInfo.environment
                env["PATH"] = Env.searchPath.joined(separator: ":")
                env["NO_COLOR"] = "1"
                p.environment = env
                p.standardInput = FileHandle.nullDevice
                let out = Pipe(), err = Pipe()
                p.standardOutput = out
                p.standardError = err

                let group = DispatchGroup()
                nonisolated(unsafe) var outData = Data()
                nonisolated(unsafe) var errData = Data()
                group.enter()
                DispatchQueue.global().async { outData = out.fileHandleForReading.readDataToEndOfFile(); group.leave() }
                group.enter()
                DispatchQueue.global().async { errData = err.fileHandleForReading.readDataToEndOfFile(); group.leave() }

                do { try p.run() } catch {
                    cont.resume(throwing: ProviderError.failed("Could not run \(executable.lastPathComponent): \(error.localizedDescription)"))
                    return
                }
                let timer = DispatchWorkItem { if p.isRunning { p.terminate() } }
                DispatchQueue.global().asyncAfter(deadline: .now() + timeout, execute: timer)
                p.waitUntilExit()
                timer.cancel()
                group.wait()
                if p.terminationReason == .uncaughtSignal {
                    cont.resume(throwing: ProviderError.failed("\(executable.lastPathComponent) timed out"))
                    return
                }
                cont.resume(returning: ShellResult(status: p.terminationStatus, stdout: outData,
                                                   stderr: String(decoding: errData, as: UTF8.self)))
            }
        }
    }
}

enum HTTP {
    static let session: URLSession = {
        let c = URLSessionConfiguration.ephemeral
        c.timeoutIntervalForRequest = 20
        c.httpCookieStorage = nil
        c.urlCache = nil
        return URLSession(configuration: c)
    }()

    static func json(_ request: URLRequest, provider: String) async throws -> [String: Any] {
        let (data, response) = try await session.data(for: request)
        let code = (response as? HTTPURLResponse)?.statusCode ?? 0
        switch code {
        case 200..<300: break
        case 401, 403: throw ProviderError.stale("\(provider) rejected the token (HTTP \(code)). Use the \(provider) CLI once to refresh it.")
        case 429: throw ProviderError.failed("\(provider) is rate limiting usage checks (HTTP 429)")
        default: throw ProviderError.failed("\(provider) usage request failed (HTTP \(code))")
        }
        return try JSONObject.parse(data)
    }
}

enum JSONObject {
    static func parse(_ data: Data) throws -> [String: Any] {
        guard let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw ProviderError.failed("Unexpected response format")
        }
        return obj
    }
}

enum Num {
    /// Accepts numbers or numeric strings (protobuf JSON encodes int64 as strings).
    static func double(_ v: Any?) -> Double? {
        switch v {
        case let n as NSNumber: n.doubleValue
        case let s as String: Double(s)
        default: nil
        }
    }
}

enum Dates {
    static func iso(_ v: Any?) -> Date? {
        guard let s = v as? String else { return nil }
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = f.date(from: s) { return d }
        f.formatOptions = [.withInternetDateTime]
        return f.date(from: s)
    }

    static func unixSeconds(_ v: Any?) -> Date? {
        guard let s = Num.double(v), s > 0 else { return nil }
        return Date(timeIntervalSince1970: s)
    }

    static func unixMillis(_ v: Any?) -> Date? {
        guard let ms = Num.double(v), ms > 0 else { return nil }
        return Date(timeIntervalSince1970: ms / 1000)
    }
}
