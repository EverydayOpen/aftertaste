import Darwin
import Foundation
import AftertasteCore

/// Undo (BUILD_PLAN §3 S16, §5.6): puts an item back from the Trash to the location the journal recorded. The only
/// `moveItem` in the code base. Never overwrites: an occupied destination means "Reveal in Trash", not a replace. The
/// lines it journals carry the original run's ID and the original path, so History can match them to the move.
enum UndoStore {
    static func restore(_ records: [UndoRecord], home: String, now: @Sendable () -> Date,
                        progress: @Sendable (UndoItemOutcome) -> Void) -> UndoOutcome {
        let undoRun = TrashPlanner.newRunID(now: now(), random: UInt32.random(in: 0...UInt32.max))
        let journalOK = Journal.begin(home: home, runID: undoRun, verb: .undo, summary: Format.count(records.count, "item"), at: now())
        var results: [UndoItemOutcome] = []
        for record in records {
            let outcome = journalOK
                ? restoreOne(record, home: home, clock: now)
                : UndoItemOutcome(record: record, status: .failed, detail: "The activity log is not writable, so nothing was changed.")
            results.append(outcome)
            progress(outcome)
        }
        if journalOK { _ = Journal.end(home: home, runID: undoRun, verb: .undo, detail: nil, at: now()) }
        return UndoOutcome(results: results)
    }

    /// Which of these still have their Trash entry (and it is still the same item).
    static func presentInTrash(_ records: [UndoRecord]) -> Set<String> {
        Set(records.compactMap { r -> String? in
            var st = stat()
            return lstat(r.trashedPath, &st) == 0 && UInt64(st.st_ino) == r.stamp.inode ? r.id : nil
        })
    }

    private static func restoreOne(_ record: UndoRecord, home: String, clock: () -> Date) -> UndoItemOutcome {
        switch Guard.verifyRestore(record, home: home) {
        case .ok: break
        case .alreadyEmptied: return note(record, .alreadyEmptied, nil, "The Trash entry is gone, so there is nothing to put back.", home: home, clock: clock)
        case .trashUnreadable(let e): return note(record, .trashUnreadable, e, "macOS does not let Aftertaste look in the Trash. Allow Full Disk Access, or drag it back yourself.", home: home, clock: clock)
        case .changedSinceTrashed: return note(record, .changedSinceTrashed, nil, "The Trash entry is no longer the item that was moved.", home: home, clock: clock)
        case .destinationExists: return note(record, .destinationExists, nil, "Something is already at the original location. Nothing was replaced.", home: home, clock: clock)
        case .blocked(let why): return note(record, .failed, nil, why, home: home, clock: clock)
        }

        let intent = entry(record, .intent, clock())
        guard Journal.intent(home: home, entry: intent) else {
            return UndoItemOutcome(record: record, status: .failed, detail: "The activity log is not writable, so nothing was changed.")
        }

        let isDir = record.stamp.type == .directory
        let trashed = URL(fileURLWithPath: record.trashedPath, isDirectory: isDir)
        let original = URL(fileURLWithPath: record.originalPath, isDirectory: isDir)
        var failure: Error?
        do { try FileManager.default.moveItem(at: trashed, to: original) } catch { failure = error }

        let code = failure.flatMap { Fs.posix($0) }
        var status = UndoStatus.restored
        if failure != nil {
            switch code {
            case EEXIST?: status = .destinationExists
            case ENOENT?: status = .alreadyEmptied
            default: status = .failed
            }
        }
        var detail = failure == nil ? nil : (failure as NSError?)?.localizedDescription
        if status == .failed, code == EPERM || code == EACCES {
            detail = "macOS did not allow the move (error \(code ?? 0)). Drag it back from the Trash in Finder."
        }
        var done = entry(record, .result, clock())
        done.undoStatus = status
        done.errno = code
        done.detail = detail
        _ = Journal.result(home: home, entry: done)
        return UndoItemOutcome(record: record, status: status, errno: code, detail: detail)
    }

    // After the move on purpose (pinned order: begin, verifyRestore, intent, move, result).

    private static func entry(_ record: UndoRecord, _ phase: ActivityPhase, _ at: Date) -> ActivityEntry {
        ActivityEntry(timestamp: at, runID: record.runID, verb: .undo, phase: phase, path: record.originalPath, label: record.label,
                      tier: record.tier, bytes: record.bytes, trashedPath: record.trashedPath, stamp: record.stamp)
    }

    /// Not restored: the outcome, plus a result line so the journal shows what was left alone.
    private static func note(_ record: UndoRecord, _ status: UndoStatus, _ code: Int32?, _ why: String, home: String,
                             clock: () -> Date) -> UndoItemOutcome {
        var line = entry(record, .result, clock())
        line.undoStatus = status
        line.errno = code
        line.detail = why
        _ = Journal.result(home: home, entry: line)
        return UndoItemOutcome(record: record, status: status, errno: code, detail: why)
    }
}
