import Foundation

/// Fixed strings for the preview, the confirm sheet and the result (BUILD_PLAN §8). Findings, not guarantees: "found",
/// "moved to the Trash", "looked in N of M places".
public enum PlanText {
    /// The announcement of a new scan: "Found 3.4 GB in 41 items for 2 apps. Caches, settings and other items that are safe to lose
    /// (1.2 GB) are ticked to start." It describes the scan's default (every High item, which is settings and the app itself as well
    /// as caches), not the user's ticks (the live "Selected" figure does that). A total that is only a floor (a walk cut short, a
    /// folder not measured) says "at least". Items another installed app uses, and the app itself, are not counted as found.
    public static func previewHeader(_ result: ScanResult) -> String {
        let left = result.leftBehind
        guard !left.isEmpty else { return emptyState(result) }
        func sum(_ bytes: UInt64, _ items: [ResidueItem]) -> String {
            items.contains { $0.sizeState != .measured } ? Format.atLeast(bytes) : Format.bytes(bytes)
        }
        var text = "Found \(sum(left.reduce(0) { $0 + $1.size }, left)) in \(Format.count(left.count, "item")) for \(Format.count(Set(left.map(\.ownerID)).count, "app"))."
        if result.preselectedCount > 0 {
            text += " Caches, settings and other items that are safe to lose (\(sum(result.preselectedBytes, result.items.filter { $0.tier == .high }))) are ticked to start."
        } else {
            text += " Nothing is ticked to start."
        }
        return text
    }

    /// "Looked in 14 of 18 places. 3 protected by macOS." Anything that stopped short is said, never hidden. The one wording the
    /// app, the card and the exported report share.
    public static func coverageLine(_ c: Coverage) -> String { coverageLine(c.facts) }

    public static func coverageLine(_ c: CoverageFacts) -> String {
        var text = "Looked in \(c.looked) of \(c.total) places."
        if c.protectedCount > 0 { text += " \(c.protectedCount) protected by macOS." }
        if c.partialCount > 0 { text += " \(c.partialCount) only partly read." }
        if c.failedCount > 0 { text += " \(c.failedCount) could not be read." }
        if c.processListUnreadable { text += " Running apps could not be listed." }
        if c.unreadableAppFolders > 0 { text += " \(Format.count(c.unreadableAppFolders, "app folder")) could not be read." }
        if c.volumeMayBeMissing { text += " A drive that may hold apps looks missing." }
        if c.recentlyRemoved > 0 { text += " " + recentlyRemovedNote(c.recentlyRemoved) }
        return text
    }

    /// "1 app removed less than 3 days ago is not listed yet. Scan again later." (An app that is already gone cannot be dropped.)
    public static func recentlyRemovedNote(_ n: Int) -> String {
        "\(Format.count(n, "app")) removed less than \(Format.count(OrphanTest.minAbsentDays, "day")) ago \(n == 1 ? "is" : "are") "
            + "not listed yet. Scan again later."
    }

    /// "Move 14 items to Trash"
    public static func moveButton(count: Int) -> String { "Move \(Format.count(count, "item")) to Trash" }

    /// What happened, not what it means.
    public static func resultLine(_ o: TrashOutcome) -> String {
        var text: String
        if o.movedCount == 0 {
            text = "Nothing was moved."
        } else {
            text = "Moved \(Format.count(o.movedCount, "item")) (\(Format.size(o.movedBytes, atLeast: o.movedBytesIsFloor))) to Trash. "
                + "Space is freed when you empty the Trash. Local snapshots can keep it in use for a while longer."
        }
        if let why = o.abortReason { text += " Stopped early: \(why)" }
        return text
    }

    /// The "Not covered" disclosure, one line each.
    public static func notCovered() -> [String] {
        [
            "Keychain items", "Login and background item records", "Launch Services and Spotlight entries", "iCloud data",
            "Other users on this Mac", "Backups and snapshots", "System folders under /private/var (installer receipts are listed by name)",
        ]
    }

    /// "Nothing found. Looked in all 18 places." only when every place was read; otherwise the weaker sentence. An app removed
    /// a moment ago is withheld on purpose, so that is said instead of an all-clear.
    public static func emptyState(_ r: ScanResult) -> String {
        if r.coverage.recentlyRemovedCount > 0 { return "Nothing found yet. " + recentlyRemovedNote(r.coverage.recentlyRemovedCount) }
        return r.isCleanAndComplete ? "Nothing found. Looked in \(r.coverage.total == 1 ? "the 1 place" : "all \(r.coverage.total) places")." : "Nothing found in the places I could read."
    }
}
