import Foundation

/// Synthetic worlds for demo mode (BUILD_PLAN §9). Pure and deterministic: one scenario and one `now` always give the same
/// library, so screenshots do not drift. Home is the example user jane and every app is fictional (`com.example.*`).
/// This file only describes a Mac as plain data (names, sizes, ages). It never decides what an item is: `DemoBackend` feeds
/// the data to the real `Scan.analyze`, so the demo exercises the real tiering, caps and guards.
public enum DemoScenarios {
    public static let home = "/Users/jane"
    public static let osVersion = "26.1"
    /// The installed app a sample "uninstall now" can be started with (`Backend.identify` accepts it).
    public static let uninstallTarget = "/Applications/Paperplane Notes.app"
    /// The Trash entries of the seeded history live under here.
    public static let trashFolder = home + "/.Trash"
    static let device: Int64 = 16_777_234
    static let day: Int64 = 86_400

    /// The Erase readiness facts a scenario shows. Only `snapshots` differs from the calm default.
    public static func readiness(for scenario: DemoScenario, now: Date) -> ReadinessFacts {
        scenario == .snapshots ? readinessVariants(now: now)[1].facts : readinessVariants(now: now)[0].facts
    }

    /// Five readiness situations, for the panel, the edge screen and the `ReadinessText` tests.
    public static func readinessVariants(now: Date) -> [(name: String, facts: ReadinessFacts)] {
        func facts(_ vault: FileVaultState, _ storage: StorageKind, _ fs: String?, silicon: Bool?, snapshots: Int?,
                   failed: [String] = [], internalDisk: Bool = true) -> ReadinessFacts {
            ReadinessFacts(fileVault: vault, storage: storage, fileSystem: fs, isInternal: failed.isEmpty ? internalDisk : nil,
                           isAppleSilicon: silicon, localSnapshotCount: snapshots, macOSVersion: osVersion, failedProbes: failed,
                           checkedAt: now)
        }
        return [
            ("filevault-on-flash", facts(.on, .solidState, "APFS", silicon: true, snapshots: 0)),
            ("filevault-off-snapshots", facts(.off, .solidState, "APFS", silicon: true, snapshots: 3)),
            ("spinning-disk", facts(.on, .rotational, "HFS+", silicon: false, snapshots: 0)),
            ("unreadable", facts(.unknown, .unknown, nil, silicon: nil, snapshots: nil, failed: ["fdesetup", "diskutil", "tmutil"])),
            ("external-boot-disk", facts(.off, .solidState, "APFS", silicon: true, snapshots: 0, internalDisk: false)),
        ]
    }

    // MARK: - The journal behind History

