import Foundation
import XCTest
@testable import AftertasteCore

final class TraceReportTests: XCTestCase {
    let orbit = T.app("com.example.orbitmeet", "Orbit Meet", exec: "OrbitMeet", team: "ABCDE12345", path: "/Applications/Orbit Meet.app", version: "6.2")

    func item(_ root: LibraryRoot, _ name: String, tier: Tier = .high, kind: ResidueKind = .cache, size: UInt64 = 0, files: Int = 0, blocked: BlockReason? = nil,
              owner: AppIdentity? = nil, rule: String = "U3") -> ResidueItem {
        let o = owner ?? orbit
        return ResidueItem(path: GuardPolicy.normalize(root.path(home: T.home) + "/" + name), ownerID: o.bundleID, ruleID: rule, root: root, kind: kind, tier: tier,
                           evidence: [Evidence(.exactID, o.bundleID)], size: size, sizeState: .measured, fileCount: files, blocked: blocked, why: "Named exactly `\(name)`, the bundle ID of \(o.displayName).")
    }

    /// Orbit Meet 6.2: 214 files, 1.3 GB, 2 launch agents, 1 privileged helper; looked in 16 of 17 places, 1 protected.
    func orbitResult(extraItems: [ResidueItem] = []) -> ScanResult {
        var items = [item(.caches, "com.example.orbitmeet", size: 1_200_000_000, files: 200), item(.preferences, "com.example.orbitmeet.plist", kind: .settings, size: 100_000_000, files: 14),
                     item(.launchAgents, "com.example.orbitmeet.agent.plist", tier: .handsOff, kind: .launchItem, blocked: .listedOnly, rule: "U12"),
                     item(.launchAgents, "com.example.orbitmeet.login.plist", tier: .handsOff, kind: .launchItem, blocked: .listedOnly, rule: "U12"),
                     item(.systemPrivilegedHelperTools, "com.example.orbitmeet.helper", tier: .needsAdmin, kind: .system, blocked: .needsAdmin, rule: "S7")]
        items += extraItems
        var bundle = item(.caches, "x", kind: .app, size: 900_000_000, files: 5000, rule: "APP")
        bundle.path = "/Applications/Orbit Meet.app"
        items.insert(bundle, at: 0)
        var places = (0..<16).map { PlaceCoverage(root: LibraryRoot.allCases[$0], state: .read) }
        places.append(PlaceCoverage(root: LibraryRoot.allCases[16], state: .protectedByMacOS, errno: 1))
        return ScanResult(scannedAt: T.now, kind: .app, groups: [ResidueGroup(owner: orbit, isOrphan: false, items: items)], coverage: Coverage(places: places),
                          home: T.home, osVersion: "26.1")
    }

    func card(_ r: ScanResult, hide: Bool = false, sample: Bool = false) -> ShareCard {
        TraceReportText.card(from: TraceReportText.report(from: r, options: .init(hideNames: hide, includeRows: true, appVersion: "0.1.0", isSample: sample), now: T.now))
    }

    func testTheCardCopyIsExact() {
        let c = card(orbitResult())
        XCTAssertEqual(TraceReportText.headline(c), "Orbit Meet 6.2 left behind")
        XCTAssertEqual(TraceReportText.figures(c), "214 files · 1.3 GB · 2 launch agents · 1 privileged helper")
        XCTAssertEqual(TraceReportText.coverage(c), "Looked in 16 of 17 places. 1 protected by macOS.")
        XCTAssertEqual(TraceReportText.listedNote(c), "Launch agents and helpers are listed, not removed.")
        XCTAssertEqual(TraceReportText.provenance(c), "macOS 26.1 · scanned 2026-10-03 · measured on this Mac, nothing sent anywhere")
        XCTAssertFalse(c.isSample)
        XCTAssertEqual(TraceReportText.sampleWatermark, "Sample data")
        XCTAssertEqual(TraceReportText.footer, "This is a list of what was found in the places listed above. It is not proof that anything was erased.")
    }

