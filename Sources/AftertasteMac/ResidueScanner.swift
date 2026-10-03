import Darwin
import Foundation
import AftertasteCore

public enum ScanBudget: Sendable {
    public static let perRootEntries = 20_000
    public static let perRootSeconds = 5.0
    public static let perItemFiles = 200_000
    public static let perItemSeconds = 5.0
}

/// Reads the library as names and `lstat`s, measures what Core says is worth measuring, and hands it all to the pure
/// `Scan.analyze` (BUILD_PLAN §5.3). File contents are never read here: no recursion looks for matches, nothing follows a
/// link, nothing crosses a device, and a folder macOS protects is recorded as protected and left alone.
public enum ResidueScanner {
    /// Lists every `LibraryRoot` once. Entries are a name and an `lstat`, plus: launchd facts for launch agent plists, and the
    /// container metadata ID for UUID-named containers (only when `containersReadable`). `containersReadable == nil` probes
    /// for Full Disk Access (see `defaultContainersReadable`). A root whose contents macOS will not let us open
    /// (`contentsMayBeProtected` and not readable) is listed by name and counted as protected by macOS.
    public static func listLibrary(home: String, now: Date, containersReadable: Bool? = nil) -> LibrarySnapshot {
        let readable = containersReadable ?? defaultContainersReadable(home: home)
        return LibrarySnapshot(home: home, listings: LibraryRoot.allCases.map { list($0, home: home, containersReadable: readable) }, takenAt: now)
    }

    /// Sizes the given paths with a manual `lstat` walk: allocated bytes, regular-file count, newest mtime. A budget or an
    /// unreadable subfolder makes it `atLeast`; a symlink, a protected container or an iCloud placeholder is `notMeasured`.
    /// Paths run in parallel, each bounded by `ScanBudget` (ponytail: no cancellation inside a walk; the budgets bound it).
    public static func measure(paths: [String], containersReadable: Bool = false) -> [String: SizeMeasure] {
        let box = Collected()
        DispatchQueue.concurrentPerform(iterations: paths.count) { i in
            box.set(paths[i], measureOne(paths[i], containersReadable: containersReadable))
        }
        return box.values
    }

    public static func stamp(of path: String) -> FileStamp? {
        let i = Fs.info(path)
        return i.err == 0 ? Fs.stamp(i.st) : nil
    }

    /// Composes: discover → listLibrary → Scan.candidatePaths → measure → Scan.analyze, then fills the stamp of anything the
    /// listing did not stamp (the dropped app bundle). An item without a stamp is never moved (Guard: "changed").
    public static func scan(_ request: ScanRequest, prefs: Preferences, home: String, osVersion: String, now: Date,
                            containersReadable: Bool? = nil) async -> ScanResult {
        let installed = InstalledApps.discover(home: home, inventory: InventoryStore.load(home: home), now: now)
        let inventory = InventoryStore.update(with: installed, home: home, now: now)
        let readable = containersReadable ?? defaultContainersReadable(home: home)
        var input = ScanInput(kind: .orphans, installed: installed, inventory: inventory,
                              library: listLibrary(home: home, now: now, containersReadable: readable),
                              running: RunningApps.snapshot(), prefs: prefs, home: home, osVersion: osVersion, now: now)
        if case .app(let target) = request {
            input.kind = .app
            input.target = target
        }
        // Apps the folders above do not show (Downloads, another drive) still own their leftovers: ask Launch Services about the
        // target and every orphan candidate, then analyse with them in the live-owner index.
        let known = Set(input.installed.apps.map { $0.bundlePath.lowercased() })
        let extra = InstalledApps.launchServicesApps(ids: Scan.ownerIDs(input) + [input.target?.bundleID].compactMap { $0 }, excluding: nil, now: now)
        input.installed.apps += extra.filter { !known.contains($0.bundlePath.lowercased()) }
        input.sizes = measure(paths: Scan.candidatePaths(input), containersReadable: readable)
        var result = Scan.analyze(input)
        for g in result.groups.indices {
            for i in result.groups[g].items.indices where result.groups[g].items[i].stamp == nil {
                let path = result.groups[g].items[i].path
                guard let s = stamp(of: path) else { continue }
                result.groups[g].items[i].stamp = s
                result.groups[g].items[i].mtime = s.mtime
            }
        }
        return result
    }

    /// Containers and Group Containers may be opened when Full Disk Access is granted, or before macOS 14 (which started asking
    /// for consent per container). The probe is `opendir` on `~/Library/Safari`, then `~/Library/Mail`. The app never nags for
    /// it. VERIFY which folder is reliable on 14, 15 and 26, and the macOS 13 claim.
    static func defaultContainersReadable(home: String) -> Bool {
        if !ProcessInfo.processInfo.isOperatingSystemAtLeast(OperatingSystemVersion(majorVersion: 14, minorVersion: 0, patchVersion: 0)) { return true }
        for folder in ["Library/Safari", "Library/Mail"] {
            let r = Fs.names(in: home + "/" + folder, limit: 1)
            if r.err == 0 { return true }
            if r.err != ENOENT { return false }
        }
        return false
    }

