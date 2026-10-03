import Foundation
import XCTest
@testable import AftertasteCore

/// Deterministic pseudo-random libraries (SplitMix64). The invariants are the safety rules: whatever the library looks like,
/// nothing that an installed app could use is ever selectable, and nothing above a rule's ceiling is ever produced.
struct SplitMix64 {
    var state: UInt64
    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
    mutating func int(_ n: Int) -> Int { Int(next() % UInt64(n)) }
    mutating func chance(_ percent: Int) -> Bool { int(100) < percent }
    mutating func pick<T>(_ a: [T]) -> T { a[int(a.count)] }
}

final class PropertyTests: XCTestCase {
    let teams = ["TEAMAAAAAA", "TEAMBBBBBB", "TEAMCCCCCC"]
    let userRoots: [LibraryRoot] = [.preferences, .caches, .applicationSupport, .containers, .groupContainers, .logs, .savedState, .httpStorages, .webKit, .cookies,
                                    .applicationScripts, .syncedPreferences, .launchAgents]

    func makeApps(_ rng: inout SplitMix64) -> [AppIdentity] {
        let names = ["Alpha One", "Beta Two", "Gamma Three", "Delta Four", "Epsilon Five", "Zeta Six", "Notes", "Music Box"]
        return names.enumerated().map { i, n in
            let id = "com.example.app\(i)"
            let team = rng.chance(60) ? rng.pick(teams) : nil
            return T.app(id, n, exec: n.replacingOccurrences(of: " ", with: ""), team: team, path: "/Applications/\(n).app",
                         embedded: rng.chance(30) ? ["\(id).helper"] : [], groups: rng.chance(40) ? ["group.\(id)"] : [])
        }
    }

    func names(for a: AppIdentity, _ rng: inout SplitMix64) -> [(LibraryRoot, String)] {
        let id = a.bundleID
        var out: [(LibraryRoot, String)] = [
            (.preferences, "\(id).plist"), (.caches, id), (.caches, "\(id).ShipIt"), (.caches, "\(id).helper"), (.savedState, "\(id).savedState"), (.httpStorages, id),
            (.webKit, id), (.cookies, "\(id).binarycookies"), (.logs, id), (.logs, a.displayName), (.applicationSupport, id), (.applicationSupport, a.displayName),
            (.applicationScripts, id), (.syncedPreferences, "\(id).plist"), (.containers, id), (.groupContainers, "group.\(id)"),
            (.diagnosticReports, "\(a.execName)_2026-09-01_jane.ips"), (.launchAgents, "\(id).agent.plist"), (.systemCaches, id), (.receipts, "\(id).pkg.bom"),
        ]
        if let t = a.teamID { out += [(.groupContainers, "\(t).shared"), (.groupContainers, "\(t).\(id)")] }
        out += [(.caches, id.uppercased()), (.applicationSupport, a.displayName.lowercased())]
        return out.filter { _ in rng.chance(55) }
    }