    func testThePlainTextCardHasTheSiteAndTheWatermark() {
        let text = TraceReportText.plainText(card(orbitResult(), sample: true), footer: "everydayopen.github.io/aftertaste")
        XCTAssertEqual(text, """
        AFTERTASTE  Sample data
        Orbit Meet 6.2 left behind

        214 files · 1.3 GB · 2 launch agents · 1 privileged helper

        Looked in 16 of 17 places. 1 protected by macOS.
        Launch agents and helpers are listed, not removed.

        macOS 26.1 · scanned 2026-10-03 · measured on this Mac, nothing sent anywhere
        everydayopen.github.io/aftertaste
        """)
    }

    func testZeroCountsAreOmittedAndNothingIsClaimedWithoutIt() {
        let r = ScanResult(scannedAt: T.now, kind: .app, groups: [ResidueGroup(owner: orbit, isOrphan: false, items: [item(.caches, "com.example.orbitmeet", size: 5_000_000, files: 7)])],
                           coverage: Coverage(places: [PlaceCoverage(root: .caches, state: .read)]), home: T.home, osVersion: "")
        let c = card(r)
        XCTAssertEqual(TraceReportText.figures(c), "7 files · 5 MB")
        XCTAssertNil(TraceReportText.listedNote(c))
        XCTAssertEqual(TraceReportText.coverage(c), "Looked in 1 of 1 places.")
        XCTAssertEqual(TraceReportText.provenance(c), "scanned 2026-10-03 · measured on this Mac, nothing sent anywhere")
        let empty = ShareCard(subject: "x", files: 0, bytes: 0, coverage: CoverageFacts(looked: 1, total: 1), osVersion: "26.1", scannedAt: T.now)
        XCTAssertEqual(TraceReportText.figures(empty), "Nothing found")
        let one = ShareCard(subject: "x", files: 1, bytes: 1, launchAgents: 1, privilegedHelpers: 1, coverage: CoverageFacts(looked: 1, total: 1), osVersion: "26.1", scannedAt: T.now)
        XCTAssertEqual(TraceReportText.figures(one), "1 file · 1 byte · 1 launch agent · 1 privileged helper")
    }

    func testPartialAndUnmeasuredTotalsAreFloorsNotExactFigures() {
        var cut = item(.caches, "com.example.orbitmeet.cut", size: 2_000_000_000, files: 50)
        cut.sizeState = .atLeast
        var protected = item(.containers, "com.example.orbitmeet", tier: .handsOff, kind: .yourData, blocked: .protectedByMacOS)
        protected.sizeState = .notMeasured
        let report = TraceReportText.report(from: orbitResult(extraItems: [cut, protected]), options: .init(hideNames: false, includeRows: true, appVersion: "", isSample: false), now: T.now)
        XCTAssertTrue(report.apps[0].lowerBound)
        XCTAssertEqual(report.apps[0].unmeasuredCount, 1, "a partly walked folder is measured so far; only the protected one is not measured")
        XCTAssertTrue(report.lowerBound)
        XCTAssertEqual(report.unmeasuredCount, 1)
        let c = TraceReportText.card(from: report)
        XCTAssertEqual(TraceReportText.figures(c), "at least 264 files · at least 3.3 GB · 2 launch agents · 1 privileged helper · 1 item not measured")
        XCTAssertTrue(TraceReportText.plainText(c, footer: "x").contains("at least 264 files"))
        let md = TraceReportText.markdown(report)
        XCTAssertTrue(md.contains("at least 264 files · at least 3.3 GB"), md)
        XCTAssertTrue(md.contains("| \(Format.atLeast(2_000_000_000)) |"), "the cut-short row is a floor too")
        XCTAssertTrue(report.apps[0].rows.contains { $0.lowerBound })
        XCTAssertTrue(TraceReportText.json(report).contains("\"lowerBound\" : true"))
        XCTAssertTrue(TraceReportText.json(report).contains("\"unmeasuredCount\" : 1"))
        // Everything measured: exact figures, no qualifiers.
        let exact = card(orbitResult())
        XCTAssertFalse(exact.lowerBound)
        XCTAssertEqual(exact.unmeasuredCount, 0)
        XCTAssertFalse(TraceReportText.figures(exact).contains("at least"))
        // Nothing measured at all still says so rather than "Nothing found".
        let onlyProtected = ShareCard(subject: "x", files: 0, bytes: 0, lowerBound: true, unmeasuredCount: 2, coverage: CoverageFacts(looked: 1, total: 1), osVersion: "", scannedAt: T.now)
        XCTAssertEqual(TraceReportText.figures(onlyProtected), "2 items not measured")
    }

