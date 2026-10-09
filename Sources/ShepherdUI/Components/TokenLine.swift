import ShepherdCore
import SwiftUI

/// Token lines as herdr's sidebar would draw them, in the panel's type. Colours chosen for dark
/// terminals are darkened in light mode until they read.
struct TokenLines: View {
    let lines: [[StyledToken]]
    var isLive = true

    var body: some View {
        if !lines.isEmpty {
            VStack(alignment: .leading, spacing: 1) {
                ForEach(lines.indices, id: \.self) { index in
                    TokenLine(tokens: lines[index], isLive: isLive)
                }
            }
        }
    }
}

struct TokenLine: View {
    let tokens: [StyledToken]
    var isLive = true
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        tokens.indices.reduce(Text("")) { line, index in
            let token = tokens[index]
            return index == 0 ? text(token) : Text("\(line)  \(text(token))")
        }
        .font(.system(size: 11))
        .lineLimit(1)
        .truncationMode(.tail)
    }

    private func text(_ token: StyledToken) -> Text {
        var text = Text(token.text).foregroundStyle(color(token))
        if token.bold { text = text.fontWeight(.semibold) }
        return text
    }

    private func color(_ token: StyledToken) -> Color {
        guard isLive, let fg = token.fg else { return token.dim || !isLive ? Color.secondary.opacity(0.7) : Color.secondary }
        let background = colorScheme == .dark ? HexColor.darkBackground : HexColor.lightBackground
        let readable = fg.readable(on: background)
        let color = Color(.sRGB, red: Double(readable.red) / 255, green: Double(readable.green) / 255, blue: Double(readable.blue) / 255)
        return token.dim ? color.opacity(0.55) : color
    }
}
