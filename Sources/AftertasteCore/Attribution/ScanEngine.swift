import Foundation

/// The classifier. Pure and deterministic: a snapshot of the library and of the installed apps goes in, grouped and tiered
/// findings come out (BUILD_PLAN §4.2, §4.6). Evidence only ever lowers or keeps a tier; nothing raises one above its caps.
public enum Scan {
    /// Paths worth measuring: every finding that is not vetoed outright, directories only (a file's size comes from its
    /// stamp), user roots only (system rows are never measured). The Mac layer measures them and calls `analyze` again.
    public static func candidatePaths(_ input: ScanInput) -> [String] {
        let skipped: Set<BlockReason> = [.appleOwned, .neverList, .iCloud, .ownCopy, .dataless]
        var paths = Set<String>()
        for group in Engine(input).run(forMeasuring: true) {
            for item in group.items where item.fileType == .directory && !(item.root?.isSystem ?? false) {
                if let b = item.blocked, skipped.contains(b) { continue }
                paths.insert(item.path)
            }
        }
        return paths.sorted()
    }

    /// The bundle IDs the scan would report on (the app being removed, or the orphan candidates). The Mac layer asks Launch Services
    /// whether any of them is installed somewhere the app folders did not show, then analyses again.
    public static func ownerIDs(_ input: ScanInput) -> [String] { Engine(input).run(forMeasuring: true).map(\.owner.bundleID) }

    /// Matching, guards, tiers, caps and groups (largest first), plus the coverage of what was looked at.
    public static func analyze(_ input: ScanInput) -> ScanResult {
        let engine = Engine(input)
        let (found, recentlyRemoved) = engine.runAll(forMeasuring: false)
        var coverage = engine.coverage
        coverage.recentlyRemovedCount = recentlyRemoved
        let groups = found.sorted {
            $0.totalBytes != $1.totalBytes ? $0.totalBytes > $1.totalBytes
                : (Names.fold($0.owner.displayName), $0.owner.bundleID) < (Names.fold($1.owner.displayName), $1.owner.bundleID)
        }
        return ScanResult(scannedAt: input.now, kind: input.kind, groups: groups, coverage: coverage, home: input.home,
                          osVersion: input.osVersion, installedCount: input.installed.apps.count)
    }
}

struct Engine {
    enum Claim: Int, Comparable {
        case none = 0, shared, sibling, drop
        static func < (a: Claim, b: Claim) -> Bool { a.rawValue < b.rawValue }
    }

    struct Cand {
        var owner: Int
        var entry: LibraryEntry
        var root: LibraryRoot
        var rule: ResidueRule
        var path: String
        var hit: Hit
        var claim = Claim.none
        var never: BlockReason?
    }

    let input: ScanInput
    let home: String
    let index: InstalledIndex
    let live: SubjectIndex
    let coverage: Coverage
    let ownerMayBeElsewhere: Bool
    let rootPaths: Set<String>

    init(_ input: ScanInput) {
        self.input = input
        home = GuardPolicy.normalize(input.home)
        index = InstalledIndex(installed: input.installed.apps, excluding: input.kind == .app ? input.target : nil, inventory: input.inventory)
        live = SubjectIndex(index.apps.compactMap { Subject($0, isLive: true, allowNames: true) })
        coverage = Coverage(places: input.library.listings.map(\.coverage), processListUnreadable: !input.running.readable,
                            unreadableAppFolders: input.installed.unreadableLocations, volumeMayBeMissing: input.installed.volumeMayBeMissing)
        ownerMayBeElsewhere = input.installed.volumeMayBeMissing || !input.installed.unreadableLocations.isEmpty
        rootPaths = Set(LibraryRoot.allCases.map { Names.fold(GuardPolicy.normalize($0.path(home: GuardPolicy.normalize(input.home)))) })
    }

    // MARK: run

    func run(forMeasuring: Bool) -> [ResidueGroup] { runAll(forMeasuring: forMeasuring).groups }

