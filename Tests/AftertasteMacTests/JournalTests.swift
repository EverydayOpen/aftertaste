import Darwin
import Foundation
import XCTest
import AftertasteCore
@testable import AftertasteMac

final class JournalTests: MacTestCase {
    private let when = Date(timeIntervalSince1970: 1_790_000_000)

    private func entry(_ sb: Sandbox, _ phase: ActivityPhase, trashed: String? = nil) -> ActivityEntry {
        ActivityEntry(timestamp: when, runID: "r1", verb: .trash, phase: phase, path: sb.home + "/Library/Caches/x", label: "Foo",
                      status: phase == .result ? .moved : nil, trashedPath: trashed)
    }

    func testBeginCreatesAPrivateFolderAndFile() throws {
        let sb = try makeSandbox()
        XCTAssertTrue(Journal.begin(home: sb.home, runID: "r1", verb: .trash, summary: "1 item", at: when))
        let dir = Journal.directory(home: sb.home)
        XCTAssertEqual(fileMode(dir), 0o700)
        XCTAssertEqual(fileMode(dir + "/" + ActivityLog.fileName(for: when)), 0o600)
    }

    func testLinesAreAppendedInOrderWithHomeRelativePaths() throws {
        let sb = try makeSandbox()
        XCTAssertTrue(Journal.begin(home: sb.home, runID: "r1", verb: .trash, summary: "1 item", at: when))
        XCTAssertTrue(Journal.intent(home: sb.home, entry: entry(sb, .intent)))
        XCTAssertTrue(Journal.result(home: sb.home, entry: entry(sb, .result, trashed: NSHomeDirectory() + "/.Trash/x")))
        XCTAssertTrue(Journal.end(home: sb.home, runID: "r1", verb: .trash, detail: nil, at: when))
        let log = Journal.loadAll(home: sb.home)
        XCTAssertEqual(log.map(\.phase), [.intent, .intent, .result, .result])
        XCTAssertEqual(log.map(\.verb), [.run, .trash, .trash, .run])
        XCTAssertEqual(log[1].path, "~/Library/Caches/x")
        XCTAssertEqual(log[2].status, .moved)
        // The sandbox home is not the real home, so the Trash path stays absolute; nothing leaks the sandbox path.
        XCTAssertFalse(log.contains { $0.path.contains(sb.home) })
    }

    func testAppendsNeverTruncate() throws {
        let sb = try makeSandbox()
        for i in 0..<3 {
            XCTAssertTrue(Journal.begin(home: sb.home, runID: "r\(i)", verb: .trash, summary: "x", at: when))
        }
        XCTAssertEqual(Journal.loadAll(home: sb.home).count, 3)
    }

    func testRefusesASymlinkedFolder() throws {
        let sb = try makeSandbox()
        let elsewhere = sb.root + "/elsewhere"
        try FileManager.default.createDirectory(atPath: elsewhere, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        try FileManager.default.createSymbolicLink(atPath: Journal.directory(home: sb.home), withDestinationPath: elsewhere)
        XCTAssertFalse(Journal.begin(home: sb.home, runID: "r1", verb: .trash, summary: "x", at: when))
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: elsewhere), [])
    }

    func testRefusesAFolderWithTheWrongModeAndDoesNotFixIt() throws {
        let sb = try makeSandbox()
        let dir = Journal.directory(home: sb.home)
        try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o755])
        XCTAssertFalse(Journal.begin(home: sb.home, runID: "r1", verb: .trash, summary: "x", at: when))
        XCTAssertEqual(fileMode(dir), 0o755, "never chmod")
    }

    func testRefusesASymlinkedFile() throws {
        let sb = try makeSandbox()
        let dir = Journal.directory(home: sb.home)
        try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        let target = sb.root + "/target.jsonl"
        FileManager.default.createFile(atPath: target, contents: Data())
        try FileManager.default.createSymbolicLink(atPath: dir + "/" + ActivityLog.fileName(for: when), withDestinationPath: target)
        XCTAssertFalse(Journal.begin(home: sb.home, runID: "r1", verb: .trash, summary: "x", at: when))
        XCTAssertEqual(try FileManager.default.attributesOfItem(atPath: target)[.size] as? UInt64, 0)
    }

    func testAnUnwritableFolderMeansNoIntent() throws {
        let sb = try makeSandbox()
        XCTAssertTrue(Journal.begin(home: sb.home, runID: "r1", verb: .trash, summary: "x", at: when))
        chmod(Journal.directory(home: sb.home), 0o500)
        XCTAssertFalse(Journal.intent(home: sb.home, entry: entry(sb, .intent)))
    }

    func testLoadAllIgnoresForeignAndMalformedFiles() throws {
        let sb = try makeSandbox()
        XCTAssertTrue(Journal.begin(home: sb.home, runID: "r1", verb: .trash, summary: "x", at: when))
        let dir = Journal.directory(home: sb.home)
        FileManager.default.createFile(atPath: dir + "/notes.txt", contents: Data("hello".utf8))
        FileManager.default.createFile(atPath: dir + "/journal-2026-01.jsonl", contents: Data("not json\n".utf8))
        XCTAssertEqual(Journal.loadAll(home: sb.home).count, 1)
    }

    func testInventoryRoundTripKeepsAbsentApps() throws {
        let sb = try makeSandbox()
        let t0 = Date(timeIntervalSince1970: 1_790_000_000), t1 = Date(timeIntervalSince1970: 1_790_100_000)
        let foo = AppIdentity(bundleID: "com.example.foo", displayName: "Foo", bundlePath: sb.home + "/Applications/Foo.app")
        InventoryStore.update(with: InstalledSnapshot(apps: [foo], capturedAt: t0), home: sb.home, now: t0)
        let after = InventoryStore.update(with: InstalledSnapshot(apps: [], capturedAt: t1), home: sb.home, now: t1)
        XCTAssertEqual(after.map(\.id), ["com.example.foo"])
        XCTAssertEqual(after[0].firstSeen.timeIntervalSince1970, t0.timeIntervalSince1970, accuracy: 1)
        XCTAssertEqual(after[0].lastSeen.timeIntervalSince1970, t0.timeIntervalSince1970, accuracy: 1, "an absent app keeps its last sighting")
        XCTAssertEqual(InventoryStore.load(home: sb.home).map(\.id), ["com.example.foo"])
        XCTAssertEqual(fileMode(Journal.directory(home: sb.home)), 0o700)
        XCTAssertEqual(fileMode(Journal.directory(home: sb.home) + "/inventory.json"), 0o600)
    }
}
