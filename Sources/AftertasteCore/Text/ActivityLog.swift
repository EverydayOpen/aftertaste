import Foundation

/// The journal's line format: one JSON object per line, sorted keys, dates as ISO-8601 whole seconds in UTC.
/// An `ActivityEntry` has no field for file contents, command lines or anything but what the screen showed.
public enum ActivityLog {
    /// "journal-2026-10.jsonl" (UTC month): one file per month.
    public static func fileName(for date: Date) -> String {
        let p = Civil.parts(date)
        return "journal-\(Civil.pad(p.year, 4))-\(Civil.pad(p.month)).jsonl"
    }

    public static func isJournalFile(_ name: String) -> Bool {
        let u = Array(name.utf8)
        guard u.count == "journal-2026-10.jsonl".utf8.count, name.hasPrefix("journal-"), name.hasSuffix(".jsonl") else { return false }
        let digits = Array(u[8..<15])
        return digits.enumerated().allSatisfy { $0.offset == 4 ? $0.element == 45 : ($0.element >= 48 && $0.element <= 57) }
    }

    /// One line, no trailing newline.
    public static func encode(_ e: ActivityEntry) -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = ISO8601Lite.encodeStrategy()
        guard let data = try? encoder.encode(e), let line = String(data: data, encoding: .utf8) else { return "" }
        return line
    }

    public static func decode(line: String) -> ActivityEntry? {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = ISO8601Lite.decodeStrategy()
        return try? decoder.decode(ActivityEntry.self, from: Data(line.utf8))
    }

    /// Tolerant: blank lines are ignored, a torn or damaged line is counted in `skippedLines` and never stops the rest.
    public static func decodeAll(_ text: String) -> (entries: [ActivityEntry], skippedLines: Int) {
        var entries: [ActivityEntry] = []
        var skipped = 0
        for raw in text.split(whereSeparator: \.isNewline) {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.isEmpty { continue }
            if let e = decode(line: line) { entries.append(e) } else { skipped += 1 }
        }
        return (entries, skipped)
    }
}
