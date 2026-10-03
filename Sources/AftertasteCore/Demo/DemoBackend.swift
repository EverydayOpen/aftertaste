import Foundation

/// The demo implementation of `Backend` (BUILD_PLAN §9): serves a scenario's synthetic Mac and mutates an in-memory copy.
/// Nothing is read from or written to the real system; the activity log lives in memory. The scan is the real
/// `Scan.analyze`, and a run re-verifies every item with the real `GuardPolicy`, `Stamps` and `RunningCheck` against that
/// copy, like the live backend does against the disk.
public enum DemoBackend {
    /// `seconds` is how long a whole run takes (staggered per item, so the list animates); 0 for tests.
    /// `now` is the only clock: it stamps the world once and every log line.
    public static func make(_ scenario: DemoScenario, seconds: Double = 1.2,
                            now: @escaping @Sendable () -> Date = { Date() }) -> Backend {
        let state = DemoState(DemoScenarios.world(scenario, now: now()), start: now())
        return Backend(
            installedApps: { state.installedSnapshot() },
            identify: { state.identify($0) },
            scan: { request, prefs in state.scan(request, prefs) },
            runState: { owner in RunningCheck.state(owner: owner, itemPath: "/var/empty", snapshot: state.world.running) },
            trash: { plan, prefs, progress in
                await run(plan, prefs, progress, state: state, seconds: seconds, now: now)
            },
            undo: { records, progress in
                var results: [UndoItemOutcome] = []
                for record in records {
                    let outcome = state.restore(record, at: now())
                    progress(outcome)
                    results.append(outcome)
                }
                return UndoOutcome(results: results)
            },
            inTrash: { state.inTrash($0) },
            readiness: { state.world.readiness },
            loadLog: { state.log },
            diagnostics: { state.diagnostics() },
            isDemo: true)
    }

    private static func run(_ plan: TrashPlan, _ prefs: Preferences, _ progress: @escaping @Sendable (ItemOutcome) -> Void,
                            state: DemoState, seconds: Double, now: @escaping @Sendable () -> Date) async -> TrashOutcome {
        let startedAt = now()
        state.append(ActivityEntry(timestamp: startedAt, runID: plan.runID, verb: .run, phase: .intent))
        state.driftOnce()
        let pause = UInt64(max(seconds, 0) / Double(max(plan.items.count, 1)) * 1_000_000_000)
        var results: [ItemOutcome] = []
        for item in plan.items {   // already in execution order
            if pause > 0 { try? await Task.sleep(nanoseconds: pause) }
            let owner = plan.owners.first { $0.bundleID == item.ownerID }
            let outcome = state.attempt(item, owner: owner, plan: plan, prefs: prefs, at: now())
            results.append(outcome)
            progress(outcome)
        }
        let finishedAt = now()
        state.append(ActivityEntry(timestamp: finishedAt, runID: plan.runID, verb: .run, phase: .result))
        return TrashOutcome(runID: plan.runID, startedAt: startedAt, finishedAt: finishedAt, results: results, skipped: plan.skipped)
    }
}

/// The mutable copy behind one demo backend: what exists, what is in the Trash, and the log.
final class DemoState: @unchecked Sendable {
    let world: DemoScenarios.World
    private let start: Date
    private let lock = NSLock()
    private var present: Set<String>
    private var stamps: [String: FileStamp]
    private var trashed: Set<String>
    private var entries: [ActivityEntry]
    private var drifted = false

    init(_ world: DemoScenarios.World, start: Date) {
        self.world = world
        self.start = start
        present = world.paths
        stamps = world.stamps(now: start)
        trashed = world.inTrash
        entries = world.log
    }

    var log: [ActivityEntry] {
        lock.lock()
        defer { lock.unlock() }
        return entries
    }

    func append(_ entry: ActivityEntry) {
        lock.lock()
        defer { lock.unlock() }
        entries.append(entry)
    }

    // MARK: reads

    func installedSnapshot() -> InstalledSnapshot {
        lock.lock()
        defer { lock.unlock() }
        return installedLocked()
    }

