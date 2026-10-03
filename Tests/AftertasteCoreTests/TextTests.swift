import Foundation
import XCTest
@testable import AftertasteCore

final class FormatTests: XCTestCase {
    func testBytesAreFinderStyleDecimal() {
        let cases: [(UInt64, String)] = [
            (0, "0 bytes"), (1, "1 byte"), (2, "2 bytes"), (999, "999 bytes"), (1000, "1 KB"), (1499, "1 KB"), (1500, "2 KB"), (412_000, "412 KB"),
            (999_499, "999 KB"), (999_500, "1 MB"), (1_000_000, "1 MB"), (1_234_567, "1.2 MB"), (12_345_678, "12.3 MB"), (99_940_000, "99.9 MB"),
            (99_950_000, "100 MB"), (412_000_000, "412 MB"), (1_300_000_000, "1.3 GB"), (1_000_000_000, "1 GB"), (340_000_000_000, "340 GB"),
            (2_500_000_000_000, "2.5 TB"), (UInt64.max, "18447 PB"),
        ]
        for (n, text) in cases { XCTAssertEqual(Format.bytes(n), text, "\(n)") }
    }

    func testAtLeastCountAndDate() {
        XCTAssertEqual(Format.atLeast(3_000_000_000), "at least 3 GB")
        XCTAssertEqual(Format.count(1, "item"), "1 item")
        XCTAssertEqual(Format.count(0, "item"), "0 items")
        XCTAssertEqual(Format.count(14, "place"), "14 places")
        XCTAssertEqual(Format.date(T.now), "2026-10-03")
        XCTAssertEqual(Format.date(Date(timeIntervalSince1970: 0)), "1970-01-01")
        XCTAssertEqual(Format.date(Date(timeIntervalSince1970: -1)), "1969-12-31")
        XCTAssertEqual(Format.size(1_000_000, .measured), "1 MB")
        XCTAssertEqual(Format.size(3_000_000_000, .atLeast), "at least 3 GB")
        XCTAssertEqual(Format.size(0, .notMeasured), "size not measured", "never shown as 0")
    }

    func testCivilDatesRoundTrip() {
        var d = -400
        while d < 40_000 {
            let date = Date(timeIntervalSince1970: Double(d) * 86_400 + 3_661)
            let p = Civil.parts(date)
            XCTAssertEqual(Civil.date(year: p.year, month: p.month, day: p.day, hour: p.hour, minute: p.minute, second: p.second), date)
            d += 37
        }
        let leap = Civil.parts(Civil.date(year: 2028, month: 2, day: 29, hour: 23, minute: 59, second: 59))
        XCTAssertEqual([leap.year, leap.month, leap.day, leap.hour, leap.minute, leap.second], [2028, 2, 29, 23, 59, 59])
    }

    func testISO8601Lite() {
        let d = Civil.date(year: 2026, month: 10, day: 3, hour: 10, minute: 15, second: 30)
        XCTAssertEqual(ISO8601Lite.string(d), "2026-10-03T10:15:30Z")
        XCTAssertEqual(ISO8601Lite.parse("2026-10-03T10:15:30Z"), d)
        XCTAssertEqual(ISO8601Lite.parse("2026-10-03T10:15:30.500Z"), d.addingTimeInterval(0.5))
        for bad in ["", "2026-10-03", "2026-10-03T10:15:30", "2026-10-03 10:15:30Z", "2026-13-03T10:15:30Z", "2026-10-03T25:15:30Z", "2026-10-03T10:15:30+02:00", "garbageXXXXXXXXXXXXXXXXXX"] {
            XCTAssertNil(ISO8601Lite.parse(bad), bad)
        }
    }

    func testPathText() {
        XCTAssertEqual(PathText.tilde("/Users/jane/Library/x", home: "/Users/jane"), "~/Library/x")
        XCTAssertEqual(PathText.tilde("/Users/jane", home: "/Users/jane/"), "~")
        XCTAssertEqual(PathText.tilde("/Users/janet/Library/x", home: "/Users/jane"), "/Users/janet/Library/x", "whole components only")
        XCTAssertEqual(PathText.tilde("/System/Volumes/Data/Users/jane/Library/x", home: "/Users/jane"), "~/Library/x")
        XCTAssertEqual(PathText.tilde("/Library/Caches/x", home: "/Users/jane"), "/Library/Caches/x")
        XCTAssertEqual(PathText.tilde("/a/b", home: "/"), "/a/b")
        XCTAssertEqual(PathText.expandTilde("~/Library/x", home: "/Users/jane"), "/Users/jane/Library/x")
        XCTAssertEqual(PathText.expandTilde("~", home: "/Users/jane/"), "/Users/jane")
        XCTAssertEqual(PathText.expandTilde("/Library/x", home: "/Users/jane"), "/Library/x")
        XCTAssertEqual(PathText.expandTilde("~other/x", home: "/Users/jane"), "~other/x")
        let p = "/Users/jane/Library/Caches/com.example.notes"
        XCTAssertEqual(PathText.expandTilde(PathText.tilde(p, home: "/Users/jane"), home: "/Users/jane"), p)
    }
}

