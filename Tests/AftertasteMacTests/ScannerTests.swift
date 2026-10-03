import Darwin
import Foundation
import XCTest
import AftertasteCore
@testable import AftertasteMac

final class ScannerTests: MacTestCase {
    /// Foo (the app being removed) and Bar (installed and staying), each with the usual leftovers.
    private func fakeLibrary(_ sb: Sandbox, installFoo: Bool = true) throws -> (foo: String, bar: String) {
        var foo = sb.home + "/Applications/Foo.app"
        if installFoo { foo = try sb.makeApp("Foo", id: "com.example.foo", exec: "Foo") }
        let bar = try sb.makeApp("Bar", id: "com.example.bar", exec: "Bar")
        for id in ["com.example.foo", "com.example.bar"] {
            sb.put("Library/Preferences/\(id).plist", bytes: 300)
            sb.put("Library/Caches/\(id)/c.bin", bytes: 4000)
            sb.put("Library/Saved Application State/\(id).savedState/windows.data", bytes: 500)
            sb.put("Library/Application Support/\(id)/doc.bin", bytes: 2000)
        }
        return (foo, bar)
    }

    private func scan(_ request: ScanRequest, _ sb: Sandbox, containersReadable: Bool = false) async -> ScanResult {
        await ResidueScanner.scan(request, prefs: .default, home: sb.home, osVersion: "26.0", now: Date(), containersReadable: containersReadable)
    }

    private func ageEverything(of id: String, _ sb: Sandbox, days: Double) {
        for rel in ["Library/Preferences/\(id).plist", "Library/Caches/\(id)/c.bin", "Library/Caches/\(id)",
                    "Library/Saved Application State/\(id).savedState/windows.data", "Library/Saved Application State/\(id).savedState",
                    "Library/Application Support/\(id)/doc.bin", "Library/Application Support/\(id)"] {
            sb.age(sb.home + "/" + rel, days: days)
        }
    }

    func testAListedFileCarriesItsAllocatedBytesAndAFolderDoesNot() throws {
        let sb = try makeSandbox()
        let file = sb.put("Library/Preferences/com.example.foo.plist", bytes: 100)
        sb.put("Library/Caches/com.example.foo/c.bin", bytes: 100)
        let library = ResidueScanner.listLibrary(home: sb.home, now: Date(), containersReadable: false)
        func entry(_ root: LibraryRoot, _ name: String) -> LibraryEntry? {
            library.listings.first { $0.coverage.root == root }?.entries.first { $0.name == name }
        }
        let st = Fs.info(file).st
        let stamp = try XCTUnwrap(entry(.preferences, "com.example.foo.plist")?.stamp)
        XCTAssertEqual(stamp.allocated, UInt64(st.st_blocks) * 512, "a file is sized in allocated bytes, like a folder's sum")
        XCTAssertNil(try XCTUnwrap(entry(.caches, "com.example.foo")?.stamp).allocated)
    }

    func testASymlinkedAppStillCountsAsInstalledUnderItsRealPath() throws {
        let sb = try makeSandbox()
        let real = try sb.makeApp("Linked", id: "com.example.linked", in: sb.root + "/Elsewhere")
        let link = sb.home + "/Applications/Linked.app"
        try FileManager.default.createSymbolicLink(atPath: link, withDestinationPath: real)
        XCTAssertNotNil(Identity.read(appURL: URL(fileURLWithPath: link), now: Date()).rejection, "dropping a link is still refused")

        let snapshot = InstalledApps.discover(home: sb.home, inventory: [], now: Date())
        let app = try XCTUnwrap(snapshot.apps.first { $0.bundleID == "com.example.linked" })
        XCTAssertEqual(app.bundlePath, (real as NSString).resolvingSymlinksInPath)
    }

    // MARK: uninstall now

    func testUninstallNowFindsTheRightTiers() async throws {
        let sb = try makeSandbox()
        let paths = try fakeLibrary(sb)
        try sb.putLaunchAgent(label: "com.example.foo.agent", program: paths.foo + "/Contents/MacOS/Foo")
        let target = try XCTUnwrap(Identity.read(appURL: URL(fileURLWithPath: paths.foo), now: Date()).identity)
        let result = await scan(.app(target), sb)

        let group = try XCTUnwrap(result.groups.first { $0.owner.bundleID == "com.example.foo" })
        func tier(_ suffix: String) -> Tier? { group.items.first { $0.path.hasSuffix(suffix) }?.tier }
        XCTAssertEqual(tier("/Applications/Foo.app"), .high, "the app you dropped")
        XCTAssertEqual(tier("/Library/Preferences/com.example.foo.plist"), .high)
        XCTAssertEqual(tier("/Library/Caches/com.example.foo"), .high)
        XCTAssertEqual(tier("/Library/Saved Application State/com.example.foo.savedState"), .high)
        XCTAssertEqual(tier("/Library/Application Support/com.example.foo"), .medium, "may hold your data")
        XCTAssertEqual(tier("/Library/LaunchAgents/com.example.foo.agent.plist"), .handsOff, "launch agents are listed, not removed")

        XCTAssertFalse(result.items.contains { $0.path.contains("com.example.bar") }, "an installed app's files are not in the list")
        XCTAssertTrue(result.items.allSatisfy { $0.stamp != nil }, "every item carries the stamp Guard compares against")
        XCTAssertEqual(result.coverage.places.count, LibraryRoot.allCases.count)

        let ticked = ItemSelection.preselected(result)
        XCTAssertEqual(ticked, Set(result.items.filter { $0.tier == .high }.map(\.id)))
        XCTAssertFalse(ticked.contains { $0.contains("Application Support") })
    }

