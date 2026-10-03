import Foundation

public enum OrphanVerdict: Sendable, Equatable {
    /// No installed app owns it and enough evidence says an app of that ID used to be here.
    case orphan(evidence: [Evidence])
    /// `reason` is for tests and diagnostics, not for the user: a non-orphan is simply not listed. `tooRecent` is the one exception:
    /// the app vanished so lately it may be an update in flight, and the scan says how many it held back for that reason.
    case notOrphan(reason: String, tooRecent: Bool = false)
}

/// Is a bundle ID a leftover of an app that is gone? (APP4 §3.3 step 5, BUILD_PLAN §4.6.) Precision first: an ID is an orphan
/// only if no installed app owns it, nothing running owns it, and either the inventory saw the app installed and it has been
/// absent for `minAbsentDays`, or two independent kinds of evidence show an app of that ID existed.
///
/// Team ID (APP4 §3.3 step 5): when another installed app is signed by the same developer as an app the inventory saw, the
/// orphan is kept but every item of it is capped at Medium (`sameTeamInstalled`). A hard reject would hide real leftovers
/// whenever the developer still has any app installed. An orphan that rests on library evidence alone has no known Team ID.
public enum OrphanTest {
    /// A bundle that vanished more recently than this is treated as an update in flight, not a removal.
    public static let minAbsentDays = 3

    /// What the library shows for an ID, besides the item being matched. At least two kinds corroborate an app that never
    /// made it into the inventory.
    enum Corroboration: Hashable {
        case prefsPlist, folder, receipt, danglingLaunchd, containerMetadata
    }

    public static func isOrphan(id: String, in input: ScanInput, index: InstalledIndex) -> OrphanVerdict {
        let presence = OrphanCandidates.presence(of: [id], in: input.library)
        return evaluate(id: id, presence: presence[Names.fold(id)] ?? [], input: input, index: index)
    }

    static func evaluate(id: String, presence: Set<Corroboration>, input: ScanInput, index: InstalledIndex) -> OrphanVerdict {
        guard StrictBundleID.isValid(id) else { return .notOrphan(reason: "not a valid bundle ID") }
        if NeverList.reason(forName: id, keep: input.prefs.keepList) != nil { return .notOrphan(reason: "never touched") }
        if Hazards.isSharedUpdater(id) { return .notOrphan(reason: "shared updater state") }
        if !index.liveOwners(ofID: id).isEmpty { return .notOrphan(reason: "an installed app owns it") }
        let f = Names.fold(id)
        if input.running.bundleIDs.contains(where: { let r = Names.fold($0); return r == f || r.hasPrefix(f + ".") }) {
            return .notOrphan(reason: "it is running")
        }
        if let record = index.record(forID: id) {
            let gone = record.lastSeen.addingTimeInterval(Double(minAbsentDays) * 86_400)
            guard gone <= input.now else { return .notOrphan(reason: "seen installed very recently", tooRecent: true) }
            var evidence = [Evidence(.noLiveOwner), Evidence(.inventoryAbsent, Format.date(record.lastSeen))]
            if let team = record.identity.teamID, !team.isEmpty, let sibling = index.liveOwners(ofTeam: team).first {
                evidence.append(Evidence(.sameTeamInstalled, sibling.displayName))
            }
            return .orphan(evidence: evidence)
        }
        // ponytail: two of five evidence kinds, not a weighted score. The orphan caps (Medium unless a stale exact-ID cache) are the
        // real protection; tune the threshold when testers report false orphans.
        guard presence.count >= 2 else { return .notOrphan(reason: "not enough evidence that an app of that ID existed") }
        var evidence = [Evidence(.noLiveOwner)]
        // No inventory record means no Team ID to compare, so an installed app whose ID starts with the same two labels (a suite) counts as the same developer.
        let vendor = f.split(separator: ".").prefix(2).joined(separator: ".")
        if vendor != "com.apple", let sibling = index.apps.first(where: { Names.fold($0.bundleID).split(separator: ".").prefix(2).joined(separator: ".") == vendor }) {
            evidence.append(Evidence(.sameTeamInstalled, sibling.displayName))
        }
        return .orphan(evidence: evidence)
    }
}

/// Finds bundle-ID-shaped names in the roots that are keyed by bundle ID and groups them under one base ID per app.
/// Name-only folders (`Application Support/Spotify`) never create a candidate by themselves.
enum OrphanCandidates {
    /// Roots whose entry names can introduce a candidate.
    static let creating: [LibraryRoot] = [
        .preferences, .preferencesByHost, .caches, .applicationSupport, .containers, .logs, .savedState, .httpStorages, .webKit,
        .cookies, .launchAgents, .applicationScripts, .syncedPreferences, .recentDocuments,
    ]

