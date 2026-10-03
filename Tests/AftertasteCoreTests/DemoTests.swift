import XCTest
@testable import AftertasteCore

/// The demo scenarios (BUILD_PLAN §9). They run through the real Core (`Scan.analyze`, `TrashPlanner`, `GuardPolicy`,
/// `Stamps`, `History`, the text), so these tests also say whether the numbers in the sample data still add up after a
/// rule changes.
final class DemoTests: XCTestCase {
    static let now = Date(timeIntervalSince1970: 1_791_021_600)   // 2026-10-03 10:00 UTC
    static let home = DemoScenarios.home

    func backend(_ s: DemoScenario) -> Backend { DemoBackend.make(s, seconds: 0, now: { DemoTests.now }) }

    func group(_ r: ScanResult, _ id: String) throws -> ResidueGroup {
        try XCTUnwrap(r.groups.first { $0.owner.bundleID == id }, "no group for \(id)")
    }

    func item(_ g: ResidueGroup, _ path: String) throws -> ResidueItem {
        try XCTUnwrap(g.items.first { $0.path == Self.home + path }, "no item at \(path)")
    }

    // MARK: the worlds

    func testWorldsAreWellFormed() {
        for s in DemoScenario.allCases {
            let w = DemoScenarios.world(s, now: Self.now)
            let paths = w.seeds.map(\.path)
            XCTAssertEqual(paths.count, Set(paths).count, "\(s): duplicate path")
            for p in paths + w.installed.map(\.bundlePath) {
                XCTAssertTrue(p.hasPrefix(Self.home + "/") || p.hasPrefix("/Library/") || p.hasPrefix("/private/var/db/receipts/") || p.hasPrefix("/Applications/"),
                              "\(s): stray path \(p)")
            }
            for a in w.installed + w.inventory.map(\.identity) {
                XCTAssertTrue(StrictBundleID.isValid(a.bundleID), a.bundleID)
                XCTAssertTrue(a.bundleID.hasPrefix("com.example."), "demo apps are fictional: \(a.bundleID)")
                if let team = a.teamID { XCTAssertEqual(team.count, 10, a.bundleID) }
            }
            XCTAssertEqual(w.library(present: w.paths, stamps: w.stamps(now: Self.now), now: Self.now).listings.count, LibraryRoot.allCases.count)
            // A removed app is remembered by the inventory, not installed.
            let installed = Set(w.installed.map(\.bundleID))
            for r in w.inventory where !installed.contains(r.identity.bundleID) { XCTAssertLessThan(r.lastSeen, Self.now) }
        }
    }

    func testScenariosAreDeterministic() async {
        for s in DemoScenario.allCases {
            let a = await backend(s).scan(.orphans, .default)
            let b = await backend(s).scan(.orphans, .default)
            XCTAssertEqual(a, b, "\(s)")
            XCTAssertEqual(DemoScenarios.history(for: s, now: Self.now), DemoScenarios.history(for: s, now: Self.now))
        }
    }

    func testCoverageIsHonest() async {
        let quiet = await backend(.quiet).scan(.orphans, .default)
        XCTAssertTrue(quiet.isCleanAndComplete, "quiet: nothing found, every place looked at")
        XCTAssertEqual(quiet.coverage.total, LibraryRoot.allCases.count)
        let leftovers = await backend(.leftovers).scan(.orphans, .default)
        XCTAssertEqual(leftovers.coverage.protectedCount, 1)
        XCTAssertEqual(leftovers.coverage.looked, leftovers.coverage.total - 1)
        let blocked = await backend(.blocked).scan(.orphans, .default)
        XCTAssertEqual(blocked.coverage.protectedCount, 2)
        XCTAssertEqual(blocked.coverage.looked, blocked.coverage.total - 2)
        XCTAssertFalse(blocked.isCleanAndComplete)
        XCTAssertFalse(blocked.groups.isEmpty, "never 0 leftovers when macOS protected folders: they are shown by name")
        for s in DemoScenario.allCases {
            let r = await backend(s).scan(.orphans, .default)
            XCTAssertEqual(r.isCleanAndComplete, r.groups.isEmpty && r.coverage.protectedCount == 0, "\(s)")
        }
    }

    // MARK: the cast