final class ActivityLogTests: XCTestCase {
    func full() -> ActivityEntry {
        ActivityEntry(timestamp: Civil.date(year: 2026, month: 10, day: 3, hour: 10, minute: 15, second: 1), runID: "20261003T101500Z-3fa9c1", verb: .trash, phase: .result,
                      path: "~/Library/Caches/com.example.notes", label: "Notes Pro", ownerID: "com.example.notes", ruleID: "U3", tier: .high, kind: .cache,
                      bytes: 1234, status: .moved, undoStatus: nil, errno: nil, trashedPath: "~/.Trash/com.example.notes", stamp: T.stamp(77), why: "Named exactly \"x\"\nsecond line",
                      detail: nil)
    }

    func testFileNames() {
        XCTAssertEqual(ActivityLog.fileName(for: T.now), "journal-2026-10.jsonl")
        XCTAssertEqual(ActivityLog.fileName(for: Civil.date(year: 2027, month: 1, day: 1)), "journal-2027-01.jsonl")
        XCTAssertEqual(ActivityLog.fileName(for: Civil.date(year: 2026, month: 12, day: 31, hour: 23, minute: 59, second: 59)), "journal-2026-12.jsonl")
        for ok in ["journal-2026-10.jsonl", "journal-1999-01.jsonl"] { XCTAssertTrue(ActivityLog.isJournalFile(ok), ok) }
        for bad in ["journal-2026-10.json", "journal-26-10.jsonl", "journal-2026-1a.jsonl", "journal-2026-10.jsonl.tmp", "activity.jsonl", ".journal-2026-10.jsonl", "journal-2026_10.jsonl", ""] {
            XCTAssertFalse(ActivityLog.isJournalFile(bad), bad)
        }
    }

    func testEncodeIsOneSortedLineAndRoundTrips() throws {
        let e = full()
        let line = ActivityLog.encode(e)
        XCTAssertFalse(line.contains("\n"), "newlines inside strings are escaped")
        XCTAssertFalse(line.hasSuffix("\n"))
        XCTAssertEqual(line, ActivityLog.encode(e), "stable")
        XCTAssertTrue(line.contains("\"timestamp\":\"2026-10-03T10:15:01Z\""), "ISO-8601 whole seconds")
        XCTAssertEqual(ActivityLog.decode(line: line), e)
        let keys = try XCTUnwrap(try JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any]).keys
        XCTAssertTrue(Set(keys).isSubset(of: ["timestamp", "runID", "verb", "phase", "path", "label", "ownerID", "ruleID", "tier", "kind", "bytes", "status", "undoStatus",
                                               "errno", "trashedPath", "stamp", "why", "detail"]), "nothing but what the screen showed: no contents, no arguments")
        // Sorted keys: the first key alphabetically comes first.
        XCTAssertTrue(line.hasPrefix("{\"bytes\":"), line)
        XCTAssertFalse(line.contains("\\/"), "slashes are not escaped")
    }

    func testEveryVerbAndPhaseRoundTrips() {
        for verb in [ActivityVerb.run, .trash, .undo] {
            for phase in [ActivityPhase.intent, .result] {
                let e = ActivityEntry(timestamp: T.now, runID: "r", verb: verb, phase: phase, undoStatus: verb == .undo ? .restored : nil, detail: "d")
                XCTAssertEqual(ActivityLog.decode(line: ActivityLog.encode(e)), e)
            }
        }
    }

    func testDecodeAllIsTolerant() {
        let a = ActivityLog.encode(full())
        var b = full()
        b.path = "~/Library/Caches/other"
        let lines = [a, "", "   ", "{not json", ActivityLog.encode(b), "{\"verb\":\"trash\"}", String(a.prefix(a.count / 2))]
        let (entries, skipped) = ActivityLog.decodeAll(lines.joined(separator: "\n"))
        XCTAssertEqual(entries.map(\.path), ["~/Library/Caches/com.example.notes", "~/Library/Caches/other"])
        XCTAssertEqual(skipped, 3)
        let crlf = ActivityLog.decodeAll(a + "\r\n" + a + "\r\n")
        XCTAssertEqual(crlf.entries.count, 2)
        XCTAssertEqual(crlf.skippedLines, 0)
        XCTAssertEqual(ActivityLog.decodeAll("").entries.count, 0)
        XCTAssertNil(ActivityLog.decode(line: "{\"timestamp\":\"yesterday\"}"))
    }
}

