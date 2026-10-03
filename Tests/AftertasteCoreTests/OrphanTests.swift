import Foundation
import XCTest
@testable import AftertasteCore

final class OrphanTests: XCTestCase {
    let gone = "com.example.gone"

    /// Two independent kinds of evidence (an ID-named plist and an ID-named folder) for an app nothing installed owns.
    func basicOrphanLibrary() -> Lib {
        var lib = Lib()
        lib.apps = [T.app("org.sample.present", "Present App")]
        lib.add(.preferences, "\(gone).plist", type: .file)
        lib.add(.caches, gone)
        lib.add(.logs, gone)
        lib.add(.savedState, "\(gone).savedState")
        lib.add(.applicationSupport, gone)
        return lib
    }

    func testOrphanTiersFollowTheOrphanCaps() {
        var lib = basicOrphanLibrary()
        lib.sizes[lib.path(.caches, gone)] = T.sized(1000)
        lib.sizes[lib.path(.logs, gone)] = T.sized(1000)
        let r = lib.analyze(.orphans)
        XCTAssertEqual(r.groups.count, 1)
        let g = r.groups[0]
        XCTAssertTrue(g.isOrphan)
        XCTAssertEqual(g.owner.bundleID, gone)
        XCTAssertEqual(g.owner.displayName, "Gone", "the label is made up from the ID, only for display")
        XCTAssertEqual(g.owner.bundlePath, "")
        let t = r.tiers()
        // High only for a cache or log with an exact ID name, no live owner, untouched for 30 days.
        XCTAssertEqual(t[lib.path(.caches, gone)], .high)
        XCTAssertEqual(t[lib.path(.logs, gone)], .high)
        // Everything else from an orphan scan is Medium at best (preferences and saved state are High only in uninstall-now).
        XCTAssertEqual(t[lib.path(.preferences, "\(gone).plist")], .medium)
        XCTAssertEqual(t[lib.path(.savedState, "\(gone).savedState")], .medium)
        XCTAssertEqual(t[lib.path(.applicationSupport, gone)], .medium)
        XCTAssertTrue(g.items.allSatisfy { $0.evidence.contains { $0.kind == .noLiveOwner } })
        XCTAssertTrue(r.item(lib.path(.caches, gone))?.why.contains("no installed app has this ID") ?? false)
        XCTAssertTrue(r.item(lib.path(.caches, gone))?.evidence.contains { $0.kind == .staleMtime } ?? false)
    }

    func testRecentlyModifiedCacheIsNotHigh() {
        var lib = Lib()
        lib.add(.preferences, "\(gone).plist", type: .file)
        lib.addEntry(.caches, gone, daysOld: 5)
        XCTAssertEqual(lib.analyze(.orphans).item(lib.path(.caches, gone))?.tier, .medium)
        // The newest file inside counts too, not just the folder's own mtime.
        var lib2 = Lib()
        lib2.add(.preferences, "\(gone).plist", type: .file)
        lib2.add(.caches, gone, daysOld: 200)
        lib2.sizes[lib2.path(.caches, gone)] = T.sized(1000, newestDaysOld: 2)
        XCTAssertEqual(lib2.analyze(.orphans).item(lib2.path(.caches, gone))?.tier, .medium)
        lib2.sizes[lib2.path(.caches, gone)] = T.sized(1000, newestDaysOld: 90)
        XCTAssertEqual(lib2.analyze(.orphans).item(lib2.path(.caches, gone))?.tier, .high)
        // Unknown age is not "old".
        var lib3 = Lib()
        lib3.add(.preferences, "\(gone).plist", type: .file)
        lib3.entries[.caches] = [LibraryEntry(name: gone, type: .directory, stamp: nil)]
        XCTAssertEqual(lib3.analyze(.orphans).item(lib3.path(.caches, gone))?.tier, .medium)
    }

