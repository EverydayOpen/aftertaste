import Foundation

/// Plain text helpers: sizes, counts and dates that read the same on every platform and locale (BUILD_PLAN §4.8).
public enum Format {
    /// Finder-style decimal units (1000), as Whydunit's ByteFormat: "999 bytes", "412 KB", "1.3 GB", "340 GB".
    public static func bytes(_ n: UInt64) -> String {
        if n < 1000 { return n == 1 ? "1 byte" : "\(n) bytes" }
        let units = ["KB", "MB", "GB", "TB", "PB"]
        var value = Double(n) / 1000
        var unit = 0
        while true {
            // KB is always whole; larger units get one decimal below 100 ("1.2 MB", "340 GB").
            let tenths = Int((value * 10).rounded())
            let oneDecimal = unit > 0 && tenths < 1000
            let whole = Int(value.rounded())
            if whole >= 1000 && unit < units.count - 1 {
                value /= 1000
                unit += 1
                continue
            }
            if oneDecimal && tenths % 10 != 0 { return "\(tenths / 10).\(tenths % 10) \(units[unit])" }
            return "\(oneDecimal ? tenths / 10 : whole) \(units[unit])"
        }
    }

    /// "at least 3 GB": a walk that hit a budget only knows a lower bound.
    public static func atLeast(_ n: UInt64) -> String { "at least " + bytes(n) }

    /// The figure, or "at least" the figure when it is only a floor.
    public static func size(_ n: UInt64, atLeast floor: Bool) -> String { floor ? atLeast(n) : bytes(n) }

    /// "1 item", "14 items". Regular plurals only (item, place, app, file, snapshot ...).
    public static func count(_ n: Int, _ noun: String) -> String { "\(n) \(noun)\(n == 1 ? "" : "s")" }

    /// "2026-10-03", UTC.
    public static func date(_ d: Date) -> String {
        let p = Civil.parts(d)
        return "\(p.year)-\(Civil.pad(p.month))-\(Civil.pad(p.day))"
    }

    /// A size as the preview shows it: "12 MB", "at least 3 GB", "size not measured".
    public static func size(_ bytes: UInt64, _ state: SizeState) -> String {
        switch state {
        case .measured: return Format.bytes(bytes)
        case .atLeast: return atLeast(bytes)
        case .notMeasured: return "size not measured"
        }
    }
}

public enum PathText {
    /// "/Users/jane/Library/x" -> "~/Library/x". Only whole path components match, so "/Users/janet" is not under "/Users/jane".
    public static func tilde(_ path: String, home: String) -> String {
        let p = GuardPolicy.normalize(path)
        let h = GuardPolicy.normalize(home)
        guard !h.isEmpty, h != "/" else { return p }
        if p == h { return "~" }
        if p.hasPrefix(h + "/") { return "~" + String(p.dropFirst(h.count)) }
        return p
    }

    /// The reverse of `tilde`: "~/Library/x" -> "/Users/jane/Library/x"; anything else is returned unchanged.
    public static func expandTilde(_ path: String, home: String) -> String {
        let h = GuardPolicy.normalize(home)
        if path == "~" { return h }
        if path.hasPrefix("~/") { return (h == "/" ? "" : h) + String(path.dropFirst(1)) }
        return path
    }
}

/// UTC calendar arithmetic without Calendar or DateFormatter (identical on Linux and macOS, no locale, no allocation storms).
enum Civil {
    struct Parts: Equatable {
        var year: Int, month: Int, day: Int, hour: Int, minute: Int, second: Int
    }

    static func pad(_ n: Int, _ width: Int = 2) -> String {
        let s = String(n)
        return s.count >= width ? s : String(repeating: "0", count: width - s.count) + s
    }