final class HistoryTests: XCTestCase {
    let home = T.home
    let stamp = T.stamp(9)

    func trash(_ run: String, _ path: String, at s: Double, status: TrashStatus = .moved, label: String = "Notes Pro", trashed: String? = nil, stamp: FileStamp? = nil) -> [ActivityEntry] {
        let t = T.now.addingTimeInterval(s)
        let intent = ActivityEntry(timestamp: t, runID: run, verb: .trash, phase: .intent, path: path, label: label, ownerID: "com.example.notes", ruleID: "U3", tier: .high,
                                   kind: .cache, bytes: 100, stamp: stamp ?? self.stamp)
        let result = ActivityEntry(timestamp: t.addingTimeInterval(1), runID: run, verb: .trash, phase: .result, path: path, label: label, bytes: 100, status: status,
                                   trashedPath: status == .moved ? (trashed ?? "~/.Trash/" + (path.split(separator: "/").last.map(String.init) ?? "")) : nil)
        return [intent, result]
    }

    func testRunsStatesAndOrder() {
        var log: [ActivityEntry] = []
        log.append(ActivityEntry(timestamp: T.now, runID: "r1", verb: .run, phase: .intent, detail: "start"))
        log += trash("r1", "~/Library/Caches/a", at: 1)
        log += trash("r1", "~/Library/Caches/b", at: 2)
        log += trash("r1", "~/Library/Caches/blocked", at: 3, status: .blocked)
        log += trash("r1", "~/Library/Caches/gone", at: 3, status: .alreadyGone)
        log += trash("r2", "~/Library/Preferences/p.plist", at: 100, label: "Other App")
        let runs = History.runs(from: log, home: home, inTrash: nil)
        XCTAssertEqual(runs.map(\.runID), ["r2", "r1"], "newest first")
        let r1 = runs[1]
        XCTAssertEqual(r1.items.count, 2)
        XCTAssertEqual(r1.notMovedCount, 1, "blocked counts, already gone does not")
        XCTAssertEqual(r1.label, "Notes Pro")
        XCTAssertEqual(r1.items[0].record.originalPath, "/Users/jane/Library/Caches/a")
        XCTAssertEqual(r1.items[0].record.trashedPath, "/Users/jane/.Trash/a")
        XCTAssertEqual(r1.items[0].record.stamp, stamp)
        XCTAssertEqual(r1.items[0].record.tier, .high)
        XCTAssertEqual(r1.items[0].state, .inTrash)
        XCTAssertEqual(r1.undoable.count, 2)
        XCTAssertEqual(r1.bytes, 200)
        XCTAssertEqual(r1.date, T.now, "the run line is the earliest")
    }

    func testASizeThatWasOnlyAFloorStaysAFloor() {
        let t = T.now
        let result = ActivityEntry(timestamp: t.addingTimeInterval(1), runID: "r1", verb: .trash, phase: .result, path: "~/Library/Caches/big", label: "Notes Pro", bytes: 500,
                                   status: .moved, trashedPath: "~/.Trash/big", stamp: stamp, lowerBound: true)
        let exact = ActivityEntry(timestamp: t.addingTimeInterval(2), runID: "r2", verb: .trash, phase: .result, path: "~/Library/Caches/small", label: "Notes Pro", bytes: 5,
                                  status: .moved, trashedPath: "~/.Trash/small", stamp: stamp)
        let runs = History.runs(from: [result, exact], home: home, inTrash: nil)
        XCTAssertEqual(runs.first { $0.runID == "r1" }?.bytesAreFloor, true)
        XCTAssertEqual(runs.first { $0.runID == "r2" }?.bytesAreFloor, false)
        // The flag survives the journal line, and a line written before it existed still reads.
        XCTAssertEqual(ActivityLog.decode(line: ActivityLog.encode(result))?.lowerBound, true)
        XCTAssertNil(ActivityLog.decode(line: ActivityLog.encode(exact))?.lowerBound)
    }