    func testAnInstalledOwnerMeansNoOrphan() {
        var lib = basicOrphanLibrary()
        lib.apps.append(T.app(gone, "Gone Back"))
        XCTAssertTrue(lib.analyze(.orphans).groups.isEmpty)
        // A helper or embedded ID of an installed app counts as owned too.
        var lib2 = basicOrphanLibrary()
        lib2.apps.append(T.app("com.example.suite", "Suite", embedded: [gone]))
        XCTAssertTrue(lib2.analyze(.orphans).groups.isEmpty)
        // And a dotted child of an installed ID is that app's own file.
        var lib3 = Lib()
        lib3.apps = [T.app("com.example.suite", "Suite")]
        lib3.add(.preferences, "com.example.suite.helper2.plist", type: .file)
        lib3.add(.caches, "com.example.suite.helper2")
        XCTAssertTrue(lib3.analyze(.orphans).groups.isEmpty)
    }

    func testOneKindOfEvidenceIsNotEnoughWithoutTheInventory() {
        var lib = Lib()
        lib.add(.preferences, "\(gone).plist", type: .file)
        XCTAssertTrue(lib.analyze(.orphans).groups.isEmpty)
        var lib2 = Lib()
        lib2.add(.caches, gone)
        XCTAssertTrue(lib2.analyze(.orphans).groups.isEmpty)
        // Name-only folders never create a candidate.
        var lib3 = Lib()
        lib3.add(.applicationSupport, "Spotify", "Orbit Meet", "Something Else")
        lib3.add(.logs, "Spotify")
        XCTAssertTrue(lib3.analyze(.orphans).groups.isEmpty)
    }

    func testEachCorroborationKindCounts() {
        func orphans(_ build: (inout Lib) -> Void) -> Bool {
            var lib = Lib()
            build(&lib)
            return !lib.analyze(.orphans).groups.isEmpty
        }
        XCTAssertTrue(orphans { $0.add(.receipts, "\(gone).pkg.bom", type: .file); $0.add(.caches, gone) }, "receipt + folder")
        XCTAssertTrue(orphans { $0.addAgent(name: "\(gone).agent.plist", label: "\(gone).agent", program: "/Applications/Gone.app/x", exists: false); $0.add(.caches, gone) },
                      "dangling launch agent + folder")
        XCTAssertFalse(orphans { $0.addAgent(name: "\(gone).agent.plist", label: "\(gone).agent", program: "/usr/bin/true", exists: true) },
                       "a launch agent whose program still exists proves nothing")
        XCTAssertTrue(orphans { $0.addEntry(.containers, "AAAAAAAA-0000-1111-2222-333333333333", container: gone); $0.add(.caches, gone) },
                      "container metadata naming the ID + folder")
        XCTAssertTrue(orphans { $0.add(.preferences, "\(gone).plist", type: .file); $0.add(.httpStorages, gone) }, "ID-named plist next to a folder")
        XCTAssertFalse(orphans { $0.add(.caches, gone, "\(gone).helper") }, "the same kind twice is still one kind")
    }

    func testInventoryAbsenceIsEnoughButOnlyAfterAFewDays() {
        var lib = Lib()
        let quill = T.app("com.example.quill", "Quill Editor", exec: "Quill", team: "QQQQQQQQQQ", embedded: ["com.example.quill.helper"])
        lib.add(.caches, "com.example.quill")
        lib.sizes[lib.path(.caches, "com.example.quill")] = T.sized(1000)
        lib.add(.applicationSupport, "Quill Editor", "Quill Editors")
        lib.inventory = [InventoryRecord(identity: quill, firstSeen: T.now.addingTimeInterval(-90 * T.day), lastSeen: T.now.addingTimeInterval(-10 * T.day))]
        let r = lib.analyze(.orphans)
        XCTAssertEqual(r.coverage.recentlyRemovedCount, 0)
        XCTAssertEqual(r.groups.count, 1)
        XCTAssertEqual(r.groups[0].owner.displayName, "Quill Editor", "a recorded name is used")
        XCTAssertEqual(r.item(lib.path(.caches, "com.example.quill"))?.tier, .high)
        XCTAssertTrue(r.item(lib.path(.caches, "com.example.quill"))?.evidence.contains { $0.kind == .inventoryAbsent } ?? false)
        XCTAssertTrue(r.item(lib.path(.caches, "com.example.quill"))?.why.contains("Last seen installed on 2026-09-23") ?? false)
        // A recorded name may match a folder (Review), at a boundary only.
        XCTAssertEqual(r.item(lib.path(.applicationSupport, "Quill Editor"))?.tier, .low)
        XCTAssertNil(r.item(lib.path(.applicationSupport, "Quill Editors")), "not at a boundary")
        // Seen yesterday: an update in flight, not a removal.
        lib.inventory = [InventoryRecord(identity: quill, firstSeen: T.now.addingTimeInterval(-90 * T.day), lastSeen: T.now.addingTimeInterval(-1 * T.day))]
        let recent = lib.analyze(.orphans)
        XCTAssertTrue(recent.groups.isEmpty)
        // ... and the scan says it held it back instead of claiming an all-clear.
        XCTAssertEqual(recent.coverage.recentlyRemovedCount, 1)
        XCTAssertFalse(recent.coverage.isComplete)
        XCTAssertFalse(recent.isCleanAndComplete)
        XCTAssertEqual(PlanText.emptyState(recent), "Nothing found yet. 1 app removed less than 3 days ago is not listed yet. Scan again later.")
        // And the inventory never makes an app live: an installed copy still wins.
        lib.inventory = [InventoryRecord(identity: quill, firstSeen: T.now.addingTimeInterval(-90 * T.day), lastSeen: T.now.addingTimeInterval(-10 * T.day))]
        lib.apps = [quill]
        XCTAssertTrue(lib.analyze(.orphans).groups.isEmpty)
    }