    func testScanPlanTrashAndUndoEndToEnd() async throws {
        let sb = try makeSandbox()
        let paths = try fakeLibrary(sb)
        let target = try XCTUnwrap(Identity.read(appURL: URL(fileURLWithPath: paths.foo), now: Date()).identity)
        let result = await scan(.app(target), sb)
        let plan = TrashPlanner.plan(from: result, ticked: ItemSelection.preselected(result), mode: .bulk(acknowledgedMedium: false),
                                     now: Date(), runID: TrashPlanner.newRunID(now: Date(), random: 0xABCDEF))
        XCTAssertEqual(plan.items.first?.ruleID, "APP", "the app goes first")
        let outcome = await sb.trash(plan)
        try requireTrash(outcome)
        XCTAssertEqual(outcome.movedCount, plan.items.count)
        XCTAssertFalse(sb.exists(paths.foo))
        XCTAssertFalse(sb.exists(sb.home + "/Library/Caches/com.example.foo"))
        XCTAssertTrue(sb.exists(sb.home + "/Library/Application Support/com.example.foo"), "unticked: your data stays")
        XCTAssertTrue(sb.exists(sb.home + "/Library/Caches/com.example.bar"), "the other app is untouched")

        // History rebuilt from the journal offers exactly what moved, and Undo puts it all back.
        let runs = History.runs(from: Journal.loadAll(home: sb.home), home: sb.home, inTrash: nil)
        let records = runs.flatMap(\.undoable)
        XCTAssertEqual(records.count, plan.items.count)
        let undone = UndoStore.restore(records, home: sb.home, now: { Date() }, progress: { _ in })
        if undone.results.first?.status == .trashUnreadable { throw XCTSkip("the Trash is not readable without Full Disk Access here (VERIFY)") }
        XCTAssertEqual(undone.restoredCount, records.count)
        XCTAssertTrue(sb.exists(paths.foo))
        XCTAssertTrue(sb.exists(sb.home + "/Library/Caches/com.example.foo/c.bin"))
    }

    // MARK: orphans

    func testOrphansNeverPreselectFreshOrNonCacheItems() async throws {
        let sb = try makeSandbox()
        _ = try fakeLibrary(sb, installFoo: false)
        let fresh = await scan(.orphans, sb)
        XCTAssertTrue(ItemSelection.preselected(fresh).isEmpty, "nothing modified in the last 30 days is High in an orphan scan")
        XCTAssertFalse(fresh.items.contains { $0.path.contains("com.example.bar") }, "Bar is installed")

        ageEverything(of: "com.example.foo", sb, days: 40)
        let stale = await scan(.orphans, sb)
        for item in stale.items where ItemSelection.preselected(stale).contains(item.id) {
            XCTAssertTrue(item.kind == .cache || item.kind == .logs, "only caches and logs may be High for an orphan: \(item.path)")
            XCTAssertNotEqual(item.ownerID, "com.example.bar")
        }
        XCTAssertFalse(stale.items.contains { $0.path.contains("com.example.bar") })
    }

    func testAnAppThatIsStillInstalledIsNeverAnOrphan() async throws {
        let sb = try makeSandbox()
        _ = try fakeLibrary(sb)
        ageEverything(of: "com.example.foo", sb, days: 90)
        ageEverything(of: "com.example.bar", sb, days: 90)
        let result = await scan(.orphans, sb)
        XCTAssertFalse(result.items.contains { $0.path.contains("com.example.foo") || $0.path.contains("com.example.bar") })
    }

    // MARK: listing and coverage

    func testAProtectedFolderIsReportedAndNeverCountsAsLooked() throws {
        guard getuid() != 0 else { throw XCTSkip("root ignores folder modes") }
        let sb = try makeSandbox()
        chmod(sb.home + "/Library/Caches", 0o000)
        let library = ResidueScanner.listLibrary(home: sb.home, now: Date(), containersReadable: true)
        let caches = try XCTUnwrap(library.listing(.caches))
        XCTAssertEqual(caches.coverage.state, .protectedByMacOS)
        XCTAssertEqual(caches.coverage.errno, EACCES)
        XCTAssertTrue(caches.entries.isEmpty)
        let coverage = Coverage(places: library.listings.map(\.coverage))
        XCTAssertFalse(coverage.isComplete, "so 'nothing found' is never shown")
        XCTAssertGreaterThanOrEqual(coverage.protectedCount, 1)
        XCTAssertEqual(library.listing(.containers)?.coverage.state, .absent, "a missing folder is a complete answer")
    }