    /// Two earlier runs of apps that are not in the library any more: Cobalt Chat nine days ago (its Trash entries are
    /// emptied, so History says "Already emptied") and Pixel Pad two days ago (still in the Trash, so Undo is offered).
    /// `inTrash` is the absolute Trash path of every item that is still there. Empty where nothing has ever run.
    static func past(for scenario: DemoScenario, now: Date) -> (entries: [ActivityEntry], inTrash: Set<String>) {
        if scenario == .quiet || scenario == .firstRun { return ([], []) }
        typealias Row = (path: String, rule: String, kind: ResidueKind, bytes: UInt64, type: FileType, why: String)
        typealias Run = (days: Int, random: UInt32, label: String, id: String, inTrash: Bool, rows: [Row])
        func why(_ id: String) -> String { "Named exactly \(id); no installed app has this ID." }
        let runs: [Run] = [
            (9, 0xc0ba17, "Cobalt Chat", "com.example.cobalt", false, [
                ("~/Library/Caches/com.example.cobalt", "U3", .cache, 84_000_000, .directory, why("com.example.cobalt")),
                ("~/Library/Preferences/com.example.cobalt.plist", "U1", .settings, 4_096, .file, why("com.example.cobalt.plist")),
                ("~/Library/Saved Application State/com.example.cobalt.savedState", "U7", .state, 1_200_000, .directory,
                 why("com.example.cobalt.savedState"))]),
            (2, 0x91ad3e, "Pixel Pad", "com.example.pixelpad", true, [
                ("~/Library/Caches/com.example.pixelpad", "U3", .cache, 51_000_000, .directory, why("com.example.pixelpad")),
                ("~/Library/Logs/com.example.pixelpad", "U11", .logs, 2_000_000, .directory, why("com.example.pixelpad")),
                ("~/Library/HTTPStorages/com.example.pixelpad", "U8", .cookies, 640_000, .directory, why("com.example.pixelpad"))]),
        ]
        var entries: [ActivityEntry] = []
        var kept: Set<String> = []
        var inode: UInt64 = 7_000_000
        for run in runs {
            let begin = now.addingTimeInterval(-Double(Int64(run.days) * day))
            let runID = TrashPlanner.newRunID(now: begin, random: run.random)
            entries.append(ActivityEntry(timestamp: begin, runID: runID, verb: .run, phase: .intent))
            for (i, row) in run.rows.enumerated() {
                inode += 1
                let at = begin.addingTimeInterval(Double(i + 1) * 2)
                let name = String(row.path.split(separator: "/").last ?? "")
                let stamp = FileStamp(device: device, inode: inode, type: row.type, size: row.type == .file ? row.bytes : 0,
                                      mtimeSeconds: Int64(begin.timeIntervalSince1970) - 40 * day, linkCount: row.type == .file ? 1 : 2)
                let trashed = "~/.Trash/" + name
                let common = { (phase: ActivityPhase, status: TrashStatus?, trashedPath: String?, when: Date) in
                    ActivityEntry(timestamp: when, runID: runID, verb: .trash, phase: phase, path: row.path, label: run.label,
                                  ownerID: run.id, ruleID: row.rule, tier: .high, kind: row.kind, bytes: row.bytes, status: status,
                                  trashedPath: trashedPath, stamp: stamp, why: row.why)
                }
                entries.append(common(.intent, nil, nil, at))
                entries.append(common(.result, .moved, trashed, at.addingTimeInterval(1)))
                if run.inTrash { kept.insert(trashFolder + "/" + name) }
            }
            entries.append(ActivityEntry(timestamp: begin.addingTimeInterval(Double(run.rows.count + 1) * 2 + 1), runID: runID,
                                         verb: .run, phase: .result))
        }
        return (entries, kept)
    }

    public static func history(for scenario: DemoScenario, now: Date) -> [ActivityEntry] { past(for: scenario, now: now).entries }

    // MARK: - The worlds

    /// What `DemoState` starts from. Plain data; `library` and `sizes` turn it into scanner input.
    struct World {
        var installed: [AppIdentity]
        var inventory: [InventoryRecord]
        var seeds: [Seed]
        var protectedRoots: Set<LibraryRoot> = []
        var running: RunningSnapshot
        var readiness: ReadinessFacts
        var log: [ActivityEntry]
        var inTrash: Set<String>
        /// Paths macOS refuses to move (EPERM) when a run reaches them.
        var refuses: Set<String> = []
        /// Paths some app writes to after the scan, so the real `Stamps.same` says "changed".
        var drifts: Set<String> = []

        var paths: Set<String> { Set(seeds.map(\.path)).union(installed.map(\.bundlePath)) }

        /// Each seed's stamp: inode by position, modification time `age` days back. Protected entries have none.
        func stamps(now: Date) -> [String: FileStamp] {
            var out: [String: FileStamp] = [:]
            let t = Int64(now.timeIntervalSince1970)
            let device = DemoScenarios.device, day = DemoScenarios.day
            for (i, s) in seeds.enumerated() where s.errno == nil {
                out[s.path] = FileStamp(device: device, inode: 5_000_000 + UInt64(i), type: s.type, size: s.type == .file ? s.bytes : 0,
                                        mtimeSeconds: t - Int64(s.age) * day - Int64(i) * 97, linkCount: s.type == .file ? 1 : 2)
            }
            for (i, a) in installed.enumerated() {
                out[a.bundlePath] = FileStamp(device: device, inode: 9_000_000 + UInt64(i), type: .directory, size: 0,
                                              mtimeSeconds: t - 200 * day, linkCount: 2)
            }
            return out
        }

        /// Measured sizes of what exists (bundles included). Unmeasured and protected seeds have none.
        func sizes(present: Set<String>, stamps: [String: FileStamp]) -> [String: SizeMeasure] {
            var out: [String: SizeMeasure] = [:]
            for s in seeds where s.measured && s.errno == nil && present.contains(s.path) {
                out[s.path] = SizeMeasure(bytes: s.bytes, fileCount: s.files, newestMtime: stamps[s.path]?.mtime)
            }
            for a in installed where present.contains(a.bundlePath) {
                let big = a.bundlePath == DemoScenarios.uninstallTarget
                out[a.bundlePath] = SizeMeasure(bytes: big ? 96_000_000 : 48_000_000, fileCount: big ? 412 : 160)
            }
            return out
        }

