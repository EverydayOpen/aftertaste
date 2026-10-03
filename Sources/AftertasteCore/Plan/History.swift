import Foundation

/// Rebuilds the History screen and the Undo manifest from the journal (BUILD_PLAN §4.7). Pure: the journal lines in, runs out.
public enum History {
    /// Newest run first. An item is `inTrash` unless a later undo recorded `restored` for it; `emptied` when `inTrash` is given
    /// and no longer lists it. Paths are expanded with `home`. A moved item whose line carries no identity stamp cannot be
    /// undone safely and is left out of the run (it still counts as moved in the journal).
    public static func runs(from entries: [ActivityEntry], home: String, inTrash: Set<String>?) -> [HistoryRun] {
        var intents: [String: ActivityEntry] = [:]
        var results: [String: [ActivityEntry]] = [:]
        var order: [String] = []
        var runStart: [String: Date] = [:]
        var restores: [ActivityEntry] = []

        for e in entries {
            switch (e.verb, e.phase) {
            case (.trash, .intent):
                intents[e.runID + "|" + e.path] = e
                if !order.contains(e.runID) { order.append(e.runID) }
                runStart[e.runID] = min(runStart[e.runID] ?? e.timestamp, e.timestamp)
            case (.trash, .result):
                results[e.runID, default: []].append(e)
                if !order.contains(e.runID) { order.append(e.runID) }
                runStart[e.runID] = min(runStart[e.runID] ?? e.timestamp, e.timestamp)
            case (.run, _):
                runStart[e.runID] = min(runStart[e.runID] ?? e.timestamp, e.timestamp)
            case (.undo, .result):
                if e.undoStatus == .restored { restores.append(e) }
            default:
                break
            }
        }

        var runs: [HistoryRun] = []
        for runID in order {
            var items: [HistoryItem] = []
            var labels: [String] = []
            var notMoved = 0
            var seen = Set<String>()
            for r in results[runID] ?? [] {
                guard seen.insert(r.path).inserted else { continue }
                guard r.status == .moved else {
                    if r.status != .alreadyGone { notMoved += 1 }
                    continue
                }
                guard let trashed = r.trashedPath, let stamp = r.stamp ?? intents[runID + "|" + r.path]?.stamp else { continue }
                let intent = intents[runID + "|" + r.path]
                let record = UndoRecord(runID: runID, originalPath: PathText.expandTilde(r.path, home: home),
                                        trashedPath: PathText.expandTilde(trashed, home: home), stamp: stamp, bytes: r.bytes,
                                        label: r.label.isEmpty ? (intent?.label ?? "") : r.label, tier: r.tier ?? intent?.tier ?? .high,
                                        movedAt: r.timestamp, kind: r.kind ?? intent?.kind,
                                        lowerBound: r.lowerBound ?? intent?.lowerBound ?? false)
                let restored = restores.contains { u in
                    PathText.expandTilde(u.path, home: home) == record.originalPath && u.timestamp >= r.timestamp
                        && (u.trashedPath.map { PathText.expandTilde($0, home: home) == record.trashedPath } ?? true)
                }
                let state: HistoryState
                if restored {
                    state = .restored
                } else if let present = inTrash, !present.contains(record.id) {
                    state = .emptied
                } else {
                    state = .inTrash
                }
                items.append(HistoryItem(record: record, state: state))
                if !record.label.isEmpty, !labels.contains(record.label) { labels.append(record.label) }
            }
            guard !items.isEmpty || notMoved > 0 else { continue }
            let label = labels.count == 1 ? labels[0] : (labels.isEmpty ? "Moved items" : Format.count(labels.count, "app"))
            runs.append(HistoryRun(runID: runID, date: runStart[runID] ?? Date(timeIntervalSince1970: 0), label: label, items: items,
                                   notMovedCount: notMoved))
        }
        return runs.sorted { $0.date != $1.date ? $0.date > $1.date : $0.runID > $1.runID }
    }
}
