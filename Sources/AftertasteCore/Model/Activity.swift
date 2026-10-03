import Foundation

public enum ActivityVerb: String, Codable, Sendable {
    /// Run-level lines: intent = the run starts, result = the run ended (with `detail` = abort reason, if any).
    case run
    case trash
    case undo
}

/// Write-ahead: an `intent` line is appended (and must succeed) *before* each action; a `result` line follows.
/// If an intent cannot be written, the action is not taken (BUILD_PLAN §3 S15).
public enum ActivityPhase: String, Codable, Sendable {
    case intent
    case result
}

/// One line of the append-only journal (JSONL, `ActivityLog.encode`). It is both the audit trail and the Undo manifest,
/// so it holds home-relative paths (`~/Library/Caches/com.example.notes`); the file never leaves the Mac and is never sent
/// anywhere. File mode 0600 in a 0700 folder, one file per month.
public struct ActivityEntry: Codable, Hashable, Sendable, Identifiable {
    public var timestamp: Date
    public var runID: String
    public var verb: ActivityVerb
    public var phase: ActivityPhase
    /// Home-relative (`~/...`) when under home, else absolute; empty on run lines.
    public var path: String
    /// App display label at the time ("Zoom"). Local only.
    public var label: String
    public var ownerID: String
    public var ruleID: String
    public var tier: Tier?
    public var kind: ResidueKind?
    public var bytes: UInt64
    /// Result of a `trash` verb (nil on intent lines).
    public var status: TrashStatus?
    /// Result of an `undo` verb (nil on intent lines).
    public var undoStatus: UndoStatus?
    public var errno: Int32?
    /// `resultingItemURL` path of a moved item (`~`-relative when under home). The Undo manifest.
    public var trashedPath: String?
    /// The identity stamp taken just before the move.
    public var stamp: FileStamp?
    /// The "why" line the user approved.
    public var why: String
    public var detail: String?
    /// `bytes` was only a floor (the size walk was cut short or the item was not measured). Absent in older lines.
    public var lowerBound: Bool?

    public init(timestamp: Date, runID: String, verb: ActivityVerb, phase: ActivityPhase, path: String = "", label: String = "",
                ownerID: String = "", ruleID: String = "", tier: Tier? = nil, kind: ResidueKind? = nil, bytes: UInt64 = 0,
                status: TrashStatus? = nil, undoStatus: UndoStatus? = nil, errno: Int32? = nil, trashedPath: String? = nil,
                stamp: FileStamp? = nil, why: String = "", detail: String? = nil, lowerBound: Bool? = nil) {
        self.timestamp = timestamp
        self.runID = runID
        self.verb = verb
        self.phase = phase
        self.path = path
        self.label = label
        self.ownerID = ownerID
        self.ruleID = ruleID
        self.tier = tier
        self.kind = kind
        self.bytes = bytes
        self.status = status
        self.undoStatus = undoStatus
        self.errno = errno
        self.trashedPath = trashedPath
        self.stamp = stamp
        self.why = why
        self.detail = detail
        self.lowerBound = lowerBound
    }

    public var id: String { "\(runID)|\(verb.rawValue)|\(phase.rawValue)|\(path)" }
}
