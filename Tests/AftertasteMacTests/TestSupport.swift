import Darwin
import Foundation
import XCTest
import AftertasteCore
@testable import AftertasteMac

/// A fake HOME for one test, under /Users/Shared (a path macOS never rewrites: `realpath` of a /var/folders temp dir is
/// /private/var/..., which the never-list rightly refuses). Nothing here touches the real home, except that `trashItem`
/// puts what it moves into the real Trash; the sandbox removes those entries again.
final class Sandbox {
    let root: String
    var home: String { root + "/home" }
    private var processes: [Process] = []
    private var trashed: [String] = []

    init() throws {
        root = "/Users/Shared/AftertasteTests-" + UUID().uuidString
        for sub in ["Library/Preferences", "Library/Caches", "Library/Application Support", "Library/Saved Application State",
                    "Library/HTTPStorages", "Library/LaunchAgents", "Library/Logs", "Applications"] {
            try FileManager.default.createDirectory(atPath: home + "/" + sub, withIntermediateDirectories: true)
        }
    }

    func cleanup() {
        for p in processes where p.isRunning { p.terminate(); p.waitUntilExit() }
        for t in trashed { try? FileManager.default.removeItem(atPath: t) }
        unlock(root)
        try? FileManager.default.removeItem(atPath: root)
    }

    private func unlock(_ path: String) {
        lchflags(path, 0)
        var st = stat()
        guard lstat(path, &st) == 0, (st.st_mode & S_IFMT) == S_IFDIR else { return }
        chmod(path, 0o700)
        for name in (try? FileManager.default.contentsOfDirectory(atPath: path)) ?? [] { unlock(path + "/" + name) }
    }

    func noteTrashed(_ outcome: TrashOutcome) { trashed += outcome.results.compactMap(\.trashedPath) }

    // MARK: building the fake library

    @discardableResult
    func put(_ rel: String, bytes: Int = 100) -> String {
        let path = home + "/" + rel
        try? FileManager.default.createDirectory(atPath: Fs.parent(of: path), withIntermediateDirectories: true)
        FileManager.default.createFile(atPath: path, contents: Data(repeating: 0x41, count: bytes))
        return path
    }

    /// `<folder>/<name>.app` with a real Info.plist, written the way Xcode would (tests may use PropertyListSerialization).
    func makeApp(_ name: String, id: String, exec: String? = nil, in folder: String? = nil, extra: [String: Any] = [:]) throws -> String {
        let app = (folder ?? home + "/Applications") + "/" + name + ".app"
        try FileManager.default.createDirectory(atPath: app + "/Contents/MacOS", withIntermediateDirectories: true)
        var plist: [String: Any] = ["CFBundleIdentifier": id, "CFBundleName": name, "CFBundleExecutable": exec ?? name,
                                    "CFBundlePackageType": "APPL", "CFBundleShortVersionString": "1.0"]
        plist.merge(extra) { _, new in new }
        let data = try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
        try data.write(to: URL(fileURLWithPath: app + "/Contents/Info.plist"))
        return app
    }