    func testOrbitMeetAddsUp() async throws {
        let r = await backend(.leftovers).scan(.orphans, .default)
        XCTAssertEqual(Set(r.groups.map(\.owner.bundleID)), [
            "com.example.orbitmeet", "com.example.lumenplayer", "com.example.harborvpn", "com.example.quilleditor",
            "com.example.glowphotos", "com.example.parcel.word"])
        XCTAssertTrue(r.groups.allSatisfy(\.isOrphan))
        XCTAssertNil(r.groups.first { $0.owner.bundleID == "com.example.paperplane" }, "an installed app has no leftovers")
        let orbit = try group(r, "com.example.orbitmeet")
        XCTAssertEqual(orbit.items.reduce(0) { $0 + $1.fileCount }, 214)
        XCTAssertEqual(orbit.items.filter { $0.ruleID == "U12" }.count, 2, "two user launch agents")
        XCTAssertEqual(orbit.items.filter { $0.ruleID == "S7" }.count, 1, "one privileged helper")
        XCTAssertEqual(orbit.items.filter { $0.ruleID == "S5" }.count, 0, "the card counts every launch item: no daemon here")
        XCTAssertTrue(orbit.items.filter { $0.ruleID == "U12" }.allSatisfy { $0.tier == .handsOff && $0.blocked == .listedOnly })
        XCTAssertTrue(orbit.items.filter { $0.ruleID == "S7" }.allSatisfy { $0.tier == .needsAdmin })
        XCTAssertEqual(Format.bytes(orbit.totalBytes), "1.3 GB")
        XCTAssertEqual(orbit.runState, .notRunning)
        XCTAssertEqual(r.groups.first?.owner.bundleID, "com.example.orbitmeet", "largest first")
    }

    func testTheCardForOrbitMeet() async throws {
        var r = await backend(.leftovers).scan(.orphans, .default)
        r.groups = [try group(r, "com.example.orbitmeet")]
        let report = TraceReportText.report(from: r, options: .init(hideNames: false, includeRows: true, appVersion: "demo", isSample: true), now: Self.now)
        let card = TraceReportText.card(from: report)
        XCTAssertEqual(TraceReportText.headline(card), "Orbit Meet 6.2 left behind")
        XCTAssertEqual(TraceReportText.figures(card), "214 files · 1.3 GB · 2 launch agents · 1 privileged helper")
        XCTAssertEqual(TraceReportText.coverage(card), "Looked in \(LibraryRoot.allCases.count - 1) of \(LibraryRoot.allCases.count) places. 1 protected by macOS.")
        XCTAssertTrue(card.isSample)
    }

    func testEveryTierShowsUp() async throws {
        let r = await backend(.leftovers).scan(.orphans, .default)
        let all = Set(r.items.map(\.tier))
        XCTAssertTrue(all.isSuperset(of: [.high, .medium, .low, .handsOff, .needsAdmin]), "\(all)")
        let quill = try group(r, "com.example.quilleditor")
        XCTAssertEqual(try item(quill, "/Library/Application Support/Quill Editor").tier, .low, "name-only is Review")
        let glow = try group(r, "com.example.glowphotos")
        let shared = try item(glow, "/Library/Group Containers/H7J6K5L4M3.glow")
        XCTAssertEqual(shared.tier, .handsOff, "an installed app has the same Team ID")
        let cache = try item(glow, "/Library/Caches/com.example.glowphotos")
        XCTAssertEqual(cache.tier, .medium, "Glow Camera from the same developer is installed: the cache is capped below High")
        XCTAssertTrue(cache.evidence.contains(Evidence(.sameTeamInstalled, "Glow Camera")))
        XCTAssertTrue(shared.blocked == .sharedWithInstalled || shared.blocked == .siblingInstalled, "\(String(describing: shared.blocked))")
        let parcel = try group(r, "com.example.parcel.word")
        XCTAssertEqual(try item(parcel, "/Library/Group Containers/Z9Y8X7W6V5.parcel").tier, .low, "suite-wide group container: Review")
    }