    func testRestoredAndEmptied() {
        var log = trash("r1", "~/Library/Caches/a", at: 1) + trash("r1", "~/Library/Caches/b", at: 2) + trash("r1", "~/Library/Caches/c", at: 3)
        log.append(ActivityEntry(timestamp: T.now.addingTimeInterval(50), runID: "u1", verb: .undo, phase: .result, path: "~/Library/Caches/a",
                                 undoStatus: .restored, trashedPath: "~/.Trash/a"))
        log.append(ActivityEntry(timestamp: T.now.addingTimeInterval(51), runID: "u1", verb: .undo, phase: .result, path: "~/Library/Caches/b", undoStatus: .destinationExists))
        let ids = History.runs(from: log, home: home, inTrash: nil)[0].items.map(\.record.id)
        let present = Set([ids[1]])
        let runs = History.runs(from: log, home: home, inTrash: present)
        XCTAssertEqual(runs.count, 1, "undo runs are not shown as runs")
        XCTAssertEqual(runs[0].items.map(\.state), [.restored, .inTrash, .emptied])
        XCTAssertEqual(runs[0].undoable.map(\.originalPath), ["/Users/jane/Library/Caches/b"])
        // Without Trash knowledge nothing is "emptied".
        XCTAssertEqual(History.runs(from: log, home: home, inTrash: nil)[0].items.map(\.state), [.restored, .inTrash, .inTrash])
        // Trashed again after the undo: the new run is in the Trash, the old one stays restored.
        log += trash("r2", "~/Library/Caches/a", at: 100)
        let again = History.runs(from: log, home: home, inTrash: nil)
        XCTAssertEqual(again[0].items.map(\.state), [.inTrash])
        XCTAssertEqual(again[1].items.map(\.state)[0], .restored)
    }

    func testAnUndoForAnotherTrashedPathIsNotThisItem() {
        var log = trash("r1", "~/Library/Caches/a", at: 1)
        log.append(ActivityEntry(timestamp: T.now.addingTimeInterval(50), runID: "u1", verb: .undo, phase: .result, path: "~/Library/Caches/a",
                                 undoStatus: .restored, trashedPath: "~/.Trash/a 2"))
        XCTAssertEqual(History.runs(from: log, home: home, inTrash: nil)[0].items[0].state, .inTrash)
    }

    func testMovedItemsWithoutAStampAreLeftOutAndMixedLabelsCount() {
        var log: [ActivityEntry] = []
        var noStamp = trash("r1", "~/Library/Caches/a", at: 1)
        noStamp[0].stamp = nil
        log += noStamp
        log += trash("r1", "~/Library/Caches/b", at: 2, label: "Other App")
        log += trash("r1", "~/Library/Caches/c", at: 3, label: "Third App")
        let run = History.runs(from: log, home: home, inTrash: nil)[0]
        XCTAssertEqual(run.items.count, 2)
        XCTAssertEqual(run.label, "2 apps")
        XCTAssertTrue(History.runs(from: [], home: home, inTrash: nil).isEmpty)
    }

    func testResultStampWinsAndIntentStampIsTheFallback() {
        var log = trash("r1", "~/Library/Caches/a", at: 1)
        log[1].stamp = T.stamp(55)
        XCTAssertEqual(History.runs(from: log, home: home, inTrash: nil)[0].items[0].record.stamp, T.stamp(55))
    }

    func testTheRecordCarriesTheKindOfTheItem() {
        XCTAssertEqual(History.runs(from: trash("r1", "~/Library/Caches/a", at: 1), home: home, inTrash: nil)[0].items[0].record.kind, .cache)
    }
}

final class WhyAndPlanTextTests: XCTestCase {
    func testEveryBlockReasonHasPlainWords() {
        let all: [BlockReason] = [.appleOwned, .neverList, .running, .runningUnknown, .protectedByMacOS, .iCloud, .dataless, .locked, .mountPoint, .linkEscapes,
                                  .otherVolume, .notLocalVolume, .sharedWithInstalled, .siblingInstalled, .listedOnly, .needsAdmin, .ownerMayBeElsewhere, .otherUser,
                                  .ownCopy, .changed]
        var seen = Set<String>()
        for r in all {
            let text = WhyText.reason(r)
            XCTAssertFalse(text.isEmpty)
            XCTAssertTrue(seen.insert(text).inserted, "each reason reads differently: \(text)")
            XCTAssertTrue(BannedPhrases.hits(in: text).isEmpty, text)
            XCTAssertFalse(text.contains("!"))
        }
        XCTAssertEqual(WhyText.reason(.running), "Running. Quit it first.")
        XCTAssertEqual(WhyText.reason(.listedOnly), "Listed only. Removing the file would not stop a job that is already loaded.")
        XCTAssertEqual(WhyText.reason(.needsAdmin), "Needs your administrator. Reveal in Finder or copy the path.")
    }