    @discardableResult
    func putLaunchAgent(label: String, program: String?) throws -> String {
        var plist: [String: Any] = ["Label": label, "RunAtLoad": true]
        if let program { plist["Program"] = program }
        let path = home + "/Library/LaunchAgents/" + label + ".plist"
        try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0).write(to: URL(fileURLWithPath: path))
        return path
    }

    func age(_ path: String, days: Double) {
        try? FileManager.default.setAttributes([.modificationDate: Date(timeIntervalSinceNow: -days * 86_400)], ofItemAtPath: path)
    }

    /// The cache folder of `id` as a High item the way a scan would have produced it (stamp taken now).
    func cacheItem(_ id: String, owner: String? = nil) -> ResidueItem {
        put("Library/Caches/\(id)/data.bin", bytes: 1000)
        return item(at: home + "/Library/Caches/" + id, owner: owner ?? id)
    }

    func item(at path: String, owner: String, ruleID: String = "U3", root: LibraryRoot? = .caches, kind: ResidueKind = .cache,
              fileType: FileType = .directory, tier: Tier = .high) -> ResidueItem {
        ResidueItem(path: path, ownerID: owner, ruleID: ruleID, root: root, kind: kind, fileType: fileType, tier: tier, size: 1000,
                    sizeState: .measured, fileCount: 1, stamp: ResidueScanner.stamp(of: path), why: "Test item.")
    }

    /// Without `owners`, one is made up for each item's owner ID (the executor refuses an item whose owner is not in the plan).
    func plan(_ items: [ResidueItem], owners: [AppIdentity]? = nil, kind: ScanKind = .orphans, acknowledged: Bool = false) -> TrashPlan {
        var made: [AppIdentity] = []
        for id in items.map(\.ownerID) where !made.contains(where: { $0.bundleID == id }) {
            made.append(AppIdentity(bundleID: id, displayName: id, capturedAt: Date()))
        }
        return TrashPlan(runID: "20261003T101500Z-" + String(UUID().uuidString.prefix(6)).lowercased(), createdAt: Date(), kind: kind,
                         owners: owners ?? made, items: items, acknowledgedMedium: acknowledged)
    }

    /// `installedNow` defaults to "nothing is installed" so a test never depends on what Launch Services knows about the fake apps.
    func trash(_ plan: TrashPlan, keep: [String] = [], installedNow: (AppIdentity, String?) -> Bool = { _, _ in false },
               progress: @escaping @Sendable (ItemOutcome) -> Void = { _ in }) async -> TrashOutcome {
        let outcome = await Trasher.run(plan, home: home, keep: keep, now: { Date() }, installedNow: installedNow, progress: progress)
        noteTrashed(outcome)
        return outcome
    }

    /// Runs a copy of the fixture (or /bin/sleep) as `path`, so something executes from inside a fake bundle or folder.
    func launch(executableAt path: String) throws -> Process {
        let fixture = Bundle(for: Sandbox.self).bundleURL.deletingLastPathComponent().appendingPathComponent("AftertasteFixture").path
        let source = FileManager.default.isExecutableFile(atPath: fixture) ? fixture : "/bin/sleep"
        try FileManager.default.createDirectory(atPath: Fs.parent(of: path), withIntermediateDirectories: true)
        try FileManager.default.copyItem(atPath: source, toPath: path)
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = ["120"]
        try process.run()
        processes.append(process)
        // A copied system binary does not run on Apple silicon (arm64e outside the system volume): skip rather than fail.
        Thread.sleep(forTimeInterval: 0.3)
        guard process.isRunning else { throw XCTSkip("could not start a helper process from \(source)") }
        return process
    }

    func exists(_ path: String) -> Bool {
        var st = stat()
        return lstat(path, &st) == 0
    }
}

class MacTestCase: XCTestCase {
    func makeSandbox() throws -> Sandbox {
        let sb = try Sandbox()
        addTeardownBlock { sb.cleanup() }
        return sb
    }

    /// `trashItem` may not work in a headless runner session (BUILD_PLAN §12, VERIFY): skip with the reason rather than fail.
    func requireTrash(_ outcome: TrashOutcome) throws {
        if let first = outcome.results.first, first.status == .failed || first.status == .protectedByMacOS {
            throw XCTSkip("trashItem is not available in this session: \(first.detail ?? "no detail")")
        }
    }

    func fileMode(_ path: String) -> UInt16 {
        var st = stat()
        XCTAssertEqual(lstat(path, &st), 0)
        return st.st_mode & 0o777
    }

    func assertChanged(_ v: GuardVerdict, file: StaticString = #filePath, line: UInt = #line) {
        if case .changed = v { return }
        XCTFail("expected .changed, got \(v)", file: file, line: line)
    }

    func assertBlocked(_ v: GuardVerdict, _ reason: BlockReason, file: StaticString = #filePath, line: UInt = #line) {
        if case .blocked(let r, _) = v, r == reason { return }
        XCTFail("expected .blocked(\(reason)), got \(v)", file: file, line: line)
    }
}
