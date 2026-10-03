import AftertasteCore
import SwiftUI

/// What a move did (docs/DESIGN.md §6.5), as a sheet over the afterglow: the headline in the fixed words of
/// `PlanText.resultLine`, what moved, what was left alone and why (grouped, in plain words, with what to do), and Undo.
/// It reads the outcome from `AppModel.phase`. It says what happened and never what it means: no "clean", no "gone for
/// good". The Trace Report card is dealt onto it once (MOTION §3.3). Written, not compiled.
struct TrashedView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        if case .result(let outcome) = model.phase { ResultPage(outcome: outcome) }
    }
}

private struct ResultPage: View {
    let outcome: TrashOutcome
    @EnvironmentObject private var model: AppModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// The card starts face down and turns over once; under Reduce Motion it is simply there.
    @State private var dealt = false

    private struct StatusGroup: Identifiable {
        let status: TrashStatus
        let rows: [ItemOutcome]
        var id: String { status.rawValue }
    }

    private struct SkipReason: Identifiable {
        let reason: String
        let count: Int
        var id: String { reason }
    }

    /// Worst first: what failed, then what macOS or a lock stopped, then what changed, then the rest.
    private static let order: [TrashStatus] = [.failed, .protectedByMacOS, .locked, .dataless, .changedSinceScan, .blocked, .notAttempted, .alreadyGone]
    private static let movedShown = 8
    private static let rowsShown = 6

