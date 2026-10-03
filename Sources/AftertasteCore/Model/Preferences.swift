import Foundation

/// The few things the user can change. Named `Preferences` so it never collides with SwiftUI's `Settings` scene. Stored as
/// one JSON blob in UserDefaults (`App/AppModel.swift` is the only file that touches UserDefaults). Nothing here can make
/// Aftertaste touch more than the rules allow: `keepList` only adds to the never-list. There is no overwrite switch in v1.
public struct Preferences: Codable, Hashable, Sendable {
    /// Extra things never to touch: bundle IDs ("com.example.notes") or absolute path prefixes. Only ever adds to `NeverList`.
    public var keepList: [String]
    /// Replace app names and bundle IDs with "App 1", "App 2" in exports and on the card. (The export sheet pre-ticks this
    /// whenever a report covers more than one app.)
    public var hideAppNamesInExports: Bool
    /// Show the optional menu bar item. Off by default; the window is the app.
    public var showMenuBarItem: Bool
    public var hasSeenFirstRun: Bool

    public init(keepList: [String] = [], hideAppNamesInExports: Bool = false, showMenuBarItem: Bool = false,
                hasSeenFirstRun: Bool = false) {
        self.keepList = keepList
        self.hideAppNamesInExports = hideAppNamesInExports
        self.showMenuBarItem = showMenuBarItem
        self.hasSeenFirstRun = hasSeenFirstRun
    }

    /// Every field is optional in a stored blob, so adding one later never wipes the user's keep-list.
    public init(from d: Decoder) throws {
        let c = try d.container(keyedBy: CodingKeys.self)
        let def = Preferences()
        keepList = try c.decodeIfPresent([String].self, forKey: .keepList) ?? def.keepList
        hideAppNamesInExports = try c.decodeIfPresent(Bool.self, forKey: .hideAppNamesInExports) ?? def.hideAppNamesInExports
        showMenuBarItem = try c.decodeIfPresent(Bool.self, forKey: .showMenuBarItem) ?? def.showMenuBarItem
        hasSeenFirstRun = try c.decodeIfPresent(Bool.self, forKey: .hasSeenFirstRun) ?? def.hasSeenFirstRun
    }

    public static let `default` = Preferences()
}
