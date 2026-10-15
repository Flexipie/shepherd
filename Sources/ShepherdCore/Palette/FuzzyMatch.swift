import Foundation

/// Fuzzy matching for the palette: the query's characters must appear in the text in order,
/// ignoring case and diacritics. Matches that start words, run together or start the text score
/// higher, and gaps between matched characters cost a little, so "api" ranks "api" above
/// "a pretty idea".
public enum FuzzyMatch {
    static let matchScore = 16
    static let wordStartBonus = 24
    static let consecutiveBonus = 32
    static let prefixBonus = 16
    /// Per character skipped between two matched ones.
    static let gapPenalty = 2
    /// Characters skipped before the first match cost the same, up to this many.
    static let maxLeadingPenalty = 10

    /// The best way to match `query` in `text`, with the matched characters as ranges of `text`,
    /// or nil when it does not match. An empty query matches with no ranges.
    public static func score(_ query: String, in text: String) -> (score: Int, ranges: [Range<String.Index>])? {
        let needle = query.map(fold)
        guard !needle.isEmpty else { return (0, []) }
        let indices = Array(text.indices)
        let hay = text.map(fold)
        guard isSubsequence(needle, of: hay) else { return nil }
        let characters = Array(text)
        let starts = characters.indices.map { isWordStart(characters, at: $0) }

        let n = hay.count, m = needle.count
        let none = Int.min / 2
        // best[i][j]: the best score with query character i matched at text position j; from[i][j]
        // is where query character i - 1 was matched on that path.
        var best = [[Int]](repeating: [Int](repeating: none, count: n), count: m)
        var from = [[Int]](repeating: [Int](repeating: -1, count: n), count: m)
        for j in 0..<n where hay[j] == needle[0] {
            var score = matchScore + (starts[j] ? wordStartBonus : 0) - min(j, maxLeadingPenalty) * gapPenalty
            if j == 0 { score += prefixBonus }
            best[0][j] = score
        }
        for i in 1..<m {
            // The best earlier match, seen from j with the gap penalty counted linearly:
            // best[i - 1][k] - gap * (j - k - 1) == (best[i - 1][k] + gap * k) - gap * (j - 1).
            var runningMax = none
            var runningFrom = -1
            for j in 0..<n {
                if j >= 1, best[i - 1][j - 1] > none {
                    let candidate = best[i - 1][j - 1] + gapPenalty * (j - 1)
                    if candidate > runningMax { runningMax = candidate; runningFrom = j - 1 }
                }
                guard hay[j] == needle[i] else { continue }
                let character = matchScore + (starts[j] ? wordStartBonus : 0)
                var score = none
                var previous = -1
                if runningFrom >= 0 {
                    score = runningMax - gapPenalty * (j - 1) + character
                    previous = runningFrom
                }
                if j >= 1, best[i - 1][j - 1] > none {
                    let consecutive = best[i - 1][j - 1] + character + consecutiveBonus
                    if consecutive >= score { score = consecutive; previous = j - 1 }
                }
                if previous >= 0 {
                    best[i][j] = score
                    from[i][j] = previous
                }
            }
        }

        guard let end = (0..<n).max(by: { best[m - 1][$0] < best[m - 1][$1] }), best[m - 1][end] > none else { return nil }
        var positions = [end]
        var j = end
        for i in stride(from: m - 1, to: 0, by: -1) {
            j = from[i][j]
            positions.append(j)
        }
        positions.reverse()
        return (best[m - 1][end], ranges(positions, indices: indices, end: text.endIndex))
    }

    /// One character, folded for comparison.
    static func fold(_ character: Character) -> String {
        String(character).folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
    }

    private static func isSubsequence(_ needle: [String], of hay: [String]) -> Bool {
        var next = needle.startIndex
        for character in hay where next < needle.endIndex && character == needle[next] {
            next += 1
        }
        return next == needle.endIndex
    }

    /// The first character, one after a separator, or an upper case letter after a lower case one.
    private static func isWordStart(_ characters: [Character], at index: Int) -> Bool {
        guard index > 0 else { return true }
        let previous = characters[index - 1], current = characters[index]
        if !(previous.isLetter || previous.isNumber) { return true }
        if previous.isLowercase && current.isUppercase { return true }
        return previous.isLetter && current.isNumber
    }

    /// Matched positions as ranges, consecutive ones merged.
    private static func ranges(_ positions: [Int], indices: [String.Index], end: String.Index) -> [Range<String.Index>] {
        var ranges: [Range<String.Index>] = []
        var start = positions[0], last = positions[0]
        for position in positions.dropFirst() {
            if position == last + 1 { last = position; continue }
            ranges.append(indices[start]..<upper(last, indices, end))
            start = position
            last = position
        }
        ranges.append(indices[start]..<upper(last, indices, end))
        return ranges
    }

    private static func upper(_ position: Int, _ indices: [String.Index], _ end: String.Index) -> String.Index {
        position + 1 < indices.count ? indices[position + 1] : end
    }
}
