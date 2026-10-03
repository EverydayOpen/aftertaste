import Darwin
import Foundation
import XCTest
import AftertasteCore
@testable import AftertasteMac

final class SystemTests: MacTestCase {
    // MARK: running

    func testAProcessRunningFromInsideABundleIsSeen() throws {
        let sb = try makeSandbox()
        let app = try sb.makeApp("Foo", id: "com.example.foo")
        let exec = app + "/Contents/MacOS/Foo"
        let process = try sb.launch(executableAt: exec)
        let owner = AppIdentity(bundleID: "com.example.foo", displayName: "Foo", bundlePath: app)
        let item = sb.home + "/Library/Caches/com.example.foo"

        let running = RunningApps.snapshot()
        XCTAssertTrue(running.readable)
        XCTAssertTrue(running.executablePaths.contains(exec), "VERIFY: libproc reports the path the process was started from")
        XCTAssertEqual(RunningCheck.state(owner: owner, itemPath: item, snapshot: running), .running)

        process.terminate()
        process.waitUntilExit()
        XCTAssertEqual(RunningCheck.state(owner: owner, itemPath: item, snapshot: RunningApps.snapshot()), .notRunning)
    }

    func testAProcessRunningFromInsideALeftoverFolderBlocksIt() throws {
        let sb = try makeSandbox()
        let folder = sb.home + "/Library/Application Support/com.example.foo"
        let process = try sb.launch(executableAt: folder + "/bin/helper")
        let state = RunningCheck.state(owner: nil, itemPath: folder, snapshot: RunningApps.snapshot())
        XCTAssertEqual(state, .running)
        process.terminate()
        process.waitUntilExit()
    }

    func testTheProcessListIsReadable() {
        let paths = Processes.executablePaths()
        XCTAssertNotNil(paths)
        XCTAssertFalse(paths?.isEmpty ?? true)
    }

    // MARK: installed apps

    func testDiscoversAppsOneNestedLevelDeepAndNotApple() throws {
        let sb = try makeSandbox()
        _ = try sb.makeApp("Top", id: "com.example.top")
        _ = try sb.makeApp("Suite", id: "com.example.suite", in: sb.home + "/Applications/Vendor Suite")
        _ = try sb.makeApp("TooDeep", id: "com.example.toodeep", in: sb.home + "/Applications/Vendor Suite/More")
        let outer = try sb.makeApp("Outer", id: "com.example.outer")
        _ = try sb.makeApp("Inner", id: "com.example.inner", in: outer + "/Contents/Resources")
        _ = try sb.makeApp("FakeApple", id: "com.apple.fakeapple")

        let snapshot = InstalledApps.discover(home: sb.home, inventory: [], now: Date())
        let ids = Set(snapshot.apps.map(\.bundleID))
        XCTAssertTrue(ids.isSuperset(of: ["com.example.top", "com.example.suite", "com.example.outer"]))
        XCTAssertFalse(ids.contains("com.example.toodeep"))
        XCTAssertFalse(ids.contains("com.example.inner"))
        XCTAssertFalse(ids.contains("com.apple.fakeapple"), "Apple's apps are never targets and never listed")
        XCTAssertFalse(snapshot.unreadableLocations.contains(sb.home + "/Applications"))
    }

    func testAnInstalledAppWithAnUnusualBundleIDStillJoinsTheLiveIndex() throws {
        let sb = try makeSandbox()
        _ = try sb.makeApp("Odd", id: "odd_app")
        _ = try sb.makeApp("Odder", id: "com.example.odd_app")
        let broken = try sb.makeApp("Broken", id: "com.example.broken", extra: ["CFBundleIdentifier": "bad/id"])
        let empty = sb.home + "/Applications/Empty.app"
        try FileManager.default.createDirectory(atPath: empty + "/Contents", withIntermediateDirectories: true)

        let snapshot = InstalledApps.discover(home: sb.home, inventory: [], now: Date())
        let ids = Set(snapshot.apps.map(\.bundleID))
        XCTAssertTrue(ids.isSuperset(of: ["odd_app", "com.example.odd_app"]), "its folders stay protected")
        XCTAssertNotNil(Identity.read(appURL: URL(fileURLWithPath: sb.home + "/Applications/Odd.app"), now: Date()).rejection, "but it is never a target")
        XCTAssertTrue(snapshot.unreadableLocations.contains(broken), "an unusable bundle is reported, so the scan is not called complete")
        XCTAssertFalse(snapshot.unreadableLocations.contains(empty), "a folder with no Info.plist is not an app")
    }

    func testAnAppRememberedOnAnUnmountedVolumeMeansAVolumeMayBeMissing() throws {
        let sb = try makeSandbox()
        let gone = AppIdentity(bundleID: "com.example.external", displayName: "External", bundlePath: "/Volumes/NoSuchDrive-\(UUID().uuidString)/Applications/E.app",
                               volumePath: "/Volumes/NoSuchDrive-\(UUID().uuidString)")
        let record = InventoryRecord(identity: gone, firstSeen: Date(), lastSeen: Date())
        XCTAssertTrue(InstalledApps.discover(home: sb.home, inventory: [record], now: Date()).volumeMayBeMissing)
        XCTAssertFalse(InstalledApps.discover(home: sb.home, inventory: [], now: Date()).unreadableLocations.contains(sb.home + "/Applications"))
    }

    // MARK: readiness and process policy

    func testTheProbeRunsExactlyTheThreeReadOnlyCommands() {
        let lines = ReadinessProbe.Command.allCases.map { ([$0.path] + $0.arguments).joined(separator: " ") }
        XCTAssertEqual(lines, ["/usr/bin/fdesetup status", "/usr/sbin/diskutil info -plist /", "/usr/bin/tmutil listlocalsnapshots /"])
    }

    func testReadinessFactsNameWhatFailed() async {
        let facts = await ReadinessProbe.facts(now: Date(), macOSVersion: "26.0")
        XCTAssertEqual(facts.macOSVersion, "26.0")
        XCTAssertTrue(Set(facts.failedProbes).isSubset(of: ["fdesetup", "diskutil", "tmutil"]))
        if !facts.failedProbes.contains("fdesetup") { XCTAssertNotEqual(facts.fileVault, .unknown) }
        if !facts.failedProbes.contains("tmutil") { XCTAssertNotNil(facts.localSnapshotCount) }
    }

    func testMaterializationIsSwitchedOff() {
        XCTAssertTrue(Materialization.disableForProcess())
    }

    func testTheLiveBackendIsWiredAndNotDemo() async throws {
        let sb = try makeSandbox()
        let backend = LiveBackend.make(home: sb.home, appVersion: "0.0.0-test")
        XCTAssertFalse(backend.isDemo)
        let app = try sb.makeApp("Foo", id: "com.example.foo")
        let lookup = await backend.identify(app)
        XCTAssertEqual(lookup.identity?.bundleID, "com.example.foo")
        let identity = try XCTUnwrap(lookup.identity)
        XCTAssertEqual(backend.runState(identity), .notRunning)
        XCTAssertTrue(backend.loadLog().isEmpty)
        let text = await backend.diagnostics()
        XCTAssertTrue(text.contains("0.0.0-test"))
        XCTAssertFalse(text.contains(sb.home), "diagnostics carry no paths")
    }
}