    /// The groups, and how many orphan candidates were held back only because their app vanished too recently.
    func runAll(forMeasuring: Bool) -> (groups: [ResidueGroup], recentlyRemoved: Int) {
        var recentlyRemoved = 0
        var owners: [Subject] = []
        var ownerEvidence: [[Evidence]] = []
        let isOrphan = input.kind == .orphans
        switch input.kind {
        case .app:
            guard let target = input.target, !target.appleSigned,
                  NeverList.reason(forName: target.bundleID) == nil, let s = Subject(target, isLive: false, allowNames: true) else { return ([], 0) }
            owners = [s]
            ownerEvidence = [[]]
        case .orphans:
            let found = OrphanCandidates.derive(library: input.library, index: index, prefs: input.prefs)
            let presence = OrphanCandidates.presence(of: Array(found.values), in: input.library)
            for (key, id) in found.sorted(by: { $0.key < $1.key }) {
                let verdict = OrphanTest.evaluate(id: id, presence: presence[key] ?? [], input: input, index: index)
                guard case .orphan(let evidence) = verdict else {
                    if case .notOrphan(reason: _, tooRecent: true) = verdict { recentlyRemoved += 1 }
                    continue
                }
                let record = index.record(forID: id)
                let identity = record?.identity ?? AppIdentity(bundleID: id, displayName: Names.prettyName(fromID: id), capturedAt: input.now)
                // A name made up from the last label of an ID must not match folders; only a real recorded name may.
                guard let s = Subject(identity, isLive: false, allowNames: record != nil) else { continue }
                owners.append(s)
                ownerEvidence.append(evidence)
            }
        }
        let ownerIndex = SubjectIndex(owners)
        var cands = candidates(ownerIndex)
        var kept: [Cand] = []
        // An owner with an installed sibling (same ID, same release channel family) shares its name-keyed folders with it.
        let withSibling = Set(owners.indices.filter { i in live.subjects.contains { index.isSibling($0.identity, of: owners[i].identity) } })
        for var c in cands {
            let owner = owners[c.owner]
            c.never = NeverList.reason(forPath: c.path, home: home, keep: input.prefs.keepList)
            if c.never == nil, NeverList.keeps(bundleID: owner.identity.bundleID, keep: input.prefs.keepList) { c.never = .neverList }
            c.claim = claim(of: c, owner: owner)
            if c.claim < .sibling, c.hit.strength == .name, withSibling.contains(c.owner) { c.claim = .sibling }
            if c.claim != .drop { kept.append(c) }
        }
        cands = kept
        let strongOwners = Set(cands.filter { $0.hit.strength >= .proven && $0.claim == .none && $0.never == nil }.map(\.owner))

        var itemsByOwner: [Int: [ResidueItem]] = [:]
        for c in cands {
            let owner = owners[c.owner]
            let item = makeItem(c, owner: owner.identity, strong: strongOwners.contains(c.owner), isOrphan: isOrphan,
                                orphanEvidence: ownerEvidence[c.owner])
            itemsByOwner[c.owner, default: []].append(item)
        }
        if input.kind == .app, let s = owners.first, let bundle = bundleItem(for: s.identity) {
            itemsByOwner[0, default: []].append(bundle)
        }

        var groups: [ResidueGroup] = []
        for (i, owner) in owners.enumerated() {
            guard let items = itemsByOwner[i], !items.isEmpty else { continue }
            let sorted = items.sorted(by: Self.order)
            let state = forMeasuring ? RunState.notRunning : runState(owner: owner.identity, items: sorted)
            groups.append(ResidueGroup(owner: owner.identity, isOrphan: isOrphan, runState: state, items: sorted))
        }
        return (groups, recentlyRemoved)
    }

    // MARK: candidates

    func candidates(_ ownerIndex: SubjectIndex) -> [Cand] {
        var out: [Cand] = []
        var seen = Set<String>()
        for listing in input.library.listings {
            let root = listing.root
            let rule = ResidueRules.rule(for: root)
            for entry in listing.entries where Names.isSafeEntryName(entry.name) && entry.type != .other {
                let path = GuardPolicy.normalize(root.path(home: home) + "/" + entry.name)
                let folded = Names.fold(entry.name)
                if rootPaths.contains(Names.fold(path)) { continue }
                let hits = ownerIndex.hits(for: entry, folded: folded, rule: rule)
                guard let hit = Self.pick(hits, in: ownerIndex), seen.insert(path).inserted else { continue }
                out.append(Cand(owner: hit.subject, entry: entry, root: root, rule: rule, path: path, hit: hit))
            }
        }
        return out
    }

    /// The strongest hit; a literal one wins a tie, then the longer (more specific) ID.
    static func pick(_ hits: [Hit], in index: SubjectIndex) -> Hit? {
        hits.max { a, b in
            if a.strength != b.strength { return a.strength < b.strength }
            if a.literal != b.literal { return !a.literal }
            return index.subjects[a.subject].id.count < index.subjects[b.subject].id.count
        }
    }

