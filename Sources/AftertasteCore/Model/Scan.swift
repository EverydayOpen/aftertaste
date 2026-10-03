import Foundation

/// The two ways to start a scan (APP4 §3.1): remove one app now, or find leftovers of apps that are gone.
public enum ScanKind: String, Codable, Sendable {
    case app
    case orphans
}

/// What the user asked for; the argument of `Backend.scan`.
public enum ScanRequest: Hashable, Sendable {
    /// Uninstall-now: the identity of a dropped or chosen `.app` (from `Backend.identify`). The bundle is a plan item.
    case app(AppIdentity)
    /// Orphans: bundle-ID-shaped leftovers whose owner is not installed anywhere Aftertaste can see.
    case orphans
}

/// Whether the owner (or anything running from inside its bundle or leftovers) is running. Anything but `.notRunning`
/// blocks the item (fail closed).
public enum RunState: String, Codable, Sendable {
    case notRunning, running, unknown
}

/// A read-only view of the process table, taken right now (`RunningApps` + `Processes`). `readable == false` means the list
/// could not be read, and then every item is treated as possibly running.
public struct RunningSnapshot: Codable, Hashable, Sendable {
    public var bundleIDs: Set<String>
    /// Executable paths of the current user's processes (libproc `proc_pidpath`). Never argv, never environment.
    public var executablePaths: [String]
    public var readable: Bool

    public init(bundleIDs: Set<String> = [], executablePaths: [String] = [], readable: Bool = true) {
        self.bundleIDs = bundleIDs
        self.executablePaths = executablePaths
        self.readable = readable
    }
}

/// Launchd facts read from a `LaunchAgents` plist by `Identity` and parsed by Core's `Parsers.launchd`. Never the whole plist.
public struct LaunchdInfo: Codable, Hashable, Sendable {
    public var label: String
    /// `Program`, else `ProgramArguments[0]`, else `BundleProgram`.
    public var program: String?
    /// The program path exists on disk (checked by the Mac layer with one `lstat`).
    public var programExists: Bool

    public init(label: String, program: String? = nil, programExists: Bool = true) {
        self.label = label
        self.program = program
        self.programExists = programExists
    }
}

/// One entry of a listed root: a name and its `lstat`, nothing more. Matching works on these, never on paths it walks itself.
public struct LibraryEntry: Codable, Hashable, Sendable {
    public var name: String
    public var type: FileType
    public var stamp: FileStamp?
    /// `errno` when `lstat` of the entry failed.
    public var errno: Int32?
    /// For `containers` UUID folders: `MCMMetadataIdentifier` read from the container's metadata plist, when readable.
    public var containerID: String?
    /// For launch agent/daemon plists.
    public var launchd: LaunchdInfo?
    /// The file is an iCloud placeholder (`EDEADLK`/dataless flag); recorded, never retried, never read.
    public var isDataless: Bool

    public init(name: String, type: FileType = .directory, stamp: FileStamp? = nil, errno: Int32? = nil,
                containerID: String? = nil, launchd: LaunchdInfo? = nil, isDataless: Bool = false) {
        self.name = name
        self.type = type
        self.stamp = stamp
        self.errno = errno
        self.containerID = containerID
        self.launchd = launchd
        self.isDataless = isDataless
    }
}

public enum PlaceState: String, Codable, Sendable {
    /// Listed.
    case read
    /// The folder does not exist (nothing to find there). Counts as looked.
    case absent
    /// `EPERM`/`EACCES`: macOS protected it.
    case protectedByMacOS
    /// The entry or time budget ran out; what was seen is real but incomplete.
    case partial
    /// Any other error.
    case failed
}

/// What happened when one root was listed.
public struct PlaceCoverage: Codable, Hashable, Sendable {
    public var root: LibraryRoot
    public var state: PlaceState
    public var errno: Int32?
    public var entryCount: Int

    public init(root: LibraryRoot, state: PlaceState, errno: Int32? = nil, entryCount: Int = 0) {
        self.root = root
        self.state = state
        self.errno = errno
        self.entryCount = entryCount
    }
}