    func testTheReportAndTheCardSayWhatStoppedShort() {
        var r = orbitResult()
        r.coverage.processListUnreadable = true
        r.coverage.unreadableAppFolders = ["/Volumes/Work/Applications"]
        r.coverage.volumeMayBeMissing = true
        r.coverage.recentlyRemovedCount = 1
        r.coverage.places[0].state = .partial
        r.coverage.places[1].state = .failed
        let line = PlanText.coverageLine(r.coverage)
        for part in ["only partly read", "could not be read", "Running apps could not be listed.", "1 app folder could not be read.", "looks missing", "removed less than 3 days ago"] {
            XCTAssertTrue(line.contains(part), part)
        }
        let report = TraceReportText.report(from: r, options: .init(hideNames: false, includeRows: true, appVersion: "", isSample: false), now: T.now)
        let c = TraceReportText.card(from: report)
        XCTAssertEqual(TraceReportText.coverage(c), line, "the card says what the app says")
        XCTAssertTrue(TraceReportText.markdown(report).contains(line), "and so does the file")
        XCTAssertFalse(TraceReportText.json(report).contains("/Volumes"), "counts, never paths")
        XCTAssertFalse(TraceReportText.markdown(report).contains("/Volumes"))
        // Nothing found while an app was withheld is not an all-clear.
        let empty = ShareCard(subject: "No apps", files: 0, bytes: 0, coverage: CoverageFacts(looked: 26, total: 26, recentlyRemoved: 2), osVersion: "", scannedAt: T.now)
        XCTAssertEqual(TraceReportText.figures(empty), "Nothing found yet")
        XCTAssertTrue(TraceReportText.coverage(empty).contains("2 apps removed less than 3 days ago are not listed yet"))
    }

    func testTheBundleAndItemsAnotherInstalledAppUsesAreNotCounted() {
        let shared = item(.groupContainers, "UBF8T346G9.Office", tier: .handsOff, kind: .shared, size: 9_000_000_000, files: 99_000, blocked: .sharedWithInstalled, rule: "U5")
        let sibling = item(.caches, "sibling", tier: .handsOff, size: 9_000_000_000, files: 99_000, blocked: .siblingInstalled)
        let c = card(orbitResult(extraItems: [shared, sibling]))
        XCTAssertEqual(TraceReportText.figures(c), "214 files · 1.3 GB · 2 launch agents · 1 privileged helper", "the app bundle and shared items were not left behind")
    }

    func testSeveralAppsAndHiddenNames() {
        let other = T.app("com.example.zoomish", "Zoomish Call", version: "5.1")
        let third = T.app("com.example.plank", "Plank Board")
        let groups = [ResidueGroup(owner: orbit, isOrphan: true, items: [item(.caches, "com.example.orbitmeet", size: 1_000_000, files: 3)]),
                      ResidueGroup(owner: other, isOrphan: true, items: [item(.caches, "com.example.zoomish", size: 2_000_000, files: 4, owner: other)]),
                      ResidueGroup(owner: third, isOrphan: true, items: [item(.caches, "com.example.plank", size: 3_000_000, files: 5, owner: third)])]
        let r = ScanResult(scannedAt: T.now, kind: .orphans, groups: groups, coverage: Coverage(places: [PlaceCoverage(root: .caches, state: .read)]), home: T.home, osVersion: "26.1")
        let c = card(r)
        XCTAssertEqual(c.subject, "3 removed apps")
        XCTAssertEqual(TraceReportText.headline(c), "3 removed apps left behind")
        XCTAssertEqual(TraceReportText.figures(c), "12 files · 6 MB")

        let hidden = TraceReportText.report(from: r, options: .init(hideNames: true, includeRows: true, appVersion: "0.1.0", isSample: false), now: T.now)
        XCTAssertEqual(hidden.apps.map(\.label), ["App 1", "App 2", "App 3"])
        XCTAssertTrue(hidden.namesHidden)
        XCTAssertTrue(hidden.apps.allSatisfy { $0.bundleID == nil && $0.version == nil })
        let single = ScanResult(scannedAt: T.now, kind: .app, groups: [groups[0]], coverage: r.coverage, home: T.home, osVersion: "26.1")
        XCTAssertEqual(card(single, hide: true).subject, "App 1")
        for output in [TraceReportText.markdown(hidden), TraceReportText.json(hidden), TraceReportText.plainText(TraceReportText.card(from: hidden), footer: "everydayopen.github.io/aftertaste")] {
            let lower = output.lowercased()
            for leak in ["orbit", "zoomish", "plank", "jane", "/users", "com.example", "6.2", "5.1"] { XCTAssertFalse(lower.contains(leak), "\(leak) leaked") }
        }
    }

