import Darwin
import Foundation
import XCTest
import AftertasteCore
@testable import AftertasteMac

/// The two verbs against a real filesystem (BUILD_PLAN §6.3). `trashItem` really moves into the runner's Trash; the sandbox
/// removes those entries afterwards. If the session cannot trash at all, the tests that need it skip with the reason.
final class TrashTests: MacTestCase {
    private func undoRecord(_ outcome: TrashOutcome, _ item: ResidueItem) throws -> UndoRecord {
        let moved = try XCTUnwrap(outcome.moved.first { $0.item.path == item.path })
        return UndoRecord(runID: outcome.runID, originalPath: item.path, trashedPath: try XCTUnwrap(moved.trashedPath),
                          stamp: try XCTUnwrap(item.stamp), bytes: item.size, label: "Foo", tier: item.tier, movedAt: Date())
    }

    private func restore(_ records: [UndoRecord], _ sb: Sandbox) -> UndoOutcome {
        UndoStore.restore(records, home: sb.home, now: { Date() }, progress: { _ in })
    }

    func testTrashThenUndoRoundTrip() async throws {
        let sb = try makeSandbox()
        let item = sb.cacheItem("com.example.foo")
        let outcome = await sb.trash(sb.plan([item]))
        try requireTrash(outcome)
        XCTAssertEqual(outcome.movedCount, 1)
        XCTAssertFalse(sb.exists(item.path), "the original is gone")

        let log = Journal.loadAll(home: sb.home).filter { $0.verb == .trash }
        XCTAssertEqual(log.map(\.phase), [.intent, .result], "write-ahead: intent first, then the result")
        XCTAssertEqual(log.last?.status, .moved)
        XCTAssertEqual(log.last?.path, "~/Library/Caches/com.example.foo")
        XCTAssertNotNil(log.last?.trashedPath, "resultingItemURL is recorded for Undo")

        let record = try undoRecord(outcome, item)
        let first = restore([record], sb)
        if first.results.first?.status == .trashUnreadable { throw XCTSkip("the Trash is not readable without Full Disk Access here (VERIFY)") }
        XCTAssertEqual(first.results.first?.status, .restored)
        XCTAssertTrue(sb.exists(item.path))
        XCTAssertTrue(Journal.loadAll(home: sb.home).contains { $0.verb == .undo && $0.undoStatus == .restored })

        XCTAssertEqual(restore([record], sb).results.first?.status, .alreadyEmptied, "restored once; the Trash entry is gone now")
    }

    func testUndoNeverOverwrites() async throws {
        let sb = try makeSandbox()
        let item = sb.cacheItem("com.example.foo")
        let outcome = await sb.trash(sb.plan([item]))
        try requireTrash(outcome)
        let record = try undoRecord(outcome, item)
        sb.put("Library/Caches/com.example.foo/marker.txt", bytes: 7)   // something new took its place
        let result = restore([record], sb)
        if result.results.first?.status == .trashUnreadable { throw XCTSkip("the Trash is not readable without Full Disk Access here (VERIFY)") }
        XCTAssertEqual(result.results.first?.status, .destinationExists)
        XCTAssertTrue(sb.exists(item.path + "/marker.txt"), "what is there is untouched")
        XCTAssertTrue(sb.exists(record.trashedPath), "and the Trash entry stays")
    }

    func testAChangedItemIsNotMoved() async throws {
        let sb = try makeSandbox()
        let item = sb.cacheItem("com.example.foo")
        sb.put("Library/Caches/com.example.foo/new.bin")      // changed after the user reviewed it
        let outcome = await sb.trash(sb.plan([item]))
        XCTAssertEqual(outcome.results.map(\.status), [.changedSinceScan])
        XCTAssertTrue(sb.exists(item.path))
    }

    func testAnItemThatWasReplacedByALinkIsNotMoved() async throws {
        let sb = try makeSandbox()
        let item = sb.cacheItem("com.example.foo")
        let outside = sb.root + "/outside"
        sb.put("../outside/payload.txt")
        try FileManager.default.removeItem(atPath: item.path)
        try FileManager.default.createSymbolicLink(atPath: item.path, withDestinationPath: outside)
        let outcome = await sb.trash(sb.plan([item]))
        XCTAssertEqual(outcome.results.map(\.status), [.changedSinceScan])
        XCTAssertTrue(sb.exists(outside + "/payload.txt"))
    }

    func testALinkedParentFolderMovesNothing() async throws {
        let sb = try makeSandbox()
        let item = sb.cacheItem("com.example.foo")
        let real = sb.root + "/realcaches"
        try FileManager.default.moveItem(atPath: sb.home + "/Library/Caches", toPath: real)
        try FileManager.default.createSymbolicLink(atPath: sb.home + "/Library/Caches", withDestinationPath: real)
        let outcome = await sb.trash(sb.plan([item]))
        XCTAssertEqual(outcome.results.map(\.status), [.blocked])
        XCTAssertTrue(sb.exists(real + "/com.example.foo/data.bin"))
    }

