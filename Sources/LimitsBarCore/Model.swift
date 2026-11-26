import Foundation

/// One rate-limit window, normalized to "how much is left".
public struct UsageWindow: Sendable, Equatable, Codable {
    /// Short label shown in the UI, e.g. "5h", "Week", "Day".
    public var label: String
    /// Remaining allowance, 0...100.
    public var remainingPercent: Double
    /// When the window resets, if the source reports it.
    public var resetsAt: Date?

    public init(label: String, remainingPercent: Double, resetsAt: Date?) {
        self.label = label
        self.remainingPercent = min(100, max(0, remainingPercent))
        self.resetsAt = resetsAt
    }

    public static func fromUsed(label: String, usedPercent: Double, resetsAt: Date?) -> UsageWindow {
        UsageWindow(label: label, remainingPercent: 100 - usedPercent, resetsAt: resetsAt)
    }
}

/// Identifies a provider. Built-ins have fixed ids; custom providers come from the config file.
public struct ProviderID: Hashable, Sendable, Encodable {
    public let id: String
    public let displayName: String
    /// One-letter tag for the menu bar.
    public let shortTag: String

    public init(id: String, displayName: String, shortTag: String) {
        self.id = id
        self.displayName = displayName
        self.shortTag = shortTag
    }

    public static let claude = ProviderID(id: "claude", displayName: "Claude", shortTag: "C")
    public static let codex = ProviderID(id: "codex", displayName: "Codex", shortTag: "X")
    public static let muse = ProviderID(id: "muse", displayName: "Muse", shortTag: "M")
    public static let devin = ProviderID(id: "devin", displayName: "Devin", shortTag: "D")
    public static let builtIns: [ProviderID] = [.claude, .codex, .muse, .devin]

    public func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        try c.encode(id)
    }
}

public enum ProviderStatus: Sendable, Equatable {
    case ok
    /// Credentials exist but are expired or rejected; the vendor CLI will refresh them on next use.
    case stale(String)
    /// The CLI or its credentials are not present on this machine.
    case notConfigured(String)
    case error(String)

    public var message: String? {
        switch self {
        case .ok: nil
        case .stale(let m), .notConfigured(let m), .error(let m): m
        }
    }
}

extension ProviderStatus: Codable {
    private enum CodingKeys: String, CodingKey { case state, message }

    public var state: String {
        switch self {
        case .ok: "ok"
        case .stale: "stale"
        case .notConfigured: "notConfigured"
        case .error: "error"
        }
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(state, forKey: .state)
        try c.encodeIfPresent(message, forKey: .message)
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let m = try c.decodeIfPresent(String.self, forKey: .message) ?? ""
        switch try c.decode(String.self, forKey: .state) {
        case "ok": self = .ok
        case "stale": self = .stale(m)
        case "notConfigured": self = .notConfigured(m)
        default: self = .error(m)
        }
    }
}

public struct ProviderSnapshot: Sendable, Equatable, Encodable {
    public var provider: ProviderID
    public var plan: String?
    public var windows: [UsageWindow]
    public var status: ProviderStatus
    public var fetchedAt: Date

    public init(provider: ProviderID, plan: String? = nil, windows: [UsageWindow] = [],
                status: ProviderStatus = .ok, fetchedAt: Date = Date()) {
        self.provider = provider
        self.plan = plan
        self.windows = windows
        self.status = status
        self.fetchedAt = fetchedAt
    }

    /// The tightest window, which is what actually limits you right now.
    public var minRemaining: Double? {
        windows.map(\.remainingPercent).min()
    }
}

public protocol UsageProvider: Sendable {
    var id: ProviderID { get }
    func fetch() async -> ProviderSnapshot
}

public enum ProviderError: Error, CustomStringConvertible {
    case notConfigured(String)
    case stale(String)
    case failed(String)

    public var description: String {
        switch self {
        case .notConfigured(let m), .stale(let m), .failed(let m): m
        }
    }
}

extension UsageProvider {
    /// Runs `body` and maps thrown errors to a snapshot status, so one provider never takes down the others.
    func snapshot(_ body: () async throws -> ProviderSnapshot) async -> ProviderSnapshot {
        do {
            return try await body()
        } catch let e as ProviderError {
            switch e {
            case .notConfigured(let m): return ProviderSnapshot(provider: id, status: .notConfigured(m))
            case .stale(let m): return ProviderSnapshot(provider: id, status: .stale(m))
            case .failed(let m): return ProviderSnapshot(provider: id, status: .error(m))
            }
        } catch {
            return ProviderSnapshot(provider: id, status: .error(error.localizedDescription))
        }
    }
}

public enum Providers {
    public static func builtIns() -> [any UsageProvider] {
        [ClaudeProvider(), CodexProvider(), MuseProvider(), DevinProvider()]
    }

    /// Built-ins plus custom command providers from the config, in display order.
    public static func all(config: Config) -> [any UsageProvider] {
        builtIns() + config.custom.map(CommandProvider.init)
    }
}
