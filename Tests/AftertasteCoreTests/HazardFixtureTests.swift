import Foundation
import XCTest
@testable import AftertasteCore

/// Gate K2: the hazard fixtures. Each must preselect nothing that belongs to an installed app, and a plan built by ticking
/// EVERYTHING (the worst thing a user or a bug could do) must still not contain such an item.
final class HazardFixtureTests: XCTestCase {
    private func abs(_ rel: String) -> String { rel.hasPrefix("/") ? rel : T.home + "/" + rel }

    func testTheFixtureSetIsComplete() throws {
        let names = Set(try loadFixtures().map(\.name))
        for required in ["office-shared-group-containers", "firefox-beta-and-thunderbird", "xcode-and-xcode-beta", "vscode-code-folder", "common-word-names",
                         "bundle-id-with-glob", "symlink-escapes-library-roots", "case-only-collisions", "unmounted-volume-orphans", "uuid-container-metadata",
                         "launchd-program-in-removed-bundle", "receipt-bom-shared-toplevel", "same-team-group-container", "vendor-roots-adobe-jetbrains",
                         "vendor-roots-google-android", "firefox-developer-edition-installed", "firefox-developer-edition-orphans"] {
            XCTAssertTrue(names.contains(required), required)
        }
    }

    func testEveryFixtureHoldsItsExpectations() throws {
        for fx in try loadFixtures() {
            let (lib, kind, target) = fx.build()
            let input = lib.input(kind, target: target)
            let result = Scan.analyze(input)
            let label = fx.name
            if fx.expect.emptyResult == true { XCTAssertTrue(result.groups.isEmpty, label) }
            for (rel, tier) in fx.expect.tiers ?? [:] { XCTAssertEqual(result.item(abs(rel))?.tier.rawValue, tier, "\(label): \(rel)") }
            for rel in fx.expect.absent ?? [] { XCTAssertNil(result.item(abs(rel)), "\(label): \(rel) must not be found") }
            for (rel, reason) in fx.expect.blocked ?? [:] { XCTAssertEqual(result.item(abs(rel))?.blocked?.rawValue, reason, "\(label): \(rel)") }
            let pre = ItemSelection.preselected(result)
            if let expected = fx.expect.preselected { XCTAssertEqual(pre, Set(expected.map(abs)), "\(label): preselected set") }

            // Tick everything and acknowledge: nothing owned by an installed app may be planned.
            let all = Set(result.items.map(\.id))
            let plan = TrashPlanner.plan(from: result, ticked: all, mode: .bulk(acknowledgedMedium: true), now: T.now, runID: "r1")
            let planned = Set(plan.items.map(\.path))
            for rel in fx.expect.installedOwned ?? [] {
                let path = abs(rel)
                XCTAssertFalse(pre.contains(path), "\(label): \(rel) preselected")
                XCTAssertFalse(planned.contains(path), "\(label): \(rel) planned")
                if let item = result.item(path) { XCTAssertTrue(item.tier == .handsOff || item.tier == .needsAdmin || item.tier == .low, "\(label): \(rel) is \(item.tier)") }
            }
            for item in plan.items {
                XCTAssertNil(item.blocked, label)
                XCTAssertFalse(item.requiresAdmin, label)
                XCTAssertTrue(item.tier == .high || item.tier == .medium, "\(label): \(item.path) is \(item.tier)")
            }
            // Every candidate to measure is something the scan found.
            let found = Set(result.items.map(\.path))
            for path in Scan.candidatePaths(input) { XCTAssertTrue(found.contains(path), "\(label): \(path)") }
            // Everything is a direct child of a root, or the dropped app.
            for item in result.items {
                if item.ruleID == "APP" { continue }
                let root = try XCTUnwrap(item.root, label)
                XCTAssertEqual(GuardPolicy.check(path: item.path, canonicalParent: GuardPolicy.normalize(root.path(home: T.home)), home: T.home, keep: [], isAppBundle: false) == nil,
                               !root.isSystem, "\(label): \(item.path)")
            }
        }
    }
}
