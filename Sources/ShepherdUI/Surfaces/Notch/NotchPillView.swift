import ShepherdCore
import SwiftUI

/// The pill on a display without a notch: a capsule under the menu bar showing which agent, why,
/// and how many others are waiting. The whole pill is one button that jumps to the agent. On a
/// notched display the same row is the notch surface's alert.
public struct NotchPillView: View {
    public nonisolated static let contentHeight: CGFloat = 44

    let item: NotchItem
    let onJump: () -> Void

    public init(item: NotchItem, onJump: @escaping () -> Void) {
        self.item = item
        self.onJump = onJump
    }

    @State private var hovering = false

    public var body: some View {
        Button(action: onJump) {
            NotchPillRow(item: item, primary: .primary, secondary: .secondary, hovering: hovering)
                .padding(.horizontal, 18)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                // Solid rather than a material: materials render flat in snapshots, and the pill
                // must read over any wallpaper.
                .background(Capsule().fill(Color(nsColor: .windowBackgroundColor))
                    .overlay(Capsule().strokeBorder(.separator, lineWidth: 0.5)))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .notchItemAccessibility(item)
    }
}

/// The pill's content: an icon for the reason, the agent and its project, "+N" for the others,
/// and an arrow that brightens on hover.
struct NotchPillRow: View {
    let item: NotchItem
    let primary: Color
    let secondary: Color
    let hovering: Bool

    var body: some View {
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
}

extension View {
    func notchItemAccessibility(_ item: NotchItem) -> some View {
        let others = item.others > 0 ? ", \(item.others) more waiting" : ""
        return accessibilityElement(children: .ignore)
            .accessibilityLabel("\(item.title), \(item.subtitle)\(others)")
            .accessibilityHint("Jumps to the agent")
            .accessibilityAddTraits(.isButton)
    }
}
