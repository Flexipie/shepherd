import ShepherdCore
import SwiftUI

/// One account's plan usage: its name and plan, then a thin bar per limit with its value and
/// when it resets, then notes. Dimmed when the data is stale. One accessibility element.
struct UsageCard: View {
    let provider: UsageProvider
    let now: Date

    /// A meter at or past this share of its limit turns orange.
    static let warning = 0.8

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(provider.name)
                    .font(.system(size: 13, weight: .semibold))
                    .lineLimit(1)
                Spacer(minLength: 8)
                if let plan = provider.plan {
                    Text(plan)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            ForEach(provider.meters) { meter in
                meterView(meter)
            }
            ForEach(provider.notes, id: \.self) { note in
                Text(note)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .opacity(provider.isStale ? 0.6 : 1)
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color.primary.opacity(0.045)))
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
        var parts = [provider.name]
        if let plan = provider.plan { parts.append(plan) }
        if provider.isStale { parts.append("out of date") }
        for meter in provider.meters {
            var text = "\(meter.label) \(meter.valueText)"
            if let resets = meter.resetsAt { text += ", resets in \(Self.remaining(until: resets, now: now))" }
            parts.append(text)
        }
        return (parts + provider.notes).joined(separator: ", ")
    }
}
