import Foundation

/// How a name matched an app (APP4 §3.3). Higher is stronger. `exact` and `proven` cap an item at High, `structural` at
/// Medium, `name` at Review. There is no fuzzy level: it does not exist.
enum Strength: Int, Comparable {
    case name = 0, structural = 1, proven = 2, exact = 3

    static func < (a: Strength, b: Strength) -> Bool { a.rawValue < b.rawValue }

    var cap: Tier {
        switch self {
        case .exact, .proven: return .high
        case .structural: return .medium
        case .name: return .low
        }
    }
}

/// One way an entry name matched one subject.
struct Hit {
    var subject: Int
    var strength: Strength
    var evidence: [Evidence]
    /// The name is the ID itself or the ID plus a documented extension (not a dotted child, helper or team match).
    var literal: Bool = false
    /// Matched through the developer's Team ID alone.
    var viaTeam: Bool = false
}

/// An app as the matcher sees it: folded, validated identifiers. Built from the target app, from an inventory record or
/// synthesised for an orphan, and from every installed app (the live-owner check).
struct Subject {
    let identity: AppIdentity
    let isLive: Bool
    /// Folded primary ID.
    let id: String
    /// Folded nested helper, login item and launchd label IDs -> original spelling. Never contains `id`.
    let embedded: [String: String]
    let helperLabels: Set<String>
    let groups: Set<String>
    let team: String?
    let variants: [String]
    let exec: String?
    /// Folded, normalised bundle path; empty when unknown.
    let bundle: String

    /// nil when the identity cannot be matched safely: for the app being removed (or an orphan) its bundle ID must pass
    /// `StrictBundleID`. An installed app only ever *protects* things, and matching is literal equality, so its IDs need
    /// not be strict: a live app with an unusual ID still keeps its folders safe.
    init?(_ identity: AppIdentity, isLive: Bool, allowNames: Bool) {
        let ok: (String) -> Bool = isLive ? Subject.isUsableLiveID : StrictBundleID.isValid
        guard ok(identity.bundleID) else { return nil }
        self.identity = identity
        self.isLive = isLive
        id = Names.fold(identity.bundleID)
        var embedded: [String: String] = [:]
        for e in identity.embeddedIDs + identity.helperLabels where ok(e) && Names.fold(e) != Names.fold(identity.bundleID) {
            embedded[Names.fold(e)] = e
        }
        self.embedded = embedded
        helperLabels = Set(identity.helperLabels.filter(ok).map(Names.fold))
        groups = Set(identity.groupIDs.filter(ok).map(Names.fold))
        team = identity.teamID.flatMap { StrictBundleID.isTeamID($0) ? Names.fold($0) : nil }
        variants = allowNames ? Names.variants(ofDisplayName: identity.displayName) : []
        let x = Names.fold(identity.execName)
        exec = allowNames && x.count >= 5 && !Hazards.commonWords.contains(x) ? x : nil
        bundle = Names.fold(GuardPolicy.normalize(identity.bundlePath))
    }

    /// Non-empty, no path separator, no control character.
    static func isUsableLiveID(_ s: String) -> Bool {
        !s.isEmpty && s.utf8.count <= 255 && !s.unicodeScalars.contains { $0.value < 32 || $0.value == 127 || $0 == "/" }
    }
}

/// Folded-name lookup tables over a set of subjects. Matching is literal and per root: an entry name is compared with the
/// rule's key, nothing recurses and nothing uses `contains`.
struct SubjectIndex {
    let subjects: [Subject]
    private var byID: [String: [Int]] = [:]
    private var byEmbedded: [String: [Int]] = [:]
    private var byGroup: [String: [Int]] = [:]
    private var byTeam: [String: [Int]] = [:]
    private var byVariant: [String: [Int]] = [:]
    private var byExec: [String: [Int]] = [:]
    private var productFolder: [String: [Int]] = [:]

