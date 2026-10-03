import Foundation
import XCTest
@testable import AftertasteCore

// Placeholder tests for the frozen Model (architect). The core owner adds the real suites beside this file.
final class ModelTests: XCTestCase {
    private func stamp(inode: UInt64 = 42) -> FileStamp {
        FileStamp(device: 1, inode: inode, type: .directory, size: 0, mtimeSeconds: 1_800_000_000, mtimeNanoseconds: 500_000_000, linkCount: 3)
    }

    private func item(_ name: String, tier: Tier, size: UInt64 = 1 << 20, kind: ResidueKind = .cache) -> ResidueItem {
        ResidueItem(path: "/Users/jane/Library/Caches/\(name)", ownerID: "com.example.notes", ruleID: "U3", root: .caches, kind: kind,
                    tier: tier, evidence: [Evidence(.exactID, name)], size: size, sizeState: .measured, fileCount: 12,
                    mtime: Date(timeIntervalSince1970: 1_800_000_000), stamp: stamp(), why: "Named exactly \(name).")
    }

    func testOnlyHighIsPreselectedAndOnlyThreeTiersHaveACheckbox() {
        XCTAssertEqual(Tier.allCases.filter(\.isPreselected), [.high])
        XCTAssertEqual(Tier.allCases.filter(\.isSelectable), [.high, .medium, .low])
        XCTAssertEqual(Tier.low.displayName, "Review")
    }

    func testCappingNeverRaisesATierAndNonLevelsWin() {
        XCTAssertEqual(Tier.high.capped(at: .medium), .medium)
        XCTAssertEqual(Tier.medium.capped(at: .high), .medium)
        XCTAssertEqual(Tier.high.capped(at: .low), .low)
        XCTAssertEqual(Tier.high.capped(at: .handsOff), .handsOff)
        XCTAssertEqual(Tier.high.capped(at: .needsAdmin), .needsAdmin)
        XCTAssertEqual(Tier.handsOff.capped(at: .high), .handsOff)
        XCTAssertEqual(Tier.needsAdmin.capped(at: .handsOff), .needsAdmin)
        for a in Tier.allCases {
            for b in Tier.allCases { XCTAssertLessThanOrEqual(a.capped(at: b).trust, a.trust) }
        }
    }

    func testLibraryRootPathsAreUnderHomeOrAbsolute() {
        XCTAssertEqual(LibraryRoot.caches.path(home: "/Users/jane"), "/Users/jane/Library/Caches")
        XCTAssertEqual(LibraryRoot.caches.path(home: "/Users/jane/"), "/Users/jane/Library/Caches")
        XCTAssertEqual(LibraryRoot.systemLaunchDaemons.path(home: "/Users/jane"), "/Library/LaunchDaemons")
        XCTAssertEqual(LibraryRoot.allCases.count, 26)
        XCTAssertEqual(Set(LibraryRoot.allCases.map(\.relativePath)).count, 26, "no two roots share a folder")
        XCTAssertTrue(LibraryRoot.allCases.filter(\.isSystem).allSatisfy { $0.relativePath.hasPrefix("/") })
        XCTAssertEqual(LibraryRoot.allCases.filter(\.contentsMayBeProtected), [.containers, .groupContainers])
    }

    func testStampDateKeepsSubsecondPart() {
        XCTAssertEqual(stamp().mtime.timeIntervalSince1970, 1_800_000_000.5, accuracy: 0.0001)
    }

    func testItemRoundTripsThroughJSONAndExposesInode() throws {
        let original = item("com.example.notes", tier: .high)
        let decoded = try JSONDecoder().decode(ResidueItem.self, from: JSONEncoder().encode(original))
        XCTAssertEqual(decoded, original)
        XCTAssertEqual(decoded.inode, 42)
        XCTAssertEqual(decoded.name, "com.example.notes")
        XCTAssertEqual(decoded.id, original.path)
    }