        /// All 26 roots, each listed once (BUILD_PLAN §4.3), with whatever of the seeds still exists.
        func library(present: Set<String>, stamps: [String: FileStamp], now: Date) -> LibrarySnapshot {
            let listings = LibraryRoot.allCases.map { root -> RootListing in
                let entries = seeds.filter { $0.root == root && present.contains($0.path) }.map {
                    LibraryEntry(name: $0.name, type: $0.type, stamp: stamps[$0.path], errno: $0.errno, containerID: $0.containerID,
                                 launchd: $0.launchd)
                }
                let blocked = protectedRoots.contains(root)
                let state: PlaceState = blocked ? .protectedByMacOS : (entries.isEmpty ? .absent : .read)
                return RootListing(coverage: PlaceCoverage(root: root, state: state, errno: blocked ? 1 : nil, entryCount: entries.count),
                                   entries: entries)
            }
            return LibrarySnapshot(home: DemoScenarios.home, listings: listings, takenAt: now)
        }
    }

    /// One thing on disk. Chainable modifiers keep the tables below to one line per item.
    struct Seed {
        var root: LibraryRoot
        var name: String
        var type: FileType
        var bytes: UInt64
        var files: Int
        var age: Int
        var measured = true
        var errno: Int32?
        var containerID: String?
        var launchd: LaunchdInfo?

        static func dir(_ root: LibraryRoot, _ name: String, _ bytes: UInt64, _ files: Int, _ age: Int = 90) -> Seed {
            Seed(root: root, name: name, type: .directory, bytes: bytes, files: files, age: age)
        }

        static func file(_ root: LibraryRoot, _ name: String, _ bytes: UInt64, _ age: Int = 90) -> Seed {
            Seed(root: root, name: name, type: .file, bytes: bytes, files: 1, age: age)
        }

        var path: String { root.path(home: DemoScenarios.home) + "/" + name }
        func container(_ id: String) -> Seed { var s = self; s.containerID = id; return s }
        /// A system row: Aftertaste does not measure what only an administrator can change.
        func unmeasured() -> Seed { var s = self; s.measured = false; return s }
        /// macOS refused to look at it (`EPERM`): listed by name, no stamp, no size.
        func protectedByMacOS() -> Seed { var s = self; s.errno = 1; s.measured = false; s.containerID = nil; return s }
        func job(_ label: String, program: String, exists: Bool = false) -> Seed {
            var s = self
            s.launchd = LaunchdInfo(label: label, program: program, programExists: exists)
            return s
        }
    }

    // MARK: - The cast

    private static func app(_ id: String, _ name: String, _ exec: String, team: String, version: String, groups: [String] = [],
                            helpers: [String] = [], owner: UInt32 = 501, at: Date) -> AppIdentity {
        AppIdentity(bundleID: id, displayName: name, execName: exec, version: version, teamID: team, groupIDs: groups,
                    helperLabels: helpers, bundlePath: "/Applications/\(name).app", installSource: .manual, bundleOwnerUID: owner,
                    capturedAt: at)
    }

    private static func ago(_ now: Date, _ days: Int) -> Date { now.addingTimeInterval(-Double(Int64(days) * day)) }

    private static func record(_ a: AppIdentity, now: Date, lastSeenDaysAgo days: Int) -> InventoryRecord {
        InventoryRecord(identity: a, firstSeen: ago(now, days + 300), lastSeen: ago(now, days))
    }

