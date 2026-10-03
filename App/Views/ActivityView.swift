import AftertasteCore
import SwiftUI

/// History, the activity log (docs/DESIGN.md §6.5): every move to the Trash, newest first, one card per run with its
/// items, "Undo run" and a per-item "Undo". An item whose Trash entry is gone says "Already emptied". Undo never overwrites:
/// the model's answer for an item that cannot go back shows up as the item staying in the Trash. Built from
/// `AppModel.history`, which comes from the journal (`History.runs`). Back is the window toolbar's. Written, not compiled.
struct ActivityView: View {
    @EnvironmentObject private var model: AppModel
    /// "Reveal Log in Finder": the root hands in the model's action so this screen reads no files itself.
    let revealLog: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Space.l) {
                header
                if model.history.isEmpty {
                    empty
                } else {
                    LazyVStack(alignment: .leading, spacing: Space.m) {
                        ForEach(model.history) { HistoryRunCard(run: $0) }
                    }
                    Text("Finder's Put Back may not work for items moved by apps. Use Undo here.")
                        .font(.system(size: 12)).foregroundStyle(.secondary)
                }
            }
            .padding(Space.xl)
            .frame(maxWidth: 720, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .background(Dawn(strength: 0.5))
    }

    private var header: some View {
        HStack(alignment: .top, spacing: Space.m) {
            VStack(alignment: .leading, spacing: Space.xxs) {
                Text("History").font(.system(size: 28, weight: .semibold)).tracking(-0.5)
                Text("Every move to the Trash is listed here, newest first. The log is a file on this Mac that Aftertaste only adds to.")
                    .font(.system(size: 13)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isHeader)
            Spacer(minLength: Space.s)
            if model.isDemo { Tag(text: TraceReportText.sampleWatermark, tint: .secondary) }
            Button("Reveal Log in Finder") { revealLog() }
                .buttonStyle(.bordered)
                .help("Show the log in Finder")
        }
    }

    private var empty: some View {
        VStack(spacing: Space.xs) {
            Image(systemName: "clock.arrow.circlepath").font(.system(size: 28)).foregroundStyle(.secondary).accessibilityHidden(true)
            Text("Nothing moved yet").font(.system(size: 15, weight: .semibold))
            Text("Every move to the Trash will be listed here, with Undo until you empty the Trash.").foregroundStyle(.secondary)
        }
        .multilineTextAlignment(.center)
        .frame(maxWidth: .infinity)
        .padding(.vertical, Space.xxl)
        .accessibilityElement(children: .combine)
    }
}

// MARK: - One run

private struct HistoryRunCard: View {
    let run: HistoryRun
    @EnvironmentObject private var model: AppModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// Short runs start open; a run of many items starts closed so it does not bury the ones before it.
    @State private var expanded: Bool

    init(run: HistoryRun) {
        self.run = run
        _expanded = State(initialValue: run.items.count <= 5)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Space.s) {
            HStack(alignment: .firstTextBaseline, spacing: Space.s) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(run.date.formatted(date: .abbreviated, time: .shortened)) · \(run.label)")
                        .font(.system(size: 15, weight: .semibold)).fixedSize(horizontal: false, vertical: true)
                    Text(summary).font(.system(size: 13, design: .rounded)).monospacedDigit().foregroundStyle(.secondary)
                }
                Spacer(minLength: Space.s)
                if run.undoable.isEmpty {
                    Text(note).font(.system(size: 12)).foregroundStyle(.secondary)
                } else {
                    Button("Undo Run") { Task { await model.undo(run: run.runID) } }
                        .accessibilityLabel("Undo run of \(run.date.formatted(date: .abbreviated, time: .shortened))")
                        .buttonStyle(.bordered)
                        .disabled(model.isBusy)
                        .help("Put the items of this run that are still in the Trash back where they were")
                }
            }
            .accessibilityElement(children: .contain)
            if !run.items.isEmpty {
                Button(expanded ? "Hide Items" : "Show \(Format.count(run.items.count, "Item"))") {
                    withAnimation(Motion.standard(reduceMotion)) { expanded.toggle() }
                }
                .buttonStyle(.borderless)
                .font(.system(size: 12))
                if expanded {
                    VStack(alignment: .leading, spacing: Space.xs) {
                        ForEach(run.items) { HistoryItemRow(item: $0) }
                    }
                }
            }
        }
        .padding(Space.m)
        .frame(maxWidth: .infinity, alignment: .leading)
        .surface(16)
    }

    /// "14 items · 212 MB", and what was left alone.
    private var summary: String {
        var text = "\(Format.count(run.items.count, "item")) · \(Format.bytes(run.bytes))"
        if run.notMovedCount > 0 { text += " · \(run.notMovedCount) left alone" }
        return text
    }

    /// Why there is no Undo button.
    private var note: String {
        if run.items.isEmpty { return "Nothing was moved" }
        if run.items.allSatisfy({ $0.state == .emptied }) { return "Already emptied" }
        if run.items.allSatisfy({ $0.state == .restored }) { return "Put back" }
        return "Nothing left to undo"
    }
}

private struct HistoryItemRow: View {
    let item: HistoryItem
    @EnvironmentObject private var model: AppModel

    var body: some View {
        let record = item.record
        let name = record.originalPath.split(separator: "/").last.map(String.init) ?? record.originalPath
        HStack(alignment: .top, spacing: Space.s) {
            Image(systemName: item.state.symbol).foregroundStyle(.secondary).frame(width: 18).accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(name)
                    .font(.system(size: 13, weight: .semibold)).fixedSize(horizontal: false, vertical: true)
                Text(PathText.tilde(record.originalPath, home: model.homePath))
                    .font(.system(.caption, design: .monospaced)).foregroundStyle(.secondary)
                    .lineLimit(1).truncationMode(.middle)
            }
            Spacer(minLength: Space.xs)
            Text(Format.bytes(record.bytes)).font(.system(size: 12, design: .rounded)).monospacedDigit().foregroundStyle(.secondary)
            switch item.state {
            case .inTrash:
                Text("In the Trash").font(.system(size: 12)).foregroundStyle(.secondary)
                Button("Undo") { Task { await model.undo(item: record) } }
                    .accessibilityLabel("Undo \(name)")
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .disabled(model.isBusy)
                Button("Show in Trash") { model.reveal(record.trashedPath) }
                    .accessibilityLabel("Show \(name) in Trash")
                    .buttonStyle(.borderless)
                    .font(.system(size: 12))
            case .restored:
                Text("Put back").font(.system(size: 12)).foregroundStyle(.secondary)
            case .emptied:
                Text("Already emptied").font(.system(size: 12)).foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .contain)
    }
}
