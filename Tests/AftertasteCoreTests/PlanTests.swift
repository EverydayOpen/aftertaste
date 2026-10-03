import Foundation
import XCTest
@testable import AftertasteCore

final class PlanTests: XCTestCase {
    let h = T.home

    // MARK: building blocks

    func item(_ root: LibraryRoot, _ name: String, tier: Tier, kind: ResidueKind = .cache, owner: String = "com.example.notes", inode: UInt64? = nil,
              size: UInt64 = 1000, blocked: BlockReason? = nil, rule: String = "U3") -> ResidueItem {
        let path = GuardPolicy.normalize(root.path(home: h) + "/" + name)
        return ResidueItem(path: path, ownerID: owner, ruleID: rule, root: root, kind: kind, tier: tier, size: size, sizeState: .measured,
                           stamp: inode.map { T.stamp($0) }, blocked: blocked, why: "why")
    }

    func result(_ items: [ResidueItem], kind: ScanKind = .orphans, run: RunState = .notRunning, owner: AppIdentity? = nil) -> ScanResult {
        let o = owner ?? T.app("com.example.notes", "Notes Pro")
        return ScanResult(scannedAt: T.now, kind: kind, groups: [ResidueGroup(owner: o, isOrphan: kind == .orphans, runState: run, items: items)],
                          coverage: Coverage(), home: h, osVersion: "26.1")
    }

    func plan(_ r: ScanResult, _ ticked: Set<String>? = nil, _ mode: TrashPlanner.Mode = .bulk(acknowledgedMedium: false)) -> TrashPlan {
        TrashPlanner.plan(from: r, ticked: ticked ?? Set(r.items.map(\.id)), mode: mode, now: T.now, runID: "r1")
    }

    // MARK: ItemSelection

    func testPreselectedIsHighOnly() {
        let items = [item(.caches, "a", tier: .high), item(.caches, "b", tier: .medium), item(.caches, "c", tier: .low), item(.caches, "d", tier: .handsOff),
                     item(.caches, "e", tier: .needsAdmin), item(.caches, "f", tier: .high)]
        let r = result(items)
        XCTAssertEqual(ItemSelection.preselected(r), Set([items[0].id, items[5].id]))
        for tier in Tier.allCases where tier != .high {
            let t = result([item(.caches, "x", tier: tier)])
            XCTAssertTrue(ItemSelection.preselected(t).isEmpty, "\(tier)")
        }
    }

    func testToggleIgnoresRowsWithoutACheckbox() {
        let items = [item(.caches, "a", tier: .high), item(.caches, "b", tier: .low), item(.caches, "c", tier: .handsOff), item(.caches, "d", tier: .needsAdmin)]
        let r = result(items)
        var t = Set<String>()
        for i in items { t = ItemSelection.toggle(t, id: i.id, in: r) }
        XCTAssertEqual(t, [items[0].id, items[1].id])
        XCTAssertEqual(ItemSelection.toggle(t, id: items[0].id, in: r), [items[1].id], "toggling again unticks")
        XCTAssertEqual(ItemSelection.toggle(t, id: "/nowhere", in: r), t)
    }

    func testSelectHighAndIncludeMyData() {
        let a = T.app("com.example.a", "A App"), b = T.app("com.example.b", "B App")
        let ia = [item(.caches, "a1", tier: .high, owner: a.bundleID), item(.applicationSupport, "a2", tier: .medium, kind: .yourData, owner: a.bundleID),
                  item(.applicationSupport, "a3", tier: .low, kind: .yourData, owner: a.bundleID)]
        let ib = [item(.caches, "b1", tier: .high, owner: b.bundleID), item(.applicationSupport, "b2", tier: .medium, kind: .yourData, owner: b.bundleID)]
        let r = ScanResult(scannedAt: T.now, kind: .orphans, groups: [ResidueGroup(owner: a, isOrphan: true, items: ia), ResidueGroup(owner: b, isOrphan: true, items: ib)],
                           coverage: Coverage(), home: h, osVersion: "26.1")
        XCTAssertEqual(ItemSelection.selectHigh([], in: r), [ia[0].id, ib[0].id])
        let on = ItemSelection.includeMyData([], owner: a.bundleID, on: true, in: r)
        XCTAssertEqual(on, [ia[1].id], "only that owner's Medium items; never Review")
        XCTAssertEqual(ItemSelection.includeMyData(on.union([ib[1].id]), owner: a.bundleID, on: false, in: r), [ib[1].id])
    }

