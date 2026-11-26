import Foundation
import Testing
@testable import LimitsBarCore

@Suite struct NoticesTests {
    static let root = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()

    @Test func joinsHardWrapsKeepsCopyrightAndClauses() {
        let md = """
        # Third-party notices

        ## Lib 1.0

        ```text
        Copyright (c) 2014 A.
        Copyright (c) 2015 B.
        All rights reserved.

        Permission is hereby granted, free of charge,
        to any person.

        =====
        EXTERNAL
        =====

        Conditions:
        1. Keep this
           notice.
        2. Reproduce it.
        ```
        """
        #expect(Notices.plainText(fromMarkdown: md) == """
        Lib 1.0

        Copyright (c) 2014 A.
        Copyright (c) 2015 B.
        All rights reserved.

        Permission is hereby granted, free of charge, to any person.

        EXTERNAL

        Conditions:
        1. Keep this notice.
        2. Reproduce it.
        """)
    }

    @Test func realNoticesKeepEveryCopyrightHolder() throws {
        let md = try String(contentsOf: Self.root.appendingPathComponent("THIRD_PARTY_NOTICES.md"), encoding: .utf8)
        let text = Notices.plainText(fromMarkdown: md)
        for holder in ["Andy Matuschak", "Colin Percival", "Yuta Mori", "Orson Peters", "Mark Hamlin"] {
            #expect(text.contains(holder))
        }
        #expect(!text.contains("```"))
        #expect(!text.contains("\n\n\n"))
    }
}
