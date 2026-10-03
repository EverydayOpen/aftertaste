import Foundation

/// Where an app came from. `brew` carries its cask token in `AppIdentity.caskToken`.
public enum InstallSource: String, Codable, Sendable {
    case manual, appStore, pkg, brew, setapp, unknown
}

/// Everything that identifies one app, captured while it is still installed (BUILD_PLAN §4.1, APP4 §3.3). Read from its
/// `Info.plist` and code signature by `AftertasteMac.Identity`; never guessed from folder names. An orphan scan has no bundle,
/// so it synthesises one from an inventory record or from the leftover's own name (`bundlePath` is then empty).
public struct AppIdentity: Codable, Hashable, Sendable, Identifiable {
    /// `CFBundleIdentifier`, validated by `StrictBundleID`. For a synthesised orphan, the ID found in the leftover names.
    public var bundleID: String
    public var displayName: String
    /// `CFBundleExecutable`: names crash reports and `CrashReporter` plists.
    public var execName: String
    public var version: String?
    /// Ten-character Apple Team ID from the code signature; nil for ad-hoc, unsigned and Apple's own apps.
    public var teamID: String?
    /// Bundle IDs of nested helpers, login items, XPC services and app extensions (bounded depth and count; shared
    /// frameworks such as `org.sparkle-project.*` excluded).
    public var embeddedIDs: [String]
    /// `com.apple.security.application-groups` entitlement values.
    public var groupIDs: [String]
    /// launchd labels the bundle ships (`SMPrivilegedExecutables`, `Contents/Library/LaunchServices`, `LaunchDaemons`).
    public var helperLabels: [String]
    /// Absolute path of the `.app`; empty for a synthesised orphan.
    public var bundlePath: String
    public var installSource: InstallSource
    /// Homebrew cask token when `installSource == .brew`.
    public var caskToken: String?
    /// Signed by Apple (`com.apple.*` system apps). Never a target.
    public var appleSigned: Bool
    /// uid that owns the bundle directory; root (0) for most Mac App Store apps, which makes the bundle "Needs admin".
    public var bundleOwnerUID: UInt32?
    /// Mount point of the volume holding the bundle; nil for the startup volume. Feeds the "app may be on a
    /// disconnected drive" rule.
    public var volumePath: String?
    public var capturedAt: Date

    public init(bundleID: String, displayName: String, execName: String = "", version: String? = nil, teamID: String? = nil,
                embeddedIDs: [String] = [], groupIDs: [String] = [], helperLabels: [String] = [], bundlePath: String = "",
                installSource: InstallSource = .unknown, caskToken: String? = nil, appleSigned: Bool = false,
                bundleOwnerUID: UInt32? = nil, volumePath: String? = nil, capturedAt: Date = Date(timeIntervalSince1970: 0)) {
        self.bundleID = bundleID
        self.displayName = displayName
        self.execName = execName
        self.version = version
        self.teamID = teamID
        self.embeddedIDs = embeddedIDs
        self.groupIDs = groupIDs
        self.helperLabels = helperLabels
        self.bundlePath = bundlePath
        self.installSource = installSource
        self.caskToken = caskToken
        self.appleSigned = appleSigned
        self.bundleOwnerUID = bundleOwnerUID
        self.volumePath = volumePath
        self.capturedAt = capturedAt
    }

    public var id: String { bundleID }

    /// Every ID this app may legitimately own a file under: its own, its helpers' and its launchd labels. Used for the
    /// running check and the "is a live owner" check, never for matching leftovers (that is exact and per rule).
    public var allIDs: [String] { [bundleID] + embeddedIDs + helperLabels }

    /// True when the bundle sits where only an administrator can move it.
    public var bundleNeedsAdmin: Bool { bundleOwnerUID.map { $0 == 0 } ?? false }
}

/// A refusal reason for a dropped or chosen `.app` (BUILD_PLAN §5.2 `identify`). nil identity means "not usable".
public struct AppLookup: Codable, Hashable, Sendable {
    public var identity: AppIdentity?
    /// Plain English, shown under the drop zone: "That is not an app.", "macOS apps from Apple are never touched.",
    /// "Aftertaste does not remove itself.", "That app is inside another app."
    public var rejection: String?

    public init(identity: AppIdentity? = nil, rejection: String? = nil) {
        self.identity = identity
        self.rejection = rejection
    }
}

/// What the directory walk of the usual app folders found, plus what it could not see.
public struct InstalledSnapshot: Codable, Hashable, Sendable {
    public var apps: [AppIdentity]
    /// App folders that exist but could not be listed (permission, timeout).
    public var unreadableLocations: [String]
    /// True when a volume that could hold apps looks absent: the inventory remembers an app on a mount point that is not
    /// mounted now, or an unreadable `/Volumes` entry exists. Caps everything in an orphan scan at Review.
    public var volumeMayBeMissing: Bool
    public var capturedAt: Date

    public init(apps: [AppIdentity], unreadableLocations: [String] = [], volumeMayBeMissing: Bool = false, capturedAt: Date) {
        self.apps = apps
        self.unreadableLocations = unreadableLocations
        self.volumeMayBeMissing = volumeMayBeMissing
        self.capturedAt = capturedAt
    }
}

/// One app Aftertaste has seen installed (`InventoryStore`, JSON in Application Support). When the app later vanishes,
/// matching becomes exact: every ID it owned is known.
public struct InventoryRecord: Codable, Hashable, Sendable, Identifiable {
    public var identity: AppIdentity
    public var firstSeen: Date
    public var lastSeen: Date

    public init(identity: AppIdentity, firstSeen: Date, lastSeen: Date) {
        self.identity = identity
        self.firstSeen = firstSeen
        self.lastSeen = lastSeen
    }

    public var id: String { identity.bundleID }
}
