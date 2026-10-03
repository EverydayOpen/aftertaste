import Foundation

/// Phrases Aftertaste never uses to describe itself (APP4 §1.2). `patterns` is a copy of the non-comment lines of
/// `tools/banned_phrases.txt`, the single source of truth that the CI grep reads; a test compares the two so they cannot drift.
/// This file is exempt from the grep because it has to spell the phrases.
public enum BannedPhrases {
    public static let patterns: [String] = [
        "secure(ly)? +erase",
        "secure(ly)? +delete",
        "permanently +delete",
        "permanently +gone",
        "unrecoverable",
        "irrecoverable",
        "cannot +be +recovered",
        "forensic-proof",
        "anti-forensic",
        "\\bmilitary\\b",
        "\\bDoD\\b",
        "\\bNSA\\b",
        "Gutmann",
        "\\bshred",
        "\\bwipe",
        "100% +gone",
        "\\bguarantee",
        "\\bcertified\\b",
        "certificate +of",
        "\\bcompliant\\b",
        "\\bGDPR\\b",
        "\\bHIPAA\\b",
        "clean +your +Mac",
        "\\bjunk\\b",
    ]

    /// The marker a line carries when it names a phrase only to say Aftertaste does not make that claim.
    public static let marker = "no-claim-ok"

    private static let expressions: [NSRegularExpression] = patterns.compactMap { try? NSRegularExpression(pattern: $0, options: [.caseInsensitive]) }

    /// The offending text, in order, for every banned phrase found. A line that carries the marker is skipped.
    public static func hits(in text: String) -> [String] {
        var out: [String] = []
        for line in text.split(omittingEmptySubsequences: false, whereSeparator: \.isNewline) {
            let s = String(line)
            if s.contains(marker) { continue }
            let range = NSRange(s.startIndex..<s.endIndex, in: s)
            for expression in expressions {
                for match in expression.matches(in: s, options: [], range: range) {
                    if let r = Range(match.range, in: s) { out.append(String(s[r])) }
                }
            }
        }
        return out
    }
}
