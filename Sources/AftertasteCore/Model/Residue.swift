import Foundation

/// What an item is, in the user's words. `app` is the dropped bundle itself (uninstall-now only).
public enum ResidueKind: String, Codable, CaseIterable, Sendable {
    case app, cache, settings, state, logs, cookies, launchItem, yourData, shared, system

    public var displayName: String {
        switch self {
        case .app: return "App"
        case .cache: return "Cache"
        case .settings: return "Settings"
        case .state: return "Saved state"
        case .logs: return "Logs"
        case .cookies: return "Cookies"
        case .launchItem: return "Launch item"
        case .yourData: return "Your data"
        case .shared: return "Shared"
        case .system: return "System"
        }
    }
}

/// How likely another app legitimately uses the same folder (vendor roots, Group Containers, updater caches).
public enum ShareRisk: String, Codable, Comparable, Sendable {
    case none, possible, high

    private var order: Int { self == .none ? 0 : (self == .possible ? 1 : 2) }
    public static func < (a: ShareRisk, b: ShareRisk) -> Bool { a.order < b.order }
}

/// Why an item is `handsOff` (or why a would-be-selectable item was blocked at action time). Core's `WhyText` words each.
public enum BlockReason: String, Codable, Sendable {
    case appleOwned, neverList, running, runningUnknown, protectedByMacOS, iCloud, dataless, locked, mountPoint
    case linkEscapes, otherVolume, notLocalVolume, sharedWithInstalled, siblingInstalled, listedOnly, needsAdmin
    case ownerMayBeElsewhere, otherUser, ownCopy, changed
}

public enum EvidenceKind: String, Codable, Sendable {
    /// Name is the bundle ID, or the ID plus a documented extension or `.` suffix.
    case exactID
    /// `<id>.helper`, `.agent`, `.xpc` ... at a dot boundary.
    case helperSuffix
    case embeddedID
    case teamPrefix
    case groupID
    /// Container metadata plist names the ID.
    case containerMetadata
    case launchdLabelIsID
    case launchdProgramInBundle
    case launchdProgramGone
    case receipt
    case caskZap
    case displayName
    case executableName
    /// Inventory says "seen installed, absent since ...".
    case inventoryAbsent
    case noLiveOwner
    /// An installed app has the same developer Team ID as the removed app (or, with no inventory record, an ID with the same first two labels): its folders may be shared. Detail: that app's name.
    case sameTeamInstalled
    case staleMtime
    case vendorNesting
}

/// One reason an item is attributed to an app. `detail` is a short fragment for the "why" line: an ID, a label, a date.
public struct Evidence: Codable, Hashable, Sendable {
    public var kind: EvidenceKind
    public var detail: String

    public init(_ kind: EvidenceKind, _ detail: String = "") {
        self.kind = kind
        self.detail = detail
    }
}

/// How well the size is known. Never shown as "0" when it was not measured.
public enum SizeState: String, Codable, Sendable {
    case measured
    /// A budget or an unreadable subfolder cut the walk short: "at least 3 GB".
    case atLeast
    /// Not looked inside (protected container, symlink, unmeasured system row): "size not measured".
    case notMeasured
}

/// A measured size, keyed by path in `ScanInput.sizes`.
public struct SizeMeasure: Codable, Hashable, Sendable {
    public var bytes: UInt64
    public var state: SizeState
    /// Regular files found inside (1 for a file, 0 for a symlink or an unmeasured folder). Feeds the card's "214 files".
    public var fileCount: Int
    /// Newest modification time found inside a directory walk (names and stat only), when known.
    public var newestMtime: Date?

    public init(bytes: UInt64, state: SizeState = .measured, fileCount: Int = 0, newestMtime: Date? = nil) {
        self.bytes = bytes
        self.state = state
        self.fileCount = fileCount
        self.newestMtime = newestMtime
    }
}

