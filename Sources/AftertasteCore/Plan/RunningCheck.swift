import Foundation

/// Is the owner (or anything running from inside its bundle or the item itself) running right now? (BUILD_PLAN S6.)
/// Pure: the Mac layer hands over a `RunningSnapshot`. Anything but `.notRunning` blocks the item; Aftertaste never quits,
/// signals or unloads anything.
public enum RunningCheck {
    /// `.unknown` when the process list could not be read (fail closed). `.running` when one of the owner's IDs is a running
    /// app, or any executable path is inside the owner's bundle or inside `itemPath`. An empty path never matches anything.
    public static func state(owner: AppIdentity?, itemPath: String, snapshot: RunningSnapshot) -> RunState {
        guard snapshot.readable else { return .unknown }
        if let owner {
            let running = Set(snapshot.bundleIDs.map(Names.fold))
            if owner.allIDs.contains(where: { running.contains(Names.fold($0)) }) { return .running }
        }
        let roots = [owner?.bundlePath ?? "", itemPath].map { Names.fold(GuardPolicy.normalize($0)) }.filter { !$0.isEmpty && $0 != "/" }
        guard !roots.isEmpty else { return .notRunning }
        for executable in snapshot.executablePaths {
            let e = Names.fold(GuardPolicy.normalize(executable))
            if roots.contains(where: { e == $0 || e.hasPrefix($0 + "/") }) { return .running }
        }
        return .notRunning
    }

    /// The worse of two states: running, then unknown, then not running.
    static func worst(_ a: RunState, _ b: RunState) -> RunState {
        if a == .running || b == .running { return .running }
        if a == .unknown || b == .unknown { return .unknown }
        return .notRunning
    }
}
