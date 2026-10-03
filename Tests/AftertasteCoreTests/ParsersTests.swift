import Foundation
import XCTest
@testable import AftertasteCore

final class ParsersTests: XCTestCase {
    private func plist(_ dict: [String: Any], format: PropertyListSerialization.PropertyListFormat = .xml) throws -> Data {
        try PropertyListSerialization.data(fromPropertyList: dict, format: format, options: 0)
    }

    private func command(_ name: String) throws -> String {
        let text = try String(contentsOf: T.fixturesDir().appendingPathComponent("commands").appendingPathComponent(name), encoding: .utf8)
        return text.split(separator: "\n", omittingEmptySubsequences: false).filter { !$0.hasPrefix("#") }.joined(separator: "\n")
    }

    // MARK: StrictBundleID

    func testValidBundleIDs() {
        for id in ["com.example.notes", "a.b", "com.example.Notes-Pro", "io.github.everydayopen.aftertaste", "org.sparkle-project.Sparkle",
                   "com.x.y.z1.v2", "UBF8T346G9.Office", "group.com.example.notes"] {
            XCTAssertTrue(StrictBundleID.isValid(id), id)
        }
    }

    func testInvalidBundleIDsAreRejected() {
        let long = String(repeating: "a", count: 80) + "." + String(repeating: "b", count: 80)
        for id in ["", "a", "com", "com.", ".com", "com..example", "com.exam*ple", "com.example.*", "com.example.?", "../etc/passwd", "com.example/..",
                   "com.example\\x", "com.exa mple", "com.example.[a]", "com.example.{a}", "com.example.~", "com.-example", "com.example-", "com.example.-a",
                   "com.example.a-", "com.exämple", "com.example.\u{0}x", "com.example.a_b", "com.example.a\nb", long] {
            XCTAssertFalse(StrictBundleID.isValid(id), id)
        }
    }

    func testLooksLikeIDSeparatesTeamPrefixes() {
        XCTAssertEqual(StrictBundleID.looksLikeID("com.example.notes")?.id, "com.example.notes")
        XCTAssertNil(StrictBundleID.looksLikeID("com.example.notes")?.team)
        let withTeam = StrictBundleID.looksLikeID("UBF8T346G9.com.example.notes")
        XCTAssertEqual(withTeam?.team, "UBF8T346G9")
        XCTAssertEqual(withTeam?.id, "com.example.notes")
        // A team prefix in front of a single label is not an ID: "<Team>.Office" is a group container name.
        XCTAssertEqual(StrictBundleID.looksLikeID("UBF8T346G9.Office")?.team, nil)
        XCTAssertEqual(StrictBundleID.looksLikeID("UBF8T346G9.Office")?.id, "UBF8T346G9.Office")
        XCTAssertNil(StrictBundleID.looksLikeID("not an id"))
        XCTAssertNil(StrictBundleID.looksLikeID("com.exam*ple"))
    }

    func testTeamIDShape() {
        XCTAssertTrue(StrictBundleID.isTeamID("UBF8T346G9"))
        XCTAssertFalse(StrictBundleID.isTeamID("ubf8t346g9"))
        XCTAssertFalse(StrictBundleID.isTeamID("UBF8T346G"))
        XCTAssertFalse(StrictBundleID.isTeamID("UBF8T346G9X"))
    }

    // MARK: Info.plist

    func testInfoPlistReadsOnlyWhatItNeedsAndAcceptsBinaryPlists() throws {
        let dict: [String: Any] = [
            "CFBundleIdentifier": "com.example.orbitmeet", "CFBundleDisplayName": "Orbit Meet", "CFBundleName": "OM",
            "CFBundleExecutable": "OrbitMeet", "CFBundleShortVersionString": "6.2", "CFBundleVersion": "620",
            "LSUIElement": true, "SMPrivilegedExecutables": ["com.example.orbitmeet.helper": "anchor apple", "bad*label": "x"],
            "NSSomethingElse": "ignored",
        ]
        for format in [PropertyListSerialization.PropertyListFormat.xml, .binary] {
            let p = try XCTUnwrap(Parsers.infoPlist(try plist(dict, format: format)))
            XCTAssertEqual(p.bundleID, "com.example.orbitmeet")
            XCTAssertEqual(p.name, "Orbit Meet")
            XCTAssertEqual(p.execName, "OrbitMeet")
            XCTAssertEqual(p.version, "6.2")
            XCTAssertEqual(p.smPrivilegedLabels, ["com.example.orbitmeet.helper"], "invalid labels are dropped")
            XCTAssertTrue(p.isUIElementOrBackground)
        }
    }