    func testConsequencesCoverEveryKind() {
        for kind in ResidueKind.allCases { XCTAssertFalse(WhyText.consequence(kind).isEmpty, "\(kind)") }
        XCTAssertEqual(WhyText.consequence(.cache), "Rebuilt automatically.")
        XCTAssertTrue(WhyText.consequence(.yourData).hasPrefix("Documents, sign-ins or history the app kept."))
    }

    func testWhyLineVariants() {
        let owner = T.app("com.example.notes", "Notes Pro")
        func line(_ kind: EvidenceKind, _ detail: String, name: String = "com.example.notes", blocked: BlockReason? = nil, extra: [Evidence] = []) -> String {
            let item = ResidueItem(path: "/Users/jane/Library/Caches/\(name)", ownerID: owner.bundleID, ruleID: "U3", kind: .cache, tier: .high,
                                   evidence: [Evidence(kind, detail)] + extra, blocked: blocked)
            return WhyText.line(for: item, owner: owner)
        }
        XCTAssertEqual(line(.exactID, "com.example.notes", extra: [Evidence(.noLiveOwner)]), "Named exactly com.example.notes; no installed app has this ID.")
        XCTAssertEqual(line(.exactID, "com.example.notes"), "Named exactly com.example.notes, the bundle ID of Notes Pro.")
        XCTAssertTrue(line(.exactID, "com.example.notes", name: "com.example.notes.ShipIt").hasPrefix("Starts with the bundle ID com.example.notes."))
        XCTAssertTrue(line(.helperSuffix, "helper").contains("helper of com.example.notes."))
        for kind in [EvidenceKind.exactID, .helperSuffix, .embeddedID, .teamPrefix, .groupID, .containerMetadata, .launchdLabelIsID, .receipt, .caskZap, .executableName, .displayName] { XCTAssertFalse(line(kind, "x1y2z3").contains("`"), "\(kind): the views show plain text") }
        XCTAssertTrue(line(.embeddedID, "com.example.notes.xpc").contains("com.example.notes.xpc"))
        XCTAssertTrue(line(.teamPrefix, "ABCDE12345").contains("Other apps from the same developer may use it."))
        XCTAssertTrue(line(.groupID, "group.com.example.notes").contains("group.com.example.notes"))
        XCTAssertTrue(line(.containerMetadata, "com.example.notes").contains("macOS lists this container"))
        XCTAssertTrue(line(.launchdProgramInBundle, "x").hasPrefix("Starts a program inside Notes Pro."))
        XCTAssertTrue(line(.launchdLabelIsID, "com.example.notes.agent").contains("com.example.notes.agent"))
        XCTAssertTrue(line(.launchdProgramGone, "x").contains("no longer there"))
        XCTAssertTrue(line(.receipt, "com.example.notes").contains("installer receipt"))
        XCTAssertTrue(line(.displayName, "Notes Pro").contains("nothing else confirms it"))
        XCTAssertTrue(line(.executableName, "NotesPro").contains("nothing else confirms it"))
        XCTAssertTrue(line(.exactID, "com.example.notes", blocked: .siblingInstalled).hasSuffix("Another installed copy of this app uses this."))
        XCTAssertTrue(line(.exactID, "com.example.notes", extra: [Evidence(.inventoryAbsent, "2026-09-23"), Evidence(.staleMtime, "45 days")]).contains("Last seen installed on 2026-09-23. Not changed for 45 days."))
        for kind in [EvidenceKind.exactID, .helperSuffix, .embeddedID, .teamPrefix, .groupID, .containerMetadata, .launchdLabelIsID, .launchdProgramInBundle, .launchdProgramGone,
                     .receipt, .caskZap, .displayName, .executableName] {
            XCTAssertTrue(BannedPhrases.hits(in: line(kind, "x")).isEmpty)
        }
    }

    func resultWith(items: Int, groups: Int, highEach: Int = 1) -> ScanResult {
        var gs: [ResidueGroup] = []
        for g in 0..<groups {
            var list: [ResidueItem] = []
            for i in 0..<(items / groups + (g == 0 ? items % groups : 0)) {
                let high = i < highEach
                list.append(ResidueItem(path: "/Users/jane/Library/Caches/g\(g)i\(i)", ownerID: "o\(g)", ruleID: "U3", kind: .cache, tier: high ? .high : .medium,
                                        size: high ? 600_000_000 / UInt64(highEach) : 1_000_000, sizeState: .measured))
            }
            gs.append(ResidueGroup(owner: T.app("com.example.a\(g)", "App \(g)"), isOrphan: true, items: list))
        }
        return ScanResult(scannedAt: T.now, kind: .orphans, groups: gs, coverage: Coverage(), home: T.home, osVersion: "26.1")
    }

