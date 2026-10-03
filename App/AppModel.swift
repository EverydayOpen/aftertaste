import AftertasteCore
import AftertasteMac
import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// The single source of truth (BUILD_PLAN §7). Core makes the scan, the selection and the plan; the backend reads and
/// moves; the views read this from the environment. The only file with UserDefaults, the pasteboard and the Finder bridge,
/// with `AftertasteApp` (safety_greps.sh checks 4, 8). Written, not compiled.
@MainActor final class AppModel: ObservableObject {
    enum Screen: Hashable { case welcome, preview, history, readiness, about }

    enum Phase: Equatable {
        case idle
        /// "Reading your Library for Orbit Meet…": by place, never a percentage.
        case scanning(String)
        /// The confirm sheet. Medium items in the plan only move once `acknowledgedMedium` is ticked.
        case confirming(TrashPlan)
        /// `finished` is how many outcomes the backend has reported, in the plan's order.
        case running(TrashPlan, finished: Int)
        case result(TrashOutcome)
        case undoing
    }

    /// `LiveBackend.make(...)`, or the scenario's backend in a DEBUG demo launch (App/Demo.swift).
    let backend: Backend
    @Published var screen: Screen = .welcome {
        didSet {
            if screen == .history, oldValue != .history { Task { await self.reloadHistory() } }
            // Leaving Erase readiness drops its facts, so the next visit never shows last time's.
            if oldValue == .readiness, screen != .readiness { readiness = nil }
        }
    }
    /// nil until `start()` has read the app folders (and not at all before the first-run explainer is passed).
    @Published private(set) var installed: InstalledSnapshot?
    @Published private(set) var request: ScanRequest?
    @Published private(set) var scan: ScanResult?
    /// The scan the user reviewed, kept after a move rescans: the Trace Report describes what was found, not the rescan.
    @Published private(set) var reportScan: ScanResult?
    /// Built only through `ItemSelection` (Core). Ids of ticked rows.
    @Published private(set) var ticked: Set<String> = []
    /// Owner ids whose "Include my data" control is on.
    @Published private(set) var includeMyData: Set<String> = []
    /// The confirm sheet's "I've looked at these; they may contain my data." checkbox.
    @Published var acknowledgedMedium = false
    @Published private(set) var phase: Phase = .idle { didSet { phaseChanged() } }
    /// Ids reported as moved while a run is in progress (drives the rows' departure, MOTION §3.2).
    @Published private(set) var movedSoFar: Set<String> = []
    @Published private(set) var lastOutcome: TrashOutcome?
    @Published private(set) var history: [HistoryRun] = []
    @Published private(set) var readiness: ReadinessFacts?
    /// Persisted as one JSON blob (not in demo mode).
    @Published var prefs: Preferences { didSet { prefsChanged(from: oldValue) } }
    /// `AppLookup.rejection`, shown under the drop zone.
    @Published var dropMessage: String?
    /// A one-line message in a pill over the window (an undo summary, "Diagnostics copied."). Clears itself.
    @Published var notice: String?
    @Published var showPreferences = false {
        didSet {
            // A keep-list edit made in Preferences re-reads the scan only once the sheet is closed (the scan cover would hide it).
            guard oldValue, !showPreferences, scanStale else { return }
            scanStale = false
            Task { await self.rescan() }
        }
    }
    /// The Trace Report sheet (app-report).
    @Published var showReport = false
    private var scanStale = false

    /// Either of the two sheets that leave the phase idle; the menu's navigation items wait while one is open.
    var sheetOpen: Bool { showReport || showPreferences }

    var isDemo: Bool { backend.isDemo }

    private static let prefsKey = "aftertaste.preferences"
    private var started = false
    private var scanTask: Task<ScanResult, Never>?
    private var scanGeneration = 0
    private var watchers: [NSObjectProtocol] = []
    private let icons = NSCache<NSString, NSImage>()

    init() {
        #if DEBUG
        let demo = Demo.backend   // non-nil only for a demo launch (App/Demo.swift)
        #else
        let demo: Backend? = nil
        #endif
        let home = NSHomeDirectory()
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? ""
        self.backend = demo ?? LiveBackend.make(home: home, appVersion: version)
        self.prefs = demo == nil ? Self.storedPrefs() : Preferences()
        AppDelegate.keepRunning = prefs.showMenuBarItem
        #if DEBUG
        Demo.start(self)
        #endif
    }

    // MARK: - Derived state

    /// "/Users/jane" in sample data, else the real home. Only for expanding `~` in the journal and for Finder.
    var homePath: String { isDemo ? DemoScenarios.home : NSHomeDirectory() }