    func testInfoPlistFallbacksAndRejections() throws {
        let minimal = try XCTUnwrap(Parsers.infoPlist(try plist(["CFBundleIdentifier": "com.example.Tiny"])))
        XCTAssertEqual(minimal.name, "Tiny")
        XCTAssertEqual(minimal.execName, "Tiny")
        XCTAssertNil(minimal.version)
        XCTAssertFalse(minimal.isUIElementOrBackground)
        XCTAssertEqual(Parsers.infoPlist(try plist(["CFBundleIdentifier": "com.example.x", "CFBundleName": "X", "LSBackgroundOnly": "1"]))?.isUIElementOrBackground, true)
        XCTAssertNil(Parsers.infoPlist(try plist(["CFBundleIdentifier": "com.example.*"])), "a glob in the ID is refused")
        XCTAssertNil(Parsers.infoPlist(try plist(["CFBundleIdentifier": "../../x.y"])))
        XCTAssertNil(Parsers.infoPlist(try plist(["CFBundleName": "No ID"])))
        XCTAssertNil(Parsers.infoPlist(Data()))
        XCTAssertNil(Parsers.infoPlist(Data("not a plist".utf8)))
        XCTAssertNil(Parsers.infoPlist(Data(count: Parsers.maxPlistBytes + 1)), "over the 1 MB cap")
    }

    // MARK: launchd and container metadata

    func testLaunchdProgramOrder() throws {
        let a = Parsers.launchd(try plist(["Label": "com.example.agent", "Program": "/Applications/X.app/Contents/MacOS/x", "ProgramArguments": ["/bin/other"]]))
        XCTAssertEqual(a?.label, "com.example.agent")
        XCTAssertEqual(a?.program, "/Applications/X.app/Contents/MacOS/x")
        let b = Parsers.launchd(try plist(["Label": "com.example.agent", "ProgramArguments": ["/usr/local/bin/tool", "--flag"]]))
        XCTAssertEqual(b?.program, "/usr/local/bin/tool")
        let c = Parsers.launchd(try plist(["Label": "com.example.agent", "BundleProgram": "Contents/MacOS/helper"]))
        XCTAssertEqual(c?.program, "Contents/MacOS/helper")
        let d = Parsers.launchd(try plist(["Label": "com.example.agent"]))
        XCTAssertEqual(d?.label, "com.example.agent")
        XCTAssertNil(d?.program)
        XCTAssertNil(Parsers.launchd(try plist(["Program": "/x"])))
        XCTAssertNil(Parsers.launchd(try plist(["Label": "  "])))
        XCTAssertNil(Parsers.launchd(try plist(["Label": "bad\u{7}label"])))
    }

    func testContainerMetadataIsValidated() throws {
        XCTAssertEqual(Parsers.containerMetadata(try plist(["MCMMetadataIdentifier": "com.example.orbitmeet", "Other": 1])), "com.example.orbitmeet")
        XCTAssertNil(Parsers.containerMetadata(try plist(["MCMMetadataIdentifier": "com.example.*"])))
        XCTAssertNil(Parsers.containerMetadata(try plist(["MCMMetadataIdentifier": ""])))
        XCTAssertNil(Parsers.containerMetadata(try plist(["Something": "else"])))
    }

    // MARK: command output fixtures

    func testFdesetupFixtures() throws {
        XCTAssertEqual(Parsers.fdesetup(try command("fdesetup-on.txt")), .on)
        XCTAssertEqual(Parsers.fdesetup(try command("fdesetup-off.txt")), .off)
        XCTAssertEqual(Parsers.fdesetup(try command("fdesetup-progress.txt")), .transitioning)
        XCTAssertEqual(Parsers.fdesetup(try command("fdesetup-garbage.txt")), .unknown)
        XCTAssertEqual(Parsers.fdesetup(""), .unknown)
        XCTAssertEqual(Parsers.fdesetup("FileVault is On.\nDeferred enablement appears to be active for user 'jane'."), .on)
    }

    func testDiskutilFixtures() throws {
        let ssd = Parsers.diskutilInfo(try Data(contentsOf: T.fixturesDir().appendingPathComponent("commands/diskutil-apfs-ssd.plist")))
        XCTAssertEqual(ssd.storage, .solidState)
        XCTAssertEqual(ssd.fileSystem, "APFS")
        XCTAssertEqual(ssd.isInternal, true)
        let hdd = Parsers.diskutilInfo(try Data(contentsOf: T.fixturesDir().appendingPathComponent("commands/diskutil-hdd.plist")))
        XCTAssertEqual(hdd.storage, .rotational)
        XCTAssertEqual(hdd.fileSystem, "HFS")
        XCTAssertEqual(hdd.isInternal, false)
        let none = Parsers.diskutilInfo(Data("garbage".utf8))
        XCTAssertEqual(none.storage, .unknown)
        XCTAssertNil(none.fileSystem)
        XCTAssertNil(none.isInternal)
        XCTAssertEqual(Parsers.diskutilInfo(try plist(["FilesystemType": "apfs"])).storage, .unknown, "no SolidState key means unknown, not a guess")
    }

    func testTmutilFixtures() throws {
        XCTAssertEqual(Parsers.tmutilSnapshots(try command("tmutil-3.txt")), 3)
        XCTAssertEqual(Parsers.tmutilSnapshots(try command("tmutil-none.txt")), 0)
        XCTAssertNil(Parsers.tmutilSnapshots(try command("tmutil-error.txt")))
        XCTAssertNil(Parsers.tmutilSnapshots(""), "an empty answer is not zero snapshots")
        XCTAssertEqual(Parsers.tmutilSnapshots("Snapshots for volume group containing disk /:\ncom.apple.TimeMachine.2026-10-03-110000.local"), 1)
    }
}
