import Foundation

/// The ONLY place a set of ticks is built (a grep enforces it). Every function ignores items that have no checkbox, so a
/// Hands off or Needs admin row can never be ticked, and only High is ever ticked without a click.
public enum ItemSelection {
    /// Ids of `tier == .high` items, nothing else.
    public static func preselected(_ result: ScanResult) -> Set<String> {
        Set(result.items.filter { $0.tier.isPreselected }.map(\.id))
    }

    /// Flips one item. Ids that are not in the result, or whose tier has no checkbox, change nothing.
    public static func toggle(_ ticked: Set<String>, id: String, in result: ScanResult) -> Set<String> {
        guard let item = result.items.first(where: { $0.id == id }), item.tier.isSelectable else { return ticked }
        var next = ticked
        if next.contains(id) { next.remove(id) } else { next.insert(id) }
        return next
    }

    /// "Select all High": adds every High item (caches, settings and other items that are safe to lose).
    public static func selectHigh(_ ticked: Set<String>, in result: ScanResult) -> Set<String> {
        ticked.union(preselected(result))
    }

    /// The per-app "Include my data" control: adds or removes that owner's Medium items.
    public static func includeMyData(_ ticked: Set<String>, owner: String, on: Bool, in result: ScanResult) -> Set<String> {
        let ids = result.groups.filter { $0.owner.bundleID == owner }.flatMap(\.items).filter { $0.tier == .medium }.map(\.id)
        var next = ticked
        for id in ids { if on { next.insert(id) } else { next.remove(id) } }
        return next
    }
}