    func testPreviewHeader() {
        // 41 items, 2 apps; 2 x 600 MB selected = 1.2 GB; the rest adds up to about 3.4 GB.
        var r = resultWith(items: 41, groups: 2)
        let rest = 41 - 2
        let restBytes = UInt64(3_400_000_000 - 1_200_000_000)
        for gi in r.groups.indices {
            for ii in r.groups[gi].items.indices where r.groups[gi].items[ii].tier == .medium { r.groups[gi].items[ii].size = restBytes / UInt64(rest) }
        }
        let text = PlanText.previewHeader(r)
        XCTAssertTrue(text.hasPrefix("Found 3.4 GB in 41 items for 2 apps. Caches, settings and other items that are safe to lose (1.2 GB) are ticked to start."), text)
        let none = resultWith(items: 3, groups: 1, highEach: 0)
        XCTAssertEqual(PlanText.previewHeader(none), "Found 3 MB in 3 items for 1 app. Nothing is ticked to start.")
        var partial = resultWith(items: 1, groups: 1)
        partial.groups[0].items[0].sizeState = .atLeast
        XCTAssertEqual(PlanText.previewHeader(partial), "Found at least 600 MB in 1 item for 1 app. Caches, settings and other items that are safe to lose (at least 600 MB) are ticked to start.")
        // An unmeasured item makes the total a floor too, and a measured High item beside it keeps its exact figure.
        var unmeasured = resultWith(items: 2, groups: 1, highEach: 1)
        unmeasured.groups[0].items[1].sizeState = .notMeasured
        unmeasured.groups[0].items[1].size = 0
        XCTAssertEqual(PlanText.previewHeader(unmeasured), "Found at least 600 MB in 2 items for 1 app. Caches, settings and other items that are safe to lose (600 MB) are ticked to start.")
        XCTAssertEqual(PlanText.previewHeader(ScanResult(scannedAt: T.now, kind: .orphans, groups: [], coverage: Coverage(places: [PlaceCoverage(root: .caches, state: .read)]),
                                                        home: T.home, osVersion: "26.1")), "Nothing found. Looked in the 1 place.")
    }

    func testCoverageLineIsHonest() {
        func cov(read: Int, prot: Int = 0, partial: Int = 0, failed: Int = 0, blind: Bool = false, folders: [String] = []) -> Coverage {
            let roots = LibraryRoot.allCases
            var places: [PlaceCoverage] = []
            var i = 0
            for (n, state) in [(read, PlaceState.read), (prot, .protectedByMacOS), (partial, .partial), (failed, .failed)] {
                for _ in 0..<n { places.append(PlaceCoverage(root: roots[i], state: state)); i += 1 }
            }
            return Coverage(places: places, processListUnreadable: blind, unreadableAppFolders: folders)
        }
        XCTAssertEqual(PlanText.coverageLine(cov(read: 15, prot: 3)), "Looked in 15 of 18 places. 3 protected by macOS.")
        XCTAssertEqual(PlanText.coverageLine(cov(read: 18)), "Looked in 18 of 18 places.")
        XCTAssertEqual(PlanText.coverageLine(cov(read: 14, prot: 2, partial: 1, failed: 1)), "Looked in 14 of 18 places. 2 protected by macOS. 1 only partly read. 1 could not be read.")
        XCTAssertTrue(PlanText.coverageLine(cov(read: 18, blind: true)).contains("Running apps could not be listed."))
        XCTAssertTrue(PlanText.coverageLine(cov(read: 18, folders: ["/Volumes/X/Applications"])).contains("1 app folder could not be read."))
        var missing = cov(read: 18)
        missing.volumeMayBeMissing = true
        missing.recentlyRemovedCount = 2
        XCTAssertEqual(PlanText.coverageLine(missing), "Looked in 18 of 18 places. A drive that may hold apps looks missing. "
                       + "2 apps removed less than 3 days ago are not listed yet. Scan again later.")
        XCTAssertEqual(PlanText.coverageLine(missing), PlanText.coverageLine(missing.facts), "one wording for the app, the card and the file")
    }

