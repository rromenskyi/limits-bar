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
        let w = try ClaudeProvider.parse(j)
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
        let w = try ClaudeProvider.parse(j)
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
        let s = try CodexProvider.parse(j)
        #expect(s.plan == "Plus")
        #expect(s.windows.map(\.label) == ["5h", "Week"])
        #expect(s.windows.map(\.remainingPercent) == [75, 12])
        #expect(s.minRemaining == 12)
    }

    @Test func nullSecondary() throws {
        let j = try json(#"{"rate_limit":{"primary_window":{"used_percent":5,"limit_window_seconds":18000},"secondary_window":null}}"#)
        #expect(try CodexProvider.parse(j).windows.count == 1)
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
        let j = try json(#"{"schemaVersion":1,"allowance":null,"reason":"quota service unavailable"}"#)
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
        let s = try DevinProvider.parse(j)
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


@Suite struct ReviewFixes {
    func isNotConfigured(_ body: () throws -> Void) -> Bool {
        do { try body(); return false } catch ProviderError.notConfigured { return true } catch { return false }
    }

    @Test func unknownEnvelopesAreErrorsNotEmptySuccess() throws {
        #expect(throws: ProviderError.self) { try CodexProvider.parse(try json(#"{"error":"temporarily unavailable"}"#)) }
        #expect(throws: ProviderError.self) { try ClaudeProvider.parse(try json(#"{"error":{"type":"overloaded"}}"#)) }
        #expect(throws: ProviderError.self) { try DevinProvider.parse(try json(#"{"code":"unauthenticated"}"#)) }
        // A known envelope with null windows is a real "no limits" answer, not an error.
        #expect(try ClaudeProvider.parse(try json(#"{"five_hour":null,"seven_day":null}"#)).isEmpty)
    }

    @Test func museSignedOutJSONIsNotConfigured() throws {
        let j = try json(#"{"schemaVersion":1,"allowance":null,"reason":"not signed in"}"#)
        #expect(isNotConfigured { _ = try MuseProvider.parse(j) })
    }

    @Test func invalidThresholdsAreDropped() {
        let a = Config.Alerts(thresholds: [1e100, 20, 20, -1, 5, 100])
        #expect(a.effectiveThresholds == [100, 20, 5])
        // Would have trapped converting 1e100 to Int.
        let snap = [ProviderSnapshot(provider: .codex, windows: [UsageWindow(label: "Week", remainingPercent: 3, resetsAt: nil)])]
        #expect(AlertPlanner.plan(snapshots: snap, alerts: Config.Alerts(thresholds: [1e100, 5]), fired: []).alerts.count == 1)
        #expect(CodexProvider.windowLabel(1e300) == "Window")
    }

    @Test func newPeriodRearmsEvenWithoutSeeingTheReset() {
        let a = Config.Alerts(thresholds: [20])
        let reset1 = Date(timeIntervalSince1970: 1_893_456_000)
        func snap(_ rem: Double, _ reset: Date) -> [ProviderSnapshot] {
            [ProviderSnapshot(provider: .codex, windows: [UsageWindow(label: "Week", remainingPercent: rem, resetsAt: reset)])]
        }
        var r = AlertPlanner.plan(snapshots: snap(18, reset1), alerts: a, fired: [])
        #expect(r.alerts.count == 1)
        // Same period, reset time jittered by a second: no repeat.
        r = AlertPlanner.plan(snapshots: snap(15, reset1.addingTimeInterval(1)), alerts: a, fired: r.fired)
        #expect(r.alerts.isEmpty)
        // App was closed over the reset; next period is already low: alert again, old key dropped.
        r = AlertPlanner.plan(snapshots: snap(12, reset1.addingTimeInterval(7 * 86_400)), alerts: a, fired: r.fired)
        #expect(r.alerts.count == 1)
        #expect(r.fired.count == 1)
    }

    @Test func devinTOMLAndServerChecks() {
        let t = DevinProvider.parseTOML("""
        # comment
        [section]
        windsurf_api_key = "abc" # work account
        api_server_url = 'https://example.invalid'
        plain = value # note
        """)
        #expect(t["windsurf_api_key"] == "abc")
        #expect(t["api_server_url"] == "https://example.invalid")
        #expect(t["plain"] == "value")
        #expect(DevinProvider.isSafeServer(URL(string: "https://server.example.invalid/x")!))
        #expect(DevinProvider.isSafeServer(URL(string: "http://localhost:8080/x")!))
        #expect(!DevinProvider.isSafeServer(URL(string: "http://server.example.invalid/x")!))
    }
}

@Suite struct SecondReviewFixes {
    let week = UsageWindow(label: "Week", remainingPercent: 40, resetsAt: nil)

    @Test func failedCheckKeepsLastNumbersButSuccessReplaces() {
        let old = ProviderSnapshot(provider: .codex, plan: "Plus", windows: [week], fetchedAt: Date(timeIntervalSince1970: 1))
        let failed = ProviderSnapshot(provider: .codex, status: .error("HTTP 500")).merged(over: old)
        #expect(failed.windows == [week])
        #expect(failed.plan == "Plus")
        #expect(failed.status == .error("HTTP 500"))
        #expect(failed.fetchedAt == Date(timeIntervalSince1970: 1))
        let missing = ProviderSnapshot(provider: .codex, status: .notConfigured("gone")).merged(over: old)
        #expect(missing.windows.isEmpty)
        let fresh = ProviderSnapshot(provider: .codex, windows: []).merged(over: old)
        #expect(fresh.windows.isEmpty)
    }

    @Test func backoffDoublesToAnHour() {
        #expect([1, 2, 3, 4, 9].map { ProviderSnapshot.backoff(streak: $0) / 60 } == [10, 20, 40, 60, 60])
    }

    @Test func booleansAreNotPercentages() throws {
        let j = try json(#"{"rate_limit":{"primary_window":{"used_percent":true,"limit_window_seconds":18000}}}"#)
        #expect(try CodexProvider.parse(j).windows.isEmpty)
        #expect(Num.double(42) == 42)
    }

    @Test func customProvidersAreDeduplicated() throws {
        let c = try JSONDecoder().decode(Config.self, from: Data("""
        {"custom":[{"id":"claude","name":"Fake","command":["x"]},
                   {"id":"g","name":"G1","command":["x"]},{"id":"g","name":"G2","command":["y"]},
                   {"id":"","name":"Empty","command":["z"]}]}
        """.utf8))
        #expect(c.allProviderIDs.map(\.id) == ["claude", "codex", "muse", "devin", "g"])
        #expect(c.validCustom.map(\.name) == ["G1"])
    }

    @Test func customTimeoutIsClamped() {
        let p = { (t: Double?) in Config.CustomProvider(id: "e", name: "E", command: ["x"], timeout: t).effectiveTimeout }
        #expect(p(nil) == 60)
        #expect(p(0) == 1)
        #expect(p(-5) == 1)
        #expect(p(1e9) == 300)
    }

    @Test func claudeSessionComesFirst() throws {
        let j = try json("""
        {"limits":[{"kind":"weekly_all","percent":3,"resets_at":null},{"kind":"session","percent":18,"resets_at":null},
                   {"kind":"weekly_scoped","percent":0,"resets_at":null,"scope":null}]}
        """)
        #expect(try ClaudeProvider.parse(j).map(\.label) == ["5h", "Week", "Week · Scoped"])
    }

    @Test func staleFiredKeysArePruned() {
        let a = Config.Alerts(thresholds: [20])
        let low = [ProviderSnapshot(provider: .claude, windows: [
            UsageWindow(label: "Week", remainingPercent: 5, resetsAt: nil),
            UsageWindow(label: "Week · Opus", remainingPercent: 5, resetsAt: nil)])]
        var r = AlertPlanner.plan(snapshots: low, alerts: a, fired: ["codex/Week/20@-"])
        #expect(r.fired.count == 3)
        // Opus window disappears: its key goes, other providers' keys stay.
        let fewer = [ProviderSnapshot(provider: .claude, windows: [UsageWindow(label: "Week", remainingPercent: 5, resetsAt: nil)])]
        r = AlertPlanner.plan(snapshots: fewer, alerts: a, fired: r.fired)
        #expect(r.fired.sorted() == ["claude/Week/20@-", "codex/Week/20@-"])
    }

    @Test func generatedLabelsAreFormatted() {
        #expect(WindowLabel.display("2h") == "2h")
        #expect(WindowLabel.display("30m") == "30m")
        #expect(WindowLabel.display("Week · Opus") == "Week · Opus")
    }
}

@Suite struct EditorChoiceTests {
    let installed: [String: URL] = [
        "com.sublimetext.4": URL(fileURLWithPath: "/Applications/Sublime Text.app"),
        "com.microsoft.VSCode": URL(fileURLWithPath: "/Applications/Visual Studio Code.app"),
    ]
    let paths: Set<String> = ["/Applications/Sublime Text.app", "/Applications/Visual Studio Code.app"]
    let textEdit = URL(fileURLWithPath: "/System/Applications/TextEdit.app")

    func pick(_ preferred: String?, editors: [String: URL]? = nil) -> String? {
        let e = editors ?? installed
        return EditorChoice.resolve(preferred: preferred, appForBundleID: { e[$0] }, appExists: { paths.contains($0) },
                                    plainTextApp: textEdit, home: URL(fileURLWithPath: "/Users/test"))?.lastPathComponent
    }

    @Test func prefersACodeEditorOverTheJSONDefault() {
        #expect(pick(nil) == "Visual Studio Code.app")
        #expect(pick(nil, editors: [:]) == "TextEdit.app")
    }

    @Test func configEditorByNameIdOrPath() {
        #expect(pick("Sublime Text") == "Sublime Text.app")
        #expect(pick("com.sublimetext.4") == "Sublime Text.app")
        #expect(pick("/Applications/Sublime Text.app") == "Sublime Text.app")
        // Unknown editor falls back to the usual order.
        #expect(pick("Nonexistent Editor") == "Visual Studio Code.app")
    }
}
