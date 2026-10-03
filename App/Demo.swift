#if DEBUG
import AftertasteCore
import AppKit
import SwiftUI

/// Screenshots (.github/workflows/screens.yml), DEBUG builds only (BUILD_PLAN §9). A launch argument opens one screen on
/// synthetic data: the scenario's Mac is built in Core (`DemoBackend`, fictional apps, home /Users/jane), so nothing is read
/// from or moved on the real system and no activity is logged. Aftertaste is a window app, so the main window is simply the
/// app's own `Window` scene (no menu bar item is involved, unlike Overstay).
///
///     -demoScreen <screen>      or --demo-screen
///     -demoScenario <scenario>  or --demo-scenario, -demo, or AFTERTASTE_DEMO=<scenario>; each screen has a default scenario
///     -demoAppearance light|dark
///     -demoCardOut <png path>   renders the Trace Report card with Export after the scan and quits
///     -demoScroll <0...1>       scrolls the main window's widest scrollable area to that fraction (what is below the fold)
///
/// Names ignore case and hyphens. An unknown name stops the app, so a typo in the workflow fails its capture.
/// AppModel calls `Demo.backend` when it picks its backend and `Demo.start(self)` at the end of init.
enum Demo {
    enum Screen: String, CaseIterable {
        /// Welcome: the drop zone and the installed list.
        case picker
        /// Welcome with the first-run explainer over it.
        case firstRun
        /// Uninstall-now: the sample installed app is dropped, so its bundle is a plan item.
        case uninstall
        /// The orphan preview ("Find leftovers"), grouped by app.
        case results
        /// The same preview on a Mac with nothing left behind: "Nothing found" with the coverage line.
        case quiet
        /// The confirm sheet.
        case confirm
        /// Frozen half way (3 of 6 reported): the progress sheet, the rows that were reported already gone behind it.
        case running
        /// The result sheet after a move. The scenario's drifting folder makes one row "changed since you reviewed it" (`edge`).
        case trashed
        /// History after a move and an Undo of that run.
        case undo
        /// History: the seeded runs and the one just made, with Undo offered.
        case activity
        /// The Trace Report sheet over the preview.
        case report
        case readiness, about, preferences
        /// The README hero's run (screens.yml records it): the sample app is dropped, so its four safe-to-lose rows sit
        /// together in one card; idle, a glide down to them, then Move with no confirm sheet and no sheet during the run, so
        /// the rows tick off into the Trash one by one in an undimmed, active window; a pause, then the result sheet.
        case hero
        /// The same run on the orphan preview (the app's other way in): the High rows of the first card leave. Rows of one
        /// card are further apart there, so fewer are in view at once; `hero` is the better GIF.
        case heroOrphans
    }

    /// While true, the move sheet is not presented for the confirm, moving and result phases, so the list stays in view with
    /// the window active (a sheet dims and deactivates the window behind it, and `alphaValue` on the sheet window does not
    /// undo that). Only the hero runs set it. VERIFY: RootView's sheet binding reads this, in a `#if DEBUG` line of its
    /// `get` (docs in the report); until it does, `hideSheets` only makes the sheet transparent.
    static var hidesMoveSheet = false

    /// nil on a normal launch.
    private static let setup: (screen: Screen, scenario: DemoScenario)? = {
        let name = argument("demoScreen")
        let given = argument("demoScenario") ?? argument("demo") ?? ProcessInfo.processInfo.environment["AFTERTASTE_DEMO"]
        guard name != nil || given != nil else { return nil }
        // BUILD_PLAN §9's screen names; "blocked" is the preview on the `blocked` scenario.
        let aliases: [String: Screen] = ["welcome": .picker, "preview": .results, "orphans": .results, "blocked": .results,
                                         "result": .trashed, "edge": .trashed, "history": .activity, "card": .report]
        let screen = name.map { (n: String) -> Screen in parse(n, alias: aliases) } ?? .results
        var scenario = DemoScenario.leftovers
        switch screen {
        case .firstRun: scenario = .firstRun
        case .readiness: scenario = .snapshots
        case .quiet: scenario = .quiet
        default: if name.map(key) == "blocked" { scenario = .blocked }
        }
        if let given { scenario = parse(given) }
        return (screen, scenario)
    }()

    private static func isHero(_ screen: Screen) -> Bool { screen == .hero || screen == .heroOrphans }

    /// Non-nil in demo mode: the scenario's backend. `running` hangs part way. A hero takes the real demo run, slowed so each
    /// row's departure can be seen, and without the scenario's two scripted failures: every ticked row moves (the stills of
    /// the result sheet keep the failures, and say so).
    static let backend: Backend? = setup.map { demo in
        var backend = DemoBackend.make(demo.scenario, seconds: demo.screen == .hero ? 3.2 : (demo.screen == .heroOrphans ? 4 : 1.2),
                                       scripted: !isHero(demo.screen))
        if demo.screen == .running { backend.trash = { plan, _, progress in await Demo.hang(plan, progress, seconds: 1, at: 0.5) } }
        return backend
    }