    func testOnlyHighIsPreselected() async throws {
        for s in DemoScenario.allCases {
            let r = await backend(s).scan(.orphans, .default)
            let picked = ItemSelection.preselected(r)
            XCTAssertEqual(picked, Set(r.items.filter { $0.tier == .high }.map(\.path)), "\(s)")
        }
        let maybe = await backend(.maybeOnly).scan(.orphans, .default)
        XCTAssertFalse(maybe.items.isEmpty)
        XCTAssertEqual(maybe.preselectedCount, 0, "maybe-only: nothing is ticked")
        XCTAssertTrue(maybe.items.allSatisfy { $0.tier == .medium || $0.tier == .low })
        let admin = await backend(.adminRows).scan(.orphans, .default)
        XCTAssertGreaterThanOrEqual(admin.items.filter { $0.tier == .needsAdmin }.count, 6)
        XCTAssertEqual(admin.preselectedCount, 0, "admin-rows: nothing is ticked")
        XCTAssertTrue(admin.items.filter { $0.root?.isSystem == true }.allSatisfy { $0.tier == .needsAdmin && $0.requiresAdmin })
        let leftovers = await backend(.leftovers).scan(.orphans, .default)
        let picked = ItemSelection.preselected(leftovers)
        XCTAssertTrue(picked.contains(Self.home + "/Library/Caches/com.example.harborvpn"), "the scripted EPERM item is ticked")
        XCTAssertTrue(picked.contains(Self.home + "/Library/Logs/com.example.lumenplayer"), "the scripted changed item is ticked")
    }

    func testBlockedRowsAreShownByName() async {
        let r = await backend(.blocked).scan(.orphans, .default)
        let rows = r.items.filter { $0.root == .containers || $0.root == .groupContainers }
        XCTAssertFalse(rows.isEmpty)
        XCTAssertTrue(rows.allSatisfy { $0.tier == .handsOff && $0.blocked != nil && $0.sizeState == .notMeasured }, "\(rows.map(\.tier))")
        XCTAssertTrue(rows.contains { $0.blocked == .protectedByMacOS }, "macOS protected: said by name")
    }

    func testBlockedScenarioAlsoShowsARunningOwnerAtTheTop() async throws {
        let r = await backend(.blocked).scan(.orphans, .default)
        let first = try XCTUnwrap(r.groups.first)
        XCTAssertEqual(first.owner.bundleID, "com.example.orbitmeet", "the biggest card is first")
        XCTAssertEqual(first.runState, .running, "the card the window opens on says so")
        XCTAssertTrue(r.groups.dropFirst().allSatisfy { $0.runState == .notRunning })
        // Ticked as always (the tiers do not change), but the planner never proposes a running app's items.
        let ticked = ItemSelection.preselected(r)
        XCTAssertTrue(first.items.contains { $0.tier == .high && ticked.contains($0.id) })
        let plan = makePlan(r)
        XCTAssertTrue(plan.items.allSatisfy { $0.ownerID != first.owner.bundleID })
        XCTAssertTrue(plan.skipped.contains { $0.reason == WhyText.reason(.running) })
        XCTAssertFalse(plan.items.isEmpty, "other apps still move")
        // The same world without the block does not have it: the leftovers scenario is unchanged.
        let calm = await backend(.leftovers).scan(.orphans, .default)
        XCTAssertTrue(calm.groups.allSatisfy { $0.runState == .notRunning })
    }

    func testAnUnscriptedRunMovesEveryTickedItem() async throws {
        let b = DemoBackend.make(.leftovers, seconds: 0, scripted: false, now: { DemoTests.now })
        let scripted = DemoScenarios.world(.leftovers, now: Self.now)
        let plain = DemoScenarios.world(.leftovers, now: Self.now, scripted: false)
        XCTAssertFalse(scripted.refuses.isEmpty || scripted.drifts.isEmpty, "the default keeps both failures")
        XCTAssertTrue(plain.refuses.isEmpty && plain.drifts.isEmpty)
        XCTAssertEqual(plain.seeds.map(\.path), scripted.seeds.map(\.path), "only the outcomes differ, not what is on disk")
        let before = await b.scan(.orphans, .default)
        let plan = makePlan(before)
        XCTAssertEqual(plan.items.count, 6, "the High rows of the sample: what the hero's button says")
        let outcome = await b.trash(plan, .default) { _ in }
        XCTAssertEqual(outcome.movedCount, plan.items.count)
        XCTAssertTrue(outcome.results.allSatisfy { $0.status == .moved })
        let after = await b.scan(.orphans, .default)
        XCTAssertEqual(after.items.count, before.items.count - plan.items.count, "the list behind the sheet loses exactly what moved")
        XCTAssertEqual(after.preselectedCount, 0, "nothing is left ticked")
    }

    // MARK: uninstall now