    /// Days since 1970-01-01 -> civil date (Howard Hinnant's algorithm).
    static func parts(_ date: Date) -> Parts {
        // Clamp so a corrupt timestamp can never trap the conversion.
        let raw = date.timeIntervalSince1970
        let t = raw.isFinite ? Int64(max(-1e13, min(1e13, raw)).rounded(.down)) : 0
        var days = t / 86_400
        var rem = t % 86_400
        if rem < 0 { rem += 86_400; days -= 1 }
        let z = days + 719_468
        let era = (z >= 0 ? z : z - 146_096) / 146_097
        let doe = z - era * 146_097
        let yoe = (doe - doe / 1460 + doe / 36_524 - doe / 146_096) / 365
        let y = yoe + era * 400
        let doy = doe - (365 * yoe + yoe / 4 - yoe / 100)
        let mp = (5 * doy + 2) / 153
        let d = doy - (153 * mp + 2) / 5 + 1
        let m = mp < 10 ? mp + 3 : mp - 9
        return Parts(year: Int(m <= 2 ? y + 1 : y), month: Int(m), day: Int(d), hour: Int(rem / 3600), minute: Int(rem % 3600 / 60),
                     second: Int(rem % 60))
    }

    static func date(year: Int, month: Int, day: Int, hour: Int = 0, minute: Int = 0, second: Int = 0) -> Date {
        let y = Int64(month <= 2 ? year - 1 : year)
        let era = (y >= 0 ? y : y - 399) / 400
        let yoe = y - era * 400
        let m = Int64(month)
        let doy = (153 * (m > 2 ? m - 3 : m + 9) + 2) / 5 + Int64(day) - 1
        let doe = yoe * 365 + yoe / 4 - yoe / 100 + doy
        let days = era * 146_097 + doe - 719_468
        return Date(timeIntervalSince1970: Double(days * 86_400 + Int64(hour * 3600 + minute * 60 + second)))
    }
}

/// "2026-10-03T10:15:00Z": the only date spelling in the journal and the JSON report.
enum ISO8601Lite {
    static func string(_ d: Date) -> String {
        let p = Civil.parts(d)
        return "\(Civil.pad(p.year, 4))-\(Civil.pad(p.month))-\(Civil.pad(p.day))T\(Civil.pad(p.hour)):\(Civil.pad(p.minute)):\(Civil.pad(p.second))Z"
    }

    /// Accepts "YYYY-MM-DDTHH:MM:SS" with optional fractional seconds, then "Z". Nothing else.
    static func parse(_ s: String) -> Date? {
        let u = Array(s.utf8)
        guard u.count >= 20, u[4] == 45, u[7] == 45, u[10] == 84, u[13] == 58, u[16] == 58 else { return nil }
        func num(_ a: Int, _ b: Int) -> Int? {
            var v = 0
            for i in a..<b {
                guard u[i] >= 48, u[i] <= 57 else { return nil }
                v = v * 10 + Int(u[i] - 48)
            }
            return v
        }
        guard let y = num(0, 4), let mo = num(5, 7), let d = num(8, 10), let h = num(11, 13), let mi = num(14, 16), let se = num(17, 19),
              (1...12).contains(mo), (1...31).contains(d), h < 24, mi < 60, se < 61 else { return nil }
        var i = 19
        var fraction = 0.0
        if u[i] == 46 {
            i += 1
            var scale = 0.1
            while i < u.count, u[i] >= 48, u[i] <= 57 {
                fraction += Double(u[i] - 48) * scale
                scale /= 10
                i += 1
            }
        }
        guard i == u.count - 1, u[i] == 90 else { return nil }
        return Civil.date(year: y, month: mo, day: d, hour: h, minute: mi, second: se).addingTimeInterval(fraction)
    }

    static func encodeStrategy() -> JSONEncoder.DateEncodingStrategy {
        .custom { date, encoder in
            var c = encoder.singleValueContainer()
            try c.encode(string(date))
        }
    }

    static func decodeStrategy() -> JSONDecoder.DateDecodingStrategy {
        .custom { decoder in
            let s = try decoder.singleValueContainer().decode(String.self)
            guard let d = parse(s) else {
                throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "Not an ISO-8601 UTC date."))
            }
            return d
        }
    }
}