    private static var started = false

    /// Called by AppModel.init, after the demo backend is in place.
    @MainActor static func start(_ model: AppModel) {
        guard let demo = setup, !started else { return }
        started = true
        if let look = argument("demoAppearance") {
            NSApplication.shared.appearance = NSAppearance(named: look == "dark" ? .darkAqua : .aqua)
        }
        // Not persisted: AppModel only stores preferences when the backend is not the demo.
        model.prefs.hasSeenFirstRun = demo.screen != .firstRun
        Task {
            await run(demo.screen, model)
            // `open` activates the app already; this covers a launch that lost focus while the scan ran.
            activateApp()
        }
        if let fraction = argument("demoScroll").flatMap(Double.init) {
            // Three passes: a lazy List or ScrollView only knows its full height after the first rows have been measured.
            Task { for wait in [3.0, 1.0, 1.0] { await pause(wait); scroll(to: fraction) } }
        }
    }

    @MainActor private static func run(_ screen: Screen, _ model: AppModel) async {
        if model.installed == nil { await model.start() }   // RootView's .task does the same; whichever comes first
        switch screen {
        case .picker, .firstRun: model.screen = .welcome
        case .readiness:
            model.screen = .readiness
            await model.loadReadiness()
        case .about: model.screen = .about
        case .preferences: model.showPreferences = true
        case .uninstall, .hero: await model.handleDrop([URL(fileURLWithPath: DemoScenarios.uninstallTarget)])
        default: await model.findOrphans()
        }
        if let path = argument("demoCardOut") {
            if !writeCard(model, to: path) { fatalError("Could not write the card") }
            NSApp.terminate(nil)
            return
        }
        switch screen {
        case .picker, .firstRun, .readiness, .about, .preferences, .uninstall, .results, .quiet: break
        case .confirm: model.requestMove()
        case .report: model.showReport = true
        case .running, .trashed:
            model.requestMove()
            await model.confirmMove()   // `running` never returns: its backend hangs part way
        case .activity, .undo:
            model.requestMove()
            await model.confirmMove()
            var runID: String?
            if case .result(let outcome) = model.phase { runID = outcome.runID }
            model.dismissResult()
            if screen == .undo, let runID { await model.undo(run: runID) }
            model.screen = .history
        case .hero, .heroOrphans: await playHero(screen, model)
        }
    }

    /// The README hero's frames are a burst of window captures while this plays (screens.yml), so every pause here is a
    /// stretch of frames. From the window appearing: 1.6 s for the scan and the cards dealing in (screens.yml drops those
    /// frames), then idle 1.2, glide 0.8, still 0.9, the run (3.2 or 4 s), the rows closing up 1.5, the result sheet 2.
    @MainActor private static func playHero(_ screen: Screen, _ model: AppModel) async {
        while !windowShown() { await pause(0.05) }   // the recording starts when the window is up
        activateApp()
        await pause(1.6)   // not recorded: the scan and the cards dealing in
        await pause(1.2)   // idle frames first
        // The rows that will leave come into view (offsets are points from the top of the list; VERIFY by eye on the first
        // CI frames and adjust: they depend on the card layout).
        await glide(to: screen == .hero ? 380 : 800, over: 0.8)
        await pause(0.9)
        // Plan and confirm in one turn, so the confirm sheet is never drawn; no sheet at all during the run (hook), and a
        // transparent one as a fallback. The window stays key and undimmed, the rows leave as outcomes arrive.
        hidesMoveSheet = true
        model.requestMove()
        let hiding = Task { await hideSheets(while: model) }
        await model.confirmMove()
        await hiding.value
        await pause(1.5)   // the remaining rows close the gap; the Selected figure has counted down
        hidesMoveSheet = false
        model.notice = nil   // a published write, so RootView asks for its sheet again and the result comes up
        for sheet in NSApp.windows.compactMap(\.attachedSheet) { sheet.alphaValue = 1 }   // in case the result reused the window
        await pause(2)
    }

    /// The Trace Report card as the report sheet would draw it, from the scan the preview shows (`ShareCard` is the Core
    /// model, `Export` renders it). Names are hidden as the app's own default says: the card only names an app when the
    /// report covers exactly one.
    @MainActor private static func writeCard(_ model: AppModel, to path: String) -> Bool {
        guard let card = model.shareCard(hideNames: model.hideNamesDefault) else { return false }
        return Export.writePNG(card, to: URL(fileURLWithPath: path))
    }

    private static let windowTitle = "Aftertaste"

