import Foundation
import XCTest
@testable import AftertasteCore

/// Uninstall-now: one dropped app, every root, every key, positive cases and near misses.
final class ScanAppTests: XCTestCase {
    let id = "com.example.orbitmeet"
    var orbit: AppIdentity {
        T.app(id, "Orbit Meet", exec: "OrbitMeet", team: "ABCDE12345", version: "6.2", embedded: ["com.example.orbitmeet.helper"],
              groups: ["group.com.example.orbitmeet"], helpers: ["com.example.orbitmeet.agent"])
    }

    /// A library that holds a little of everything Orbit Meet leaves behind.
    func fullLibrary() -> Lib {
        var lib = Lib()
        lib.apps = [orbit]
        lib.add(.preferences, "\(id).plist", "\(id).helper.plist", "com.example.other.plist", type: .file)
        lib.add(.preferencesByHost, "\(id).A1B2C3D4-0000-1111-2222-333344445555.plist", type: .file)
        lib.add(.caches, id, "\(id).ShipIt", "\(id).helper", "\(id)pro", "\(id)2", "com.example.other")
        lib.add(.savedState, "\(id).savedState")
        lib.add(.httpStorages, id, "\(id).binarycookies")
        lib.add(.webKit, id)
        lib.add(.cookies, "\(id).binarycookies", type: .file)
        lib.add(.logs, id, "Orbit Meet", "Orbit Meetings", "Orbit Meet 6.2", "Orbit Meet Calendar", "Orbit Meet Beta")
        lib.add(.diagnosticReports, "OrbitMeet_2026-09-30-101010_jane.ips", "Other_2026.ips", type: .file)
        lib.add(.crashReporter, "OrbitMeet_ABC123.plist", type: .file)
        lib.add(.recentDocuments, "\(id).sfl2", type: .file)
        lib.addAgent(name: "\(id).agent.plist", label: "\(id).agent", program: "/Applications/Orbit Meet.app/Contents/MacOS/agent", exists: false)
        lib.addAgent(name: "com.example.keystone.plist", label: "com.example.keystone", program: "/Library/Keystone/ksagent")
        lib.add(.syncedPreferences, "\(id).plist", type: .file)
        lib.add(.applicationScripts, id)
        lib.add(.applicationSupport, id, "Orbit Meet", "Adobe", "Google")
        lib.add(.containers, id)
        lib.addEntry(.containers, "3F2A9C70-AAAA-BBBB-CCCC-123456789ABC", container: id)
        lib.add(.groupContainers, "group.\(id)", "ABCDE12345.shared", "ZZZZZZZZZZ.shared")
        lib.add(.autosaveInformation, id)
        lib.add(.systemApplicationSupport, id)
        lib.addAgent(.systemLaunchDaemons, name: "\(id).daemon.plist", label: "\(id).daemon", program: "/Library/PrivilegedHelperTools/\(id).helper")
        lib.addAgent(.systemLaunchAgents, name: "\(id).sysagent.plist", label: "\(id).sysagent", program: nil)
        lib.add(.systemPrivilegedHelperTools, "\(id).helper", type: .file)
        lib.add(.receipts, "\(id).pkg.bom", "\(id).pkg.plist", "com.example.otherpkg.bom", type: .file)
        // Containers and group containers can be read; give them sizes so they are not "protected".
        for (root, name) in [(LibraryRoot.containers, id), (.containers, "3F2A9C70-AAAA-BBBB-CCCC-123456789ABC"), (.groupContainers, "group.\(id)"),
                             (.groupContainers, "ABCDE12345.shared"), (.groupContainers, "ZZZZZZZZZZ.shared")] {
            lib.sizes[lib.path(root, name)] = T.sized(2_000_000)
        }
        return lib
    }

    func p(_ lib: Lib, _ root: LibraryRoot, _ name: String) -> String { lib.path(root, name) }