    var appVersion: String { Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "" }

    var isBusy: Bool { phase != .idle }

    /// A Move or an Undo is in flight: quitting waits (`AppDelegate`), because the process must not die between an item
    /// reaching the Trash and its result line reaching the log.
    private func phaseChanged() {
        let moving: Bool
        switch phase {
        case .running, .undoing: moving = true
        default: moving = false
        }
        guard moving != AppDelegate.busy else { return }
        AppDelegate.busy = moving
        if moving { ProcessInfo.processInfo.disableSuddenTermination() } else { ProcessInfo.processInfo.enableSuddenTermination() }
    }

    /// The installed apps the picker offers: no Apple apps (never a target) and not Aftertaste itself. Sorted by name.
    var pickable: [AppIdentity] {
        let own = Bundle.main.bundleIdentifier
        return (installed?.apps ?? [])
            .filter { !$0.appleSigned && $0.bundleID != own }
            .sorted { $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending }
    }

    /// Exactly what the big button would move right now, from the planner itself (so the count on the button can never
    /// disagree with the plan): High and Medium ticked rows that are eligible. Medium counts as if acknowledged.
    var bulkPreview: (count: Int, bytes: UInt64) {
        guard let scan else { return (0, 0) }
        let plan = TrashPlanner.plan(from: scan, ticked: ticked, mode: .bulk(acknowledgedMedium: true), now: scan.scannedAt, runID: "preview")
        return (plan.items.count, plan.totalBytes)
    }

    /// The Trace Report's default for "Hide app names": on when the preference is on or the report covers several apps.
    var hideNamesDefault: Bool { prefs.hideAppNamesInExports || (reportScan ?? scan).map { $0.groups.count > 1 } ?? false }

    /// The data behind the Markdown and JSON exports and the card, from the scan the user reviewed. nil before a scan.
    func traceReport(hideNames: Bool, includeRows: Bool = true) -> TraceReport? {
        guard let source = reportScan ?? scan else { return nil }
        let options = TraceReportText.Options(hideNames: hideNames, includeRows: includeRows, appVersion: appVersion, isSample: isDemo)
        return TraceReportText.report(from: source, options: options, now: source.scannedAt)
    }

    /// The 1200 x 630 card's data (measured numbers only).
    func shareCard(hideNames: Bool) -> ShareCard? {
        traceReport(hideNames: hideNames, includeRows: false).map { TraceReportText.card(from: $0) }
    }

    // MARK: - Start

    /// Once per launch. Nothing is read before the first-run explainer has been passed (BUILD_PLAN §7.2).
    func start() async {
        guard !started else { return }
        started = true
        watchApps()
        guard prefs.hasSeenFirstRun else { return }
        await loadInstalledAndHistory()
    }

    private func loadInstalledAndHistory() async {
        installed = await backend.installedApps()
        await reloadHistory()
    }

    // MARK: - Choosing and scanning

    /// A file dropped on the window (or chosen in the panel): one app at a time, validated by the backend (`identify`).
    func handleDrop(_ urls: [URL]) async {
        dropMessage = nil
        guard phase == .idle else { return }
        guard urls.count == 1, let url = urls.first, url.isFileURL else {
            dropMessage = urls.count > 1 ? "Drop one app at a time." : "Drop an app from Finder."
            return
        }
        let lookup = await backend.identify(url.path)
        guard let identity = lookup.identity else {
            dropMessage = lookup.rejection ?? "That is not an app."
            return
        }
        await startScan(.app(identity), switchScreen: true)
    }

    /// An app picked from the installed list. It goes through `identify` too, so the same refusals apply.
    func choose(_ app: AppIdentity) async {
        dropMessage = nil
        guard phase == .idle else { return }
        if app.bundlePath.isEmpty {
            await startScan(.app(app), switchScreen: true)
            return
        }
        let lookup = await backend.identify(app.bundlePath)
        guard let identity = lookup.identity else {
            dropMessage = lookup.rejection ?? "That is not an app."
            return
        }
        await startScan(.app(identity), switchScreen: true)
    }

    /// "Choose an app…": the system open panel, applications only. Read-only; it only names a file.
    func chooseApp() async {
        guard phase == .idle else { return }
        guard !isDemo else {
            post("Choosing an app is not available in sample data.")
            return
        }
        let panel = NSOpenPanel()
        panel.title = "Choose an App"
        panel.prompt = "Choose"
        panel.allowedContentTypes = [.applicationBundle]
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.directoryURL = URL(fileURLWithPath: "/Applications", isDirectory: true)
        guard panel.runModal() == .OK else { return }
        await handleDrop(panel.urls)
    }