    init(_ subjects: [Subject]) {
        self.subjects = subjects
        for (i, s) in subjects.enumerated() {
            byID[s.id, default: []].append(i)
            for e in s.embedded.keys { byEmbedded[e, default: []].append(i) }
            for g in s.groups { byGroup[g, default: []].append(i) }
            if let t = s.team { byTeam[t, default: []].append(i) }
            for v in s.variants { byVariant[v, default: []].append(i) }
            if let x = s.exec { byExec[x, default: []].append(i) }
            for folder in Hazards.perProductFolders[s.id] ?? [] {
                productFolder[folder.root.rawValue + "|" + Names.fold(folder.name), default: []].append(i)
            }
        }
    }

    /// All the ways `entry` (folded name `n`) matches a subject under `rule`, one hit per subject (the strongest).
    func hits(for entry: LibraryEntry, folded n: String, rule: ResidueRule) -> [Hit] {
        var out: [Hit] = []
        switch rule.key {
        case .idPlist:
            if let stem = Names.strip(n, ext: ".plist") { addStem(stem, dot: true, to: &out) }
        case .idByHost:
            if let s = Names.strip(n, ext: ".plist"), let stem = Self.stripHostUUID(s) { addStem(stem, dot: true, to: &out) }
        case .idExact:
            addStem(n, dot: false, to: &out)
        case .idDotPrefix:
            addStem(n, dot: true, to: &out)
        case .idExtension:
            for ext in Self.extensions(for: rule.root) { if let stem = Names.strip(n, ext: ext) { addStem(stem, dot: true, to: &out) } }
        case .idOrName:
            addStem(n, dot: true, to: &out)
            addNames(n, to: &out)
        case .execPrefix:
            addExec(n, root: rule.root, to: &out)
        case .launchLabel:
            addLaunch(entry, folded: n, to: &out)
        case .teamOrGroup:
            addGroup(n, name: entry.name, to: &out)
        case .containerID:
            addStem(n, dot: false, to: &out)
            if let cid = entry.containerID { addContainerMetadata(Names.fold(cid), to: &out) }
        case .receiptID:
            let stem = Names.strip(n, ext: ".bom") ?? Names.strip(n, ext: ".plist")
            if let stem {
                addStem(stem, dot: true, to: &out)
                out = out.map { var h = $0; h.evidence = [Evidence(.receipt, subjects[h.subject].identity.bundleID)]; return h }
            }
        }
        for i in productFolder[rule.root.rawValue + "|" + n] ?? [] {
            out.append(Hit(subject: i, strength: .proven, evidence: [Evidence(.caskZap, entry.name)]))
        }
        return Self.best(out)
    }

    // MARK: matching pieces

    private func addStem(_ stem: String, dot: Bool, to out: inout [Hit]) {
        for i in byID[stem] ?? [] {
            out.append(Hit(subject: i, strength: .exact, evidence: [Evidence(.exactID, subjects[i].identity.bundleID)], literal: true))
        }
        for i in byEmbedded[stem] ?? [] {
            out.append(Hit(subject: i, strength: .structural, evidence: [Evidence(.embeddedID, subjects[i].embedded[stem] ?? stem)]))
        }
        guard dot else { return }
        for prefix in Names.dotPrefixes(stem) where prefix.contains(".") {
            let suffix = Names.firstLabel(after: prefix, in: stem) ?? ""
            let isHelper = Hazards.helperSuffixes.contains(suffix)
            // A two-label ID ("com.company") is too short to claim everything that starts with it as its own. An installed
            // app still protects its dotted children whatever its length.
            let long = prefix.split(separator: ".").count >= 3
            for i in byID[prefix] ?? [] where long || subjects[i].isLive {
                let e = isHelper ? Evidence(.helperSuffix, suffix) : Evidence(.exactID, subjects[i].identity.bundleID)
                out.append(Hit(subject: i, strength: isHelper ? .structural : .exact, evidence: [e]))
            }
            for i in byEmbedded[prefix] ?? [] {
                out.append(Hit(subject: i, strength: .structural, evidence: [Evidence(.embeddedID, subjects[i].embedded[prefix] ?? prefix)]))
            }
        }
    }

