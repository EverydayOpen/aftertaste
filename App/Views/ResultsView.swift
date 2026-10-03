import AftertasteCore
import SwiftUI

/// The Preview, the dry run (docs/DESIGN.md §6.5): the apps on the left, and on the right what was found for them, one
/// card per app, every row with its tier, its size and the one-line reason it belongs to the app. Nothing here moves
/// anything: the Move button hands a plan to the confirm sheet (`ConfirmSheet`). Hands off and Needs admin rows have no
/// checkbox and say "Listed, not removed"; Review rows are moved one at a time. The window's Back and Preferences belong to
/// `RootView`; this screen adds its own Sample tag, Rescan, History and Erase readiness (the menu has the shortcuts).
/// Written, not compiled.
struct ResultsView: View {
    @EnvironmentObject private var model: AppModel

    /// nil = every app.
    @State private var focus: String?

    var body: some View {
        if let scan = model.scan {
            // A focused app that left the scan (moved, or gone after an undo rescan) falls back to every app in both panes.
            let live = focus.flatMap { id in scan.groups.contains { $0.id == id } ? id : nil }
            NavigationSplitView {
                PreviewSidebar(scan: scan, focus: Binding(get: { live }, set: { focus = $0 }))
                    .navigationSplitViewColumnWidth(min: 240, ideal: 280, max: 360)
            } detail: {
                PreviewDetail(scan: scan, focus: live)
            }
            .toolbar {
                ToolbarItemGroup(placement: .primaryAction) {
                    if model.isDemo { Tag(text: TraceReportText.sampleWatermark, tint: .secondary) }
                    Button { Task { await model.rescan() } } label: { Label("Rescan", systemImage: "arrow.clockwise") }
                        .disabled(model.isBusy)
                        .help("Read the Library again (Command-R)")
                    Button { model.show(.history) } label: { Label("History", systemImage: "clock.arrow.circlepath") }
                        .help("History")
                    Button { model.show(.readiness) } label: { Label("Erase Readiness", systemImage: "lock.shield") }
                        .help("Erase readiness")
                }
            }
        } else {
            VStack(spacing: Space.s) {
                ProgressView()
                if case .scanning(let place) = model.phase { Text(place).foregroundStyle(.secondary) }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Dawn(strength: 0.6))
        }
    }
}

/// Words and orders shared by the confirm and result sheets.
enum ResidueText {
    /// The order of the class groups, everywhere.
    static let classOrder: [ResidueKind] = [.app, .settings, .state, .cookies, .cache, .logs, .yourData, .shared, .launchItem, .system]

    /// "Orbit Meet · Logs": the app and what kind of item it is, wherever a row would otherwise show only a bundle ID.
    static func label(_ owner: String, _ kind: ResidueKind) -> String { "\(owner) · \(kind.displayName)" }

    /// "412 MB", "at least 3 GB", "size not measured": a sum is never shown as exact when a part was not.
    static func size(_ items: [ResidueItem]) -> String {
        if items.isEmpty { return Format.bytes(0) }
        if items.allSatisfy({ $0.sizeState == .notMeasured }) { return "size not measured" }
        let bytes = items.reduce(UInt64(0)) { $0 + $1.size }
        return items.contains { $0.sizeState != .measured } ? Format.atLeast(bytes) : Format.bytes(bytes)
    }
}

// MARK: - Sidebar

private struct PreviewSidebar: View {
    let scan: ScanResult
    @Binding var focus: String?
    private static let allTag = "all-apps"

    var body: some View {
        List(selection: Binding<String?>(get: { focus ?? Self.allTag }, set: { focus = ($0 == nil || $0 == Self.allTag) ? nil : $0 })) {
            if scan.groups.isEmpty {
                Text("Nothing found").foregroundStyle(.secondary)
            } else {
                Label("All apps", systemImage: "square.grid.2x2").tag(Self.allTag)
            }
            ForEach(scan.groups) { group in
                PreviewSidebarRow(group: group).tag(group.id)
            }
        }
    }
}

private struct PreviewSidebarRow: View {
    let group: ResidueGroup

