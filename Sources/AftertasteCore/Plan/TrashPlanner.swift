import Foundation

/// Turns what the user saw and ticked into the immutable list that gets executed (BUILD_PLAN §4.7). Pure. The executor
/// re-verifies every item anyway; the planner's job is to never even propose one that must not move.
public enum TrashPlanner {
    public enum Mode: Sendable, Equatable {
        /// The big button: High items always, Medium only when the confirm sheet's acknowledgement is ticked, never Review.
        case bulk(acknowledgedMedium: Bool)
        /// One Review item with its own confirmation.
        case singleReview(id: String)
    }

    /// "20261003T101500Z-3fa9c1": UTC time plus six hex digits.
    public static func newRunID(now: Date, random: UInt32) -> String {
        let p = Civil.parts(now)
        let hex = String(random & 0xFF_FFFF, radix: 16)
        let pad = String(repeating: "0", count: max(0, 6 - hex.count)) + hex
        return "\(Civil.pad(p.year, 4))\(Civil.pad(p.month))\(Civil.pad(p.day))T\(Civil.pad(p.hour))\(Civil.pad(p.minute))\(Civil.pad(p.second))Z-\(pad)"
    }

    /// Keeps only ticked, selectable items; drops Medium unless acknowledged; `.singleReview` plans exactly one Review item;
    /// drops items whose group is running or unknown, duplicates by device and inode, and children of a planned parent.
    /// Order: the app bundle first, then High before Medium before Review; within a tier cookies, state, logs, caches,
    /// settings, then your data, then shared; stable by path.
    public static func plan(from result: ScanResult, ticked: Set<String>, mode: Mode, now: Date, runID: String) -> TrashPlan {
        var skipped: [PlanSkip] = []
        var chosen: [(item: ResidueItem, group: ResidueGroup)] = []
        var acknowledged = false

        switch mode {
        case .bulk(let ack):
            acknowledged = ack
            for group in result.groups {
                for item in group.items where ticked.contains(item.id) {
                    if let why = problem(item, in: group) {
                        skipped.append(PlanSkip(path: item.path, reason: why))
                    } else if item.tier == .low {
                        skipped.append(PlanSkip(path: item.path, reason: "Review items are moved one at a time."))
                    } else if item.tier == .medium && !ack {
                        skipped.append(PlanSkip(path: item.path, reason: "Items that may hold your data need your confirmation."))
                    } else {
                        chosen.append((item, group))
                    }
                }
            }
        case .singleReview(let id):
            if let group = result.groups.first(where: { $0.items.contains { $0.id == id } }), let item = group.items.first(where: { $0.id == id }) {
                if let why = problem(item, in: group) {
                    skipped.append(PlanSkip(path: item.path, reason: why))
                } else if item.tier != .low {
                    skipped.append(PlanSkip(path: item.path, reason: "Only Review items are moved one at a time."))
                } else {
                    chosen.append((item, group))
                }
            } else {
                skipped.append(PlanSkip(path: id, reason: "That item is not in this scan."))
            }
        }

        // Uninstall-now: while the app is still installed its files stay unless the app itself goes in the same run
        // (an installed app's files are never touched). A single Review item can therefore never be planned beside it.
        if result.kind == .app {
            for group in result.groups where group.items.contains(where: { $0.ruleID == "APP" }) {
                let planned = chosen.filter { $0.group.owner.bundleID == group.owner.bundleID }
                if !planned.isEmpty, !planned.contains(where: { $0.item.ruleID == "APP" }) {
                    for p in planned { skipped.append(PlanSkip(path: p.item.path, reason: "\(group.owner.displayName) is still installed, so its files stay.")) }
                    chosen.removeAll { $0.group.owner.bundleID == group.owner.bundleID }
                }
            }
        }

        chosen.sort { a, b in
            let ra = sortKey(a.item), rb = sortKey(b.item)
            return ra != rb ? ra.lexicographicallyPrecedes(rb) : a.item.path < b.item.path
        }

        let plannedPaths = chosen.map(\.item.path)
        var items: [ResidueItem] = []
        var owners: [AppIdentity] = []
        var seenIdentity = Set<String>()
        for (item, group) in chosen {
            if let st = item.stamp {
                let key = "\(st.device):\(st.inode)"
                if !seenIdentity.insert(key).inserted {
                    skipped.append(PlanSkip(path: item.path, reason: "The same item is already in the list."))
                    continue
                }
            }
            if let parent = plannedPaths.first(where: { item.path.hasPrefix($0 + "/") }) {
                skipped.append(PlanSkip(path: item.path, reason: "Moves along with \(parent.split(separator: "/").last.map(String.init) ?? "its folder")."))
                continue
            }
            items.append(item)
            if !owners.contains(where: { $0.bundleID == group.owner.bundleID }) { owners.append(group.owner) }
        }
        return TrashPlan(runID: runID, createdAt: now, kind: result.kind, owners: owners, items: items, skipped: skipped,
                         acknowledgedMedium: acknowledged && items.contains { $0.tier == .medium })
    }

    /// Why an item can never be part of a plan, whatever the user ticked. nil = eligible.
    static func problem(_ item: ResidueItem, in group: ResidueGroup) -> String? {
        if let b = item.blocked { return WhyText.reason(b) }
        if item.requiresAdmin { return WhyText.reason(.needsAdmin) }
        if !item.tier.isSelectable { return "Aftertaste does not move this kind of item." }
        if item.kind == .launchItem || item.kind == .system { return WhyText.reason(.listedOnly) }
        switch group.runState {
        case .running: return WhyText.reason(.running)
        case .unknown: return WhyText.reason(.runningUnknown)
        case .notRunning: return nil
        }
    }

    /// (is not the app bundle, tier rank, class rank).
    private static func sortKey(_ item: ResidueItem) -> [Int] {
        let classRank: Int
        switch item.kind {
        case .app: classRank = 0
        case .cookies: classRank = 1
        case .state: classRank = 2
        case .logs: classRank = 3
        case .cache: classRank = 4
        case .settings: classRank = 5
        case .launchItem: classRank = 6
        case .yourData: classRank = 7
        case .shared: classRank = 8
        case .system: classRank = 9
        }
        return [item.ruleID == "APP" ? 0 : 1, Engine.rank(item.tier), classRank]
    }
}
