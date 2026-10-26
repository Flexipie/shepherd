import ShepherdCore
import SwiftUI

/// An agent in the queue (with its project) or in a project card (without). One accessibility
/// element: "codex, api, needs you, 4 minutes". With `onJump`, an arrow after the time jumps
/// straight to the agent; it shows while the row is hovered or selected. A context size, when
/// known, sits before the time ("184k", or "184k context" with `namesContext`). With `checkout`,
/// the row stands for a repo card's checkout and its one agent: the checkout's label (a branch
/// glyph for a worktree, a dot when focused) as the title, then the agent's status.
struct AgentRow: View {
    let row: PanelAgentRow
    let now: Date
    var checkout: HerdProject?
    var showsProject = false
    var namesContext = false
    var isSelected = false
    /// Characters of the name a palette query matched.
    var nameHighlights: [Range<String.Index>] = []
    var onJump: (() -> Void)?

    @State private var isHovered = false

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            StateGlyph(status: row.agent.status, isLive: row.isLive, size: showsProject ? 14 : 12)
                .alignmentGuide(.firstTextBaseline) { $0[VerticalAlignment.center] + 4 }
            VStack(alignment: .leading, spacing: 2) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    if let checkout {
                        checkoutTitle(checkout)
                    } else {
                        Highlighted.text(row.agent.name, nameHighlights)
                            .font(.system(size: showsProject ? 13 : 12, weight: .semibold))
                    }
                    Text(subtitle)
                        .font(.system(size: showsProject ? 12 : 11))
                        .foregroundStyle(.secondary)
                    Spacer(minLength: 8)
                    if let tokens = row.contextTokens {
                        Text(namesContext ? "\(ContextSize.short(tokens)) context" : ContextSize.short(tokens))
                            .font(.system(size: 11).monospacedDigit())
                            .foregroundStyle(.secondary)
                            .help(ContextSize.help(tokens))
                            .fixedSize()
                    }
                    if let elapsed = Elapsed.short(row.agent.since, now: now) {
                        Text(elapsed)
                            .font(.system(size: 11).monospacedDigit())
                            .foregroundStyle(.secondary)
                            .fixedSize()
                    }
                    if let onJump {
                        jumpButton(onJump)
                    }
                }
                .lineLimit(1)
                TokenLines(lines: row.tokens, isLive: row.isLive)
            }
        }
        .opacity(row.isLive ? 1 : 0.6)
        .rowChrome(isSelected: isSelected, vertical: showsProject ? 6 : 4)
        .onHover { isHovered = $0 }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
        .accessibilityAddTraits(row.action == nil ? [] : .isButton)
        .accessibilityActions {
            if let onJump { Button("Jump", action: onJump) }
        }
    }

    private func checkoutTitle(_ checkout: HerdProject) -> some View {
        HStack(spacing: 5) {
            if checkout.repo?.isLinkedCheckout == true {
                Image(systemName: "arrow.triangle.branch")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
            Text(checkout.name.isEmpty ? "Untitled" : checkout.name)
                .font(.system(size: 12, weight: .semibold))
            if checkout.isFocusedInSource {
                Circle().fill(Color.accentColor).frame(width: 5, height: 5)
            }
        }
        .layoutPriority(1)
    }

    /// Always laid out, so the row does not shift when the arrow appears.
    private func jumpButton(_ onJump: @escaping () -> Void) -> some View {
        let shows = isHovered || isSelected
        return Button(action: onJump) {
            Image(systemName: "arrow.up.right")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.secondary)
                .frame(width: 14, height: 14)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("Jump to it (⌘-click)")
        .opacity(shows ? 1 : 0)
        .allowsHitTesting(shows)
    }

    private var subtitle: String {
        let status = row.isLive ? row.agent.statusText : "last seen \(row.agent.statusText)"
        guard showsProject, !row.agent.project.isEmpty else { return status }
        return "\(row.agent.project) · \(status)"
    }

    private var accessibilityText: String {
        var parts = [row.agent.name]
        if let checkout {
            parts.insert(checkout.name, at: 0)
            if checkout.repo?.isLinkedCheckout == true { parts.insert("worktree", at: 1) }
            if checkout.isFocusedInSource { parts.append("focused") }
        }
        if showsProject, !row.agent.project.isEmpty { parts.append(row.agent.project) }
        parts.append(row.isLive ? row.agent.statusText : "last seen \(row.agent.statusText), not live")
        if let spoken = Elapsed.spoken(row.agent.since, now: now) { parts.append(spoken) }
        if let tokens = row.contextTokens { parts.append(ContextSize.spoken(tokens)) }
        parts += row.tokens.flatMap { $0.map(\.text) }
        return parts.joined(separator: ", ")
    }
}