    func testInventoryMapsEmbeddedIDsToTheAppAndGroupsThem() {
        var lib = Lib()
        let quill = T.app("com.example.quill", "Quill Editor", embedded: ["com.example.quill.shared"])
        lib.add(.caches, "com.example.quill.shared")
        lib.add(.preferences, "com.example.quill.plist", type: .file)
        lib.inventory = [InventoryRecord(identity: quill, firstSeen: T.now.addingTimeInterval(-90 * T.day), lastSeen: T.now.addingTimeInterval(-10 * T.day))]
        let r = lib.analyze(.orphans)
        XCTAssertEqual(r.groups.count, 1)
        XCTAssertEqual(r.groups[0].owner.bundleID, "com.example.quill")
        XCTAssertEqual(r.groups[0].items.count, 2)
    }

    func testHelpersAndDottedChildrenGroupUnderOneBaseID() {
        var lib = Lib()
        lib.add(.preferences, "\(gone).plist", "\(gone).helper.plist", type: .file)
        lib.add(.caches, gone, "\(gone).helper", "\(gone).ShipIt")
        lib.sizes[lib.path(.caches, gone)] = T.sized(1000)
        lib.add(.savedState, "\(gone).helper.savedState")
        let r = lib.analyze(.orphans)
        XCTAssertEqual(r.groups.count, 1)
        XCTAssertEqual(r.groups[0].owner.bundleID, gone)
        XCTAssertEqual(r.groups[0].items.count, 6)
        // Dotted children are not "exact ID names": Medium, never High, in an orphan scan.
        XCTAssertEqual(r.item(lib.path(.caches, "\(gone).ShipIt"))?.tier, .medium)
        XCTAssertEqual(r.item(lib.path(.caches, gone))?.tier, .high)
    }

    func testTwoOrphansStaySeparate() {
        var lib = Lib()
        lib.add(.preferences, "com.example.one.plist", "com.example.two.plist", type: .file)
        lib.add(.caches, "com.example.one", "com.example.two")
        let r = lib.analyze(.orphans)
        XCTAssertEqual(r.groups.map(\.owner.bundleID).sorted(), ["com.example.one", "com.example.two"])
        for g in r.groups { XCTAssertEqual(g.items.count, 2) }
    }

    func testAMissingVolumeOrUnreadableAppFolderCapsEverythingAtReview() {
        var lib = basicOrphanLibrary()
        lib.volumeMayBeMissing = true
        let r = lib.analyze(.orphans)
        XCTAssertFalse(r.items.isEmpty)
        for item in r.items { XCTAssertTrue(item.tier == .low || item.tier == .handsOff, "\(item.path) \(item.tier)") }
        XCTAssertTrue(r.items.allSatisfy { $0.why.contains("may be on a drive that is not connected") })
        XCTAssertTrue(ItemSelection.preselected(r).isEmpty)
        XCTAssertTrue(r.coverage.volumeMayBeMissing)
        var lib2 = basicOrphanLibrary()
        lib2.unreadableAppFolders = ["/Volumes/Backup/Applications"]
        for item in lib2.analyze(.orphans).items { XCTAssertNotEqual(item.tier, .high); XCTAssertNotEqual(item.tier, .medium) }
    }