    var body: some View {
        HStack(alignment: .top, spacing: Space.xs) {
            AppIconView(path: group.owner.bundlePath, size: 24)
            VStack(alignment: .leading, spacing: 3) {
                Text(group.owner.displayName).font(.system(size: 13, weight: .semibold)).fixedSize(horizontal: false, vertical: true)
                Text("\(Format.count(group.items.count, "item")) · \(ResidueText.size(group.items))")
                    .font(.system(size: 12)).foregroundStyle(.secondary).monospacedDigit()
                // The word is in the chip; only High has the violet dot (Tier.tint). Compact chips so three tiers share one line;
                // they stack only when even that does not fit.
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 6) { chips }
                    VStack(alignment: .leading, spacing: 4) { chips }
                }
                if group.isOrphan { Text("Not installed").font(.system(size: 11)).foregroundStyle(.secondary) }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(label)
        }
        .padding(.vertical, 4)
    }

    private var chips: some View {
        ForEach([Tier.high, .medium, .low], id: \.self) { tier in
            if group.count(tier) > 0 { TierCount(tier: tier, count: group.count(tier)) }
        }
    }

    private var label: String {
        let tiers = [Tier.high, .medium, .low].filter { group.count($0) > 0 }.map { "\(group.count($0)) \($0.displayName)" }
        return ([group.owner.displayName, "\(Format.count(group.items.count, "item")), \(ResidueText.size(group.items))"]
            + tiers + (group.isOrphan ? ["Not installed"] : [])).joined(separator: ", ")
    }
}

/// A `Tag` set smaller for the sidebar: "2 High", "5 Medium", "1 Review" fit one line of the narrowest sidebar.
private struct TierCount: View {
    let tier: Tier
    let count: Int
    @Environment(\.colorSchemeContrast) private var contrast

    var body: some View {
        HStack(spacing: 4) {
            if tier == .high { Circle().fill(tier.tint).frame(width: 5, height: 5).accessibilityHidden(true) }
            Text("\(count) \(tier.displayName)").font(.system(size: 11, weight: .semibold)).monospacedDigit()
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background(tier.tint.opacity(0.14), in: Capsule())
        .overlay(Capsule().strokeBorder(contrast == .increased ? Color.primary.opacity(0.4) : tier.tint.opacity(0.3), lineWidth: contrast == .increased ? 1 : 0.5))
        .fixedSize()
    }
}

// MARK: - Detail

private struct PreviewDetail: View {
    let scan: ScanResult
    let focus: String?
    @EnvironmentObject private var model: AppModel

    var body: some View {
        // The same planner the Move button uses (acknowledgement assumed, because the confirm sheet asks for it), so the
        // count on the button is exactly what the sheet will list.
        let plan = TrashPlanner.plan(from: scan, ticked: model.ticked, mode: .bulk(acknowledgedMedium: true), now: scan.scannedAt, runID: "preview")
        let groups = focus.flatMap { id in scan.groups.first { $0.id == id } }.map { [$0] } ?? scan.groups
        let notices = Self.notices(scan)
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: Space.l) {
                    if let run = lastMove { LastMoveStrip(run: run) }
                    if scan.groups.isEmpty {
                        PreviewNothingFound(scan: scan)
                    } else {
                        // Running and blocked state come first, so they never need a scroll to find (DESIGN §6.5).
                        if !notices.isEmpty { PreviewNotices(lines: notices) }
                        PreviewStage(scan: scan, plan: plan, running: runningPlan)
                        PreviewGroups(groups: groups, departed: leaving)
                            .id(scan.scannedAt)
                    }
                    PreviewNotCovered()
                }
                .padding(.horizontal, Space.xl)
                .padding(.vertical, Space.l)
                .frame(maxWidth: 780, alignment: .leading)
                .frame(maxWidth: .infinity)
            }
            if !scan.groups.isEmpty { PreviewMoveBar(count: plan.items.count) }
        }
        .background(Dawn(strength: 0.6))
    }

    private var runningPlan: (plan: TrashPlan, finished: Int)? {
        if case .running(let plan, let finished) = model.phase { return (plan, finished) }
        return nil
    }

    /// The move made from this scan, while some of it is still in the Trash: the list above has already lost those rows, so
    /// this says where they went and offers Undo. Gone once the scan is replaced, the run is undone or the Trash is emptied.
    private var lastMove: HistoryRun? {
        guard model.phase == .idle, let outcome = model.lastOutcome, outcome.movedCount > 0,
              let reviewed = model.reportScan, outcome.startedAt > reviewed.scannedAt,
              let run = model.history.first(where: { $0.runID == outcome.runID }), !run.undoable.isEmpty else { return nil }
        return run
    }

    /// Why some rows will not move, in words: a running app, or folders macOS keeps private. Empty when nothing blocks.
    private static func notices(_ scan: ScanResult) -> [String] {
        var lines: [String] = []
        let running = scan.groups.filter { $0.runState == .running }.map { $0.owner.displayName }
        if running.count == 1 {
            lines.append("\(running[0]) is running. Quit it to move its items, then Rescan.")
        } else if running.count > 1 {
            lines.append("\(Format.count(running.count, "app")) are running: \(running.joined(separator: ", ")). Quit them to move their items, then Rescan.")
        }
        if scan.groups.contains(where: { $0.runState == .unknown }) { lines.append(WhyText.reason(.runningUnknown)) }
        let protected = scan.items.filter { $0.blocked == .protectedByMacOS }.count
        if protected > 0 {
            lines.append("\(Format.count(protected, "item")) \(protected == 1 ? "is" : "are") protected by macOS and listed, not removed. Reveal in Finder to look inside.")
        }
        return lines
    }

    /// A row leaves when its outcome has been reported as moved (MOTION §3.2), never on a fake schedule; a row that was
    /// left alone stays, and the result sheet says why.
    private var leaving: Set<String> {
        guard let running = runningPlan else { return [] }
        return departed(running.plan, finished: running.finished, moved: { model.movedSoFar.contains($0) })
    }
}

