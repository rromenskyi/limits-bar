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
    /// ("codex/Week") are built from them. Each " · " part is translated if a translation exists
    /// ("Week · Opus" -> "Неделя · Opus"); generated durations like "2h" or "30m" are formatted.
    public static func display(_ label: String) -> String {
        label.components(separatedBy: " · ").map(part).joined(separator: " · ")
    }

    static func part(_ s: String) -> String {
        if s.count > 1, let n = Int(s.dropLast()) {
            if s.hasSuffix("h"), s != "5h" { return Lf("%dh", n) }
            if s.hasSuffix("m") { return Lf("%dm", n) }
        }
        return L(s)
    }
}
