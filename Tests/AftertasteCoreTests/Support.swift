import Foundation
import XCTest
@testable import AftertasteCore

/// Test helpers: a tiny fixture builder for library snapshots and a loader for the JSON fixtures in `Fixtures/`.
/// Fake names only: the user is `jane`, apps are `com.example.*` except the few real vendor names the hazard fixtures need.
enum T {
    static let home = "/Users/jane"
    /// 2026-10-03 12:00:00 UTC.
    static let now = Civil.date(year: 2026, month: 10, day: 3, hour: 12)
    static let day: TimeInterval = 86_400

    static func fixturesDir(_ file: StaticString = #filePath) -> URL {
        URL(fileURLWithPath: "\(file)").deletingLastPathComponent().appendingPathComponent("Fixtures")
    }

    static func repoRoot(_ file: StaticString = #filePath) -> URL {
        URL(fileURLWithPath: "\(file)").deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    }

    static func app(_ id: String, _ name: String, exec: String? = nil, team: String? = nil, path: String? = nil, version: String? = nil,
                    embedded: [String] = [], groups: [String] = [], helpers: [String] = [], uid: UInt32? = 501) -> AppIdentity {
        AppIdentity(bundleID: id, displayName: name, execName: exec ?? name, version: version, teamID: team, embeddedIDs: embedded,
                    groupIDs: groups, helperLabels: helpers, bundlePath: path ?? "/Applications/\(name).app", bundleOwnerUID: uid,
                    capturedAt: now)
    }

    static func stamp(_ inode: UInt64, type: FileType = .directory, size: UInt64 = 0, daysOld: Double = 100) -> FileStamp {
        FileStamp(device: 1, inode: inode, type: type, size: size, mtimeSeconds: Int64(now.timeIntervalSince1970 - daysOld * day),
                  mtimeNanoseconds: 0, linkCount: 1)
    }

    static func sized(_ bytes: UInt64, files: Int = 3, newestDaysOld: Double? = nil) -> SizeMeasure {
        SizeMeasure(bytes: bytes, state: .measured, fileCount: files, newestMtime: newestDaysOld.map { now.addingTimeInterval(-$0 * day) })
    }
}

/// Builds a `ScanInput` one root at a time.
struct Lib {
    var apps: [AppIdentity] = []
    var inventory: [InventoryRecord] = []
    var entries: [LibraryRoot: [LibraryEntry]] = [:]
    var coverageOverride: [LibraryRoot: PlaceState] = [:]
    var sizes: [String: SizeMeasure] = [:]
    var running = RunningSnapshot()
    var prefs = Preferences.default
    var volumeMayBeMissing = false
    var unreadableAppFolders: [String] = []
    private var nextInode: UInt64 = 1000

    mutating func add(_ root: LibraryRoot, _ names: String..., type: FileType = .directory, daysOld: Double = 100, size: UInt64? = nil) {
        for name in names { addEntry(root, name, type: type, daysOld: daysOld, size: size) }
    }

    mutating func addEntry(_ root: LibraryRoot, _ name: String, type: FileType = .directory, daysOld: Double = 100, size: UInt64? = nil,
                           container: String? = nil, launchd: LaunchdInfo? = nil, dataless: Bool = false) {
        nextInode += 1
        let st = T.stamp(nextInode, type: type, size: size ?? (type == .file ? 2048 : 0), daysOld: daysOld)
        entries[root, default: []].append(LibraryEntry(name: name, type: type, stamp: st, containerID: container, launchd: launchd, isDataless: dataless))
    }

    mutating func addAgent(_ root: LibraryRoot = .launchAgents, name: String, label: String, program: String?, exists: Bool = true) {
        addEntry(root, name, type: .file, launchd: LaunchdInfo(label: label, program: program, programExists: exists))
    }

    func path(_ root: LibraryRoot, _ name: String) -> String { GuardPolicy.normalize(root.path(home: T.home) + "/" + name) }

    func snapshot() -> LibrarySnapshot {
        let listings = LibraryRoot.allCases.map { root -> RootListing in
            let list = entries[root] ?? []
            let state = coverageOverride[root] ?? .read
            let visible = state == .read ? list : []
            return RootListing(coverage: PlaceCoverage(root: root, state: state, errno: state == .protectedByMacOS ? 1 : nil, entryCount: visible.count),
                               entries: visible)
        }
        return LibrarySnapshot(home: T.home, listings: listings, takenAt: T.now)
    }

    func input(_ kind: ScanKind, target: AppIdentity? = nil, prefs: Preferences? = nil, running: RunningSnapshot? = nil) -> ScanInput {
        ScanInput(kind: kind, target: target,
                  installed: InstalledSnapshot(apps: apps, unreadableLocations: unreadableAppFolders, volumeMayBeMissing: volumeMayBeMissing, capturedAt: T.now),
                  inventory: inventory, library: snapshot(), sizes: sizes, running: running ?? self.running, prefs: prefs ?? self.prefs,
                  home: T.home, osVersion: "26.1", now: T.now)
    }