    func testUninstallNowOfPaperplaneNotes() async throws {
        let b = backend(.leftovers)
        let lookup = await b.identify(DemoScenarios.uninstallTarget)
        let app = try XCTUnwrap(lookup.identity)
        XCTAssertEqual(app.bundleID, "com.example.paperplane")
        XCTAssertTrue(app.bundleOwnerUID == 501)
        let r = await b.scan(.app(app), .default)
        let g = try group(r, "com.example.paperplane")
        XCTAssertFalse(g.isOrphan)
        let bundle = try XCTUnwrap(g.items.first)
        XCTAssertEqual(bundle.ruleID, "APP")
        XCTAssertEqual(bundle.tier, .high)
        XCTAssertNotNil(bundle.stamp, "the run needs something to compare")
        XCTAssertEqual(try item(g, "/Library/Containers/com.example.paperplane").tier, .medium, "your data is never ticked")
        XCTAssertEqual(try item(g, "/Library/Preferences/com.example.paperplane.plist").tier, .high)
        // Rejections read as the rest of the app words them.
        for (path, reason) in [("/System/Applications/Calculator.app", "macOS apps from Apple are never touched."),
                               ("/Applications/Aftertaste.app", "Aftertaste does not remove itself."),
                               ("/tmp/notes.txt", "That is not an app."),
                               ("/Applications/Tern Browser.app/Contents/Helper.app", "That app is inside another app.")] {
            let l = await b.identify(path)
            XCTAssertNil(l.identity, path)
            XCTAssertEqual(l.rejection, reason)
        }
    }

    func testAnAppOnlyAnAdministratorCanMoveShowsNeedsAdminRowsOnly() async throws {
        let b = backend(.adminRows)
        let lookup = await b.identify("/Applications/Atlas Disk Tools.app")
        let atlas = try XCTUnwrap(lookup.identity)
        XCTAssertTrue(atlas.bundleNeedsAdmin)
        let r = await b.scan(.app(atlas), .default)
        let g = try group(r, "com.example.atlasdisk")
        XCTAssertGreaterThanOrEqual(g.items.count, 6)
        XCTAssertTrue(g.items.allSatisfy { $0.tier == .needsAdmin }, "\(g.items.map(\.tier))")
        XCTAssertEqual(r.preselectedCount, 0)
        XCTAssertTrue(ItemSelection.preselected(r).isEmpty)
    }

    // MARK: a run, and its undo

    func makePlan(_ r: ScanResult, _ id: String = "demo-run") -> TrashPlan {
        TrashPlanner.plan(from: r, ticked: ItemSelection.preselected(r), mode: .bulk(acknowledgedMedium: false), now: Self.now, runID: id)
    }

    func testARunReportsEveryOutcomeAndUndoPutsItBack() async throws {
        let b = backend(.leftovers)
        let before = await b.scan(.orphans, .default)
        let plan = makePlan(before)
        XCTAssertFalse(plan.items.isEmpty)
        let seen = Box()
        let outcome = await b.trash(plan, .default) { seen.add($0) }
        XCTAssertEqual(seen.count, plan.items.count, "progress for every item")
        XCTAssertEqual(outcome.results.count, plan.items.count)
        let byPath = Dictionary(uniqueKeysWithValues: outcome.results.map { ($0.item.path, $0) })
        let harbor = try XCTUnwrap(byPath[Self.home + "/Library/Caches/com.example.harborvpn"])
        XCTAssertEqual(harbor.status, .protectedByMacOS)
        XCTAssertEqual(harbor.errno, 1)
        let lumen = try XCTUnwrap(byPath[Self.home + "/Library/Logs/com.example.lumenplayer"])
        XCTAssertEqual(lumen.status, .changedSinceScan, "the real Stamps check says so")
        XCTAssertEqual(lumen.detail, "Changed since you reviewed it.")
        XCTAssertEqual(outcome.movedCount, plan.items.count - 2)
        XCTAssertTrue(outcome.moved.allSatisfy { ($0.trashedPath ?? "").hasPrefix(DemoScenarios.trashFolder + "/") })
        XCTAssertGreaterThan(outcome.movedBytes, 0)

        // The journal: a run line pair, an intent before every result of a moved item, nothing for the one stopped early.
        let log = b.loadLog()
        let mine = log.filter { $0.runID == plan.runID }
        XCTAssertEqual(mine.filter { $0.verb == .run }.count, 2)
        for o in outcome.moved {
            let lines = mine.filter { $0.verb == .trash && $0.path == PathText.tilde(o.item.path, home: Self.home) }
            XCTAssertEqual(lines.map(\.phase), [.intent, .result])
            XCTAssertEqual(lines.last?.status, .moved)
            XCTAssertNotNil(lines.last?.stamp)
        }
        let changed = mine.filter { $0.path == PathText.tilde(lumen.item.path, home: Self.home) }
        XCTAssertEqual(changed.map(\.phase), [.result], "stopped before the move: no intent")
        for line in log { XCTAssertEqual(ActivityLog.decode(line: ActivityLog.encode(line)), line) }

        // Gone from the next scan; History offers Undo for exactly what moved.
        let after = await b.scan(.orphans, .default)
        let left = Set(after.items.map(\.path))
        for o in outcome.moved { XCTAssertFalse(left.contains(o.item.path)) }
        XCTAssertTrue(left.contains(harbor.item.path) && left.contains(lumen.item.path))
        let runs = History.runs(from: b.loadLog(), home: Self.home, inTrash: nil)
        let newest = try XCTUnwrap(runs.first { $0.runID == plan.runID })
        XCTAssertEqual(newest.undoable.count, outcome.movedCount)
        XCTAssertEqual(b.inTrash(newest.undoable), Set(newest.undoable.map(\.id)))

        let undone = await b.undo(newest.undoable) { _ in }
        XCTAssertEqual(undone.restoredCount, outcome.movedCount)
        let restored = await b.scan(.orphans, .default)
        XCTAssertEqual(Set(restored.items.map(\.path)), Set(before.items.map(\.path)), "everything is back")
        XCTAssertTrue(b.inTrash(newest.undoable).isEmpty)
        let again = await b.undo(newest.undoable) { _ in }
        XCTAssertTrue(again.results.allSatisfy { $0.status == .alreadyEmptied }, "a second Undo has nothing to put back")
    }

