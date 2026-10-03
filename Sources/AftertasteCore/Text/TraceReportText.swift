import Foundation

/// The Trace Report (APP4 §2.4): a list of what was found, with measured numbers only. The card is the "before" screen:
/// no "recoverable", no "erased", no keychain line, no lines with a zero count.
public enum TraceReportText {
    public struct Options: Sendable {
        public var hideNames: Bool
        public var includeRows: Bool
        public var appVersion: String
        public var isSample: Bool

        public init(hideNames: Bool = false, includeRows: Bool = true, appVersion: String = "", isSample: Bool = false) {
            self.hideNames = hideNames
            self.includeRows = includeRows
            self.appVersion = appVersion
            self.isSample = isSample
        }
    }

    public static let footer = "This is a list of what was found in the places listed above. It is not proof that anything was erased."
    public static let sampleWatermark = "Sample data"
    /// Evidence whose detail is a name or an ID, so it is hidden when names are. The rest is a date, a count or another app's name.
    private static let namingEvidence: Set<EvidenceKind> = [
        .exactID, .helperSuffix, .embeddedID, .teamPrefix, .groupID, .containerMetadata, .launchdLabelIsID, .launchdProgramInBundle,
        .launchdProgramGone, .receipt, .caskZap, .displayName, .executableName,
    ]
    private static let keptExtensions: Set<String> = ["plist", "savedState", "binarycookies", "sfl", "sfl2", "sfl3", "log"]

    // MARK: report

    public static func report(from result: ScanResult, options: Options, now: Date) -> TraceReport {
        let labels = options.hideNames ? Redaction.labels(for: result.groups.map(\.owner)) : [:]
        var apps: [TraceApp] = []
        for group in result.groups {
            let label = labels[group.owner.bundleID] ?? group.owner.displayName
            let left = group.leftBehind
            let agents: Set<LibraryRoot> = [.launchAgents, .systemLaunchAgents]
            var rows: [TraceRow] = []
            if options.includeRows {
                let shown = group.items.filter { $0.ruleID != "APP" }
                var paths = shown.map { PathText.tilde($0.path, home: result.home) }
                var whys = shown.map(\.why)
                if options.hideNames {
                    // The matched leaf is replaced whole (its name can hold fragments no token list knows); only a known extension stays.
                    let stems: [(String, String)] = shown.map { item in
                        let leaf = (item.path as NSString).lastPathComponent
                        let ext = (leaf as NSString).pathExtension
                        let parent = Redaction.apply(PathText.tilde((item.path as NSString).deletingLastPathComponent, home: result.home), owner: group.owner, label: label)
                        return (parent + "/" + label, keptExtensions.contains(ext) ? "." + ext : "")
                    }
                    // Rows of one app would otherwise collapse into the same line: number the ones that collide.
                    var total: [String: Int] = [:], next: [String: Int] = [:]
                    for s in stems { total[s.0 + s.1, default: 0] += 1 }
                    paths = stems.map { s in
                        let key = s.0 + s.1
                        guard total[key, default: 0] > 1 else { return key }
                        next[key, default: 0] += 1
                        return s.0 + " (\(next[key, default: 0]))" + s.1
                    }
                    whys = shown.map { item in
                        var why = item.why
                        // The other app's name is neither the owner's to hide with the owner's label nor the report's to show.
                        for e in item.evidence where e.kind == .sameTeamInstalled { why = why.replacingOccurrences(of: " (\(e.detail))", with: "") }
                        let leaf = (item.path as NSString).lastPathComponent
                        // Only evidence that names something is a token: dates and day counts would be replaced by the label.
                        let extra = ([leaf] + item.evidence.filter { namingEvidence.contains($0.kind) }.map(\.detail)).filter { $0.count >= 3 }
                        return Redaction.apply(why, owner: group.owner, label: label, extra: extra)
                    }
                }
                for (i, item) in shown.enumerated() {
                    rows.append(TraceRow(path: paths[i], kind: item.kind, tier: item.tier, bytes: item.size, lowerBound: item.sizeState == .atLeast, why: whys[i]))
                }
            }
            apps.append(TraceApp(label: label, version: options.hideNames ? nil : group.owner.version,
                                 bundleID: options.hideNames ? nil : group.owner.bundleID,
                                 files: left.reduce(0) { $0 + $1.fileCount }, bytes: left.reduce(0) { $0 + $1.size },
                                 lowerBound: left.contains { $0.sizeState != .measured },
                                 unmeasuredCount: left.filter { $0.sizeState == .notMeasured }.count,
                                 launchAgents: left.filter { item in item.root.map { agents.contains($0) } ?? false }.count,
                                 launchDaemons: left.filter { $0.root == .systemLaunchDaemons }.count,
                                 privilegedHelpers: left.filter { $0.root == .systemPrivilegedHelperTools }.count, rows: rows))
        }
        let c = result.coverage
        let unreadable = c.places.filter { $0.state != .read && $0.state != .absent }.map(\.root.displayName)
        return TraceReport(generatedAt: now, kind: result.kind, apps: apps, coverage: c.facts, unreadablePlaces: unreadable,
                           osVersion: result.osVersion, appVersion: options.appVersion, namesHidden: options.hideNames, isSample: options.isSample)
    }