/// One thing found on disk and attributed to an app, with everything the user needs to judge it. Built by Core's
/// `Attribution` from a `LibrarySnapshot`; the Mac layer only fills `size`, `stamp` and `mtime` from `lstat`.
public struct ResidueItem: Codable, Hashable, Sendable, Identifiable {
    /// Canonical absolute path with the `/System/Volumes/Data` firmlink spelling removed. Unique within a result.
    public var path: String
    /// `AppIdentity.bundleID` of the owner this item is attributed to.
    public var ownerID: String
    /// `ResidueRule.id` that matched ("U1"), or "APP" for the dropped bundle.
    public var ruleID: String
    public var root: LibraryRoot?
    public var kind: ResidueKind
    public var fileType: FileType
    public var tier: Tier
    public var evidence: [Evidence]
    public var size: UInt64
    public var sizeState: SizeState
    /// Regular files inside (see `SizeMeasure.fileCount`).
    public var fileCount: Int
    public var mtime: Date?
    /// The identity stamp taken when this was scanned (`inode` lives in it). nil only for demo data.
    public var stamp: FileStamp?
    public var sharedRisk: ShareRisk
    public var requiresAdmin: Bool
    /// Path or size says "may be your only copy" (Core `Irreplaceable`); forces `tier` to `.low` or lower.
    public var irreplaceable: Bool
    /// Set when `tier == .handsOff` (and for blocked rows shown as such).
    public var blocked: BlockReason?
    /// One plain sentence: "Named exactly `com.example.notes.savedState`; no installed app has this ID."
    public var why: String

    public init(path: String, ownerID: String, ruleID: String, root: LibraryRoot? = nil, kind: ResidueKind,
                fileType: FileType = .directory, tier: Tier, evidence: [Evidence] = [], size: UInt64 = 0,
                sizeState: SizeState = .notMeasured, fileCount: Int = 0, mtime: Date? = nil, stamp: FileStamp? = nil,
                sharedRisk: ShareRisk = .none, requiresAdmin: Bool = false, irreplaceable: Bool = false,
                blocked: BlockReason? = nil, why: String = "") {
        self.path = path
        self.ownerID = ownerID
        self.ruleID = ruleID
        self.root = root
        self.kind = kind
        self.fileType = fileType
        self.tier = tier
        self.evidence = evidence
        self.size = size
        self.sizeState = sizeState
        self.fileCount = fileCount
        self.mtime = mtime
        self.stamp = stamp
        self.sharedRisk = sharedRisk
        self.requiresAdmin = requiresAdmin
        self.irreplaceable = irreplaceable
        self.blocked = blocked
        self.why = why
    }

    public var id: String { path }
    public var name: String { path.split(separator: "/").last.map(String.init) ?? path }
    public var inode: UInt64? { stamp?.inode }
}

/// One residue rule, as data (BUILD_PLAN §4.3). The catalogue is `ResidueRules.all` in Core; one line per rule, tested.
/// `ceiling` is the honesty mechanism: whatever the evidence says, an item never ends above its rule's ceiling.
public struct ResidueRule: Codable, Hashable, Sendable, Identifiable {
    /// How the folder's entry names encode the owner.
    public enum Key: String, Codable, Sendable {
        /// `<id>.plist`
        case idPlist
        /// `<id>.<hardware uuid>.plist`
        case idByHost
        /// `<id>`
        case idExact
        /// `<id>` or `<id>.<anything>` (helpers, `.binarycookies`)
        case idDotPrefix
        /// `<id>` + one of `.savedState`, `.binarycookies`, `.sfl2`, `.sfl3`
        case idExtension
        /// `<id>` (strong), else the display name (weak; capped at Review)
        case idOrName
        /// `<ExecutableName>_...`
        case execPrefix
        /// `<label>.plist` plus ownership proof read from the plist
        case launchLabel
        /// `<TeamID>.<name>` or a known `group.<id>`
        case teamOrGroup
        /// `<id>` or a UUID folder whose metadata names the ID
        case containerID
        /// `<pkg id>.bom` / `.plist`
        case receiptID
    }

    public var id: String
    public var root: LibraryRoot
    /// Human pattern for the docs and the "why" detail: "<id>.plist".
    public var pattern: String
    public var key: Key
    public var kind: ResidueKind
    public var ceiling: Tier
    public var shareRisk: ShareRisk
    /// Free text: what macOS may do to reading or removing this (VERIFY notes live here).
    public var access: String
    /// Fraction of zap-bearing Homebrew casks that list this location; informational.
    public var zapShare: Double?

    public init(id: String, root: LibraryRoot, pattern: String, key: Key, kind: ResidueKind, ceiling: Tier,
                shareRisk: ShareRisk = .none, access: String = "", zapShare: Double? = nil) {
        self.id = id
        self.root = root
        self.pattern = pattern
        self.key = key
        self.kind = kind
        self.ceiling = ceiling
        self.shareRisk = shareRisk
        self.access = access
        self.zapShare = zapShare
    }
}
