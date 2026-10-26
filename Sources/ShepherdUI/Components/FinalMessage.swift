import SwiftUI

/// An agent's whole last message, in the box the stage and the palette use for its last lines.
/// Inline Markdown (bold, code, links) is drawn; line breaks are kept. Selectable, so a sentence
/// can be copied. With `maxHeight`, a longer message scrolls from its start.
struct FinalMessage: View {
    let message: String
    var maxHeight: CGFloat?

    @State private var height: CGFloat = 0

    var body: some View {
        Group {
            if let maxHeight {
                ScrollView {
                    text.onGeometryChange(for: CGFloat.self) { $0.size.height } action: { height = $0 }
                }
                .scrollBounceBehavior(.basedOnSize)
                .frame(height: min(max(height, 1), maxHeight))
            } else {
                text
            }
        }
        .background(RoundedRectangle(cornerRadius: 8).fill(Color.primary.opacity(0.06)))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Last message")
        .accessibilityValue(String(Self.attributed(message).characters))
    }

    private var text: some View {
        Text(Self.attributed(message))
            .font(.system(size: 12))
            .textSelection(.enabled)
            .frame(maxWidth: .infinity, alignment: .topLeading)
            .fixedSize(horizontal: false, vertical: true)
            .padding(8)
    }

    /// The message with its inline Markdown applied, or as plain text when it does not parse.
    static func attributed(_ message: String) -> AttributedString {
        let options = AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        return (try? AttributedString(markdown: message, options: options)) ?? AttributedString(message)
    }
}
