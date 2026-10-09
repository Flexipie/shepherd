import Foundation

/// A `#RGB` or `#RRGGBB` colour, as herdr's sidebar config writes them.
public struct HexColor: Sendable, Hashable, CustomStringConvertible {
    /// sRGB components, 0...255.
    public let red: UInt8
    public let green: UInt8
    public let blue: UInt8

    public init(red: UInt8, green: UInt8, blue: UInt8) {
        self.red = red
        self.green = green
        self.blue = blue
    }

    public init?(_ text: String) {
        guard text.hasPrefix("#") else { return nil }
        let hex = text.dropFirst()
        guard hex.count == 3 || hex.count == 6, hex.allSatisfy(\.isHexDigit) else { return nil }
        let digits = hex.count == 3 ? hex.flatMap { [$0, $0] } : Array(hex)
        func byte(_ index: Int) -> UInt8 { UInt8(String(digits[index...index + 1]), radix: 16)! }
        self.init(red: byte(0), green: byte(2), blue: byte(4))
    }

    public var description: String { String(format: "#%02x%02x%02x", red, green, blue) }

    /// WCAG relative luminance.
    public var luminance: Double {
        func linear(_ component: UInt8) -> Double {
            let value = Double(component) / 255
            return value <= 0.04045 ? value / 12.92 : pow((value + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * linear(red) + 0.7152 * linear(green) + 0.0722 * linear(blue)
    }

    /// WCAG contrast ratio, 1...21.
    public func contrast(with other: HexColor) -> Double {
        let (light, dark) = luminance > other.luminance ? (luminance, other.luminance) : (other.luminance, luminance)
        return (light + 0.05) / (dark + 0.05)
    }

    /// This colour if it reads on `background`; otherwise the nearest step towards black (on a
    /// light background) or white (on a dark one) that reaches `minimum`. herdr colours are picked
    /// for dark terminals, so in light mode a pastel is darkened rather than shown washed out.
    public func readable(on background: HexColor, minimum: Double = 4.5) -> HexColor {
        guard contrast(with: background) < minimum else { return self }
        let target: Double = background.luminance > 0.18 ? 0 : 255
        for step in 1...50 {
            let amount = Double(step) / 50
            func mix(_ component: UInt8) -> UInt8 {
                UInt8((Double(component) + (target - Double(component)) * amount).rounded())
            }
            let candidate = HexColor(red: mix(red), green: mix(green), blue: mix(blue))
            if candidate.contrast(with: background) >= minimum { return candidate }
        }
        return target == 0 ? HexColor(red: 0, green: 0, blue: 0) : HexColor(red: 255, green: 255, blue: 255)
    }

    /// Nominal panel backgrounds the guard checks against.
    public static let lightBackground = HexColor(red: 0xf2, green: 0xf2, blue: 0xf2)
    public static let darkBackground = HexColor(red: 0x1e, green: 0x1e, blue: 0x1e)
}