    func testUndoNeverOverwrites() async throws {
        let b = backend(.leftovers)
        let before = await b.scan(.orphans, .default)
        let outcome = await b.trash(makePlan(before), .default) { _ in }
        let newest = try XCTUnwrap(History.runs(from: b.loadLog(), home: Self.home, inTrash: nil).first)
        // Put one item back by hand, then ask for all of them: that one is in the way and nothing is overwritten.
        let first = try XCTUnwrap(newest.undoable.first)
        _ = await b.undo([first]) { _ in }
        let outcomeAll = await b.undo(newest.undoable) { _ in }
        XCTAssertEqual(outcomeAll.results.first { $0.record == first }?.status, .alreadyEmptied)
        XCTAssertEqual(outcomeAll.restoredCount, outcome.movedCount - 1)
    }

    func testTheExecutorRefusesWhatAPlanShouldNeverCarry() async throws {
        let b = backend(.leftovers)
        let r = await b.scan(.orphans, .default)
        let orbit = try group(r, "com.example.orbitmeet")
        let agent = try XCTUnwrap(orbit.items.first { $0.ruleID == "U12" })
        let installed = await b.installedApps().apps
        let tern = try XCTUnwrap(installed.first { $0.bundleID == "com.example.tern" })
        let running = ResidueItem(path: Self.home + "/Library/Caches/com.example.tern", ownerID: tern.bundleID, ruleID: "U3", root: .caches,
                                  kind: .cache, tier: .high)
        let ghost = ResidueItem(path: Self.home + "/Library/Caches/com.example.nothere", ownerID: orbit.owner.bundleID, ruleID: "U3",
                                root: .caches, kind: .cache, tier: .high)
        let plan = TrashPlan(runID: "forced", createdAt: Self.now, kind: .orphans, owners: [orbit.owner, tern], items: [agent, running, ghost])
        let outcome = await b.trash(plan, .default) { _ in }
        XCTAssertEqual(outcome.results.map(\.status), [.blocked, .blocked, .alreadyGone])
        XCTAssertEqual(outcome.results[1].detail, WhyText.reason(.running))
        XCTAssertEqual(outcome.movedCount, 0)
        let state = b.runState(tern)
        XCTAssertEqual(state, .running)
        let orbitState = b.runState(orbit.owner)
        XCTAssertEqual(orbitState, .notRunning)
    }