    // MARK: TrashPlanner

    func testRunIDShape() {
        XCTAssertEqual(TrashPlanner.newRunID(now: Civil.date(year: 2026, month: 10, day: 3, hour: 10, minute: 15), random: 0x3fa9c1), "20261003T101500Z-3fa9c1")
        XCTAssertEqual(TrashPlanner.newRunID(now: T.now, random: 0xAB), "20261003T120000Z-0000ab")
        XCTAssertEqual(TrashPlanner.newRunID(now: T.now, random: 0xFFFF_FFFF), "20261003T120000Z-ffffff")
    }

    func testBulkPlansHighAlwaysMediumOnlyWhenAcknowledgedAndNeverReview() {
        let items = [item(.caches, "h", tier: .high), item(.applicationSupport, "m", tier: .medium, kind: .yourData), item(.applicationSupport, "l", tier: .low, kind: .yourData)]
        let r = result(items)
        let noAck = plan(r)
        XCTAssertEqual(noAck.items.map(\.tier), [.high])
        XCTAssertFalse(noAck.acknowledgedMedium)
        XCTAssertEqual(noAck.skipped.count, 2)
        let ack = plan(r, nil, .bulk(acknowledgedMedium: true))
        XCTAssertEqual(ack.items.map(\.tier), [.high, .medium])
        XCTAssertTrue(ack.acknowledgedMedium)
        XCTAssertTrue(ack.skipped.contains { $0.path == items[2].path && $0.reason.contains("one at a time") })
        XCTAssertFalse(plan(result([items[0]]), nil, .bulk(acknowledgedMedium: true)).acknowledgedMedium, "nothing Medium to acknowledge")
        XCTAssertEqual(ack.kind, .orphans)
        XCTAssertEqual(ack.runID, "r1")
        XCTAssertEqual(ack.createdAt, T.now)
        XCTAssertEqual(ack.owners.map(\.bundleID), ["com.example.notes"])
    }

    func testOnlyTickedItemsAreEverPlanned() {
        let items = [item(.caches, "a", tier: .high), item(.caches, "b", tier: .high)]
        let r = result(items)
        XCTAssertEqual(plan(r, [items[0].id]).items.map(\.path), [items[0].path])
        XCTAssertTrue(plan(r, []).items.isEmpty)
        XCTAssertTrue(plan(r, ["/not/in/the/scan"]).items.isEmpty)
    }

    func testSingleReviewPlansExactlyOneReviewItem() {
        let items = [item(.applicationSupport, "l1", tier: .low, kind: .yourData), item(.applicationSupport, "l2", tier: .low, kind: .yourData), item(.caches, "h", tier: .high)]
        let r = result(items)
        let one = plan(r, [], .singleReview(id: items[0].id))
        XCTAssertEqual(one.items.map(\.path), [items[0].path])
        XCTAssertEqual(plan(r, Set(items.map(\.id)), .singleReview(id: items[1].id)).items.map(\.path), [items[1].path], "the other ticks do not tag along")
        XCTAssertTrue(plan(r, [], .singleReview(id: items[2].id)).items.isEmpty, "a High item is not a Review item")
        XCTAssertTrue(plan(r, [], .singleReview(id: "/nowhere")).items.isEmpty)
        XCTAssertFalse(plan(r, [], .singleReview(id: "/nowhere")).skipped.isEmpty)
    }