    func testEveryRootAndKeyAtTheExactTier() {
        let lib = fullLibrary()
        let r = lib.analyze(.app, target: orbit)
        let tiers = r.tiers()
        func expect(_ root: LibraryRoot, _ name: String, _ tier: Tier?, line: UInt = #line) {
            XCTAssertEqual(tiers[p(lib, root, name)], tier, "\(root) \(name)", line: line)
        }
        XCTAssertEqual(tiers["/Applications/Orbit Meet.app"], .high)
        expect(.preferences, "\(id).plist", .high)
        expect(.preferences, "\(id).helper.plist", .medium)
        expect(.preferences, "com.example.other.plist", nil)
        expect(.preferencesByHost, "\(id).A1B2C3D4-0000-1111-2222-333344445555.plist", .high)
        expect(.caches, id, .high)
        expect(.caches, "\(id).ShipIt", .high)
        expect(.caches, "\(id).helper", .medium)
        expect(.caches, "\(id)pro", nil)
        expect(.caches, "\(id)2", nil)
        expect(.caches, "com.example.other", nil)
        expect(.savedState, "\(id).savedState", .high)
        expect(.httpStorages, id, .high)
        expect(.httpStorages, "\(id).binarycookies", .high)
        expect(.webKit, id, .high)
        expect(.cookies, "\(id).binarycookies", .high)
        expect(.logs, id, .high)
        expect(.logs, "Orbit Meet", .medium)
        expect(.logs, "Orbit Meetings", nil)
        expect(.logs, "Orbit Meet 6.2", .medium)
        expect(.logs, "Orbit Meet Calendar", nil)
        expect(.logs, "Orbit Meet Beta", nil)
        expect(.diagnosticReports, "OrbitMeet_2026-09-30-101010_jane.ips", .medium)
        expect(.diagnosticReports, "Other_2026.ips", nil)
        expect(.crashReporter, "OrbitMeet_ABC123.plist", .medium)
        expect(.recentDocuments, "\(id).sfl2", .high)
        expect(.launchAgents, "\(id).agent.plist", .handsOff)
        expect(.launchAgents, "com.example.keystone.plist", nil)
        expect(.syncedPreferences, "\(id).plist", .medium)
        expect(.applicationScripts, id, .medium)
        expect(.applicationSupport, id, .medium)
        expect(.applicationSupport, "Orbit Meet", .low)
        expect(.applicationSupport, "Adobe", nil)
        expect(.applicationSupport, "Google", nil)
        expect(.containers, id, .medium)
        expect(.containers, "3F2A9C70-AAAA-BBBB-CCCC-123456789ABC", .medium)
        expect(.groupContainers, "group.\(id)", .low)
        expect(.groupContainers, "ABCDE12345.shared", .low)
        expect(.groupContainers, "ZZZZZZZZZZ.shared", nil)
        expect(.autosaveInformation, id, .handsOff)
        expect(.systemApplicationSupport, id, .needsAdmin)
        expect(.systemLaunchDaemons, "\(id).daemon.plist", .needsAdmin)
        expect(.systemLaunchAgents, "\(id).sysagent.plist", .needsAdmin)
        expect(.systemPrivilegedHelperTools, "\(id).helper", .needsAdmin)
        expect(.receipts, "\(id).pkg.bom", .needsAdmin)
        expect(.receipts, "\(id).pkg.plist", .needsAdmin)
        expect(.receipts, "com.example.otherpkg.bom", nil)
    }

    func testNothingAboveItsCeilingAndOnlyHighIsPreselected() {
        let r = fullLibrary().analyze(.app, target: orbit)
        for item in r.items where item.ruleID != "APP" {
            let rule = ResidueRules.all.first { $0.id == item.ruleID }!
            XCTAssertEqual(item.tier.capped(at: rule.ceiling), item.tier, "\(item.path) is above its rule ceiling")
        }
        let pre = ItemSelection.preselected(r)
        XCTAssertEqual(Set(r.items.filter { $0.tier == .high }.map(\.id)), pre)
        for item in r.items where item.tier != .high { XCTAssertFalse(pre.contains(item.id), item.path) }
        XCTAssertFalse(r.items.contains { $0.tier == .high && $0.sharedRisk == .high })
    }

