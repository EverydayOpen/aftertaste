import AftertasteCore
import SwiftUI

/// The window's content: one screen at a time (welcome, preview, history, Erase readiness, about) under one toolbar, a
/// cover while the Library is read or items are put back, and every sheet, one at a time: the first-run explainer, the
/// move (confirm, then moving, then the result, all one sheet whose content changes), the Trace Report and Preferences.
/// Hosting them here means they show on any screen.
struct RootView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private enum ActiveSheet: Hashable, Identifiable {
        case firstRun, move, report, preferences
        var id: Self { self }
    }

    var body: some View {
        
        screenView
            .frame(minWidth: 760, minHeight: 560)
            .overlay { cover }
            .overlay(alignment: .top) { notice }
            .animation(Motion.standard(reduceMotion), value: model.notice)
            .toolbar { toolbar }
            .sheet(item: sheet) { which in
                switch which {
                case .firstRun: FirstRunView().environmentObject(model)
                case .move:
                    // One sheet for the whole move, so confirm -> moving -> result swaps content instead of dismissing
                    // one sheet and presenting another.
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

    @ViewBuilder private var screenView: some View {
        switch model.screen {
        case .welcome: PickerView()
        case .preview: ResultsView()
        case .history: ActivityView(revealLog: { model.revealLog() })
        case .readiness: ReadinessView()
        case .about: AboutView()
        }
    }

    // MARK: - Toolbar

    /// Back on every screen but the welcome (it is disabled there). ResultsView adds its own Sample tag, Rescan, History and
    /// Erase readiness, so the root repeats those only on the other screens; Preferences is always here.
    @ToolbarContentBuilder private var toolbar: some ToolbarContent {
        ToolbarItem(placement: .navigation) {
            Button { model.goBack() } label: { Label("Back", systemImage: "chevron.left") }
                .disabled(model.screen == .welcome || model.isBusy)
                .help("Back (Command-[)")
        }
        ToolbarItemGroup(placement: .primaryAction) {
            if model.screen != .preview {
                if model.isDemo { Tag(text: TraceReportText.sampleWatermark, tint: .secondary) }
                Button { model.show(.history) } label: { Label("History", systemImage: "clock.arrow.circlepath") }
                    .disabled(model.screen == .history)
                    .help("History")
                Button { model.show(.readiness) } label: { Label("Erase Readiness", systemImage: "lock.shield") }
                    .disabled(model.screen == .readiness)
                    .help("Erase readiness")
            }
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

    /// One sheet at a time, in this order: the first-run explainer (until Continue), the move (confirm, moving, result), the
    /// report, Preferences. Esc cancels a confirmation, dismisses a result or closes a sheet; a running move and the
    /// first-run explainer cannot be dismissed. Putting items back has no sheet: it is the cover.
    private var sheet: Binding<ActiveSheet?> {
        Binding(
            get: {
                if !model.prefs.hasSeenFirstRun { return .firstRun }
                switch model.phase {
                case .confirming, .running, .result: return .move
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
