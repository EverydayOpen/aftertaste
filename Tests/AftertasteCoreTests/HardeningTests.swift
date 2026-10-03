import Foundation
import XCTest
@testable import AftertasteCore

/// Edge cases found while reviewing the classifier against the failure that kills this product: taking something that
/// belongs to someone else.
final class HardeningTests: XCTestCase {
    func testTwoLabelIDsDoNotClaimDottedChildren() {
        var lib = Lib()
        let short = T.app("com.company", "Company Tool", path: "/Applications/Company Tool.app")
        lib.apps = [short]
        lib.add(.caches, "com.company", "com.company.my_app", "com.company.ShipIt")
        lib.add(.preferences, "com.company.plist", "com.company.my_app.plist", type: .file)
        let r = lib.analyze(.app, target: short)
        XCTAssertEqual(r.item(lib.path(.caches, "com.company"))?.tier, .high)
        XCTAssertEqual(r.item(lib.path(.preferences, "com.company.plist"))?.tier, .high)
        for name in ["com.company.my_app", "com.company.ShipIt"] { XCTAssertNil(r.item(lib.path(.caches, name)), name) }
        XCTAssertNil(r.item(lib.path(.preferences, "com.company.my_app.plist")))
    }

    func testAnOrphanWithATwoLabelBaseDoesNotSweepUpOtherAppsFolders() {
        var lib = Lib()
        lib.add(.preferences, "com.company.plist", type: .file)
        lib.add(.caches, "com.company", "com.company.my_app")
        let r = lib.analyze(.orphans)
        XCTAssertNil(r.items.first { $0.name == "com.company.my_app" }, "an installed app with an unusual ID could own it")
    }

    func testALiveTwoLabelAppStillProtectsItsDottedChildren() {
        var lib = Lib()
        let target = T.app("com.livecorp.tool", "Live Tool", path: "/Applications/Live Tool.app")
        lib.apps = [target, T.app("com.livecorp", "Live Corp")]
        lib.add(.caches, "com.livecorp.tool", "com.livecorp.tool.sub")
        let r = lib.analyze(.app, target: target)
        XCTAssertEqual(r.item(lib.path(.caches, "com.livecorp.tool"))?.tier, .handsOff, "named exactly like the target, but a live vendor-ID app may own it too")
        XCTAssertEqual(r.item(lib.path(.caches, "com.livecorp.tool"))?.blocked, .sharedWithInstalled)
        XCTAssertFalse(r.item(lib.path(.caches, "com.livecorp.tool.sub"))?.tier.isSelectable ?? false)
    }

    func testAnInstalledAppWithAnUnusualIDStillProtectsItsFolders() {
        var lib = Lib()
        let target = T.app("com.vendor.tool", "Vendor Tool", path: "/Applications/Vendor Tool.app")
        let live = T.app("com.vendor.tool.my_app", "My App", path: "/Applications/My App.app")
        XCTAssertNil(Subject(live, isLive: false, allowNames: true), "the app being removed must have a strict ID")
        XCTAssertNotNil(Subject(live, isLive: true, allowNames: true), "an installed app only protects, so an underscore is fine")
        lib.apps = [target, live]
        lib.add(.caches, "com.vendor.tool", "com.vendor.tool.my_app", "com.vendor.tool.my_app.cache")
        let r = lib.analyze(.app, target: target)
        XCTAssertEqual(r.item(lib.path(.caches, "com.vendor.tool"))?.tier, .high)
        XCTAssertNil(r.item(lib.path(.caches, "com.vendor.tool.my_app")))
        XCTAssertNil(r.item(lib.path(.caches, "com.vendor.tool.my_app.cache")))
        // Never a path separator or a control character, even for a live app.
        XCTAssertNil(Subject(T.app("com.x/../y", "Bad"), isLive: true, allowNames: false))
        XCTAssertNil(Subject(T.app("", "Bad"), isLive: true, allowNames: false))
    }

