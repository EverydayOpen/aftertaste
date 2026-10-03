import AftertasteCore
import SwiftUI

/// The sheet for a move (docs/DESIGN.md §6.5): what will go to the Trash, per class, with anything that may hold the user's
/// own data named one by one behind a required acknowledgement; then, while the run goes, how far it is; and, while Undo
/// runs, one line saying so. One view for all three phases so the sheet stays put and only its content changes. The plan it shows is the plan that runs (`TrashPlanner`
/// made it from what the user saw); this sheet only asks. Written, not compiled.
struct ConfirmSheet: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        switch model.phase {
        case .confirming(let plan): ConfirmPage(plan: plan)
        case .running(let plan, let finished): MovingPage(plan: plan, finished: finished)
        case .undoing: PuttingBackPage()
        default: EmptyView()
        }
    }
}

// MARK: - Confirm

/// Sized to its content: the page and the buttons when they fit (`ViewThatFits`), and when the page is taller than the
/// sheet's cap only the page scrolls, with the buttons pinned below it. No fixed height, so no dead space.
private struct ConfirmPage: View {
    let plan: TrashPlan
    @EnvironmentObject private var model: AppModel

    private struct SkipReason: Identifiable {
        let reason: String
        let count: Int
        var id: String { reason }
    }

    private struct ClassRow: Identifiable {
        let kind: ResidueKind
        let items: [ResidueItem]
        var id: String { kind.rawValue }
    }

    var body: some View {
        ViewThatFits(in: .vertical) {
            VStack(spacing: 0) {
                page
                bar
            }
            VStack(spacing: 0) {
                ScrollView { page }
                bar
            }
        }
        .frame(width: 500)
        .frame(maxHeight: 640)
    }