    /// Apps that are installed in every scenario, and the folders they legitimately own (never reported as leftovers).
    private static func live(now: Date) -> (apps: [AppIdentity], seeds: [Seed]) {
        let apps = [
            app("com.example.paperplane", "Paperplane Notes", "PaperplaneNotes", team: "P9Q8R7S6T5", version: "3.4.1", at: now),
            app("com.example.glowcamera", "Glow Camera", "GlowCamera", team: "H7J6K5L4M3", version: "2.0", at: now),
            app("com.example.tern", "Tern Browser", "Tern", team: "T1E2R3N4B5", version: "9.1", at: now),
            app("com.example.mosaic", "Mosaic Sheets", "MosaicSheets", team: "M0S1A2I3C4", version: "5.0", at: now),
            app("com.example.ferry", "Ferry Transfer", "FerryTransfer", team: "F5E6R7R8Y9", version: "1.3", at: now),
        ]
        let seeds: [Seed] = [
            .file(.preferences, "com.example.paperplane.plist", 9_216, 1),
            .dir(.caches, "com.example.paperplane", 38_400_000, 21, 1),
            .dir(.savedState, "com.example.paperplane.savedState", 640_000, 3, 2),
            .dir(.containers, "com.example.paperplane", 214_000_000, 118, 1).container("com.example.paperplane"),
            .file(.preferences, "com.example.glowcamera.plist", 8_192, 3),
            .dir(.caches, "com.example.glowcamera", 22_000_000, 40, 3),
            .file(.preferences, "com.example.tern.plist", 14_336, 1),
            .dir(.caches, "com.example.tern", 310_000_000, 502, 1),
            .file(.preferences, "com.example.mosaic.plist", 6_144, 6),
        ]
        return (apps, seeds)
    }

    // Removed apps. Each returns its identity (as the inventory remembers it), how long ago it was last seen, and what it left.
    private typealias Gone = (app: AppIdentity, lastSeen: Int, seeds: [Seed])

    /// 214 files, 1.3 GB (decimal), two user launch agents and one privileged helper (the card's "2 launch agents, 1 privileged
    /// helper": the report counts every launch item, so Orbit Meet has no launch daemon of its own; Harbor VPN does).
    private static func orbit(_ now: Date) -> Gone {
        let id = "com.example.orbitmeet"
        let a = app(id, "Orbit Meet", "OrbitMeet", team: "A1B2C3D4E5", version: "6.2",
                    helpers: [id + ".agent", id + ".updater", id + ".helper"], at: ago(now, 62))
        let bundle = "/Applications/Orbit Meet.app/Contents"
        return (a, 62, [
            .file(.preferences, id + ".plist", 18_432, 62),
            .dir(.caches, id, 412_300_000, 96, 62),
            .dir(.savedState, id + ".savedState", 3_870_000, 5, 62),
            .dir(.webKit, id, 61_450_000, 33, 62),
            .dir(.httpStorages, id, 1_620_000, 4, 62),
            .dir(.logs, id, 22_410_000, 17, 62),
            .dir(.applicationSupport, id, 796_000_000, 55, 70),
            .file(.launchAgents, id + ".agent.plist", 612, 62).job(id + ".agent", program: bundle + "/Library/LoginItems/OrbitAgent.app/Contents/MacOS/OrbitAgent"),
            .file(.launchAgents, id + ".updater.plist", 584, 62).job(id + ".updater", program: bundle + "/MacOS/OrbitUpdater"),
            .file(.systemPrivilegedHelperTools, id + ".helper", 1_240_000, 62).unmeasured(),
        ])
    }

    private static func lumen(_ now: Date) -> Gone {
        let id = "com.example.lumenplayer"
        return (app(id, "Lumen Player", "LumenPlayer", team: "L2M3N4P5Q6", version: "2.8", at: ago(now, 80)), 80, [
            .file(.preferences, id + ".plist", 6_144, 80),
            .dir(.caches, id, 156_000_000, 64, 80),
            .dir(.logs, id, 1_100_000, 6, 80),
            .dir(.savedState, id + ".savedState", 880_000, 3, 80),
            .dir(.applicationSupport, id, 88_000_000, 31, 90),
            .dir(.containers, id, 52_000_000, 77, 80).container(id),
        ])
    }

    private static func harbor(_ now: Date) -> Gone {
        let id = "com.example.harborvpn"
        return (app(id, "Harbor VPN", "HarborVPN", team: "H4R5B6V7P8", version: "4.1", helpers: [id + ".helper"], at: ago(now, 100)), 100, [
            .file(.preferences, id + ".plist", 5_120, 100),
            .dir(.caches, id, 12_000_000, 9, 100),
            .file(.systemLaunchDaemons, id + ".helper.plist", 538, 100).job(id + ".helper", program: "/Library/PrivilegedHelperTools/" + id + ".helper", exists: true).unmeasured(),
            .file(.systemPrivilegedHelperTools, id + ".helper", 1_480_000, 100).unmeasured(),
        ])
    }

