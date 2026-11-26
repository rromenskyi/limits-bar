import Foundation
import Testing

/// Every string the code looks up must exist in every language, with the same format specifiers.
@Suite struct LocalizationTests {
    static let root = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()

    /// Keys passed indirectly (ternaries, enum titles, window label heads).
    static let indirectKeys = ["Checking…", "No supported CLIs found", "Bars", "Numbers", "5h", "Week", "Day", "Window"]
    /// Pass-through formats that need no translation.
    static let ignored: Set<String> = ["Muse: %@"]

    static func usedKeys() throws -> Set<String> {
        var keys = Set(indirectKeys)
        let regex = try NSRegularExpression(pattern: #"\bLf?\("((?:[^"\\]|\\.)*)""#)
        let files = FileManager.default.enumerator(at: root.appendingPathComponent("Sources"), includingPropertiesForKeys: nil)!
        for case let url as URL in files where url.pathExtension == "swift" {
            let text = try String(contentsOf: url, encoding: .utf8)
            for m in regex.matches(in: text, range: NSRange(text.startIndex..., in: text)) {
                let key = String(text[Range(m.range(at: 1), in: text)!]).replacingOccurrences(of: "\\\"", with: "\"")
                keys.insert(key)
            }
        }
        return keys.subtracting(ignored)
    }

    static func specifiers(_ s: String) -> [String] {
        let regex = try! NSRegularExpression(pattern: #"%(?:\d\$)?[@d%]"#)
        return regex.matches(in: s, range: NSRange(s.startIndex..., in: s)).map { String(s[Range($0.range, in: s)!]) }
    }

    @Test func everyLanguageHasEveryKey() throws {
        let keys = try Self.usedKeys()
        #expect(keys.count > 40)
        let dir = Self.root.appendingPathComponent("Resources/Localization")
        let langs = try FileManager.default.contentsOfDirectory(atPath: dir.path).filter { $0.hasSuffix(".lproj") }
        #expect(langs.count >= 10)
        for lang in langs {
            let url = dir.appendingPathComponent(lang).appendingPathComponent("Localizable.strings")
            let table = try #require(NSDictionary(contentsOf: url) as? [String: String], "\(lang) does not parse")
            for key in keys {
                let value = try #require(table[key], "\(lang) is missing \"\(key)\"")
                #expect(Self.specifiers(value) == Self.specifiers(key), "\(lang): \"\(key)\" -> \"\(value)\"")
            }
        }
    }
}