    func testLaunchItemsAreListedNotRemoved() {
        let r = fullLibrary().analyze(.app, target: orbit)
        let agent = r.item(p(fullLibrary(), .launchAgents, "\(id).agent.plist"))
        XCTAssertEqual(agent?.blocked, .listedOnly)
        XCTAssertEqual(agent?.kind, .launchItem)
        XCTAssertTrue(agent?.evidence.contains { $0.kind == .launchdProgramInBundle } ?? false)
        XCTAssertTrue(agent?.why.contains("Listed only") ?? false)
        XCTAssertEqual(r.item("/Library/LaunchDaemons/\(id).daemon.plist")?.requiresAdmin, true)
        XCTAssertEqual(r.item("/Library/LaunchDaemons/\(id).daemon.plist")?.blocked, .needsAdmin)
    }

    func testTheBundleIsFirstInTheGroupAndEverythingIsOneGroup() {
        let r = fullLibrary().analyze(.app, target: orbit)
        XCTAssertEqual(r.groups.count, 1)
        XCTAssertEqual(r.groups[0].items.first?.ruleID, "APP")
        XCTAssertEqual(r.groups[0].items.first?.path, "/Applications/Orbit Meet.app")
        XCTAssertEqual(r.groups[0].owner.bundleID, id)
        XCTAssertFalse(r.groups[0].isOrphan)
        // After the bundle: High first, then Medium, Review, Hands off, Needs admin; no tier comes back after a later one.
        let ranks = r.groups[0].items.dropFirst().map { Engine.rank($0.tier) }
        XCTAssertEqual(ranks, ranks.sorted())
        XCTAssertEqual(Set(r.items.map(\.id)).count, r.items.count, "ids are unique")
    }

    func testNameMatchRisesOnlyWithAnIDProvenSibling() {
        var lib = Lib()
        lib.apps = [orbit]
        lib.add(.logs, "Orbit Meet")
        XCTAssertEqual(lib.analyze(.app, target: orbit).tiers()[lib.path(.logs, "Orbit Meet")], .low, "alone, a name is only Review")
        lib.add(.caches, id)
        XCTAssertEqual(lib.analyze(.app, target: orbit).tiers()[lib.path(.logs, "Orbit Meet")], .medium, "with an ID-named sibling it may rise one step")
    }

    func testVersionAndSpacingVariantsMatchAtABoundaryOnly() {
        var lib = Lib()
        lib.apps = [orbit]
        lib.add(.applicationSupport, "OrbitMeet", "orbit-meet", "Orbit_Meet 2", "ORBIT MEET", "Orbit Meet.old", "OrbitMeeting", "Orbit Meetup", "XOrbit Meet", "Orbit Meet Calendar", "Orbit Meet Beta")
        let t = lib.analyze(.app, target: orbit).tiers()
        for name in ["OrbitMeet", "orbit-meet", "Orbit_Meet 2", "ORBIT MEET"] {
            XCTAssertEqual(t[lib.path(.applicationSupport, name)], .low, name)
        }
        for name in ["Orbit Meet.old", "OrbitMeeting", "Orbit Meetup", "XOrbit Meet", "Orbit Meet Calendar", "Orbit Meet Beta"] { XCTAssertNil(t[lib.path(.applicationSupport, name)], name) }
    }

