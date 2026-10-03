import Foundation
import XCTest
@testable import AftertasteCore

final class RulesTests: XCTestCase {
    // MARK: the rule table

    func testExactlyOneRulePerRootAndUniqueIDs() {
        XCTAssertEqual(ResidueRules.all.count, LibraryRoot.allCases.count)
        XCTAssertEqual(Set(ResidueRules.all.map(\.root)), Set(LibraryRoot.allCases))
        XCTAssertEqual(Set(ResidueRules.all.map(\.id)).count, ResidueRules.all.count)
        for root in LibraryRoot.allCases { XCTAssertEqual(ResidueRules.rule(for: root).root, root) }
    }

    func testCeilingsMatchTheContract() {
        let expected: [String: Tier] = [
            "U1": .high, "U1b": .high, "U3": .high, "U7": .high, "U8": .high, "U9": .high, "U10": .high, "U11": .high, "U11b": .high,
            "U17": .high, "U16": .high, "U12": .handsOff, "U15": .medium, "U6": .medium, "U2": .medium, "U4": .medium, "U5": .low,
            "U14": .handsOff, "S2": .needsAdmin, "S3": .needsAdmin, "S4": .needsAdmin, "S5": .needsAdmin, "S6": .needsAdmin,
            "S7": .needsAdmin, "S8": .needsAdmin, "S11": .needsAdmin,
        ]
        XCTAssertEqual(Dictionary(uniqueKeysWithValues: ResidueRules.all.map { ($0.id, $0.ceiling) }), expected)
    }

    func testEverySystemRootIsNeedsAdminAndNoUserRootIsAboveItsDocumentedCeiling() {
        for rule in ResidueRules.all {
            if rule.root.isSystem { XCTAssertEqual(rule.ceiling, .needsAdmin, rule.id) }
            if !rule.root.isSystem { XCTAssertNotEqual(rule.ceiling, .needsAdmin, rule.id) }
        }
        // Data that may be yours is never High; shared data is never above Review.
        for id in ["U2", "U4", "U6", "U15"] { XCTAssertEqual(ResidueRules.all.first { $0.id == id }?.ceiling, .medium) }
        XCTAssertEqual(ResidueRules.all.first { $0.id == "U5" }?.ceiling, .low)
        // Launch agents are listed, not removed, in v1.
        XCTAssertEqual(ResidueRules.rule(for: .launchAgents).ceiling, .handsOff)
        XCTAssertEqual(ResidueRules.rule(for: .autosaveInformation).ceiling, .handsOff)
    }

    func testZapSharesAreFractions() {
        for rule in ResidueRules.all { if let z = rule.zapShare { XCTAssertTrue((0...1).contains(z), rule.id) } }
        XCTAssertEqual(ResidueRules.rule(for: .preferences).zapShare, 0.755)
    }