    func testUninstallNowRunMovesTheBundleFirstAndItLeavesTheInstalledList() async throws {
        let b = backend(.leftovers)
        let lookup = await b.identify(DemoScenarios.uninstallTarget)
        let app = try XCTUnwrap(lookup.identity)
        let r = await b.scan(.app(app), .default)
        let plan = makePlan(r)
        XCTAssertEqual(plan.items.first?.ruleID, "APP")
        let outcome = await b.trash(plan, .default) { _ in }
        XCTAssertEqual(outcome.results.first?.status, .moved)
        let installed = await b.installedApps().apps.map(\.bundleID)
        XCTAssertFalse(installed.contains("com.example.paperplane"))
        let mine = try XCTUnwrap(History.runs(from: b.loadLog(), home: Self.home, inTrash: nil).first { $0.runID == plan.runID })
        let undone = await b.undo(mine.undoable) { _ in }
        XCTAssertEqual(undone.restoredCount, outcome.movedCount)
        let back = await b.installedApps().apps.map(\.bundleID)
        XCTAssertTrue(back.contains("com.example.paperplane"))
    }

    // MARK: history, readiness, honest copy

    func testHistoryIsSeededWithTwoPastRuns() async throws {
        let b = backend(.leftovers)
        let all = History.runs(from: b.loadLog(), home: Self.home, inTrash: nil)
        XCTAssertEqual(all.count, 2)
        let records = all.flatMap { $0.items.map(\.record) }
        let there = b.inTrash(records)
        let runs = History.runs(from: b.loadLog(), home: Self.home, inTrash: there)
        let emptied = try XCTUnwrap(runs.first { $0.label == "Cobalt Chat" })
        let kept = try XCTUnwrap(runs.first { $0.label == "Pixel Pad" })
        XCTAssertTrue(emptied.items.allSatisfy { $0.state == .emptied }, "one run is Already emptied")
        XCTAssertTrue(kept.items.allSatisfy { $0.state == .inTrash })
        XCTAssertEqual(kept.undoable.count, 3)
        for s in [DemoScenario.quiet, .firstRun] { XCTAssertTrue(backend(s).loadLog().isEmpty, "\(s): nothing has ever run") }
    }

    func testReadinessVariantsNeverGuess() {
        let variants = DemoScenarios.readinessVariants(now: Self.now)
        XCTAssertEqual(variants.count, 5)
        for (name, facts) in variants {
            let lines = ReadinessText.lines(facts)
            XCTAssertFalse(lines.isEmpty, name)
            for l in lines { XCTAssertTrue(BannedPhrases.hits(in: l.title + " " + l.body).isEmpty, "\(name): \(l.body)") }
        }
        let bad = ReadinessText.lines(variants[3].facts).map(\.body).joined(separator: " ")
        XCTAssertTrue(bad.contains("could not be read") || bad.contains("could not be listed"), bad)
        let snaps = ReadinessText.lines(DemoScenarios.readiness(for: .snapshots, now: Self.now))
        XCTAssertTrue(snaps.contains { $0.tone == .attention && $0.body.contains("3 local snapshots") }, "\(snaps)")
        XCTAssertEqual(DemoScenarios.readiness(for: .snapshots, now: Self.now).fileVault, .off)
        XCTAssertEqual(DemoScenarios.readiness(for: .leftovers, now: Self.now).localSnapshotCount, 0)
    }

    func testBackendServesTheScenarioReadinessAndDiagnostics() async {
        let b = backend(.snapshots)
        XCTAssertTrue(b.isDemo)
        let facts = await b.readiness()
        XCTAssertEqual(facts.localSnapshotCount, 3)
        let text = await b.diagnostics()
        XCTAssertFalse(text.isEmpty)
        XCTAssertFalse(text.contains(Self.home), "diagnostics carry no paths")
    }

    func testNothingTheDemoSaysIsBanned() async {
        for s in DemoScenario.allCases {
            let b = backend(s)
            var words = b.loadLog().flatMap { [$0.label, $0.why, $0.detail ?? ""] }
            let r = await b.scan(.orphans, .default)
            words += r.items.map(\.why)
            let outcome = await b.trash(makePlan(r), .default) { _ in }
            words += outcome.results.compactMap(\.detail)
            words += ["That is not an app.", "macOS apps from Apple are never touched.", "Aftertaste does not remove itself.", "That app is not part of the sample data."]
            for w in words { XCTAssertTrue(BannedPhrases.hits(in: w).isEmpty, "\(s): \(w)") }
        }
    }
}

/// Collects progress callbacks from a `@Sendable` closure.
final class Box: @unchecked Sendable {
    private let lock = NSLock()
    private var items: [ItemOutcome] = []
    func add(_ o: ItemOutcome) { lock.lock(); items.append(o); lock.unlock() }
    var count: Int { lock.lock(); defer { lock.unlock() }; return items.count }
}