    func testCaseAndUnicodeAreFolded() {
        var lib = Lib()
        let cafe = T.app("com.example.cafe", "Café Notes", path: "/Applications/Café Notes.app")
        lib.apps = [cafe]
        lib.add(.caches, "COM.EXAMPLE.CAFE")
        lib.add(.applicationSupport, "Cafe\u{0301} Notes")   // decomposed é
        lib.add(.preferences, "Com.Example.Cafe.PLIST", type: .file)
        let r = lib.analyze(.app, target: cafe)
        XCTAssertEqual(r.item(lib.path(.caches, "COM.EXAMPLE.CAFE"))?.tier, .high)
        XCTAssertEqual(r.item(lib.path(.applicationSupport, "Cafe\u{0301} Notes"))?.tier, .low)
        XCTAssertEqual(r.item(lib.path(.preferences, "Com.Example.Cafe.PLIST"))?.tier, .high)
    }

    func testProtectedContainersAreHandsOffByNameAndNeverSized() {
        var lib = Lib()
        lib.apps = [orbit]
        lib.add(.containers, id)
        lib.add(.groupContainers, "group.\(id)")
        let r = lib.analyze(.app, target: orbit)
        for (root, name) in [(LibraryRoot.containers, id), (.groupContainers, "group.\(id)")] {
            let item = r.item(lib.path(root, name))
            XCTAssertEqual(item?.tier, .handsOff)
            XCTAssertEqual(item?.blocked, .protectedByMacOS)
            XCTAssertEqual(item?.sizeState, .notMeasured)
        }
        XCTAssertTrue(Scan.candidatePaths(lib.input(.app, target: orbit)).contains(lib.path(.containers, id)), "asked to be measured")
    }

    func testSymlinksAndDatalessAndLostStampsAreHandled() {
        var lib = Lib()
        lib.apps = [orbit]
        lib.add(.caches, id, type: .symlink)
        lib.addEntry(.savedState, "\(id).savedState", dataless: true)
        lib.entries[.logs, default: []].append(LibraryEntry(name: id, type: .directory, stamp: nil, errno: 13))
        lib.entries[.webKit, default: []].append(LibraryEntry(name: id, type: .directory, stamp: nil, errno: 2))
        lib.entries[.cookies, default: []].append(LibraryEntry(name: "\(id).binarycookies", type: .other, stamp: T.stamp(7)))
        let r = lib.analyze(.app, target: orbit)
        XCTAssertEqual(r.item(lib.path(.caches, id))?.tier, .low, "a link is the item, but never above Review")
        XCTAssertEqual(r.item(lib.path(.savedState, "\(id).savedState"))?.blocked, .dataless)
        XCTAssertEqual(r.item(lib.path(.logs, id))?.blocked, .protectedByMacOS)
        XCTAssertEqual(r.item(lib.path(.webKit, id))?.blocked, .changed)
        XCTAssertNil(r.item(lib.path(.cookies, "\(id).binarycookies")), "sockets and devices are not listed")
    }

    func testSizesAreSpaceOnDiskAndAPlaceholderIsNotMeasured() {
        var lib = Lib()
        lib.apps = [orbit]
        // A sparse file: 10 MB logical, 4 KB on disk. Directories are summed in allocated bytes, so a file counts that way too.
        lib.add(.preferences, "\(id).plist", type: .file, size: 10_000_000)
        lib.entries[.preferences]?[0].stamp?.allocated = 4096
        lib.add(.preferences, "\(id).helper.plist", type: .file, size: 3000)   // no allocation recorded: the logical size
        // An iCloud placeholder reports its full logical size but holds none of it here.
        lib.addEntry(.recentDocuments, "\(id).sfl2", type: .file, size: 9_000_000, dataless: true)
        let r = lib.analyze(.app, target: orbit)
        XCTAssertEqual(r.item(lib.path(.preferences, "\(id).plist"))?.size, 4096)
        XCTAssertEqual(r.item(lib.path(.preferences, "\(id).helper.plist"))?.size, 3000)
        let placeholder = r.item(lib.path(.recentDocuments, "\(id).sfl2"))
        XCTAssertEqual(placeholder?.size, 0)
        XCTAssertEqual(placeholder?.sizeState, .notMeasured)
        XCTAssertEqual(placeholder?.fileCount, 0)
        XCTAssertEqual(placeholder?.blocked, .dataless)
        XCTAssertEqual(r.totalBytes, 7096)
        XCTAssertTrue(Stamps.same(T.stamp(1), { var s = T.stamp(1); s.allocated = 1; return s }()), "allocated is not part of the identity stamp")
    }

