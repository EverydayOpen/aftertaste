import AppKit
import AftertasteCore

/// What is running right now: NSWorkspace for bundle IDs, libproc for executable paths. Read fresh on every call, never
/// cached (S6). The app never quits or signals anything; a running owner only blocks its items.
public enum RunningApps {
    public static func snapshot() -> RunningSnapshot {
        // VERIFY: NSWorkspace.runningApplications from a background thread, and in a headless CI session.
        let ids = Set(NSWorkspace.shared.runningApplications.compactMap(\.bundleIdentifier))
        let paths = Processes.executablePaths()
        return RunningSnapshot(bundleIDs: ids, executablePaths: paths ?? [], readable: paths != nil)
    }
}
