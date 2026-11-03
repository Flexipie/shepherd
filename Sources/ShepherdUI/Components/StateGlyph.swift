import ShepherdCore
import SwiftUI

/// An agent's state as a symbol. Colour carries meaning only while the source is live; stale
/// state is grey so it never reads as current.
struct StateGlyph: View {
    let status: HerdStatus
    var isLive = true
    var size: CGFloat = 13
    @Environment(\.isMonochrome) private var isMonochrome

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

    /// In the notch only blocked keeps a colour; the symbol tells the rest apart.
    private var color: Color {
        if isMonochrome { return status == .blocked ? .orange : status == .idle || status == .unknown ? .secondary : .primary }
        return switch status {
        case .blocked: .orange
        case .done: .green
        case .working: .blue
        case .idle, .unknown: .secondary
        }
    }
}
