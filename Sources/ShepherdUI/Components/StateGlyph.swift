import ShepherdCore
import SwiftUI

/// An agent's state as a symbol. Colour carries meaning only while the source is live; stale
/// state is grey so it never reads as current.
struct StateGlyph: View {
    let status: HerdStatus
    var isLive = true
    var size: CGFloat = 13

    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: size, weight: .semibold))
            .foregroundStyle(isLive ? color : Color.secondary)
            .frame(width: size + 4)
            .accessibilityHidden(true)
    }

    private var symbol: String {
        switch status {
        case .blocked: "exclamationmark.circle.fill"
        case .done: "checkmark.circle.fill"
        case .working: "circle.dashed"
        case .idle: "circle"
        case .unknown: "questionmark.circle"
        }
    }

    private var color: Color {
        switch status {
        case .blocked: .orange
        case .done: .green
        case .working: .blue
        case .idle, .unknown: .secondary
        }
    }
}

extension HerdAgent {
    /// What the agent is doing, in words: the source's label if it has one.
    var statusText: String {
        if let statusLabel { return statusLabel }
        return switch status {
        case .blocked: "needs you"
        case .done: "finished"
        case .working: "working"
        case .idle: "idle"
        case .unknown: "unknown"
        }
    }
}