    func testGroupContainerEvidenceKeepsTheNameAsStored() {
        var lib = Lib()
        lib.apps = [orbit]
        lib.add(.groupContainers, "Group.COM.Example.OrbitMeet", "abcde12345.Shared")
        let r = lib.analyze(.app, target: orbit)
        let group = r.item(lib.path(.groupContainers, "Group.COM.Example.OrbitMeet"))
        XCTAssertTrue(group?.evidence.contains(Evidence(.groupID, "Group.COM.Example.OrbitMeet")) ?? false, "\(String(describing: group?.evidence))")
        XCTAssertFalse(group?.evidence.contains { $0.kind == .groupID && $0.detail != "Group.COM.Example.OrbitMeet" } ?? true)
        XCTAssertTrue(group?.why.contains("(Group.COM.Example.OrbitMeet)") ?? false, group?.why ?? "")
        // The team-prefixed spelling too (matching stays case-insensitive).
        XCTAssertNotNil(r.item(lib.path(.groupContainers, "abcde12345.Shared")))
    }

    func testSizesAndCountsComeFromMeasurementsAndStamps() {
        var lib = Lib()
        lib.apps = [orbit]
        lib.add(.caches, id)
        lib.add(.preferences, "\(id).plist", type: .file, size: 4321)
        lib.sizes[lib.path(.caches, id)] = SizeMeasure(bytes: 5_000_000, state: .atLeast, fileCount: 42)
        let r = lib.analyze(.app, target: orbit)
        let cache = r.item(lib.path(.caches, id))
        XCTAssertEqual(cache?.size, 5_000_000)
        XCTAssertEqual(cache?.sizeState, .atLeast)
        XCTAssertEqual(cache?.fileCount, 42)
        let prefs = r.item(lib.path(.preferences, "\(id).plist"))
        XCTAssertEqual(prefs?.size, 4321)
        XCTAssertEqual(prefs?.sizeState, .measured)
        XCTAssertEqual(prefs?.fileCount, 1)
        XCTAssertEqual(r.item("/Applications/Orbit Meet.app")?.sizeState, .notMeasured)
        // Files are not asked to be measured again (their stamp has the size); the app bundle and folders are.
        let paths = Scan.candidatePaths(lib.input(.app, target: orbit))
        XCTAssertTrue(paths.contains(lib.path(.caches, id)))
        XCTAssertTrue(paths.contains("/Applications/Orbit Meet.app"))
        XCTAssertFalse(paths.contains(lib.path(.preferences, "\(id).plist")))
        XCTAssertEqual(paths, paths.sorted())
    }

    func testSystemRowsAreNeverMeasured() {
        let lib = fullLibrary()
        let paths = Scan.candidatePaths(lib.input(.app, target: orbit))
        XCTAssertFalse(paths.contains { $0.hasPrefix("/Library") || $0.hasPrefix("/private") })
        XCTAssertFalse(paths.contains { !$0.hasPrefix("/Users/jane") && !$0.hasSuffix(".app") })
    }

    func testMacAppStoreRootOwnedBundleNeedsAdminAndNothingIsPlanned() {
        var lib = Lib()
        let mas = T.app(id, "Orbit Meet", path: "/Applications/Orbit Meet.app", uid: 0)
        lib.apps = [mas]
        lib.add(.caches, id)
        let r = lib.analyze(.app, target: mas)
        XCTAssertEqual(r.item("/Applications/Orbit Meet.app")?.tier, .needsAdmin)
        XCTAssertEqual(r.item("/Applications/Orbit Meet.app")?.requiresAdmin, true)
        let plan = TrashPlanner.plan(from: r, ticked: Set(r.items.map(\.id)), mode: .bulk(acknowledgedMedium: true), now: T.now, runID: "r")
        XCTAssertTrue(plan.items.isEmpty, "the app stays installed, so its files stay")
        XCTAssertFalse(plan.skipped.isEmpty)
    }

