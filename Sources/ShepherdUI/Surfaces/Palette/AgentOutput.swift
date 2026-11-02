import ShepherdCore
import SwiftUI

/// What an agent last showed, in the palette: its whole last message once it stopped and a reader
/// found one (scrolling past `maxHeight`, or cut at `linesHeight`), else its last lines
/// ("Reading…" until they arrive). Those are its last `lineCount`, or with `linesHeight` all of
/// them in a box that tall cut from the top, so wrapped lines never push the newest ones out. An
/// agent whose source cannot show its lines gets a note instead, and a failed read its error.
struct AgentOutput: View {
    let row: PanelAgentRow
    let lines: [String]?
    var canRead = true
    var error: String?
    var lineCount: Int?
    var linesHeight: CGFloat?
    var maxHeight: CGFloat?

    var body: some View {
        if row.showsFinalMessage, let message = row.finalMessage {
            if let linesHeight {
                // Its start matters most, so a long message is cut at the bottom.
                FinalMessage(message: message)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxHeight: linesHeight, alignment: .top)
                    .clipShape(.rect(cornerRadius: 8))
            } else {
                FinalMessage(message: message, maxHeight: maxHeight)
            }
        } else if !canRead {
            Text("Its source cannot show its lines")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
        } else if lines == nil, let error {
            failure(error)
        } else {
            terminalLines
            // A later read failed: the lines above are older than the agent's screen.
            if let error { failure(error) }
        }
    }

    private func failure(_ error: String) -> some View {
        Label {
            Text(error).lineLimit(2)
        } icon: {
            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
        }
        .font(.system(size: 11))
    }

    @ViewBuilder
    private var terminalLines: some View {
        let shown = lines.map { $0.suffix(lineCount ?? $0.count).joined(separator: "\n") }
        let text = Text(shown ?? "Reading…")
            .font(.system(size: 10.5, design: .monospaced))
            .foregroundStyle(lines == nil ? .secondary : .primary)
            .lineLimit(lineCount)
            .frame(maxWidth: .infinity, alignment: .topLeading)
        Group {
            if let linesHeight {
                text.fixedSize(horizontal: false, vertical: true)
                    .frame(maxHeight: linesHeight - 16, alignment: .bottom)
                    .clipped()
            } else {
                text
            }
        }
        .padding(8)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color.primary.opacity(0.06)))
        .accessibilityLabel("Last lines")
    }
}