    func analyze(_ kind: ScanKind, target: AppIdentity? = nil) -> ScanResult { Scan.analyze(input(kind, target: target)) }
}

extension ScanResult {
    func item(_ path: String) -> ResidueItem? { items.first { $0.path == path } }
    func tiers() -> [String: Tier] { Dictionary(uniqueKeysWithValues: items.map { ($0.path, $0.tier) }) }
    func group(_ id: String) -> ResidueGroup? { groups.first { $0.owner.bundleID == id } }
}

// MARK: JSON fixtures

struct FxEntry: Decodable {
    var name: String
    var type: String?
    var container: String?
    var label: String?
    var program: String?
    var programExists: Bool?
    var daysOld: Double?

    init(from decoder: Decoder) throws {
        if let s = try? decoder.singleValueContainer().decode(String.self) {
            name = s
            return
        }
        let c = try decoder.container(keyedBy: Keys.self)
        name = try c.decode(String.self, forKey: .name)
        type = try c.decodeIfPresent(String.self, forKey: .type)
        container = try c.decodeIfPresent(String.self, forKey: .container)
        label = try c.decodeIfPresent(String.self, forKey: .label)
        program = try c.decodeIfPresent(String.self, forKey: .program)
        programExists = try c.decodeIfPresent(Bool.self, forKey: .programExists)
        daysOld = try c.decodeIfPresent(Double.self, forKey: .daysOld)
    }

    enum Keys: String, CodingKey { case name, type, container, label, program, programExists, daysOld }
}

struct FxApp: Decodable {
    var id: String
    var name: String
    var exec: String?
    var team: String?
    var path: String?
    var version: String?
    var groups: [String]?
    var embedded: [String]?
    var helpers: [String]?
    var installed: Bool?
}

struct FxExpect: Decodable {
    var tiers: [String: String]?
    var absent: [String]?
    var blocked: [String: String]?
    /// Items that belong to an installed app: nothing may preselect them and no plan may contain them.
    var installedOwned: [String]?
    var preselected: [String]?
    var emptyResult: Bool?
}

struct FixtureFile: Decodable {
    var name: String
    var note: String?
    var kind: String
    var target: String?
    var apps: [FxApp]
    var library: [String: [FxEntry]]
    var sizes: [String: Int]?
    var volumeMayBeMissing: Bool?
    var expect: FxExpect

    static func guessType(_ name: String) -> FileType {
        let n = name.lowercased()
        if n.hasSuffix(".savedstate") { return .directory }
        return [".plist", ".sfl2", ".sfl3", ".bom", ".binarycookies", ".ips", ".crash"].contains { n.hasSuffix($0) } ? .file : .directory
    }

    func build() -> (lib: Lib, kind: ScanKind, target: AppIdentity?) {
        var lib = Lib()
        var target: AppIdentity?
        for a in apps {
            let identity = T.app(a.id, a.name, exec: a.exec, team: a.team, path: a.path, version: a.version, embedded: a.embedded ?? [],
                                 groups: a.groups ?? [], helpers: a.helpers ?? [])
            if target == nil, a.id == self.target { target = identity }
            if a.installed ?? true { lib.apps.append(identity) }
        }
        let byPath = Dictionary(uniqueKeysWithValues: LibraryRoot.allCases.map { ($0.relativePath, $0) })
        for (rel, entries) in library.sorted(by: { $0.key < $1.key }) {
            guard let root = byPath[rel] else { fatalError("fixture root not found") }
            for e in entries {
                let type = e.type.flatMap(FileType.init(rawValue:)) ?? Self.guessType(e.name)
                let info = e.label.map { LaunchdInfo(label: $0, program: e.program, programExists: e.programExists ?? true) }
                lib.addEntry(root, e.name, type: info != nil ? .file : type, daysOld: e.daysOld ?? 100, container: e.container, launchd: info)
            }
        }
        for (rel, bytes) in sizes ?? [:] {
            lib.sizes[GuardPolicy.normalize(T.home + "/" + rel)] = T.sized(UInt64(bytes))
        }
        lib.volumeMayBeMissing = volumeMayBeMissing ?? false
        return (lib, kind == "orphans" ? .orphans : .app, target)
    }
}

func loadFixtures(_ folder: String = "library", file: StaticString = #filePath) throws -> [FixtureFile] {
    let dir = T.fixturesDir(file).appendingPathComponent(folder)
    let names = try FileManager.default.contentsOfDirectory(atPath: dir.path).filter { $0.hasSuffix(".json") }.sorted()
    return try names.map { try JSONDecoder().decode(FixtureFile.self, from: Data(contentsOf: dir.appendingPathComponent($0))) }
}