    func testRunningAppIsNotAnOrphan() {
        let lib = basicOrphanLibrary()
        let running = RunningSnapshot(bundleIDs: [gone], executablePaths: [], readable: true)
        XCTAssertTrue(Scan.analyze(lib.input(.orphans, running: running)).groups.isEmpty)
    }

    func testAppleSharedAndOwnNamesAreNeverOrphans() {
        var lib = Lib()
        for id in ["com.apple.foo", "com.google.Keystone", "com.google.SoftwareUpdate", "org.sparkle-project.Sparkle", "io.github.everydayopen.aftertaste"] {
            lib.add(.preferences, "\(id).plist", type: .file)
            lib.add(.caches, id)
        }
        XCTAssertTrue(lib.analyze(.orphans).groups.isEmpty)
    }

    func testGroupContainersNeedATeamIDTheOrphanDoesNotHave() {
        var lib = basicOrphanLibrary()
        lib.add(.groupContainers, "UBF8T346G9.Office", "group.\(gone)")
        lib.sizes[lib.path(.groupContainers, "group.\(gone)")] = T.sized(1000)
        let r = lib.analyze(.orphans)
        XCTAssertNil(r.item(lib.path(.groupContainers, "UBF8T346G9.Office")))
        XCTAssertEqual(r.item(lib.path(.groupContainers, "group.\(gone)"))?.tier, .low, "a group named for the ID is Review at most")
    }

    func testSharedTeamStaysWithTheInstalledApps() {
        var lib = Lib()
        let word = T.app("com.example.word", "Word Thing", team: "UBF8T346G9", groups: ["UBF8T346G9.Office"])
        let excel = T.app("com.example.excel", "Excel Thing", team: "UBF8T346G9", groups: ["UBF8T346G9.Office"])
        lib.apps = [excel]
        lib.add(.preferences, "com.example.word.plist", type: .file)
        lib.add(.caches, "com.example.word")
        lib.sizes[lib.path(.caches, "com.example.word")] = T.sized(1000)
        lib.add(.groupContainers, "UBF8T346G9.Office")
        lib.sizes[lib.path(.groupContainers, "UBF8T346G9.Office")] = T.sized(1000)
        lib.inventory = [InventoryRecord(identity: word, firstSeen: T.now.addingTimeInterval(-90 * T.day), lastSeen: T.now.addingTimeInterval(-10 * T.day))]
        let r = lib.analyze(.orphans)
        XCTAssertEqual(r.item(lib.path(.groupContainers, "UBF8T346G9.Office"))?.tier, .handsOff)
        XCTAssertEqual(r.item(lib.path(.groupContainers, "UBF8T346G9.Office"))?.blocked, .sharedWithInstalled)
        // Excel from the same developer is installed: Word's cache is still listed as Word's own, but is not preselected.
        let cache = r.item(lib.path(.caches, "com.example.word"))
        XCTAssertEqual(cache?.tier, .medium, "capped, not rejected")
        XCTAssertTrue(cache?.evidence.contains(Evidence(.sameTeamInstalled, "Excel Thing")) ?? false)
        XCTAssertTrue(cache?.why.contains("Another app from the same developer (Excel Thing) is still installed") ?? false, cache?.why ?? "")
        XCTAssertEqual(r.preselectedCount, 0)
        // With no other app of that developer installed, the same cache is High.
        lib.apps = []
        lib.sizes[lib.path(.caches, "com.example.word")] = T.sized(1000)
        XCTAssertEqual(lib.analyze(.orphans).item(lib.path(.caches, "com.example.word"))?.tier, .high)
    }

