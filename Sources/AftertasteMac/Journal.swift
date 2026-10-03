import Darwin
import Foundation
import AftertasteCore

/// The write-ahead journal (BUILD_PLAN §3 S15, §5.7): JSONL, append-only, one file per month, 0600 in a 0700 folder under
/// `~/Library/Application Support/Aftertaste` (never inside iCloud). An `intent` line is written and fsync'd before every
/// move, a `result` line after. If a line cannot be written the caller must not move anything (fail closed). It holds
/// home-relative paths because Undo needs them; it never leaves the Mac. The only file with raw `write(2)`.
enum Journal {
    static func directory(home: String) -> String { LibraryRoot.applicationSupport.path(home: home) + "/Aftertaste" }

    /// Creates the folder if needed (0700). An existing one must be a real directory of ours with mode 0700: never followed
    /// through a symlink, never chmod'ed back into shape (a wrong mode means false).
    static func prepare(home: String) -> Bool {
        let dir = directory(home: home)
        var st = stat()
        if lstat(dir, &st) != 0 {
            guard errno == ENOENT,
                  (try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true,
                                                            attributes: [.posixPermissions: 0o700])) != nil else { return false }
        }
        return isOurs(dir)
    }

    /// Starts a run: prepares the folder, opens this month's file and writes the run line. False = nothing may move.
    static func begin(home: String, runID: String, verb: ActivityVerb, summary: String, at: Date) -> Bool {
        guard prepare(home: home) else { return false }
        return append(home: home, ActivityEntry(timestamp: at, runID: runID, verb: .run, phase: .intent, label: summary, detail: verb.rawValue))
    }

    static func intent(home: String, entry: ActivityEntry) -> Bool { append(home: home, entry) }

    static func result(home: String, entry: ActivityEntry) -> Bool { append(home: home, entry) }

    static func end(home: String, runID: String, verb: ActivityVerb, detail: String?, at: Date) -> Bool {
        append(home: home, ActivityEntry(timestamp: at, runID: runID, verb: .run, phase: .result, label: verb.rawValue, detail: detail))
    }

    /// Every journal-*.jsonl, oldest first. Missing, foreign or unreadable = nothing. ponytail: whole files in memory;
    /// paginate if a month ever reaches tens of megabytes (the cap below skips such a file instead).
    static func loadAll(home: String) -> [ActivityEntry] {
        let dir = directory(home: home)
        guard isOurs(dir), let names = try? FileManager.default.contentsOfDirectory(atPath: dir) else { return [] }
        var out: [ActivityEntry] = []
        for name in names.filter(ActivityLog.isJournalFile).sorted() {
            let path = dir + "/" + name
            var st = stat()
            guard lstat(path, &st) == 0, (st.st_mode & S_IFMT) == S_IFREG, st.st_uid == getuid(), st.st_size < 64 << 20,
                  let text = try? String(contentsOfFile: path, encoding: .utf8) else { continue }
            out += ActivityLog.decodeAll(text).entries
        }
        return out
    }

    // MARK: -

    private static func isOurs(_ dir: String) -> Bool {
        var st = stat()
        return lstat(dir, &st) == 0 && (st.st_mode & S_IFMT) == S_IFDIR && st.st_uid == getuid() && (st.st_mode & 0o777) == 0o700
    }

    /// One line, one write(2) loop, then fsync. O_NOFOLLOW refuses a symlinked file, O_NONBLOCK makes a planted FIFO fail
    /// instead of hanging, and the opened file itself is checked (regular, ours, 0600). Opens and closes per line: a
    /// handful of lines per item, and nothing stays open between them.
    private static func append(home: String, _ entry: ActivityEntry) -> Bool {
        var e = entry
        e.path = PathText.tilde(e.path, home: home)
        e.trashedPath = e.trashedPath.map { PathText.tilde($0, home: home) }
        let dir = directory(home: home)
        guard isOurs(dir) else { return false }
        let fd = open(dir + "/" + ActivityLog.fileName(for: e.timestamp), O_WRONLY | O_APPEND | O_CREAT | O_NOFOLLOW | O_NONBLOCK | O_CLOEXEC, 0o600)
        guard fd >= 0 else { return false }
        defer { close(fd) }
        var st = stat()
        guard fstat(fd, &st) == 0, (st.st_mode & S_IFMT) == S_IFREG, st.st_uid == getuid(), (st.st_mode & 0o777) == 0o600 else { return false }
        let bytes = Array((ActivityLog.encode(e) + "\n").utf8)
        var done = 0
        while done < bytes.count {
            let n = bytes[done...].withUnsafeBytes { write(fd, $0.baseAddress, $0.count) }
            if n < 0 {
                if errno == EINTR { continue }
                return false
            }
            done += n
        }
        // fsync, not F_FULLFSYNC (reserved, S17): a power cut can lose the last line; a crash of this process cannot.
        return fsync(fd) == 0
    }
}
