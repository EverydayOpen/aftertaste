import Darwin
import Foundation
import AftertasteCore

/// Small lstat/readdir helpers shared by the Mac layer. Nothing here follows a symlink, reads a file or changes anything.
/// Written, not compiled (BUILD_PLAN §5): every Darwin name below is VERIFY until a macOS CI run.
enum Fs {
    // Values from <sys/stat.h>, spelled out (like Materialization) so we do not depend on how the C macros import. VERIFY each.
    static let immutableOrAppendFlags: UInt32 = 0x0000_0002 | 0x0000_0004 | 0x0002_0000 | 0x0004_0000 // UF_IMMUTABLE UF_APPEND SF_IMMUTABLE SF_APPEND
    static let restrictedFlag: UInt32 = 0x0008_0000   // SF_RESTRICTED
    static let noUnlinkFlag: UInt32 = 0x0010_0000     // SF_NOUNLINK
    static let dataVaultFlag: UInt32 = 0x0000_0080    // UF_DATAVAULT (macOS-protected folders)
    static let datalessFlag: UInt32 = 0x4000_0000     // SF_DATALESS (iCloud placeholder); value VERIFY
    static var lockedFlags: UInt32 { immutableOrAppendFlags | restrictedFlag | noUnlinkFlag }

    /// `lstat`: the item itself, never its target. `err == 0` means `st` is valid.
    static func info(_ path: String) -> (st: stat, err: Int32) {
        var st = stat()
        return lstat(path, &st) == 0 ? (st, 0) : (st, errno)
    }

    static func kind(_ st: stat) -> FileType {
        switch st.st_mode & S_IFMT {
        case S_IFREG: return .file
        case S_IFDIR: return .directory
        case S_IFLNK: return .symlink
        default: return .other
        }
    }

    static func seconds(_ st: stat) -> Double { Double(st.st_mtimespec.tv_sec) + Double(st.st_mtimespec.tv_nsec) / 1_000_000_000 }

    static func stamp(_ st: stat) -> FileStamp {
        let t = kind(st)
        return FileStamp(device: Int64(st.st_dev), inode: UInt64(st.st_ino), type: t, size: t == .directory ? 0 : UInt64(max(0, st.st_size)),
                         mtimeSeconds: Int64(st.st_mtimespec.tv_sec), mtimeNanoseconds: Int64(st.st_mtimespec.tv_nsec),
                         linkCount: UInt32(st.st_nlink), allocated: t == .directory ? nil : allocated(st))
    }

    /// Allocated bytes (st_blocks * 512), the way Finder's "size on disk" counts. A dataless placeholder is 0.
    static func allocated(_ st: stat) -> UInt64 { UInt64(max(0, st.st_blocks)) * 512 }

    static func parent(of path: String) -> String { (path as NSString).deletingLastPathComponent }

    /// Fixed-size C char arrays (d_name, f_mntonname) import as tuples.
    static func string<T>(_ tuple: T) -> String {
        withUnsafeBytes(of: tuple) { raw in raw.bindMemory(to: CChar.self).baseAddress.map { String(cString: $0) } ?? "" }
    }

    /// Entry names of one folder (no "." or ".."), at most `limit` of them and for at most `seconds`; `truncated` says a
    /// budget cut the list. `err` is the errno of `opendir` (ENOENT = absent, EPERM/EACCES = protected by macOS).
    static func names(in path: String, limit: Int = .max, seconds: Double = .infinity) -> (names: [String], err: Int32, truncated: Bool) {
        guard let dir = opendir(path) else { return ([], errno, false) }
        defer { closedir(dir) }
        var out: [String] = []
        let start = DispatchTime.now().uptimeNanoseconds
        while let ent = readdir(dir) {
            let name = string(ent.pointee.d_name)
            if name == "." || name == ".." { continue }
            out.append(name)
            if out.count > limit { out.removeLast(); return (out, 0, true) }
            if out.count % 256 == 0, Double(DispatchTime.now().uptimeNanoseconds - start) / 1_000_000_000 > seconds { return (out, 0, true) }
        }
        return (out, 0, false)
    }

    /// Mount point of the volume holding `path`; nil for the startup volume (or when it cannot be told).
    static func volume(of path: String) -> String? {
        var fs = statfs()
        guard statfs(path, &fs) == 0 else { return nil }
        let mount = string(fs.f_mntonname)
        return mount == "/" || mount == "/System/Volumes/Data" ? nil : mount
    }

    static func isMountPoint(_ path: String) -> Bool {
        var fs = statfs()
        return statfs(path, &fs) == 0 && string(fs.f_mntonname) == path
    }

    static func looksLikeUUID(_ s: String) -> Bool { s.count == 36 && UUID(uuidString: s) != nil }

    /// The errno behind a Foundation error (FileManager reports Cocoa codes with a POSIX error underneath, or none).
    static func posix(_ error: Error) -> Int32? {
        let e = error as NSError
        if e.domain == NSPOSIXErrorDomain { return Int32(e.code) }
        if let u = e.userInfo[NSUnderlyingErrorKey] as? NSError, u.domain == NSPOSIXErrorDomain { return Int32(u.code) }
        guard e.domain == NSCocoaErrorDomain else { return nil }
        switch e.code {
        case 257, 513: return EACCES      // NSFileReadNoPermissionError, NSFileWriteNoPermissionError
        case 4, 260: return ENOENT        // NSFileNoSuchFileError, NSFileReadNoSuchFileError
        case 516: return EEXIST           // NSFileWriteFileExistsError
        default: return nil
        }
    }

    static func text(_ verdict: GuardVerdict) -> String {
        switch verdict {
        case .ok: return "OK."
        case .gone: return "It is already gone."
        case .changed(let why), .blocked(_, let why): return why
        }
    }
}