// MARK: - Notices: the last move, and what will not move

/// The rows of the move that was just made left the list above, so this says where they went and offers Undo.
private struct LastMoveStrip: View {
    let run: HistoryRun
    @EnvironmentObject private var model: AppModel

    var body: some View {
        let items = run.undoable
        let size = Format.size(items.reduce(UInt64(0)) { $0 + $1.bytes }, atLeast: items.contains { $0.lowerBound })
        HStack(spacing: Space.s) {
            Image(systemName: "trash").font(.system(size: 11, weight: .medium)).foregroundStyle(Brand.duskInk)
                .well(Brand.dusk, size: 24).accessibilityHidden(true)
            Text("\(Format.count(items.count, "item")) (\(size)) moved to the Trash from this scan.")
                .font(.system(size: 13)).fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: Space.xs)
            Button("Undo") { Task { await model.undo(run: run.runID) } }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(model.isBusy)
                .help("Put these items back where they were")
            Button("Open History") { model.show(.history) }
                .buttonStyle(.borderless)
                .font(.system(size: 12))
        }
        .padding(.horizontal, Space.s)
        .padding(.vertical, Space.xs)
        .frame(maxWidth: .infinity, alignment: .leading)
        .surface(Radius.plate)
    }
}

/// Running apps and folders macOS keeps private, at the top of the preview: neutral, never red, and nothing to scroll for.
private struct PreviewNotices: View {
    let lines: [String]