    func build(seed: UInt64) -> (lib: Lib, kind: ScanKind, target: AppIdentity?) {
        var rng = SplitMix64(state: seed)
        var lib = Lib()
        let apps = makeApps(&rng)
        let installed = apps.filter { _ in rng.chance(60) }
        lib.apps = installed
        let kind: ScanKind = rng.chance(50) ? .app : .orphans
        var target: AppIdentity?
        if kind == .app {
            target = rng.pick(apps)
            if !lib.apps.contains(where: { $0.bundleID == target?.bundleID }), rng.chance(50), let t = target { lib.apps.append(t) }
        }
        for a in apps where rng.chance(75) {
            for (root, name) in names(for: a, &rng) {
                var type = FileType.directory
                if name.hasSuffix(".plist") || name.hasSuffix(".ips") || name.hasSuffix(".bom") || name.hasSuffix(".binarycookies") { type = .file }
                if rng.chance(5) { type = .symlink }
                if root == .launchAgents || root == .systemLaunchAgents {
                    lib.addAgent(root, name: name, label: String(name.dropLast(6)), program: rng.chance(50) ? a.bundlePath + "/Contents/MacOS/x" : "/usr/bin/true", exists: rng.chance(50))
                } else {
                    lib.addEntry(root, name, type: type, daysOld: Double(rng.int(300)), container: nil, dataless: rng.chance(3))
                }
            }
        }
        let noise: [(LibraryRoot, String)] = [
            (.caches, "com.apple.Safari"), (.preferences, "com.apple.finder.plist"), (.applicationSupport, "Adobe"), (.applicationSupport, "Google"), (.caches, "Mozilla"),
            (.caches, "com.google.Keystone"), (.applicationSupport, "Notes"), (.applicationSupport, "Music"), (.groupContainers, "group.com.apple.notes"),
            (.groupContainers, "UBF8T346G9.Office"), (.caches, "org.sparkle-project.Sparkle"), (.applicationSupport, "Mobile Documents"), (.caches, "io.github.everydayopen.aftertaste"),
            (.applicationSupport, "Aftertaste"), (.caches, "com.example.stranger"), (.preferences, "com.example.stranger.plist"), (.caches, "com.example.*"),
        ]
        for (root, name) in noise where rng.chance(50) { lib.addEntry(root, name, type: name.hasSuffix(".plist") ? .file : .directory, daysOld: Double(rng.int(300))) }
        // Containers and group containers are only measured (readable) sometimes.
        for root in [LibraryRoot.containers, .groupContainers] {
            for e in lib.entries[root] ?? [] where rng.chance(50) { lib.sizes[lib.path(root, e.name)] = T.sized(UInt64(rng.int(1_000_000) + 1)) }
        }
        lib.volumeMayBeMissing = rng.chance(15)
        if rng.chance(10) { lib.running = RunningSnapshot(readable: false) }
        for root in userRoots where rng.chance(4) { lib.coverageOverride[root] = .protectedByMacOS }
        return (lib, kind, target)
    }

    func stem(_ name: String) -> String {
        var f = Names.fold(name)
        for ext in [".plist", ".savedstate", ".binarycookies", ".sfl2", ".sfl3", ".bom", ".ips"] where f.hasSuffix(ext) { f = String(f.dropLast(ext.count)) }
        return f
    }