    func testAnUnfinishedWalkCannotProveAFolderIsStale() {
        var lib = Lib()
        lib.add(.preferences, "\(gone).plist", type: .file)
        lib.add(.caches, gone, daysOld: 200)
        // Measured: nothing inside is newer than 30 days -> High with the stale line.
        lib.sizes[lib.path(.caches, gone)] = T.sized(1000, newestDaysOld: 90)
        var item = lib.analyze(.orphans).item(lib.path(.caches, gone))
        XCTAssertEqual(item?.tier, .high)
        XCTAssertTrue(item?.evidence.contains { $0.kind == .staleMtime } ?? false)
        // The walk hit its budget: a newer file may sit in the part that was not seen.
        lib.sizes[lib.path(.caches, gone)] = SizeMeasure(bytes: 1000, state: .atLeast, fileCount: 3, newestMtime: T.now.addingTimeInterval(-90 * T.day))
        item = lib.analyze(.orphans).item(lib.path(.caches, gone))
        XCTAssertEqual(item?.tier, .medium)
        XCTAssertFalse(item?.evidence.contains { $0.kind == .staleMtime } ?? true)
        XCTAssertFalse(item?.why.contains("Not changed for") ?? true)
        // Never measured at all: same.
        lib.sizes[lib.path(.caches, gone)] = nil
        item = lib.analyze(.orphans).item(lib.path(.caches, gone))
        XCTAssertEqual(item?.tier, .medium)
        XCTAssertFalse(item?.evidence.contains { $0.kind == .staleMtime } ?? true)
    }

    func testOrphanVerdictsDirectly() {
        let lib = basicOrphanLibrary()
        let input = lib.input(.orphans)
        let index = InstalledIndex(installed: input.installed.apps, excluding: nil, inventory: [])
        XCTAssertEqual(OrphanTest.isOrphan(id: gone, in: input, index: index), .orphan(evidence: [Evidence(.noLiveOwner)]))
        let quill = T.app("com.example.quill", "Quill Editor")
        let recent = InstalledIndex(installed: [], excluding: nil, inventory: [InventoryRecord(identity: quill, firstSeen: T.now.addingTimeInterval(-90 * T.day), lastSeen: T.now.addingTimeInterval(-1 * T.day))])
        XCTAssertEqual(OrphanTest.isOrphan(id: "com.example.quill", in: input, index: recent), .notOrphan(reason: "seen installed very recently", tooRecent: true))
        XCTAssertEqual(OrphanTest.isOrphan(id: "com.apple.thing", in: input, index: recent), .notOrphan(reason: "never touched"), "other refusals are not 'recent'")
        for bad in ["com.apple.thing", "com.example.*", "x", "org.sample.present"] {
            if case .orphan = OrphanTest.isOrphan(id: bad, in: input, index: index) { XCTFail(bad) }
        }
        if case .orphan = OrphanTest.isOrphan(id: "com.example.unknown", in: input, index: index) { XCTFail("no evidence at all") }
    }

    func testOrphanDanglingLaunchAgentIsListedNotMoved() {
        var lib = Lib()
        lib.add(.caches, gone)
        lib.addAgent(name: "\(gone).login.plist", label: "\(gone).login", program: "/Applications/Gone.app/Contents/MacOS/login", exists: false)
        let r = lib.analyze(.orphans)
        let agent = r.item(lib.path(.launchAgents, "\(gone).login.plist"))
        XCTAssertEqual(agent?.tier, .handsOff)
        XCTAssertEqual(agent?.blocked, .listedOnly)
        XCTAssertTrue(agent?.evidence.contains { $0.kind == .launchdProgramGone } ?? false)
    }

    func testOrphanScanIsDeterministicAndSorted() {
        var lib = Lib()
        for (i, id) in ["com.example.aaa", "com.example.bbb", "com.example.ccc"].enumerated() {
            lib.add(.preferences, "\(id).plist", type: .file)
            lib.add(.caches, id)
            lib.sizes[lib.path(.caches, id)] = T.sized(UInt64(1000 * (i + 1)))
        }
        let a = lib.analyze(.orphans)
        XCTAssertEqual(a, lib.analyze(.orphans))
        XCTAssertEqual(a.groups.map(\.owner.bundleID), ["com.example.ccc", "com.example.bbb", "com.example.aaa"], "largest first")
    }
}
