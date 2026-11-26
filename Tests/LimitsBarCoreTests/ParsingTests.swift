import Foundation
import Testing
@testable import LimitsBarCore

// All fixtures are synthetic and shaped after the real responses.

private func json(_ s: String) throws -> [String: Any] {
    try JSONObject.parse(Data(s.utf8))
}

@Suite struct ClaudeParsing {
    @Test func prefersLimitsList() throws {
        let j = try json("""
        {"five_hour":{"utilization":40.0,"resets_at":"2030-01-01T05:00:00.123+00:00"},
         "limits":[
          {"kind":"session","percent":18,"resets_at":"2030-01-01T05:00:00.123456+00:00","scope":null},
          {"kind":"weekly_all","percent":3,"resets_at":"2030-01-05T07:00:00+00:00","scope":null},
          {"kind":"weekly_scoped","percent":50,"resets_at":"2030-01-05T07:00:00+00:00",
           "scope":{"model":{"id":null,"display_name":"Opus"},"surface":null}}]}
        """)
        let w = ClaudeProvider.parse(j)
        #expect(w.map(\.label) == ["5h", "Week", "Week · Opus"])
        #expect(w.map(\.remainingPercent) == [82, 97, 50])
        #expect(w[0].resetsAt != nil)
    }

    @Test func fallsBackToNamedWindows() throws {
        let j = try json("""
        {"five_hour":{"utilization":25.5,"resets_at":"2030-01-01T05:00:00+00:00"},
         "seven_day":{"utilization":10,"resets_at":"2030-01-05T07:00:00+00:00"},
         "seven_day_opus":null}
        """)
        let w = ClaudeProvider.parse(j)
        #expect(w.map(\.label) == ["5h", "Week"])
        #expect(w[0].remainingPercent == 74.5)
    }

    @Test func credentials() throws {
        let c = try ClaudeProvider.parseCredentials(Data("""
        {"claudeAiOauth":{"accessToken":"tok","expiresAt":1893456000000,
          "subscriptionType":"pro","rateLimitTier":"default_claude_max_20x"}}
        """.utf8))
        #expect(c.accessToken == "tok")
        #expect(c.plan == "Pro · Max 20x")
        #expect(c.expiresAt == Date(timeIntervalSince1970: 1_893_456_000))
    }

    @Test func missingOAuthIsNotConfigured() {
        #expect(throws: ProviderError.self) {
            try ClaudeProvider.parseCredentials(Data(#"{"other":{}}"#.utf8))
        }
    }
}

@Suite struct CodexParsing {
    @Test func windows() throws {
        let j = try json("""
        {"plan_type":"plus","rate_limit":{
          "primary_window":{"used_percent":25,"limit_window_seconds":18000,"reset_at":1893456000},
          "secondary_window":{"used_percent":88,"limit_window_seconds":604800,"reset_at":1893800000}}}
        """)
        let s = CodexProvider.parse(j)
        #expect(s.plan == "Plus")
        #expect(s.windows.map(\.label) == ["5h", "Week"])
        #expect(s.windows.map(\.remainingPercent) == [75, 12])
        #expect(s.minRemaining == 12)
    }

    @Test func nullSecondary() throws {
        let j = try json(#"{"rate_limit":{"primary_window":{"used_percent":5,"limit_window_seconds":18000},"secondary_window":null}}"#)
        #expect(CodexProvider.parse(j).windows.count == 1)
    }
}

@Suite struct MuseParsing {
    @Test func allowance() throws {
        let j = try json("""
        {"schemaVersion":1,"allowance":{"tier":"Muse Code Power Usage",
          "window":{"usedPercent":9,"resetsAtMs":1893456000000},
          "weekly":{"usedPercent":56,"resetsAtMs":1893800000000}},"reason":null}
        """)
        let s = try MuseProvider.parse(j)
        #expect(s.plan == "Power Usage")
        #expect(s.windows.map(\.remainingPercent) == [91, 44])
        #expect(s.windows[0].resetsAt == Date(timeIntervalSince1970: 1_893_456_000))
    }