    private static func pause(_ seconds: Double) async { try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000)) }

    @MainActor private static func windowShown() -> Bool {
        NSApp.windows.contains { $0.title == windowTitle && $0.isVisible }
    }

    /// Sets any sheet of the app's windows to fully transparent every 20 ms while a move is confirmed or running.
    /// VERIFY on a Mac that `alphaValue` hides a SwiftUI sheet window and that the next sheet comes up opaque.
    @MainActor private static func hideSheets(while model: AppModel) async {
        func moving() -> Bool {
            switch model.phase {
            case .confirming, .running: return true
            default: return false
            }
        }
        while moving() {
            for sheet in NSApp.windows.compactMap(\.attachedSheet) { sheet.alphaValue = 0 }
            await pause(0.02)
        }
    }

    // MARK: Scrolling

    /// The main window's widest scrollable area (the sidebar is narrower).
    /// VERIFY on a Mac that SwiftUI's ScrollView and List are NSScrollViews in the main window.
    @MainActor private static func listScroller() -> NSScrollView? {
        guard let root = (NSApp.windows.first { $0.title == windowTitle } ?? NSApp.mainWindow)?.contentView else { return nil }
        var best: NSScrollView?
        func find(_ view: NSView) {
            if let scroller = view as? NSScrollView, let document = scroller.documentView,
               document.frame.height > scroller.contentView.bounds.height + 1,
               scroller.frame.width > (best?.frame.width ?? 0) { best = scroller }
            view.subviews.forEach(find)
        }
        find(root)
        return best
    }

    /// How far the list has travelled, in points from the top, and how far it can.
    @MainActor private static func position(of scroller: NSScrollView) -> (offset: CGFloat, travel: CGFloat) {
        guard let document = scroller.documentView else { return (0, 0) }
        let travel = max(document.frame.height - scroller.contentView.bounds.height, 0)
        let y = scroller.contentView.bounds.origin.y
        return (document.isFlipped ? y : travel - y, travel)
    }

    @MainActor private static func place(_ scroller: NSScrollView, offset: CGFloat) {
        guard let document = scroller.documentView else { return }
        let travel = position(of: scroller).travel
        let y = min(max(offset, 0), travel)
        scroller.contentView.scroll(to: NSPoint(x: 0, y: document.isFlipped ? y : travel - y))
        scroller.reflectScrolledClipView(scroller.contentView)
    }

    /// `fraction` of the list's travel from the top.
    @MainActor private static func scroll(to fraction: Double) {
        guard let scroller = listScroller() else { return }
        place(scroller, offset: position(of: scroller).travel * CGFloat(fraction))
    }

    /// To `offset` points from the top over `seconds`, eased, one step per frame, so the capture burst has frames of it.
    @MainActor private static func glide(to offset: CGFloat, over seconds: Double) async {
        guard let scroller = listScroller() else { return }
        let from = position(of: scroller).offset
        let steps = max(Int(seconds * 60), 1)
        for step in 1...steps {
            let t = CGFloat(step) / CGFloat(steps)
            place(scroller, offset: from + (offset - from) * (t * t * (3 - 2 * t)))
            await pause(1.0 / 60)
        }
    }

    // MARK: The frozen run

    /// A run that reports the first `fraction` of its items as moved, evenly over `seconds`, then waits (the `running`
    /// capture). The real Trasher is never involved: this is a Backend closure in demo mode only.
    private static func hang(_ plan: TrashPlan, _ progress: @Sendable (ItemOutcome) -> Void, seconds: Double, at fraction: Double) async -> TrashOutcome {
        let started = Date()
        let reported = Int((Double(plan.items.count) * fraction).rounded(.down))
        let step = seconds / Double(max(reported, 1))
        var results: [ItemOutcome] = []
        for item in plan.items.prefix(reported) {
            await pause(step)
            let outcome = ItemOutcome(item: item, status: .moved, trashedPath: DemoScenarios.trashFolder + "/" + item.name)
            results.append(outcome)
            progress(outcome)
        }
        while !Task.isCancelled { await pause(1) }
        return TrashOutcome(runID: plan.runID, startedAt: started, finishedAt: Date(), results: results, skipped: plan.skipped)
    }

    // MARK: Arguments

    /// The value after `-name` or `--kebab-name` (`demoScreen` is also `--demo-screen`), never a stored setting.
    private static func argument(_ name: String) -> String? {
        let kebab = name.map { $0.isUppercase ? "-" + $0.lowercased() : String($0) }.joined()
        let arguments = ProcessInfo.processInfo.arguments
        guard let i = arguments.firstIndex(where: { $0 == "-" + name || $0 == "--" + kebab }), i + 1 < arguments.count else { return nil }
        return arguments[i + 1]
    }

    private static func key(_ s: String) -> String { s.lowercased().replacingOccurrences(of: "-", with: "") }

    private static func parse<T: CaseIterable & RawRepresentable>(_ name: String, alias: [String: T] = [:]) -> T
    where T.RawValue == String {
        guard let hit = alias[key(name)] ?? T.allCases.first(where: { key($0.rawValue) == key(name) }) else {
            fatalError("Unknown demo name")   // constant text: a crash report must not carry names
        }
        return hit
    }
}
#endif
