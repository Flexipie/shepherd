import SwiftUI

/// Text with some ranges emphasised: the characters a palette query matched, bold in the accent
/// colour.
enum Highlighted {
    static func text(_ string: String, _ ranges: [Range<String.Index>]) -> Text {
        var text = Text("")
        var cursor = string.startIndex
        for range in ranges where range.lowerBound >= cursor && range.upperBound <= string.endIndex {
            if cursor < range.lowerBound { text = Text("\(text)\(Text(string[cursor..<range.lowerBound]))") }
            let match = Text(string[range]).fontWeight(.bold).foregroundStyle(Color.accentColor)
            text = Text("\(text)\(match)")
            cursor = range.upperBound
        }
        guard cursor > string.startIndex else { return Text(string) }
        if cursor < string.endIndex { text = Text("\(text)\(Text(string[cursor...]))") }
        return text
    }
}