    func testHideNamesReplacesTheMatchedLeafAndEvidenceDetails() {
        var odd = item(.applicationSupport, "OrbMt Helper Data", tier: .low, kind: .yourData)
        odd.evidence = [Evidence(.executableName, "OrbMt")]
        odd.why = "Named like the executable `OrbMt`."
        let r = TraceReportText.report(from: orbitResult(extraItems: [odd]), options: .init(hideNames: true, includeRows: true, appVersion: "", isSample: false), now: T.now)
        let all = TraceReportText.markdown(r) + TraceReportText.json(r)
        XCTAssertFalse(all.lowercased().contains("orbmt"), "leaf fragment leaked")
        XCTAssertTrue(TraceReportText.markdown(r).contains("`~/Library/Application Support/App 1`"))
        XCTAssertTrue(TraceReportText.markdown(r).contains("`~/Library/Preferences/App 1.plist`"))
    }

    func testHideNamesKeepsDatesAndTheOtherAppOutOfTheLabel() {
        let sibling = T.app("com.example.orbitpal", "Orbit Pal", team: "ABCDE12345")
        var cache = item(.caches, "com.example.orbitmeet.cache", size: 1000, files: 2)
        cache.evidence = [Evidence(.exactID, orbit.bundleID), Evidence(.noLiveOwner), Evidence(.inventoryAbsent, "2026-08-14"), Evidence(.staleMtime, "47 days"),
                          Evidence(.sameTeamInstalled, sibling.displayName)]
        cache.why = WhyText.line(for: cache, owner: orbit)
        XCTAssertTrue(cache.why.contains("Orbit Pal"))
        let other = T.app("com.example.plank", "Plank Board")
        let groups = [ResidueGroup(owner: orbit, isOrphan: true, items: [cache]),
                      ResidueGroup(owner: other, isOrphan: true, items: [item(.caches, "com.example.plank", size: 10, files: 1, owner: other)])]
        let r = ScanResult(scannedAt: T.now, kind: .orphans, groups: groups, coverage: Coverage(places: [PlaceCoverage(root: .caches, state: .read)]), home: T.home, osVersion: "26.1")
        let report = TraceReportText.report(from: r, options: .init(hideNames: true), now: T.now)
        let why = report.apps[0].rows[0].why
        XCTAssertTrue(why.contains("Last seen installed on 2026-08-14."), why)
        XCTAssertTrue(why.contains("Not changed for 47 days."), why)
        XCTAssertTrue(why.contains("Another app from the same developer is still installed, so this is not preselected."), why)
        XCTAssertFalse(why.contains("Orbit"), why)
        XCTAssertFalse(why.contains("App 1 is still") || why.contains("(App 1)"), why)
    }

    func testRowsThatWouldCollapseWhenNamesAreHiddenStayApart() {
        let r = TraceReportText.report(from: orbitResult(), options: .init(hideNames: true), now: T.now)
        let paths = r.apps[0].rows.map(\.path)
        XCTAssertEqual(Set(paths).count, paths.count, "\(paths)")
        XCTAssertTrue(paths.contains("~/Library/LaunchAgents/App 1 (1).plist"))
        XCTAssertTrue(paths.contains("~/Library/LaunchAgents/App 1 (2).plist"))
        XCTAssertTrue(paths.contains("~/Library/Caches/App 1"), "a row that does not collide keeps its plain label")
    }