    func testButtonsResultsAndNotCovered() {
        XCTAssertEqual(PlanText.moveButton(count: 14), "Move 14 items to Trash")
        XCTAssertEqual(PlanText.moveButton(count: 1), "Move 1 item to Trash")
        for banned in ["Clean", "Erase", "Wipe", "Shred", "Destroy", "Secure"] { XCTAssertFalse(PlanText.moveButton(count: 3).contains(banned)) }
        func item(_ n: String, _ status: TrashStatus, _ size: UInt64, _ state: SizeState = .measured) -> ItemOutcome {
            ItemOutcome(item: ResidueItem(path: "/Users/jane/Library/Caches/\(n)", ownerID: "o", ruleID: "U3", kind: .cache, tier: .high, size: size, sizeState: state), status: status)
        }
        let ok = TrashOutcome(runID: "r", startedAt: T.now, finishedAt: T.now, results: [item("a", .moved, 100_000_000), item("b", .moved, 112_000_000), item("c", .blocked, 5)])
        XCTAssertEqual(PlanText.resultLine(ok), "Moved 2 items (212 MB) to Trash. Space is freed when you empty the Trash. Local snapshots can keep it in use for a while longer.")
        XCTAssertFalse(ok.movedBytesIsFloor)
        // A moved folder whose walk was cut short, or that was never measured, makes the total a floor; one that was not moved does not.
        let cut = TrashOutcome(runID: "r", startedAt: T.now, finishedAt: T.now, results: [item("a", .moved, 100_000_000), item("b", .moved, 112_000_000, .atLeast)])
        XCTAssertTrue(cut.movedBytesIsFloor)
        XCTAssertTrue(PlanText.resultLine(cut).hasPrefix("Moved 2 items (at least 212 MB) to Trash."), PlanText.resultLine(cut))
        XCTAssertFalse(TrashOutcome(runID: "r", startedAt: T.now, finishedAt: T.now, results: [item("a", .moved, 1), item("b", .blocked, 1, .atLeast)]).movedBytesIsFloor)
        let none = TrashOutcome(runID: "r", startedAt: T.now, finishedAt: T.now, results: [item("c", .notAttempted, 5)], abortReason: "The activity log is not writable, so nothing was changed.")
        XCTAssertEqual(PlanText.resultLine(none), "Nothing was moved. Stopped early: The activity log is not writable, so nothing was changed.")
        let lines = PlanText.notCovered()
        XCTAssertEqual(lines.count, 7)
        XCTAssertTrue(lines.joined(separator: " ").contains("Keychain items"))
        XCTAssertTrue(lines.joined(separator: " ").contains("iCloud data"))
        for text in [PlanText.resultLine(ok), PlanText.resultLine(none)] + lines { XCTAssertTrue(BannedPhrases.hits(in: text).isEmpty, text) }
    }

    func testEmptyStateOnlyClaimsNothingWhenEveryPlaceWasRead() {
        let full = ScanResult(scannedAt: T.now, kind: .orphans, groups: [],
                              coverage: Coverage(places: LibraryRoot.allCases.map { PlaceCoverage(root: $0, state: .read) }), home: T.home, osVersion: "26.1")
        XCTAssertEqual(PlanText.emptyState(full), "Nothing found. Looked in all 26 places.")
        var part = full
        part.coverage.places[0].state = .protectedByMacOS
        XCTAssertEqual(PlanText.emptyState(part), "Nothing found in the places I could read.")
        part = full
        part.coverage.processListUnreadable = true
        XCTAssertEqual(PlanText.emptyState(part), "Nothing found in the places I could read.")
    }
}

final class RedactionTests: XCTestCase {
    func testLabelsAreStableAndShared() {
        let a = T.app("com.example.a", "A App"), b = T.app("com.example.b", "B App")
        XCTAssertEqual(Redaction.labels(for: [a, b, a]), ["com.example.a": "App 1", "com.example.b": "App 2"])
        XCTAssertEqual(Redaction.labels(for: []), [:])
    }

    func testApplyReplacesEverySpelling() {
        let owner = T.app("com.example.orbitmeet", "Orbit Meet 6.2", exec: "OrbitMeet", team: "ABCDE12345", embedded: ["com.example.orbitmeet.helper"], groups: ["group.com.example.orbitmeet"])
        let text = "~/Library/Caches/com.example.orbitmeet.helper and ~/Library/Application Support/Orbit Meet, orbit-meet, ORBITMEET, OrbitMeet_2026.ips, ABCDE12345.shared, group.com.example.orbitmeet"
        let out = Redaction.apply(text, owner: owner, label: "App 1")
        for leak in ["orbit", "Orbit", "ORBIT", "ABCDE", "com.example"] { XCTAssertFalse(out.lowercased().contains(leak.lowercased()), "\(leak) leaked: \(out)") }
        XCTAssertTrue(out.contains("~/Library/Caches/App 1"))
        // A label that contains a token must not be replaced twice.
        let appOwner = T.app("com.example.app", "App", exec: "AppTool")
        XCTAssertEqual(Redaction.apply("com.example.app and App", owner: appOwner, label: "App 1"), "App 1 and App 1")
    }
}

