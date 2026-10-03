import Foundation

/// The false-positive hazards of the residue map (research §7) as data. Everything here only ever makes Aftertaste more
/// careful: a name in these lists lowers a tier, hides a match or demands a second proof; nothing raises one.
/// Apps are named descriptively (Aftertaste is not affiliated with or endorsed by any app it detects).
public enum Hazards {
    /// Folded words that are too generic to identify an app by name (T3 never matches them).
    public static let commonWords: Set<String> = [
        "notes", "music", "photos", "messages", "preview", "calendar", "helper", "agent", "service", "update", "sync", "backup",
        "cloud", "manager", "monitor", "server", "client", "mail", "safari", "maps", "books", "home", "stocks", "news", "clock",
        "contacts", "reminders", "podcasts", "weather", "terminal", "console", "finder", "dock", "login", "logic", "store",
        "system", "settings", "utility", "utilities", "cache", "caches", "data", "support", "library", "application",
        "applications", "assistant", "installer", "launcher", "updater", "daemon", "shared", "default", "general",
        "preferences", "setup", "tools", "player", "editor", "viewer", "studio", "camera", "drive", "files", "keychain",
        "search", "share", "widget", "widgets", "extension", "extensions", "plugin", "plugins", "browser", "remote", "writer",
        "reader", "capture", "screen", "recorder", "video", "audio", "image", "images", "document", "documents", "desktop",
        "download", "downloads", "launch", "menu", "status", "toolbox", "workspace", "project", "projects", "design",
    ]

    /// Shared updater, telemetry and crash-report state: at most Review whoever "owns" it (APP4 §3.2 U3).
    /// A trailing "*" means "starts with"; everything is compared folded.
    public static let sharedUpdaterNames: [String] = [
        "com.google.SoftwareUpdate", "com.google.Keystone*", "org.sparkle-project.*", "KSCrashReports", "Mozilla",
        "com.microsoft.autoupdate*", "com.crashlytics*", "io.sentry*", "com.bugsnag*", "SentryCrash",
    ]

    /// Vendor folders that several products share. A name match on one of these is at most Review and never preselected.
    public static let sharedVendorRoots: Set<String> = [
        "adobe", "microsoft", "google", "mozilla", "jetbrains", "ableton", "cycling '74", "native instruments", "avid",
        "steinberg", "waves", "izotope", "setapp", "android", "java", "python", "oracle", "autodesk", "corel", "unity",
        "blackmagic design", "apple", "dropbox", "docker", "npm", "node", "swift", "rust", "go", "ruby",
    ]

    /// Release-channel words. Two apps whose IDs differ only by one of these are one family and share folders.
    public static let channelFamilyTokens: [String] = [
        "beta", "nightly", "canary", "dev", "esr", "insiders", "preview", "alpha", "rc", "developeredition",
    ]

    /// A trailing label that marks a helper of the app whose ID is in front of it (APP4 §3.3 T2). Orphans group under the base ID.
    public static let helperSuffixes: [String] = [
        "helper", "agent", "daemon", "service", "xpc", "launcher", "updater", "installer", "login", "extension", "plugin",
    ]

    /// Names shared by a desktop app and a command-line tool. No top-level dot folder (`~/.name`) is ever derived from a display
    /// name (Mole #993), and v1 does not scan the home folder at all; this list guards any future rule.
    public static let sameNamedCLIDenylist: Set<String> = [
        "claude", "codex", "cursor", "windsurf", "zed", "code", "docker", "podman", "git", "gh", "node", "npm", "yarn", "pnpm",
        "bun", "deno", "python", "pip", "ruby", "gem", "go", "cargo", "rustup", "java", "maven", "gradle", "kube", "helm",
        "terraform", "aws", "gcloud", "az", "ssh", "gnupg", "gpg", "vim", "emacs", "tmux", "zsh", "bash", "fish", "brew",
        "conda", "nvm", "pyenv", "rbenv", "asdf", "config", "local", "cache", "ollama", "lima", "colima",
    ]

    /// A folder an app is known to write under a name that is not its ID or display name (VS Code writes "Code").
    public struct ProductFolder: Sendable, Hashable {
        public var root: LibraryRoot
        public var name: String
        public init(_ root: LibraryRoot, _ name: String) {
            self.root = root
            self.name = name
        }
    }

    /// Folded bundle ID -> folders. These are proven (T1) matches for that exact ID and nothing else, so `Code` belongs to
    /// VS Code and `Code - Insiders` to its sibling, never the other way round.
    public static let perProductFolders: [String: [ProductFolder]] = [
        "com.microsoft.vscode": [ProductFolder(.applicationSupport, "Code")],
        "com.microsoft.vscodeinsiders": [ProductFolder(.applicationSupport, "Code - Insiders")],
        "com.tinyspeck.slackmacgap": [ProductFolder(.applicationSupport, "Slack")],
        "us.zoom.xos": [ProductFolder(.applicationSupport, "zoom.us"), ProductFolder(.logs, "zoom.us")],
        "com.hnc.discord": [ProductFolder(.applicationSupport, "discord")],
        "com.spotify.client": [ProductFolder(.applicationSupport, "Spotify")],
        // Every Firefox channel writes its profiles under "Firefox" (VERIFY the Developer Edition and Nightly IDs on a real Mac).
        "org.mozilla.firefox": [ProductFolder(.applicationSupport, "Firefox")],
        "org.mozilla.firefoxdeveloperedition": [ProductFolder(.applicationSupport, "Firefox")],
        "org.mozilla.nightly": [ProductFolder(.applicationSupport, "Firefox")],
        "notion.id": [ProductFolder(.applicationSupport, "Notion")],
        "com.figma.desktop": [ProductFolder(.applicationSupport, "Figma")],
        "md.obsidian": [ProductFolder(.applicationSupport, "obsidian")],
    ]

    public static func isCommonWord(_ s: String) -> Bool { commonWords.contains(Names.fold(s)) }

    public static func isSameNamedCLI(_ s: String) -> Bool {
        sameNamedCLIDenylist.contains(Names.fold(s.hasPrefix(".") ? String(s.dropFirst()) : s))
    }

    public static func isSharedVendorRoot(_ name: String) -> Bool { sharedVendorRoots.contains(Names.fold(name)) }

    public static func isSharedUpdater(_ name: String) -> Bool {
        let f = Names.fold(name)
        for pattern in sharedUpdaterNames {
            let p = Names.fold(pattern)
            if p.hasSuffix("*") ? f.hasPrefix(String(p.dropLast())) : f == p { return true }
        }
        return false
    }

    /// A key for "same app, other release channel": the folded ID with a trailing channel word removed from its last label.
    /// "com.microsoft.VSCodeInsiders" and "com.microsoft.VSCode" share "com.microsoft.vscode"; "...Chrome.canary" and "...Chrome" too.
    public static func channelFamily(ofID id: String) -> String {
        if id.caseInsensitiveCompare("org.mozilla.nightly") == .orderedSame { return "org.mozilla.firefox" }
        var labels = Names.fold(id).split(separator: ".").map(String.init)
        guard labels.count >= 2 else { return Names.fold(id) }
        if channelFamilyTokens.contains(labels[labels.count - 1]), labels.count >= 4 {
            labels.removeLast()
            return labels.joined(separator: ".")
        }
        var last = labels[labels.count - 1]
        var changed = true
        while changed {
            changed = false
            for token in channelFamilyTokens where last.hasSuffix(token) && last.count - token.count >= 3 {
                last = String(last.dropLast(token.count))
                changed = true
            }
        }
        labels[labels.count - 1] = last
        return labels.joined(separator: ".")
    }
}