    /// Who else could legitimately use this entry? A different installed app that matches it exactly owns it (drop); a
    /// sibling (same ID, same release channel family) or a weaker match (team, helper, name) makes it shared.
    func claim(of c: Cand, owner: Subject) -> Claim {
        let liveHits = live.hits(for: c.entry, folded: Names.fold(c.entry.name), rule: c.rule)
        var result = Claim.none
        // The entry is named exactly like the app being removed: a live app that only matches it as a dotted child does not own it.
        let ownerNamedIt = c.hit.literal && c.hit.strength >= .exact
        for h in liveHits {
            let other = live.subjects[h.subject]
            if index.isSibling(other.identity, of: owner.identity) {
                result = max(result, .sibling)
            } else if !h.viaTeam, c.rule.key != .teamOrGroup,
                      (h.strength >= .proven && !(ownerNamedIt && !h.literal)) || (h.strength >= .structural && other.id.hasPrefix(owner.id + ".")) {
                // A different installed app owns it exactly, or is a more specific app whose ID starts with this one's.
                result = .drop
            } else {
                result = max(result, .shared)
            }
        }
        return result
    }

    // MARK: items

    func makeItem(_ c: Cand, owner: AppIdentity, strong: Bool, isOrphan: Bool, orphanEvidence: [Evidence]) -> ResidueItem {
        let entry = c.entry
        let measure = input.sizes[c.path]
        var size: UInt64 = 0
        var sizeState = SizeState.notMeasured
        var fileCount = 0
        // Every size is space on disk, so rows add up. An iCloud placeholder holds none of its logical size here: not measured.
        if entry.isDataless {
            // size stays 0, state notMeasured
        } else if let m = measure {
            size = m.bytes
            sizeState = m.state
            fileCount = m.fileCount
        } else if entry.type == .file, let st = entry.stamp {
            size = st.allocated ?? st.size
            sizeState = .measured
            fileCount = 1
        }
        let newest = [entry.stamp?.mtime, measure?.newestMtime].compactMap { $0 }.max()
        // A folder is only as old as the newest file in it, and a walk that was cut short did not see all of them.
        let seenAll = entry.type != .directory || measure?.state == .measured
        let stale = seenAll && (newest.map { input.now.timeIntervalSince($0) >= 30 * 86_400 } ?? false)

        var blocked: BlockReason? = c.never
        if blocked == nil, entry.isDataless { blocked = .dataless }
        // A live owner's claim comes before "needs admin" and "listed only": those would tell the user to remove a file an installed app still uses.
        if blocked == nil, c.claim == .sibling { blocked = .siblingInstalled }
        if blocked == nil, c.claim == .shared { blocked = .sharedWithInstalled }
        if blocked == nil, c.root.isSystem { blocked = .needsAdmin }
        if blocked == nil, c.rule.ceiling == .handsOff { blocked = .listedOnly }
        if blocked == nil, c.root.contentsMayBeProtected, measure == nil || measure?.state == .notMeasured { blocked = .protectedByMacOS }
        if blocked == nil, entry.stamp == nil, let e = entry.errno { blocked = (e == 1 || e == 13) ? .protectedByMacOS : .changed }

        var risk = c.rule.shareRisk
        if c.hit.strength >= .proven, risk == .high, c.root != .groupContainers { risk = .possible }
        if Hazards.isSharedVendorRoot(entry.name) || Hazards.isSharedUpdater(entry.name) { risk = .high }
        if c.claim != .none, risk == .none { risk = .possible }

        let irreplaceable = blocked == nil && Irreplaceable.looksIrreplaceable(path: entry.name, bytes: size)

        var tier: Tier
        if let b = blocked {
            tier = b == .needsAdmin ? .needsAdmin : .handsOff
        } else {
            var cap = c.hit.strength.cap
            // A name-only match with a proven sibling item for the same app may rise one step, never above Medium.
            if c.hit.strength == .name, strong { cap = .medium }
            tier = c.rule.ceiling.capped(at: cap)
            if risk == .high || irreplaceable || entry.type == .symlink { tier = tier.capped(at: .low) }
            if isOrphan {
                let cacheLike = c.rule.kind == .cache || c.rule.kind == .logs
                let sameTeam = orphanEvidence.contains { $0.kind == .sameTeamInstalled }
                let mayStayHigh = cacheLike && c.hit.strength == .exact && c.hit.literal && stale && !ownerMayBeElsewhere && !sameTeam
                if !mayStayHigh { tier = tier.capped(at: .medium) }
                if ownerMayBeElsewhere { tier = tier.capped(at: .low) }
            }
        }

        var evidence = c.hit.evidence
        if isOrphan {
            evidence += orphanEvidence
            if stale, let newest { evidence.append(Evidence(.staleMtime, Format.count(Int(input.now.timeIntervalSince(newest) / 86_400), "day"))) }
        }
        var item = ResidueItem(path: c.path, ownerID: owner.bundleID, ruleID: c.rule.id, root: c.root, kind: c.rule.kind,
                               fileType: entry.type, tier: tier, evidence: evidence, size: size, sizeState: sizeState,
                               fileCount: fileCount, mtime: entry.stamp?.mtime, stamp: entry.stamp, sharedRisk: risk,
                               requiresAdmin: c.root.isSystem, irreplaceable: irreplaceable, blocked: blocked)
        item.why = WhyText.line(for: item, owner: owner)
        if isOrphan, ownerMayBeElsewhere, blocked == nil { item.why += " " + WhyText.reason(.ownerMayBeElsewhere) }
        return item
    }