    func findOrphans() async {
        dropMessage = nil
        await startScan(.orphans, switchScreen: true)
    }

    /// ⌘R. Same request, fresh read; the ticks go back to the default (High only).
    func rescan() async {
        guard phase == .idle, let request else { return }
        await startScan(request, switchScreen: false)
    }

    private func startScan(_ r: ScanRequest, switchScreen: Bool) async {
        guard phase == .idle, prefs.hasSeenFirstRun else { return }
        let label = Self.scanLabel(r)
        phase = .scanning(label)
        announce(label)
        scanGeneration += 1
        let mine = scanGeneration
        let backend = self.backend, prefs = self.prefs
        let task = Task { await backend.scan(r, prefs) }
        scanTask = task
        let result = await task.value
        guard mine == scanGeneration else { return }   // cancelled: the cancel already put the phase back
        scanTask = nil
        request = r
        apply(result, keepReport: false)
        phase = .idle
        if switchScreen { screen = .preview }
        announce(PlanText.previewHeader(result))
    }

    /// The scan cover's Cancel. The backend may finish reading in the background; its result is dropped.
    func cancelScan() {
        guard case .scanning = phase else { return }
        scanGeneration += 1
        scanTask?.cancel()
        scanTask = nil
        phase = .idle
    }

    private static func scanLabel(_ r: ScanRequest) -> String {
        switch r {
        case .app(let app): return "Reading your Library for \(app.displayName)…"
        case .orphans: return "Reading your Library for apps that are gone…"
        }
    }

    private func apply(_ result: ScanResult, keepReport: Bool) {
        scan = result
        ticked = ItemSelection.preselected(result)
        includeMyData = []
        acknowledgedMedium = false
        if !keepReport { reportScan = result }
    }

    /// Back to the welcome screen, forgetting the scan.
    func closeScan() {
        guard phase == .idle else { return }
        scan = nil
        request = nil
        reportScan = nil
        ticked = []
        includeMyData = []
        acknowledgedMedium = false
        notice = nil
        scanStale = false
        showReport = false
        showPreferences = false
        screen = .welcome
    }

    // MARK: - Screens

    func show(_ next: Screen) {
        screen = next   // `screen`'s observer reloads the history; ReadinessView loads its own facts
    }

    /// The toolbar's Back: from the preview it closes the scan; from the other screens it returns to where you were.
    func goBack() {
        switch screen {
        case .welcome: break
        case .preview: closeScan()
        case .history, .readiness, .about: screen = scan == nil ? .welcome : .preview
        }
    }

    /// Clears the old facts first, so "Check Again" visibly checks.
    func loadReadiness() async {
        readiness = nil
        readiness = await backend.readiness()
    }

    /// The journal, newest run first, with "Already emptied" resolved against the Trash. Off the main thread.
    func reloadHistory() async {
        let backend = self.backend, home = homePath
        history = await Task.detached { () -> [HistoryRun] in
            let entries = backend.loadLog()
            let first = History.runs(from: entries, home: home, inTrash: nil)
            let present = backend.inTrash(first.flatMap { $0.items.map(\.record) })
            return History.runs(from: entries, home: home, inTrash: present)
        }.value
    }

    // MARK: - Selection and moving

    func toggle(_ id: String) {
        guard phase == .idle, let scan else { return }
        ticked = ItemSelection.toggle(ticked, id: id, in: scan)
    }

    /// "Select all High" (the items that rebuild themselves).
    func selectHigh() {
        guard phase == .idle, let scan else { return }
        ticked = ItemSelection.selectHigh(ticked, in: scan)
    }

    func setIncludeMyData(owner: String, _ on: Bool) {
        guard phase == .idle, let scan else { return }
        ticked = ItemSelection.includeMyData(ticked, owner: owner, on: on, in: scan)
        if on { includeMyData.insert(owner) } else { includeMyData.remove(owner) }
    }

    /// The big button: opens the confirm sheet with a plan of the ticked High and Medium rows (never Review).
    func requestMove() { makePlan(.bulk(acknowledgedMedium: true)) }

    /// A Review row's own "Move to Trash…".
    func requestMoveReview(id: String) { makePlan(.singleReview(id: id)) }

