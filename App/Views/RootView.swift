import AftertasteCore
import SwiftUI

/// The window's content: one screen at a time (welcome, preview, history, Erase readiness, about) under one toolbar, a
/// cover while the Library is read or items are put back, and every sheet, one at a time: the first-run explainer, the
/// move (confirm, then the result; the progress of the move itself is the preview's bottom bar), the Trace Report and
/// Preferences. Hosting them here means they show on any screen.
///
/// The window's root is one `NavigationSplitView`, so AppKit gives its sidebar the full window height (under the title bar and
/// the traffic lights). The sidebar holds the apps of a preview that found something; on every other screen it is collapsed
/// and the screen is the detail.
struct RootView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// The app picked in the preview's sidebar; nil = every app.
    @State private var focus: String?
    /// What the user chose for the sidebar while it has anything to show.
    @State private var columns = NavigationSplitViewVisibility.all

    private enum ActiveSheet: Hashable, Identifiable {
        case firstRun, move, report, preferences
        var id: Self { self }
    }

    var body: some View {
        NavigationSplitView(columnVisibility: columnVisibility) {
            sidebar.navigationSplitViewColumnWidth(min: 240, ideal: 280, max: 360)
        } detail: {
            screenView
        }
        .frame(minWidth: 760, minHeight: 560)
        .overlay { cover }
        .overlay(alignment: .top) { notice }
        .animation(Motion.standard(reduceMotion), value: model.notice)
        .toolbar { toolbar }
        .sheet(item: sheet) { which in
            switch which {
            case .firstRun: FirstRunView().environmentObject(model)
            case .move:
                // One sheet for the confirmation and the result, so the result replaces the confirmation's content. The
                // move itself has no sheet: the window stays active and the rows leave the list behind it.
                Group {
                    if case .result = model.phase { TrashedView() } else { ConfirmSheet() }
                }
                .environmentObject(model)
            case .report:
                // The scan the user reviewed, not the rescan after a move: the card is the "before" screen.
                if let reviewed = model.reportScan ?? model.scan { TraceReportView(scan: reviewed).environmentObject(model) }
            case .preferences: PreferencesSheet().environmentObject(model)
            }
        }
        .task { await model.start() }
    }

    // MARK: - Sidebar and screens

    /// A preview with something found; every other screen, and a quiet result, is one centred page.
    private var showsSidebar: Bool { model.screen == .preview && model.scan?.groups.isEmpty == false }

    /// Collapsed whenever the sidebar has nothing to show; otherwise the user's choice. VERIFY on a Mac that the system
    /// sidebar button is harmless on the screens where it is collapsed (the setter ignores it there).
    private var columnVisibility: Binding<NavigationSplitViewVisibility> {
        Binding(get: { showsSidebar ? columns : .detailOnly }, set: { if showsSidebar { columns = $0 } })
    }

    /// A focused app that left the scan (moved, or gone after an undo rescan) falls back to every app in both panes.
    private var liveFocus: String? {
        guard let id = focus, model.scan?.groups.contains(where: { $0.id == id }) == true else { return nil }
        return id
    }

    @ViewBuilder private var sidebar: some View {
        if showsSidebar, let scan = model.scan {
            PreviewSidebar(scan: scan, focus: Binding(get: { liveFocus }, set: { focus = $0 }))
        } else {
            EmptyView()
        }
    }

    @ViewBuilder private var screenView: some View {
        switch model.screen {
        case .welcome: PickerView()
        case .preview: ResultsView(focus: liveFocus)
        case .history: ActivityView(revealLog: { model.revealLog() })
        case .readiness: ReadinessView()
        case .about: AboutView()
        }
    }

    // MARK: - Toolbar

    /// One toolbar for every screen, always in this order: the Sample tag (demo only), Rescan (preview only), History, Erase
    /// readiness, Preferences. Back is absent on the welcome screen, not disabled.
    @ToolbarContentBuilder private var toolbar: some ToolbarContent {
        if model.screen != .welcome {
            ToolbarItem(placement: .navigation) {
                Button { model.goBack() } label: { Label("Back", systemImage: "chevron.left") }
                    .disabled(model.isBusy)
                    .help("Back (Command-[)")
            }
        }
        ToolbarItemGroup(placement: .primaryAction) {
            if model.isDemo { Tag(text: TraceReportText.sampleWatermark, tint: .secondary) }
            if model.screen == .preview {
                Button { Task { await model.rescan() } } label: { Label("Rescan", systemImage: "arrow.clockwise") }
                    .disabled(model.isBusy)
                    .help("Read the Library again (Command-R)")
            }
            Button { model.show(.history) } label: { Label("History", systemImage: "clock.arrow.circlepath") }
                .disabled(model.screen == .history)
                .help("History")
            Button { model.show(.readiness) } label: { Label("Erase Readiness", systemImage: "lock.shield") }
                .disabled(model.screen == .readiness)
                .help("Erase readiness")
            Button { model.showPreferences = true } label: { Label("Preferences", systemImage: "gearshape") }
                .disabled(model.isBusy)
                .help("Preferences")
        }
    }

    // MARK: - Cover and notice

    /// While the Library is read (with Cancel) or items are put back (a short, uncancellable step): a veil that takes
    /// clicks, a spinner and one sentence.
    @ViewBuilder private var cover: some View {
        switch model.phase {
        case .scanning(let label): BusyCover(label: label, cancel: { model.cancelScan() })
        case .undoing: BusyCover(label: "Putting items back…", cancel: nil)
        default: EmptyView()
        }
    }

    /// An undo summary, "Diagnostics copied.": a pill on the controls layer that clears itself.
    @ViewBuilder private var notice: some View {
        if let text = model.notice {
            HStack(spacing: Space.s) {
                Text(text).font(.callout).fixedSize(horizontal: false, vertical: true)
                Button { model.notice = nil } label: { Image(systemName: "xmark") }
                    .buttonStyle(.borderless)
                    .help("Dismiss")
                    .accessibilityLabel("Dismiss")
            }
            .padding(.horizontal, Space.m)
            .padding(.vertical, Space.xs)
            .barSurface()
            .padding(.top, Space.s)
            .transition(.opacity)
        }
    }

    // MARK: - Sheets

    /// One sheet at a time, in this order: the first-run explainer (until Continue), the move (confirm, then result), the
    /// report, Preferences. Esc cancels a confirmation, dismisses a result or closes a sheet; the first-run explainer cannot
    /// be dismissed. A running move has no sheet (its progress is the preview's bottom bar, so the window stays active and the
    /// rows are seen leaving) and putting items back has none either: it is the cover.
    private var sheet: Binding<ActiveSheet?> {
        Binding(
            get: {
                if !model.prefs.hasSeenFirstRun { return .firstRun }
                #if DEBUG
                if Demo.hidesMoveSheet { return nil }   // the hero records the rows leaving with the window active
                #endif
                switch model.phase {
                case .confirming, .result: return .move
                default: break
                }
                if model.showReport { return .report }
                if model.showPreferences, model.phase == .idle { return .preferences }
                return nil
            },
            set: { _ in
                if !model.prefs.hasSeenFirstRun { return }
                switch model.phase {
                case .confirming: model.cancelConfirm()
                case .result: model.dismissResult()
                case .running, .undoing, .scanning: break
                case .idle:
                    if model.showReport { model.showReport = false } else { model.showPreferences = false }
                }
            })
    }
}

/// A centred card over a light veil: a spinner, one sentence, an optional Cancel. The veil blocks the window behind it.
private struct BusyCover: View {
    let label: String
    let cancel: (() -> Void)?

    var body: some View {
        ZStack {
            Color.black.opacity(0.12)
            VStack(spacing: Space.s) {
                ProgressView().controlSize(.regular)
                Text(label).font(.callout).multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
                if let cancel { Button("Cancel", action: cancel).buttonStyle(.bordered).keyboardShortcut(.cancelAction) }
            }
            .padding(Space.xl)
            .frame(maxWidth: 340)
            .surface(Radius.plate)
        }
        .accessibilityElement(children: .contain)
    }
}