    func testSiblingsShareNameKeyedFoldersToo() {
        // Xcode and Xcode-beta: the display names differ, the folder "Xcode" is used by both.
        var lib = Lib()
        let a = T.app("com.apple.dt.Xcode", "Xcode", path: "/Applications/Xcode.app")
        let b = T.app("com.apple.dt.Xcode", "Xcode-beta", path: "/Applications/Xcode-beta.app")
        lib.apps = [a, b]
        lib.add(.applicationSupport, "Xcode")
        XCTAssertEqual(lib.analyze(.app, target: a).item(lib.path(.applicationSupport, "Xcode"))?.blocked, .siblingInstalled)
        lib.apps = [a]
        XCTAssertEqual(lib.analyze(.app, target: a).item(lib.path(.applicationSupport, "Xcode"))?.tier, .low, "alone, a name match is Review")
    }

    func testTheSameEntryNeverAppearsTwiceAndCaseVariantsStaySeparate() {
        var lib = Lib()
        let app = T.app("com.example.notes", "Notes Pro", path: "/Applications/Notes Pro.app")
        lib.apps = [app]
        lib.add(.caches, "com.example.notes", "COM.EXAMPLE.NOTES")
        let r = lib.analyze(.app, target: app)
        XCTAssertEqual(r.items.filter { $0.root == .caches }.count, 2, "on a case-sensitive volume these are two folders")
        XCTAssertEqual(Set(r.items.map(\.path)).count, r.items.count)
    }

    func testEntryNamesCannotSmuggleAPath() {
        var lib = Lib()
        let app = T.app("com.example.notes", "Notes Pro", path: "/Applications/Notes Pro.app")
        lib.apps = [app]
        lib.entries[.caches] = [LibraryEntry(name: "../Preferences/com.example.notes.plist", type: .file, stamp: T.stamp(1)),
                                LibraryEntry(name: "com.example.notes/../x", type: .directory, stamp: T.stamp(2)),
                                LibraryEntry(name: "..", type: .directory, stamp: T.stamp(3)), LibraryEntry(name: ".", type: .directory, stamp: T.stamp(4)),
                                LibraryEntry(name: "", type: .directory, stamp: T.stamp(5)), LibraryEntry(name: "com.example.notes\u{0}x", type: .directory, stamp: T.stamp(6)),
                                LibraryEntry(name: "com.example.notes", type: .directory, stamp: T.stamp(7))]
        let r = lib.analyze(.app, target: app)
        XCTAssertEqual(r.items.filter { $0.root == .caches }.map(\.name), ["com.example.notes"])
    }

    func testNoDotDirectoryIsEverProposedFromADisplayName() {
        var lib = Lib()
        let app = T.app("com.example.claudish", "Claudish Code", path: "/Applications/Claudish Code.app")
        lib.apps = [app]
        lib.add(.caches, "com.example.claudish")
        let paths = Scan.candidatePaths(lib.input(.app, target: app)) + Scan.analyze(lib.input(.app, target: app)).items.map(\.path)
        for path in paths {
            XCTAssertTrue(path.hasPrefix("/Users/jane/Library/") || path.hasSuffix(".app"), path)
            XCTAssertFalse(path.contains("/."), path)
        }
        XCTAssertFalse(LibraryRoot.allCases.contains { $0.relativePath.split(separator: "/").contains { $0.hasPrefix(".") } }, "no root is a dot folder")
    }

    func testSharedUpdaterNamesAreHeldAtReview() {
        var lib = Lib()
        let chrome = T.app("com.google.Chrome", "Google Chrome", path: "/Applications/Google Chrome.app")
        lib.apps = [chrome]
        lib.add(.caches, "com.google.Chrome", "com.google.Keystone", "com.google.Chrome.helper")
        let r = lib.analyze(.app, target: chrome)
        XCTAssertEqual(r.item(lib.path(.caches, "com.google.Chrome"))?.tier, .high)
        XCTAssertNil(r.item(lib.path(.caches, "com.google.Keystone")))
        // An ID that IS a shared updater, owned by a (weird) target, is held at Review.
        let odd = T.app("com.google.Keystone.Agent", "Keystone Agent", path: "/Applications/Keystone Agent.app")
        var lib2 = Lib()
        lib2.apps = [odd]
        lib2.add(.caches, "com.google.Keystone.Agent")
        XCTAssertEqual(lib2.analyze(.app, target: odd).item(lib2.path(.caches, "com.google.Keystone.Agent"))?.tier, .low)
    }
}
