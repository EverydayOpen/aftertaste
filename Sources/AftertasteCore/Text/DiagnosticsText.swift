import Foundation

/// "Copy diagnostics": what happened at each scanned location, as numbers. No file names, no app names, no paths below the
/// fixed folders Aftertaste looks in. Testers paste it into an issue so the macOS container question can be settled.
public enum DiagnosticsText {
    public static func text(coverage: Coverage, installedCount: Int, osVersion: String, appVersion: String, readiness: ReadinessFacts?) -> String {
        var lines = ["Aftertaste \(appVersion.isEmpty ? "(unknown version)" : appVersion) on macOS \(osVersion.isEmpty ? "(unknown)" : osVersion)"]
        lines.append("Installed apps found: \(installedCount)")
        lines.append("Looked in \(coverage.looked) of \(coverage.total) places; \(coverage.protectedCount) protected, \(coverage.partialCount) partial, \(coverage.failedCount) failed")
        lines.append("Running apps readable: \(coverage.processListUnreadable ? "no" : "yes")")
        lines.append("App folders that could not be read: \(coverage.unreadableAppFolders.count)")
        lines.append("A drive that may be missing: \(coverage.volumeMayBeMissing ? "yes" : "no")")
        lines.append("")
        lines.append("Place | result | errno | entries")
        for p in coverage.places {
            let place = p.root.isSystem ? p.root.relativePath : "~/" + p.root.relativePath
            lines.append("\(place) | \(p.state.rawValue) | \(p.errno.map(String.init) ?? "-") | \(p.entryCount)")
        }
        if let r = readiness {
            lines.append("")
            lines.append("FileVault: \(r.fileVault.rawValue)")
            lines.append("Storage: \(r.storage.rawValue)\(r.fileSystem.map { ", " + $0 } ?? "")")
            lines.append("Apple silicon: \(r.isAppleSilicon.map { $0 ? "yes" : "no" } ?? "unknown")")
            lines.append("Local snapshots: \(r.localSnapshotCount.map(String.init) ?? "unknown")")
            if !r.failedProbes.isEmpty { lines.append("Probes that failed: " + r.failedProbes.joined(separator: ", ")) }
        }
        return lines.joined(separator: "\n")
    }
}