    func testLaunchDaemonsAreCountedApartFromLaunchAgents() {
        let daemon = item(.systemLaunchDaemons, "com.example.orbitmeet.vpn.plist", tier: .needsAdmin, kind: .system, blocked: .needsAdmin, rule: "S5")
        let sysAgent = item(.systemLaunchAgents, "com.example.orbitmeet.sys.plist", tier: .needsAdmin, kind: .system, blocked: .needsAdmin, rule: "S4")
        let report = TraceReportText.report(from: orbitResult(extraItems: [daemon, sysAgent]), options: .init(), now: T.now)
        XCTAssertEqual(report.launchAgents, 3, "two user agents and a system agent")
        XCTAssertEqual(report.launchDaemons, 1)
        let c = TraceReportText.card(from: report)
        XCTAssertEqual(TraceReportText.figures(c), "214 files · 1.3 GB · 3 launch agents · 1 launch daemon · 1 privileged helper")
        XCTAssertEqual(TraceReportText.listedNote(c), "Launch agents, launch daemons and helpers are listed, not removed.")
        let only = ShareCard(subject: "x", files: 1, bytes: 1, launchDaemons: 1, coverage: CoverageFacts(looked: 1, total: 1), osVersion: "", scannedAt: T.now)
        XCTAssertEqual(TraceReportText.listedNote(only), "Launch daemons are listed, not removed.")
        XCTAssertTrue(TraceReportText.markdown(report).contains("1 launch daemon"))
    }

    func testRowsPathsAreTildeAndNeverHoldTheHomeFolder() {
        let report = TraceReportText.report(from: orbitResult(), options: .init(hideNames: false, includeRows: true, appVersion: "0.1.0", isSample: false), now: T.now)
        let rows = report.apps[0].rows
        XCTAssertEqual(rows.count, 5, "the app bundle is not a leftover row")
        XCTAssertTrue(rows.contains { $0.path == "~/Library/Caches/com.example.orbitmeet" })
        XCTAssertTrue(rows.contains { $0.path == "/Library/PrivilegedHelperTools/com.example.orbitmeet.helper" })
        for text in [TraceReportText.markdown(report), TraceReportText.json(report)] {
            XCTAssertFalse(text.contains("/Users"), "no home folder")
            XCTAssertFalse(text.contains("jane"))
        }
        let slim = TraceReportText.report(from: orbitResult(), options: .init(hideNames: false, includeRows: false, appVersion: "", isSample: false), now: T.now)
        XCTAssertTrue(slim.apps[0].rows.isEmpty)
        XCTAssertFalse(TraceReportText.markdown(slim).contains("| Item |"))
    }

    func testNoRecoverableNoErasedNoBannedWordingOnTheCard() {
        for sample in [false, true] {
            let c = card(orbitResult(), sample: sample)
            let pieces = [TraceReportText.headline(c), TraceReportText.figures(c), TraceReportText.coverage(c), TraceReportText.listedNote(c) ?? "", TraceReportText.provenance(c),
                          TraceReportText.plainText(c, footer: "everydayopen.github.io/aftertaste")]
            for p in pieces {
                let lower = p.lowercased()
                for word in ["recover", "erased", "erase ", "keychain", "secure", "deleted", "clean"] { XCTAssertFalse(lower.contains(word), "\(word) in: \(p)") }
                XCTAssertTrue(BannedPhrases.hits(in: p).isEmpty, p)
            }
        }
    }

    func testMarkdownHasTheHeaderTheRowsTheGapsAndTheFooter() {
        var r = orbitResult()
        r.coverage.places[3].state = .failed
        let report = TraceReportText.report(from: r, options: .init(hideNames: false, includeRows: true, appVersion: "0.1.0", isSample: true), now: T.now)
        let md = TraceReportText.markdown(report)
        XCTAssertTrue(md.hasPrefix("# What Aftertaste found on this Mac on 2026-10-03\n"))
        XCTAssertTrue(md.contains("_Sample data_"))
        XCTAssertTrue(md.contains("## Orbit Meet 6.2"))
        XCTAssertTrue(md.contains("`com.example.orbitmeet`"))
        XCTAssertTrue(md.contains("| `~/Library/Caches/com.example.orbitmeet` | Cache | High | 1.2 GB |"))
        XCTAssertTrue(md.contains("Looked in 15 of 17 places. 1 protected by macOS."))
        XCTAssertTrue(md.contains("Not read: "), "places that were not read are named")
        XCTAssertTrue(md.contains("## Not covered"))
        XCTAssertTrue(md.contains("- Keychain items"))
        XCTAssertTrue(md.contains("Aftertaste 0.1.0"))
        XCTAssertTrue(md.hasSuffix(TraceReportText.footer + "\n"))
        XCTAssertEqual(report.unreadablePlaces.count, 2)
    }

