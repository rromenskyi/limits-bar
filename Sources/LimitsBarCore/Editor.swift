import Foundation

/// Picks the app that opens config.json. The system default for .json is often Xcode, which is a
/// heavy way to edit five lines, so a code editor is preferred, then the plain-text editor.
public enum EditorChoice {
    /// Code editors in order of preference, by bundle id.
    public static let codeEditors = [
        "com.microsoft.VSCode",
        "com.todesktop.230313mzl4w4u92",  // Cursor
        "dev.zed.Zed",
        "com.sublimetext.4",
        "com.sublimetext.3",
        "com.barebones.bbedit",
        "com.coteditor.CotEditor",
        "com.panic.Nova",
        "com.macromates.TextMate",
    ]

    /// - Parameters:
    ///   - preferred: the config's `editor` value: a path to an .app, a bundle id, or an app name.
    ///   - appForBundleID: resolves a bundle id to an installed app.
    ///   - appExists: whether an .app exists at a path.
    ///   - plainTextApp: the system's default app for plain text.
    public static func resolve(preferred: String?,
                               appForBundleID: (String) -> URL?,
                               appExists: (String) -> Bool,
                               plainTextApp: URL?,
                               home: URL = FileManager.default.homeDirectoryForCurrentUser) -> URL? {
        if let p = preferred?.trimmingCharacters(in: .whitespaces), !p.isEmpty {
            let expanded = (p as NSString).expandingTildeInPath
            if expanded.hasPrefix("/") {
                if appExists(expanded) { return URL(fileURLWithPath: expanded) }
            } else if let byID = appForBundleID(p) {
                return byID
            } else {
                let name = p.hasSuffix(".app") ? p : p + ".app"
                for dir in ["/Applications", home.appendingPathComponent("Applications").path, "/System/Applications"] {
                    let path = dir + "/" + name
                    if appExists(path) { return URL(fileURLWithPath: path) }
                }
            }
        }
        for id in codeEditors {
            if let url = appForBundleID(id) { return url }
        }
        return plainTextApp
    }
}
