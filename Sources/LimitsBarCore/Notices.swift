import Foundation

/// Turns THIRD_PARTY_NOTICES.md into plain text for the About panel.
public enum Notices {
    /// Drops Markdown markup and joins the 80-column hard wraps of license texts back into
    /// paragraphs, so a narrow text view wraps them once. Copyright lines and numbered clauses keep
    /// their own lines.
    public static func plainText(fromMarkdown markdown: String) -> String {
        let lines = markdown.components(separatedBy: "\n").compactMap { raw -> String? in
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.hasPrefix("```") { return "" }
            if line.hasPrefix("# ") { return nil }
            if !line.isEmpty && line.allSatisfy({ $0 == "=" }) { return nil }
            return line.hasPrefix("## ") ? String(line.dropFirst(3)) : line
        }
        var out = ""
        var previous = ""
        for line in lines {
            if line.isEmpty {
                if !out.isEmpty && !out.hasSuffix("\n\n") { out += out.hasSuffix("\n") ? "\n" : "\n\n" }
            } else if previous.isEmpty || previous.hasSuffix(":") || startsOwnLine(line) {
                if !out.isEmpty && !out.hasSuffix("\n") { out += "\n" }
                out += line
            } else {
                out += " " + line
            }
            previous = line
        }
        return out.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func startsOwnLine(_ line: String) -> Bool {
        line.hasPrefix("Copyright") || line.hasPrefix("All rights reserved") || line == "--"
            || line.range(of: #"^\d+\. "#, options: .regularExpression) != nil
    }
}