    func testRuleTableExportsAsStableJSON() throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let a = try encoder.encode(ResidueRules.all)
        let decoded = try JSONDecoder().decode([ResidueRule].self, from: a)
        XCTAssertEqual(decoded, ResidueRules.all)
    }

    // MARK: never-list

    func testNeverListNames() {
        XCTAssertEqual(NeverList.reason(forName: "com.apple.Safari"), .appleOwned)
        XCTAssertEqual(NeverList.reason(forName: "COM.APPLE.notes"), .appleOwned, "case-insensitive")
        XCTAssertEqual(NeverList.reason(forName: "group.com.apple.notes"), .appleOwned)
        XCTAssertEqual(NeverList.reason(forName: "243LU875E5.groups.com.apple.podcasts"), .appleOwned)
        XCTAssertEqual(NeverList.reason(forName: "io.github.everydayopen.aftertaste"), .ownCopy)
        XCTAssertEqual(NeverList.reason(forName: "io.github.everydayopen.aftertaste.plist"), .ownCopy)
        XCTAssertEqual(NeverList.reason(forName: "Aftertaste"), .ownCopy)
        XCTAssertEqual(NeverList.reason(forName: "Mobile Documents"), .iCloud)
        XCTAssertEqual(NeverList.reason(forName: "CloudStorage"), .iCloud)
        XCTAssertEqual(NeverList.reason(forName: "iCloud~com~example~notes"), .iCloud)
        XCTAssertEqual(NeverList.reason(forName: "Keychains"), .neverList)
        XCTAssertEqual(NeverList.reason(forName: "Photos Library.photoslibrary"), .neverList)
        XCTAssertEqual(NeverList.reason(forName: ".."), .neverList)
        XCTAssertNil(NeverList.reason(forName: "com.example.notes"))
        XCTAssertNil(NeverList.reason(forName: "com.applesauce.thing"), "only the com.apple. prefix is Apple's")
        XCTAssertNil(NeverList.reason(forName: "UBF8T346G9.Office"))
    }

    func testAppleAllowListedAppsAreNotVetoed() {
        for id in ["com.apple.dt.Xcode", "com.apple.dt.Xcode.savedState", "com.apple.iWork.Pages", "com.apple.TestFlight"] {
            XCTAssertNil(NeverList.reason(forName: id), id)
        }
        XCTAssertTrue(AppleAllowList.allows("com.apple.dt.Xcode"))
        XCTAssertTrue(AppleAllowList.allows("com.apple.dt.Xcode.helper"))
        XCTAssertFalse(AppleAllowList.allows("com.apple.dt.XcodeCleaner"), "the boundary is a dot, not a prefix")
        XCTAssertFalse(AppleAllowList.allows("com.apple.Safari"))
        XCTAssertEqual(NeverList.reason(forName: "group.com.apple.dt.Xcode"), .appleOwned, "group spellings of Apple IDs stay vetoed")
    }

    func testNeverListPaths() {
        let h = T.home
        func r(_ p: String, keep: [String] = []) -> BlockReason? { NeverList.reason(forPath: p, home: h, keep: keep) }
        XCTAssertEqual(r("\(h)/Library/Mobile Documents/com~apple~CloudDocs/x"), .iCloud)
        XCTAssertEqual(r("\(h)/Library/CloudStorage/Dropbox"), .iCloud)
        XCTAssertEqual(r("\(h)/Library/Application Support/CloudDocs/session"), .iCloud)
        XCTAssertEqual(r("\(h)/Library/Keychains/login.keychain-db"), .neverList)
        XCTAssertEqual(r("\(h)/Library/Mail/V10"), .neverList)
        XCTAssertEqual(r("\(h)/Library/Messages/chat.db"), .neverList)
        XCTAssertEqual(r("\(h)/Library/Safari/History.db"), .neverList)
        XCTAssertEqual(r("\(h)/Library/Developer/Xcode"), .neverList)
        XCTAssertEqual(r("\(h)/Library/Application Support/MobileSync/Backup"), .neverList)
        XCTAssertEqual(r("\(h)/.Trash/x"), .neverList)
        XCTAssertEqual(r("\(h)/Library/Containers/com.apple.Notes"), .appleOwned)
        XCTAssertEqual(r("\(h)/Library/Group Containers/group.com.apple.notes"), .appleOwned)
        XCTAssertEqual(r("/System/Library/CoreServices"), .neverList)
        XCTAssertEqual(r("/System/Volumes/Data/usr/local/bin/x"), .neverList, "the firmlink spelling is normalised first")
        XCTAssertEqual(r("/usr/local/bin/tool"), .neverList)
        XCTAssertEqual(r("/private/var/db/dslocal"), .neverList)
        XCTAssertNil(r("/private/var/db/receipts/com.example.pkg.bom"), "receipt rows are listed (needs admin), not vetoed")
        XCTAssertEqual(r("\(h)/Library/Application Support/Aftertaste"), .ownCopy)
        XCTAssertNil(r("\(h)/Library/Caches/com.example.notes"))
        XCTAssertNil(r("\(h)/Library/Application Support/com.apple.sharedfilelist/com.apple.LSSharedFileList.ApplicationRecentDocuments/com.example.notes.sfl2"),
                     "the recent-documents root lives inside an Apple-named folder; its children are fine")
        XCTAssertEqual(r("\(h)/Library/Application Support/com.apple.sharedfilelist"), .neverList, "the folder itself is never an item")
    }

    func testKeepListAddsToTheNeverList() {
        let h = T.home
        XCTAssertEqual(NeverList.reason(forPath: "\(h)/Library/Caches/com.example.notes", home: h, keep: ["com.example.notes"]), .neverList)
        XCTAssertEqual(NeverList.reason(forPath: "\(h)/Library/Preferences/com.example.notes.plist", home: h, keep: ["com.example.notes"]), .neverList)
        XCTAssertEqual(NeverList.reason(forPath: "\(h)/Library/Caches/com.example.notes.helper", home: h, keep: ["com.example.notes"]), .neverList)
        XCTAssertNil(NeverList.reason(forPath: "\(h)/Library/Caches/com.example.notesx", home: h, keep: ["com.example.notes"]))
        XCTAssertEqual(NeverList.reason(forPath: "\(h)/Library/Application Support/Foo", home: h, keep: ["~/Library/Application Support/Foo"]), .neverList)
        XCTAssertEqual(NeverList.reason(forPath: "\(h)/Library/Application Support/Foo", home: h, keep: ["\(h)/Library/Application Support/Foo/Important"]), .neverList,
                       "moving a folder would take the kept file inside it")
        XCTAssertNil(NeverList.reason(forPath: "\(h)/Library/Application Support/Bar", home: h, keep: ["~/Library/Application Support/Foo"]))
        // The default volume ignores case: a keep entry typed in another case still protects the folder, and so does a parent in the wrong case.
        XCTAssertEqual(NeverList.reason(forPath: "\(h)/Library/Application Support/Foo", home: h, keep: ["~/library/application support/FOO"]), .neverList)
        XCTAssertEqual(NeverList.reason(forPath: "\(h)/Library/Application Support/Foo/Sub", home: h, keep: ["\(h)/LIBRARY/Application Support/foo"]), .neverList)
        XCTAssertEqual(NeverList.reason(forPath: "\(h)/Library/Application Support/Foo", home: h, keep: ["~/LIBRARY/APPLICATION SUPPORT/foo/Important"]), .neverList)
        XCTAssertNil(NeverList.reason(forPath: "\(h)/Library/Application Support/Foobar", home: h, keep: ["~/library/application support/FOO"]))
        XCTAssertTrue(NeverList.keeps(bundleID: "com.example.notes.helper", keep: ["com.example.notes"]))
        XCTAssertFalse(NeverList.keeps(bundleID: "com.example.other", keep: ["com.example.notes", "/Users/jane/x"]))
    }

    // MARK: hazards and irreplaceable

    func testChannelFamilies() {
        XCTAssertEqual(Hazards.channelFamily(ofID: "com.microsoft.VSCodeInsiders"), Hazards.channelFamily(ofID: "com.microsoft.VSCode"))
        XCTAssertEqual(Hazards.channelFamily(ofID: "com.google.Chrome.canary"), Hazards.channelFamily(ofID: "com.google.Chrome"))
        XCTAssertEqual(Hazards.channelFamily(ofID: "org.mozilla.firefoxdeveloperedition"), Hazards.channelFamily(ofID: "org.mozilla.firefox"))
        XCTAssertNotEqual(Hazards.channelFamily(ofID: "org.mozilla.thunderbird"), Hazards.channelFamily(ofID: "org.mozilla.firefox"))
        XCTAssertNotEqual(Hazards.channelFamily(ofID: "com.example.notes"), Hazards.channelFamily(ofID: "com.example.notesx"))
        XCTAssertNotEqual(Hazards.channelFamily(ofID: "com.vendor.beta"), Hazards.channelFamily(ofID: "com.vendor.alpha"), "two products are not channels of one")
        XCTAssertNotEqual(Hazards.channelFamily(ofID: "com.vendor.beta"), Hazards.channelFamily(ofID: "org.other.beta"))
    }

    func testDisplayNameVariantsAreBoundaryMaterialAndExcludeCommonWords() {
        XCTAssertEqual(Set(Names.variants(ofDisplayName: "Orbit Meet 6.2")), ["orbit meet", "orbitmeet", "orbit-meet", "orbit_meet",
                                                                              "orbit meet 6.2", "orbitmeet6.2", "orbit-meet-6.2", "orbit_meet_6.2"])
        XCTAssertEqual(Names.variants(ofDisplayName: "Notes"), [], "a common word never identifies an app")
        XCTAssertEqual(Names.variants(ofDisplayName: "Music"), [])
        XCTAssertEqual(Names.variants(ofDisplayName: "Tiny"), [], "shorter than five characters")
        XCTAssertTrue(Names.variants(ofDisplayName: "Slack").contains("slack"))
        XCTAssertTrue(Names.variants(ofDisplayName: "Firefox Nightly").contains("firefox"), "channel word removed")
    }

    func testSharedNames() {
        XCTAssertTrue(Hazards.isSharedUpdater("com.google.Keystone.Agent"))
        XCTAssertTrue(Hazards.isSharedUpdater("org.sparkle-project.Sparkle"))
        XCTAssertTrue(Hazards.isSharedUpdater("KSCrashReports"))
        XCTAssertFalse(Hazards.isSharedUpdater("com.example.notes"))
        XCTAssertTrue(Hazards.isSharedVendorRoot("Adobe"))
        XCTAssertTrue(Hazards.isSharedVendorRoot("JetBrains"))
        XCTAssertTrue(Hazards.isSharedVendorRoot("google"))
        XCTAssertFalse(Hazards.isSharedVendorRoot("Zoom"))
        XCTAssertTrue(Hazards.isSameNamedCLI(".claude"))
        XCTAssertTrue(Hazards.isSameNamedCLI("Docker"))
        XCTAssertFalse(Hazards.isSameNamedCLI("orbitmeet"))
    }

    func testIrreplaceable() {
        for p in ["~/Library/Application Support/1Password", "~/Library/Application Support/Bitwarden", "~/Library/Application Support/Steam",
                  "~/Library/Containers/com.example.mailclient", "~/Library/Application Support/Parallels", "~/Library/Application Support/MobileSync",
                  "~/Library/Application Support/Ableton", "~/Library/Application Support/Foo/Backups", "~/Library/Application Support/MyWallet",
                  "~/Library/Containers/com.docker.docker", "~/Library/Application Support/Tool/Documents", "~/Library/Application Support/game/Saves"] {
            XCTAssertTrue(Irreplaceable.looksIrreplaceable(path: p, bytes: 10), p)
        }
        XCTAssertFalse(Irreplaceable.looksIrreplaceable(path: "~/Library/Caches/com.example.orbitmeet", bytes: 10_000_000))
        XCTAssertTrue(Irreplaceable.looksIrreplaceable(path: "~/Library/Caches/com.example.orbitmeet", bytes: 5_000_000_001))
        XCTAssertFalse(Irreplaceable.looksIrreplaceable(path: "~/Library/Caches/com.example.orbitmeet", bytes: 5_000_000_000))
    }

    func testHomeFolderNameNeverTripsTheIrreplaceableTest() {
        var lib = Lib()
        lib.add(.caches, "com.example.orbitmeet")
        let app = T.app("com.example.orbitmeet", "Orbit Meet")
        // Only the entry name is tested, so a home folder called "janet" or anything else can never make a path look like a mail store.
        let snapshot = LibrarySnapshot(home: "/Users/janet", listings: lib.snapshot().listings, takenAt: T.now)
        let r = Scan.analyze(ScanInput(kind: .app, target: app, installed: InstalledSnapshot(apps: [], capturedAt: T.now), library: snapshot,
                                       home: "/Users/janet", osVersion: "26.1", now: T.now))
        XCTAssertEqual(r.item("/Users/janet/Library/Caches/com.example.orbitmeet")?.tier, .high)
        XCTAssertEqual(r.item("/Users/janet/Library/Caches/com.example.orbitmeet")?.irreplaceable, false)
    }
}
