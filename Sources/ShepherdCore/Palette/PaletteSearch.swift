/// Ranks palette items for a query. Each word of the query must match one of an item's words
/// (its title, project, status, kind or token values); the title counts most. With no query, the
/// items keep their order: agents that need the user first, as the index builds them.
public enum PaletteSearch {
    public static let limit = 50

    public static func results(_ items: [PaletteItem], query: String, limit: Int = PaletteSearch.limit) -> [PaletteResult] {
        let terms = query.split(whereSeparator: \.isWhitespace).map(String.init)
        guard !terms.isEmpty else { return items.prefix(limit).map { PaletteResult(item: $0) } }
        let scored = items.enumerated().compactMap { index, item -> (PaletteResult, score: Int, index: Int)? in
            guard let (score, highlights) = match(terms, item) else { return nil }
            return (PaletteResult(item: item, highlights: highlights), score, index)
        }
        return scored
            .sorted { a, b in
                if a.score != b.score { return a.score > b.score }
                if a.0.item.needsYou != b.0.item.needsYou { return a.0.item.needsYou }
                return a.index < b.index
            }
            .prefix(limit)
            .map(\.0)
    }

    /// The summed best score of each term, and the characters of the title the terms match; nil
    /// when a term matches nothing.
    static func match(_ terms: [String], _ item: PaletteItem) -> (Int, [Range<String.Index>])? {
        var total = 0
        var highlights: [Range<String.Index>] = []
        for term in terms {
            var best: Int?
            for (index, text) in item.searchText.enumerated() {
                guard let (score, ranges) = FuzzyMatch.score(term, in: text) else { continue }
                // Other words count two thirds, so a name match beats the same match in a token.
                let weighted = index == 0 ? score : score * 2 / 3
                best = max(best ?? weighted, weighted)
                // The title shows what it matched even when another word matched better.
                if index == 0 { highlights += ranges }
            }
            guard let best else { return nil }
            total += best
        }
        return (total, highlights.sorted { $0.lowerBound < $1.lowerBound })
    }
}