    func testJSONIsSortedAndRoundTrips() throws {
        let report = TraceReportText.report(from: orbitResult(), options: .init(hideNames: false, includeRows: true, appVersion: "0.1.0", isSample: false), now: T.now)
        let text = TraceReportText.json(report)
        XCTAssertEqual(text, TraceReportText.json(report))
        XCTAssertTrue(text.contains("\"generatedAt\" : \"2026-10-03T12:00:00Z\""))
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = ISO8601Lite.decodeStrategy()
        XCTAssertEqual(try decoder.decode(TraceReport.self, from: Data(text.utf8)), report)
        XCTAssertEqual(report.files, 214)
        XCTAssertEqual(report.launchAgents, 2)
        XCTAssertEqual(report.privilegedHelpers, 1)
    }

    func testMarkdownTableCellsCannotBreakTheTable() {
        var weird = item(.caches, "pipe|name\nline", size: 10, files: 1)
        weird.why = "a | b\nc"
        let md = TraceReportText.markdown(TraceReportText.report(from: orbitResult(extraItems: [weird]), options: .init(), now: T.now))
        for line in md.split(separator: "\n") where line.hasPrefix("| `") { XCTAssertEqual(line.components(separatedBy: " | ").count >= 5, true) }
        XCTAssertTrue(md.contains("pipe\\|name"))
    }
}

final class ReadinessTextTests: XCTestCase {
    func lines(_ f: ReadinessFacts) -> [String: ReadinessText.Line] { Dictionary(uniqueKeysWithValues: ReadinessText.lines(f).map { ($0.id, $0) }) }

    func testFileVaultSentences() {
        XCTAssertEqual(lines(ReadinessFacts(fileVault: .on))["filevault"]?.body, "FileVault is on.")
        XCTAssertEqual(lines(ReadinessFacts(fileVault: .on))["filevault"]?.tone, .ok)
        XCTAssertEqual(lines(ReadinessFacts(fileVault: .off))["filevault"]?.body, "FileVault is off.")
        XCTAssertEqual(lines(ReadinessFacts(fileVault: .transitioning))["filevault"]?.body, "FileVault is changing state.")
        XCTAssertEqual(lines(ReadinessFacts(fileVault: .unknown))["filevault"]?.body, "FileVault state could not be read.")
    }

    func testExternalBootDiskIsNotCalledEncrypted() {
        let body = lines(ReadinessFacts(isInternal: false, isAppleSilicon: true))["encryption"]?.body ?? ""
        XCTAssertEqual(body, "This Mac started from an external disk. Only its internal storage is always encrypted; turn on FileVault for this disk.")
        XCTAssertTrue((lines(ReadinessFacts(isInternal: true, isAppleSilicon: true))["encryption"]?.body ?? "").hasPrefix("This Mac encrypts its storage"))
        // The probe failed: it is said, never guessed.
        let unknown = lines(ReadinessFacts(isInternal: nil, isAppleSilicon: true))["encryption"]
        XCTAssertFalse(unknown?.body.contains("This Mac encrypts its storage") ?? true)
        XCTAssertEqual(unknown?.body, "Could not tell whether this Mac starts from its internal storage. Where it offers Erase All Content and Settings, destroying the key that way is the strongest erase Apple offers.")
        XCTAssertEqual(unknown?.tone, .info)
    }

    func testEncryptionSentenceNeverOverclaimsOnIntelOrUnknown() {
        let silicon = lines(ReadinessFacts(isInternal: true, isAppleSilicon: true))["encryption"]?.body ?? ""
        XCTAssertEqual(silicon, "This Mac encrypts its storage. Destroying the key (Erase All Content and Settings, or re-formatting an encrypted external disk) is the strongest erase Apple offers.")
        for silicon in [false, nil] as [Bool?] {
            let body = lines(ReadinessFacts(isAppleSilicon: silicon))["encryption"]?.body ?? ""
            XCTAssertFalse(body.contains("This Mac encrypts its storage"), "\(String(describing: silicon))")
            XCTAssertTrue(body.contains("Erase All Content and Settings"))
        }
    }

