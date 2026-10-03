import Foundation

/// Apple apps people really do uninstall. Their bundle IDs start with `com.apple.`, which is otherwise never touched.
public enum AppleAllowList {
    public static let ids: [String] = [
        "com.apple.dt.Xcode", "com.apple.iWork.Pages", "com.apple.iWork.Numbers", "com.apple.iWork.Keynote",
        "com.apple.configurator.ui", "com.apple.SFSymbols", "com.apple.TestFlight",
    ]

    /// The ID itself or a dotted child of it (`com.apple.dt.Xcode.savedState` is Xcode's).
    public static func allows(_ bundleID: String) -> Bool {
        let f = Names.fold(bundleID)
        return ids.contains { let a = Names.fold($0); return f == a || f.hasPrefix(a + ".") }
    }
}

/// Everything Aftertaste refuses to touch, hard-coded (BUILD_PLAN S9, S12, S23). The user's keep-list only ever adds to it.
/// The iCloud and sync folder names appear in this file and nowhere else in the code base (a grep enforces it).
public enum NeverList {
    /// Our own bundle ID prefix, support folder and preferences.
    static let ownIDPrefix = "io.github.everydayopen.aftertaste"

    /// Folded folder names that are iCloud, sync or file-provider storage.
    static let iCloudNames: Set<String> = ["mobile documents", "cloudstorage", "clouddocs", "fileprovider", "com~apple~clouddocs"]

    /// Folded names of Apple-owned or personal-data folders that are never an app's leftover.
    static let personalNames: Set<String> = [
        "keychains", "mail", "messages", "safari", "photos", "accounts", "addressbook", "calendars", "mobilesync", ".mobilebackups",
        "crashreporter", "com.apple.sharedfilelist", ".trash", "developer",
    ]

    /// First folder under `~/Library` that is never touched, whatever is inside.
    static let libraryTopLevel: Set<String> = [
        "mobile documents", "cloudstorage", "keychains", "mail", "messages", "safari", "photos", "accounts", "addressbook",
        "calendars", "developer", "fileprovider",
    ]

    /// Folders under `~/Library/Application Support` that are never touched.
    static let supportTopLevel: Set<String> = ["clouddocs", "fileprovider", "mobilesync", "addressbook", "com.apple.tcc", "icloud"]

    // The reason a single folder or file name (no slash) is off limits, or nil. `keep` is the user's keep-list.
    public static func reason(forName name: String, keep: [String] = []) -> BlockReason? {
        let f = Names.fold(name)
        if f.isEmpty || f == "." || f == ".." { return .neverList }
        if f.hasPrefix(ownIDPrefix) || f == "aftertaste" { return .ownCopy }
        if iCloudNames.contains(f) || f.hasPrefix("icloud~") { return .iCloud }
        if personalNames.contains(f) || f.hasSuffix(".photoslibrary") { return .neverList }
        if isAppleOwned(f) { return .appleOwned }
        if keeps(name: f, keep: keep) { return .neverList }
        return nil
    }

    /// The reason a whole path is off limits, or nil. `keep` entries are bundle IDs or absolute (or `~`) path prefixes.
    public static func reason(forPath path: String, home: String, keep: [String] = []) -> BlockReason? {
        let p = GuardPolicy.normalize(path)
        let h = GuardPolicy.normalize(home)
        for root in ["/System", "/usr", "/bin", "/sbin", "/private"] where p == root || p.hasPrefix(root + "/") {
            if p.hasPrefix("/private/var/db/receipts/") { break }
            return .neverList
        }
        let relative: [String]
        if !h.isEmpty, h != "/", p.hasPrefix(h + "/") {
            relative = p.dropFirst(h.count + 1).split(separator: "/").map { Names.fold(String($0)) }
        } else {
            relative = p.split(separator: "/").map { Names.fold(String($0)) }
        }
        if relative.contains(".trash") { return .neverList }
        if relative.contains(where: { $0.hasPrefix("icloud~") || iCloudNames.contains($0) }) { return .iCloud }
        if relative.contains(where: { $0.hasSuffix(".photoslibrary") }) { return .neverList }
        if relative.first == "library", relative.count >= 2 {
            if libraryTopLevel.contains(relative[1]) { return relative[1] == "fileprovider" || relative[1].hasPrefix("mobile") || relative[1] == "cloudstorage" ? .iCloud : .neverList }
            if relative[1] == "application support", relative.count >= 3, supportTopLevel.contains(relative[2]) {
                return relative[2] == "clouddocs" || relative[2] == "fileprovider" || relative[2] == "icloud" ? .iCloud : .neverList
            }
        }
        if let leaf = p.split(separator: "/").last, let r = reason(forName: String(leaf)) { return r }
        if !keep.isEmpty {
            for entry in keep where entry.hasPrefix("/") || entry.hasPrefix("~") {
                let k = GuardPolicy.normalize(PathText.expandTilde(entry, home: h))
                guard !k.isEmpty, k != "/" else { continue }
                // Either contains the other: moving a folder would take the kept file inside it. Folded: the default volume ignores case.
                let kf = Names.fold(k), pf = Names.fold(p)
                if pf == kf || pf.hasPrefix(kf + "/") || kf.hasPrefix(pf + "/") { return .neverList }
            }
            if let leaf = p.split(separator: "/").last, keeps(name: Names.fold(String(leaf)), keep: keep) { return .neverList }
        }
        return nil
    }

    /// True when the user keeps this bundle ID (the ID itself or anything below it).
    public static func keeps(bundleID: String, keep: [String]) -> Bool {
        let f = Names.fold(bundleID)
        return keep.contains { k in
            guard !k.hasPrefix("/"), !k.hasPrefix("~") else { return false }
            let kf = Names.fold(k)
            return !kf.isEmpty && (f == kf || f.hasPrefix(kf + "."))
        }
    }

    // A folded entry name is the kept bundle ID, the ID plus a known extension, or a dotted child.
    static func keeps(name f: String, keep: [String]) -> Bool {
        if keep.isEmpty { return false }
        for ext in ["", ".plist", ".savedstate", ".binarycookies", ".sfl2", ".sfl3", ".bom"] {
            let stem = ext.isEmpty ? f : (Names.strip(f, ext: ext) ?? "")
            if !stem.isEmpty, keeps(bundleID: stem, keep: keep) { return true }
        }
        return false
    }

    /// `com.apple.*` in any of its spellings (plain, `group.`, `<Team>.group.`, `groups.`), unless it is an allow-listed app.
    static func isAppleOwned(_ f: String) -> Bool {
        if f.hasPrefix("com.apple.") || f == "com.apple" { return !AppleAllowList.allows(f) }
        var rest = Substring(f)
        if let dot = rest.firstIndex(of: "."), StrictBundleID.isTeamID(rest[rest.startIndex..<dot].uppercased()) {
            rest = rest[rest.index(after: dot)...]
        }
        for prefix in ["group.", "groups."] where rest.hasPrefix(prefix) { rest = rest.dropFirst(prefix.count) }
        return rest.hasPrefix("com.apple.") || rest == "com.apple"
    }
}