    func testALinkLeafMovesTheLinkAndNeverItsTarget() async throws {
        let sb = try makeSandbox()
        sb.put("../outside/payload.txt")
        let link = sb.home + "/Library/Caches/com.example.link"
        try FileManager.default.createSymbolicLink(atPath: link, withDestinationPath: sb.root + "/outside")
        let item = sb.item(at: link, owner: "com.example.link", fileType: .symlink)
        let outcome = await sb.trash(sb.plan([item]))
        try requireTrash(outcome)
        XCTAssertEqual(outcome.movedCount, 1)   // VERIFY: trashItem on a symlink moves the link
        XCTAssertFalse(sb.exists(link))
        XCTAssertTrue(sb.exists(sb.root + "/outside/payload.txt"), "the target is never touched")
    }

    func testTiersWithoutAGreenLightAreRefused() async throws {
        let sb = try makeSandbox()
        var handsOff = sb.cacheItem("com.example.a")
        handsOff.tier = .handsOff
        var admin = sb.cacheItem("com.example.b")
        admin.tier = .needsAdmin
        var medium = sb.cacheItem("com.example.c")
        medium.tier = .medium
        var reviewA = sb.cacheItem("com.example.d")
        reviewA.tier = .low
        var reviewB = sb.cacheItem("com.example.e")
        reviewB.tier = .low
        var blocked = sb.cacheItem("com.example.f")
        blocked.blocked = .listedOnly
        let all = [handsOff, admin, medium, reviewA, reviewB, blocked]
        let outcome = await sb.trash(sb.plan(all))   // Medium not acknowledged; two Review items in one plan
        XCTAssertEqual(outcome.results.map(\.status), Array(repeating: TrashStatus.blocked, count: all.count))
        for item in all { XCTAssertTrue(sb.exists(item.path), item.path) }
    }

    func testARunningOwnerBlocksItsItems() async throws {
        let sb = try makeSandbox()
        let app = try sb.makeApp("Foo", id: "com.example.foo")
        let owner = try XCTUnwrap(Identity.read(appURL: URL(fileURLWithPath: app), now: Date()).identity)
        let process = try sb.launch(executableAt: app + "/Contents/MacOS/Foo")
        let item = sb.cacheItem("com.example.foo")
        let blocked = await sb.trash(sb.plan([item], owners: [owner]))
        XCTAssertEqual(blocked.results.map(\.status), [.blocked])
        XCTAssertTrue(sb.exists(item.path))

        process.terminate()
        process.waitUntilExit()
        let freed = await sb.trash(sb.plan([item], owners: [owner]))
        try requireTrash(freed)
        XCTAssertEqual(freed.movedCount, 1)
    }

    func testAJournalThatStopsWorkingStopsTheRun() async throws {
        let sb = try makeSandbox()
        let a = sb.cacheItem("com.example.a")
        let b = sb.cacheItem("com.example.b")
        let dir = Journal.directory(home: sb.home)
        let outcome = await sb.trash(sb.plan([a, b]), progress: { _ in chmod(dir, 0o500) })   // after the first item
        try requireTrash(outcome)
        XCTAssertEqual(outcome.results.map(\.status), [.moved, .notAttempted])
        XCTAssertNotNil(outcome.abortReason)
        XCTAssertTrue(sb.exists(b.path), "the second item was never touched")
    }

    func testNothingMovesWhenTheJournalCannotBeOpened() async throws {
        let sb = try makeSandbox()
        let item = sb.cacheItem("com.example.foo")
        try FileManager.default.createDirectory(atPath: Journal.directory(home: sb.home), withIntermediateDirectories: true,
                                                attributes: [.posixPermissions: 0o755])
        let outcome = await sb.trash(sb.plan([item]))
        XCTAssertEqual(outcome.results.map(\.status), [.notAttempted])
        XCTAssertNotNil(outcome.abortReason)
        XCTAssertTrue(sb.exists(item.path))
    }

    func testUninstallNowStopsWhenTheAppDoesNotMove() async throws {
        let sb = try makeSandbox()
        let app = try sb.makeApp("Foo", id: "com.example.foo")
        let owner = try XCTUnwrap(Identity.read(appURL: URL(fileURLWithPath: app), now: Date()).identity)
        let bundle = sb.item(at: app, owner: "com.example.foo", ruleID: "APP", root: nil, kind: .app)
        let cache = sb.cacheItem("com.example.foo")
        sb.put("Applications/Foo.app/changed.txt")   // the bundle changed after review
        let outcome = await sb.trash(sb.plan([bundle, cache], owners: [owner], kind: .app))
        XCTAssertEqual(outcome.results.map(\.status), [.changedSinceScan, .notAttempted])
        XCTAssertTrue(sb.exists(app))
        XCTAssertTrue(sb.exists(cache.path))
    }

