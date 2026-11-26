import Foundation

/// User configuration, stored as JSON at `~/.config/limits-bar/config.json`
/// (or `$XDG_CONFIG_HOME/limits-bar/config.json`). Every field is optional.
///
///     {
///       "menuBar": "bars",
///       "disabled": ["devin"],
///       "custom": [
///         { "id": "gemini", "name": "Gemini", "tag": "G",
///           "command": ["~/bin/gemini-quota"], "timeout": 30 }
///       ]
///     }
public struct Config: Codable, Equatable, Sendable {
    /// "bars" (default) or "numbers".
    public var menuBar: String?
    /// Provider ids to hide. Providers whose CLI isn't installed are hidden automatically.
    public var disabled: [String]?
    /// Extra providers backed by a command that prints usage JSON.
    public var custom: [CustomProvider]

    public init(menuBar: String? = nil, disabled: [String]? = nil, custom: [CustomProvider] = []) {
        self.menuBar = menuBar
        self.disabled = disabled
        self.custom = custom
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        menuBar = try c.decodeIfPresent(String.self, forKey: .menuBar)
        disabled = try c.decodeIfPresent([String].self, forKey: .disabled)
        custom = try c.decodeIfPresent([CustomProvider].self, forKey: .custom) ?? []
    }

    public struct CustomProvider: Codable, Equatable, Sendable {
        public var id: String
        public var name: String
        /// Menu bar letter; defaults to the first letter of `name`.
        public var tag: String?
        /// Program and arguments. `~` is expanded; a bare name is looked up on PATH.
        public var command: [String]
        public var timeout: Double?

        public init(id: String, name: String, tag: String? = nil, command: [String], timeout: Double? = nil) {
            self.id = id
            self.name = name
            self.tag = tag
            self.command = command
            self.timeout = timeout
        }

        public var providerID: ProviderID {
            ProviderID(id: id, displayName: name,
                       shortTag: tag.flatMap { $0.isEmpty ? nil : String($0.prefix(2)) } ?? String(name.prefix(1)).uppercased())
        }
    }

    public func isEnabled(_ id: ProviderID) -> Bool {
        !(disabled ?? []).contains(id.id)
    }

    public var allProviderIDs: [ProviderID] {
        ProviderID.builtIns + custom.map(\.providerID)
    }

    // MARK: - File

    public static var fileURL: URL {
        (Env.value("XDG_CONFIG_HOME").map { URL(fileURLWithPath: $0) }
            ?? Env.home.appendingPathComponent(".config"))
            .appendingPathComponent("limits-bar/config.json")
    }

    /// Loads the config. A missing file is an empty config; a broken file is reported, not overwritten.
    public static func load(from url: URL = fileURL) -> (Config, String?) {
        guard let data = try? Data(contentsOf: url) else { return (Config(), nil) }
        do {
            return (try JSONDecoder().decode(Config.self, from: data), nil)
        } catch {
            return (Config(), "config.json could not be read: \(error.localizedDescription)")
        }
    }

    public func save(to url: URL = fileURL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        try enc.encode(self).write(to: url, options: .atomic)
    }
}
