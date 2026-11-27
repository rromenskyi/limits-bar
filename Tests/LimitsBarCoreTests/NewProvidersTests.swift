import Foundation
import Testing
@testable import LimitsBarCore

private func json(_ s: String) throws -> [String: Any] { try JSONObject.parse(Data(s.utf8)) }

@Suite struct CopilotTests {
    @Test func freePlanSkipsEmptyPremium() throws {
        let s = try CopilotProvider.parse(json("""
        {"access_type_sku":"free_limited_copilot","copilot_plan":"individual",
         "quota_reset_date_utc":"2026-12-01T00:00:00.000Z",
         "quota_snapshots":{
          "chat":{"entitlement":200,"remaining":150,"percent_remaining":75.0,"unlimited":false},
          "completions":{"entitlement":2000,"remaining":2000,"percent_remaining":100.0,"unlimited":false},
          "premium_interactions":{"entitlement":0,"remaining":0,"percent_remaining":0.0,"unlimited":false}}}
        """))
        #expect(s.plan == "Free")
        #expect(s.windows.map(\.label) == ["Chat", "Completions"])
        #expect(s.windows[0].remainingPercent == 75)
        #expect(s.windows[0].resetsAt == Dates.iso("2026-12-01T00:00:00Z"))
    }

    @Test func proPlanShowsPremiumFirstAndSkipsUnlimited() throws {
        let s = try CopilotProvider.parse(json("""
        {"access_type_sku":"copilot_pro","quota_snapshots":{
          "chat":{"entitlement":0,"percent_remaining":100,"unlimited":true},
          "completions":{"entitlement":0,"percent_remaining":100,"unlimited":true},
          "premium_interactions":{"entitlement":300,"percent_remaining":12.5,"unlimited":false}}}
        """))
        #expect(s.plan == "Pro")
        #expect(s.windows.map(\.label) == ["Premium"])
        #expect(s.windows[0].remainingPercent == 12.5)
    }

    @Test func unknownShapeIsAnError() {
        #expect(throws: ProviderError.self) { try CopilotProvider.parse(json(#"{"message":"oops"}"#)) }
    }

    @Test func pluginTokenOnlyForGitHubDotCom() {
        let apps = #"{"ghe.example.com:Iv1.x":{"oauth_token":"ghe_tok"},"github.com:Iv1.b507":{"user":"u","oauth_token":"gho_abc"}}"#
        #expect(CopilotProvider.pluginToken(Data(apps.utf8)) == "gho_abc")
        #expect(CopilotProvider.pluginToken(Data(#"{"ghe.example.com":{"oauth_token":"x"}}"#.utf8)) == nil)
    }
}

@Suite struct GeminiTests {
    @Test func bucketsPerModelKeepTightest() throws {
        let s = try GeminiProvider.parse(json("""
        {"buckets":[
          {"modelId":"gemini-2.5-pro","remainingFraction":0.8,"resetTime":"2026-11-27T08:00:00Z","tokenType":"REQUESTS"},
          {"modelId":"gemini-2.5-pro_vertex","remainingFraction":0.5,"resetTime":"2026-11-27T08:00:00Z"},
          {"modelId":"gemini-2.5-flash-lite","remainingFraction":1,"resetTime":"2026-11-27T08:00:00Z"},
          {"modelId":"gemini-2.5-flash","tokenType":"REQUESTS"}]}
        """), plan: "Free")
        #expect(s.windows.map(\.label) == ["2.5 Pro", "2.5 Flash Lite"])
        #expect(s.windows[0].remainingPercent == 50)
        #expect(s.windows[1].remainingPercent == 100)
        #expect(s.plan == "Free")
    }

    @Test func projectAndPlanFromLoadCodeAssist() throws {
        let load = try json(#"{"currentTier":{"id":"free-tier"},"cloudaicompanionProject":"proj-123"}"#)
        #expect(GeminiProvider.project(load) == "proj-123")
        #expect(GeminiProvider.plan(load) == "Free")
        let paid = try json(#"{"currentTier":{"id":"standard-tier"},"paidTier":{"name":"Google AI Pro"},"cloudaicompanionProject":{"id":"p2"}}"#)
        #expect(GeminiProvider.project(paid) == "p2")
        #expect(GeminiProvider.plan(paid) == "Google AI Pro")
        #expect(GeminiProvider.project(try json(#"{"currentTier":{"id":"free-tier"}}"#)) == nil)
    }

    @Test func missingBucketsIsAnError() {
        #expect(throws: ProviderError.self) { try GeminiProvider.parse(json(#"{"error":"x"}"#), plan: nil) }
    }
}

@Suite struct CursorTests {
    @Test func planUsageFromUsedAndLimitNotPercentFields() throws {
        let s = try CursorProvider.parse(json("""
        {"billingCycleStart":"2026-08-18T08:09:13.000Z","billingCycleEnd":"2026-09-18T08:09:13.000Z",
         "membershipType":"pro","limitType":"user","isUnlimited":false,
         "individualUsage":{
           "plan":{"enabled":true,"used":1516,"limit":2000,"remaining":484,
                   "breakdown":{"included":1516,"bonus":0,"total":1516},
                   "autoPercentUsed":3.29,"apiPercentUsed":0.71,"totalPercentUsed":3.06},
           "onDemand":{"enabled":false,"used":0,"limit":null,"remaining":null}},
         "teamUsage":{}}
        """))
        #expect(s.plan == "Pro")
        #expect(s.windows.map(\.label) == ["Month"])
        #expect(abs(s.windows[0].remainingPercent - 24.2) < 0.001)
        #expect(s.windows[0].resetsAt == Dates.iso("2026-09-18T08:09:13.000Z"))
    }

    @Test func onDemandWithLimitAndUnlimitedPlans() throws {
        let s = try CursorProvider.parse(json("""
        {"membershipType":"pro_plus","individualUsage":{
          "plan":{"enabled":true,"used":500,"limit":1000},
          "onDemand":{"enabled":true,"used":250,"limit":1000,"remaining":750}}}
        """))
        #expect(s.plan == "Pro+")
        #expect(s.windows.map(\.remainingPercent) == [50, 75])
        let u = try CursorProvider.parse(json(#"{"membershipType":"ultra","isUnlimited":true,"individualUsage":{"plan":{"used":1,"limit":2}}}"#))
        #expect(u.windows.isEmpty)
        #expect(throws: ProviderError.self) { try CursorProvider.parse(json(#"{"error":"x"}"#)) }
    }

    @Test func userIDFromJWT() {
        func jwt(_ payload: String) -> String {
            let b = Data(payload.utf8).base64EncodedString()
                .replacingOccurrences(of: "=", with: "").replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_")
            return "eyJhbGciOiJIUzI1NiJ9.\(b).sig"
        }
        #expect(CursorProvider.userID(fromJWT: jwt(#"{"sub":"auth0|user_01ABC","exp":1}"#)) == "user_01ABC")
        #expect(CursorProvider.userID(fromJWT: jwt(#"{"sub":"a|b;c=d"}"#)) == nil)  // nothing that could inject a cookie
        #expect(CursorProvider.userID(fromJWT: "not-a-jwt") == nil)
    }
}
