import Foundation
import LimitsBarCore

// `LimitsBar --dump` prints the normalized snapshots as JSON and exits, without starting the UI.
if CommandLine.arguments.contains("--dump") {
    let snapshots = await withTaskGroup(of: ProviderSnapshot.self) { group in
        let config = Config.load().0
        for p in Providers.all(config: config) where config.isEnabled(p.id) {
            group.addTask { await p.fetch() }
        }
        var out: [ProviderSnapshot] = []
        for await s in group { out.append(s) }
        let order = config.allProviderIDs
        return out.sorted { (order.firstIndex(of: $0.provider) ?? 0) < (order.firstIndex(of: $1.provider) ?? 0) }
    }
    let enc = JSONEncoder()
    enc.outputFormatting = [.prettyPrinted, .sortedKeys]
    enc.dateEncodingStrategy = .iso8601
    FileHandle.standardOutput.write(try enc.encode(snapshots))
    FileHandle.standardOutput.write(Data("\n".utf8))
    exit(0)
}

// `LimitsBar --snapshot out.png` renders the panel with live data to a PNG (for checking layout).
if let i = CommandLine.arguments.firstIndex(of: "--snapshot"), i + 1 < CommandLine.arguments.count {
    await Snapshot.write(to: URL(fileURLWithPath: CommandLine.arguments[i + 1]))
    exit(0)
}

LimitsBarApp.main()
