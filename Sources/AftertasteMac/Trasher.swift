import Foundation
import AftertasteCore

/// The only place in the code base that moves anything to the Trash (BUILD_PLAN §3 S1, §5.5). Per item, synchronously:
/// verify, installed-now check, running check, write-ahead intent, move, result. `tools/safety_greps.sh` pins that order and forbids a suspension
/// point between the verification and the move.
enum Trasher {
    /// Never throws. If the journal cannot be opened, nothing moves. A systemic condition (the journal stops being writable,
    /// the app of an uninstall-now run did not move) leaves the rest `notAttempted`; an item-level error is recorded and the
    /// run goes on. The body has no suspension points on purpose (async only so callers can hop off the main thread).
    ///
    /// `installedNow` answers "is an app with this owner's ID installed right now?" (Launch Services; the second argument is
    /// the bundle an uninstall-now run just moved, which must not count). It is asked at most once per owner per run.
    static func run(_ plan: TrashPlan, home: String, keep: [String], now: @Sendable () -> Date,
                    installedNow: (AppIdentity, String?) -> Bool = Trasher.launchServicesHasIt,
                    progress: @Sendable (ItemOutcome) -> Void) async -> TrashOutcome {
        let started = now()
        var results: [ItemOutcome] = []
        var abort: String?
        var installedCache: [String: Bool] = [:]
        var appMoved = Set<String>()
        func isInstalled(_ owner: AppIdentity) -> Bool {
            if let known = installedCache[owner.bundleID] { return known }
            let answer = installedNow(owner, appMoved.contains(owner.bundleID) ? owner.bundlePath : nil)
            installedCache[owner.bundleID] = answer
            return answer
        }
        let journalOK = Journal.begin(home: home, runID: plan.runID, verb: .trash, summary: Format.count(plan.items.count, "item"), at: started)
        if !journalOK { abort = "The activity log is not writable, so nothing was changed." }
        for item in plan.items {
            let outcome: ItemOutcome
            if let reason = abort {
                outcome = ItemOutcome(item: item, status: .notAttempted, detail: reason)
            } else {
                let (done, stop) = moveOne(item, in: plan, home: home, keep: keep, clock: now, isInstalled: isInstalled)
                outcome = done
                abort = stop
                if item.ruleID == "APP", outcome.status == .moved { appMoved.insert(item.ownerID) }
                // S22: in uninstall-now the app goes first; if it did not move, nothing else does.
                if abort == nil, plan.kind == .app, item.ruleID == "APP", outcome.status != .moved, outcome.status != .alreadyGone {
                    abort = "Nothing else was moved because the app itself did not move."
                }
            }
            results.append(outcome)
            progress(outcome)
        }
        let finished = now()
        if journalOK { _ = Journal.end(home: home, runID: plan.runID, verb: .trash, detail: abort, at: finished) }
        return TrashOutcome(runID: plan.runID, startedAt: started, finishedAt: finished, results: results, skipped: plan.skipped, abortReason: abort)
    }

    /// The per-item body. Returns the outcome and, for a systemic condition, the reason to stop the run.
    private static func moveOne(_ item: ResidueItem, in plan: TrashPlan, home: String, keep: [String],
                                clock: () -> Date, isInstalled: (AppIdentity) -> Bool) -> (ItemOutcome, String?) {
        if let why = notAllowed(item, in: plan) { return (skipped(item, .blocked, why, in: plan, home: home, clock: clock), nil) }

        // 1. Guard (pure policy + lstat + stamp). Anything but .ok returns without touching the item.
        switch Guard.verify(item, home: home, keep: keep) {
        case .ok: break
        case .gone: return (skipped(item, .alreadyGone, "It was already gone.", in: plan, home: home, clock: clock), nil)
        case .changed(let why): return (skipped(item, .changedSinceScan, why, in: plan, home: home, clock: clock), nil)
        case .blocked(let reason, let why): return (skipped(item, statusFor(reason), why, in: plan, home: home, clock: clock), nil)
        }

        // 2. The owner may have been installed again since the scan; then its files are in use. The app bundle itself is exempt.
        let owner = plan.owners.first { $0.bundleID == item.ownerID }
        if item.ruleID != "APP", let owner, isInstalled(owner) {
            return (skipped(item, .blocked, "Its app is installed now, so this was left alone.", in: plan, home: home, clock: clock), nil)
        }

        // 3. Running, read fresh.
        let snap = RunningApps.snapshot()
        let running = RunningCheck.state(owner: owner, itemPath: item.path, snapshot: snap)
        if running != .notRunning {
            let why = WhyText.reason(running == .running ? .running : .runningUnknown)
            return (skipped(item, .blocked, why, in: plan, home: home, clock: clock), nil)
        }

        // 4. Write-ahead. Failure means nothing moves and the run stops.
        let label = owner?.displayName ?? item.ownerID
        let intent = ActivityEntry(timestamp: clock(), runID: plan.runID, verb: .trash, phase: .intent, path: item.path, label: label,
                                   ownerID: item.ownerID, ruleID: item.ruleID, tier: item.tier, kind: item.kind, bytes: item.size,
                                   stamp: item.stamp, why: item.why, lowerBound: isFloor(item))
        guard Journal.intent(home: home, entry: intent) else {
            let why = "The activity log is not writable, so nothing was changed."
            return (ItemOutcome(item: item, status: .notAttempted, detail: why), "The activity log stopped being writable, so the rest was not attempted.")
        }

        // 5. The move. No suspension point from the verification to here. The link is the item, never its target (VERIFY).
        let url = URL(fileURLWithPath: item.path, isDirectory: item.fileType == .directory)
        var resulting: NSURL?
        var failure: Error?
        do { try FileManager.default.trashItem(at: url, resultingItemURL: &resulting) } catch { failure = error }

        // 6. Result, with resultingItemURL recorded for Undo.
        let code = failure.flatMap { Fs.posix($0) }
        var status = TrashStatus.moved
        if failure != nil {
            switch code {
            case EPERM?, EACCES?: status = .protectedByMacOS
            case ENOENT?: status = .alreadyGone
            case EDEADLK?: status = .dataless
            default: status = .failed
            }
        }
        let trashed = status == .moved ? (resulting as URL?)?.path : nil
        var detail: String?
        if status == .moved && trashed == nil { detail = "Moved, but macOS did not say where, so Undo is not available for this item." }
        if status == .failed || status == .protectedByMacOS { detail = (failure as NSError?)?.localizedDescription }
        let record = ActivityEntry(timestamp: clock(), runID: plan.runID, verb: .trash, phase: .result, path: item.path, label: label,
                                   ownerID: item.ownerID, ruleID: item.ruleID, tier: item.tier, kind: item.kind, bytes: item.size,
                                   status: status, errno: code, trashedPath: trashed, stamp: item.stamp, why: item.why, detail: detail, lowerBound: isFloor(item))
        let logged = Journal.result(home: home, entry: record)
        let outcome = ItemOutcome(item: item, status: status, errno: code, detail: detail, trashedPath: trashed)
        return (outcome, logged ? nil : "The activity log stopped being writable, so the rest was not attempted.")
    }

