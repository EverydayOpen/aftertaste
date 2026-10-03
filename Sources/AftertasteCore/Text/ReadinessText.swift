import Foundation

/// The Erase readiness panel in plain English (BUILD_PLAN §4.8.1). Every sentence is built from a fact the read-only commands
/// returned; a fact that could not be read says so and is never guessed. No scare copy, no promise.
public enum ReadinessText {
    public enum Tone: String, Sendable, Equatable { case ok, info, attention }

    public struct Line: Sendable, Equatable {
        public var id: String
        public var title: String
        public var body: String
        public var tone: Tone

        public init(id: String, title: String, body: String, tone: Tone) {
            self.id = id
            self.title = title
            self.body = body
            self.tone = tone
        }
    }

    public static let notReachable = "Not reachable by this app: unified log, FSEvents, snapshots, backups, iCloud copies, keychain items, login-item records."

    public static let trashNote = "Moving to the Trash does not erase anything; the data stays until the Trash is emptied and the space is reused."

    public static let needToBeSure = "Use Erase All Content and Settings on a Mac that offers it, or re-format an encrypted external disk. Apple explains the steps."

    public static func lines(_ f: ReadinessFacts) -> [Line] {
        var out: [Line] = []
        switch f.fileVault {
        case .on: out.append(Line(id: "filevault", title: "FileVault", body: "FileVault is on.", tone: .ok))
        case .off: out.append(Line(id: "filevault", title: "FileVault", body: "FileVault is off.", tone: .attention))
        case .transitioning: out.append(Line(id: "filevault", title: "FileVault", body: "FileVault is changing state.", tone: .info))
        case .unknown: out.append(Line(id: "filevault", title: "FileVault", body: "FileVault state could not be read.", tone: .info))
        }

        if f.isAppleSilicon == true && f.isInternal == false {
            out.append(Line(id: "encryption", title: "Encryption", body: "This Mac started from an external disk. Only its internal storage is always encrypted; "
                + "turn on FileVault for this disk.", tone: .info))
        } else if f.isAppleSilicon == true && f.isInternal == true {
            out.append(Line(id: "encryption", title: "Encryption", body: "This Mac encrypts its storage. Destroying the key "
                + "(Erase All Content and Settings, or re-formatting an encrypted external disk) is the strongest erase Apple offers.", tone: .ok))
        } else if f.isAppleSilicon == true {
            out.append(Line(id: "encryption", title: "Encryption", body: "Could not tell whether this Mac starts from its internal storage. "
                + "Where it offers Erase All Content and Settings, destroying the key that way is the strongest erase Apple offers.", tone: .info))
        } else {
            out.append(Line(id: "encryption", title: "Encryption", body: "Where this Mac offers Erase All Content and Settings, "
                + "destroying the key that way is the strongest erase Apple offers.", tone: .info))
        }

        switch f.storage {
        case .solidState:
            out.append(Line(id: "storage", title: "Storage", body: "This is flash storage, so overwriting a file may not reach every copy.", tone: .info))
        case .rotational:
            // VERIFY: whether APFS overwrites a file in place is not established (it is copy-on-write), so only a non-APFS disk says "may reach".
            let hfs = f.fileSystem?.lowercased().contains("hfs") ?? false
            out.append(Line(id: "storage", title: "Storage", body: hfs
                ? "This disk spins; overwriting a file may reach the file's own blocks, but not copies in snapshots or backups."
                : "This disk spins, but overwriting a file may not reach its old blocks, and never reaches copies in snapshots or backups.", tone: .info))
        case .unknown:
            out.append(Line(id: "storage", title: "Storage", body: "The storage type could not be read.", tone: .info))
        }

        switch f.localSnapshotCount {
        case .some(let n) where n > 0:
            let verb = n == 1 ? "exists" : "exist"
            out.append(Line(id: "snapshots", title: "Local snapshots",
                            body: "\(Format.count(n, "local snapshot")) \(verb) that may still hold these files.", tone: .attention))
        case .some:
            // VERIFY: the count is `tmutil listlocalsnapshots /`, which names Time Machine snapshots only. Other APFS snapshots are not counted.
            out.append(Line(id: "snapshots", title: "Local snapshots", body: "No Time Machine local snapshots were found. Other kinds of snapshot are not counted.", tone: .info))
        case .none:
            out.append(Line(id: "snapshots", title: "Local snapshots", body: "Local snapshots could not be listed.", tone: .info))
        }

        out.append(Line(id: "trash", title: "The Trash", body: trashNote, tone: .info))
        out.append(Line(id: "notReachable", title: "Out of reach", body: notReachable, tone: .info))
        out.append(Line(id: "needToBeSure", title: "Need to be sure?", body: needToBeSure, tone: .info))
        return out
    }

    /// Who could read old data, and whether anything in this app helps. Plain sentences, no promises.
    public static func threats() -> [(who: String, answer: String)] {
        [
            ("Someone using your unlocked Mac", "They can open anything you can open, including the Trash and files you moved there."),
            ("Someone with your Mac but not your password", "With FileVault on, reading the disk needs your login password or recovery key. With FileVault off, a Mac that encrypts its storage ties the key to the hardware only: anyone who can sign in sees everything."),
            ("The next owner of your Mac", "Use Erase All Content and Settings where this Mac offers it (otherwise erase the disk from Recovery) before handing it on. Moving files to the Trash does not remove them."),
            ("Time Machine and local snapshots", "Copies there are outside what this app can reach. The count above covers Time Machine local snapshots only; other snapshots and backups are not counted."),
            ("iCloud", "Copies in iCloud are managed in System Settings, not here."),
        ]
    }
}
