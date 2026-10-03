import Darwin
import Foundation
import XCTest
import AftertasteCore
@testable import AftertasteMac

final class GuardTests: MacTestCase {
    private func verify(_ item: ResidueItem, _ sb: Sandbox, keep: [String] = []) -> GuardVerdict {
        Guard.verify(item, home: sb.home, keep: keep)
    }

    func testAnUntouchedItemPasses() throws {
        let sb = try makeSandbox()
        XCTAssertEqual(verify(sb.cacheItem("com.example.foo"), sb), .ok)
    }

    func testChangedContentsOrStampAreRefused() throws {
        let sb = try makeSandbox()
        let item = sb.cacheItem("com.example.foo")
        sb.put("Library/Caches/com.example.foo/more.bin")          // the folder's mtime moves
        assertChanged(verify(item, sb))
        let file = sb.put("Library/Caches/com.example.file.bin", bytes: 10)
        let fileItem = sb.item(at: file, owner: "com.example.file", fileType: .file)
        XCTAssertEqual(verify(fileItem, sb), .ok)
        sb.put("Library/Caches/com.example.file.bin", bytes: 20)   // same path, different size
        assertChanged(verify(fileItem, sb))
    }

    func testAMissingItemIsGone() throws {
        let sb = try makeSandbox()
        let item = sb.cacheItem("com.example.foo")
        try FileManager.default.removeItem(atPath: item.path)
        XCTAssertEqual(verify(item, sb), .gone)
    }

    func testAnItemReplacedByALinkIsRefused() throws {
        let sb = try makeSandbox()
        let item = sb.cacheItem("com.example.foo")
        let outside = sb.root + "/outside"
        try FileManager.default.createDirectory(atPath: outside, withIntermediateDirectories: true)
        try FileManager.default.removeItem(atPath: item.path)
        try FileManager.default.createSymbolicLink(atPath: item.path, withDestinationPath: outside)
        assertChanged(verify(item, sb))
    }

    func testALinkedParentFolderIsRefused() throws {
        let sb = try makeSandbox()
        let item = sb.cacheItem("com.example.foo")
        let real = sb.root + "/realcaches"
        try FileManager.default.moveItem(atPath: sb.home + "/Library/Caches", toPath: real)
        try FileManager.default.createSymbolicLink(atPath: sb.home + "/Library/Caches", withDestinationPath: real)
        assertBlocked(verify(item, sb), .linkEscapes)
    }

    func testOutsideTheAllowedRootsIsRefused() throws {
        let sb = try makeSandbox()
        let path = sb.put("Documents/com.example.foo/x.bin")
        let item = sb.item(at: sb.home + "/Documents/com.example.foo", owner: "com.example.foo")
        XCTAssertNotEqual(verify(item, sb), .ok, path)
        let nested = sb.item(at: sb.home + "/Library/Caches/com.example.foo/deeper", owner: "com.example.foo")
        XCTAssertNotEqual(verify(nested, sb), .ok, "only immediate children of a root")
    }

    func testTheKeepListAndTheNeverListWin() throws {
        let sb = try makeSandbox()
        let item = sb.cacheItem("com.example.foo")
        XCTAssertNotEqual(verify(item, sb, keep: ["com.example.foo"]), .ok)
        let apple = sb.cacheItem("com.apple.somethingelse")
        XCTAssertNotEqual(verify(apple, sb), .ok)
        let own = sb.cacheItem("io.github.everydayopen.aftertaste")
        XCTAssertNotEqual(verify(own, sb), .ok)
    }

    func testALockedItemIsRefusedAndNeverUnlocked() throws {
        let sb = try makeSandbox()
        let item = sb.cacheItem("com.example.foo")
        XCTAssertEqual(chflags(item.path, UInt32(UF_IMMUTABLE)), 0)
        assertBlocked(verify(item, sb), .locked)
        var st = stat()
        XCTAssertEqual(lstat(item.path, &st), 0)
        XCTAssertNotEqual(st.st_flags & UInt32(UF_IMMUTABLE), 0, "still locked: Guard never clears a flag")
    }

    // MARK: restore verdicts

    private func record(trashed: String, original: String, stamp: FileStamp) -> UndoRecord {
        UndoRecord(runID: "r1", originalPath: original, trashedPath: trashed, stamp: stamp, bytes: 1, label: "Foo", tier: .high, movedAt: Date())
    }

    func testAFolderCalledDotAppInTheLibraryCanBePutBack() throws {
        let sb = try makeSandbox()
        let original = sb.put("Library/Application Support/Fake.app/data.bin")
        let trashed = sb.put(".Trash/Fake.app/data.bin")
        let stamp = try XCTUnwrap(ResidueScanner.stamp(of: Fs.parent(of: trashed)))
        try FileManager.default.removeItem(atPath: Fs.parent(of: original))
        func rec(_ kind: ResidueKind?) -> UndoRecord {
            UndoRecord(runID: "r1", originalPath: Fs.parent(of: original), trashedPath: Fs.parent(of: trashed), stamp: stamp, bytes: 1,
                       label: "Foo", tier: .medium, movedAt: Date(), kind: kind)
        }
        XCTAssertEqual(Guard.verifyRestore(rec(.yourData), home: sb.home), .ok, "its kind says it is not an app")
        XCTAssertEqual(Guard.verifyRestore(rec(nil), home: sb.home), .ok, "no kind: judged by the folder it was in, not by its name")
        if case .blocked = Guard.verifyRestore(rec(.app), home: sb.home) {} else { XCTFail("an app is only put back into an Applications folder") }
    }

    func testRestoreVerdicts() throws {
        let sb = try makeSandbox()
        let item = sb.cacheItem("com.example.foo")
        let stamp = try XCTUnwrap(item.stamp)
        // An emptied Trash entry.
        XCTAssertEqual(Guard.verifyRestore(record(trashed: sb.home + "/.Trash/nothing", original: item.path, stamp: stamp), home: sb.home), .alreadyEmptied)
        // A path that is not in a Trash folder is refused even if it exists and matches.
        if case .blocked = Guard.verifyRestore(record(trashed: item.path, original: item.path, stamp: stamp), home: sb.home) {} else { XCTFail("not a Trash location") }
        // A Trash entry that is not the recorded item.
        let other = sb.put(".Trash/com.example.foo", bytes: 5)
        XCTAssertEqual(Guard.verifyRestore(record(trashed: other, original: item.path, stamp: stamp), home: sb.home), .changedSinceTrashed)
        // Matching entry, occupied destination.
        let match = FileStamp(device: stamp.device, inode: ResidueScanner.stamp(of: other)!.inode, type: .file, size: 5, mtimeSeconds: 0)
        XCTAssertEqual(Guard.verifyRestore(record(trashed: other, original: item.path, stamp: match), home: sb.home), .destinationExists)
        // Matching entry, free destination.
        try FileManager.default.removeItem(atPath: item.path)
        XCTAssertEqual(Guard.verifyRestore(record(trashed: other, original: item.path, stamp: match), home: sb.home), .ok)
    }
}