    func testContainersAreListedByNameUnlessTheyMayBeOpened() throws {
        let sb = try makeSandbox()
        let uuid = UUID().uuidString
        let container = sb.home + "/Library/Containers/" + uuid
        try FileManager.default.createDirectory(atPath: container, withIntermediateDirectories: true)
        let meta = try PropertyListSerialization.data(fromPropertyList: ["MCMMetadataIdentifier": "com.example.foo"], format: .xml, options: 0)
        try meta.write(to: URL(fileURLWithPath: container + "/.com.apple.containermanagerd.metadata.plist"))

        let closed = ResidueScanner.listLibrary(home: sb.home, now: Date(), containersReadable: false).listing(.containers)
        XCTAssertEqual(closed?.coverage.state, .protectedByMacOS)
        XCTAssertEqual(closed?.entries.map(\.name), [uuid])
        XCTAssertNil(closed?.entries.first?.containerID, "contents are not opened without consent")

        let open = ResidueScanner.listLibrary(home: sb.home, now: Date(), containersReadable: true).listing(.containers)
        XCTAssertEqual(open?.coverage.state, .read)
        XCTAssertEqual(open?.entries.first?.containerID, "com.example.foo")
    }

    func testListingRecordsLaunchAgentsAndStamps() throws {
        let sb = try makeSandbox()
        let app = try sb.makeApp("Foo", id: "com.example.foo")
        try sb.putLaunchAgent(label: "com.example.foo.agent", program: app + "/Contents/MacOS/Foo")
        sb.put("Library/Caches/com.example.foo/x.bin")
        let library = ResidueScanner.listLibrary(home: sb.home, now: Date(), containersReadable: false)
        let agent = try XCTUnwrap(library.listing(.launchAgents)?.entries.first)
        XCTAssertEqual(agent.launchd?.label, "com.example.foo.agent")
        let cache = try XCTUnwrap(library.listing(.caches)?.entries.first)
        XCTAssertEqual(cache.type, .directory)
        XCTAssertEqual(cache.stamp, ResidueScanner.stamp(of: sb.home + "/Library/Caches/com.example.foo"))
    }

    // MARK: measuring

    func testMeasureCountsFilesAndStaysInsideTheFolder() throws {
        let sb = try makeSandbox()
        sb.put("Library/Caches/com.example.m/a.bin", bytes: 5000)
        sb.put("Library/Caches/com.example.m/sub/b.bin", bytes: 5000)
        sb.put("../outside/big.bin", bytes: 1 << 20)
        let dir = sb.home + "/Library/Caches/com.example.m"
        try FileManager.default.createSymbolicLink(atPath: dir + "/escape", withDestinationPath: sb.root + "/outside")
        let link = sb.home + "/Library/Caches/com.example.link"
        try FileManager.default.createSymbolicLink(atPath: link, withDestinationPath: sb.root + "/outside")

        let sizes = ResidueScanner.measure(paths: [dir, link, sb.home + "/Library/Caches/missing"])
        let m = try XCTUnwrap(sizes[dir])
        XCTAssertEqual(m.state, .measured)
        XCTAssertEqual(m.fileCount, 2, "the link inside is not followed")
        XCTAssertGreaterThanOrEqual(m.bytes, 10_000)
        XCTAssertLessThan(m.bytes, 200_000)
        XCTAssertEqual(sizes[link]?.state, .notMeasured, "a link is not measured")
        XCTAssertEqual(sizes[sb.home + "/Library/Caches/missing"]?.state, .notMeasured)
    }

    func testMeasureReportsTheNewestModificationTime() throws {
        let sb = try makeSandbox()
        let dir = sb.home + "/Library/Caches/com.example.old"
        sb.put("Library/Caches/com.example.old/sub/a.bin")
        for p in [dir + "/sub/a.bin", dir + "/sub", dir] { sb.age(p, days: 40) }
        let m = try XCTUnwrap(ResidueScanner.measure(paths: [dir])[dir])
        let age = Date().timeIntervalSince(try XCTUnwrap(m.newestMtime)) / 86_400
        XCTAssertEqual(age, 40, accuracy: 1)
    }

    func testProtectedContainersAreNotMeasuredWithoutConsent() throws {
        let sb = try makeSandbox()
        let container = sb.home + "/Library/Containers/com.example.foo"
        sb.put("Library/Containers/com.example.foo/Data/x.bin", bytes: 3000)
        XCTAssertEqual(ResidueScanner.measure(paths: [container])[container]?.state, .notMeasured)
        XCTAssertEqual(ResidueScanner.measure(paths: [container], containersReadable: true)[container]?.state, .measured)
    }

    func testStampOfALinkIsTheLinksOwn() throws {
        let sb = try makeSandbox()
        sb.put("../outside/file.txt")
        let link = sb.home + "/Library/Caches/com.example.link"
        try FileManager.default.createSymbolicLink(atPath: link, withDestinationPath: sb.root + "/outside")
        XCTAssertEqual(ResidueScanner.stamp(of: link)?.type, .symlink)
        XCTAssertNil(ResidueScanner.stamp(of: sb.home + "/Library/Caches/missing"))
    }
}