    func testAnOwnerThatIsInstalledAgainBlocksItsItemsAndIsAskedOncePerRun() async throws {
        let sb = try makeSandbox()
        let a = sb.cacheItem("com.example.foo")
        let b = sb.cacheItem("com.example.foo.more", owner: "com.example.foo")
        var asked: [String] = []
        let outcome = await sb.trash(sb.plan([a, b]), installedNow: { owner, _ in asked.append(owner.bundleID); return true })
        XCTAssertEqual(outcome.results.map(\.status), [.blocked, .blocked])
        XCTAssertEqual(asked, ["com.example.foo"], "asked once per owner, not once per item")
        XCTAssertTrue(sb.exists(a.path) && sb.exists(b.path))
    }

    func testUninstallNowDoesNotCountTheBundleItJustMoved() async throws {
        let sb = try makeSandbox()
        let app = try sb.makeApp("Foo", id: "com.example.foo")
        let owner = try XCTUnwrap(Identity.read(appURL: URL(fileURLWithPath: app), now: Date()).identity)
        let bundle = sb.item(at: app, owner: "com.example.foo", ruleID: "APP", root: nil, kind: .app)
        let cache = sb.cacheItem("com.example.foo")
        var excluded: String?
        let outcome = await sb.trash(sb.plan([bundle, cache], owners: [owner], kind: .app), installedNow: { _, path in excluded = path; return false })
        try requireTrash(outcome)
        XCTAssertEqual(outcome.movedCount, 2)
        XCTAssertTrue(excluded?.hasSuffix("/Foo.app") == true, "the original bundle path is excluded from the installed check")
    }

    func testAnItemWhoseOwnerIsNotInThePlanIsRefused() async throws {
        let sb = try makeSandbox()
        let item = sb.cacheItem("com.example.foo")
        let outcome = await sb.trash(sb.plan([item], owners: []))
        XCTAssertEqual(outcome.results.map(\.status), [.blocked])
        XCTAssertTrue(sb.exists(item.path))
    }

    func testAnAppItemInAnOrphanPlanOrNotFirstIsRefused() async throws {
        let sb = try makeSandbox()
        let app = try sb.makeApp("Foo", id: "com.example.foo")
        let bundle = sb.item(at: app, owner: "com.example.foo", ruleID: "APP", root: nil, kind: .app)
        let orphanRun = await sb.trash(sb.plan([bundle], kind: .orphans))
        XCTAssertEqual(orphanRun.results.map(\.status), [.blocked])
        let cache = sb.cacheItem("com.example.foo")
        let notFirst = await sb.trash(sb.plan([cache, bundle], kind: .app))
        XCTAssertEqual(notFirst.results.last?.status, .blocked)
        XCTAssertTrue(sb.exists(app))
    }

    func testUninstallNowMovesTheAppFirst() async throws {
        let sb = try makeSandbox()
        let app = try sb.makeApp("Foo", id: "com.example.foo")
        let owner = try XCTUnwrap(Identity.read(appURL: URL(fileURLWithPath: app), now: Date()).identity)
        let bundle = sb.item(at: app, owner: "com.example.foo", ruleID: "APP", root: nil, kind: .app)
        let cache = sb.cacheItem("com.example.foo")
        let outcome = await sb.trash(sb.plan([bundle, cache], owners: [owner], kind: .app))
        try requireTrash(outcome)
        XCTAssertEqual(outcome.results.map(\.status), [.moved, .moved])
        XCTAssertEqual(outcome.results.map(\.item.path), [app, cache.path])
    }

    func testAnAppRunWithoutTheAppItemMovesNothingOfThatOwner() async throws {
        let sb = try makeSandbox()
        let cache = sb.cacheItem("com.example.foo")
        let outcome = await sb.trash(sb.plan([cache], kind: .app), installedNow: { _, _ in true })
        XCTAssertEqual(outcome.results.map(\.status), [.blocked])
        XCTAssertTrue(sb.exists(cache.path))
    }

    func testALaunchItemIsListedNeverMoved() async throws {
        let sb = try makeSandbox()
        let plist = try sb.putLaunchAgent(label: "com.example.foo.helper", program: nil)
        let item = sb.item(at: plist, owner: "com.example.foo", ruleID: "U9", root: .launchAgents, kind: .launchItem, fileType: .file, tier: .high)
        let outcome = await sb.trash(sb.plan([item]))
        XCTAssertEqual(outcome.results.map(\.status), [.blocked])
        XCTAssertTrue(sb.exists(plist))
    }

    func testAnApproximateSizeIsJournaledAsAFloor() async throws {
        let sb = try makeSandbox()
        var item = sb.cacheItem("com.example.foo")
        item.sizeState = .atLeast
        let outcome = await sb.trash(sb.plan([item]))
        try requireTrash(outcome)
        let results = Journal.loadAll(home: sb.home).filter { $0.verb == .trash && $0.phase == .result && $0.runID == outcome.runID }
        XCTAssertEqual(results.map(\.lowerBound), [true])
    }
}
