import AppKit
import Darwin
import Foundation
import AftertasteCore

/// The apps installed right now (BUILD_PLAN §5.2): the usual app folders, one level deep plus one nested folder level
/// (Adobe-style folders, Setapp, Utilities), and each mounted volume's Applications folder. Apple's own apps are not
/// listed: they are never a target and never need to be a live owner (their IDs are on the never-list).
public enum InstalledApps {
    public static func discover(home: String, inventory: [InventoryRecord], now: Date) -> InstalledSnapshot {
        var apps: [AppIdentity] = []
        var unreadable: [String] = []
        var skipped: [String] = [] // bundles with an Info.plist that could not be used: the live index may be missing an app
        var seen = Set<String>()
        func add(_ app: AppIdentity) { if seen.insert(app.bundlePath).inserted { apps.append(app) } }

        func list(_ folder: String, nested: Bool) {
            let r = Fs.names(in: folder)
            if r.err == ENOENT { return }
            if r.err != 0 { unreadable.append(folder); return }
            for name in r.names.sorted() where !name.hasPrefix(".") {
                let path = folder + "/" + name
                if name.hasSuffix(".app") {
                    if let app = appIdentity(at: path, now: now) { add(app) }
                    else if isUnusableBundle(path, now: now) { skipped.append(path) }
                } else if !nested, Fs.kind(Fs.info(path).st) == .directory {
                    list(path, nested: true)
                }
            }
        }
        list("/Applications", nested: false)
        list(home + "/Applications", nested: false)

        // Other volumes: a leftover whose app lives on a drive that is mounted counts as owned; one on a drive that is
        // not mounted must not look abandoned.
        var volumeMissing = false
        let volumes = Fs.names(in: "/Volumes")
        if volumes.err != 0 && volumes.err != ENOENT { volumeMissing = true }
        for name in volumes.names.sorted() {
            let path = "/Volumes/" + name
            guard Fs.kind(Fs.info(path).st) == .directory else { continue } // the startup volume's link is a symlink
            let before = unreadable.count
            list(path + "/Applications", nested: false)
            if unreadable.count > before { volumeMissing = true }
        }
        for record in inventory {
            if let volume = record.identity.volumePath, !Fs.isMountPoint(volume) { volumeMissing = true }
        }

        let found = Set(apps.map(\.bundleID))
        for app in launchServicesApps(ids: inventory.map(\.identity.bundleID).filter { !found.contains($0) }, excluding: nil, now: now) { add(app) }

        apps.sort { $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending }
        return InstalledSnapshot(apps: apps, unreadableLocations: unreadable + skipped, volumeMayBeMissing: volumeMissing, capturedAt: now)
    }

    /// The live-owner index follows a `.app` symlink (an app linked into /Applications from another drive) and records the app under
    /// its real path. `Identity.read` itself still rejects symlinks, so dropping one on the window is refused. It reads leniently
    /// (`readLive`): an installed app with an unusual bundle ID still protects its folders.
    private static func lookup(at path: String, now: Date) -> AppLookup {
        var real = path
        if Fs.kind(Fs.info(path).st) == .symlink {
            guard let r = realpath(path, nil) else { return AppLookup(rejection: Identity.notAnApp) }
            real = String(cString: r)
            free(r)
        }
        return Identity.readLive(appURL: URL(fileURLWithPath: real, isDirectory: true), now: now)
    }

    private static func appIdentity(at path: String, now: Date) -> AppIdentity? { lookup(at: path, now: now).identity }

    /// A bundle that has an `Info.plist` but that even the live reader refused (no usable bundle ID, too big, damaged): the index
    /// may be missing an installed app. A folder with no `Info.plist`, Apple's apps and our own are not counted.
    private static func isUnusableBundle(_ path: String, now: Date) -> Bool {
        Fs.info(path + "/Contents/Info.plist").err == 0 && lookup(at: path, now: now).rejection == Identity.notAnApp
    }

    /// Launch Services is a second opinion for apps outside the folders above (a Downloads folder, a Desktop, a Dock-pinned copy on
    /// another drive): the copies of these bundle IDs that exist right now. A copy in the Trash is not installed, and neither is
    /// `excluding` (the bundle an uninstall-now run just moved, which Launch Services may keep returning for a while).
    /// VERIFY what it returns for trashed, archived and deleted copies on a real Mac.
    static func launchServicesApps(ids: [String], excluding bundlePath: String?, now: Date) -> [AppIdentity] {
        var out: [AppIdentity] = []
        for id in Set(ids) {
            for url in NSWorkspace.shared.urlsForApplications(withBundleIdentifier: id) {
                let path = GuardPolicy.normalize(url.path)
                if path.contains("/.Trash/") || path.contains("/.Trashes/") { continue }
                if let bundlePath, path.caseInsensitiveCompare(GuardPolicy.normalize(bundlePath)) == .orderedSame { continue }
                guard Fs.info(path).err == 0, let app = appIdentity(at: path, now: now) else { continue }
                out.append(app)
            }
        }
        return out
    }
}
