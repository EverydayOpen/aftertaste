import Foundation
import XCTest
@testable import AftertasteCore

/// An item another installed app still uses is never offered for removal, whichever root it sits in.
final class LiveOwnerTests: XCTestCase {
    let id = "com.example.tool"

    func library(sibling: Bool) -> (Lib, AppIdentity) {
        var lib = Lib()
        let target = T.app(id, "Tool", path: "/Applications/Tool.app")
        lib.apps = [target]
        if sibling {
            lib.apps.append(T.app(id, "Tool Beta", path: "/Applications/Tool Beta.app"))
        } else {
            // Another app lists the agent's label among its own IDs, so the agent is shared rather than owned outright.
            lib.apps.append(T.app("com.example.suite", "Suite", embedded: ["\(id).agent"]))
        }
        lib.addAgent(.launchAgents, name: "\(id).agent.plist", label: "\(id).agent", program: "/Applications/Tool.app/Contents/MacOS/agent")
        lib.addAgent(.systemLaunchDaemons, name: "\(id).agent.plist", label: "\(id).agent", program: "/Applications/Tool.app/Contents/MacOS/agent")
        return (lib, target)
    }

    func check(sibling: Bool) {
        let (lib, target) = library(sibling: sibling)
        let r = lib.analyze(.app, target: target)
        let want: BlockReason = sibling ? .siblingInstalled : .sharedWithInstalled
        for root in [LibraryRoot.launchAgents, .systemLaunchDaemons] {
            guard let item = r.item(lib.path(root, "\(id).agent.plist")) else { return XCTFail("\(root) row missing") }
            XCTAssertEqual(item.blocked, want, "\(root)")
            XCTAssertEqual(item.tier, .handsOff, "\(root)")
            XCTAssertEqual(item.requiresAdmin, root.isSystem, "\(root)")
            XCTAssertTrue(item.why.contains(sibling ? "Another installed copy" : "Another installed app uses this"), item.why)
        }
        XCTAssertEqual(r.leftBehind.filter { $0.root != nil }.count, 0, "claimed rows are not left behind")
        let report = TraceReportText.report(from: r, options: .init(), now: T.now)
        XCTAssertEqual(report.launchAgents, 0)
        XCTAssertEqual(report.launchDaemons, 0)
        XCTAssertFalse(PlanText.previewHeader(r).hasPrefix("Found"), "the app bundle alone is not a leftover")
    }

    func testASiblingsLaunchItemsAreNotNeedsAdminOrListedOnly() { check(sibling: true) }

    func testASharedLaunchItemIsNotNeedsAdminOrListedOnly() { check(sibling: false) }

    func testThePreviewCountsOnlyWhatWasLeftBehind() {
        var lib = Lib()
        let target = T.app(id, "Tool", path: "/Applications/Tool.app")
        lib.apps = [target, T.app("com.example.suite", "Suite", embedded: ["\(id).agent"])]
        lib.add(.caches, id)
        lib.sizes[lib.path(.caches, id)] = T.sized(5_000_000)
        lib.addAgent(.launchAgents, name: "\(id).agent.plist", label: "\(id).agent", program: nil)
        let r = lib.analyze(.app, target: target)
        XCTAssertEqual(r.leftBehind.map(\.path), [lib.path(.caches, id)])
        XCTAssertTrue(PlanText.previewHeader(r).hasPrefix("Found 5 MB in 1 item for 1 app."), PlanText.previewHeader(r))
    }

    func testASuiteStillInstalledCapsAnOrphanWithNoInventoryRecord() {
        var lib = Lib()
        lib.apps = [T.app("io.vendorco.suite", "Suite")]
        lib.add(.preferences, "io.vendorco.helper.plist", type: .file)
        lib.add(.caches, "io.vendorco.helper")
        lib.sizes[lib.path(.caches, "io.vendorco.helper")] = T.sized(1000)
        let cache = lib.analyze(.orphans).item(lib.path(.caches, "io.vendorco.helper"))
        XCTAssertEqual(cache?.tier, .medium)
        XCTAssertTrue(cache?.evidence.contains(Evidence(.sameTeamInstalled, "Suite")) ?? false)
        lib.apps = [T.app("io.other.suite", "Other")]
        XCTAssertEqual(lib.analyze(.orphans).item(lib.path(.caches, "io.vendorco.helper"))?.tier, .high)
    }

    func testTheSnapshotThreatLineDoesNotOverclaim() {
        let line = ReadinessText.threats().first { $0.who.hasPrefix("Time Machine") }?.answer ?? ""
        XCTAssertTrue(line.contains("Time Machine local snapshots only"), line)
    }
}
