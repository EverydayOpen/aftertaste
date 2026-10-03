import Foundation

/// A skipped item and why ("Running. Quit it first.", "Changed since you reviewed it.").
public struct PlanSkip: Codable, Hashable, Sendable {
    public var path: String
    public var reason: String

    public init(path: String, reason: String) {
        self.path = path
        self.reason = reason
    }
}

/// An immutable list of the items the user ticked, in the order they will be moved (BUILD_PLAN §4.6). Only a plan built by
/// `TrashPlanner.plan` from a scan the user saw in this session can be executed. The executor is authoritative about
/// *whether* each item may still be moved; the plan only says what the user approved.
public struct TrashPlan: Codable, Hashable, Sendable {
    /// One per Move click; ties the journal lines together. `TrashPlanner.newRunID`.
    public var runID: String
    public var createdAt: Date
    public var kind: ScanKind
    /// Everyone the items belong to (the Trasher runs the running-app check against `allIDs` of each).
    public var owners: [AppIdentity]
    /// In execution order: the app bundle first (S22), then settings/state/cache/logs, `.medium` and `.low` last.
    public var items: [ResidueItem]
    public var skipped: [PlanSkip]
    /// The user ticked "I've looked at these; they may contain my data" for the Medium items in `items`.
    public var acknowledgedMedium: Bool

    public init(runID: String, createdAt: Date, kind: ScanKind, owners: [AppIdentity], items: [ResidueItem],
                skipped: [PlanSkip] = [], acknowledgedMedium: Bool = false) {
        self.runID = runID
        self.createdAt = createdAt
        self.kind = kind
        self.owners = owners
        self.items = items
        self.skipped = skipped
        self.acknowledgedMedium = acknowledgedMedium
    }

    public var totalBytes: UInt64 { items.reduce(0) { $0 + $1.size } }
    public var includesMedium: Bool { items.contains { $0.tier == .medium } }
    public var includesReview: Bool { items.contains { $0.tier == .low } }
}

/// The answer of `Guard.verify` (Mac) and `GuardPolicy.check` (Core, pure): may this item still be moved, right now?
public enum GuardVerdict: Equatable, Sendable {
    case ok
    /// ENOENT: already gone (`TrashStatus.alreadyGone`).
    case gone
    /// The stamp, type, tier or ownership differs from what the user saw (`TrashStatus.changedSinceScan`).
    case changed(String)
    /// A rule says no (`TrashStatus.blocked`, or `.protectedByMacOS`/`.locked`/`.dataless` for those reasons).
    case blocked(BlockReason, String)
}

public enum TrashStatus: String, Codable, Sendable {
    /// `trashItem` succeeded; `trashedPath` is recorded.
    case moved
    /// ENOENT at action time: not an error, not counted as moved.
    case alreadyGone
    /// Stamp, tier or ownership changed since the scan. Nothing moved.
    case changedSinceScan
    /// Our own guards said no (running, never-list, link escape, other volume, journal not writable ...). `detail` says which.
    case blocked
    /// EPERM/EACCES from macOS. Reported, never escalated.
    case protectedByMacOS
    /// uchg/schg/restricted/deny-delete ACL. Never unlocked.
    case locked
    /// EDEADLK: stored in iCloud, not downloaded. Recorded, not retried.
    case dataless
    /// Any other error.
    case failed
    /// The run was aborted before this item (app launched, journal error, Trash unavailable).
    case notAttempted

    public var wasMoved: Bool { self == .moved }
}

public struct ItemOutcome: Codable, Hashable, Sendable, Identifiable {
    public var item: ResidueItem
    public var status: TrashStatus
    public var errno: Int32?
    /// Short plain text for `blocked`, `changedSinceScan`, `failed`.
    public var detail: String?
    /// Where the Trash put it (`resultingItemURL`), when `status == .moved`. Absolute.
    public var trashedPath: String?

    public init(item: ResidueItem, status: TrashStatus, errno: Int32? = nil, detail: String? = nil, trashedPath: String? = nil) {
        self.item = item
        self.status = status
        self.errno = errno
        self.detail = detail
        self.trashedPath = trashedPath
    }

    public var id: String { item.path }
}

public struct TrashOutcome: Codable, Hashable, Sendable {
    public var runID: String
    public var startedAt: Date
    public var finishedAt: Date
    public var results: [ItemOutcome]
    /// Copied from the plan so the result screen can say what was left alone.
    public var skipped: [PlanSkip]
    /// Set when a systemic condition stopped the run ("The activity log is not writable", "<App> was launched").
    public var abortReason: String?

    public init(runID: String, startedAt: Date, finishedAt: Date, results: [ItemOutcome], skipped: [PlanSkip] = [],
                abortReason: String? = nil) {
        self.runID = runID
        self.startedAt = startedAt
        self.finishedAt = finishedAt
        self.results = results
        self.skipped = skipped
        self.abortReason = abortReason
    }