    private func addNames(_ n: String, to out: inout [Hit]) {
        if byVariant.isEmpty { return }
        var candidates = [n]
        var index = n.startIndex
        while index < n.endIndex {
            let c = n[index]
            if index > n.startIndex, c == " " || c == "-" || c == "_" || c == ".", Self.isVersionTail(n[n.index(after: index)...]) {
                candidates.append(String(n[n.startIndex..<index]))
            }
            index = n.index(after: index)
        }
        for c in candidates {
            for i in byVariant[c] ?? [] {
                out.append(Hit(subject: i, strength: .name, evidence: [Evidence(.displayName, subjects[i].identity.displayName)]))
            }
        }
    }

    /// Only version words may follow the app name: "Orbit Meet Calendar" and "Slack Beta" are other products. `n` is already folded.
    private static func isVersionTail(_ rest: Substring) -> Bool {
        let words = rest.split(whereSeparator: { " -_.".contains($0) })
        return !words.isEmpty && words.allSatisfy { Names.isVersionWord(String($0)) }
    }

    private func addExec(_ n: String, root: LibraryRoot, to out: inout [Hit]) {
        if byExec.isEmpty { return }
        let exts = root == .crashReporter ? [".plist"] : [".ips", ".crash", ".diag"]
        guard let ext = exts.first(where: { n.hasSuffix($0) }), let stem = Names.strip(n, ext: ext) else { return }
        var prefixes: [String] = []
        var index = stem.startIndex
        while index < stem.endIndex {
            if index > stem.startIndex, stem[index] == "_" { prefixes.append(String(stem[stem.startIndex..<index])) }
            index = stem.index(after: index)
        }
        for p in prefixes {
            for i in byExec[p] ?? [] {
                out.append(Hit(subject: i, strength: .name, evidence: [Evidence(.executableName, subjects[i].identity.execName)]))
            }
        }
    }

    private func addContainerMetadata(_ cid: String, to out: inout [Hit]) {
        for i in byID[cid] ?? [] {
            out.append(Hit(subject: i, strength: .proven, evidence: [Evidence(.containerMetadata, subjects[i].identity.bundleID)]))
        }
        for i in byEmbedded[cid] ?? [] {
            out.append(Hit(subject: i, strength: .structural, evidence: [Evidence(.containerMetadata, subjects[i].embedded[cid] ?? cid)]))
        }
    }

    /// Launchd ownership (APP4 §3.3): (a) the label is the ID, starts with `ID.` or is a recorded helper label; (b) the program
    /// is inside the removed bundle; (c) the program is gone and the label starts with the ID. Anything else is not ours.
    private func addLaunch(_ entry: LibraryEntry, folded n: String, to out: inout [Hit]) {
        let info = entry.launchd
        let rawLabel = info?.label ?? (Names.strip(entry.name, ext: ".plist") ?? entry.name)
        let label = Names.fold(rawLabel)
        // Without a parsed plist the label is only the file name, which is a convention: structural, not exact.
        let byName: Strength = info == nil ? .structural : .exact
        for i in byID[label] ?? [] {
            out.append(Hit(subject: i, strength: byName, evidence: [Evidence(.launchdLabelIsID, rawLabel)], literal: true))
        }
        for i in byEmbedded[label] ?? [] {
            out.append(Hit(subject: i, strength: .structural, evidence: [Evidence(.launchdLabelIsID, rawLabel)]))
        }
        for prefix in Names.dotPrefixes(label) where prefix.contains(".") {
            let long = prefix.split(separator: ".").count >= 3
            for i in byID[prefix] ?? [] where long || subjects[i].isLive {
                var evidence = [Evidence(.launchdLabelIsID, rawLabel)]
                if let info, !info.programExists { evidence.append(Evidence(.launchdProgramGone, rawLabel)) }
                out.append(Hit(subject: i, strength: byName, evidence: evidence))
            }
            for i in byEmbedded[prefix] ?? [] {
                out.append(Hit(subject: i, strength: .structural, evidence: [Evidence(.launchdLabelIsID, rawLabel)]))
            }
        }
        if let program = info?.program {
            let p = Names.fold(GuardPolicy.normalize(program))
            // ponytail: a linear walk over every subject per launch item; index by bundle path if the app list ever gets huge.
            for (i, s) in subjects.enumerated() where !s.bundle.isEmpty && p.hasPrefix(s.bundle + "/") {
                out.append(Hit(subject: i, strength: .proven, evidence: [Evidence(.launchdProgramInBundle, rawLabel)]))
            }
        }
    }

