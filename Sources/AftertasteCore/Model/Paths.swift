import Foundation

/// Every folder Aftertaste looks in, listed once and never recursed into (BUILD_PLAN §4.3). Nothing else is scanned.
/// The first group is under the user's `~/Library`; the `system*` group and `receipts` are root-owned and only ever
/// produce read-only "Needs admin" rows.
public enum LibraryRoot: String, Codable, CaseIterable, Sendable {
    case preferences, preferencesByHost, caches, applicationSupport, containers, groupContainers, logs, diagnosticReports
    case savedState, httpStorages, webKit, cookies, launchAgents, applicationScripts, syncedPreferences
    case recentDocuments, crashReporter, autosaveInformation
    case systemApplicationSupport, systemCaches, systemPreferences, systemLaunchAgents, systemLaunchDaemons
    case systemPrivilegedHelperTools, systemLogs, receipts

    /// Under `~` for user roots (no leading slash); absolute for system roots.
    public var relativePath: String {
        switch self {
        case .preferences: return "Library/Preferences"
        case .preferencesByHost: return "Library/Preferences/ByHost"
        case .caches: return "Library/Caches"
        case .applicationSupport: return "Library/Application Support"
        case .containers: return "Library/Containers"
        case .groupContainers: return "Library/Group Containers"
        case .logs: return "Library/Logs"
        case .diagnosticReports: return "Library/Logs/DiagnosticReports"
        case .savedState: return "Library/Saved Application State"
        case .httpStorages: return "Library/HTTPStorages"
        case .webKit: return "Library/WebKit"
        case .cookies: return "Library/Cookies"
        case .launchAgents: return "Library/LaunchAgents"
        case .applicationScripts: return "Library/Application Scripts"
        case .syncedPreferences: return "Library/SyncedPreferences"
        case .recentDocuments: return "Library/Application Support/com.apple.sharedfilelist/com.apple.LSSharedFileList.ApplicationRecentDocuments"
        case .crashReporter: return "Library/Application Support/CrashReporter"
        case .autosaveInformation: return "Library/Autosave Information"
        case .systemApplicationSupport: return "/Library/Application Support"
        case .systemCaches: return "/Library/Caches"
        case .systemPreferences: return "/Library/Preferences"
        case .systemLaunchAgents: return "/Library/LaunchAgents"
        case .systemLaunchDaemons: return "/Library/LaunchDaemons"
        case .systemPrivilegedHelperTools: return "/Library/PrivilegedHelperTools"
        case .systemLogs: return "/Library/Logs"
        case .receipts: return "/private/var/db/receipts"
        }
    }

    public var isSystem: Bool { relativePath.hasPrefix("/") }

    /// The folder's absolute path for this user's home (with or without a trailing slash).
    public func path(home: String) -> String {
        if isSystem { return relativePath }
        let h = home.hasSuffix("/") && home.count > 1 ? String(home.dropLast()) : home
        return h + "/" + relativePath
    }

    /// Short name for the coverage strip and the diagnostics.
    public var displayName: String {
        switch self {
        case .preferences: return "Preferences"
        case .preferencesByHost: return "ByHost preferences"
        case .caches: return "Caches"
        case .applicationSupport: return "Application Support"
        case .containers: return "Containers"
        case .groupContainers: return "Group Containers"
        case .logs: return "Logs"
        case .diagnosticReports: return "Crash reports"
        case .savedState: return "Saved state"
        case .httpStorages: return "HTTP storages"
        case .webKit: return "WebKit data"
        case .cookies: return "Cookies"
        case .launchAgents: return "Launch agents"
        case .applicationScripts: return "Application Scripts"
        case .syncedPreferences: return "Synced preferences"
        case .recentDocuments: return "Recent documents"
        case .crashReporter: return "Crash reporter"
        case .autosaveInformation: return "Autosave Information"
        case .systemApplicationSupport: return "Application Support (all users)"
        case .systemCaches: return "Caches (all users)"
        case .systemPreferences: return "Preferences (all users)"
        case .systemLaunchAgents: return "Launch agents (all users)"
        case .systemLaunchDaemons: return "Launch daemons"
        case .systemPrivilegedHelperTools: return "Privileged helpers"
        case .systemLogs: return "Logs (all users)"
        case .receipts: return "Installer receipts"
        }
    }

    /// macOS 14+ may refuse to look inside these without consent or Full Disk Access (VERIFY on 14, 15, 26, 27). They are
    /// listed by name only; entries are never sized or opened unless a probe says the contents are readable.
    public var contentsMayBeProtected: Bool { self == .containers || self == .groupContainers }
}

/// What kind of filesystem object an item is. A symlink is its own item and is never followed.
public enum FileType: String, Codable, Sendable {
    case file, directory, symlink, other
}

/// The identity of a filesystem object at one moment (BUILD_PLAN §3 S5). Recorded at scan time and compared right before
/// the move. A directory's `size` is always 0 (its entry count and size change as apps write; the stamp never includes them).
public struct FileStamp: Codable, Hashable, Sendable {
    public var device: Int64
    public var inode: UInt64
    public var type: FileType
    public var size: UInt64
    public var mtimeSeconds: Int64
    public var mtimeNanoseconds: Int64
    public var linkCount: UInt32
    /// `st_blocks * 512`: the space the file takes on disk, the unit directory sizes are summed in. nil when unknown (then `size` is
    /// used). Not part of `Stamps.same`.
    public var allocated: UInt64?

    public init(device: Int64, inode: UInt64, type: FileType, size: UInt64, mtimeSeconds: Int64,
                mtimeNanoseconds: Int64 = 0, linkCount: UInt32 = 1, allocated: UInt64? = nil) {
        self.device = device
        self.inode = inode
        self.type = type
        self.size = size
        self.mtimeSeconds = mtimeSeconds
        self.mtimeNanoseconds = mtimeNanoseconds
        self.linkCount = linkCount
        self.allocated = allocated
    }

    public var mtime: Date { Date(timeIntervalSince1970: Double(mtimeSeconds) + Double(mtimeNanoseconds) / 1_000_000_000) }
}