    private func makePlan(_ mode: TrashPlanner.Mode) {
        guard phase == .idle, let scan else { return }
        let now = Date()
        // Medium rows are listed in the plan so the sheet can name them; `confirmMove` refuses to run until the
        // acknowledgement is ticked and then stamps the plan with it.
        let plan = TrashPlanner.plan(from: scan, ticked: ticked, mode: mode, now: now,
                                     runID: TrashPlanner.newRunID(now: now, random: UInt32.random(in: 0...0xFF_FFFF)))
        guard !plan.items.isEmpty else {
            NSSound.beep()
            post(plan.skipped.first?.reason ?? "Nothing is ticked.")
            return
        }
        acknowledgedMedium = false
        phase = .confirming(plan)
    }

    func cancelConfirm() {
        guard case .confirming = phase else { return }
        acknowledgedMedium = false
        phase = .idle
    }

    /// Runs the confirmed plan off the main thread. The rows leave as outcomes arrive (`movedSoFar`); when everything has
    /// reported, the app rescans (so the result sits on top of fresh groups) and then shows the outcome.
    func confirmMove() async {
        guard case .confirming(var plan) = phase, !plan.items.isEmpty, !plan.includesMedium || acknowledgedMedium else { return }
        plan.acknowledgedMedium = plan.includesMedium && acknowledgedMedium
        movedSoFar = []
        phase = .running(plan, finished: 0)
        let backend = self.backend, prefs = self.prefs
        let outcome = await backend.trash(plan, prefs) { [weak self] item in
            Task { @MainActor in self?.noteReported(item) }
        }
        lastOutcome = outcome
        phase = .running(plan, finished: plan.items.count)
        if let request {
            let fresh = await backend.scan(request, prefs)
            apply(fresh, keepReport: true)
        }
        await reloadHistory()
        phase = .result(outcome)
        announce(PlanText.resultLine(outcome))
    }

    private func noteReported(_ item: ItemOutcome) {
        guard case .running(let plan, let n) = phase else { return }
        if item.status.wasMoved { movedSoFar.insert(item.item.id) }
        phase = .running(plan, finished: min(n + 1, plan.items.count))
    }

    func dismissResult() {
        guard case .result = phase else { return }
        phase = .idle
    }

    // MARK: - Undo

    func undo(run: String) async {
        guard let found = history.first(where: { $0.runID == run }) else { return }
        await performUndo(found.undoable)
    }

    func undo(item: UndoRecord) async { await performUndo([item]) }

    private func performUndo(_ records: [UndoRecord]) async {
        switch phase {
        case .idle, .result: break
        default: return
        }
        guard !records.isEmpty else {
            post("Nothing to put back.")
            return
        }
        phase = .undoing
        let backend = self.backend, prefs = self.prefs
        let outcome = await backend.undo(records) { _ in }
        phase = .idle
        await reloadHistory()
        if let request, outcome.restoredCount > 0 {
            let fresh = await backend.scan(request, prefs)
            apply(fresh, keepReport: false)
        }
        let text = Self.undoSummary(outcome)
        post(text)
    }

    private static func undoSummary(_ o: UndoOutcome) -> String {
        let restored = o.restoredCount
        var text = restored == 0 ? "Nothing was put back." : "Put back \(Format.count(restored, "item"))."
        let others = o.results.filter { $0.status != .restored }
        if let first = others.first {
            let why: String
            switch first.status {
            case .destinationExists: why = "something is already at the original location"
            case .alreadyEmptied: why = "the Trash was emptied"
            case .trashUnreadable: why = "macOS would not let me look in the Trash"
            case .changedSinceTrashed: why = "it changed in the Trash"
            case .failed, .restored: why = "it could not be moved"
            }
            text += " \(Format.count(others.count, "item")) could not be put back (\(others.count == 1 ? why : "for example, " + why))."
        }
        return text
    }

    // MARK: - Running apps