    @Test func reasonWithoutAllowance() throws {
        let j = try json(#"{"schemaVersion":1,"allowance":null,"reason":"not signed in"}"#)
        #expect(throws: ProviderError.self) { try MuseProvider.parse(j) }
    }
}

@Suite struct DevinParsing {
    @Test func remainingIsNotInverted() throws {
        let j = try json("""
        {"userStatus":{"planStatus":{"planInfo":{"planName":"Pro"},
          "dailyQuotaRemainingPercent":70,"weeklyQuotaRemainingPercent":35,
          "dailyQuotaResetAtUnix":"1893456000","weeklyQuotaResetAtUnix":"1893800000"}}}
        """)
        let s = DevinProvider.parse(j)
        #expect(s.plan == "Pro")
        #expect(s.windows.map(\.label) == ["Day", "Week"])
        #expect(s.windows.map(\.remainingPercent) == [70, 35])
        #expect(s.windows[1].resetsAt == Date(timeIntervalSince1970: 1_893_800_000))
    }

    @Test func toml() {
        let t = DevinProvider.parseTOML("""
        windsurf_api_key = "abc=def"
        api_server_url = "https://example.invalid/"
        """)
        #expect(t["windsurf_api_key"] == "abc=def")
        #expect(t["api_server_url"] == "https://example.invalid/")
    }
}

@Suite struct Normalization {
    @Test func clamps() {
        #expect(UsageWindow.fromUsed(label: "x", usedPercent: 120, resetsAt: nil).remainingPercent == 0)
        #expect(UsageWindow(label: "x", remainingPercent: -5, resetsAt: nil).remainingPercent == 0)
    }

    @Test func codexWindowLabels() {
        #expect(CodexProvider.windowLabel(18_000) == "5h")
        #expect(CodexProvider.windowLabel(604_800) == "Week")
        #expect(CodexProvider.windowLabel(86_400) == "Day")
        #expect(CodexProvider.windowLabel(1_800) == "30m")
    }

    @Test func statusEncodesFlat() throws {
        let data = try JSONEncoder().encode(ProviderStatus.stale("expired"))
        let obj = try JSONObject.parse(data)
        #expect(obj["state"] as? String == "stale")
        #expect(obj["message"] as? String == "expired")
    }
}

@Suite struct ConfigTests {
    @Test func emptyAndPartialFiles() throws {
        let c = try JSONDecoder().decode(Config.self, from: Data("{}".utf8))
        #expect(c.custom.isEmpty)
        #expect(c.isEnabled(.claude))

        let d = try JSONDecoder().decode(Config.self, from: Data(#"{"disabled":["devin"],"menuBar":"numbers"}"#.utf8))
        #expect(!d.isEnabled(.devin))
        #expect(d.isEnabled(.muse))
        #expect(d.menuBar == "numbers")
    }

    @Test func customProviderIDs() throws {
        let c = try JSONDecoder().decode(Config.self, from: Data("""
        {"custom":[{"id":"gem","name":"gemini","command":["gem-quota"]},
                   {"id":"or","name":"OpenRouter","tag":"OR","command":["x"]}]}
        """.utf8))
        #expect(c.allProviderIDs.map(\.id) == ["claude", "codex", "muse", "devin", "gem", "or"])
        #expect(c.custom[0].providerID.shortTag == "G")
        #expect(c.custom[1].providerID.shortTag == "OR")
    }

    @Test func roundTripsThroughFile() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString).appendingPathComponent("config.json")
        let c = Config(menuBar: "numbers", disabled: ["codex"],
                       custom: [.init(id: "e", name: "Example", command: ["~/bin/e"], timeout: 5)])
        try c.save(to: url)
        let (loaded, err) = Config.load(from: url)
        #expect(err == nil)
        #expect(loaded == c)
    }

    @Test func brokenFileIsReported() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".json")
        try Data("{not json".utf8).write(to: url)
        let (c, err) = Config.load(from: url)
        #expect(err != nil)
        #expect(c == Config())
    }
}

@Suite struct CommandProviderTests {
    let id = ProviderID(id: "e", displayName: "Example", shortTag: "E")