    private static func quill(_ now: Date) -> Gone {
        let id = "com.example.quilleditor"
        return (app(id, "Quill Editor", "QuillEditor", team: "Q7E8D9I0T1", version: "1.9", at: ago(now, 120)), 120, [
            .file(.preferences, id + ".plist", 3_072, 120),
            .dir(.caches, id, 2_400_000, 12, 120),
            // Named after the app, not its ID: the only match is the name, so it is shown for review and never preselected.
            .dir(.applicationSupport, "Quill Editor", 54_000_000, 140, 120),
        ])
    }

    private static func glowPhotos(_ now: Date) -> Gone {
        let id = "com.example.glowphotos"
        return (app(id, "Glow Photos", "GlowPhotos", team: "H7J6K5L4M3", version: "3.2", at: ago(now, 75)), 75, [
            .file(.preferences, id + ".plist", 7_168, 75),
            .dir(.caches, id, 31_000_000, 58, 75),
            // The installed Glow Camera has the same Team ID: this folder may be its, so it is listed and left alone, and this app's
            // cache is capped at Medium (an orphan whose developer still has an app installed is never preselected).
            .dir(.groupContainers, "H7J6K5L4M3.glow", 18_000_000, 22, 75),
        ])
    }

    private static func parcel(_ now: Date) -> Gone {
        let id = "com.example.parcel.word"
        return (app(id, "Parcel Word", "ParcelWord", team: "Z9Y8X7W6V5", version: "16.4", groups: ["Z9Y8X7W6V5.parcel"], at: ago(now, 140)), 140, [
            .file(.preferences, id + ".plist", 11_264, 140),
            // Office-style: one group container for the whole suite, so shared by design.
            .dir(.groupContainers, "Z9Y8X7W6V5.parcel", 96_000_000, 310, 140),
        ])
    }

    /// Only Medium and Review can come out of these: settings and folders in an orphan scan, a cache touched four days ago,
    /// a name-only folder and a suite-wide group container.
    private static func maybeOnly(_ now: Date) -> [Gone] {
        let kite = "com.example.kitedraw", rivet = "com.example.rivetnotes"
        return [
            (app(kite, "Kite Draw", "KiteDraw", team: "K1T2E3D4R5", version: "7.0", at: ago(now, 90)), 90, [
                .file(.preferences, kite + ".plist", 4_608, 90),
                .dir(.applicationSupport, kite, 41_000_000, 87, 90),
            ]),
            (app(rivet, "Rivet Notes", "RivetNotes", team: "R6V7T8N9O0", version: "2.2", at: ago(now, 95)), 95, [
                .dir(.caches, rivet, 9_000_000, 14, 4),
                .dir(.applicationSupport, "Rivet Notes", 22_000_000, 40, 4),
            ]),
            parcel(now),
        ]
    }

    /// Installed, with a bundle only an administrator can move (owned by root, like many App Store apps), and nothing but
    /// all-users files left around it: uninstall-now shows Needs admin rows and nothing else.
    private static func atlas(_ now: Date) -> (app: AppIdentity, seeds: [Seed]) {
        let id = "com.example.atlasdisk", tools = "/Library/PrivilegedHelperTools/"
        return (app(id, "Atlas Disk Tools", "AtlasDisk", team: "A7L8A9S0D1", version: "8.0", helpers: [id + ".helper"], owner: 0, at: now), [
            .file(.systemLaunchDaemons, id + ".helper.plist", 548, 30).job(id + ".helper", program: tools + id + ".helper", exists: true).unmeasured(),
            .file(.systemPrivilegedHelperTools, id + ".helper", 1_320_000, 30).unmeasured(),
            .file(.receipts, id + ".pkg.bom", 14_336, 30).unmeasured(),
            .file(.receipts, id + ".pkg.plist", 1_024, 30).unmeasured(),
            .dir(.systemApplicationSupport, id, 15_000_000, 22, 30).unmeasured(),
        ])
    }

