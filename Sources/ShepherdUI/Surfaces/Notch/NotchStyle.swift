import SwiftUI

/// The notch's look in one place: white and grey tiers on black like the hardware notch, orange
/// the one colour (it means "needs you"). Tiers are `primary`, so they are white in the notch,
/// which is always dark. Not a theme: the palette keeps its own look.
enum NotchStyle {
    // Fills.
    static let selected = Color.primary.opacity(0.12)
    static let hover = Color.primary.opacity(0.07)
    static let card = Color.primary.opacity(0.045)
    static let track = Color.primary.opacity(0.1)
    static let field = Color.primary.opacity(0.07)

    // Text.
    static let secondary = Color.primary.opacity(0.6)
    static let tertiary = Color.primary.opacity(0.35)

    // Radii.
    static let rowRadius: CGFloat = 7
    static let cardRadius: CGFloat = 10

    // Spacing and type.
    static let small: CGFloat = 4
    static let medium: CGFloat = 8
    static let large: CGFloat = 12
    static let caption: CGFloat = 10
    static let body: CGFloat = 11
    static let title: CGFloat = 13

    static let meterHeight: CGFloat = 6

    // Motion. Each runs on a change only, never at idle.
    /// Switching tabs, opening a stage and the tab pill.
    static let slide = Animation.spring(duration: 0.3, bounce: 0.1)
    /// What Reduce Motion gets instead: no movement, a short fade.
    static let fade = Animation.easeInOut(duration: 0.15)
    static let meter = Animation.easeOut(duration: 0.4)
    /// How far content travels as it slides in or out.
    static let travel: CGFloat = 24

    /// A slide plus fade that enters and leaves on the side of `edge`, so content on the left
    /// (Agents, the columns) goes left and content on the right (Gadgets, a stage) goes right.
    /// Only the fade with Reduce Motion.
    static func slide(from edge: HorizontalEdge, reduceMotion: Bool) -> AnyTransition {
        guard !reduceMotion else { return .opacity }
        return .opacity.combined(with: .offset(x: edge == .leading ? -travel : travel))
    }
}

extension EnvironmentValues {
    /// Set by the notch bar: shared rows, cards, meters and buttons draw in `NotchStyle`'s white
    /// tiers instead of the accent colour.
    @Entry var isMonochrome = false
}

/// A faint key-cap hint such as "⌘1" or "Return", beside the control it presses. Hidden from
/// VoiceOver: the control's help says it.
struct KeyHint: View {
    let keys: String

    init(_ keys: String) {
        self.keys = keys
    }

    var body: some View {
        Text(keys)
            .font(.system(size: NotchStyle.caption, weight: .medium))
            .foregroundStyle(NotchStyle.tertiary)
            .accessibilityHidden(true)
    }
}
