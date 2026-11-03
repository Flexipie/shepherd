import ShepherdCore
import SwiftUI

/// The right side of the notch bar while an agent is open: its row, its last visible lines (its
/// whole last message instead, once it stopped and a reader found one), and
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
        VStack(alignment: .leading, spacing: NotchStyle.medium) {
            header
            HStack(alignment: .top, spacing: NotchStyle.medium) {
                lines
                controls.frame(width: Self.controlsWidth, alignment: .topLeading)
            }
            if let error = stage.error {
                Label {
                    Text(error).lineLimit(2)
                } icon: {
                    Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                }
                .font(.system(size: NotchStyle.body))
            }
        }
    }

    private var header: some View {
        HStack(spacing: 6) {
            AgentRow(row: stage.row, now: now, showsProject: true, namesContext: true, showsPreview: false)
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
        if stage.row.showsFinalMessage, let message = stage.row.finalMessage {
            FinalMessage(message: message, maxHeight: linesHeight)
        } else {
            terminalLines
        }
    }

    @ViewBuilder
    private var terminalLines: some View {
        let text = Text(stage.lines.map { $0.joined(separator: "\n") } ?? "Reading…")
            .font(.system(size: NotchStyle.caption, design: .monospaced))
            .foregroundStyle(stage.lines == nil ? NotchStyle.secondary : Color.primary)
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
        .background(RoundedRectangle(cornerRadius: NotchStyle.rowRadius).fill(NotchStyle.field))
        .accessibilityLabel("Last lines")
    }

    private var controls: some View {
        VStack(alignment: .leading, spacing: NotchStyle.small) {
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
                    .font(.system(size: NotchStyle.body))
                    .foregroundStyle(NotchStyle.secondary)
                    .padding(.horizontal, 4)
            }
        }
        .disabled(stage.isSending)
    }

    /// The palette's prompt box, smaller: Return sends.
    private var reply: some View {
        HStack(spacing: 8) {
            Image(systemName: stage.prompts ? "text.bubble" : "arrowshape.turn.up.left")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(NotchStyle.secondary)
            TextField(stage.prompts ? "Prompt \(stage.row.agent.name)…" : "Reply to \(stage.row.agent.name)…", text: $draft)
                .textFieldStyle(.plain)
                .font(.system(size: NotchStyle.title))
                .onSubmit(send)
            KeyHint("Return")
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(RoundedRectangle(cornerRadius: NotchStyle.cardRadius).fill(NotchStyle.field))
    }

    private func send() {
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        onStage(.reply(text))
        draft = ""
    }
}

/// A small flat button for the stage, readable on the notch's black. `prominent` is the one
/// solid button of a form: white with black text.
struct StageButtonStyle: ButtonStyle {
    var fill: Color?
    var prominent = false

    func makeBody(configuration: Configuration) -> some View {
        StageButton(configuration: configuration, fill: fill, prominent: prominent)
    }
}

/// The button itself, which holds its hover: in the notch a hovered button brightens.
private struct StageButton: View {
    let configuration: ButtonStyleConfiguration
    let fill: Color?
    let prominent: Bool

    @State private var isHovered = false
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.isMonochrome) private var isMonochrome

    var body: some View {
        configuration.label
            .font(.system(size: isMonochrome ? NotchStyle.body : 12, weight: prominent ? .semibold : .medium))
            .foregroundStyle(prominent ? AnyShapeStyle(Color.black) : AnyShapeStyle(.foreground))
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(RoundedRectangle(cornerRadius: NotchStyle.rowRadius).fill(background))
            .opacity(isEnabled ? 1 : 0.45)
            .contentShape(Rectangle())
            .onHover { isHovered = isMonochrome && isEnabled && $0 }
    }

    private var background: Color {
        let pressed = configuration.isPressed
        if prominent { return Color.white.opacity(pressed ? 0.8 : isHovered ? 0.9 : 1) }
        return fill ?? Color.primary.opacity(pressed ? 0.18 : isHovered ? 0.14 : 0.1)
    }
}
