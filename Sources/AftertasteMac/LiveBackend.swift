import Foundation
import AftertasteCore

/// The real `Backend` (BUILD_PLAN §5.9): composes the Mac files. Every path derives from the one injected `home`.
public enum LiveBackend {
    public static func make(home: String, appVersion: String) -> Backend {
        let osVersion = versionString()
        let last = Last()
        return Backend(
            installedApps: {
                let snapshot = InstalledApps.discover(home: home, inventory: InventoryStore.load(home: home), now: Date())
                InventoryStore.update(with: snapshot, home: home, now: Date())
                return snapshot
            },
            identify: { path in Identity.read(appURL: URL(fileURLWithPath: path, isDirectory: true), now: Date()) },
            scan: { request, prefs in
                let result = await ResidueScanner.scan(request, prefs: prefs, home: home, osVersion: osVersion, now: Date())
                last.setScan(result)
                return result
            },
            // An orphan has no bundle (empty path); RunningCheck never matches an empty path.
            runState: { owner in RunningCheck.state(owner: owner, itemPath: owner.bundlePath, snapshot: RunningApps.snapshot()) },
            trash: { plan, prefs, progress in
                await Trasher.run(plan, home: home, keep: prefs.keepList, now: { Date() }, progress: progress)
            },
            undo: { records, progress in
                UndoStore.restore(records, home: home, now: { Date() }, progress: progress)
            },
            inTrash: { records in UndoStore.presentInTrash(records) },
            readiness: {
                let facts = await ReadinessProbe.facts(now: Date(), macOSVersion: osVersion)
                last.setReadiness(facts)
                return facts
            },
            loadLog: { Journal.loadAll(home: home) },
            diagnostics: {
                let (scan, readiness) = last.snapshot()
                return DiagnosticsText.text(coverage: scan?.coverage ?? Coverage(), installedCount: scan?.installedCount ?? 0,
                                            osVersion: osVersion, appVersion: appVersion, readiness: readiness)
            },
            isDemo: false)
    }

    /// "26.1" (or "26.1.1"); what the report prints as "macOS 26.1".
    static func versionString() -> String {
        let v = ProcessInfo.processInfo.operatingSystemVersion
        return v.patchVersion > 0 ? "\(v.majorVersion).\(v.minorVersion).\(v.patchVersion)" : "\(v.majorVersion).\(v.minorVersion)"
    }

    /// The last scan and readiness result, kept only so "Copy diagnostics" has something to describe. Never written anywhere.
    private final class Last: @unchecked Sendable {
        private let lock = NSLock()
        private var scan: ScanResult?
        private var readiness: ReadinessFacts?
        func setScan(_ r: ScanResult) { lock.lock(); scan = r; lock.unlock() }
        func setReadiness(_ f: ReadinessFacts) { lock.lock(); readiness = f; lock.unlock() }
        func snapshot() -> (ScanResult?, ReadinessFacts?) { lock.lock(); defer { lock.unlock() }; return (scan, readiness) }
    }
}