    func testInvariantsHoldForRandomLibraries() {
        for seed in 0..<100 {
            let (lib, kind, target) = build(seed: UInt64(seed) &* 7919 &+ 13)
            let input = lib.input(kind, target: target)
            let result = Scan.analyze(input)
            let ctx = "seed \(seed) \(kind)"
            XCTAssertEqual(result, Scan.analyze(input), "\(ctx): deterministic")
            let ids = result.items.map(\.id)
            XCTAssertEqual(Set(ids).count, ids.count, "\(ctx): unique ids")
            let pre = ItemSelection.preselected(result)
            let liveApps = lib.apps.filter { $0.bundlePath != target?.bundlePath }

            for group in result.groups {
                if kind == .orphans {
                    XCTAssertFalse(liveApps.contains { Names.fold($0.bundleID) == Names.fold(group.owner.bundleID) }, "\(ctx): an installed app is not an orphan")
                    XCTAssertTrue(group.isOrphan)
                }
                for item in group.items {
                    let p = "\(ctx) \(item.path)"
                    if item.ruleID != "APP" {
                        let root = item.root!
                        XCTAssertEqual(item.path, GuardPolicy.normalize(root.path(home: T.home) + "/" + item.name), p)
                        let rule = ResidueRules.rule(for: root)
                        XCTAssertEqual(item.tier.capped(at: rule.ceiling), item.tier, "\(p): above the ceiling of \(rule.id)")
                        XCTAssertEqual(item.ruleID, rule.id, p)
                    }
                    // Selectable means: no block, no admin, not a launch item, not a system row.
                    if item.tier.isSelectable {
                        XCTAssertNil(item.blocked, p)
                        XCTAssertFalse(item.requiresAdmin, p)
                        XCTAssertFalse(item.kind == .launchItem || item.kind == .system, p)
                        if item.tier != .low { XCTAssertNotEqual(item.sharedRisk, .high, "\(p): high share risk is Review at most") }
                    } else {
                        XCTAssertFalse(pre.contains(item.id), p)
                    }
                    XCTAssertEqual(pre.contains(item.id), item.tier == .high, p)
                    if item.tier == .needsAdmin { XCTAssertTrue(item.requiresAdmin, p) }
                    if item.requiresAdmin { XCTAssertTrue(item.tier == .needsAdmin || item.tier == .handsOff, p) }
                    if item.irreplaceable || item.fileType == .symlink { XCTAssertTrue(item.tier == .low || !item.tier.isSelectable, p) }

                    // The never-list always wins.
                    if NeverList.reason(forPath: item.path, home: T.home, keep: []) != nil { XCTAssertFalse(item.tier.isSelectable, "\(p): never-list") }
                    let s = stem(item.name)
                    if s.hasPrefix("com.apple.") || s.hasPrefix("io.github.everydayopen.aftertaste") { XCTAssertFalse(item.tier.isSelectable, p) }
                    if Hazards.isSharedVendorRoot(item.name) || Hazards.isSharedUpdater(item.name) { XCTAssertTrue(item.tier == .low || !item.tier.isSelectable, "\(p): shared name") }
                    if item.tier == .high { XCTAssertNotEqual(item.sharedRisk, .high, p) }

                    // Nothing an installed app owns is selectable.
                    if item.tier.isSelectable && item.ruleID != "APP" {
                        for live in liveApps {
                            for id in live.allIDs.map(Names.fold) {
                                XCTAssertFalse(s == id || s.hasPrefix(id + "."), "\(p): belongs to installed \(live.bundleID)")
                            }
                            if item.root == .groupContainers, let t = live.teamID { XCTAssertFalse(Names.fold(item.name).hasPrefix(Names.fold(t) + "."), "\(p): team of \(live.bundleID)") }
                        }
                    }
                    // Orphan caps.
                    if group.isOrphan, item.tier == .high {
                        XCTAssertTrue(item.kind == .cache || item.kind == .logs, p)
                        XCTAssertFalse(input.installed.volumeMayBeMissing, p)
                        XCTAssertTrue(item.evidence.contains { $0.kind == .staleMtime } && item.evidence.contains { $0.kind == .noLiveOwner }, p)
                    }
                    if group.isOrphan, input.installed.volumeMayBeMissing { XCTAssertTrue(item.tier == .low || !item.tier.isSelectable, p) }
                }
            }

            // Ticking everything and acknowledging everything still plans only safe things.
            let plan = TrashPlanner.plan(from: result, ticked: Set(ids), mode: .bulk(acknowledgedMedium: true), now: T.now, runID: "r")
            for item in plan.items {
                XCTAssertTrue(item.tier == .high || item.tier == .medium, "\(ctx) \(item.path)")
                XCTAssertNil(item.blocked)
                let group = result.groups.first { $0.owner.bundleID == item.ownerID }
                XCTAssertEqual(group?.runState, .notRunning, ctx)
            }
            if kind == .app, plan.items.contains(where: { $0.ruleID != "APP" }), result.items.contains(where: { $0.ruleID == "APP" }) {
                XCTAssertEqual(plan.items.first?.ruleID, "APP", "\(ctx): the app goes first")
            }
            // Measuring never asks for more than the scan found.
            let found = Set(ids)
            for path in Scan.candidatePaths(input) { XCTAssertTrue(found.contains(path), "\(ctx) \(path)") }
        }
    }
}
