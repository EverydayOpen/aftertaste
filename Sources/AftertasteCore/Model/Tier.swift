import Foundation

/// How far Aftertaste trusts that an item belongs to the app and may be moved to the Trash (BUILD_PLAN §4.2).
/// `high`, `medium` and `low` are the confidence tiers (the UI calls `low` "Review"). `handsOff` and `needsAdmin` are not
/// levels of trust but states: the item is shown with a reason and has no checkbox. Never conveyed by colour alone.
public enum Tier: String, Codable, CaseIterable, Sendable {
    /// Exact bundle-ID match and regenerable or pure settings. The only tier that is ever preselected.
    case high
    /// Likely belongs to the app but may hold the user's own data. Needs the per-app "Include my data" control and an
    /// acknowledgement in the confirm sheet.
    case medium
    /// Shared or ambiguous ("Review"). Executed one item at a time, each with its own confirmation. Never in a bulk action.
    case low
    /// Found, explained, never touched (Apple's, iCloud, running, protected by macOS, listed-only launch items...).
    case handsOff
    /// Lives where an ordinary app cannot write. Listed with "Reveal in Finder" and "Copy path"; never removed in v1.
    case needsAdmin

    public var displayName: String {
        switch self {
        case .high: return "High"
        case .medium: return "Medium"
        case .low: return "Review"
        case .handsOff: return "Hands off"
        case .needsAdmin: return "Needs admin"
        }
    }

    /// Has a checkbox at all.
    public var isSelectable: Bool { self == .high || self == .medium || self == .low }

    /// Ticked when a scan result is first shown. High only. The single place this is acted on is `ItemSelection` in Core;
    /// this property is what it reads.
    public var isPreselected: Bool { self == .high }

    /// 3 high, 2 medium, 1 low, 0 for the two non-levels.
    public var trust: Int {
        switch self {
        case .high: return 3
        case .medium: return 2
        case .low: return 1
        case .handsOff, .needsAdmin: return 0
        }
    }

    /// The lower of two tiers. A non-selectable tier on either side wins (a ceiling of `.handsOff` keeps an item hands off
    /// whatever its evidence says); `self` wins a tie between the two non-levels.
    public func capped(at ceiling: Tier) -> Tier {
        if !isSelectable { return self }
        if !ceiling.isSelectable { return ceiling }
        return trust <= ceiling.trust ? self : ceiling
    }
}
