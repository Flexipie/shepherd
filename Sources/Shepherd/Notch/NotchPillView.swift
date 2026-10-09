import ShepherdCore
import SwiftUI

/// The pill's content: which agent, why, and how many others are waiting. The whole pill is one
/// button that jumps to the agent.
struct NotchPillView: View {
    let item: NotchItem
    let style: NotchGeometry.Style
    let onJump: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: onJump) {
            VStack(spacing: 0) {
                if case .notch(let height) = style { Color.clear.frame(height: height) }
                row
                    .padding(.horizontal, 18)
                    .frame(height: NotchGeometry.contentHeight)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(background)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
        .accessibilityHint("Jumps to the agent")
        .accessibilityAddTraits(.isButton)
    }

    private var row: some View {
        HStack(spacing: 10) {
            Image(systemName: item.reason == .blocked ? "exclamationmark.circle.fill" : "checkmark.circle.fill")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(item.reason == .blocked ? Color.orange : Color.green)
            VStack(alignment: .leading, spacing: 1) {
                Text(item.title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(primary)
                Text(item.subtitle)
                    .font(.system(size: 11))
                    .foregroundStyle(secondary)
            }
            .lineLimit(1)
            Spacer(minLength: 8)
            if item.others > 0 {
                Text("+\(item.others)")
                    .font(.system(size: 11, weight: .semibold).monospacedDigit())
                    .foregroundStyle(secondary)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 2)
                    .background(Capsule().fill(secondary.opacity(0.18)))
            }
            Image(systemName: "arrow.up.forward")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(secondary)
                .opacity(hovering ? 1 : 0.5)
        }
    }

    @ViewBuilder private var background: some View {
        switch style {
        case .notch:
            // Black like the notch it extends, whatever the system appearance.
            UnevenRoundedRectangle(bottomLeadingRadius: 18, bottomTrailingRadius: 18)
                .fill(Color.black)
        case .floating:
            Capsule().fill(.regularMaterial)
                .overlay(Capsule().strokeBorder(.separator, lineWidth: 0.5))
        }
    }

    private var primary: Color { style == .floating ? .primary : .white }
    private var secondary: Color { style == .floating ? .secondary : Color.white.opacity(0.65) }

    private var accessibilityText: String {
        let others = item.others > 0 ? ", \(item.others) more waiting" : ""
        return "\(item.title), \(item.subtitle)\(others)"
    }
}
