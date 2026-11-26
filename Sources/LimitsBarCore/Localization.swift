import Foundation

/// Looks up a user-facing string in the app bundle's Localizable.strings; the English text is the key.
public func L(_ key: String) -> String {
    Bundle.main.localizedString(forKey: key, value: key, table: nil)
}

/// Localized format string with arguments, e.g. `Lf("%d%% left", 42)`.
public func Lf(_ key: String, _ args: CVarArg...) -> String {
    String(format: L(key), locale: .current, arguments: args)
}

public enum WindowLabel {
    /// Translates a window label for display. Labels stay English internally because mute keys
    /// ("codex/Week") are built from them. "Week · Opus" translates the part before the dot.
    public static func display(_ label: String) -> String {
        let parts = label.components(separatedBy: " · ")
        guard let head = parts.first else { return label }
        return ([L(head)] + parts.dropFirst()).joined(separator: " · ")
    }
}
