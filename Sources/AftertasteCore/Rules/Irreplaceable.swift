import Foundation

/// "May be your only copy": paths and sizes that suggest data a person cannot regenerate. The test errs toward asking, so
/// it is a plain case-insensitive contains. A hit forces Review (never preselected, one item at a time).
public enum Irreplaceable {
    public static let tokens: [String] = [
        "wallet", "vault", "keychain", "keystore", ".kdbx", "1password", "bitwarden", "keepass", "backup", "mobilesync",
        ".photoslibrary", "messages", "mail", "parallels", ".pvm", ".utm", ".vmdk", ".vdi", "docker", "library/logic", "ableton",
        "steam", "saves", "documents",
    ]

    /// Five gigabytes (decimal, as Finder shows sizes).
    public static let sizeThreshold: UInt64 = 5_000_000_000

    /// `path` is the entry name (or a home-relative path), never the absolute one, so a user called "mailer" or a root folder
    /// called "Recent Documents" does not trip the test.
    public static func looksIrreplaceable(path: String, bytes: UInt64) -> Bool {
        if bytes > sizeThreshold { return true }
        let p = path.lowercased()
        return tokens.contains { p.contains($0) }
    }
}