    func testRunningOrUnknownGroupsAreDroppedWithAReason() {
        let items = [item(.caches, "a", tier: .high)]
        for (state, text) in [(RunState.running, "Running"), (.unknown, "Could not tell")] {
            let p = plan(result(items, run: state))
            XCTAssertTrue(p.items.isEmpty)
            XCTAssertTrue(p.skipped.first?.reason.contains(text) ?? false, "\(state)")
        }
    }

    func testNothingBlockedNotEvenWithAForgedTier() {
        let forged = [item(.caches, "a", tier: .high, blocked: .neverList), item(.systemCaches, "b", tier: .high, kind: .system), item(.launchAgents, "c", tier: .high, kind: .launchItem),
                      item(.caches, "d", tier: .handsOff), item(.caches, "e", tier: .needsAdmin)]
        var withAdmin = forged
        withAdmin[1].requiresAdmin = true
        let p = plan(result(withAdmin), nil, .bulk(acknowledgedMedium: true))
        XCTAssertTrue(p.items.isEmpty)
        XCTAssertEqual(p.skipped.count, 5)
    }

    func testDuplicatesByInodeAndChildrenOfAPlannedParentAreDropped() {
        let a = item(.caches, "a", tier: .high, inode: 1)
        let dup = item(.httpStorages, "a", tier: .high, inode: 1)
        let b = item(.caches, "b", tier: .high, inode: 2)
        var child = item(.caches, "b/inner", tier: .high, inode: 3)
        child.path = b.path + "/inner"
        let p = plan(result([a, dup, b, child]))
        XCTAssertEqual(Set(p.items.map(\.path)), [a.path, b.path])
        XCTAssertEqual(p.skipped.count, 2)
        // The same inode on another device is another file.
        var other = item(.httpStorages, "z", tier: .high)
        other.stamp = FileStamp(device: 2, inode: 1, type: .directory, size: 0, mtimeSeconds: 0)
        XCTAssertEqual(plan(result([a, other])).items.count, 2)
    }

    func testExecutionOrder() {
        let app = T.app("com.example.notes", "Notes Pro")
        var bundle = item(.caches, "x", tier: .high, kind: .app, rule: "APP")
        bundle.path = "/Applications/Notes Pro.app"
        let items = [item(.preferences, "p.plist", tier: .high, kind: .settings), item(.caches, "c", tier: .high), item(.logs, "l", tier: .high, kind: .logs),
                     item(.savedState, "s", tier: .high, kind: .state), item(.cookies, "k", tier: .high, kind: .cookies),
                     item(.applicationSupport, "m", tier: .medium, kind: .yourData), item(.preferences, "q.plist", tier: .medium, kind: .settings)]
        let r = result([bundle] + items.reversed(), kind: .app, owner: app)
        let p = plan(r, nil, .bulk(acknowledgedMedium: true))
        XCTAssertEqual(p.items.first?.ruleID, "APP", "the app goes first")
        XCTAssertEqual(p.items.dropFirst().map(\.kind), [.cookies, .state, .logs, .cache, .settings, .settings, .yourData])
        XCTAssertEqual(p.items.map(\.tier), [.high, .high, .high, .high, .high, .high, .medium, .medium], "High before Medium")
    }

    func testInstalledAppsFilesStayUnlessTheAppGoesInTheSameRun() {
        let app = T.app("com.example.notes", "Notes Pro")
        var bundle = item(.caches, "x", tier: .high, kind: .app, rule: "APP")
        bundle.path = "/Applications/Notes Pro.app"
        let cache = item(.caches, "c", tier: .high)
        let review = item(.applicationSupport, "r", tier: .low, kind: .yourData)
        let r = result([bundle, cache, review], kind: .app, owner: app)
        XCTAssertEqual(plan(r).items.map(\.path), [bundle.path, cache.path])
        let noBundle = plan(r, [cache.id])
        XCTAssertTrue(noBundle.items.isEmpty, "unticking the app keeps its files too")
        XCTAssertTrue(noBundle.skipped.first?.reason.contains("still installed") ?? false)
        XCTAssertTrue(plan(r, [], .singleReview(id: review.id)).items.isEmpty, "a lone Review item cannot go while the app stays")
        // Once the app is gone (no bundle row) the leftovers are plain leftovers.
        let gone = result([cache, review], kind: .app, owner: app)
        XCTAssertEqual(plan(gone).items.map(\.path), [cache.path])
        XCTAssertEqual(plan(gone, [], .singleReview(id: review.id)).items.map(\.path), [review.path])
    }

