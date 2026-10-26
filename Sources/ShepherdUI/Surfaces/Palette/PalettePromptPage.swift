import ShepherdCore
import SwiftUI

/// The palette prompting one agent: the field takes a prompt (or a reply while the agent is
/// blocked), and below it are the agent's row, its last lines (its whole last message instead,
/// once it stopped and a reader found one, scrolling past `maxHeight`) and, while blocked, its choices
/// with ⌘ digits. Return sends; the text stays until the send succeeds, so a failure loses
/// nothing. Left in an empty field goes back to the list.
struct PalettePromptPage: View {
    let stage: AgentStage
    let now: Date
    var maxHeight: CGFloat?
    @Binding var draft: String
    let onEvent: (PaletteEvent) -> Void

    @FocusState private var focused: Bool

    /// Enough to see what the agent last said, short enough to stay a palette.
    static let lineCount = 8

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            field
            Divider().padding(.horizontal, 10)
            VStack(alignment: .leading, spacing: 8) {
                AgentRow(row: stage.row, now: now, showsProject: true, namesContext: true,
                         showsPreview: !stage.row.showsFinalMessage)
                if stage.row.showsFinalMessage, let message = stage.row.finalMessage {
                    FinalMessage(message: message, maxHeight: maxHeight)
                } else {
                    lines
                }
                if stage.canSendKeys {
                    if stage.choices.isEmpty {
                        HStack(spacing: 6) {
                            Button("Return") { onEvent(.stage(.keys(["enter"]))) }
                            Button("Escape") { onEvent(.stage(.keys(["esc"]))) }
                        }
                        .buttonStyle(StageButtonStyle())
                    } else {
                        ChoiceButtons(choices: stage.choices, commandDigits: true) { onEvent(.stage(.keys($0))) }
                    }
                }
                if !stage.canSendKeys && !stage.canReply {
                    Text("Nothing can be sent to this agent")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
                if let error = stage.error {
                    Label {
                        Text(error).lineLimit(2)
                    } icon: {
                        Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                    }
                    .font(.system(size: 11))
                }
            }
            .disabled(stage.isSending)
            .padding(.horizontal, 10)
            .padding(.vertical, 10)
        }
    }

    private var field: some View {
        HStack(spacing: 10) {
            Image(systemName: stage.prompts ? "text.bubble" : "arrowshape.turn.up.left")
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(.secondary)
            TextField(placeholder, text: $draft)
                .textFieldStyle(.plain)
                .font(.system(size: 18))
                .focused($focused)
                .disabled(!stage.canReply)
                .onSubmit(send)
                .onKeyPress(.leftArrow) { key(.left) }
                .onKeyPress(.rightArrow) { key(.right) }
                .onKeyPress(.tab) { key(.tab) }
            if stage.isSending {
                ProgressView().controlSize(.small)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        // A box, so the field reads as somewhere to type, unlike the search field above a list.
        .background(RoundedRectangle(cornerRadius: 10).fill(Color.primary.opacity(0.07)))
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .focusOnAppear($focused)
    }

    private var placeholder: String {
        let name = stage.row.agent.project.isEmpty ? stage.row.agent.name : "\(stage.row.agent.name) (\(stage.row.agent.project))"
        guard stage.canReply else { return "Cannot send text to \(name)" }
        return stage.prompts ? "Prompt \(name)…" : "Reply to \(name)…"
    }

    private var lines: some View {
        let shown = stage.lines.map { $0.suffix(Self.lineCount).joined(separator: "\n") }
        return Text(shown ?? "Reading…")
            .font(.system(size: 10.5, design: .monospaced))
            .foregroundStyle(stage.lines == nil ? .secondary : .primary)
            .lineLimit(Self.lineCount)
            .frame(maxWidth: .infinity, alignment: .topLeading)
            .padding(8)
            .background(RoundedRectangle(cornerRadius: 8).fill(Color.primary.opacity(0.06)))
            .accessibilityLabel("Last lines")
    }

    private func key(_ key: PaletteMode.Key) -> KeyPress.Result {
        switch PaletteMode.prompt.handle(key, canPromptSelection: false, fieldEmpty: draft.isEmpty) {
        case .back:
            onEvent(.back)
            return .handled
        case .swallow: return .handled
        case .prompt, .close, .pass: return .ignored
        }
    }

    private func send() {
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !stage.isSending else { return }
        onEvent(.stage(.reply(text)))
    }
}