    // MARK: - Listing

    private static func list(_ root: LibraryRoot, home: String, containersReadable: Bool) -> RootListing {
        let dir = root.path(home: home)
        let r = Fs.names(in: dir, limit: ScanBudget.perRootEntries, seconds: ScanBudget.perRootSeconds)
        if r.err != 0 {
            let state: PlaceState = r.err == ENOENT ? .absent : (r.err == EPERM || r.err == EACCES ? .protectedByMacOS : .failed)
            return RootListing(coverage: PlaceCoverage(root: root, state: state, errno: r.err == ENOENT ? nil : r.err))
        }
        let canOpen = containersReadable || !root.contentsMayBeProtected
        let entries = r.names.sorted().map { entry($0, in: dir, root: root, canOpen: canOpen) }
        let state: PlaceState = canOpen ? (r.truncated ? .partial : .read) : .protectedByMacOS
        return RootListing(coverage: PlaceCoverage(root: root, state: state, entryCount: entries.count), entries: entries)
    }

    private static func entry(_ name: String, in dir: String, root: LibraryRoot, canOpen: Bool) -> LibraryEntry {
        let path = dir + "/" + name
        let i = Fs.info(path)
        guard i.err == 0 else { return LibraryEntry(name: name, type: .other, errno: i.err) }
        let type = Fs.kind(i.st)
        var e = LibraryEntry(name: name, type: type, stamp: Fs.stamp(i.st), isDataless: (i.st.st_flags & Fs.datalessFlag) != 0)
        guard !e.isDataless else { return e }
        switch root {
        case .containers where canOpen && type == .directory && Fs.looksLikeUUID(name):
            e.containerID = Identity.containerMetadataID(atContainer: path)
        case .launchAgents, .systemLaunchAgents, .systemLaunchDaemons:
            if type == .file && name.hasSuffix(".plist") { e.launchd = Identity.launchd(at: path) }
        default:
            break
        }
        return e
    }

    // MARK: - Measuring

    private static func measureOne(_ path: String, containersReadable: Bool) -> SizeMeasure {
        let top = Fs.info(path)
        guard top.err == 0 else { return SizeMeasure(bytes: 0, state: .notMeasured) }
        let newestTop = Date(timeIntervalSince1970: Fs.seconds(top.st))
        switch Fs.kind(top.st) {
        case .file:
            return SizeMeasure(bytes: Fs.allocated(top.st), state: .measured, fileCount: 1, newestMtime: newestTop)
        case .directory:
            break
        default:
            return SizeMeasure(bytes: 0, state: .notMeasured, fileCount: 0, newestMtime: newestTop)
        }
        let protected = !containersReadable && (path.contains("/Library/Containers/") || path.contains("/Library/Group Containers/"))
        if protected || (top.st.st_flags & Fs.datalessFlag) != 0 {
            return SizeMeasure(bytes: 0, state: .notMeasured, fileCount: 0, newestMtime: newestTop)
        }

        var bytes: UInt64 = 0
        var files = 0
        var visited = 0
        var newest = Fs.seconds(top.st)
        var exact = true
        var stack = [path]
        let start = DispatchTime.now().uptimeNanoseconds
        walk: while let dir = stack.popLast() {
            let r = Fs.names(in: dir)
            if r.err != 0 {
                // The item's own folder cannot be opened: nothing was counted, so say "not measured", not "at least 0 bytes".
                if dir == path { return SizeMeasure(bytes: 0, state: .notMeasured, fileCount: 0, newestMtime: newestTop) }
                exact = false
                continue
            }
            for name in r.names {
                visited += 1
                if visited > ScanBudget.perItemFiles || Double(DispatchTime.now().uptimeNanoseconds - start) / 1_000_000_000 > ScanBudget.perItemSeconds {
                    exact = false
                    break walk
                }
                let child = dir + "/" + name
                let c = Fs.info(child)
                guard c.err == 0 else { exact = false; continue }
                newest = max(newest, Fs.seconds(c.st))
                switch Fs.kind(c.st) {
                case .file:
                    bytes += Fs.allocated(c.st)
                    files += 1
                case .directory:
                    // Never across a device, never into a placeholder.
                    if c.st.st_dev != top.st.st_dev || (c.st.st_flags & Fs.datalessFlag) != 0 { exact = false } else { stack.append(child) }
                default:
                    break
                }
            }
        }
        return SizeMeasure(bytes: bytes, state: exact ? .measured : .atLeast, fileCount: files, newestMtime: Date(timeIntervalSince1970: newest))
    }

    /// Collects the parallel results. A lock around a dictionary; nothing else is shared.
    private final class Collected: @unchecked Sendable {
        private let lock = NSLock()
        private var map: [String: SizeMeasure] = [:]
        func set(_ key: String, _ value: SizeMeasure) { lock.lock(); map[key] = value; lock.unlock() }
        var values: [String: SizeMeasure] { lock.lock(); defer { lock.unlock() }; return map }
    }
}
