import Foundation
import Testing
@testable import LimitsBarCore

@Suite struct ShellTests {
    func script(_ body: String) throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("lb-\(UUID().uuidString).sh")
        try ("#!/bin/sh\n" + body).write(to: url, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
        return url
    }

    @Test func ignoresSIGTERMStillTimesOut() async throws {
        let url = try script("trap '' TERM\nsleep 30\n")
        let start = Date()
        await #expect(throws: ProviderError.self) { try await Shell.run(url, [], timeout: 1) }
        #expect(Date().timeIntervalSince(start) < 8)
    }

    @Test func backgroundChildHoldingPipeDoesNotHang() async throws {
        let url = try script("( sleep 30 ) &\necho hello\n")
        let start = Date()
        let r = try await Shell.run(url, [], timeout: 10)
        #expect(String(decoding: r.stdout, as: UTF8.self).contains("hello"))
        #expect(Date().timeIntervalSince(start) < 5)
    }

    @Test func capturesBothStreams() async throws {
        let url = try script("echo out\necho err >&2\nexit 3\n")
        let r = try await Shell.run(url, [], timeout: 10)
        #expect(String(decoding: r.stdout, as: UTF8.self) == "out\n")
        #expect(r.stderr == "err\n")
        #expect(r.status == 3)
    }
}