    func testStorageAndSnapshotSentences() {
        XCTAssertEqual(lines(ReadinessFacts(storage: .solidState))["storage"]?.body, "This is flash storage, so overwriting a file may not reach every copy.")
        XCTAssertEqual(lines(ReadinessFacts(storage: .rotational, fileSystem: "HFS+"))["storage"]?.body, "This disk spins; overwriting a file may reach the file's own blocks, but not copies in snapshots or backups.")
        for fs in ["APFS", nil] as [String?] {
            let body = lines(ReadinessFacts(storage: .rotational, fileSystem: fs))["storage"]?.body ?? ""
            XCTAssertEqual(body, "This disk spins, but overwriting a file may not reach its old blocks, and never reaches copies in snapshots or backups.")
            XCTAssertFalse(body.contains("can reach"), "APFS is copy-on-write: no promise that an overwrite reaches the old blocks")
        }
        XCTAssertEqual(lines(ReadinessFacts(storage: .unknown))["storage"]?.body, "The storage type could not be read.")
        XCTAssertEqual(lines(ReadinessFacts(localSnapshotCount: 3))["snapshots"]?.body, "3 local snapshots exist that may still hold these files.")
        XCTAssertEqual(lines(ReadinessFacts(localSnapshotCount: 3))["snapshots"]?.tone, .attention)
        XCTAssertEqual(lines(ReadinessFacts(localSnapshotCount: 1))["snapshots"]?.body, "1 local snapshot exists that may still hold these files.")
        XCTAssertEqual(lines(ReadinessFacts(localSnapshotCount: 0))["snapshots"]?.body, "No Time Machine local snapshots were found. Other kinds of snapshot are not counted.")
        XCTAssertEqual(lines(ReadinessFacts(localSnapshotCount: 0))["snapshots"]?.tone, .info, "only Time Machine snapshots are counted, so this is not an all-clear")
        XCTAssertEqual(lines(ReadinessFacts(localSnapshotCount: nil))["snapshots"]?.body, "Local snapshots could not be listed.")
    }

    func testEveryCombinationIsPlainHonestAndComplete() {
        for fv in [FileVaultState.on, .off, .transitioning, .unknown] {
            for storage in [StorageKind.solidState, .rotational, .unknown] {
                for snaps in [nil, 0, 1, 7] as [Int?] {
                    for silicon in [nil, true, false] as [Bool?] {
                      for internalDisk in [nil, true, false] as [Bool?] {
                        let f = ReadinessFacts(fileVault: fv, storage: storage, isInternal: internalDisk, isAppleSilicon: silicon, localSnapshotCount: snaps)
                        let ls = ReadinessText.lines(f)
                        XCTAssertEqual(ls.map(\.id), ["filevault", "encryption", "storage", "snapshots", "trash", "notReachable", "needToBeSure"])
                        for l in ls {
                            XCTAssertFalse(l.body.isEmpty)
                            XCTAssertTrue(BannedPhrases.hits(in: l.body + " " + l.title).isEmpty, l.body)
                            let lower = (l.body + l.title).lowercased()
                            for word in ["secure", "unrecoverable", "forensic", "certified", "!", "wipe", "shred"] { XCTAssertFalse(lower.contains(word), "\(word): \(l.body)") }
                        }
                        let byID = Dictionary(uniqueKeysWithValues: ls.map { ($0.id, $0) })
                        XCTAssertEqual(byID["notReachable"]?.body, ReadinessText.notReachable)
                        XCTAssertEqual(byID["trash"]?.body, "Moving to the Trash does not erase anything; the data stays until the Trash is emptied and the space is reused.")
                        if internalDisk == false { XCTAssertFalse(byID["encryption"]?.body.contains("This Mac encrypts its storage") ?? true) }
                      }
                    }
                }
            }
        }
        XCTAssertEqual(ReadinessText.notReachable, "Not reachable by this app: unified log, FSEvents, snapshots, backups, iCloud copies, keychain items, login-item records.")
    }

    func testThreatTable() {
        let t = ReadinessText.threats()
        XCTAssertGreaterThanOrEqual(t.count, 4)
        for row in t {
            XCTAssertFalse(row.who.isEmpty)
            XCTAssertFalse(row.answer.isEmpty)
            XCTAssertTrue(BannedPhrases.hits(in: row.who + " " + row.answer).isEmpty)
            XCTAssertFalse(row.answer.contains("!"))
            if row.answer.contains("encrypts its storage") { XCTAssertTrue(row.answer.contains("FileVault off"), row.answer) }
        }
    }
}