    /// Uninstall-now: the dropped bundle itself, present while the app is still installed (or at least measurable).
    func bundleItem(for target: AppIdentity) -> ResidueItem? {
        let path = GuardPolicy.normalize(target.bundlePath)
        guard !path.isEmpty else { return nil }
        let folded = Names.fold(path)
        let installed = input.installed.apps.contains { Names.fold(GuardPolicy.normalize($0.bundlePath)) == folded }
        let measure = input.sizes[path]
        guard installed || measure != nil else { return nil }
        var blocked: BlockReason? = NeverList.reason(forPath: path, home: home, keep: input.prefs.keepList)
        if blocked == nil, NeverList.keeps(bundleID: target.bundleID, keep: input.prefs.keepList) { blocked = .neverList }
        if blocked == nil, target.bundleNeedsAdmin { blocked = .needsAdmin }
        // The Guard moves an app only out of an Applications folder; offering a bundle from Downloads would abort the whole run.
        let parent = "/" + path.split(separator: "/").dropLast().joined(separator: "/")
        let outsideAppFolder = blocked == nil && !GuardPolicy.isInAppFolder(parent, home: home)
        if outsideAppFolder { blocked = .neverList }
        let tier: Tier = blocked == nil ? .high : (blocked == .needsAdmin ? .needsAdmin : .handsOff)
        var item = ResidueItem(path: path, ownerID: target.bundleID, ruleID: "APP", root: nil, kind: .app, fileType: .directory, tier: tier,
                               size: measure?.bytes ?? 0, sizeState: measure?.state ?? .notMeasured, fileCount: measure?.fileCount ?? 0,
                               requiresAdmin: target.bundleNeedsAdmin, blocked: blocked)
        item.why = WhyText.line(for: item, owner: target)
        if outsideAppFolder { item.why = "The app you chose. It is not in an Applications folder, so Aftertaste does not move it. Move it to Applications first." }
        return item
    }

    func runState(owner: AppIdentity, items: [ResidueItem]) -> RunState {
        var state = RunningCheck.state(owner: owner, itemPath: "", snapshot: input.running)
        if state == .running || state == .unknown { return state }
        for item in items {
            state = RunningCheck.worst(state, RunningCheck.state(owner: nil, itemPath: item.path, snapshot: input.running))
            if state == .running { break }
        }
        return state
    }

    /// The app bundle first, then tier (High first), then size (largest first), then name.
    static func order(_ a: ResidueItem, _ b: ResidueItem) -> Bool {
        let aApp = a.ruleID == "APP", bApp = b.ruleID == "APP"
        if aApp != bApp { return aApp }
        if a.tier != b.tier { return rank(a.tier) < rank(b.tier) }
        if a.size != b.size { return a.size > b.size }
        let an = Names.fold(a.name), bn = Names.fold(b.name)
        return an != bn ? an < bn : a.path < b.path
    }

    static func rank(_ t: Tier) -> Int {
        switch t {
        case .high: return 0
        case .medium: return 1
        case .low: return 2
        case .handsOff: return 3
        case .needsAdmin: return 4
        }
    }
}