    public var movedCount: Int { results.filter { $0.status.wasMoved }.count }
    /// Sum of the sizes shown at approval time for what was moved. "Moved", never "freed": space is freed when the Trash is emptied.
    public var movedBytes: UInt64 { results.reduce(0) { $0 + ($1.status.wasMoved ? $1.item.size : 0) } }
    /// Some moved item was only partly walked or not measured, so `movedBytes` is a floor ("at least").
    public var movedBytesIsFloor: Bool { results.contains { $0.status.wasMoved && $0.item.sizeState != .measured } }
    public var notMovedCount: Int { results.filter { !$0.status.wasMoved && $0.status != .alreadyGone }.count }
    public var moved: [ItemOutcome] { results.filter { $0.status.wasMoved } }
}

/// What Undo needs to put one moved item back: where it was, where the Trash put it, and what it looked like.
/// Rebuilt from the journal (`History.runs`); the journal's absolute-or-`~` paths are expanded with the current home.
public struct UndoRecord: Codable, Hashable, Sendable, Identifiable {
    public var runID: String
    /// Absolute original location (`~` expanded).
    public var originalPath: String
    /// Absolute location in the Trash (`resultingItemURL`).
    public var trashedPath: String
    /// The stamp taken just before the move; the Trash entry must still match its device (same volume), inode and type.
    public var stamp: FileStamp
    public var bytes: UInt64
    /// `bytes` was only a floor when the item was approved (a walk cut short, not measured).
    public var lowerBound: Bool
    /// App display label for History ("Zoom").
    public var label: String
    public var tier: Tier
    public var movedAt: Date
    /// What the item was (`.app` for a dropped bundle). nil in records from before this was kept: Undo then judges by the folder.
    public var kind: ResidueKind?

    public init(runID: String, originalPath: String, trashedPath: String, stamp: FileStamp, bytes: UInt64, label: String,
                tier: Tier, movedAt: Date, kind: ResidueKind? = nil, lowerBound: Bool = false) {
        self.runID = runID
        self.originalPath = originalPath
        self.trashedPath = trashedPath
        self.stamp = stamp
        self.bytes = bytes
        self.lowerBound = lowerBound
        self.label = label
        self.tier = tier
        self.movedAt = movedAt
        self.kind = kind
    }

    public var id: String { runID + "|" + originalPath }
}

public enum UndoStatus: String, Codable, Sendable {
    case restored
    /// Something is already at the original path. Never overwritten; offer "Reveal in Trash".
    case destinationExists
    /// The Trash entry is gone ("Already emptied").
    case alreadyEmptied
    /// macOS would not let us look in the Trash (offer Full Disk Access or "drag it back yourself").
    case trashUnreadable
    /// The Trash entry no longer matches the journal's stamp (device, inode, type). Nothing moved.
    case changedSinceTrashed
    case failed
}

public struct UndoItemOutcome: Codable, Hashable, Sendable, Identifiable {
    public var record: UndoRecord
    public var status: UndoStatus
    public var errno: Int32?
    public var detail: String?

    public init(record: UndoRecord, status: UndoStatus, errno: Int32? = nil, detail: String? = nil) {
        self.record = record
        self.status = status
        self.errno = errno
        self.detail = detail
    }

    public var id: String { record.id }
}

public struct UndoOutcome: Codable, Hashable, Sendable {
    public var results: [UndoItemOutcome]
    public init(results: [UndoItemOutcome]) { self.results = results }
    public var restoredCount: Int { results.filter { $0.status == .restored }.count }
}

/// Where one moved item is now, for the History screen.
public enum HistoryState: String, Codable, Sendable {
    /// Moved and (as far as the journal knows) still in the Trash: Undo is offered.
    case inTrash
    case restored
    /// The Trash entry is gone (checked with `Backend.inTrash`).
    case emptied
}

public struct HistoryItem: Codable, Hashable, Sendable, Identifiable {
    public var record: UndoRecord
    public var state: HistoryState
    public init(record: UndoRecord, state: HistoryState) {
        self.record = record
        self.state = state
    }
    public var id: String { record.id }
}

/// One Move click, newest first in the list. Built by `History.runs` from the journal.
public struct HistoryRun: Codable, Hashable, Sendable, Identifiable {
    public var runID: String
    public var date: Date
    /// "Zoom", "3 apps".
    public var label: String
    public var items: [HistoryItem]
    /// Items the run did not move (skipped, blocked, failed), for the per-run summary.
    public var notMovedCount: Int

    public init(runID: String, date: Date, label: String, items: [HistoryItem], notMovedCount: Int = 0) {
        self.runID = runID
        self.date = date
        self.label = label
        self.items = items
        self.notMovedCount = notMovedCount
    }

    public var id: String { runID }
    public var undoable: [UndoRecord] { items.filter { $0.state == .inTrash }.map(\.record) }
    public var bytes: UInt64 { items.reduce(0) { $0 + $1.record.bytes } }
    /// `bytes` is a floor: some item's size was only a floor when it was moved.
    public var bytesAreFloor: Bool { items.contains { $0.record.lowerBound } }
}