    /// The name without one of the (lowercase, ASCII) extensions, original spelling; nil if it has none of them.
    static func dropping(_ name: String, _ exts: [String]) -> String? {
        let f = Names.fold(name)
        for ext in exts where f.hasSuffix(ext) && name.count > ext.count { return String(name.dropLast(ext.count)) }
        return nil
    }

    /// The bundle ID an entry's name (or its launchd label, or its container metadata) spells, original spelling.
    static func stems(of entry: LibraryEntry, in root: LibraryRoot) -> [String] {
        let name = entry.name
        var raw: String?
        switch root {
        case .preferences, .syncedPreferences, .systemPreferences: raw = dropping(name, [".plist"])
        case .preferencesByHost: raw = dropping(name, [".plist"]).flatMap { SubjectIndex.stripHostUUID($0) }
        case .savedState: raw = dropping(name, [".savedstate"])
        case .cookies: raw = dropping(name, [".binarycookies"])
        case .recentDocuments: raw = dropping(name, [".sfl2", ".sfl3"])
        case .httpStorages: raw = dropping(name, [".binarycookies"]) ?? name
        case .containers: raw = entry.containerID ?? name
        case .launchAgents, .systemLaunchAgents, .systemLaunchDaemons: raw = entry.launchd?.label ?? dropping(name, [".plist"]) ?? name
        case .receipts: raw = dropping(name, [".bom", ".plist"])
        default: raw = name
        }
        guard let raw, let parsed = StrictBundleID.looksLikeID(raw) else { return [] }
        return [parsed.id]
    }

    /// Strips one trailing helper label when the base keeps at least three labels ("com.example.app.helper" -> "com.example.app").
    static func base(of id: String) -> String {
        let labels = id.split(separator: ".").map(String.init)
        guard labels.count >= 4, let last = labels.last, Hazards.helperSuffixes.contains(Names.fold(last)) else { return id }
        return labels.dropLast().joined(separator: ".")
    }

    /// Folded base ID -> original spelling, after resolving inventory IDs and merging dotted children into a shorter candidate.
    static func derive(library: LibrarySnapshot, index: InstalledIndex, prefs: Preferences) -> [String: String] {
        var found: [String: String] = [:]
        for root in creating {
            guard let listing = library.listing(root) else { continue }
            for entry in listing.entries where Names.isSafeEntryName(entry.name) && entry.type != .other {
                if NeverList.reason(forName: entry.name, keep: prefs.keepList) != nil { continue }
                for stem in stems(of: entry, in: root) {
                    var id = base(of: stem)
                    if let record = index.record(forID: id) { id = record.identity.bundleID }
                    if Hazards.isSharedUpdater(id) || NeverList.reason(forName: id, keep: prefs.keepList) != nil { continue }
                    let key = Names.fold(id)
                    if found[key] == nil { found[key] = id }
                }
            }
        }
        // A candidate that is a dotted child of a shorter candidate (three labels or more) is that app's own file.
        var accepted: [String: String] = [:]
        for (key, id) in found.sorted(by: { $0.key.count < $1.key.count || ($0.key.count == $1.key.count && $0.key < $1.key) }) {
            let merged = Names.dotPrefixes(key).contains { $0.split(separator: ".").count >= 3 && accepted[$0] != nil }
            if !merged { accepted[key] = id }
        }
        return accepted
    }

    /// For each ID (folded), which kinds of evidence the library shows. One pass over every root, system roots included.
    static func presence(of ids: [String], in library: LibrarySnapshot) -> [String: Set<OrphanTest.Corroboration>] {
        let known = Set(ids.map(Names.fold))
        var out: [String: Set<OrphanTest.Corroboration>] = [:]
        func owner(of stem: String) -> String? {
            let f = Names.fold(stem)
            if known.contains(f) { return f }
            return Names.dotPrefixes(f).first { known.contains($0) }
        }
        for listing in library.listings {
            let root = listing.root
            for entry in listing.entries where Names.isSafeEntryName(entry.name) {
                for stem in stems(of: entry, in: root) {
                    guard let key = owner(of: stem) else { continue }
                    switch root {
                    case .receipts: out[key, default: []].insert(.receipt)
                    case .launchAgents, .systemLaunchAgents, .systemLaunchDaemons:
                        if let info = entry.launchd, !info.programExists { out[key, default: []].insert(.danglingLaunchd) }
                    case .containers:
                        if entry.containerID != nil { out[key, default: []].insert(.containerMetadata) } else { out[key, default: []].insert(.folder) }
                    case .preferences:
                        out[key, default: []].insert(Names.fold(stem) == key ? .prefsPlist : .folder)
                    case .systemPrivilegedHelperTools, .systemPreferences, .systemApplicationSupport, .systemCaches, .systemLogs, .groupContainers,
                         .diagnosticReports, .crashReporter, .autosaveInformation:
                        break
                    default: out[key, default: []].insert(.folder)
                    }
                }
            }
        }
        return out
    }
}