    /// Sized to its content, as the confirm sheet is: the page and the bar when they fit, else the page scrolls.
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
        .frame(width: 620)
        .frame(maxHeight: 760)
        .background(Dawn())
        .task {
            if reduceMotion {
                dealt = true
                return
            }
            try? await Task.sleep(nanoseconds: 100_000_000)
            withAnimation(Motion.spring(false)) { dealt = true }
        }
    }

    // MARK: Page

    private var page: some View {
        let (headline, rest) = Self.split(PlanText.resultLine(outcome))
        let moved = outcome.moved
        let groups = Self.order.compactMap { status -> StatusGroup? in
            let rows = outcome.results.filter { $0.status == status }
            return rows.isEmpty ? nil : StatusGroup(status: status, rows: rows)
        }
        return VStack(alignment: .leading, spacing: Space.m) {
            VStack(alignment: .leading, spacing: Space.xxs) {
                HStack(alignment: .firstTextBaseline) {
                    Text(headline)
                        .font(.system(size: 22, weight: .semibold, design: .rounded)).monospacedDigit().tracking(-0.3)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: Space.s)
                    if model.isDemo { Tag(text: TraceReportText.sampleWatermark, tint: .secondary) }
                }
                if !rest.isEmpty {
                    Text(rest).font(.system(size: 13)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }
            }
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isHeader)
            if !moved.isEmpty { movedBox(moved) }
            ForEach(groups) { leftAlone($0) }
            if !outcome.skipped.isEmpty { skippedLines }
            if let card = model.shareCard(hideNames: model.hideNamesDefault) { cardPreview(card) }
        }
        .padding(.horizontal, Space.xl)
        .padding(.top, Space.xl)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func movedBox(_ moved: [ItemOutcome]) -> some View {
        VStack(alignment: .leading, spacing: Space.xs) {
            ForEach(moved.prefix(Self.movedShown)) { row in
                HStack(spacing: Space.s) {
                    Image(systemName: TrashStatus.moved.symbol).foregroundStyle(TrashStatus.moved.tint).accessibilityHidden(true)
                    Text(row.item.name).font(.system(size: 13, weight: .semibold)).fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: Space.xs)
                    Text(Format.size(row.item.size, row.item.sizeState))
                        .font(.system(size: 12, design: .rounded)).monospacedDigit().foregroundStyle(.secondary)
                }
                .accessibilityElement(children: .combine)
            }
            if moved.count > Self.movedShown {
                Text("and \(moved.count - Self.movedShown) more. All of them are listed in History.")
                    .font(.system(size: 12)).foregroundStyle(.secondary)
            }
        }
        .padding(Space.m)
        .frame(maxWidth: .infinity, alignment: .leading)
        .surface(16)
    }

    /// One block per reason an item stayed: the word, what to do, then the items. Failed is the only red, and only its symbol.
    private func leftAlone(_ group: StatusGroup) -> some View {
        VStack(alignment: .leading, spacing: Space.xs) {
            HStack(spacing: Space.xs) {
                Image(systemName: group.status.symbol).foregroundStyle(group.status.tint).accessibilityHidden(true)
                Text("\(group.status.word) · \(group.rows.count)").font(.system(size: 13, weight: .semibold))
            }
            Text(Self.advice(group.status)).font(.system(size: 12)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            ForEach(group.rows.prefix(Self.rowsShown)) { row in
                HStack(alignment: .firstTextBaseline, spacing: Space.xs) {
                    VStack(alignment: .leading, spacing: 1) {
                        Text(row.item.name).font(.system(.caption, design: .monospaced)).fixedSize(horizontal: false, vertical: true)
                        if let detail = row.detail, !detail.isEmpty {
                            Text(detail).font(.system(size: 12)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    Spacer(minLength: Space.xs)
                    if group.status != .alreadyGone && group.status != .notAttempted {
                        Button("Reveal in Finder") { model.reveal(row.item.path) }
                            .buttonStyle(.borderless)
                            .font(.system(size: 12))
                            .help("Show this item in Finder")
                    }
                }
                .accessibilityElement(children: .contain)
            }
            if group.rows.count > Self.rowsShown {
                Text("and \(group.rows.count - Self.rowsShown) more.").font(.system(size: 12)).foregroundStyle(.secondary)
            }
        }
        .padding(Space.m)
        .frame(maxWidth: .infinity, alignment: .leading)
        .surface(16)
    }

    /// Items the plan left out before the run started, by reason.
    private var skippedLines: some View {
        let reasons = Dictionary(grouping: outcome.skipped, by: \.reason)
            .map { SkipReason(reason: $0.key, count: $0.value.count) }
            .sorted { $0.count != $1.count ? $0.count > $1.count : $0.reason < $1.reason }
        return VStack(alignment: .leading, spacing: 2) {
            ForEach(reasons.prefix(4)) { Text("\($0.count) left out before the move. \($0.reason)") }
            if reasons.count > 4 { Text("and \(Format.count(reasons.count - 4, "more reason"))") }
        }
        .font(.system(size: 12)).foregroundStyle(.secondary)
        .fixedSize(horizontal: false, vertical: true)
    }

    /// The card of what was found before the move (the model keeps that scan for the report), turning over once, then
    /// tilting a few degrees under the pointer. Decoration stays outside `TraceCardView`, so the saved PNG never has it.
    private func cardPreview(_ card: ShareCard) -> some View {
        TraceCardView(card: card, width: 420)
            .modifier(FlipFaces(angle: dealt ? 0 : 180, back: CardBack()))
            .modifier(HoverTilt(max: 4, glare: true))
            .lifted()
            .frame(maxWidth: .infinity)
            .padding(.vertical, Space.xs)
    }

    // MARK: Bar

    private var bar: some View {
        HStack(spacing: Space.s) {
            Button("Undo All") { Task { await model.undo(run: outcome.runID) } }
                .buttonStyle(DuskButtonStyle())
                .disabled(outcome.movedCount == 0)
                .help("Put everything from this move back where it was")
            Button("Open Trash") { model.openTrash() }
                .buttonStyle(.borderless)
                .disabled(outcome.movedCount == 0)
            Button("Open History") {
                model.dismissResult()
                model.show(.history)
            }
            .buttonStyle(.borderless)
            CopyCardButton(title: "Copy Card") { model.traceReport(hideNames: model.hideNamesDefault, includeRows: false) }
            .buttonStyle(.borderless)
            .help("Copy the Trace Report card as an image")
            Spacer(minLength: Space.s)
            Button("Done") { model.dismissResult() }
                .keyboardShortcut(.cancelAction)
        }
        .padding(.vertical, Space.xs)
        .padding(.horizontal, Space.m)
        .barSurface()
        .padding(.horizontal, Space.xl)
        .padding(.top, Space.m)
        .padding(.bottom, Space.xl)
    }

    // MARK: Words

    /// "Moved 14 items (212 MB) to Trash." and the rest of the fixed result line.
    private static func split(_ line: String) -> (String, String) {
        guard let r = line.range(of: ". ") else { return (line, "") }
        return (String(line[..<r.lowerBound]) + ".", String(line[r.upperBound...]))
    }

    /// What to do next, in plain words. Never "try again", never an apology.
    private static func advice(_ status: TrashStatus) -> String {
        switch status {
        case .moved: return ""
        case .alreadyGone: return "These were already gone when the move reached them."
        case .changedSinceScan: return "These changed after the scan, so Aftertaste left them. Scan again to see them as they are now."
        case .blocked: return "Aftertaste's own checks said no for these. The reason is under each one."
        case .protectedByMacOS: return "macOS did not allow Aftertaste to move these. Reveal one in Finder to deal with it yourself."
        case .locked: return "These are locked. Aftertaste never unlocks anything."
        case .dataless: return "These are stored in iCloud and not downloaded. Aftertaste left them alone."
        case .failed: return "These could not be moved. Reveal one in Finder to look at it, or move it yourself."
        case .notAttempted: return "The move stopped before it reached these."
        }
    }
}
