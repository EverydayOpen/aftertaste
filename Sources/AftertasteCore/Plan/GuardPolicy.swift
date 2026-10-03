import Foundation

/// The pure half of `Guard.verify` (Mac): may this path still be moved, judged by its spelling alone? The Mac layer adds the
/// facts only the filesystem knows (realpath of the parent, lstat of the leaf, device, volume type, flags, owner, stamp).
public enum GuardPolicy {
    /// nil = allowed. `canonicalParent` is the Mac layer's `realpath` of the item's parent folder.
    /// Allowed means: the item is an immediate child of an allow-listed user root (or an `.app` directly in an Applications
    /// folder), the parent is not a link to somewhere else, and nothing on the never-list or keep-list matches. System roots
    /// answer `needsAdmin`: v1 never moves them.
    public static func check(path: String, canonicalParent: String, home: String, keep: [String], isAppBundle: Bool) -> GuardVerdict? {
        let p = normalize(path)
        guard p.hasPrefix("/"), !p.unicodeScalars.contains(where: { $0.value == 0 }) else {
            return .blocked(.neverList, "That is not a full path.")
        }
        let comps = p.split(separator: "/", omittingEmptySubsequences: true).map(String.init)
        guard comps.count >= 2, !comps.contains(".."), !comps.contains(".") else {
            return .blocked(.neverList, "That path is not one Aftertaste moves.")
        }
        let leaf = comps[comps.count - 1]
        let parent = "/" + comps.dropLast().joined(separator: "/")
        if Names.fold(normalize(canonicalParent)) != Names.fold(parent) {
            return .blocked(.linkEscapes, WhyText.reason(.linkEscapes))
        }
        if let reason = NeverList.reason(forPath: p, home: home, keep: keep) {
            return .blocked(reason, WhyText.reason(reason))
        }
        if isAppBundle {
            guard Names.fold(leaf).hasSuffix(".app"), Names.fold(leaf).count > 4 else {
                return .blocked(.neverList, "That is not an app.")
            }
            return isInAppFolder(parent, home: home) ? nil : .blocked(.neverList, "That app is not in an Applications folder.")
        }
        let h = normalize(home)
        for root in LibraryRoot.allCases where Names.fold(normalize(root.path(home: h))) == Names.fold(p) {
            return .blocked(.neverList, "That folder is one Aftertaste looks inside.")
        }
        for root in LibraryRoot.allCases where Names.fold(normalize(root.path(home: h))) == Names.fold(parent) {
            return root.isSystem ? .blocked(.needsAdmin, WhyText.reason(.needsAdmin)) : nil
        }
        return .blocked(.neverList, "That is not in a place Aftertaste looks.")
    }

    /// Strips the `/System/Volumes/Data` firmlink spelling, collapses `//`, drops a trailing `/`. Does not resolve `.` or `..`
    /// (the check rejects them) and does not touch the disk.
    public static func normalize(_ path: String) -> String {
        guard !path.isEmpty else { return "" }
        var parts = path.split(separator: "/", omittingEmptySubsequences: true).map(String.init)
        guard path.hasPrefix("/") else { return parts.joined(separator: "/") }
        if parts.count >= 3, parts[0] == "System", parts[1] == "Volumes", parts[2] == "Data" { parts.removeFirst(3) }
        return "/" + parts.joined(separator: "/")
    }

    /// Where an app can sit and still be moved: `/Applications`, its `Utilities` and `Setapp` folders, `~/Applications`.
    /// One nested folder level (Adobe-style `/Applications/Some Suite/Some App.app`) and mounted `/Volumes/*/Applications`
    /// are accepted by `check` as well.
    public static func appFolders(home: String) -> [String] {
        let h = normalize(home)
        return ["/Applications", "/Applications/Utilities", "/Applications/Setapp", (h == "/" ? "" : h) + "/Applications"]
    }

    public static func isInAppFolder(_ parent: String, home: String) -> Bool {
        let folders = appFolders(home: home).map(Names.fold)
        let fp = Names.fold(parent)
        if folders.contains(fp) { return true }
        let parts = fp.split(separator: "/").map(String.init)
        // The nested level is a suite folder, never another app: nothing inside an installed app's bundle is moved.
        guard !parts.contains(where: { $0.hasSuffix(".app") }) else { return false }
        if parts.count >= 2, folders.contains("/" + parts.dropLast().joined(separator: "/")) { return true }
        return (parts.count == 3 || parts.count == 4) && parts[0] == "volumes" && parts[2] == "applications"
    }
}

/// Did the thing change between the scan and now? Directories never compare their size (it changes as apps write).
public enum Stamps {
    public static func same(_ a: FileStamp, _ b: FileStamp) -> Bool {
        a.device == b.device && a.inode == b.inode && a.type == b.type && a.mtimeSeconds == b.mtimeSeconds
            && a.mtimeNanoseconds == b.mtimeNanoseconds && a.linkCount == b.linkCount && (a.type != .file || a.size == b.size)
    }
}