    func testABundleOutsideAnApplicationsFolderIsHandsOffAndNothingIsPlanned() {
        var lib = Lib()
        let dropped = T.app(id, "Orbit Meet", path: "/Users/jane/Downloads/Orbit Meet.app")
        lib.apps = [dropped]
        lib.add(.caches, id)
        lib.sizes["/Users/jane/Downloads/Orbit Meet.app"] = T.sized(1_000_000)
        let r = lib.analyze(.app, target: dropped)
        let bundle = r.item("/Users/jane/Downloads/Orbit Meet.app")
        XCTAssertEqual(bundle?.tier, .handsOff, "the Guard would refuse it and stop the whole run")
        XCTAssertTrue(bundle?.why.contains("Applications folder") ?? false, bundle?.why ?? "")
        let plan = TrashPlanner.plan(from: r, ticked: Set(r.items.map(\.id)), mode: .bulk(acknowledgedMedium: true), now: T.now, runID: "r")
        XCTAssertTrue(plan.items.isEmpty, "the app stays installed, so its files stay")
        // An app in ~/Applications or a suite folder is still offered.
        for path in ["/Users/jane/Applications/Orbit Meet.app", "/Applications/Suite/Orbit Meet.app"] {
            let app = T.app(id, "Orbit Meet", path: path)
            var other = Lib()
            other.apps = [app]
            other.add(.caches, id)
            XCTAssertEqual(other.analyze(.app, target: app).item(path)?.tier, .high, path)
        }
    }

    func testTheBundleDisappearsOnceItIsNoLongerInstalledOrMeasurable() {
        var lib = Lib()
        lib.apps = []                                    // already moved to the Trash
        lib.add(.caches, id)
        let r = lib.analyze(.app, target: orbit)
        XCTAssertNil(r.item("/Applications/Orbit Meet.app"))
        XCTAssertEqual(r.item(lib.path(.caches, id))?.tier, .high)
        lib.sizes["/Applications/Orbit Meet.app"] = T.sized(1_000_000)
        XCTAssertNotNil(lib.analyze(.app, target: orbit).item("/Applications/Orbit Meet.app"), "measured means it is still there")
    }

    func testRefusesTargetsItMustNeverTouch() {
        var lib = Lib()
        lib.add(.caches, "com.apple.Safari", "io.github.everydayopen.aftertaste")
        for target in [T.app("com.apple.Safari", "Safari"), T.app("io.github.everydayopen.aftertaste", "Aftertaste"), T.app("com.example.*", "Glob")] {
            XCTAssertTrue(lib.analyze(.app, target: target).groups.isEmpty, target.bundleID)
        }
        var signed = T.app("com.example.signed", "Signed Thing")
        signed.appleSigned = true
        XCTAssertTrue(lib.analyze(.app, target: signed).groups.isEmpty)
        XCTAssertTrue(lib.analyze(.app, target: nil).groups.isEmpty)
        // An Apple app people really do uninstall is allowed.
        let xcode = T.app("com.apple.dt.Xcode", "Xcode", path: "/Applications/Xcode.app")
        lib.apps = [xcode]
        lib.add(.caches, "com.apple.dt.Xcode")
        XCTAssertEqual(lib.analyze(.app, target: xcode).item(lib.path(.caches, "com.apple.dt.Xcode"))?.tier, .high)
    }