    func testGroupAndResultTotalsCountOnlyHighAsPreselected() {
        let owner = AppIdentity(bundleID: "com.example.notes", displayName: "Notes Pro", execName: "NotesPro")
        let group = ResidueGroup(owner: owner, isOrphan: false, items: [
            item("a", tier: .high, size: 100), item("b", tier: .high, size: 50), item("c", tier: .medium, size: 1000),
            item("d", tier: .handsOff, size: 7), item("e", tier: .needsAdmin, size: 3),
        ])
        let result = ScanResult(scannedAt: Date(), kind: .app, groups: [group], coverage: Coverage(), home: "/Users/jane", osVersion: "26.1")
        XCTAssertEqual(group.highBytes, 150)
        XCTAssertEqual(group.totalBytes, 1160)
        XCTAssertEqual(result.preselectedCount, 2)
        XCTAssertEqual(result.preselectedBytes, 150)
        XCTAssertEqual(group.count(.handsOff), 1)
    }

    func testCoverageNeverCallsPartialOrProtectedPlacesLooked() {
        let places = [
            PlaceCoverage(root: .preferences, state: .read, entryCount: 10), PlaceCoverage(root: .cookies, state: .absent),
            PlaceCoverage(root: .containers, state: .protectedByMacOS, errno: 1), PlaceCoverage(root: .caches, state: .partial),
            PlaceCoverage(root: .logs, state: .failed, errno: 5),
        ]
        var cov = Coverage(places: places)
        XCTAssertEqual(cov.total, 5)
        XCTAssertEqual(cov.looked, 2)
        XCTAssertEqual(cov.protectedCount, 1)
        XCTAssertEqual(cov.partialCount, 1)
        XCTAssertEqual(cov.failedCount, 1)
        XCTAssertFalse(cov.isComplete)
        cov.places = places.filter { $0.state == .read || $0.state == .absent }
        XCTAssertTrue(cov.isComplete)
        cov.processListUnreadable = true
        XCTAssertFalse(cov.isComplete, "an unreadable process list makes running state unknown")
        let empty = ScanResult(scannedAt: Date(), kind: .orphans, groups: [], coverage: cov, home: "/Users/jane", osVersion: "26.1")
        XCTAssertFalse(empty.isCleanAndComplete, "never claim 'nothing found' on partial coverage")
    }

    func testOutcomeCountsOnlyWhatWasMoved() {
        func out(_ name: String, _ status: TrashStatus, _ mb: UInt64) -> ItemOutcome {
            ItemOutcome(item: item(name, tier: .high, size: mb << 20), status: status)
        }
        let outcome = TrashOutcome(runID: "r1", startedAt: Date(), finishedAt: Date(), results: [
            out("a", .moved, 100), out("b", .moved, 200), out("c", .blocked, 400), out("d", .alreadyGone, 800), out("e", .protectedByMacOS, 1600),
        ])
        XCTAssertEqual(outcome.movedCount, 2)
        XCTAssertEqual(outcome.movedBytes, 300 << 20)
        XCTAssertEqual(outcome.notMovedCount, 2, "already gone is neither moved nor a problem")
    }

    func testHistoryRunOffersUndoOnlyForItemsStillInTheTrash() {
        func rec(_ n: String) -> UndoRecord {
            UndoRecord(runID: "r1", originalPath: "/Users/jane/Library/Caches/\(n)", trashedPath: "/Users/jane/.Trash/\(n)", stamp: stamp(),
                       bytes: 10, label: "Notes Pro", tier: .high, movedAt: Date())
        }
        let run = HistoryRun(runID: "r1", date: Date(), label: "Notes Pro", items: [
            HistoryItem(record: rec("a"), state: .inTrash), HistoryItem(record: rec("b"), state: .restored), HistoryItem(record: rec("c"), state: .emptied),
        ])
        XCTAssertEqual(run.undoable.map(\.originalPath), ["/Users/jane/Library/Caches/a"])
        XCTAssertEqual(run.bytes, 30)
    }

