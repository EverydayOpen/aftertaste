import AftertasteCore
import SwiftUI

/// What a move did (docs/DESIGN.md §6.5), as a sheet over the afterglow: the headline in the fixed words of
/// `PlanText.resultLine` beside the Trace Report card, a tally that adds up to what was selected, what moved and what was left
/// alone and why (each row named by app and kind, not by bundle ID), and Undo. It reads the outcome from `AppModel.phase`. It
/// says what happened and never what it means: no "clean", no "gone for good". The card is dealt once (MOTION §3.3).
/// Written, not compiled.
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
    private static let movedShown = 6
    private static let rowsShown = 4
    /// The headline, the card and the bar are fixed; only the rows scroll, and only past this height. The whole sheet then stays
    /// near 500pt, which clears the title bar of the smallest window (760 x 560).
    private static let detailsMax: CGFloat = 260
    private static let cardWidth: CGFloat = 232

    var body: some View {
        let groups = Self.order.compactMap { status -> StatusGroup? in
            let rows = outcome.results.filter { $0.status == status }
            return rows.isEmpty ? nil : StatusGroup(status: status, rows: rows)
        }
        let hasDetails = !outcome.moved.isEmpty || !groups.isEmpty || !outcome.skipped.isEmpty
        VStack(spacing: 0) {
            hero
            if hasDetails {
                // Sized to its rows: they sit directly when they fit, else they scroll inside a capped area.
                ViewThatFits(in: .vertical) {
                    details(groups)
                    ScrollView { details(groups) }
                }
                .frame(maxHeight: Self.detailsMax)
            }
            bar
        }
        .frame(width: 660)
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

    // MARK: Hero

    /// The headline and the tally on the left, the card on the right, so the card is shown whole and not under a scroll.
    private var hero: some View {
        let (headline, rest) = Self.split(PlanText.resultLine(outcome))
        return HStack(alignment: .top, spacing: Space.m) {
            VStack(alignment: .leading, spacing: Space.xs) {
                VStack(alignment: .leading, spacing: Space.xxs) {
                    Text(headline)
                        .font(.system(size: 22, weight: .semibold, design: .rounded)).monospacedDigit().tracking(-0.3)
                        .fixedSize(horizontal: false, vertical: true)
                    if !rest.isEmpty {
                        Text(rest).font(.system(size: 13)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    }
                }
                .accessibilityElement(children: .combine)
                .accessibilityAddTraits(.isHeader)
                if let tally {
                    Text(tally).font(.system(size: 12, weight: .medium)).monospacedDigit().foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if model.isDemo { Tag(text: TraceReportText.sampleWatermark, tint: .secondary) }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            if let card = model.shareCard(hideNames: model.hideNamesDefault) { cardPreview(card) }
        }
        .padding(.horizontal, Space.xl)
        .padding(.top, Space.l)
        .padding(.bottom, Space.s)
    }

    /// "Of 6 items selected: 4 moved, 2 not moved." The same numbers the list showed before the move, so none of them disagree.
    private var tally: String? {
        let gone = outcome.results.filter { $0.status == .alreadyGone }.count
        var parts = ["\(outcome.movedCount) moved"]
        if outcome.notMovedCount > 0 { parts.append("\(outcome.notMovedCount) not moved") }
        if gone > 0 { parts.append("\(gone) already gone") }
        if !outcome.skipped.isEmpty { parts.append("\(outcome.skipped.count) left out before the move") }
        guard parts.count > 1 else { return nil }
        return "Of \(Format.count(outcome.results.count + outcome.skipped.count, "item")) selected: " + parts.joined(separator: ", ") + "."
    }

    /// The card of what was found before the move (the model keeps that scan for the report), turning over once, then
    /// tilting a few degrees under the pointer. Decoration stays outside `TraceCardView`, so the saved PNG never has it.
    private func cardPreview(_ card: ShareCard) -> some View {
        TraceCardView(card: card, width: Self.cardWidth)
            .modifier(FlipFaces(angle: dealt ? 0 : 180, back: CardBack()))
            .modifier(HoverTilt(max: 4, glare: true))
            .lifted()
            .frame(width: Self.cardWidth)
    }

    // MARK: Rows

    /// Owner names from the scan the user reviewed (the rescan after a move may not have the app any more).
    private var ownerNames: [String: String] {
        var names: [String: String] = [:]
        for group in (model.reportScan ?? model.scan)?.groups ?? [] { names[group.id] = group.owner.displayName }
        return names
    }

    private func label(_ item: ResidueItem) -> String {
        ResidueText.label(ownerNames[item.ownerID] ?? item.ownerID, item.kind)
    }

    private func details(_ groups: [StatusGroup]) -> some View {
        VStack(alignment: .leading, spacing: Space.xs) {
            if !outcome.moved.isEmpty { movedBox(outcome.moved) }
            ForEach(groups) { leftAlone($0) }
            if !outcome.skipped.isEmpty { skippedLines }
        }
        .padding(.horizontal, Space.xl)
        .padding(.vertical, Space.xs)   // room for the surfaces' shadows inside the scroll
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func movedBox(_ moved: [ItemOutcome]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(moved.prefix(Self.movedShown)) { row in
                HStack(spacing: Space.xs) {
                    Image(systemName: TrashStatus.moved.symbol).foregroundStyle(TrashStatus.moved.tint).accessibilityHidden(true)
                    Text(label(row.item)).font(.system(size: 13, weight: .semibold)).lineLimit(1).layoutPriority(1)
                    Text(row.item.name).font(.system(.caption, design: .monospaced)).foregroundStyle(.secondary)
                        .lineLimit(1).truncationMode(.middle)
                    Spacer(minLength: Space.xs)
                    Text(Format.size(row.item.size, row.item.sizeState))
                        .font(.system(size: 12, design: .rounded)).monospacedDigit().foregroundStyle(.secondary).fixedSize()
                }
                .help(PathText.tilde(row.item.path, home: model.homePath))
                .accessibilityElement(children: .combine)
            }
            if moved.count > Self.movedShown {
                Text("and \(moved.count - Self.movedShown) more. All of them are listed in History.")
                    .font(.system(size: 12)).foregroundStyle(.secondary)
            }
        }
        .padding(Space.s)
        .frame(maxWidth: .infinity, alignment: .leading)
        .surface(Radius.plate)
    }

    /// One block per reason an item stayed: the word, what to do, then the items. Failed is the only red, and only its symbol.
    private func leftAlone(_ group: StatusGroup) -> some View {
        VStack(alignment: .leading, spacing: Space.xxs) {
            HStack(spacing: Space.xs) {
                Image(systemName: group.status.symbol).foregroundStyle(group.status.tint).accessibilityHidden(true)
                Text("\(group.status.word) · \(group.rows.count)").font(.system(size: 13, weight: .semibold))
            }
            Text(Self.advice(group.status)).font(.system(size: 12)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            ForEach(group.rows.prefix(Self.rowsShown)) { row in
                HStack(alignment: .firstTextBaseline, spacing: Space.xs) {
                    VStack(alignment: .leading, spacing: 1) {
                        Text(label(row.item)).font(.system(size: 12, weight: .semibold)).fixedSize(horizontal: false, vertical: true)
                        Text(row.item.name).font(.system(.caption, design: .monospaced)).foregroundStyle(.secondary)
                            .lineLimit(1).truncationMode(.middle)
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
                .padding(.top, 2)
                .accessibilityElement(children: .contain)
            }
            if group.rows.count > Self.rowsShown {
                Text("and \(group.rows.count - Self.rowsShown) more.").font(.system(size: 12)).foregroundStyle(.secondary)
            }
        }
        .padding(Space.s)
        .frame(maxWidth: .infinity, alignment: .leading)
        .surface(Radius.plate)
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
        .padding(.horizontal, Space.xs)
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
        .padding(.top, Space.xs)
        .padding(.bottom, Space.l)
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
