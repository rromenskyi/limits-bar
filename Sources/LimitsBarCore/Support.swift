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
    static let outputCap = 4 << 20

    /// Runs a process with a hard deadline. On timeout it sends SIGTERM, then SIGKILL, and returns
    /// without waiting for pipes a leftover child may still hold open. Output is capped.
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

                let collected = Collected()
                let eof = DispatchGroup()
                for (pipe, isOut) in [(out, true), (err, false)] {
                    eof.enter()
                    pipe.fileHandleForReading.readabilityHandler = { h in
                        let d = h.availableData
                        if d.isEmpty {
                            h.readabilityHandler = nil
                            eof.leave()
                        } else {
                            collected.append(d, toOut: isOut)
                        }
                    }
                }
                let exited = DispatchSemaphore(value: 0)
                p.terminationHandler = { _ in exited.signal() }

                do { try p.run() } catch {
                    out.fileHandleForReading.readabilityHandler = nil
                    err.fileHandleForReading.readabilityHandler = nil
                    cont.resume(throwing: ProviderError.failed(Lf("Could not run %@: %@", executable.lastPathComponent, error.localizedDescription)))
                    return
                }
                var timedOut = false
                if exited.wait(timeout: .now() + timeout) == .timedOut {
                    timedOut = true
                    p.terminate()
                    if exited.wait(timeout: .now() + 2) == .timedOut {
                        kill(p.processIdentifier, SIGKILL)
                        _ = exited.wait(timeout: .now() + 2)
                    }
                }
                // A child that inherited the pipes can keep them open; don't wait for it forever.
                if eof.wait(timeout: .now() + 1) == .timedOut {
                    out.fileHandleForReading.readabilityHandler = nil
                    err.fileHandleForReading.readabilityHandler = nil
                }
                if timedOut {
                    cont.resume(throwing: ProviderError.failed(Lf("%@ timed out", executable.lastPathComponent)))
                    return
                }
                let (o, e) = collected.snapshot()
                cont.resume(returning: ShellResult(status: p.terminationStatus, stdout: o,
                                                   stderr: String(decoding: e, as: UTF8.self)))
            }
        }
    }

    /// Thread-safe output buffers for the two pipes.
    final class Collected: @unchecked Sendable {
        private let lock = NSLock()
        private var out = Data(), err = Data()

        func append(_ d: Data, toOut: Bool) {
            lock.lock(); defer { lock.unlock() }
            if toOut { if out.count < Shell.outputCap { out.append(d) } }
            else if err.count < Shell.outputCap { err.append(d) }
        }

        func snapshot() -> (Data, Data) {
            lock.lock(); defer { lock.unlock() }
            return (out, err)
        }
    }
}

enum HTTP {
    static let session: URLSession = {
        let c = URLSessionConfiguration.ephemeral
        c.timeoutIntervalForRequest = 20
        c.httpCookieStorage = nil
        c.urlCache = nil
        return URLSession(configuration: c, delegate: NoRedirects(), delegateQueue: nil)
    }()

    /// Usage endpoints don't redirect; following one could send a token or key to another host.
    final class NoRedirects: NSObject, URLSessionTaskDelegate, Sendable {
        func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                        newRequest request: URLRequest) async -> URLRequest? { nil }
    }

    /// - Parameters:
    ///   - staleHint: replaces the default "use the CLI once" advice on 401/403.
    ///   - notFound: on 404, report the provider as not configured with this message.
    static func json(_ request: URLRequest, provider: String, staleHint: String? = nil,
                     notFound: String? = nil) async throws -> [String: Any] {
        let (data, response) = try await session.data(for: request)
        let code = (response as? HTTPURLResponse)?.statusCode ?? 0
        switch code {
        case 200..<300: break
        case 404 where notFound != nil: throw ProviderError.notConfigured(notFound!)
        case 401, 403:
            if let staleHint { throw ProviderError.stale(Lf("%@ rejected the token (HTTP %d). %@", provider, code, staleHint)) }
            throw ProviderError.stale(Lf("%@ rejected the token (HTTP %d). Use the %@ CLI once to refresh it.", provider, code, provider))
        case 300..<400: throw ProviderError.failed(Lf("%@ usage request failed (HTTP %d)", provider, code))
        case 429: throw ProviderError.rateLimited(Lf("%@ is rate limiting usage checks (HTTP 429)", provider))
        default: throw ProviderError.failed(Lf("%@ usage request failed (HTTP %d)", provider, code))
        }
        return try JSONObject.parse(data)
    }
}

enum JSONObject {
    static func parse(_ data: Data) throws -> [String: Any] {
        guard let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw ProviderError.failed(L("Unexpected response format"))
        }
        return obj
    }
}

enum Num {
    /// Accepts numbers or numeric strings (protobuf JSON encodes int64 as strings).
    static func double(_ v: Any?) -> Double? {
        switch v {
        case let n as NSNumber:
            // JSON booleans arrive as NSNumber too; `true` must not read as 1%.
            CFGetTypeID(n) == CFBooleanGetTypeID() ? nil : n.doubleValue
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