    /// Removed apps with all-users leftovers. Aftertaste only finds an app through its own folders (a system folder alone
    /// never starts a search), so each keeps one settings file: a Medium row beside the Needs admin rows.
    private static func adminOnly(_ now: Date) -> [Gone] {
        let vpn = "com.example.harborvpn", sync = "com.example.pylonsync"
        return [
            (app(vpn, "Harbor VPN", "HarborVPN", team: "H4R5B6V7P8", version: "4.1", helpers: [vpn + ".helper"], at: ago(now, 100)), 100, [
                .file(.preferences, vpn + ".plist", 5_120, 100),
                .file(.systemLaunchDaemons, vpn + ".helper.plist", 538, 100).job(vpn + ".helper", program: "/Library/PrivilegedHelperTools/" + vpn + ".helper", exists: true).unmeasured(),
                .file(.systemPrivilegedHelperTools, vpn + ".helper", 1_480_000, 100).unmeasured(),
                .file(.receipts, vpn + ".pkg.bom", 18_432, 100).unmeasured(),
                .file(.receipts, vpn + ".pkg.plist", 1_024, 100).unmeasured(),
                .dir(.systemApplicationSupport, vpn, 8_200_000, 14, 100).unmeasured(),
            ]),
            (app(sync, "Pylon Sync", "PylonSync", team: "P3Y4L5O6N7", version: "3.0", helpers: [sync + ".helper", sync + ".agent"], at: ago(now, 110)), 110, [
                .file(.preferences, sync + ".plist", 4_096, 110),
                .file(.systemLaunchDaemons, sync + ".helper.plist", 561, 110).job(sync + ".helper", program: "/Library/PrivilegedHelperTools/" + sync + ".helper", exists: true).unmeasured(),
                .file(.systemPrivilegedHelperTools, sync + ".helper", 960_000, 110).unmeasured(),
                .file(.systemLaunchAgents, sync + ".agent.plist", 498, 110).job(sync + ".agent", program: "/Applications/Pylon Sync.app/Contents/MacOS/PylonSync").unmeasured(),
                .dir(.systemCaches, sync, 4_100_000, 9, 110).unmeasured(),
                .file(.receipts, sync + ".pkg.bom", 12_288, 110).unmeasured(),
                .file(.receipts, sync + ".pkg.plist", 1_024, 110).unmeasured(),
            ]),
        ]
    }

    static func world(_ scenario: DemoScenario, now: Date) -> World {
        let base = live(now: now)
        var inventory = base.apps.map { record($0, now: now, lastSeenDaysAgo: 0) }
        var seeds = base.seeds
        var w = World(installed: base.apps, inventory: [], seeds: [], running: RunningSnapshot(
            bundleIDs: ["com.example.tern", "com.example.mosaic"],
            executablePaths: ["/Applications/Tern Browser.app/Contents/MacOS/Tern", "/Applications/Mosaic Sheets.app/Contents/MacOS/MosaicSheets"]),
                      readiness: readiness(for: scenario, now: now), log: [], inTrash: [])
        var gone: [Gone] = []
        switch scenario {
        case .quiet, .firstRun:
            break
        case .leftovers, .snapshots, .blocked:
            gone = [orbit(now), lumen(now), harbor(now), quill(now), glowPhotos(now), parcel(now)]
            // Harbor's cache is root-owned (macOS says no); a Lumen log is written to after the scan.
            w.refuses = ["\(home)/Library/Caches/com.example.harborvpn"]
            w.drifts = ["\(home)/Library/Logs/com.example.lumenplayer"]
            w.protectedRoots = scenario == .blocked ? [.containers, .groupContainers] : [.cookies]
        case .maybeOnly:
            gone = maybeOnly(now)
        case .adminRows:
            gone = adminOnly(now)
            let a = atlas(now)
            w.installed.append(a.app)
            inventory.append(record(a.app, now: now, lastSeenDaysAgo: 0))
            seeds += a.seeds
        }
        for g in gone {
            inventory.append(record(g.app, now: now, lastSeenDaysAgo: g.lastSeen))
            seeds += g.seeds
        }
        if scenario == .blocked {
            // Names are visible, contents are not: the rows are shown by name and never touched.
            let hidden: Set<LibraryRoot> = [.containers, .groupContainers]
            seeds = seeds.map { hidden.contains($0.root) ? $0.protectedByMacOS() : $0 }
        }
        let p = past(for: scenario, now: now)
        w.inventory = inventory
        w.seeds = seeds
        w.log = p.entries
        w.inTrash = p.inTrash
        return w
    }
}