    /// Group Containers: a known group ID, `group.<id>`, `<TeamID>.<id>` (exact), or just `<TeamID>.<anything>` (structural,
    /// shared by the developer's other apps).
    private func addGroup(_ n: String, name: String, to out: inout [Hit]) {
        for i in byGroup[n] ?? [] {
            out.append(Hit(subject: i, strength: .exact, evidence: [Evidence(.groupID, name)], literal: true))
        }
        if n.hasPrefix("group.") {
            let rest = String(n.dropFirst(6))
            for i in byID[rest] ?? [] {
                out.append(Hit(subject: i, strength: .exact, evidence: [Evidence(.groupID, name)], literal: true))
            }
            for prefix in Names.dotPrefixes(rest) {
                for i in byID[prefix] ?? [] { out.append(Hit(subject: i, strength: .structural, evidence: [Evidence(.groupID, name)])) }
            }
        }
        guard let dot = n.firstIndex(of: "."), n.distance(from: n.startIndex, to: dot) == 10 else { return }
        let head = String(n[n.startIndex..<dot])
        let tail = String(n[n.index(after: dot)...])
        for i in byTeam[head] ?? [] {
            let s = subjects[i]
            if tail == s.id || tail == "group." + s.id || tail.hasPrefix(s.id + ".") || tail.hasPrefix("group." + s.id + ".") {
                out.append(Hit(subject: i, strength: .exact, evidence: [Evidence(.exactID, s.identity.bundleID)], literal: tail == s.id))
            } else {
                out.append(Hit(subject: i, strength: .structural, evidence: [Evidence(.teamPrefix, head.uppercased())], viaTeam: true))
            }
        }
    }

    // MARK: helpers

    /// One hit per subject: the strongest (a literal one wins a tie), with the evidence of every hit for that subject, strongest first.
    static func best(_ hits: [Hit]) -> [Hit] {
        var chosen: [Int: Hit] = [:]
        for h in hits {
            guard let current = chosen[h.subject] else {
                chosen[h.subject] = h
                continue
            }
            let hWins = h.strength > current.strength || (h.strength == current.strength && h.literal && !current.literal)
            var merged = hWins ? h : current
            let other = hWins ? current : h
            merged.evidence += other.evidence.filter { !merged.evidence.contains($0) }
            if hWins { merged.viaTeam = h.viaTeam }
            chosen[h.subject] = merged
        }
        return chosen.values.sorted { $0.subject < $1.subject }
    }

    static func extensions(for root: LibraryRoot) -> [String] {
        switch root {
        case .savedState: return [".savedstate"]
        case .cookies: return [".binarycookies"]
        case .recentDocuments: return [".sfl2", ".sfl3"]
        default: return []
        }
    }

    /// "<id>.<hardware uuid>" -> "<id>" for ByHost preferences; nil when the tail is not a UUID.
    static func stripHostUUID(_ s: String) -> String? {
        guard s.count > 37 else { return nil }
        let tail = s.suffix(36)
        let dashes = [8, 13, 18, 23]
        let chars = Array(tail)
        for (i, c) in chars.enumerated() {
            if dashes.contains(i) { guard c == "-" else { return nil } } else { guard c.isHexDigit else { return nil } }
        }
        let head = s.dropLast(36)
        guard head.hasSuffix(".") else { return nil }
        return String(head.dropLast())
    }
}