    // MARK: card

    public static func card(from report: TraceReport) -> ShareCard {
        let subject: String
        if report.apps.count == 1, let app = report.apps.first {
            subject = [app.label, app.version].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " ")
        } else if report.apps.isEmpty {
            subject = "No apps"
        } else {
            subject = "\(report.apps.count) removed apps"
        }
        return ShareCard(subject: subject, files: report.files, bytes: report.bytes, lowerBound: report.lowerBound,
                         unmeasuredCount: report.unmeasuredCount, launchAgents: report.launchAgents, launchDaemons: report.launchDaemons,
                         privilegedHelpers: report.privilegedHelpers, coverage: report.coverage, osVersion: report.osVersion,
                         scannedAt: report.generatedAt, isSample: report.isSample)
    }

    /// "Orbit Meet 6.2 left behind"
    public static func headline(_ c: ShareCard) -> String { "\(c.subject) left behind" }

    /// "214 files · 1.3 GB · 2 launch agents · 1 launch daemon · 1 privileged helper": lines with a zero count are omitted. A total that is only a
    /// floor reads "at least 214 files · at least 1.3 GB · 2 items not measured".
    public static func figures(_ c: ShareCard) -> String {
        var parts: [String] = []
        if c.files > 0 { parts.append((c.lowerBound ? "at least " : "") + Format.count(c.files, "file")) }
        if c.bytes > 0 { parts.append(c.lowerBound ? Format.atLeast(c.bytes) : Format.bytes(c.bytes)) }
        if c.launchAgents > 0 { parts.append(Format.count(c.launchAgents, "launch agent")) }
        if c.launchDaemons > 0 { parts.append(Format.count(c.launchDaemons, "launch daemon")) }
        if c.privilegedHelpers > 0 { parts.append(Format.count(c.privilegedHelpers, "privileged helper")) }
        if c.unmeasuredCount > 0 { parts.append(Format.count(c.unmeasuredCount, "item") + " not measured") }
        return parts.isEmpty ? (c.coverage.recentlyRemoved > 0 ? "Nothing found yet" : "Nothing found") : parts.joined(separator: " · ")
    }

    /// "Looked in 16 of 17 places. 1 protected by macOS." Worded by `PlanText.coverageLine`, like the app and the file.
    public static func coverage(_ c: ShareCard) -> String { PlanText.coverageLine(c.coverage) }

    /// Only when the card counts launch agents, launch daemons or helpers; it names the ones it counts.
    public static func listedNote(_ c: ShareCard) -> String? {
        let nouns = [c.launchAgents > 0 ? "launch agents" : nil, c.launchDaemons > 0 ? "launch daemons" : nil, c.privilegedHelpers > 0 ? "helpers" : nil].compactMap { $0 }
        guard let last = nouns.last else { return nil }
        let list = nouns.count == 1 ? last : nouns.dropLast().joined(separator: ", ") + " and " + last
        return list.prefix(1).uppercased() + list.dropFirst() + " are listed, not removed."
    }

    /// "macOS 26.1 · scanned 2026-10-03 · measured on this Mac, nothing sent anywhere"
    public static func provenance(_ c: ShareCard) -> String {
        var parts: [String] = []
        if !c.osVersion.isEmpty { parts.append("macOS \(c.osVersion)") }
        parts.append("scanned \(Format.date(c.scannedAt))")
        parts.append("measured on this Mac, nothing sent anywhere")
        return parts.joined(separator: " · ")
    }

    /// The pasteboard fallback: the card as text. The caller passes the site address.
    public static func plainText(_ c: ShareCard, footer: String) -> String {
        var lines = ["AFTERTASTE" + (c.isSample ? "  " + sampleWatermark : ""), headline(c), "", figures(c), "", coverage(c)]
        if let note = listedNote(c) { lines.append(note) }
        lines += ["", provenance(c), footer]
        return lines.joined(separator: "\n")
    }

    // MARK: files

    public static func markdown(_ r: TraceReport) -> String {
        var out: [String] = ["# What Aftertaste found on this Mac on \(Format.date(r.generatedAt))", ""]
        if r.isSample { out += ["_\(sampleWatermark)_", ""] }
        out += [PlanText.coverageLine(r.coverage)]
        if !r.unreadablePlaces.isEmpty { out += ["Not read: " + r.unreadablePlaces.joined(separator: ", ") + "."] }
        var provenance = ["measured on this Mac, nothing sent anywhere"]
        if !r.osVersion.isEmpty { provenance.insert("macOS \(r.osVersion)", at: 0) }
        if !r.appVersion.isEmpty { provenance.append("Aftertaste \(r.appVersion)") }
        out += [provenance.joined(separator: " · "), ""]
        if r.apps.isEmpty { out += ["Nothing was found in the places listed.", ""] }
        for app in r.apps {
            out += ["## " + [app.label, app.version].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " ")]
            if let id = app.bundleID { out += ["`\(id)`"] }
            let c = ShareCard(subject: app.label, files: app.files, bytes: app.bytes, lowerBound: app.lowerBound,
                              unmeasuredCount: app.unmeasuredCount, launchAgents: app.launchAgents, launchDaemons: app.launchDaemons,
                              privilegedHelpers: app.privilegedHelpers, coverage: r.coverage, osVersion: r.osVersion, scannedAt: r.generatedAt)
            out += ["", figures(c), ""]
            if !app.rows.isEmpty {
                out += ["| Item | Kind | Tier | Size | Why |", "| --- | --- | --- | --- | --- |"]
                for row in app.rows {
                    out.append("| `\(cell(row.path))` | \(row.kind.displayName) | \(row.tier.displayName) | \(row.bytes > 0 ? (row.lowerBound ? Format.atLeast(row.bytes) : Format.bytes(row.bytes)) : "–") | \(cell(row.why)) |")
                }
                out.append("")
            }
            if let note = listedNote(c) { out += [note, ""] }
        }
        out += ["## Not covered", ""] + PlanText.notCovered().map { "- " + $0 } + ["", "---", footer]
        return out.joined(separator: "\n") + "\n"
    }

    public static func json(_ r: TraceReport) -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .prettyPrinted, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = ISO8601Lite.encodeStrategy()
        guard let data = try? encoder.encode(r), let text = String(data: data, encoding: .utf8) else { return "{}" }
        return text
    }

    private static func cell(_ s: String) -> String {
        s.replacingOccurrences(of: "|", with: "\\|").replacingOccurrences(of: "\n", with: " ")
    }
}