    var body: some View {
        HStack(alignment: .top, spacing: Space.s) {
            Image(systemName: "hand.raised").font(.system(size: 13, weight: .medium)).foregroundStyle(.secondary)
                .well(Color.secondary, size: 28).accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                Text("Some items will stay where they are").font(.system(size: 13, weight: .semibold))
                ForEach(lines, id: \.self) {
                    Text($0).font(.system(size: 12)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(Space.s)
        .frame(maxWidth: .infinity, alignment: .leading)
        .surface(Radius.plate)
        .accessibilityElement(children: .combine)
    }
}

// MARK: - The stage: totals, coverage, orphan caveat

private struct PreviewStage: View {
    let scan: ScanResult
    let plan: TrashPlan
    let running: (plan: TrashPlan, finished: Int)?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private static let orphanHeader = "These belong to apps I can't find. I may be wrong if the app lives on a drive that is not connected."

    /// Why a leftover may have an owner that is still around somewhere Aftertaste cannot see.
    private static let orphanDoubts = [
        "The app is on an external or network drive that is not connected now.",
        "The app runs from Homebrew or the command line and never had an app bundle in the usual folders.",
        "The app belongs to another user account on this Mac, or to a virtual machine.",
        "The app is on another partition of this Mac.",
        "It is an iPhone or iPad app that runs on this Mac.",
        "A device manager installs or hides the app.",
        "It is a developer tool that never ships as an app bundle.",
    ]

    var body: some View {
        // While a run is going, Selected counts down to what is still to be reported (MOTION §3.2).
        let selectedItems = running.map { Array($0.plan.items.dropFirst($0.finished)) } ?? plan.items
        // One source for Found, Items and the sentence under them: what the scan says was left behind (`PlanText.previewHeader`
        // counts the same list). Rows that are listed but not counted are said, so the sidebar's per-app counts still add up.
        let left = scan.leftBehind
        let uncounted = scan.itemCount - left.count
        VStack(alignment: .leading, spacing: Space.s) {
            HStack(alignment: .top, spacing: Space.xl) {
                figure("Found", ResidueText.size(left), size: 40)
                figure("Items", String(left.count))
                figure("Selected", ResidueText.size(selectedItems))
                Spacer(minLength: 0)
            }
            .animation(Motion.standard(reduceMotion), value: selectedItems.count)
            .accessibilityHidden(true)
            if scan.kind == .orphans {
                Text(Self.orphanHeader).font(.system(size: 15)).fixedSize(horizontal: false, vertical: true)
                Text(PlanText.previewHeader(scan)).font(.system(size: 13)).foregroundStyle(.secondary)
                if uncounted > 0 { uncountedNote(uncounted) }
                DisclosureGroup("Why might this be wrong?") {
                    VStack(alignment: .leading, spacing: Space.xs) {
                        ForEach(Self.orphanDoubts, id: \.self) { Text($0).font(.system(size: 12)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true) }
                    }
                    .padding(Space.s)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .surface(16)
                }
                .font(.system(size: 13))
            } else {
                Text(PlanText.previewHeader(scan)).font(.system(size: 15)).fixedSize(horizontal: false, vertical: true)
                if uncounted > 0 { uncountedNote(uncounted) }
            }
            PreviewCoverage(scan: scan)
        }
    }

    /// "3.4 GB" as a number over a unit; "size not measured" is set small and may wrap, so the row never clips.
    private func figure(_ label: String, _ text: String, size: CGFloat = 26) -> some View {
        let parts = text.split(separator: " ", maxSplits: 1).map(String.init)
        let measured = parts.count == 2 && parts[0].first?.isNumber == true
        return Metric(label, measured ? parts[0] : text, unit: measured ? parts[1] : nil, size: measured ? size : 15)
            .fixedSize(horizontal: measured, vertical: true)
    }

    private func uncountedNote(_ n: Int) -> some View {
        Text("\(n) more \(n == 1 ? "item is" : "items are") listed below but not counted here: \(n == 1 ? "it is" : "they are") the app itself, or something an installed app also uses.")
            .font(.system(size: 12)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
    }
}

/// "Looked in 25 of 26 places. 1 protected by macOS." and, behind a disclosure, the places that were not read in full.
private struct PreviewCoverage: View {
    let scan: ScanResult
    @EnvironmentObject private var model: AppModel

    var body: some View {
        let unread = scan.coverage.places.filter { $0.state != .read && $0.state != .absent }
        VStack(alignment: .leading, spacing: Space.xs) {
            Text(PlanText.coverageLine(scan.coverage)).font(.system(size: 13)).foregroundStyle(.secondary)
            if !unread.isEmpty {
                DisclosureGroup("Places I could not read") {
                    VStack(alignment: .leading, spacing: Space.xs) {
                        ForEach(unread, id: \.root) { place in
                            HStack(spacing: Space.s) {
                                Text(place.root.displayName).font(.system(size: 13, weight: .semibold))
                                Text(word(place.state)).font(.system(size: 12)).foregroundStyle(.secondary)
                                Spacer(minLength: Space.xs)
                                Button("Reveal in Finder") { model.reveal(place.root.path(home: scan.home)) }
                                    .buttonStyle(.borderless)
                                    .font(.system(size: 12))
                                    .help("Show this folder in Finder")
                            }
                            .accessibilityElement(children: .combine)
                        }
                        if scan.coverage.protectedCount > 0 {
                            Text("macOS keeps some folders private from apps. You can look inside them yourself with Reveal in Finder. "
                                + "Allowing Aftertaste in System Settings, Privacy & Security, Full Disk Access may let it read more. It works without that.")
                                .font(.system(size: 12)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                            Button("Open Full Disk Access Settings") { model.openFullDiskAccessSettings() }
                                .buttonStyle(.bordered)
                                .controlSize(.small)
                        }
                    }
                    .padding(Space.s)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .surface(16)
                }
                .font(.system(size: 13))
            }
        }
    }

    private func word(_ state: PlaceState) -> String {
        switch state {
        case .protectedByMacOS: return "Protected by macOS"
        case .partial: return "Only partly read"
        case .failed: return "Could not be read"
        case .read, .absent: return "Read"
        }
    }
}

/// The quiet state: an empty outline, one calm sentence, and what was looked at, so a short page still reads as an answer.
/// The check shows only when every place was read (BUILD_PLAN §3 S20); a partial scan keeps the weaker sentence and says why.
private struct PreviewNothingFound: View {
    let scan: ScanResult
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let complete = scan.isCleanAndComplete
        VStack(spacing: Space.l) {
            VStack(spacing: Space.s) {
                ZStack {
                    DashedOutline(radius: 26, lineWidth: 2, opacity: 0.45)
                    Image(systemName: complete ? "checkmark.circle.fill" : "magnifyingglass")
                        .font(.system(size: 34))
                        .foregroundStyle(complete ? Color.green : Color.secondary)
                        .bounce(on: scan.scannedAt, reduceMotion: reduceMotion)
                }
                .frame(width: 96, height: 96)
                .accessibilityHidden(true)
                Text(PlanText.emptyState(scan)).font(.system(size: 17, weight: .semibold))
                if complete {
                    Text(scan.kind == .orphans ? "Nothing here belongs to an app that is no longer installed."
                                               : "Nothing in your Library is named for this app.")
                        .font(.system(size: 13)).foregroundStyle(.secondary)
                }
            }
            .multilineTextAlignment(.center)
            .accessibilityElement(children: .combine)
            checked
            if !complete { PreviewCoverage(scan: scan) }
        }
        .frame(maxWidth: 520)
        .frame(maxWidth: .infinity)
        .padding(.top, Space.xl)
        .padding(.bottom, Space.m)
    }

    /// What Aftertaste looked at. Names of places, a count of installed apps, and what it did not read.
    private var checked: some View {
        let names = scan.coverage.places.map { $0.root.displayName }
        let shown = names.prefix(4).joined(separator: ", ")
        return VStack(alignment: .leading, spacing: Space.s) {
            Text("What was checked").font(.caption.weight(.semibold).smallCaps()).foregroundStyle(.secondary)
            row("folder", "Places in your Library",
                names.count > 4 ? "\(shown) and \(names.count - 4) more." : (shown.isEmpty ? "None listed." : shown + "."))
            if scan.installedCount > 0 {
                row("app.badge.checkmark", Format.count(scan.installedCount, "installed app"), "Each name in those places was compared with them.")
            }
            row("list.bullet.rectangle", "Names and sizes only", "No file contents were read, apart from the small property lists that say who an app is.")
        }
        .padding(Space.m)
        .frame(maxWidth: .infinity, alignment: .leading)
        .surface(16)
    }

    private func row(_ symbol: String, _ title: String, _ detail: String) -> some View {
        HStack(alignment: .top, spacing: Space.s) {
            Image(systemName: symbol).font(.system(size: 11, weight: .medium)).foregroundStyle(.secondary)
                .well(Color.secondary, size: 24).accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 13, weight: .semibold))
                Text(detail).font(.system(size: 12)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

private struct PreviewNotCovered: View {
    var body: some View {
        DisclosureGroup("Not covered") {
            VStack(alignment: .leading, spacing: Space.xxs) {
                ForEach(PlanText.notCovered(), id: \.self) { Text($0).font(.system(size: 12)).foregroundStyle(.secondary) }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, Space.xxs)
        }
        .font(.system(size: 13))
    }
}

// MARK: - Group cards

/// The cards come in once per scan result: flipped down on a 45 ms stagger, at most three steps (MOTION §3.4). The parent
/// gives the view `.id(scan.scannedAt)`, so a new scan starts again from `shown == false`.
private struct PreviewGroups: View {
    let groups: [ResidueGroup]
    let departed: Set<String>
    @State private var shown = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(alignment: .leading, spacing: Space.xl) {
            ForEach(Array(groups.enumerated()), id: \.element.id) { index, group in
                if shown {
                    PreviewGroupCard(group: group, departed: departed)
                        .transition(.flip(reduceMotion).animation(Motion.spring(reduceMotion).delay(Motion.delay(min(index, 3), reduceMotion))))
                }
            }
        }
        .onAppear { withAnimation(Motion.standard(reduceMotion)) { shown = true } }
    }
}

private struct PreviewGroupCard: View {
    let group: ResidueGroup
    let departed: Set<String>
    @EnvironmentObject private var model: AppModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private struct ClassGroup: Identifiable {
        let kind: ResidueKind
        let items: [ResidueItem]
        var id: String { kind.rawValue }
    }

    var body: some View {
        let items = group.items.filter { !departed.contains($0.id) }
        let sections = ResidueText.classOrder.compactMap { kind -> ClassGroup? in
            let inKind = items.filter { $0.kind == kind }
            return inKind.isEmpty ? nil : ClassGroup(kind: kind, items: inKind)
        }
        let segments = ResidueBar.segments(for: ResidueGroup(owner: group.owner, isOrphan: group.isOrphan, runState: group.runState, items: items),
                                           ticked: model.ticked)
        VStack(alignment: .leading, spacing: Space.m) {
            header
            if !segments.isEmpty {
                ResidueBar(segments: segments)
            }
            VStack(alignment: .leading, spacing: Space.m) {
                ForEach(sections) { PreviewClassSection(kind: $0.kind, items: $0.items, group: group) }
            }
            .animation(Motion.spring(reduceMotion), value: departed)
        }
        .padding(Space.l)
        .frame(maxWidth: .infinity, alignment: .leading)
        .surface(18)
        .layered()
    }

    private var header: some View {
        let owner = group.owner
        let medium = group.count(.medium) > 0
        return HStack(alignment: .center, spacing: Space.s) {
            AppIconView(path: owner.bundlePath, size: 32)
            VStack(alignment: .leading, spacing: 2) {
                Text(owner.version.map { "\(owner.displayName) \($0)" } ?? owner.displayName)
                    .font(.system(size: 17, weight: .semibold)).fixedSize(horizontal: false, vertical: true)
                if let note = runNote {
                    Text(note).font(.system(size: 12)).foregroundStyle(.secondary)
                } else if group.isOrphan {
                    Text("Not installed").font(.system(size: 12)).foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: Space.s)
            if medium {
                Toggle("Include my data", isOn: Binding(get: { model.includeMyData.contains(owner.bundleID) },
                                                       set: { model.setIncludeMyData(owner: owner.bundleID, $0) }))
                    .toggleStyle(.switch)
                    .disabled(group.runState != .notRunning)
                    .help("Also select the items that may hold your own data. You confirm them before anything moves.")
            }
        }
    }

    /// "Running. Quit Orbit Meet first." The app's move is blocked; other apps' items proceed.
    private var runNote: String? {
        switch group.runState {
        case .notRunning: return nil
        case .running: return "Running. Quit \(group.owner.displayName) first."
        case .unknown: return WhyText.reason(.runningUnknown)
        }
    }
}

/// One class of one app (Cache, Logs, System ...): its header, its consequence line and its rows. A class that is only
/// listed (Hands off, Needs admin) folds after two rows, so a long list of read-only items never pushes the rest of the card
/// out of view; "Show more" opens it.
private struct PreviewClassSection: View {
    let kind: ResidueKind
    let items: [ResidueItem]
    let group: ResidueGroup
    @State private var showAll = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private static let folded = 2

    var body: some View {
        let listedOnly = items.allSatisfy { !$0.tier.isSelectable }
        let fold = listedOnly && !showAll && items.count > Self.folded + 1
        let shown = fold ? Array(items.prefix(Self.folded)) : items
        VStack(alignment: .leading, spacing: Space.xs) {
            VStack(alignment: .leading, spacing: 2) {
                Text("\(kind.displayName) · \(items.count)")
                    .font(.caption.weight(.semibold).smallCaps()).foregroundStyle(.secondary)
                Text(WhyText.consequence(kind)).font(.system(size: 12)).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            ForEach(shown) { item in
                PreviewItemRow(item: item, group: group)
                    .transition(.outline(reduceMotion, index: group.items.firstIndex(where: { $0.id == item.id }) ?? 0))
            }
            if fold {
                let rest = items.count - Self.folded
                Button("Show \(rest) More \(rest == 1 ? "Item" : "Items")") { withAnimation(Motion.standard(reduceMotion)) { showAll = true } }
                    .buttonStyle(.borderless)
                    .font(.system(size: 12))
            }
        }
    }
}

// MARK: - One row

private struct PreviewItemRow: View {
    let item: ResidueItem
    let group: ResidueGroup
    @EnvironmentObject private var model: AppModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var expanded = false
    @State private var hovering = false
    private enum ActionField: Hashable { case reveal, copy }
    @FocusState private var focused: ActionField?

    var body: some View {
        let why = item.why.isEmpty ? WhyText.line(for: item, owner: group.owner) : item.why
        let size = Format.size(item.size, item.sizeState)
        let blockedByRun = group.runState != .notRunning
        // The keyboard and VoiceOver always reach these two; the pointer or keyboard focus reveals them.
        let showActions = hovering || expanded || focused != nil || !item.tier.isSelectable
        HStack(alignment: .top, spacing: Space.s) {
            checkbox(blockedByRun: blockedByRun)
            Image(systemName: item.kind.symbol)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.secondary)
                .well(Color.secondary, size: 20)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                HStack(alignment: .firstTextBaseline, spacing: Space.xs) {
                    Text(item.name).font(.system(size: 13, weight: .semibold)).fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: Space.xs)
                    Text(size).font(.system(size: 12, weight: .medium, design: .rounded)).monospacedDigit().foregroundStyle(.secondary)
                    Tag(text: item.tier.displayName, tint: item.tier.tint)
                }
                Text(PathText.tilde(item.path, home: model.scan?.home ?? ""))
                    .font(.system(.caption, design: .monospaced)).foregroundStyle(.secondary)
                    .lineLimit(1).truncationMode(.middle)
                Text(why).font(.system(size: 12)).foregroundStyle(.secondary)
                    .lineLimit(expanded ? nil : (item.tier.isSelectable ? 2 : 1))   // a listed-only row is a single line; Details has the rest
                    .fixedSize(horizontal: false, vertical: true)
                if longNote {
                    Text(Self.listedNote(item)).font(.system(size: 12, weight: .medium)).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if expanded { details }
                HStack(spacing: Space.s) {
                    Button(expanded ? "Hide Details" : "Details") { withAnimation(Motion.standard(reduceMotion)) { expanded.toggle() } }
                        .buttonStyle(.borderless)
                    Group {
                        Button("Reveal in Finder") { model.reveal(item.path) }
                            .buttonStyle(.borderless)
                            .focused($focused, equals: .reveal)
                            .help("Show this item in Finder")
                        CopyButton(title: "Copy Path") { model.copyPath(item.path) }
                            .buttonStyle(.borderless)
                            .focused($focused, equals: .copy)   // VERIFY: .focused on the wrapper view reaches its inner Button
                            .help("Copy the full path")
                    }
                    .opacity(showActions ? 1 : 0)
                    Spacer(minLength: Space.xs)
                    if item.tier == .low {
                        Button("Move to Trash…") { model.requestMoveReview(id: item.id) }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                            .disabled(blockedByRun || model.phase != .idle)
                            .help("Review rows are moved one at a time, each with its own confirmation")
                    } else if !item.tier.isSelectable && !longNote {
                        Text(Self.listedNote(item)).font(.system(size: 12, weight: .medium)).foregroundStyle(.secondary)
                    }
                }
                .font(.system(size: 12))
            }
        }
        .padding(.vertical, 4)
        .onHover { hovering = $0 }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(item.name), \(item.tier.displayName), \(size), \(why)" + (item.tier.isSelectable ? "" : " Listed, not removed."))
    }

    /// High and Medium have a checkbox; Review, Hands off and Needs admin do not. A Medium row stays unticked and
    /// unavailable until the app's "Include my data" control is on.
    @ViewBuilder private func checkbox(blockedByRun: Bool) -> some View {
        if item.tier == .high || item.tier == .medium {
            let needsData = item.tier == .medium && !model.includeMyData.contains(group.owner.bundleID)
            Toggle(isOn: Binding(get: { model.ticked.contains(item.id) }, set: { _ in model.toggle(item.id) })) {
                Text("Select \(item.name)")
            }
            .toggleStyle(.checkbox)
            .labelsHidden()
            .disabled(blockedByRun || needsData || model.phase != .idle)
            .help(needsData ? "Turn on Include my data for this app first" : "Select this item")
        } else {
            Color.clear.frame(width: 16, height: 16).accessibilityHidden(true)
        }
    }

    private var details: some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(Array(item.evidence.enumerated()), id: \.offset) { _, evidence in
                Text("• " + Self.evidenceText(evidence))
            }
            if let root = item.root {
                let rule = ResidueRules.rule(for: root)
                Text("Place: \(root.displayName) · rule \(rule.id), \(rule.pattern)")
            }
            Text("Owner: \(group.owner.bundleID)")
            Text((item.sizeState == .notMeasured ? "Contents not measured" : Format.count(item.fileCount, "file"))
                + (item.mtime.map { " · changed \(Format.date($0))" } ?? ""))
            Text("Aftertaste read names and sizes, plus the small property-list files that say who an app is.")
        }
        .font(.system(.caption, design: .monospaced))
        .textSelection(.enabled)
        .padding(Space.xs)
        .frame(maxWidth: .infinity, alignment: .leading)
        .terminal()
    }

    /// The long note (the app bundle itself) is a line of its own; the short one sits at the end of the action row.
    private var longNote: Bool { item.tier == .needsAdmin && item.kind == .app }

    /// Hands off and Needs admin rows are shown and explained, never removed (v1 has no helper and no administrator rights).
    private static func listedNote(_ item: ResidueItem) -> String {
        item.tier == .needsAdmin && item.kind == .app
            ? "Listed, not removed. Drag it to the Trash in Finder, then run Find Leftovers."
            : "Listed, not removed."
    }

    private static func evidenceText(_ e: Evidence) -> String {
        let title: String
        switch e.kind {
        case .exactID: title = "Name is the bundle ID"
        case .helperSuffix: title = "Named after a helper of the app"
        case .embeddedID: title = "Named for a part inside the app"
        case .teamPrefix: title = "Starts with the developer's team ID"
        case .groupID: title = "A group the app shares data through"
        case .containerMetadata: title = "macOS lists this container under the app's ID"
        case .launchdLabelIsID: title = "Launch label starts with the app's ID"
        case .launchdProgramInBundle: title = "Starts a program inside the app"
        case .launchdProgramGone: title = "Starts a program that is no longer there"
        case .receipt: title = "An installer receipt names the app"
        case .caskZap: title = "A known folder of this app"
        case .displayName: title = "Named like the app"
        case .executableName: title = "Named after the app's program"
        case .inventoryAbsent: title = "Seen installed before, gone since"
        case .noLiveOwner: title = "No installed app has this ID"
        case .sameTeamInstalled: title = "An installed app has the same developer"
        case .staleMtime: title = "Not changed for a while"
        case .vendorNesting: title = "Inside a vendor folder"
        }
        return e.detail.isEmpty ? title : "\(title): \(e.detail)"
    }
}

// MARK: - The bar

private struct PreviewMoveBar: View {
    let count: Int
    @EnvironmentObject private var model: AppModel

    var body: some View {
        let idle = model.phase == .idle
        HStack(spacing: Space.s) {
            if case .running(let plan, let finished) = model.phase {
                // The move shows its progress here, in the window, with the rows leaving above it (the sheet stays small).
                MoveProgress(plan: plan, finished: finished, compact: true)
            } else {
                // The rarer actions share one menu so the bar fits the narrowest detail pane without truncating a label.
                Menu("More") {
                    Button("Select All High") { model.selectHigh() }
                    Button("Export Report") { model.showReport = true }
                    Button("Close Scan") { model.closeScan() }
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
                .disabled(!idle)
                .help("Select every High item, export the report, or close this scan")
                Spacer(minLength: Space.s)
                Text(count == 0 ? "Nothing selected" : "\(Format.count(count, "item")) selected")
                    .font(.system(size: 12)).foregroundStyle(.secondary).monospacedDigit().lineLimit(1).fixedSize()
                Button(PlanText.moveButton(count: count)) { model.requestMove() }
                    .buttonStyle(DuskButtonStyle())
                    .keyboardShortcut(.defaultAction)
                    .fixedSize()
                    .disabled(count == 0 || !idle)
            }
        }
        .padding(.vertical, Space.xs)
        .padding(.horizontal, Space.m)
        .barSurface()
        .padding(.horizontal, Space.l)
        .padding(.top, Space.xs)
        .padding(.bottom, Space.l)
    }
}
