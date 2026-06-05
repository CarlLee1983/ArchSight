import Foundation

/// Lightweight fuzzy subsequence matcher for the Quick Open panel. Pure value
/// logic so it is unit-testable without any UI. Scoring favors matches that are
/// consecutive and that land at path-segment starts (filename hits).
public enum FuzzyMatch {
    private static let segmentBonus = 6
    private static let consecutiveBonus = 8

    /// True when every character of `query` appears in `candidate` in order
    /// (case-insensitive).
    public static func matches(_ query: String, in candidate: String) -> Bool {
        score(query, in: candidate) != nil
    }

    /// Greedy subsequence score; higher is better. Returns nil when `candidate`
    /// does not contain `query` as a subsequence. Empty query scores 0.
    public static func score(_ query: String, in candidate: String) -> Int? {
        if query.isEmpty {
            return 0
        }
        let needles = Array(query.lowercased())
        let haystack = Array(candidate.lowercased())
        var needleIndex = 0
        var total = 0
        var previousMatched = false

        for (index, character) in haystack.enumerated() {
            guard needleIndex < needles.count, character == needles[needleIndex] else {
                previousMatched = false
                continue
            }
            var points = 1
            let atSegmentStart = index == 0 || haystack[index - 1] == "/"
            if atSegmentStart {
                points += segmentBonus
            }
            if previousMatched {
                points += consecutiveBonus
            }
            total += points
            needleIndex += 1
            previousMatched = true
        }

        return needleIndex == needles.count ? total : nil
    }

    /// Filters out non-matches and ranks the rest best-first. An empty query
    /// returns the candidates unchanged. Ties preserve input order.
    public static func rank(_ query: String, candidates: [String]) -> [String] {
        if query.isEmpty {
            return candidates
        }
        return candidates
            .enumerated()
            .compactMap { offset, candidate -> (offset: Int, candidate: String, score: Int)? in
                guard let value = score(query, in: candidate) else {
                    return nil
                }
                return (offset, candidate, value)
            }
            .sorted { lhs, rhs in
                lhs.score != rhs.score ? lhs.score > rhs.score : lhs.offset < rhs.offset
            }
            .map(\.candidate)
    }
}