    func testPlanIsPureAndDeterministic() {
        let items = (0..<20).map { item(.caches, "c\($0)", tier: .high, inode: UInt64($0 + 1)) }
        let r = result(items.shuffled())
        XCTAssertEqual(plan(r), plan(r))
        XCTAssertEqual(plan(r).items.map(\.path), items.map(\.path).sorted())
    }

    // MARK: GuardPolicy

    func check(_ path: String, parent: String? = nil, keep: [String] = [], app: Bool = false) -> GuardVerdict? {
        let p = GuardPolicy.normalize(path)
        let par = parent ?? "/" + p.split(separator: "/").dropLast().joined(separator: "/")
        return GuardPolicy.check(path: path, canonicalParent: par, home: h, keep: keep, isAppBundle: app)
    }

    func testGuardAllowsOnlyChildrenOfAllowListedRoots() {
        XCTAssertNil(check("\(h)/Library/Caches/com.example.notes"))
        XCTAssertNil(check("\(h)/Library/Preferences/com.example.notes.plist"))
        XCTAssertNil(check("\(h)/Library/Preferences/ByHost/com.example.notes.A.plist"))
        XCTAssertNil(check("\(h)/Library/Logs/DiagnosticReports/Notes_1.ips"))
        XCTAssertNil(check("\(h)/Library/Application Support/com.apple.sharedfilelist/com.apple.LSSharedFileList.ApplicationRecentDocuments/com.example.notes.sfl2"))
        guard case .blocked(.neverList, _)? = check("\(h)/Library/Caches/com.example.notes/deep/file") else { return XCTFail("a grandchild is not an item") }
        guard case .blocked(.neverList, _)? = check("\(h)/Library/Caches") else { return XCTFail("a root itself") }
        guard case .blocked(.neverList, _)? = check("\(h)/Library/Preferences/ByHost") else { return XCTFail("a nested root") }
        guard case .blocked(.neverList, _)? = check("\(h)/Library/Logs/DiagnosticReports") else { return XCTFail("a nested root") }
        guard case .blocked(.neverList, _)? = check("\(h)/Documents/thesis.pdf") else { return XCTFail("Documents") }
        guard case .blocked(.neverList, _)? = check("\(h)/.config/tool") else { return XCTFail("dotdirs are not scanned") }
        guard case .blocked(.neverList, _)? = check("/Users/janet/Library/Caches/x") else { return XCTFail("other users") }
    }

    func testGuardRefusesLinksAndSpellingTricks() {
        guard case .blocked(.linkEscapes, _)? = check("\(h)/Library/Caches/x", parent: "/Volumes/Elsewhere/Caches") else { return XCTFail("parent is a link") }
        guard case .blocked(.neverList, _)? = check("\(h)/Library/Caches/../Preferences/x", parent: "\(h)/Library/Caches/../Preferences") else { return XCTFail("..") }
        guard case .blocked(.neverList, _)? = check("relative/path", parent: "relative") else { return XCTFail("relative") }
        guard case .blocked(.neverList, _)? = check("/", parent: "/") else { return XCTFail("root") }
        // The firmlink spelling is the same item.
        XCTAssertNil(check("/System/Volumes/Data\(h)/Library/Caches/com.example.notes", parent: "\(h)/Library/Caches"))
        XCTAssertNil(check("\(h)//Library//Caches/com.example.notes/", parent: "\(h)/Library/Caches/"))
        XCTAssertNil(check("\(h)/library/caches/com.example.notes", parent: "\(h)/Library/Caches"), "case-insensitive volume")
    }