    private var page: some View {
        let home = model.homePath
        let n = plan.items.count
        let medium = plan.items.filter { $0.tier == .medium }
        let review = plan.items.filter { $0.tier == .low }
        let rows = ResidueText.classOrder.compactMap { kind -> ClassRow? in
            let inKind = plan.items.filter { $0.kind == kind }
            return inKind.isEmpty ? nil : ClassRow(kind: kind, items: inKind)
        }
        return VStack(alignment: .leading, spacing: Space.m) {
            SheetHeader(symbol: "trash",
                        title: n == 0 ? "Nothing to move" : PlanText.moveButton(count: n) + "?",
                        detail: n == 0 ? "Nothing in this selection can be moved." : "\(ResidueText.size(plan.items)) from \(ownerNames).")
            if n > 0 {
                VStack(alignment: .leading, spacing: Space.s) {
                    ForEach(rows) { row in
                        HStack(spacing: Space.s) {
                            Image(systemName: row.kind.symbol)
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(.secondary)
                                .well(Color.secondary, size: 24)
                                .accessibilityHidden(true)
                            Text(row.kind.displayName).font(.system(size: 13, weight: .semibold))
                            Spacer(minLength: Space.xs)
                            Text("\(Format.count(row.items.count, "item")) · \(ResidueText.size(row.items))")
                                .font(.system(size: 13, design: .rounded)).monospacedDigit().foregroundStyle(.secondary)
                        }
                        .accessibilityElement(children: .combine)
                    }
                }
                .padding(Space.m)
                .frame(maxWidth: .infinity, alignment: .leading)
                .surface(16)
            }
            if !medium.isEmpty { mediumBox(medium, home: home) }
            if !review.isEmpty { reviewBox(review, home: home) }
            if !plan.skipped.isEmpty { skippedLines }
            if n > 0 {
                Text("Items go to the Trash. You can undo from History until you empty it.")
                    .font(.system(size: 13)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.horizontal, Space.xl)
        .padding(.top, Space.xl)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var bar: some View {
        let n = plan.items.count
        return HStack(spacing: Space.xs) {
            Spacer()
            Button("Cancel", role: .cancel) { model.cancelConfirm() }
                .keyboardShortcut(.cancelAction)
            Button(PlanText.moveButton(count: n)) { Task { await model.confirmMove() } }
                .buttonStyle(DuskButtonStyle())
                .keyboardShortcut(.defaultAction)
                .disabled(n == 0 || (plan.includesMedium && !model.acknowledgedMedium))
        }
        .padding(.horizontal, Space.xl)
        .padding(.top, Space.m)
        .padding(.bottom, Space.xl)
    }

    /// Items that may hold the user's own data, each by name, and the one acknowledgement that unlocks the button.
    private func mediumBox(_ items: [ResidueItem], home: String) -> some View {
        VStack(alignment: .leading, spacing: Space.s) {
            Text("May hold your data").font(.caption.weight(.semibold).smallCaps()).foregroundStyle(.secondary)
            ForEach(items) { line($0, home: home) }
            Toggle("I've looked at these; they may contain my data.", isOn: $model.acknowledgedMedium)
                .toggleStyle(.checkbox)
                .font(.system(size: 13))
        }
        .padding(Space.m)
        .frame(maxWidth: .infinity, alignment: .leading)
        .surface(16)
    }

    /// A Review item has this sheet as its own confirmation: its reason stays in view while the user decides.
    private func reviewBox(_ items: [ResidueItem], home: String) -> some View {
        VStack(alignment: .leading, spacing: Space.s) {
            Text("Review item").font(.caption.weight(.semibold).smallCaps()).foregroundStyle(.secondary)
            ForEach(items) { line($0, home: home) }
        }
        .padding(Space.m)
        .frame(maxWidth: .infinity, alignment: .leading)
        .surface(16)
    }

    private func line(_ item: ResidueItem, home: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(alignment: .firstTextBaseline, spacing: Space.xs) {
                Text(item.name).font(.system(size: 13, weight: .semibold)).fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: Space.xs)
                Text(Format.size(item.size, item.sizeState)).font(.system(size: 12, design: .rounded)).monospacedDigit().foregroundStyle(.secondary)
            }
            Text(PathText.tilde(item.path, home: home))
                .font(.system(.caption, design: .monospaced)).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
            Text(item.why).font(.system(size: 12)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
    }

    /// What was ticked and left out, by reason: "2 left out. Running. Quit it first."
    private var skippedLines: some View {
        let reasons = Dictionary(grouping: plan.skipped, by: \.reason)
            .map { SkipReason(reason: $0.key, count: $0.value.count) }
            .sorted { $0.count != $1.count ? $0.count > $1.count : $0.reason < $1.reason }
        return VStack(alignment: .leading, spacing: 2) {
            ForEach(reasons.prefix(4)) { entry in
                Text("\(entry.count) left out. \(entry.reason)")
            }
            if reasons.count > 4 { Text("and \(Format.count(reasons.count - 4, "more reason"))") }
        }
        .font(.system(size: 12)).foregroundStyle(.secondary)
        .fixedSize(horizontal: false, vertical: true)
    }

    /// "Orbit Meet", "Orbit Meet and Paperplane Notes", "Orbit Meet, Lumen Player and 2 more".
    private var ownerNames: String {
        let names = plan.owners.map(\.displayName)
        switch names.count {
        case 0: return "the selection"
        case 1: return names[0]
        case 2: return "\(names[0]) and \(names[1])"
        default: return "\(names[0]), \(names[1]) and \(names.count - 2) more"
        }
    }
}

// MARK: - Running

/// "Moving… 6 of 14". The rows leave the list behind the sheet as outcomes arrive. The only loop is the system spinner.
private struct MovingPage: View {
    let plan: TrashPlan
    let finished: Int
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let total = plan.items.count
        let done = min(finished, total)
        VStack(alignment: .leading, spacing: Space.m) {
            Text("Moving to Trash").font(.system(size: 22, weight: .semibold)).tracking(-0.3)
            HStack(spacing: Space.s) {
                ProgressView().controlSize(.small)
                Text("Moving… \(done) of \(total)")
                    .font(.system(.body, design: .rounded)).monospacedDigit()
                    .contentTransition(.numericText())
                    .animation(Motion.standard(reduceMotion), value: done)
            }
            Text("Each item is checked again just before it moves.")
                .font(.system(size: 12)).foregroundStyle(.secondary)
        }
        .padding(Space.xl)
        .frame(width: 440, alignment: .leading)
        .interactiveDismissDisabled()
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Moving to Trash")
        .accessibilityValue("\(done) of \(total)")
    }
}

// MARK: - Undoing

/// Undo has no per-item progress to show (the backend reports once, at the end), so this is a spinner and a sentence.
private struct PuttingBackPage: View {
    var body: some View {
        VStack(alignment: .leading, spacing: Space.m) {
            Text("Putting Items Back").font(.system(size: 22, weight: .semibold)).tracking(-0.3)
            HStack(spacing: Space.s) {
                ProgressView().controlSize(.small)
                Text("Putting items back where they were…").font(.body)
            }
            Text("Nothing is overwritten. An item that cannot go back stays in the Trash.")
                .font(.system(size: 12)).foregroundStyle(.secondary)
        }
        .padding(Space.xl)
        .frame(width: 440, alignment: .leading)
        .interactiveDismissDisabled()
        .accessibilityElement(children: .combine)
    }
}
