import SwiftUI

/// The black shape that extends the notch: a flat top flush with the screen edge, concave top
/// corners that flare into the menu bar like the hardware notch, and a rounded bottom. It draws
/// `frame` (the body, in the view's coordinates) rather than the rect it is given, so one shape
/// can move and resize inside a fixed canvas, and animates both with the radius.
struct NotchShape: Shape {
    var frame: CGRect
    var radius: CGFloat
    var flare: CGFloat = NotchMetrics.flare

    var animatableData: AnimatablePair<CGRect.AnimatableData, CGFloat> {
        get { AnimatablePair(frame.animatableData, radius) }
        set {
            frame.animatableData = newValue.first
            radius = newValue.second
        }
    }

    func path(in _: CGRect) -> Path {
        let body = frame.standardized
        let radius = max(0, min(radius, body.width / 2, body.height - flare))
        let flare = max(0, min(flare, body.height / 2))
        var path = Path()
        path.move(to: CGPoint(x: body.minX - flare, y: body.minY))
        path.addQuadCurve(to: CGPoint(x: body.minX, y: body.minY + flare), control: CGPoint(x: body.minX, y: body.minY))
        path.addLine(to: CGPoint(x: body.minX, y: body.maxY - radius))
        path.addQuadCurve(to: CGPoint(x: body.minX + radius, y: body.maxY), control: CGPoint(x: body.minX, y: body.maxY))
        path.addLine(to: CGPoint(x: body.maxX - radius, y: body.maxY))
        path.addQuadCurve(to: CGPoint(x: body.maxX, y: body.maxY - radius), control: CGPoint(x: body.maxX, y: body.maxY))
        path.addLine(to: CGPoint(x: body.maxX, y: body.minY + flare))
        path.addQuadCurve(to: CGPoint(x: body.maxX + flare, y: body.minY), control: CGPoint(x: body.maxX, y: body.minY))
        path.closeSubpath()
        return path
    }
}
