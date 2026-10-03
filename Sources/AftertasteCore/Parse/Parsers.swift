import Foundation

/// What Aftertaste reads from an app's `Contents/Info.plist`. Nothing else in the plist is looked at.
public struct InfoPlist: Sendable, Equatable {
    public var bundleID: String
    public var name: String
    public var execName: String
    public var version: String?
    /// Labels from `SMPrivilegedExecutables` (privileged helpers the app installs), each validated.
    public var smPrivilegedLabels: [String]
    /// `LSUIElement` or `LSBackgroundOnly`: a menu bar app, agent or helper.
    public var isUIElementOrBackground: Bool

    public init(bundleID: String, name: String, execName: String, version: String? = nil, smPrivilegedLabels: [String] = [],
                isUIElementOrBackground: Bool = false) {
        self.bundleID = bundleID
        self.name = name
        self.execName = execName
        self.version = version
        self.smPrivilegedLabels = smPrivilegedLabels
        self.isUIElementOrBackground = isUIElementOrBackground
    }
}

/// Strict reverse-DNS validation. Every ID that reaches a rule passes through here: a bundle ID with `*`, `?` or `..` would
/// otherwise turn a literal name match into a pattern (Mole's lesson).
public enum StrictBundleID {
    /// At least two labels of `[A-Za-z0-9-]`, no label empty or starting or ending with `-`, at most 155 characters.
    public static func isValid(_ s: String) -> Bool {
        guard s.utf8.count >= 3, s.utf8.count <= 155 else { return false }
        var labels = 0
        var length = 0
        var previous: UInt8 = 46
        for b in s.utf8 {
            if b == 46 {
                guard length > 0, previous != 45 else { return false }
                labels += 1
                length = 0
            } else {
                let ok = (b >= 48 && b <= 57) || (b >= 65 && b <= 90) || (b >= 97 && b <= 122) || b == 45
                guard ok else { return false }
                if length == 0 && b == 45 { return false }
                length += 1
            }
            previous = b
        }
        guard length > 0, previous != 45 else { return false }
        return labels + 1 >= 2
    }

    /// Ten uppercase letters or digits: an Apple Team ID.
    public static func isTeamID(_ s: String) -> Bool {
        s.utf8.count == 10 && s.utf8.allSatisfy { ($0 >= 48 && $0 <= 57) || ($0 >= 65 && $0 <= 90) }
    }

    /// "<id>" or "<TeamID>.<id>" (a 10-character `[A-Z0-9]` team in front of a valid ID). nil when the name is neither.
    public static func looksLikeID(_ name: String) -> (team: String?, id: String)? {
        guard isValid(name) else { return nil }
        if let dot = name.firstIndex(of: ".") {
            let head = String(name[name.startIndex..<dot])
            let rest = String(name[name.index(after: dot)...])
            if isTeamID(head), isValid(rest) { return (head, rest) }
        }
        return (nil, name)
    }
}

/// The only place property lists are parsed (pure, so every parser has a Linux fixture test). The Mac layer reads the bytes
/// (at most 1 MB per file) and hands them over; nothing here touches the disk.
public enum Parsers {
    static let maxPlistBytes = 1_048_576

    private static func dictionary(_ data: Data) -> [String: Any]? {
        guard !data.isEmpty, data.count <= maxPlistBytes else { return nil }
        guard let object = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil) else { return nil }
        return object as? [String: Any]
    }

    private static func truthy(_ v: Any?) -> Bool {
        if let b = v as? Bool { return b }
        if let n = v as? NSNumber { return n.boolValue }
        if let s = v as? String { return ["1", "yes", "true"].contains(s.lowercased()) }
        return false
    }

    private static func text(_ v: Any?) -> String? {
        guard let s = v as? String else { return nil }
        let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
        return t.isEmpty ? nil : t
    }

    /// nil unless `CFBundleIdentifier` passes `StrictBundleID`.
    public static func infoPlist(_ data: Data) -> InfoPlist? {
        guard let d = dictionary(data), let id = text(d["CFBundleIdentifier"]), StrictBundleID.isValid(id) else { return nil }
        let lastLabel = id.split(separator: ".").last.map(String.init) ?? id
        let exec = text(d["CFBundleExecutable"])
        let name = text(d["CFBundleDisplayName"]) ?? text(d["CFBundleName"]) ?? exec ?? lastLabel
        let version = text(d["CFBundleShortVersionString"]) ?? text(d["CFBundleVersion"])
        var labels: [String] = []
        if let sm = d["SMPrivilegedExecutables"] as? [String: Any] {
            labels = sm.keys.filter { StrictBundleID.isValid($0) }.sorted()
        }
        return InfoPlist(bundleID: id, name: name, execName: exec ?? name, version: version, smPrivilegedLabels: labels,
                         isUIElementOrBackground: truthy(d["LSUIElement"]) || truthy(d["LSBackgroundOnly"]))
    }

    /// `Label`, and the program it runs: `Program`, else the first of `ProgramArguments`, else `BundleProgram`.
    public static func launchd(_ data: Data) -> (label: String, program: String?)? {
        guard let d = dictionary(data), let label = text(d["Label"]), label.utf8.count <= 255,
              !label.unicodeScalars.contains(where: { $0.value < 32 || $0.value == 127 }) else { return nil }
        var program = text(d["Program"])
        if program == nil, let args = d["ProgramArguments"] as? [Any], let first = args.first { program = text(first) }
        if program == nil { program = text(d["BundleProgram"]) }
        return (label, program)
    }

    /// `MCMMetadataIdentifier` of a container's metadata plist, validated.
    public static func containerMetadata(_ data: Data) -> String? {
        guard let d = dictionary(data), let id = text(d["MCMMetadataIdentifier"]), StrictBundleID.isValid(id) else { return nil }
        return id
    }

    /// `fdesetup status`: "FileVault is On." / "FileVault is Off." / "... in progress"; anything else is unknown.
    public static func fdesetup(_ text: String) -> FileVaultState {
        let t = text.lowercased()
        if t.contains("in progress") { return .transitioning }
        if t.contains("filevault is on") { return .on }
        if t.contains("filevault is off") { return .off }
        return .unknown
    }

    /// `diskutil info -plist /`. Keys `SolidState`, `FilesystemName`/`FilesystemType`, `Internal` (VERIFY on 13, 15, 26).
    public static func diskutilInfo(_ plist: Data) -> (storage: StorageKind, fileSystem: String?, isInternal: Bool?) {
        guard let d = dictionary(plist) else { return (.unknown, nil, nil) }
        var storage = StorageKind.unknown
        if let v = d["SolidState"] as? Bool { storage = v ? .solidState : .rotational }
        let fileSystem = text(d["FilesystemName"]) ?? text(d["FilesystemType"]).map { $0.uppercased() }
        return (storage, fileSystem, d["Internal"] as? Bool)
    }

    /// `tmutil listlocalsnapshots /`: the number of "com.apple.TimeMachine.*" lines. nil when the text is an error or not the
    /// listing at all (an empty answer is not "zero snapshots").
    public static func tmutilSnapshots(_ text: String) -> Int? {
        var snapshots = 0
        var sawHeader = false
        for raw in text.split(whereSeparator: \.isNewline) {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.hasPrefix("com.apple.TimeMachine.") { snapshots += 1 }
            if line.lowercased().hasPrefix("snapshots for") { sawHeader = true }
        }
        if snapshots > 0 { return snapshots }
        return sawHeader ? 0 : nil
    }
}
