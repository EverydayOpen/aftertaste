import Foundation

/// "Hide app names": an installed-app list is itself sensitive, so exports can replace every spelling of an app's identity
/// with "App 1", "App 2".
public enum Redaction {
    /// bundleID -> "App 1", "App 2" in the order given (duplicates share a label).
    public static func labels(for owners: [AppIdentity]) -> [String: String] {
        var out: [String: String] = [:]
        for owner in owners where out[owner.bundleID] == nil { out[owner.bundleID] = "App \(out.count + 1)" }
        return out
    }

    /// Replaces the bundle ID, every ID the app owns, its group IDs and Team ID, its executable and every spelling of its
    /// display name (as-is, without spaces, with hyphens or underscores, version word removed), case-insensitively.
    /// `extra` are further spellings to hide (the matched file name, an evidence detail).
    public static func apply(_ text: String, owner: AppIdentity, label: String, extra: [String] = []) -> String {
        var tokens: [String] = owner.allIDs + owner.groupIDs + extra
        tokens += [owner.bundleID, owner.execName, owner.caskToken ?? "", owner.teamID ?? ""]
        for form in nameForms(owner.displayName) { tokens.append(form) }
        let unique = Array(Set(tokens.filter { $0.count >= 3 })).sorted { $0.count != $1.count ? $0.count > $1.count : $0 < $1 }
        // Swap in a placeholder first so a token that appears inside the label itself ("App") is not replaced twice.
        let placeholder = "\u{1}"
        var result = text
        for token in unique { result = result.replacingOccurrences(of: token, with: placeholder, options: .caseInsensitive) }
        return result.replacingOccurrences(of: placeholder, with: label)
    }

    static func nameForms(_ display: String) -> [String] {
        let words = display.split(whereSeparator: { $0 == " " || $0 == "\t" }).map(String.init)
        var shorter = words
        while shorter.count > 1, let last = shorter.last, last.allSatisfy({ $0.isNumber || $0 == "." || $0 == "v" }) || Hazards.channelFamilyTokens.contains(last.lowercased()) {
            shorter.removeLast()
        }
        var out: [String] = []
        for form in [words, shorter] {
            for sep in [" ", "", "-", "_"] { out.append(form.joined(separator: sep)) }
        }
        return out
    }
}
