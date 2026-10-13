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

    init(stage: NewTaskStage, onStage: @escaping (StageAction) -> Void) {
        self.stage = stage
        self.onStage = onStage
        _project = State(initialValue: stage.suggestedProject ?? stage.projects.first?.id)
        _kind = State(initialValue: stage.kinds.first ?? "claude")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("New task")
                    .font(.system(size: 13, weight: .semibold))
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
            HStack(alignment: .top, spacing: 12) {
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
                        .font(.system(size: 12))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 6)
                        .background(RoundedRectangle(cornerRadius: 7).fill(Color.primary.opacity(0.08)))
                    HStack(spacing: 8) {
                        Button(stage.isStarting ? "Starting…" : "Start", action: start)
                            .buttonStyle(StageButtonStyle(fill: Color.accentColor.opacity(0.35)))
                            .disabled(project == nil || stage.isStarting)
                        Text("Creates a worktree, starts \(kind) in it and sends the prompt.")
                            .font(.system(size: 11))
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
                .font(.system(size: 11))
            }
        }
        .font(.system(size: 12))
    }

    private func field(_ title: String, text: Binding<String>) -> some View {
        TextField(title, text: text)
            .textFieldStyle(.plain)
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(RoundedRectangle(cornerRadius: 7).fill(Color.primary.opacity(0.08)))
    }

    private func start() {
        guard let project else { return }
        let branch = branch.trimmingCharacters(in: .whitespacesAndNewlines)
        onStage(.startTask(NewTask(project: project, branch: branch.isEmpty ? nil : branch, kind: kind,
                                   prompt: prompt.trimmingCharacters(in: .whitespacesAndNewlines))))
    }
}

/// The "+" after the project columns, which opens the new task form.
struct NewTaskButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Image(systemName: "plus").font(.system(size: 14, weight: .semibold))
                Text("New task").font(.system(size: 11))
            }
            .foregroundStyle(.secondary)
            .frame(width: 76, height: 64)
            .background(RoundedRectangle(cornerRadius: 10).strokeBorder(Color.secondary.opacity(0.35), style: StrokeStyle(lineWidth: 1, dash: [4, 3])))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("Start an agent on a new branch")
    }
}
