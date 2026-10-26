import ShepherdCore
import SwiftUI

/// A gadget's card: its title and detail, then a thin bar per meter with its value and when it
/// resets, then its lines. Dimmed when the data is stale. One accessibility element. Usage and
/// This Mac are both drawn by it; a gadget whose content fits needs no view of its own.
struct GadgetCardView: View {
    let card: GadgetCard
    let now: Date

    /// A meter at or past this share of its limit turns orange.
    static let warning = 0.8

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(card.title)
                    .font(.system(size: 13, weight: .semibold))
                    .lineLimit(1)
                Spacer(minLength: 8)
                if let detail = card.detail {
                    Text(detail)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            ForEach(card.meters) { meter in
                meterView(meter)
            }
            ForEach(card.lines, id: \.self) { line in
                Text(line)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .opacity(card.isStale ? 0.6 : 1)
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .frame(maxWidth: .infinity, alignment: .leading)
        .card(padding: EdgeInsets())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
    }

    private func meterView(_ meter: UsageMeter) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(meter.label)
                    .font(.system(size: 11, weight: .medium))
                if let resets = meter.resetsAt {
                    Text("resets in \(Self.remaining(until: resets, now: now))")
                        .font(.system(size: 10).monospacedDigit())
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 6)
                Text(meter.valueText)
                    .font(.system(size: 11, weight: .medium).monospacedDigit())
            }
            .lineLimit(1)
            Capsule()
                .fill(Color.primary.opacity(0.12))
                .frame(height: 4)
                .overlay(alignment: .leading) {
                    GeometryReader { geometry in
                        Capsule()
                            .fill(meter.fraction >= Self.warning ? Color.orange : Color.accentColor)
                            .frame(width: max(meter.fraction > 0 ? 4 : 0, geometry.size.width * meter.fraction))
                    }
                }
        }
    }

    /// "now", "42m", "2h 10m", "6d 4h".
    static func remaining(until date: Date, now: Date) -> String {
        let seconds = max(0, Int(date.timeIntervalSince(now)))
        return switch seconds {
        case ..<60: "under a minute"
        case ..<3600: "\(seconds / 60)m"
        case ..<86_400: "\(seconds / 3600)h \(seconds % 3600 / 60)m"
        default: "\(seconds / 86_400)d \(seconds % 86_400 / 3600)h"
        }
    }

    private var accessibilityText: String {
        var parts = [card.title]
        if let detail = card.detail { parts.append(detail) }
        if card.isStale { parts.append("out of date") }
        for meter in card.meters {
            var text = "\(meter.label) \(meter.valueText)"
            if let resets = meter.resetsAt { text += ", resets in \(Self.remaining(until: resets, now: now))" }
            parts.append(text)
        }
        return (parts + card.lines).joined(separator: ", ")
    }
}
