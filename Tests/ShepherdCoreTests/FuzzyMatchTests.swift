import Testing
@testable import ShepherdCore

@Suite struct FuzzyMatchTests {
    func matched(_ query: String, _ text: String) -> [String]? {
        FuzzyMatch.score(query, in: text).map { result in result.ranges.map { String(text[$0]) } }
    }

    @Test func matchesASubsequenceInOrder() {
        #expect(matched("apr", "api review") == ["ap", "r"])
        #expect(FuzzyMatch.score("rpa", in: "api review") == nil)
        #expect(FuzzyMatch.score("x", in: "api") == nil)
        #expect(FuzzyMatch.score("apis", in: "api") == nil)
    }

    @Test func emptyQueryMatchesWithNothingHighlighted() {
        #expect(FuzzyMatch.score("", in: "api")?.ranges.isEmpty == true)
    }

    @Test func ignoresCaseAndDiacritics() {
        #expect(matched("CAFE", "Café menu") == ["Café"])
        #expect(matched("ü", "Über") == ["Ü"])
    }

    @Test func prefersWordStartsAndRuns() throws {
        // "ar" as the starts of "api review" beats the run inside "bar".
        let starts = try #require(FuzzyMatch.score("ar", in: "api review"))
        let inside = try #require(FuzzyMatch.score("ar", in: "foobar"))
        #expect(starts.score > inside.score)
        // The word start is picked over an earlier match mid-word.
        #expect(matched("r", "error report") == ["r"])
        #expect(FuzzyMatch.score("r", in: "error report")?.ranges.first?.lowerBound == "error report".firstIndex(of: " ").map {
            "error report".index(after: $0)
        })
        // camelCase and digits after letters start words too.
        #expect(matched("rw", "readWrite") == ["r", "W"])
        #expect(matched("pr142", "pr #142") == ["pr", "142"])
    }

    @Test func prefixesAndShorterGapsScoreHigher() throws {
        let prefix = try #require(FuzzyMatch.score("api", in: "api"))
        let later = try #require(FuzzyMatch.score("api", in: "the api"))
        let spread = try #require(FuzzyMatch.score("api", in: "a pretty idea"))
        #expect(prefix.score > later.score)
        #expect(later.score > spread.score)
    }

    @Test func rangesMergeConsecutiveCharacters() {
        let text = "claude code"
        let ranges = FuzzyMatch.score("clco", in: text)?.ranges
        #expect(ranges?.count == 2)
        #expect(ranges.map { $0.map { String(text[$0]) } } == ["cl", "co"])
    }
}
