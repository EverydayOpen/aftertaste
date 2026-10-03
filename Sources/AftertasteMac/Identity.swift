import Darwin
import Foundation
import Security
import AftertasteCore

/// Who an app is and what it ships (BUILD_PLAN §5.1): the bundle's `Contents/Info.plist` (parsed by Core), its code
/// signature (Team ID and app groups) and its nested helpers. Also the three small files the scanner reads next to it: launchd
/// plists and container metadata plists. Every read is one regular file, never a symlink, 1 MB at most. The only file with
/// `Security` and, with the journal and inventory, the only one that reads file contents.
public enum Identity {
    static let notAnApp = "That is not an app."
    private static let maxPlist: Int64 = 1 << 20
    private static let embeddedRoots = ["Contents/Library/LoginItems", "Contents/XPCServices", "Contents/PlugIns"]
    private static let ownIDPrefix = "io.github.everydayopen.aftertaste"

    public static func read(appURL: URL, now: Date) -> AppLookup { load(appURL, now: now, live: false) }

    /// Same as `read` for an installed app in the live-owner index. Such an app only ever protects files and Core matches its IDs
    /// literally, so a bundle ID that is not strict reverse-DNS (an underscore, one label) is accepted when it is merely usable.
    static func readLive(appURL: URL, now: Date) -> AppLookup { load(appURL, now: now, live: true) }

    private static func load(_ appURL: URL, now: Date, live: Bool) -> AppLookup {
        let path = appURL.standardizedFileURL.path
        let top = Fs.info(path)
        guard path.hasSuffix(".app"), top.err == 0, Fs.kind(top.st) == .directory else {
            return AppLookup(rejection: notAnApp)
        }
        if URL(fileURLWithPath: Fs.parent(of: path)).pathComponents.contains(where: { $0.hasSuffix(".app") }) {
            return AppLookup(rejection: "That app is inside another app.")
        }
        guard let data = plist(at: path + "/Contents/Info.plist"), let info = Parsers.infoPlist(data) ?? (live ? Parsers.liveInfoPlist(data) : nil) else {
            return AppLookup(rejection: notAnApp)
        }
        if info.bundleID.lowercased().hasPrefix(ownIDPrefix) { return AppLookup(rejection: "Aftertaste does not remove itself.") }
        let apple = (info.bundleID.lowercased().hasPrefix("com.apple.") && !AppleAllowList.allows(info.bundleID)) || path.hasPrefix("/System/")
        if apple { return AppLookup(rejection: "macOS apps from Apple are never touched.") }

        let signature = signed(by: appURL)
        let nested = nestedBundles(in: path)
        var labels = info.smPrivilegedLabels + nested.labels
        for sub in ["Contents/Library/LaunchServices", "Contents/Library/LaunchDaemons", "Contents/Library/LaunchAgents"] {
            labels += Fs.names(in: path + "/" + sub).names.map { $0.hasSuffix(".plist") ? String($0.dropLast(6)) : $0 }
        }
        let source: InstallSource = Fs.info(path + "/Contents/_MASReceipt").err == 0 ? .appStore
            : (path.hasPrefix("/Applications/Setapp/") ? .setapp : .manual)
        let name = info.name.isEmpty ? ((path as NSString).lastPathComponent as NSString).deletingPathExtension : info.name
        let identity = AppIdentity(bundleID: info.bundleID, displayName: name, execName: info.execName, version: info.version,
                                   teamID: signature.team, embeddedIDs: unique(nested.ids), groupIDs: signature.groups,
                                   helperLabels: unique(labels.filter(StrictBundleID.isValid)), bundlePath: path, installSource: source,
                                   appleSigned: false, bundleOwnerUID: top.st.st_uid, volumePath: Fs.volume(of: path), capturedAt: now)
        return AppLookup(identity: identity)
    }

    /// launchd plist → label and program, plus one lstat for whether the program still exists. Relative programs are not checked.
    static func launchd(at path: String) -> LaunchdInfo? {
        guard let data = plist(at: path), let parsed = Parsers.launchd(data) else { return nil }
        let exists = parsed.program.map { $0.hasPrefix("/") ? Fs.info($0).err == 0 : true } ?? true
        return LaunchdInfo(label: parsed.label, program: parsed.program, programExists: exists)
    }

    /// `MCMMetadataIdentifier` of a container folder. Only called when the scanner knows it may open container folders.
    static func containerMetadataID(atContainer path: String) -> String? {
        plist(at: path + "/.com.apple.containermanagerd.metadata.plist").flatMap { Parsers.containerMetadata($0) }
    }

    // MARK: -

    private static func unique(_ xs: [String]) -> [String] {
        var seen = Set<String>()
        return xs.filter { seen.insert($0).inserted }
    }

    /// One regular file (not a link, not an iCloud placeholder), at most 1 MB.
    private static func plist(at path: String) -> Data? {
        let i = Fs.info(path)
        guard i.err == 0, Fs.kind(i.st) == .file, Int64(i.st.st_size) <= maxPlist, (i.st.st_flags & Fs.datalessFlag) == 0 else { return nil }
        return try? Data(contentsOf: URL(fileURLWithPath: path))
    }

    /// Team ID and app-group entitlements from the signature. Reads the signature blob only; it never validates the bundle
    /// (that would hash every file in it). Unsigned and ad-hoc apps simply have neither. VERIFY on ad-hoc, unsigned, Apple-signed.
    private static func signed(by url: URL) -> (team: String?, groups: [String]) {
        var code: SecStaticCode?
        guard SecStaticCodeCreateWithPath(url as CFURL, SecCSFlags(), &code) == errSecSuccess, let code else { return (nil, []) }
        var cf: CFDictionary?
        guard SecCodeCopySigningInformation(code, SecCSFlags(rawValue: UInt32(kSecCSSigningInformation)), &cf) == errSecSuccess,
              let info = cf as? [String: Any] else { return (nil, []) }
        let team = info[kSecCodeInfoTeamIdentifier as String] as? String
        let entitlements = info[kSecCodeInfoEntitlementsDict as String] as? [String: Any]
        return (team, entitlements?["com.apple.security.application-groups"] as? [String] ?? [])
    }

    /// Bundle IDs of nested helpers, login items, XPC services and extensions: at most 128 bundles, 4 levels deep, never
    /// through a symlink, never Sparkle's.
    private static func nestedBundles(in bundle: String) -> (ids: [String], labels: [String]) {
        var ids: [String] = []
        var labels: [String] = []
        var budget = 128
        func walk(_ dir: String, depth: Int) {
            guard depth <= 4, budget > 0, Fs.kind(Fs.info(dir).st) == .directory else { return }
            for name in Fs.names(in: dir).names.sorted() where budget > 0 && (name.hasSuffix(".app") || name.hasSuffix(".xpc") || name.hasSuffix(".appex")) {
                let p = dir + "/" + name
                let i = Fs.info(p)
                guard i.err == 0, Fs.kind(i.st) == .directory else { continue }
                budget -= 1
                if let data = plist(at: p + "/Contents/Info.plist"), let parsed = Parsers.infoPlist(data) {
                    if parsed.bundleID.hasPrefix("org.sparkle-project.") { continue }
                    ids.append(parsed.bundleID)
                    labels += parsed.smPrivilegedLabels
                }
                for root in embeddedRoots { walk(p + "/" + root, depth: depth + 1) }
            }
        }
        for root in embeddedRoots { walk(bundle + "/" + root, depth: 1) }
        return (ids, labels)
    }
}
