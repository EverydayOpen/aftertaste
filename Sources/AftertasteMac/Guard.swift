import Darwin
import Foundation
import AftertasteCore

/// The Mac half of S4/S5 (BUILD_PLAN §5.4): re-reads everything from the filesystem right now and caches nothing. The pure
/// half, `GuardPolicy.check`, is Core's and is tested on Linux. Internal on purpose: only `Trasher` and `UndoStore` ask.
enum Guard {
    /// May this item still be moved, right now? Anything but `.ok` means the item is not touched.
    static func verify(_ item: ResidueItem, home: String, keep: [String]) -> GuardVerdict {
        // 1. The parent, canonicalised: a symlinked parent resolves somewhere that is not an allowed root.
        let parent = Fs.parent(of: item.path)
        guard let real = realpath(parent, nil) else {
            let e = errno
            if e == ENOENT { return .gone }
            return e == EPERM || e == EACCES ? .blocked(.protectedByMacOS, "macOS does not let Aftertaste look in this folder.")
                                              : .changed("The folder could not be resolved (error \(e)).")
        }
        let canonical = String(cString: real)
        free(real)
        if let verdict = GuardPolicy.check(path: item.path, canonicalParent: canonical, home: home, keep: keep,
                                           isAppBundle: item.ruleID == "APP") { return verdict }

        // 2. The leaf, never followed: a symlink is the item.
        var st = stat()
        guard lstat(item.path, &st) == 0 else {
            let e = errno
            if e == ENOENT { return .gone }
            return e == EPERM || e == EACCES ? .blocked(.protectedByMacOS, "macOS does not let Aftertaste look at this item.")
                                              : .changed("The item could not be looked at, error \(e).")
        }
        guard Fs.kind(st) == item.fileType else { return .changed("It is no longer the same kind of item.") }

        // 3. Same device as its parent (not a mount point), on a local volume.
        var pst = stat()
        guard lstat(canonical, &pst) == 0 else { return .changed("The folder could not be read.") }
        if st.st_dev != pst.st_dev {
            return .blocked(Fs.kind(st) == .directory ? .mountPoint : .otherVolume, "It is on another volume than its folder.")
        }
        var fs = statfs()
        guard statfs(canonical, &fs) == 0 else { return .changed("The volume could not be read.") }
        guard (fs.f_flags & UInt32(MNT_LOCAL)) != 0 else { return .blocked(.notLocalVolume, "It is on a network or other non-local volume.") }

        // 4. Flags: locked and protected items are listed, never unlocked. Placeholders stay in iCloud.
        if (st.st_flags & Fs.dataVaultFlag) != 0 { return .blocked(.protectedByMacOS, "macOS protects this folder.") }
        if (st.st_flags & Fs.datalessFlag) != 0 { return .blocked(.dataless, "It is stored in iCloud and not downloaded.") }
        if (st.st_flags & Fs.lockedFlags) != 0 { return .blocked(.locked, "It is locked. Aftertaste does not unlock things.") }

        // 5. Ours to move (not root's, not another account's).
        guard st.st_uid == getuid() else { return .blocked(.needsAdmin, "It belongs to another account. Needs your administrator.") }

        // 6. Exactly what the user reviewed.
        guard let scanned = item.stamp else { return .changed("It was not measured, so it is not moved.") }
        guard Stamps.same(scanned, Fs.stamp(st)) else { return .changed("It changed since you reviewed it.") }
        return .ok
    }

    enum RestoreVerdict: Equatable { case ok, alreadyEmptied, trashUnreadable(Int32), changedSinceTrashed, destinationExists, blocked(String) }

    /// Undo: the Trash entry exists and still is the item the journal recorded (same device, inode, type); the original's
    /// folder exists inside an allowed root on a local volume, on the same disk as the Trash entry (so the move is a rename,
    /// never a copy); and nothing is at the original path (never overwritten).
    static func verifyRestore(_ record: UndoRecord, home: String) -> RestoreVerdict {
        var tst = stat()
        guard lstat(record.trashedPath, &tst) == 0 else {
            let e = errno
            if e == ENOENT { return .alreadyEmptied }
            return e == EPERM || e == EACCES ? .trashUnreadable(e) : .blocked("The Trash entry could not be looked at, error \(e).")
        }
        guard record.trashedPath.contains("/.Trash/") || record.trashedPath.contains("/.Trashes/") else {
            return .blocked("That is not a Trash location.")
        }
        guard Int64(tst.st_dev) == record.stamp.device, UInt64(tst.st_ino) == record.stamp.inode, Fs.kind(tst) == record.stamp.type else {
            return .changedSinceTrashed
        }

        let parent = Fs.parent(of: record.originalPath)
        guard let real = realpath(parent, nil) else { return .blocked("The original folder is no longer there.") }
        let canonical = String(cString: real)
        free(real)
        // A library folder may be called "Foo.app"; only a recorded app (or, for old records, a bundle in an Applications folder) is one.
        let isApp = record.kind.map { $0 == .app }
            ?? (record.originalPath.hasSuffix(".app") && record.stamp.type == .directory && GuardPolicy.isInAppFolder(GuardPolicy.normalize(parent), home: home))
        if let verdict = GuardPolicy.check(path: record.originalPath, canonicalParent: canonical, home: home, keep: [], isAppBundle: isApp) {
            return .blocked(Fs.text(verdict))
        }
        var pst = stat()
        guard lstat(canonical, &pst) == 0 else { return .blocked("The original folder could not be read.") }
        if pst.st_dev != tst.st_dev { return .blocked("The Trash is on another disk than the original folder. Drag it back in Finder.") }
        var fs = statfs()
        guard statfs(canonical, &fs) == 0, (fs.f_flags & UInt32(MNT_LOCAL)) != 0 else { return .blocked("The original folder is not on a local volume.") }

        var ost = stat()
        if lstat(record.originalPath, &ost) == 0 { return .destinationExists }
        return errno == ENOENT ? .ok : .blocked("The original location could not be read.")
    }
}
