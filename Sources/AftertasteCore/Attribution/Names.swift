import Foundation

/// Name comparison helpers shared by the matcher, the never-list and the guard. Names are compared folded (Unicode NFC,
/// case-insensitive) because the usual APFS volume is case-insensitive; the name is always shown as stored.
enum Names {
    static func fold(_ s: String) -> String {
        // ASCII is already in normal form; skipping the Unicode pass is what keeps a whole-library scan fast.
        s.utf8.allSatisfy { $0 < 0x80 } ? s.lowercased() : s.precomposedStringWithCanonicalMapping.lowercased()
    }

    /// Labels of a dotted name, folded.
    static func labels(_ s: String) -> [String] { fold(s).split(separator: ".", omittingEmptySubsequences: true).map(String.init) }

    /// Every proper prefix of `s` that ends right before a ".", longest first: "a.b.c" -> ["a.b", "a"].
    static func dotPrefixes(_ s: String) -> [String] {
        var out: [String] = []
        var index = s.endIndex
        while let dot = s[s.startIndex..<index].lastIndex(of: ".") {
            if dot == s.startIndex { break }
            out.append(String(s[s.startIndex..<dot]))
            index = dot
        }
        return out
    }

    /// The first label after `prefix + "."` in `s` ("com.a.b.helper.x" after "com.a.b" -> "helper"), folded input expected.
    static func firstLabel(after prefix: String, in s: String) -> String? {
        guard s.hasPrefix(prefix + ".") else { return nil }
        let rest = s.dropFirst(prefix.count + 1)
        return rest.split(separator: ".", maxSplits: 1, omittingEmptySubsequences: false).first.map(String.init)
    }

    /// `name` without a trailing `ext` (compared folded); nil when it does not end with it or nothing would be left.
    static func strip(_ name: String, ext: String) -> String? {
        guard name.hasSuffix(ext), name.count > ext.count else { return nil }
        return String(name.dropLast(ext.count))
    }

    /// Display-name variants for T3 matching, folded: as-is, no spaces, hyphens, underscores, and the same with a trailing
    /// version or channel word removed ("Orbit Meet 6.2" -> "orbit meet"). Short ones (< 5) and common words are dropped.
    static func variants(ofDisplayName display: String) -> [String] {
        var base = display.trimmingCharacters(in: .whitespacesAndNewlines)
        if Names.fold(base).hasSuffix(".app") { base = String(base.dropLast(4)) }
        var words = base.split(whereSeparator: { $0 == " " || $0 == "\t" }).map(String.init)
        var forms: [[String]] = [words]
        while let last = words.last, words.count > 1, isVersionWord(last) || Hazards.channelFamilyTokens.contains(Names.fold(last)) {
            words.removeLast()
        }
        if words.count != forms[0].count { forms.append(words) }
        var out: [String] = []
        for form in forms {
            for sep in [" ", "", "-", "_"] {
                let v = fold(form.joined(separator: sep))
                if v.count >= 5, !Hazards.commonWords.contains(v), !out.contains(v) { out.append(v) }
            }
        }
        return out
    }

    static func isVersionWord(_ w: String) -> Bool {
        let t = w.lowercased()
        let body = t.hasPrefix("v") ? String(t.dropFirst()) : t
        return !body.isEmpty && body.allSatisfy { $0.isNumber || $0 == "." }
    }

    /// "com.example.orbitmeet" -> "Orbitmeet": the label shown for an orphan whose real name is unknown.
    static func prettyName(fromID id: String) -> String {
        let last = id.split(separator: ".").last.map(String.init) ?? id
        let spaced = last.replacingOccurrences(of: "-", with: " ").replacingOccurrences(of: "_", with: " ")
        return spaced.split(separator: " ").map { $0.prefix(1).uppercased() + $0.dropFirst() }.joined(separator: " ")
    }

    static func isSafeEntryName(_ name: String) -> Bool {
        !name.isEmpty && name != "." && name != ".." && !name.contains("/") && !name.unicodeScalars.contains { $0.value == 0 }
    }
}