/// "Looked in N of M places." (BUILD_PLAN §3 S20). "Nothing found" may be shown only when `isComplete`.
public struct Coverage: Codable, Hashable, Sendable {
    public var places: [PlaceCoverage]
    /// The process table could not be read, so running state is unknown.
    public var processListUnreadable: Bool
    /// App folders that could not be listed (the installed index may be missing apps).
    public var unreadableAppFolders: [String]
    /// A volume that could hold apps looks missing (orphan results are capped at Review).
    public var volumeMayBeMissing: Bool
    /// Orphan candidates held back because their app vanished less than `OrphanTest.minAbsentDays` days ago (maybe an update in
    /// flight). Not found is not the same as not there, so while this is above 0 the scan is not complete.
    public var recentlyRemovedCount: Int

    public init(places: [PlaceCoverage] = [], processListUnreadable: Bool = false, unreadableAppFolders: [String] = [],
                volumeMayBeMissing: Bool = false, recentlyRemovedCount: Int = 0) {
        self.places = places
        self.processListUnreadable = processListUnreadable
        self.unreadableAppFolders = unreadableAppFolders
        self.volumeMayBeMissing = volumeMayBeMissing
        self.recentlyRemovedCount = recentlyRemovedCount
    }

    public var total: Int { places.count }
    /// Listed fully (or absent, which is a complete answer).
    public var looked: Int { places.filter { $0.state == .read || $0.state == .absent }.count }
    public var protectedCount: Int { places.filter { $0.state == .protectedByMacOS }.count }
    public var partialCount: Int { places.filter { $0.state == .partial }.count }
    public var failedCount: Int { places.filter { $0.state == .failed }.count }
    public var isComplete: Bool { looked == total && !processListUnreadable && unreadableAppFolders.isEmpty && recentlyRemovedCount == 0 }

    /// The same facts as numbers and flags, with no paths: what the card and the exported report keep.
    public var facts: CoverageFacts {
        CoverageFacts(looked: looked, total: total, protectedCount: protectedCount, partialCount: partialCount, failedCount: failedCount,
                      processListUnreadable: processListUnreadable, unreadableAppFolders: unreadableAppFolders.count,
                      volumeMayBeMissing: volumeMayBeMissing, recentlyRemoved: recentlyRemovedCount)
    }
}

/// `Coverage` without paths. `PlanText.coverageLine` words it, so the app, the card and the report cannot drift apart.
public struct CoverageFacts: Codable, Hashable, Sendable {
    public var looked: Int
    public var total: Int
    public var protectedCount: Int
    public var partialCount: Int
    public var failedCount: Int
    public var processListUnreadable: Bool
    public var unreadableAppFolders: Int
    public var volumeMayBeMissing: Bool
    public var recentlyRemoved: Int

    public init(looked: Int, total: Int, protectedCount: Int = 0, partialCount: Int = 0, failedCount: Int = 0,
                processListUnreadable: Bool = false, unreadableAppFolders: Int = 0, volumeMayBeMissing: Bool = false,
                recentlyRemoved: Int = 0) {
        self.looked = looked
        self.total = total
        self.protectedCount = protectedCount
        self.partialCount = partialCount
        self.failedCount = failedCount
        self.processListUnreadable = processListUnreadable
        self.unreadableAppFolders = unreadableAppFolders
        self.volumeMayBeMissing = volumeMayBeMissing
        self.recentlyRemoved = recentlyRemoved
    }
}

/// One listed root plus how it went.
public struct RootListing: Codable, Hashable, Sendable {
    public var coverage: PlaceCoverage
    public var entries: [LibraryEntry]

    public init(coverage: PlaceCoverage, entries: [LibraryEntry] = []) {
        self.coverage = coverage
        self.entries = entries
    }

    public var root: LibraryRoot { coverage.root }
}

/// The whole library as names and stamps. This is all the matcher sees, so every rule is a fixture test on Linux.
public struct LibrarySnapshot: Codable, Hashable, Sendable {
    public var home: String
    public var listings: [RootListing]
    public var takenAt: Date

    public init(home: String, listings: [RootListing], takenAt: Date) {
        self.home = home
        self.listings = listings
        self.takenAt = takenAt
    }

    public func listing(_ root: LibraryRoot) -> RootListing? { listings.first { $0.root == root } }
}