    private func installedLocked() -> InstalledSnapshot {
        InstalledSnapshot(apps: world.installed.filter { present.contains($0.bundlePath) }, capturedAt: start)
    }

    func identify(_ appPath: String) -> AppLookup {
        if let app = installedSnapshot().apps.first(where: { $0.bundlePath == appPath }) { return AppLookup(identity: app) }
        let last = appPath.split(separator: "/").last.map(String.init) ?? ""
        if appPath.contains(".app/") { return AppLookup(rejection: "That app is inside another app.") }
        if !last.hasSuffix(".app") { return AppLookup(rejection: "That is not an app.") }
        if appPath.hasPrefix("/System/") { return AppLookup(rejection: "macOS apps from Apple are never touched.") }
        if last == "Aftertaste.app" { return AppLookup(rejection: "Aftertaste does not remove itself.") }
        return AppLookup(rejection: "That app is not part of the sample data.")
    }

    /// The real analysis over the current copy. Items without a stamp (the dropped bundle) get theirs from the copy, so the
    /// run's check has something to compare, as the live scanner would have recorded.
    func scan(_ request: ScanRequest, _ prefs: Preferences) -> ScanResult {
        lock.lock()
        defer { lock.unlock() }
        var kind = ScanKind.orphans
        var target: AppIdentity?
        if case .app(let identity) = request {
            kind = .app
            target = identity
        }
        let input = ScanInput(kind: kind, target: target, installed: installedLocked(), inventory: world.inventory,
                              library: world.library(present: present, stamps: stamps, now: start),
                              sizes: world.sizes(present: present, stamps: stamps), running: world.running, prefs: prefs,
                              home: DemoScenarios.home, osVersion: DemoScenarios.osVersion, now: start)
        var result = Scan.analyze(input)
        for g in result.groups.indices {
            for i in result.groups[g].items.indices where result.groups[g].items[i].stamp == nil {
                result.groups[g].items[i].stamp = stamps[result.groups[g].items[i].path]
            }
        }
        return result
    }

    func inTrash(_ records: [UndoRecord]) -> Set<String> {
        lock.lock()
        defer { lock.unlock() }
        return Set(records.filter { trashed.contains($0.trashedPath) }.map(\.id))
    }

    func diagnostics() -> String {
        lock.lock()
        defer { lock.unlock() }
        let listings = world.library(present: present, stamps: stamps, now: start).listings
        return DiagnosticsText.text(coverage: Coverage(places: listings.map(\.coverage)), installedCount: installedLocked().apps.count,
                                    osVersion: DemoScenarios.osVersion, appVersion: "demo", readiness: world.readiness)
    }

    // MARK: a run

    /// An app writes to a folder after the scan, once per backend: the scenario's drifting paths change their stamp.
    func driftOnce() {
        lock.lock()
        defer { lock.unlock() }
        if drifted { return }
        drifted = true
        for path in world.drifts {
            if var s = stamps[path] {
                s.mtimeSeconds += 90
                stamps[path] = s
            }
        }
    }

