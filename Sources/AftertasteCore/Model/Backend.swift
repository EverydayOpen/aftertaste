import Foundation

/// The seam between the app and the system: a struct of closures with exactly two implementations.
/// `AftertasteMac.LiveBackend.make(home:)` reads the real library and moves real files to the Trash;
/// `DemoBackend.make(_:)` (Core, `Demo/`) serves a fixture scenario and mutates an in-memory copy. In demo mode nothing is
/// read from or written to the real system.
public struct Backend: Sendable {
    /// The apps found in the usual folders, for the picker ("Choose an app"). Also refreshes the inventory (live only).
    public var installedApps: @Sendable () async -> InstalledSnapshot
    /// Validates a dropped or chosen `.app` path: is it an app, not Apple's, not this app, not nested in another app.
    public var identify: @Sendable (_ appPath: String) async -> AppLookup
    /// Lists the library once, measures candidates, and returns the analysed result. Never throws, never moves anything,
    /// never reads file contents. Coverage records what could not be read.
    public var scan: @Sendable (_ request: ScanRequest, _ prefs: Preferences) async -> ScanResult
    /// Whether the owner (or anything running from inside its bundle) is running right now. Re-read on every call.
    public var runState: @Sendable (_ owner: AppIdentity) -> RunState
    /// Runs a plan: per item, in order, re-verifies, writes the intent line, moves to the Trash, writes the result line, and
    /// calls `progress`. Never throws. Refuses to start if the journal cannot be opened for appending.
    public var trash: @Sendable (_ plan: TrashPlan, _ prefs: Preferences, _ progress: @escaping @Sendable (ItemOutcome) -> Void) async -> TrashOutcome
    /// Puts items back from the Trash to their recorded original location (never overwrites).
    public var undo: @Sendable (_ records: [UndoRecord], _ progress: @escaping @Sendable (UndoItemOutcome) -> Void) async -> UndoOutcome
    /// Which of these records still have their Trash entry (`UndoRecord.id`s). For "Already emptied" in History.
    public var inTrash: @Sendable (_ records: [UndoRecord]) -> Set<String>
    /// The Erase readiness facts. Read-only commands only.
    public var readiness: @Sendable () async -> ReadinessFacts
    /// The journal, oldest first.
    public var loadLog: @Sendable () -> [ActivityEntry]
    /// "Copy diagnostics": an errno matrix per scanned location, no file names (Core `DiagnosticsText`).
    public var diagnostics: @Sendable () async -> String
    /// True for the demo implementation: the window shows a "Sample data" badge and the card is watermarked.
    public var isDemo: Bool

    public init(installedApps: @escaping @Sendable () async -> InstalledSnapshot,
                identify: @escaping @Sendable (_ appPath: String) async -> AppLookup,
                scan: @escaping @Sendable (_ request: ScanRequest, _ prefs: Preferences) async -> ScanResult,
                runState: @escaping @Sendable (_ owner: AppIdentity) -> RunState,
                trash: @escaping @Sendable (_ plan: TrashPlan, _ prefs: Preferences, _ progress: @escaping @Sendable (ItemOutcome) -> Void) async -> TrashOutcome,
                undo: @escaping @Sendable (_ records: [UndoRecord], _ progress: @escaping @Sendable (UndoItemOutcome) -> Void) async -> UndoOutcome,
                inTrash: @escaping @Sendable (_ records: [UndoRecord]) -> Set<String>,
                readiness: @escaping @Sendable () async -> ReadinessFacts,
                loadLog: @escaping @Sendable () -> [ActivityEntry],
                diagnostics: @escaping @Sendable () async -> String,
                isDemo: Bool = false) {
        self.installedApps = installedApps
        self.identify = identify
        self.scan = scan
        self.runState = runState
        self.trash = trash
        self.undo = undo
        self.inTrash = inTrash
        self.readiness = readiness
        self.loadLog = loadLog
        self.diagnostics = diagnostics
        self.isDemo = isDemo
    }
}

/// Launch scenarios for demo mode (BUILD_PLAN §9). Raw values are what `-demoScenario <name>` accepts.
public enum DemoScenario: String, Codable, CaseIterable, Sendable {
    /// Nothing left behind in the places read, with complete coverage.
    case quiet
    /// Six removed apps, every tier and class, one app dropped for uninstall-now.
    case leftovers
    /// Only Medium and Review rows: nothing preselected.
    case maybeOnly = "maybe-only"
    /// macOS protected some folders (containers); blocked rows by name, coverage "Looked in 15 of 18 places".
    case blocked
    /// The first-run explanation over an empty welcome screen.
    case firstRun = "first-run"
    /// Erase readiness warns: local snapshots exist, FileVault on or off, flash storage.
    case snapshots
    /// Needs-admin rows: launch daemons, privileged helpers, receipts, read-only.
    case adminRows = "admin-rows"
}