    func testKeepListMakesItemsHandsOff() {
        var lib = fullLibrary()
        lib.prefs = Preferences(keepList: [id])
        let r = Scan.analyze(lib.input(.app, target: orbit))
        XCTAssertTrue(r.items.allSatisfy { $0.tier == .handsOff || $0.tier == .needsAdmin }, "everything of a kept app is off limits")
        XCTAssertEqual(r.item("/Applications/Orbit Meet.app")?.tier, .handsOff)
        var lib2 = fullLibrary()
        lib2.prefs = Preferences(keepList: ["~/Library/Caches/\(id)"])
        let r2 = Scan.analyze(lib2.input(.app, target: orbit))
        XCTAssertEqual(r2.item(lib2.path(.caches, id))?.tier, .handsOff)
        XCTAssertEqual(r2.item(lib2.path(.caches, "\(id).ShipIt"))?.tier, .high, "a path keep entry is exact, not a prefix of siblings")
    }

    func testRunningOwnerBlocksTheGroupAndAnUnreadableProcessListBlocksEverything() {
        let lib = fullLibrary()
        let running = RunningSnapshot(bundleIDs: [id], executablePaths: [], readable: true)
        XCTAssertEqual(Scan.analyze(lib.input(.app, target: orbit, running: running)).groups.first?.runState, .running)
        let inside = RunningSnapshot(bundleIDs: [], executablePaths: ["/Applications/Orbit Meet.app/Contents/MacOS/OrbitMeet"], readable: true)
        XCTAssertEqual(Scan.analyze(lib.input(.app, target: orbit, running: inside)).groups.first?.runState, .running)
        let fromCache = RunningSnapshot(bundleIDs: [], executablePaths: ["/Users/jane/Library/Caches/\(id)/helper"], readable: true)
        XCTAssertEqual(Scan.analyze(lib.input(.app, target: orbit, running: fromCache)).groups.first?.runState, .running)
        let blind = RunningSnapshot(readable: false)
        let r = Scan.analyze(lib.input(.app, target: orbit, running: blind))
        XCTAssertEqual(r.groups.first?.runState, .unknown)
        XCTAssertTrue(r.coverage.processListUnreadable)
        XCTAssertFalse(r.coverage.isComplete)
        XCTAssertEqual(Scan.analyze(lib.input(.app, target: orbit)).groups.first?.runState, .notRunning)
    }

    func testCoverageIsCarriedThrough() {
        var lib = fullLibrary()
        lib.coverageOverride[.containers] = .protectedByMacOS
        lib.coverageOverride[.groupContainers] = .protectedByMacOS
        let r = lib.analyze(.app, target: orbit)
        XCTAssertEqual(r.coverage.total, 26)
        XCTAssertEqual(r.coverage.protectedCount, 2)
        XCTAssertEqual(r.coverage.looked, 24)
        XCTAssertFalse(r.coverage.isComplete)
        XCTAssertNil(r.item(lib.path(.containers, id)), "a folder macOS would not let us list shows no rows")
    }

    func testDeterministic() {
        let a = fullLibrary().analyze(.app, target: orbit)
        let b = fullLibrary().analyze(.app, target: orbit)
        XCTAssertEqual(a, b)
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        XCTAssertEqual(try? encoder.encode(a), try? encoder.encode(b))
    }

    func testWhyLinesNameTheEvidence() {
        let lib = fullLibrary()
        let r = lib.analyze(.app, target: orbit)
        XCTAssertEqual(r.item(lib.path(.savedState, "\(id).savedState"))?.why, "Named exactly \(id).savedState, after Orbit Meet's bundle ID.")
        XCTAssertTrue(r.item(lib.path(.caches, "\(id).ShipIt"))?.why.hasPrefix("Starts with the bundle ID") ?? false)
        XCTAssertTrue(r.item(lib.path(.containers, "3F2A9C70-AAAA-BBBB-CCCC-123456789ABC"))?.why.contains("macOS lists this container") ?? false)
        XCTAssertTrue(r.item(lib.path(.logs, "Orbit Meet"))?.why.contains("nothing else confirms it") ?? false)
        XCTAssertEqual(r.item("/Applications/Orbit Meet.app")?.why, "The app you chose.")
        for item in r.items { XCTAssertFalse(item.why.isEmpty, item.path) }
    }
}