    // MARK: - Helpers (after the move on purpose: the pinned order in the file is begin, verify, running, intent, move, result)

    /// An item that was not moved: the outcome, plus a result line so the journal shows what was left alone.
    private static func skipped(_ item: ResidueItem, _ status: TrashStatus, _ why: String, in plan: TrashPlan, home: String,
                                clock: () -> Date) -> ItemOutcome {
        let owner = plan.owners.first { $0.bundleID == item.ownerID }
        _ = Journal.result(home: home, entry: ActivityEntry(timestamp: clock(), runID: plan.runID, verb: .trash, phase: .result, path: item.path,
                                                            label: owner?.displayName ?? item.ownerID, ownerID: item.ownerID, ruleID: item.ruleID,
                                                            tier: item.tier, kind: item.kind, bytes: item.size, status: status, stamp: item.stamp, detail: why,
                                                            lowerBound: isFloor(item)))
        return ItemOutcome(item: item, status: status, detail: why)
    }

    /// Set in the journal when the size is not an exact measurement, so History never prints it as one.
    private static func isFloor(_ item: ResidueItem) -> Bool? { item.sizeState == .measured ? nil : true }

    /// The default `installedNow`: Launch Services, nothing cached.
    static func launchServicesHasIt(_ owner: AppIdentity, excluding bundlePath: String?) -> Bool {
        !InstalledApps.launchServicesApps(ids: [owner.bundleID], excluding: bundlePath, now: Date()).isEmpty
    }

    private static func statusFor(_ reason: BlockReason) -> TrashStatus {
        switch reason {
        case .protectedByMacOS: return .protectedByMacOS
        case .locked: return .locked
        case .dataless, .iCloud: return .dataless
        default: return .blocked
        }
    }

    /// Defence in depth: the executor refuses what the planner would never have produced.
    private static func notAllowed(_ item: ResidueItem, in plan: TrashPlan) -> String? {
        if !item.path.hasPrefix("/") { return "That is not a full path." }
        if item.ruleID == "APP", plan.kind != .app || plan.items.first?.path != item.path { return "Only an uninstall-now run moves an app, and it goes first." }
        if item.ruleID != "APP", plan.kind == .app, plan.items.first.map({ $0.ruleID == "APP" && $0.ownerID == item.ownerID }) != true {
            return "An uninstall-now run moves the app first."
        }
        if !plan.owners.contains(where: { $0.bundleID == item.ownerID }) { return "Aftertaste does not know whose this is, so it does not move it." }
        if item.kind == .launchItem || item.kind == .system || item.root == .launchAgents || item.root == .autosaveInformation {
            return "Aftertaste only lists this item; it does not move it."
        }
        if !item.tier.isSelectable || item.blocked != nil || item.requiresAdmin { return "Aftertaste only lists this item; it does not move it." }
        if item.tier == .medium && !plan.acknowledgedMedium { return "Items that may hold your data need your confirmation first." }
        if item.tier == .low && plan.items.count != 1 { return "Review items are moved one at a time." }
        return nil
    }
}