    func testGuardAppliesTheNeverListAndKeepList() {
        guard case .blocked(.appleOwned, _)? = check("\(h)/Library/Caches/com.apple.Safari") else { return XCTFail("Apple") }
        guard case .blocked(.iCloud, _)? = check("\(h)/Library/Mobile Documents/com~apple~CloudDocs") else { return XCTFail("iCloud") }
        guard case .blocked(.ownCopy, _)? = check("\(h)/Library/Application Support/Aftertaste") else { return XCTFail("ours") }
        guard case .blocked(.neverList, _)? = check("\(h)/Library/Caches/com.example.notes", keep: ["com.example.notes"]) else { return XCTFail("keep") }
        guard case .blocked(.neverList, _)? = check("\(h)/Library/Developer/Xcode") else { return XCTFail("Developer") }
        XCTAssertNil(check("\(h)/Library/Caches/com.apple.dt.Xcode"), "the allow-list")
    }

    func testGuardSystemRootsAreNeedsAdmin() {
        for p in ["/Library/Application Support/com.example.notes", "/Library/LaunchDaemons/com.example.notes.plist", "/Library/PrivilegedHelperTools/com.example.notes",
                  "/private/var/db/receipts/com.example.notes.bom", "/Library/Caches/com.example.notes"] {
            guard case .blocked(.needsAdmin, _)? = check(p) else { return XCTFail(p) }
        }
        guard case .blocked(.neverList, _)? = check("/System/Library/Caches/x") else { return XCTFail("/System") }
        guard case .blocked(.neverList, _)? = check("/usr/local/bin/tool") else { return XCTFail("/usr") }
    }

    func testGuardAppBundles() {
        for ok in ["/Applications/Orbit.app", "/Applications/Utilities/Orbit.app", "/Applications/Setapp/Orbit.app", "/Applications/Suite/Orbit.app",
                   "\(h)/Applications/Orbit.app", "\(h)/Applications/Suite/Orbit.app", "/Volumes/Ext/Applications/Orbit.app", "/Volumes/Ext/Applications/Suite/Orbit.app"] {
            XCTAssertNil(check(ok, app: true), ok)
        }
        for bad in ["/Applications/Other.app/Inner.app", "\(h)/Applications/Other.app/Inner.app", "/Volumes/Ext/Applications/Other.app/Inner.app",
                    "/Applications/Utilities/Other.app/Inner.app", "/Applications/A/B/Orbit.app", "\(h)/Downloads/Orbit.app", "/Applications/Orbit.txt", "/Applications/.app", "\(h)/Desktop/Orbit.app", "/System/Applications/Notes.app",
                    "/Volumes/Ext/Orbit.app", "/Applications/Orbit.app/Contents/MacOS/Orbit", "\(h)/Library/Caches/Orbit.app"] {
            XCTAssertNotNil(check(bad, app: true), bad)
        }
        XCTAssertNotNil(check("/Applications/Orbit.app", keep: ["/Applications/Orbit.app"], app: true))
        XCTAssertEqual(GuardPolicy.appFolders(home: h), ["/Applications", "/Applications/Utilities", "/Applications/Setapp", "\(h)/Applications"])
    }

    func testNormalize() {
        XCTAssertEqual(GuardPolicy.normalize("/System/Volumes/Data/Users/jane/x/"), "/Users/jane/x")
        XCTAssertEqual(GuardPolicy.normalize("/System/Volumes/Data"), "/")
        XCTAssertEqual(GuardPolicy.normalize("//a///b//"), "/a/b")
        XCTAssertEqual(GuardPolicy.normalize("/"), "/")
        XCTAssertEqual(GuardPolicy.normalize(""), "")
        XCTAssertEqual(GuardPolicy.normalize("/System/Library/x"), "/System/Library/x", "only the Data firmlink prefix is removed")
        XCTAssertEqual(GuardPolicy.normalize("~/Library/x/"), "~/Library/x")
    }