    func testActivityEntryRoundTripsAndKeepsTheWriteAheadPhase() throws {
        let e = ActivityEntry(timestamp: Date(timeIntervalSince1970: 1_800_000_000), runID: "r1", verb: .trash, phase: .intent,
                              path: "~/Library/Caches/com.example.notes", label: "Notes Pro", ownerID: "com.example.notes", ruleID: "U3",
                              tier: .high, kind: .cache, bytes: 5, stamp: stamp(), why: "Named exactly.")
        let decoded = try JSONDecoder().decode(ActivityEntry.self, from: JSONEncoder().encode(e))
        XCTAssertEqual(decoded, e)
        XCTAssertNil(decoded.status)
        XCTAssertNotEqual(e.id, ActivityEntry(timestamp: e.timestamp, runID: "r1", verb: .trash, phase: .result, path: e.path).id)
    }

    func testIdentityListsEveryIDItMayOwn() {
        let id = AppIdentity(bundleID: "com.example.notes", displayName: "Notes Pro", embeddedIDs: ["com.example.notes.helper"],
                             helperLabels: ["com.example.notes.agent"], bundleOwnerUID: 0)
        XCTAssertEqual(id.allIDs, ["com.example.notes", "com.example.notes.helper", "com.example.notes.agent"])
        XCTAssertTrue(id.bundleNeedsAdmin)
        XCTAssertFalse(AppIdentity(bundleID: "a.b", displayName: "x", bundleOwnerUID: 501).bundleNeedsAdmin)
    }

    func testStoredPreferencesSurviveMissingAndUnknownFields() throws {
        func decode(_ json: String) throws -> Preferences { try JSONDecoder().decode(Preferences.self, from: Data(json.utf8)) }
        XCTAssertEqual(try decode("{}"), Preferences.default)
        XCTAssertEqual(try decode("{\"keepList\":[\"com.example.keep\"],\"somethingNew\":1}").keepList, ["com.example.keep"])
        let mine = Preferences(keepList: ["/Users/jane/Library/Application Support/Keep"], hideAppNamesInExports: true, showMenuBarItem: true, hasSeenFirstRun: true)
        let full = try JSONSerialization.jsonObject(with: JSONEncoder().encode(mine)) as! [String: Any]
        XCTAssertEqual(full.count, 4)
        XCTAssertEqual(try JSONDecoder().decode(Preferences.self, from: JSONEncoder().encode(mine)), mine)
        for key in full.keys {
            var partial = full
            partial[key] = nil
            let got = try JSONDecoder().decode(Preferences.self, from: JSONSerialization.data(withJSONObject: partial))
            if key != "keepList" { XCTAssertEqual(got.keepList, mine.keepList, "dropping \(key) must not reset the keep-list") }
        }
    }

    func testDemoScenarioNamesMatchTheLaunchArgument() {
        XCTAssertEqual(DemoScenario.allCases.map(\.rawValue).sorted(),
                       ["admin-rows", "blocked", "first-run", "leftovers", "maybe-only", "quiet", "snapshots"])
        XCTAssertEqual(DemoScenario(rawValue: "maybe-only"), .maybeOnly)
    }

    func testReportTotalsAddUpAcrossApps() {
        let a = TraceApp(label: "App 1", files: 10, bytes: 100, launchAgents: 1)
        let b = TraceApp(label: "App 2", files: 5, bytes: 50, privilegedHelpers: 2)
        let r = TraceReport(generatedAt: Date(), kind: .orphans, apps: [a, b], coverage: CoverageFacts(looked: 20, total: 26, protectedCount: 2),
                            osVersion: "26.1", namesHidden: true)
        XCTAssertEqual(r.files, 15)
        XCTAssertEqual(r.bytes, 150)
        XCTAssertEqual(r.launchAgents, 1)
        XCTAssertEqual(r.privilegedHelpers, 2)
    }

    func testShareRiskOrdersNoneBelowHigh() {
        XCTAssertLessThan(ShareRisk.none, .possible)
        XCTAssertLessThan(ShareRisk.possible, .high)
    }
}
