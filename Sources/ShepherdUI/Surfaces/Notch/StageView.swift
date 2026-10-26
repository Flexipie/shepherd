import ShepherdCore
import SwiftUI

/// The right side of the notch bar while an agent is open: its row, its last visible lines, and
/// beside them the ways to answer it (its choices with their digits, or Return and Escape when
/// none were found, and a reply field), or a prompt field when it is not waiting on a question.
/// Disabled while a send is on its way.
struct StageView: View {
    let stage: AgentStage
    let now: Date
    /// The lines box's height, so the bar stays under its cap; nil lets it grow.
    let linesHeight: CGFloat?
    let perform: (PanelAction) -> Void
    let onStage: (StageAction) -> Void

    @State private var draft = ""

    static let controlsWidth: CGFloat = 270

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            header
            HStack(alignment: .top, spacing: 10) {
                lines
                controls.frame(width: Self.controlsWidth, alignment: .topLeading)
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
    }

    private var header: some View {
        HStack(spacing: 6) {
            AgentRow(row: stage.row, now: now, showsProject: true, namesContext: true)
            if let action = stage.row.action {
                Button("Jump") { perform(action) }
                    .buttonStyle(StageButtonStyle())
                    .help("Show the agent in its terminal")
            }
            Button {
                onStage(.close)
            } label: {
                Image(systemName: "xmark").font(.system(size: 10, weight: .bold))
            }
            .buttonStyle(StageButtonStyle())
            .help("Back to the projects (Escape)")
            .accessibilityLabel("Close")
        }
    }

    @ViewBuilder
    private var lines: some View {
        let text = Text(stage.lines.map { $0.joined(separator: "\n") } ?? "Reading…")
            .font(.system(size: 10.5, design: .monospaced))
            .foregroundStyle(stage.lines == nil ? .secondary : .primary)
            .frame(maxWidth: .infinity, alignment: .topLeading)
            .padding(8)
        Group {
            if let linesHeight {
                ScrollView { text }
                    .defaultScrollAnchor(.bottom)
                    .frame(height: linesHeight)
            } else {
                text
            }
        }
        .background(RoundedRectangle(cornerRadius: 8).fill(Color.primary.opacity(0.06)))
        .accessibilityLabel("Last lines")
    }

    private var controls: some View {
        VStack(alignment: .leading, spacing: 4) {
            if stage.canSendKeys {
                if stage.choices.isEmpty {
                    HStack(spacing: 6) {
                        Button("Return") { onStage(.keys(["enter"])) }
                        Button("Escape") { onStage(.keys(["esc"])) }
                    }
                    .buttonStyle(StageButtonStyle())
                } else {
                    ChoiceButtons(choices: stage.choices) { onStage(.keys($0)) }
                }
            }
            if stage.canReply {
                reply.padding(.top, 2)
            }
            if !stage.canSendKeys && !stage.canReply {
                Text("Nothing can be sent to this agent")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 4)
            }
        }
        .disabled(stage.isSending)
    }

    private var reply: some View {
        HStack(spacing: 6) {
            TextField(stage.prompts ? "Prompt \(stage.row.agent.name)" : "Reply", text: $draft)
                .textFieldStyle(.plain)
                .font(.system(size: 12))
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .background(RoundedRectangle(cornerRadius: 7).fill(Color.primary.opacity(0.08)))
                .onSubmit(send)
            Button(stage.prompts ? "Prompt" : "Send", action: send)
                .buttonStyle(StageButtonStyle())
                .disabled(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
    }

    private func send() {
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        onStage(.reply(text))
        draft = ""
    }
}

/// A small flat button for the stage, readable on the notch's black.
struct StageButtonStyle: ButtonStyle {
    var fill: Color?
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12, weight: .medium))
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(RoundedRectangle(cornerRadius: 7)
                .fill(fill ?? Color.primary.opacity(configuration.isPressed ? 0.18 : 0.1)))
            .opacity(isEnabled ? 1 : 0.45)
            .contentShape(Rectangle())
    }
}
