import Foundation

/// The residue map as data: one rule per place Aftertaste looks (BUILD_PLAN §4.3, APP4 §3.2). `ceiling` is the honesty
/// mechanism: whatever the evidence says, an item never ends above it. `zapShare` is informational (the fraction of
/// Homebrew casks with a zap stanza that list the location).
public enum ResidueRules {
    public static let all: [ResidueRule] = [
        ResidueRule(id: "U1", root: .preferences, pattern: "<id>.plist", key: .idPlist, kind: .settings, ceiling: .high,
                    access: "Readable without special permission.", zapShare: 0.755),
        ResidueRule(id: "U1b", root: .preferencesByHost, pattern: "<id>.<uuid>.plist", key: .idByHost, kind: .settings, ceiling: .high,
                    access: "Readable without special permission."),
        ResidueRule(id: "U3", root: .caches, pattern: "<id>, <id>.*", key: .idDotPrefix, kind: .cache, ceiling: .high, shareRisk: .possible,
                    access: "Shared updater caches are excluded by name.", zapShare: 0.465),
        ResidueRule(id: "U7", root: .savedState, pattern: "<id>.savedState", key: .idExtension, kind: .state, ceiling: .high,
                    zapShare: 0.481),
        ResidueRule(id: "U8", root: .httpStorages, pattern: "<id>, <id>.binarycookies", key: .idDotPrefix, kind: .cookies, ceiling: .high,
                    zapShare: 0.241),
        ResidueRule(id: "U9", root: .webKit, pattern: "<id>", key: .idExact, kind: .state, ceiling: .high, zapShare: 0.105),
        ResidueRule(id: "U10", root: .cookies, pattern: "<id>.binarycookies", key: .idExtension, kind: .cookies, ceiling: .high,
                    access: "May need Full Disk Access on newer macOS (VERIFY).", zapShare: 0.038),
        ResidueRule(id: "U11", root: .logs, pattern: "<id>, <Name>", key: .idOrName, kind: .logs, ceiling: .high, shareRisk: .possible,
                    access: "A name-only match is Review at most.", zapShare: 0.188),
        ResidueRule(id: "U11b", root: .diagnosticReports, pattern: "<Exec>_*.ips", key: .execPrefix, kind: .logs, ceiling: .high,
                    shareRisk: .possible, access: "Named after the program, so it needs a second proof."),
        ResidueRule(id: "U17", root: .crashReporter, pattern: "<Exec>_*.plist", key: .execPrefix, kind: .logs, ceiling: .high,
                    shareRisk: .possible, access: "Named after the program, so it needs a second proof."),
        ResidueRule(id: "U16", root: .recentDocuments, pattern: "<id>.sfl2, <id>.sfl3", key: .idExtension, kind: .state, ceiling: .high),
        // v1 lists launch agents and never removes them (owner decision): removing the file would not stop a loaded job.
        // Flipping this ceiling to .high with proof is a one-row change for v1.1.
        ResidueRule(id: "U12", root: .launchAgents, pattern: "<label>.plist", key: .launchLabel, kind: .launchItem, ceiling: .handsOff,
                    shareRisk: .possible, access: "Listed only in v1.", zapShare: 0.020),
        ResidueRule(id: "U15", root: .syncedPreferences, pattern: "<id>.plist", key: .idPlist, kind: .settings, ceiling: .medium,
                    shareRisk: .possible, access: "Syncs to your other devices.", zapShare: 0.001),
        ResidueRule(id: "U6", root: .applicationScripts, pattern: "<id>, <id>.*", key: .idDotPrefix, kind: .yourData, ceiling: .medium,
                    access: "Scripts you may have written.", zapShare: 0.140),
        ResidueRule(id: "U2", root: .applicationSupport, pattern: "<id>, <Name>", key: .idOrName, kind: .yourData, ceiling: .medium,
                    shareRisk: .high, access: "Vendor folders are shared and are never offered.", zapShare: 0.649),
        ResidueRule(id: "U4", root: .containers, pattern: "<id>, <uuid> + metadata", key: .containerID, kind: .yourData, ceiling: .medium,
                    shareRisk: .possible, access: "macOS 14 and later may refuse to look inside (VERIFY).", zapShare: 0.147),
        ResidueRule(id: "U5", root: .groupContainers, pattern: "<TeamID>.<name>, group.<id>", key: .teamOrGroup, kind: .shared, ceiling: .low,
                    shareRisk: .high, access: "Shared by every app of the developer; protected from macOS 15 (VERIFY).", zapShare: 0.057),
        ResidueRule(id: "U14", root: .autosaveInformation, pattern: "<id>*", key: .idDotPrefix, kind: .yourData, ceiling: .handsOff,
                    access: "May hold unsaved documents.", zapShare: 0.002),
        ResidueRule(id: "S2", root: .systemApplicationSupport, pattern: "<id>, <Name>", key: .idOrName, kind: .system, ceiling: .needsAdmin,
                    shareRisk: .high, zapShare: 0.019),
        ResidueRule(id: "S3", root: .systemCaches, pattern: "<id>, <id>.*", key: .idDotPrefix, kind: .system, ceiling: .needsAdmin,
                    shareRisk: .possible, zapShare: 0.003),
        ResidueRule(id: "S4", root: .systemPreferences, pattern: "<id>.plist", key: .idPlist, kind: .system, ceiling: .needsAdmin,
                    shareRisk: .possible, zapShare: 0.006),
        ResidueRule(id: "S5", root: .systemLaunchDaemons, pattern: "<label>.plist", key: .launchLabel, kind: .system, ceiling: .needsAdmin,
                    shareRisk: .possible, zapShare: 0.010),
        ResidueRule(id: "S6", root: .systemLaunchAgents, pattern: "<label>.plist", key: .launchLabel, kind: .system, ceiling: .needsAdmin,
                    shareRisk: .possible, zapShare: 0.002),
        ResidueRule(id: "S7", root: .systemPrivilegedHelperTools, pattern: "<label>", key: .launchLabel, kind: .system, ceiling: .needsAdmin,
                    zapShare: 0.004),
        ResidueRule(id: "S8", root: .receipts, pattern: "<pkg id>.bom, <pkg id>.plist", key: .receiptID, kind: .system, ceiling: .needsAdmin,
                    shareRisk: .possible, access: "Names only; readable without root is VERIFY.", zapShare: 0.001),
        ResidueRule(id: "S11", root: .systemLogs, pattern: "<id>, <Name>", key: .idOrName, kind: .system, ceiling: .needsAdmin,
                    shareRisk: .possible, zapShare: 0.009),
    ]

    private static let byRoot: [LibraryRoot: ResidueRule] = Dictionary(uniqueKeysWithValues: all.map { ($0.root, $0) })

    /// Every root has exactly one rule (a test asserts it), so this never fails for a shipped root.
    public static func rule(for root: LibraryRoot) -> ResidueRule {
        byRoot[root] ?? ResidueRule(id: "none", root: root, pattern: "", key: .idExact, kind: .system, ceiling: .handsOff)
    }
}
