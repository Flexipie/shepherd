import AppKit
import ShepherdCore
import SwiftUI

/// The new task form in the notch bar: which project's repo, a branch (optional), which agent,
/// and its first prompt. Start makes a checkout, starts the agent there and sends the prompt;
/// the bar then shows the new agent's stage. Disabled while starting; a failure stays on screen.
struct NewTaskView: View {
    let stage: NewTaskStage
    let onStage: (StageAction) -> Void

    @State private var project: ProjectID?
    @State private var branch = ""
    @State private var kind: String
    @State private var prompt = ""
    @Environment(\.isMonochrome) private var isMonochrome

    init(stage: NewTaskStage, onStage: @escaping (StageAction) -> Void) {
        self.stage = stage
        self.onStage = onStage
        _project = State(initialValue: stage.suggestedProject ?? stage.projects.first?.id)
        _kind = State(initialValue: stage.kinds.first ?? "claude")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: NotchStyle.medium) {
            HStack {
                Text("New task")
                    .font(.system(size: NotchStyle.title, weight: .semibold))
                Spacer()
                Button {
                    onStage(.close)
                } label: {
                    Image(systemName: "xmark").font(.system(size: 10, weight: .bold))
                }
                .buttonStyle(StageButtonStyle())
                .help("Back to the projects (Escape)")
                .accessibilityLabel("Close")
            }
            HStack(alignment: .top, spacing: NotchStyle.large) {
                VStack(alignment: .leading, spacing: 6) {
                    Picker("Project", selection: $project) {
                        ForEach(stage.projects, id: \.id) { project in
                            Text(project.name.isEmpty ? "Untitled" : project.name).tag(Optional(project.id))
                        }
                    }
                    Picker("Agent", selection: $kind) {
                        ForEach(stage.kinds, id: \.self) { Text($0).tag($0) }
                    }
                    field("Branch (optional)", text: $branch)
                }
                .frame(width: 230)
                VStack(alignment: .leading, spacing: 6) {
                    TextField("What should it do?", text: $prompt, axis: .vertical)
                        .lineLimit(3...5)
                        .textFieldStyle(.plain)
                        .font(.system(size: NotchStyle.title))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 7)
                        .background(RoundedRectangle(cornerRadius: NotchStyle.cardRadius).fill(NotchStyle.field))
                        .onKeyPress(.return, phases: .down) { press in
                            // While an input method is composing, Return confirms its candidate.
                            let composing = (NSApp.keyWindow?.firstResponder as? NSTextView)?.hasMarkedText() ?? false
                            guard !composing, press.modifiers.isDisjoint(with: [.shift, .option]) else { return .ignored }
                            start()
                            return .handled
                        }
                        .help("Return starts the task; Shift- or Option-Return adds a line")
                    HStack(spacing: NotchStyle.medium) {
                        Button(stage.isStarting ? "Starting…" : "Start", action: start)
                            .buttonStyle(StageButtonStyle(fill: isMonochrome ? nil : Color.accentColor.opacity(0.35),
                                                          prominent: isMonochrome))
                            .disabled(project == nil || stage.isStarting)
                        if isMonochrome { KeyHint("Return") }
                        Text("Creates a worktree, starts \(kind) in it and sends the prompt.")
                            .font(.system(size: NotchStyle.body))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
            }
            .disabled(stage.isStarting)
            if let error = stage.error {
                Label {
                    Text(error).lineLimit(2)
                } icon: {
                    Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                }
                .font(.system(size: NotchStyle.body))
            }
        }
        .font(.system(size: 12))
    }

    private func field(_ title: String, text: Binding<String>) -> some View {
        TextField(title, text: text)
            .textFieldStyle(.plain)
            .font(.system(size: NotchStyle.title))
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(RoundedRectangle(cornerRadius: NotchStyle.cardRadius).fill(NotchStyle.field))
    }

    private func start() {
        guard let project else { return }
        let branch = branch.trimmingCharacters(in: .whitespacesAndNewlines)
        onStage(.startTask(NewTask(project: project, branch: branch.isEmpty ? nil : branch, kind: kind,
                                   prompt: prompt.trimmingCharacters(in: .whitespacesAndNewlines))))
    }
}

/// The New task button in the bar's top strip, which opens the new task form.
struct NewTaskButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label("New task", systemImage: "plus")
        }
        .buttonStyle(StageButtonStyle())
        .help("Start an agent on a new branch")
    }
}