    @Test func remainingAndUsed() throws {
        let j = try json("""
        {"plan":"Demo","windows":[
          {"label":"Day","remainingPercent":64,"resetsAt":"2030-01-01T00:00:00Z"},
          {"label":"Week","usedPercent":30,"resetsAt":1893456000},
          {"label":"Junk"}]}
        """)
        let s = try CommandProvider.parse(j, id: id)
        #expect(s.plan == "Demo")
        #expect(s.windows.map(\.remainingPercent) == [64, 70])
        #expect(s.windows[1].resetsAt == Date(timeIntervalSince1970: 1_893_456_000))
        #expect(s.windows[0].resetsAt != nil)
    }

    @Test func errorField() throws {
        #expect(throws: ProviderError.self) { try CommandProvider.parse(try json(#"{"error":"quota api down"}"#), id: id) }
    }

    @Test func runsExampleScript() async throws {
        let script = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("examples/custom-provider.sh")
        let p = CommandProvider(.init(id: "e", name: "Example", command: [script.path]))
        let s = await p.fetch()
        #expect(s.status == .ok)
        #expect(s.windows.map(\.remainingPercent) == [64, 70])
    }

    @Test func missingCommandIsNotConfigured() async {
        let p = CommandProvider(.init(id: "e", name: "Example", command: ["/nonexistent/quota"]))
        let s = await p.fetch()
        if case .notConfigured = s.status {} else { Issue.record("expected notConfigured, got \(s.status)") }
    }
}

@Suite struct AlertPlannerTests {
    func snap(_ remaining: Double, label: String = "Week", status: ProviderStatus = .ok) -> [ProviderSnapshot] {
        [ProviderSnapshot(provider: .codex, windows: [UsageWindow(label: label, remainingPercent: remaining, resetsAt: nil)],
                          status: status)]
    }

    @Test func firesOncePerCrossingAndRearms() {
        let a = Config.Alerts(thresholds: [20, 5])
        var r = AlertPlanner.plan(snapshots: snap(50), alerts: a, fired: [])
        #expect(r.alerts.isEmpty)
        r = AlertPlanner.plan(snapshots: snap(18), alerts: a, fired: r.fired)
        #expect(r.alerts.map(\.threshold) == [20])
        r = AlertPlanner.plan(snapshots: snap(15), alerts: a, fired: r.fired)
        #expect(r.alerts.isEmpty)
        r = AlertPlanner.plan(snapshots: snap(4), alerts: a, fired: r.fired)
        #expect(r.alerts.map(\.threshold) == [5])
        // Window resets: both thresholds re-arm.
        r = AlertPlanner.plan(snapshots: snap(100), alerts: a, fired: r.fired)
        #expect(r.fired.isEmpty)
        r = AlertPlanner.plan(snapshots: snap(19), alerts: a, fired: r.fired)
        #expect(r.alerts.map(\.threshold) == [20])
    }

    @Test func bigDropSendsOnlyLowest() {
        let r = AlertPlanner.plan(snapshots: snap(3), alerts: Config.Alerts(thresholds: [20, 5]), fired: [])
        #expect(r.alerts.map(\.threshold) == [5])
        #expect(r.fired.count == 2)
    }

    @Test func mutedAndDisabledStaySilentButTrack() {
        let muted = AlertPlanner.plan(snapshots: snap(3), alerts: Config.Alerts(muted: ["codex/Week"]), fired: [])
        #expect(muted.alerts.isEmpty)
        #expect(!muted.fired.isEmpty)
        let off = AlertPlanner.plan(snapshots: snap(3), alerts: Config.Alerts(enabled: false), fired: [])
        #expect(off.alerts.isEmpty)
        // Turning alerts back on later doesn't replay an old crossing.
        let on = AlertPlanner.plan(snapshots: snap(3), alerts: Config.Alerts(), fired: off.fired)
        #expect(on.alerts.isEmpty)
    }

    @Test func staleDataIsIgnored() {
        let r = AlertPlanner.plan(snapshots: snap(3, status: .stale("expired")), alerts: Config.Alerts(), fired: [])
        #expect(r.alerts.isEmpty)
        #expect(r.fired.isEmpty)
    }

    @Test func defaultsAndMuteKey() {
        #expect(Config.Alerts().effectiveThresholds == [20, 5])
        #expect(AlertPlanner.muteKey(.claude, UsageWindow(label: "5h", remainingPercent: 1, resetsAt: nil)) == "claude/5h")
    }
}
