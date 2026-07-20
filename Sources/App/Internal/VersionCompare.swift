import Foundation

/// Dotted-numeric version comparison. Pure and dependency-free so it can be
/// self-checked standalone (see Tests/version_compare_check.swift).
enum VersionCompare {
    /// True when `latest` represents a strictly newer release than `current`.
    /// Tolerates a leading "v", differing component counts, and trailing
    /// pre-release suffixes (only the leading integer of each dotted part counts).
    static func isNewer(_ latest: String, than current: String) -> Bool {
        let a = components(latest)
        let b = components(current)
        for i in 0 ..< max(a.count, b.count) {
            let l = i < a.count ? a[i] : 0
            let c = i < b.count ? b[i] : 0
            if l != c { return l > c }
        }
        return false
    }

    private static func components(_ raw: String) -> [Int] {
        let trimmed = raw.trimmingCharacters(in: .whitespaces)
            .drop { $0 == "v" || $0 == "V" }
        return trimmed.split(separator: ".").map { part in
            Int(part.prefix { $0.isNumber }) ?? 0
        }
    }
}