final class BannedPhrasesTests: XCTestCase {
    func fileLines() throws -> [String] {
        let url = T.repoRoot().appendingPathComponent("tools/banned_phrases.txt")
        return try String(contentsOf: url, encoding: .utf8).split(separator: "\n").map(String.init).filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("#") && !$0.trimmingCharacters(in: .whitespaces).isEmpty }
    }

    func testPatternsEqualTheToolsFile() throws {
        XCTAssertEqual(BannedPhrases.patterns, try fileLines())
    }

    func testEveryBannedExampleIsCaughtAndHonestCopyIsNot() {
        let bad = ["This app will securely erase your files", "Use Secure Delete for sensitive data", "Your data is permanently deleted", "The files are permanently gone",
                   "It leaves unrecoverable gaps", "irrecoverable", "data cannot be recovered", "a forensic-proof cleaner", "anti-forensic mode", "military grade", "meets DoD standards",
                   "the NSA cannot read it", "Gutmann 35 pass", "a file shredder", "Wipe the leftovers", "100% gone", "We guarantee it", "a certified eraser", "certificate of destruction",
                   "NIST compliant", "GDPR ready", "HIPAA safe", "clean your Mac in one click", "remove junk files"]
        for text in bad { XCTAssertFalse(BannedPhrases.hits(in: text).isEmpty, text) }
        let good = ["Moved 3 items to the Trash. Undo from History.", "Erase readiness: FileVault is on.", "Looked in 14 of 18 places.", "Found 3.4 GB in 41 items for 2 apps.",
                    "This is flash storage, so overwriting a file may not reach every copy.", "Not reachable by this app: unified log, FSEvents, snapshots."]
        for text in good { XCTAssertTrue(BannedPhrases.hits(in: text).isEmpty, text) }
    }

    func testMarkerCaseAndLines() {
        XCTAssertTrue(BannedPhrases.hits(in: "We never say unrecoverable.  no-claim-ok").isEmpty)
        XCTAssertEqual(BannedPhrases.hits(in: "fine\nUNRECOVERABLE\nalso fine").count, 1)
        XCTAssertEqual(BannedPhrases.hits(in: "unrecoverable no-claim-ok\nWipe it"), ["Wipe"])
        XCTAssertEqual(BannedPhrases.hits(in: "SECURELY   ERASE"), ["SECURELY   ERASE"])
        XCTAssertTrue(BannedPhrases.hits(in: "swipe left, junkyard, shredded paper").count == 1, "\\bwipe must not match 'swipe'; \\bshred matches 'shredded'")
    }
}

final class DiagnosticsTextTests: XCTestCase {
    func testNoNamesNoPaths() {
        let places = [PlaceCoverage(root: .caches, state: .read, entryCount: 12), PlaceCoverage(root: .containers, state: .protectedByMacOS, errno: 1),
                      PlaceCoverage(root: .systemLaunchDaemons, state: .absent)]
        let facts = ReadinessFacts(fileVault: .on, storage: .solidState, fileSystem: "APFS", isAppleSilicon: true, localSnapshotCount: 3, failedProbes: ["tmutil"])
        let text = DiagnosticsText.text(coverage: Coverage(places: places), installedCount: 87, osVersion: "26.1", appVersion: "0.1.0", readiness: facts)
        XCTAssertTrue(text.hasPrefix("Aftertaste 0.1.0 on macOS 26.1"))
        XCTAssertTrue(text.contains("Installed apps found: 87"))
        XCTAssertTrue(text.contains("~/Library/Caches | read | - | 12"))
        XCTAssertTrue(text.contains("~/Library/Containers | protectedByMacOS | 1 | 0"))
        XCTAssertTrue(text.contains("/Library/LaunchDaemons | absent | - | 0"))
        XCTAssertTrue(text.contains("Looked in 2 of 3 places; 1 protected, 0 partial, 0 failed"))
        XCTAssertTrue(text.contains("Local snapshots: 3"))
        XCTAssertFalse(text.contains("/Users"))
        XCTAssertFalse(text.contains("jane"))
        let bare = DiagnosticsText.text(coverage: Coverage(), installedCount: 0, osVersion: "", appVersion: "", readiness: nil)
        XCTAssertTrue(bare.contains("(unknown)"))
    }
}