    // MARK: Stamps and RunningCheck

    func testStampsCompareIdentityNotDirectorySize() {
        let a = FileStamp(device: 1, inode: 5, type: .file, size: 10, mtimeSeconds: 100, mtimeNanoseconds: 5, linkCount: 1)
        XCTAssertTrue(Stamps.same(a, a))
        var b = a; b.size = 11
        XCTAssertFalse(Stamps.same(a, b), "a file that changed size")
        var dirA = a; dirA.type = .directory; dirA.size = 0
        var dirB = dirA; dirB.size = 4096
        XCTAssertTrue(Stamps.same(dirA, dirB), "directory size is not part of the identity")
        let mutations: [(inout FileStamp) -> Void] = [{ $0.device = 2 }, { $0.inode = 6 }, { $0.type = .symlink }, { $0.mtimeSeconds = 101 },
                                                       { $0.mtimeNanoseconds = 6 }, { $0.linkCount = 2 }]
        for mutate in mutations {
            var c = a
            mutate(&c)
            XCTAssertFalse(Stamps.same(a, c))
        }
    }

    func testRunningCheck() {
        let app = T.app("com.example.orbit", "Orbit", path: "/Applications/Orbit.app", embedded: ["com.example.orbit.helper"], helpers: ["com.example.orbit.agent"])
        func state(_ snap: RunningSnapshot, item: String = "\(h)/Library/Caches/com.example.orbit", owner: AppIdentity? = app) -> RunState {
            RunningCheck.state(owner: owner, itemPath: item, snapshot: snap)
        }
        XCTAssertEqual(state(RunningSnapshot()), .notRunning)
        XCTAssertEqual(state(RunningSnapshot(readable: false)), .unknown, "unreadable means unknown, never 'not running'")
        XCTAssertEqual(state(RunningSnapshot(bundleIDs: ["com.example.orbit"])), .running)
        XCTAssertEqual(state(RunningSnapshot(bundleIDs: ["COM.EXAMPLE.ORBIT"])), .running)
        XCTAssertEqual(state(RunningSnapshot(bundleIDs: ["com.example.orbit.helper"])), .running)
        XCTAssertEqual(state(RunningSnapshot(bundleIDs: ["com.example.orbit.agent"])), .running)
        XCTAssertEqual(state(RunningSnapshot(bundleIDs: ["com.example.other"])), .notRunning)
        XCTAssertEqual(state(RunningSnapshot(executablePaths: ["/Applications/Orbit.app/Contents/MacOS/Orbit"])), .running)
        XCTAssertEqual(state(RunningSnapshot(executablePaths: ["/applications/orbit.app/Contents/Helpers/h"])), .running)
        XCTAssertEqual(state(RunningSnapshot(executablePaths: ["/Applications/Orbit.appx/x"])), .notRunning, "a path prefix is not a bundle")
        XCTAssertEqual(state(RunningSnapshot(executablePaths: ["\(h)/Library/Caches/com.example.orbit/tool"])), .running)
        XCTAssertEqual(state(RunningSnapshot(executablePaths: ["\(h)/Library/Caches/com.example.orbit"])), .running)
        XCTAssertEqual(state(RunningSnapshot(executablePaths: ["\(h)/Library/Caches/com.example.orbit2/tool"])), .notRunning)
        XCTAssertEqual(state(RunningSnapshot(executablePaths: ["/usr/bin/true"]), owner: nil), .notRunning)
        let orphan = T.app("com.example.gone", "Gone", path: "")
        XCTAssertEqual(state(RunningSnapshot(executablePaths: ["/usr/bin/true"]), item: "", owner: orphan), .notRunning, "an empty path matches nothing")
    }
}