/// Everything `Scan.analyze` needs. Pure data in, `ScanResult` out. `sizes` is empty on the first pass; the Mac layer asks
/// `Scan.candidatePaths` which paths are worth measuring, measures them, and calls `analyze` again with the sizes.
public struct ScanInput: Sendable {
    public var kind: ScanKind
    /// The dropped app for `.app`; nil for `.orphans`.
    public var target: AppIdentity?
    public var installed: InstalledSnapshot
    public var inventory: [InventoryRecord]
    public var library: LibrarySnapshot
    public var sizes: [String: SizeMeasure]
    public var running: RunningSnapshot
    public var prefs: Preferences
    public var home: String
    public var osVersion: String
    public var now: Date

    public init(kind: ScanKind, target: AppIdentity? = nil, installed: InstalledSnapshot, inventory: [InventoryRecord] = [],
                library: LibrarySnapshot, sizes: [String: SizeMeasure] = [:], running: RunningSnapshot = RunningSnapshot(),
                prefs: Preferences = .default, home: String, osVersion: String, now: Date) {
        self.kind = kind
        self.target = target
        self.installed = installed
        self.inventory = inventory
        self.library = library
        self.sizes = sizes
        self.running = running
        self.prefs = prefs
        self.home = home
        self.osVersion = osVersion
        self.now = now
    }
}

/// All items attributed to one app, ready for the preview screen.
public struct ResidueGroup: Codable, Hashable, Sendable, Identifiable {
    public var owner: AppIdentity
    /// True for an orphan scan (the owner is synthesised and the caps of APP4 §3.2 apply).
    public var isOrphan: Bool
    public var runState: RunState
    /// Sorted: the app bundle first, then tier (high first), then size descending, then name.
    public var items: [ResidueItem]

    public init(owner: AppIdentity, isOrphan: Bool, runState: RunState = .notRunning, items: [ResidueItem]) {
        self.owner = owner
        self.isOrphan = isOrphan
        self.runState = runState
        self.items = items
    }

    public var id: String { owner.bundleID }
    public var totalBytes: UInt64 { items.reduce(0) { $0 + $1.size } }
    /// What the app left behind: not the app bundle, and nothing another installed app still uses. The preview, the report and the card share this.
    public var leftBehind: [ResidueItem] { items.filter { $0.ruleID != "APP" && $0.blocked != .sharedWithInstalled && $0.blocked != .siblingInstalled } }
    public var highBytes: UInt64 { items.filter { $0.tier == .high }.reduce(0) { $0 + $1.size } }
    public var highCount: Int { items.filter { $0.tier == .high }.count }
    public func count(_ tier: Tier) -> Int { items.filter { $0.tier == tier }.count }
}

/// The result of a scan: what the preview screen, the card and the report are all built from.
public struct ScanResult: Codable, Hashable, Sendable {
    public var scannedAt: Date
    public var kind: ScanKind
    /// Largest `totalBytes` first.
    public var groups: [ResidueGroup]
    public var coverage: Coverage
    public var home: String
    public var osVersion: String
    /// Installed apps found (so "nothing found" can say what it checked).
    public var installedCount: Int

    public init(scannedAt: Date, kind: ScanKind, groups: [ResidueGroup], coverage: Coverage, home: String, osVersion: String,
                installedCount: Int = 0) {
        self.scannedAt = scannedAt
        self.kind = kind
        self.groups = groups
        self.coverage = coverage
        self.home = home
        self.osVersion = osVersion
        self.installedCount = installedCount
    }

    public var items: [ResidueItem] { groups.flatMap(\.items) }
    public var itemCount: Int { groups.reduce(0) { $0 + $1.items.count } }
    public var leftBehind: [ResidueItem] { groups.flatMap(\.leftBehind) }
    public var totalBytes: UInt64 { groups.reduce(0) { $0 + $1.totalBytes } }
    public var preselectedCount: Int { groups.reduce(0) { $0 + $1.highCount } }
    public var preselectedBytes: UInt64 { groups.reduce(0) { $0 + $1.highBytes } }
    /// Nothing to show *and* every place was looked at. "Nothing found in the places I could read" otherwise.
    public var isCleanAndComplete: Bool { groups.isEmpty && coverage.isComplete }
}
