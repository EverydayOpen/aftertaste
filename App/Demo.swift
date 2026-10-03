#if DEBUG
import AftertasteCore
import AppKit
import Combine
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
        /// Frozen at 40 percent: the rows leaving, part way.
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
        /// Idle on the preview, then Move with no confirm sheet and no visible sheet, a 4 s run, then the result: the README
        /// hero's frames (screens.yml records it).
        case hero
    }

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

    /// Non-nil in demo mode: the scenario's backend. `running` hangs part way and `hero` takes the real demo run, slowed to 4 s.
    static let backend: Backend? = setup.map { demo in
        var backend = DemoBackend.make(demo.scenario, seconds: demo.screen == .hero ? 4 : 1.2)
        if demo.screen == .running { backend.trash = { plan, _, progress in await Demo.hang(plan, progress, seconds: 1, at: 0.4) } }
        return backend
    }

    private static var started = false
    private static var sink: AnyCancellable?

    /// Called by AppModel.init, after the demo backend is in place.
    @MainActor static func start(_ model: AppModel) {
        guard let demo = setup, !started else { return }
        started = true
        trace("start screen=\(demo.screen) prefsSeen=\(model.prefs.hasSeenFirstRun)")
        var changes = 0
        sink = model.objectWillChange.sink { _ in
            changes += 1
            if changes >= 300 && changes < 303 { trace("change #\(changes)\n" + Thread.callStackSymbols.prefix(14).joined(separator: "\n")) }
        }
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
            Task { for wait in [3.0, 1.0, 1.0] { try? await Task.sleep(nanoseconds: UInt64(wait * 1_000_000_000)); scroll(to: fraction) } }
        }
    }

    @MainActor private static func run(_ screen: Screen, _ model: AppModel) async {
        trace("run begin installed=\(model.installed?.apps.count ?? -1)")
        if model.installed == nil { await model.start() }   // RootView's .task does the same; whichever comes first
        trace("run after start installed=\(model.installed?.apps.count ?? -1)")
        switch screen {
        case .picker, .firstRun: model.screen = .welcome
        case .readiness:
            model.screen = .readiness
            await model.loadReadiness()
        case .about: model.screen = .about
        case .preferences: model.showPreferences = true
        case .uninstall: await model.handleDrop([URL(fileURLWithPath: DemoScenarios.uninstallTarget)])
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
            await model.confirmMove()   // `running` never returns: its backend hangs at 40 percent
        case .activity, .undo:
            model.requestMove()
            await model.confirmMove()
            var runID: String?
            if case .result(let outcome) = model.phase { runID = outcome.runID }
            model.dismissResult()
            if screen == .undo, let runID { await model.undo(run: runID) }
            model.screen = .history
        case .hero:
            while !windowShown() { try? await Task.sleep(nanoseconds: 50_000_000) }   // the recording starts when the window is up
            try? await Task.sleep(nanoseconds: 2_500_000_000)   // idle frames first
            // The rows are the shot: the confirm sheet and any sheet during the run stay invisible until the result (which
            // is wanted at the end). Plan and confirm in one turn, so the confirm sheet is never drawn.
            model.requestMove()
            let hiding = Task { await hideSheets(while: model) }
            await model.confirmMove()
            await hiding.value
            try? await Task.sleep(nanoseconds: 700_000_000)
            for sheet in NSApp.windows.compactMap(\.attachedSheet) { sheet.alphaValue = 1 }   // in case the result reused the window
        }
    }

    /// The Trace Report card as the report sheet would draw it, from the scan the preview shows (`ShareCard` is the Core
    /// model, `Export` renders it). Names are hidden as the app's own default says: the card only names an app when the
    /// report covers exactly one.
    @MainActor private static func writeCard(_ model: AppModel, to path: String) -> Bool {
        guard let card = model.shareCard(hideNames: model.hideNamesDefault) else { return false }
        return Export.writePNG(card, to: URL(fileURLWithPath: path))
    }

    private static let windowTitle = "Aftertaste"

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
            try? await Task.sleep(nanoseconds: 20_000_000)
        }
    }

    /// The main window's widest scrollable area (the sidebar is narrower), scrolled to `fraction` of its travel from the top.
    /// VERIFY on a Mac that SwiftUI's ScrollView and List are NSScrollViews in the main window.
    @MainActor private static func scroll(to fraction: Double) {
        guard let root = (NSApp.windows.first { $0.title == windowTitle } ?? NSApp.mainWindow)?.contentView else { return }
        var best: NSScrollView?
        func find(_ view: NSView) {
            if let scroller = view as? NSScrollView, let document = scroller.documentView,
               document.frame.height > scroller.contentView.bounds.height + 1,
               scroller.frame.width > (best?.frame.width ?? 0) { best = scroller }
            view.subviews.forEach(find)
        }
        find(root)
        guard let scroller = best, let document = scroller.documentView else { return }
        let travel = document.frame.height - scroller.contentView.bounds.height
        scroller.contentView.scroll(to: NSPoint(x: 0, y: travel * (document.isFlipped ? fraction : 1 - fraction)))
        scroller.reflectScrolledClipView(scroller.contentView)
    }

    /// A run that reports the first `fraction` of its items as moved, evenly over `seconds`, then waits (the `running`
    /// capture). The real Trasher is never involved: this is a Backend closure in demo mode only.
    static func trace(_ s: String) { FileHandle.standardError.write(Data(("[demo] " + s + "\n").utf8)) }

    private static func hang(_ plan: TrashPlan, _ progress: @Sendable (ItemOutcome) -> Void, seconds: Double, at fraction: Double) async -> TrashOutcome {
        let started = Date()
        let reported = Int((Double(plan.items.count) * fraction).rounded(.down))
        let pause = UInt64(seconds / Double(max(reported, 1)) * 1_000_000_000)
        var results: [ItemOutcome] = []
        for item in plan.items.prefix(reported) {
            try? await Task.sleep(nanoseconds: pause)
            let outcome = ItemOutcome(item: item, status: .moved, trashedPath: DemoScenarios.trashFolder + "/" + item.name)
            results.append(outcome)
            progress(outcome)
        }
        while !Task.isCancelled { try? await Task.sleep(nanoseconds: 1_000_000_000) }
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