    /// The Trasher's order, against the copy: policy, identity, running, then the move. Every attempt leaves an intent line
    /// and a result line; an item stopped before the move leaves only the result line.
    func attempt(_ item: ResidueItem, owner: AppIdentity?, plan: TrashPlan, prefs: Preferences, at: Date) -> ItemOutcome {
        lock.lock()
        defer { lock.unlock() }
        let label = owner?.displayName ?? item.ownerID
        func line(_ phase: ActivityPhase, _ status: TrashStatus?, errno: Int32? = nil, trashedPath: String? = nil,
                  detail: String? = nil) -> ActivityEntry {
            ActivityEntry(timestamp: at, runID: plan.runID, verb: .trash, phase: phase,
                          path: PathText.tilde(item.path, home: DemoScenarios.home), label: label, ownerID: item.ownerID,
                          ruleID: item.ruleID, tier: item.tier, kind: item.kind, bytes: item.size, status: status, errno: errno,
                          trashedPath: trashedPath.map { PathText.tilde($0, home: DemoScenarios.home) }, stamp: item.stamp,
                          why: item.why, detail: detail, lowerBound: item.sizeState == .measured ? nil : true)
        }
        func stop(_ status: TrashStatus, errno: Int32? = nil, detail: String? = nil) -> ItemOutcome {
            entries.append(line(.result, status, errno: errno, detail: detail))
            return ItemOutcome(item: item, status: status, errno: errno, detail: detail)
        }
        let parent = String(item.path[..<(item.path.lastIndex(of: "/") ?? item.path.startIndex)])
        switch GuardPolicy.check(path: item.path, canonicalParent: parent, home: DemoScenarios.home, keep: prefs.keepList,
                                 isAppBundle: item.ruleID == "APP") ?? .ok {
        case .ok: break
        case .gone: return stop(.alreadyGone)
        case .changed(let why): return stop(.changedSinceScan, detail: why)
        case .blocked(let reason, let why):
            switch reason {
            case .protectedByMacOS: return stop(.protectedByMacOS, errno: 1, detail: why)
            case .locked: return stop(.locked, detail: why)
            case .dataless: return stop(.dataless, detail: why)
            default: return stop(.blocked, detail: why)
            }
        }
        if !item.tier.isSelectable { return stop(.blocked, detail: WhyText.reason(item.blocked ?? .neverList)) }
        guard present.contains(item.path) else { return stop(.alreadyGone) }
        if let seen = item.stamp, let current = stamps[item.path], !Stamps.same(seen, current) {
            return stop(.changedSinceScan, detail: "Changed since you reviewed it.")
        }
        if RunningCheck.state(owner: owner, itemPath: item.path, snapshot: world.running) != .notRunning {
            return stop(.blocked, detail: WhyText.reason(.running))
        }
        entries.append(line(.intent, nil))
        if world.refuses.contains(item.path) {
            entries.append(line(.result, .protectedByMacOS, errno: 1))
            return ItemOutcome(item: item, status: .protectedByMacOS, errno: 1)
        }
        var trashedAt = DemoScenarios.trashFolder + "/" + item.name
        var n = 1
        while trashed.contains(trashedAt) {   // close to the Finder's rule: a name already in the Trash gets a number
            n += 1
            trashedAt = DemoScenarios.trashFolder + "/" + item.name + " " + String(n)
        }
        present.remove(item.path)
        stamps.removeValue(forKey: item.path)
        trashed.insert(trashedAt)
        entries.append(line(.result, .moved, trashedPath: trashedAt))
        return ItemOutcome(item: item, status: .moved, trashedPath: trashedAt)
    }

    /// Undo of one record: never overwrites, and an emptied Trash entry is "Already emptied".
    func restore(_ record: UndoRecord, at: Date) -> UndoItemOutcome {
        lock.lock()
        defer { lock.unlock() }
        func line(_ phase: ActivityPhase, _ status: UndoStatus?) -> ActivityEntry {
            ActivityEntry(timestamp: at, runID: record.runID, verb: .undo, phase: phase,
                          path: PathText.tilde(record.originalPath, home: DemoScenarios.home), label: record.label, tier: record.tier,
                          bytes: record.bytes, undoStatus: status,
                          trashedPath: PathText.tilde(record.trashedPath, home: DemoScenarios.home), stamp: record.stamp)
        }
        func stop(_ status: UndoStatus, _ detail: String? = nil) -> UndoItemOutcome {
            entries.append(line(.result, status))
            return UndoItemOutcome(record: record, status: status, detail: detail)
        }
        guard trashed.contains(record.trashedPath) else { return stop(.alreadyEmptied) }
        guard !present.contains(record.originalPath) else { return stop(.destinationExists, "Something is already there.") }
        entries.append(line(.intent, nil))
        trashed.remove(record.trashedPath)
        present.insert(record.originalPath)
        stamps[record.originalPath] = record.stamp
        return stop(.restored)
    }
}
