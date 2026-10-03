import Darwin
import Foundation
import XCTest
import AftertasteCore
@testable import AftertasteMac

final class IdentityTests: MacTestCase {
    private func read(_ path: String) -> AppLookup { Identity.read(appURL: URL(fileURLWithPath: path), now: Date()) }

    func testReadsAFakeApp() throws {
        let sb = try makeSandbox()
        let app = try sb.makeApp("Foo", id: "com.example.foo", exec: "FooBin")
        let r = read(app)
        XCTAssertNil(r.rejection)
        let id = try XCTUnwrap(r.identity)
        XCTAssertEqual(id.bundleID, "com.example.foo")
        XCTAssertEqual(id.displayName, "Foo")
        XCTAssertEqual(id.execName, "FooBin")
        XCTAssertEqual(id.version, "1.0")
        XCTAssertEqual(id.bundlePath, app)
        XCTAssertEqual(id.bundleOwnerUID, getuid())
        XCTAssertFalse(id.appleSigned)
        XCTAssertEqual(id.installSource, .manual)
    }

    func testRefusesWhatIsNotAnApp() throws {
        let sb = try makeSandbox()
        try FileManager.default.createDirectory(atPath: sb.home + "/Applications/Plain.app", withIntermediateDirectories: true)
        XCTAssertNotNil(read(sb.home + "/Applications/Plain.app").rejection, "no Info.plist")
        XCTAssertNotNil(read(sb.home + "/Applications").rejection, "not a .app")
        XCTAssertNotNil(read(sb.home + "/Applications/Missing.app").rejection)
        let bad = try sb.makeApp("Bad", id: "no_dots_here")
        XCTAssertNotNil(read(bad).rejection, "an ID that is not reverse-DNS")
        let star = try sb.makeApp("Star", id: "com.example.*")
        XCTAssertNotNil(read(star).rejection, "an ID with a wildcard")
    }

    func testRefusesALinkToAnApp() throws {
        let sb = try makeSandbox()
        let app = try sb.makeApp("Real", id: "com.example.real")
        let link = sb.home + "/Applications/Link.app"
        try FileManager.default.createSymbolicLink(atPath: link, withDestinationPath: app)
        XCTAssertNotNil(read(link).rejection)
    }

    func testRefusesAppleOursAndNested() throws {
        let sb = try makeSandbox()
        let fake = try sb.makeApp("Fake", id: "com.apple.fakeapp")
        XCTAssertEqual(read(fake).rejection, "macOS apps from Apple are never touched.")
        let us = try sb.makeApp("Us", id: "io.github.everydayopen.aftertaste")
        XCTAssertEqual(read(us).rejection, "Aftertaste does not remove itself.")
        let outer = try sb.makeApp("Outer", id: "com.example.outer")
        let inner = try sb.makeApp("Inner", id: "com.example.inner", in: outer + "/Contents/Resources")
        XCTAssertEqual(read(inner).rejection, "That app is inside another app.")
        // The Apple allow-list: an Apple app people really uninstall is a valid target.
        let xcode = try sb.makeApp("Xcode", id: "com.apple.dt.Xcode")
        XCTAssertNil(read(xcode).rejection)
    }

    func testRealAppleAppIsRefused() throws {
        guard FileManager.default.fileExists(atPath: "/System/Applications/Calculator.app") else { throw XCTSkip("no Calculator.app") }
        XCTAssertNotNil(read("/System/Applications/Calculator.app").rejection)
    }

    func testCollectsNestedIDsLabelsAndSkipsSparkle() throws {
        let sb = try makeSandbox()
        let app = try sb.makeApp("Foo", id: "com.example.foo", extra: ["SMPrivilegedExecutables": ["com.example.foo.helper": "anchor apple"]])
        _ = try sb.makeApp("Login", id: "com.example.foo.login", in: app + "/Contents/Library/LoginItems")
        _ = try sb.makeApp("Updater", id: "org.sparkle-project.Sparkle.Autoupdate", in: app + "/Contents/XPCServices")
        try FileManager.default.createDirectory(atPath: app + "/Contents/Library/LaunchServices", withIntermediateDirectories: true)
        FileManager.default.createFile(atPath: app + "/Contents/Library/LaunchServices/com.example.foo.privhelper", contents: Data())
        let id = try XCTUnwrap(read(app).identity)
        XCTAssertEqual(id.embeddedIDs, ["com.example.foo.login"])
        XCTAssertEqual(Set(id.helperLabels), ["com.example.foo.helper", "com.example.foo.privhelper"])
    }

    func testLaunchdPlistFacts() throws {
        let sb = try makeSandbox()
        let app = try sb.makeApp("Foo", id: "com.example.foo")
        let there = try sb.putLaunchAgent(label: "com.example.foo.agent", program: app + "/Contents/MacOS/Foo")
        FileManager.default.createFile(atPath: app + "/Contents/MacOS/Foo", contents: Data())
        let a = try XCTUnwrap(Identity.launchd(at: there))
        XCTAssertEqual(a.label, "com.example.foo.agent")
        XCTAssertTrue(a.programExists)
        let gone = try sb.putLaunchAgent(label: "com.example.gone", program: sb.home + "/Applications/Nope.app/Contents/MacOS/Nope")
        XCTAssertEqual(Identity.launchd(at: gone)?.programExists, false)
    }

    func testPlistReadersRefuseLinksAndBigFiles() throws {
        let sb = try makeSandbox()
        let real = try sb.putLaunchAgent(label: "com.example.real", program: nil)
        let link = sb.home + "/Library/LaunchAgents/com.example.link.plist"
        try FileManager.default.createSymbolicLink(atPath: link, withDestinationPath: real)
        XCTAssertNil(Identity.launchd(at: link))
        let big = sb.put("Library/LaunchAgents/com.example.big.plist", bytes: 2 << 20)
        XCTAssertNil(Identity.launchd(at: big))
    }

    func testContainerMetadataID() throws {
        let sb = try makeSandbox()
        let container = sb.home + "/Library/Containers/" + UUID().uuidString
        try FileManager.default.createDirectory(atPath: container, withIntermediateDirectories: true)
        let data = try PropertyListSerialization.data(fromPropertyList: ["MCMMetadataIdentifier": "com.example.foo"], format: .xml, options: 0)
        try data.write(to: URL(fileURLWithPath: container + "/.com.apple.containermanagerd.metadata.plist"))
        XCTAssertEqual(Identity.containerMetadataID(atContainer: container), "com.example.foo")
        XCTAssertNil(Identity.containerMetadataID(atContainer: sb.home + "/Library/Containers/none"))
    }
}
