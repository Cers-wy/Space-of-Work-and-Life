import SwiftUI

// Both surfaces use the same 40pt contour, centered on the 32pt logo.
struct SpaceSidebarShape: Shape {
    var extended: Bool
    func path(in rect: CGRect) -> Path {
        guard extended else { return RoundedRectangle(cornerRadius: SpaceStyle.cornerRadius).path(in: rect) }
        let edge = rect.maxX - 16
        let h = rect.maxY
        var p = Path()
        p.move(to: CGPoint(x: 8, y: 0))
        p.addLine(to: CGPoint(x: edge - 8, y: 0))
        p.addQuadCurve(to: CGPoint(x: edge, y: 8), control: CGPoint(x: edge, y: 0))
        p.addLine(to: CGPoint(x: edge, y: 12))
        p.addCurve(to: CGPoint(x: edge + 8, y: 20), control1: CGPoint(x: edge, y: 17), control2: CGPoint(x: edge + 3, y: 20))
        p.addCurve(to: CGPoint(x: edge + 16, y: 28), control1: CGPoint(x: edge + 13, y: 20), control2: CGPoint(x: edge + 16, y: 23))
        p.addLine(to: CGPoint(x: edge + 16, y: 36))
        p.addCurve(to: CGPoint(x: edge + 8, y: 44), control1: CGPoint(x: edge + 16, y: 41), control2: CGPoint(x: edge + 13, y: 44))
        p.addCurve(to: CGPoint(x: edge, y: 52), control1: CGPoint(x: edge + 3, y: 44), control2: CGPoint(x: edge, y: 47))
        p.addLine(to: CGPoint(x: edge, y: h - 8))
        p.addQuadCurve(to: CGPoint(x: edge - 8, y: h), control: CGPoint(x: edge, y: h))
        p.addLine(to: CGPoint(x: 8, y: h))
        p.addQuadCurve(to: CGPoint(x: 0, y: h - 8), control: CGPoint(x: 0, y: h))
        p.addLine(to: CGPoint(x: 0, y: 8))
        p.addQuadCurve(to: CGPoint(x: 8, y: 0), control: .zero)
        p.closeSubpath()
        return p
    }
}

struct SpaceOverviewShape: Shape {
    var notched: Bool
    func path(in rect: CGRect) -> Path {
        guard notched else { return RoundedRectangle(cornerRadius: SpaceStyle.cornerRadius).path(in: rect) }
        let w = rect.maxX, h = rect.maxY
        var p = Path()
        p.move(to: CGPoint(x: 8, y: 0))
        p.addLine(to: CGPoint(x: w - 8, y: 0))
        p.addQuadCurve(to: CGPoint(x: w, y: 8), control: CGPoint(x: w, y: 0))
        p.addLine(to: CGPoint(x: w, y: h - 8))
        p.addQuadCurve(to: CGPoint(x: w - 8, y: h), control: CGPoint(x: w, y: h))
        p.addLine(to: CGPoint(x: 8, y: h))
        p.addQuadCurve(to: CGPoint(x: 0, y: h - 8), control: CGPoint(x: 0, y: h))
        p.addLine(to: CGPoint(x: 0, y: 52))
        p.addCurve(to: CGPoint(x: 8, y: 44), control1: CGPoint(x: 0, y: 47), control2: CGPoint(x: 3, y: 44))
        p.addCurve(to: CGPoint(x: 16, y: 36), control1: CGPoint(x: 13, y: 44), control2: CGPoint(x: 16, y: 41))
        p.addLine(to: CGPoint(x: 16, y: 28))
        p.addCurve(to: CGPoint(x: 8, y: 20), control1: CGPoint(x: 16, y: 23), control2: CGPoint(x: 13, y: 20))
        p.addCurve(to: CGPoint(x: 0, y: 12), control1: CGPoint(x: 3, y: 20), control2: CGPoint(x: 0, y: 17))
        p.addLine(to: CGPoint(x: 0, y: 8))
        p.addQuadCurve(to: CGPoint(x: 8, y: 0), control: .zero)
        p.closeSubpath()
        return p
    }
}

extension View {
    func navigationGlass<S: Shape>(_ palette: OrbitPalette, shape: S) -> some View {
        modifier(NavigationGlassSurface(palette: palette, shape: shape))
    }
}

private struct NavigationGlassSurface<S: Shape>: ViewModifier {
    let palette: OrbitPalette
    let shape: S
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    func body(content: Content) -> some View {
        content.background {
            if reduceTransparency { shape.fill(palette.dark ? Color(hex: 0x181818) : .white) }
            else {
                shape.fill(.ultraThinMaterial)
                    .overlay { shape.fill(palette.panel) }
                    .overlay { shape.fill(palette.dark ? Color(hex: 0xA855F7).opacity(0.055) : .clear) }
            }
        }
        .overlay { shape.stroke(palette.border, lineWidth: 1) }
        .clipShape(shape)
    }
}