    /// An app starting or quitting changes which groups can move. No polling: the workspace tells us (BUILD_PLAN §7.2).
    private func watchApps() {
        guard !isDemo else { return }
        let center = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.didLaunchApplicationNotification, NSWorkspace.didTerminateApplicationNotification] {
            watchers.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor in self?.refreshRunStates() }
            })
        }
    }

    /// Re-reads `runState` for each group (off the main thread) and updates the scan in place. Never while a plan is
    /// confirmed or running: a plan is never changed under the user (the executor re-checks anyway).
    private func refreshRunStates() {
        guard phase == .idle, let current = scan, !current.groups.isEmpty else { return }
        let backend = self.backend
        let owners = current.groups.map(\.owner)
        Task {
            let states = await Task.detached { owners.map { backend.runState($0) } }.value
            guard phase == .idle, var updated = scan, updated.scannedAt == current.scannedAt, updated.groups.count == states.count else { return }
            for i in updated.groups.indices { updated.groups[i].runState = states[i] }
            if updated != scan { scan = updated }
        }
    }

    // MARK: - Finder, links, pasteboard

    /// The app's own icon for a bundle path; nil for no path (an orphan), in sample data, or when there is nothing to show.
    func icon(forApp path: String) -> NSImage? {
        guard !path.isEmpty, !isDemo else { return nil }
        if let hit = icons.object(forKey: path as NSString) { return hit }
        let image = NSWorkspace.shared.icon(forFile: path)
        icons.setObject(image, forKey: path as NSString)
        return image
    }

    func reveal(_ path: String) {
        guard !isDemo else {
            post("This is sample data, so there is nothing to show in Finder.")
            return
        }
        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)])
    }

    func copyPath(_ path: String) { copyToPasteboard(path) }

    func openTrash() {
        guard !isDemo else {
            post("This is sample data, so there is no Trash to open.")
            return
        }
        NSWorkspace.shared.open(URL(fileURLWithPath: homePath + "/.Trash", isDirectory: true))
    }

    /// Shows the newest journal file in Finder (its folder if there is none yet).
    func revealLog() {
        guard !isDemo else {
            post("The sample activity log lives in memory.")
            return
        }
        let folder = URL(fileURLWithPath: homePath + "/Library/Application Support/Aftertaste", isDirectory: true)
        let file = folder.appendingPathComponent(ActivityLog.fileName(for: Date()))
        if !NSWorkspace.shared.selectFile(file.path, inFileViewerRootedAtPath: folder.path), !NSWorkspace.shared.open(folder) {
            NSSound.beep()
        }
    }

    func openFullDiskAccessSettings() {
        if let url = URL(string: Links.fullDiskAccess) { NSWorkspace.shared.open(url) }
    }

    /// Opens a link in the browser, only on a click (the app makes no connections of its own).
    func openLink(_ url: URL) { NSWorkspace.shared.open(url) }
    func openEraseGuide() { openLink(Links.eraseAllContent) }
    func openWebsite() { openLink(Links.website) }
    func openReleases() { openLink(Links.releases) }
    func openIssues() { openLink(Links.issues) }

    /// "Copy card" and friends: the report of the scan the user reviewed, with names hidden as the default says. The
    /// Trace Report sheet exports its own report (it holds the "Hide app names" toggle).
    func exportReport(format: ExportFormat) {
        guard let report = traceReport(hideNames: hideNamesDefault) else {
            NSSound.beep()
            return
        }
        Export.run(format, report: report)
    }

    /// For testers (Help > Copy Diagnostics): an errno matrix per place, no file names (Core `DiagnosticsText`).
    func copyDiagnostics() async {
        let text = await backend.diagnostics()
        copyToPasteboard(text)
        post("Diagnostics copied.")
    }

    /// A one-line message that clears itself after a few seconds.
    func post(_ text: String) {
        notice = text
        announce(text)
        Task {
            try? await Task.sleep(nanoseconds: 8_000_000_000)
            if notice == text { notice = nil }
        }
    }

    // MARK: - Preferences

    private static func storedPrefs() -> Preferences {
        guard let data = UserDefaults.standard.data(forKey: prefsKey),
              let stored = try? JSONDecoder().decode(Preferences.self, from: data) else { return Preferences() }
        return stored
    }

    private func prefsChanged(from old: Preferences) {
        if !backend.isDemo, let data = try? JSONEncoder().encode(prefs) { UserDefaults.standard.set(data, forKey: Self.prefsKey) }
        AppDelegate.keepRunning = prefs.showMenuBarItem
        if !old.hasSeenFirstRun, prefs.hasSeenFirstRun, started { Task { await self.loadInstalledAndHistory() } }
        // The keep-list only adds protection; a scan on screen is re-read so a newly kept item disappears from it
        // (after Preferences closes, if it is open: a scan cover would take the sheet away mid-edit).
        if old.keepList != prefs.keepList, request != nil, phase == .idle {
            if showPreferences { scanStale = true } else { Task { await self.rescan() } }
        }
    }

    /// The spinner has no text of its own, so VoiceOver hears the outcome.
    private func announce(_ text: String) {
        NSAccessibility.post(element: NSApplication.shared, notification: .announcementRequested,
                             userInfo: [.announcement: text, .priority: NSAccessibilityPriorityLevel.high.rawValue])
    }
}
