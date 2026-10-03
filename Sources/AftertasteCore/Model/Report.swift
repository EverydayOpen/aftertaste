import Foundation

/// One row of the exported report. `path` is already redacted (`~` for home; app name/ID replaced when names are hidden).
public struct TraceRow: Codable, Hashable, Sendable {
    public var path: String
    public var kind: ResidueKind
    public var tier: Tier
    public var bytes: UInt64
    /// The walk was cut short: `bytes` is a floor ("at least").
    public var lowerBound: Bool
    public var why: String

    public init(path: String, kind: ResidueKind, tier: Tier, bytes: UInt64, lowerBound: Bool = false, why: String) {
        self.path = path
        self.kind = kind
        self.tier = tier
        self.bytes = bytes
        self.lowerBound = lowerBound
        self.why = why
    }
}

/// What was found for one app. Counts are measured on this Mac during this scan; nothing is estimated.
public struct TraceApp: Codable, Hashable, Sendable {
    /// The app's name, or "App 1", "App 2" when names are hidden.
    public var label: String
    public var version: String?
    /// Nil when names are hidden.
    public var bundleID: String?
    public var files: Int
    public var bytes: UInt64
    /// `files` and `bytes` are floors: some item was only partly walked or not measured at all.
    public var lowerBound: Bool
    /// Items whose size was not measured (protected folders, iCloud placeholders, system rows); they add 0 to the totals.
    public var unmeasuredCount: Int
    public var launchAgents: Int
    /// System launch daemons: not launch agents, and counted apart from the privileged helper that registers one.
    public var launchDaemons: Int
    public var privilegedHelpers: Int
    /// What the app left behind, counted the way the preview's sentence counts it (`ResidueGroup.leftBehind`): the one item count the
    /// header, the card and the file share. It does not depend on `includeRows`, so a report without rows still has it.
    public var itemCount: Int
    public var rows: [TraceRow]

    public init(label: String, version: String? = nil, bundleID: String? = nil, files: Int, bytes: UInt64, lowerBound: Bool = false,
                unmeasuredCount: Int = 0, launchAgents: Int = 0, launchDaemons: Int = 0, privilegedHelpers: Int = 0, itemCount: Int = 0,
                rows: [TraceRow] = []) {
        self.label = label
        self.version = version
        self.bundleID = bundleID
        self.files = files
        self.bytes = bytes
        self.lowerBound = lowerBound
        self.unmeasuredCount = unmeasuredCount
        self.launchAgents = launchAgents
        self.launchDaemons = launchDaemons
        self.privilegedHelpers = privilegedHelpers
        self.itemCount = itemCount
        self.rows = rows
    }
}

/// The Trace Report (APP4 §2.4): the data behind the Markdown/JSON export and the card. A list of what was found in the
/// places listed, not proof that anything was erased. Never contains "recoverable", "erased" or any banned phrase.
public struct TraceReport: Codable, Hashable, Sendable {
    public var generatedAt: Date
    public var kind: ScanKind
    public var apps: [TraceApp]
    /// What was looked at and what stopped short, as numbers (no paths).
    public var coverage: CoverageFacts
    /// Places that could not be read, by display name (no paths).
    public var unreadablePlaces: [String]
    public var osVersion: String
    public var appVersion: String
    /// Names were replaced by "App 1" ... and bundle IDs omitted.
    public var namesHidden: Bool
    public var isSample: Bool

    public init(generatedAt: Date, kind: ScanKind, apps: [TraceApp], coverage: CoverageFacts, unreadablePlaces: [String] = [],
                osVersion: String, appVersion: String = "", namesHidden: Bool = false, isSample: Bool = false) {
        self.generatedAt = generatedAt
        self.kind = kind
        self.apps = apps
        self.coverage = coverage
        self.unreadablePlaces = unreadablePlaces
        self.osVersion = osVersion
        self.appVersion = appVersion
        self.namesHidden = namesHidden
        self.isSample = isSample
    }

    public var files: Int { apps.reduce(0) { $0 + $1.files } }
    public var bytes: UInt64 { apps.reduce(0) { $0 + $1.bytes } }
    public var launchAgents: Int { apps.reduce(0) { $0 + $1.launchAgents } }
    public var launchDaemons: Int { apps.reduce(0) { $0 + $1.launchDaemons } }
    public var privilegedHelpers: Int { apps.reduce(0) { $0 + $1.privilegedHelpers } }
    public var itemCount: Int { apps.reduce(0) { $0 + $1.itemCount } }
    public var lowerBound: Bool { apps.contains(where: \.lowerBound) }
    public var unmeasuredCount: Int { apps.reduce(0) { $0 + $1.unmeasuredCount } }
}

/// The data behind the 1200x630 card (`TraceReportText.card`). Every number is measured; lines with a zero count are omitted
/// by the view; no keychain line; no "recoverable" or "erased" wording (the card is the before screen).
public struct ShareCard: Codable, Hashable, Sendable {
    /// "Zoom 6.x" for one app, "3 removed apps" for several, "App 1" when names are hidden.
    public var subject: String
    public var files: Int
    public var bytes: UInt64
    /// `files` and `bytes` are floors (see `TraceApp.lowerBound`); the card says "at least".
    public var lowerBound: Bool
    public var unmeasuredCount: Int
    public var launchAgents: Int
    public var launchDaemons: Int
    public var privilegedHelpers: Int
    public var coverage: CoverageFacts
    public var osVersion: String
    public var scannedAt: Date
    /// Draws the "Sample data" watermark. Always true in demo mode.
    public var isSample: Bool

    public init(subject: String, files: Int, bytes: UInt64, lowerBound: Bool = false, unmeasuredCount: Int = 0, launchAgents: Int = 0,
                launchDaemons: Int = 0, privilegedHelpers: Int = 0, coverage: CoverageFacts, osVersion: String, scannedAt: Date, isSample: Bool = false) {
        self.subject = subject
        self.files = files
        self.bytes = bytes
        self.lowerBound = lowerBound
        self.unmeasuredCount = unmeasuredCount
        self.launchAgents = launchAgents
        self.launchDaemons = launchDaemons
        self.privilegedHelpers = privilegedHelpers
        self.coverage = coverage
        self.osVersion = osVersion
        self.scannedAt = scannedAt
        self.isSample = isSample
    }
}
