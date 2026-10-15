import ShepherdCore
import SwiftUI

/// A blocked agent's choices as buttons, each pressing its key. With `commandDigits`, ⌘ and the
/// key press it too, for places where plain digits are typing (the palette's prompt field).
struct ChoiceButtons: View {
    let choices: [AgentChoice]
    var commandDigits = false
    let onKeys: ([String]) -> Void

    var body: some View {
        ForEach(choices, id: \.key) { choice in
            button(choice)
        }
    }

    @ViewBuilder
    private func button(_ choice: AgentChoice) -> some View {
        let shortcut = commandDigits ? choice.key.first.flatMap { $0.isNumber ? KeyEquivalent($0) : nil } : nil
        let base = Button {
            onKeys([choice.key])
        } label: {
            HStack(alignment: .firstTextBaseline, spacing: 7) {
                Text(shortcut == nil ? choice.key : "⌘\(choice.key)")
                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                    .frame(minWidth: 16, minHeight: 16)
                    .padding(.horizontal, shortcut == nil ? 0 : 3)
                    .background(RoundedRectangle(cornerRadius: 4).strokeBorder(Color.secondary.opacity(0.6)))
                Text(choice.label)
                    .font(.system(size: 12, weight: choice.isSelected ? .semibold : .regular))
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .buttonStyle(StageButtonStyle(fill: choice.isSelected ? Color.accentColor.opacity(0.22) : nil))
        .help(shortcut == nil ? "Press \(choice.key)" : "Press ⌘\(choice.key)")
        if let shortcut {
            base.keyboardShortcut(shortcut, modifiers: .command)
        } else {
            base
        }
    }
}
