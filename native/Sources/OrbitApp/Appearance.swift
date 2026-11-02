import SwiftUI
import OrbitCore

enum SpaceStyle {
    static let cornerRadius: CGFloat = 8
    static let controlHeight: CGFloat = 40
    static let toolbarHeight: CGFloat = 36
}

struct OrbitPalette {
    let dark: Bool
    var canvas: Color { Color(hex: dark ? 0x000000 : 0xE8EEF6) }
    var text: Color { Color(hex: dark ? 0xF5F5F7 : 0x26364D) }
    var secondary: Color { Color(hex: dark ? 0xCCCCD2 : 0x53647B) }
    var muted: Color { Color(hex: dark ? 0xA0A0AB : 0x64738B) }
    var accent: Color { Color(hex: dark ? 0xB879FF : 0x2F6CFF) }
    var blue: Color { Color(hex: dark ? 0xABC7FF : 0x3668C1) }
    var purple: Color { Color(hex: dark ? 0xC5B5FF : 0x7759AD) }
    var green: Color { Color(hex: dark ? 0x96DBC2 : 0x2D806B) }
    var amber: Color { Color(hex: dark ? 0xF0CF9C : 0x93672D) }
    var red: Color { Color(hex: dark ? 0xF9B3C2 : 0xBA5366) }
    var border: Color { dark ? Color(hex: 0xC4B5D8).opacity(0.18) : .white.opacity(0.85) }
    var card: Color { dark ? Color(hex: 0x1F1F1F).opacity(0.66) : Color.white.opacity(0.72) }
    var panel: Color { dark ? Color(hex: 0x181818).opacity(0.55) : Color(hex: 0xF9FCFF).opacity(0.52) }
    var primary: Color { Color(hex: dark ? 0x9333EA : 0x356BFA) }
    var hover: Color { accent.opacity(dark ? 0.16 : 0.08) }
    func category(_ category: TaskCategory) -> Color {
        switch category { case .work: blue; case .personal: purple; case .life: green }
    }
    func status(_ status: TaskStatus) -> Color {
        switch status { case .todo: blue; case .doing: purple; case .done: green; default: accent }
    }
    func priority(_ priority: TaskPriority) -> Color {
        switch priority { case .high: red; case .medium: amber; case .low: muted }
    }
}

extension Color {
    init(hex: UInt32) {
        self.init(.sRGB, red: Double((hex >> 16) & 255) / 255,
                  green: Double((hex >> 8) & 255) / 255, blue: Double(hex & 255) / 255, opacity: 1)
    }
}

extension View {
    func orbitFont(_ size: CGFloat = 14, weight: Font.Weight = .regular) -> some View {
        font(.custom(weight == .semibold ? "PingFangSC-Semibold" : "PingFangSC-Regular", size: size))
    }
    func glass(_ palette: OrbitPalette) -> some View {
        modifier(SpaceGlass(palette: palette))
    }
}

private struct SpaceGlass: ViewModifier {
    let palette: OrbitPalette
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: SpaceStyle.cornerRadius, style: .continuous)
        content.background {
            if reduceTransparency { shape.fill(palette.dark ? Color(hex: 0x181818) : .white) }
            else {
                shape.fill(.ultraThinMaterial)
                    .overlay { shape.fill(palette.panel) }
                    .overlay { shape.fill(palette.dark ? Color(hex: 0xA855F7).opacity(0.055) : .clear) }
                    .overlay(alignment: .top) { shape.strokeBorder(.white.opacity(palette.dark ? 0.05 : 0.35)) }
            }
        }
        .overlay { shape.strokeBorder(palette.border, lineWidth: 1) }
        .clipShape(shape)
    }

}

struct OrbitIconButton: View {
    let symbol: String
    let label: String
    var selected = false
    var primary = false
    var compact = false
    let action: () -> Void
    @Environment(\.colorScheme) private var scheme
    @State private var hover = false
    var body: some View {
        let palette = OrbitPalette(dark: scheme == .dark)
        Button(action: action) {
            Image(systemName: symbol).font(.system(size: 14, weight: .medium))
                .frame(width: compact ? SpaceStyle.toolbarHeight : SpaceStyle.controlHeight,
                       height: compact ? SpaceStyle.toolbarHeight : SpaceStyle.controlHeight)
                .foregroundStyle(primary ? .white : selected ? palette.accent : palette.secondary)
                .background(primary ? palette.primary : (selected || hover ? palette.hover : Color.clear), in: RoundedRectangle(cornerRadius: SpaceStyle.cornerRadius, style: .continuous))
                .contentShape(RoundedRectangle(cornerRadius: SpaceStyle.cornerRadius, style: .continuous))
        }
        .buttonStyle(.plain).onHover { hover = $0 }.help(label).accessibilityLabel(label)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

struct CategoryBadge: View {
    let category: TaskCategory
    var count: Int? = nil
    @Environment(\.colorScheme) private var scheme
    var body: some View {
        let palette = OrbitPalette(dark: scheme == .dark)
        HStack(spacing: 4) {
            Circle().fill(palette.category(category)).frame(width: 7, height: 7)
            Text(category.title + (count.map { " \($0)" } ?? ""))
        }.orbitFont(12).foregroundStyle(palette.secondary)
    }
}

struct SpaceRibbon: Shape {
    func path(in rect: CGRect) -> Path {
        let sx = rect.width / 40, sy = rect.height / 40
        var path = Path()
        path.move(to: CGPoint(x: 27 * sx, y: 11 * sy))
        path.addLine(to: CGPoint(x: 17 * sx, y: 11 * sy))
        path.addCurve(to: CGPoint(x: 17 * sx, y: 20 * sy), control1: CGPoint(x: 8 * sx, y: 11 * sy), control2: CGPoint(x: 8 * sx, y: 20 * sy))
        path.addLine(to: CGPoint(x: 23 * sx, y: 20 * sy))
        path.addCurve(to: CGPoint(x: 23 * sx, y: 29 * sy), control1: CGPoint(x: 32 * sx, y: 20 * sy), control2: CGPoint(x: 32 * sx, y: 29 * sy))
        path.addLine(to: CGPoint(x: 13 * sx, y: 29 * sy))
        return path
    }
}

struct OrbitMark: View {
    var size: CGFloat = 32
    @Environment(\.colorScheme) private var scheme
    var body: some View {
        let palette = OrbitPalette(dark: scheme == .dark)
        ZStack {
            RoundedRectangle(cornerRadius: SpaceStyle.cornerRadius, style: .continuous).fill(palette.primary)
            SpaceRibbon().stroke(.white, style: StrokeStyle(lineWidth: size * 0.085, lineCap: .round, lineJoin: .round))
            RoundedRectangle(cornerRadius: size * 0.025).fill(Color(hex: 0xB8D2FF))
                .frame(width: size * 0.10, height: size * 0.10).offset(x: size * 0.26, y: -size * 0.27)
        }.frame(width: size, height: size).accessibilityHidden(true)
    }
}

struct AmbientBackground: View {
    let dark: Bool
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                OrbitPalette(dark: dark).canvas
                if dark && !reduceTransparency {
                    Ellipse().fill(Color(hex: 0x8B5CF6).opacity(0.22))
                        .frame(width: geometry.size.width * 0.5, height: geometry.size.height * 0.65)
                        .blur(radius: 120).offset(x: geometry.size.width * 0.05, y: geometry.size.height * 0.05)
                    Ellipse().fill(Color(hex: 0x9333EA).opacity(0.36))
                        .frame(width: geometry.size.width * 0.65, height: geometry.size.height * 0.55)
                        .blur(radius: 100).offset(x: geometry.size.width * 0.35, y: -geometry.size.height * 0.4)
                    Ellipse().fill(Color(hex: 0xA855F7).opacity(0.28))
                        .frame(width: geometry.size.width * 0.55, height: geometry.size.height * 0.45)
                        .blur(radius: 100).offset(x: -geometry.size.width * 0.35, y: geometry.size.height * 0.45)
                } else if !reduceTransparency {
                    Ellipse().fill(Color(hex: 0xAACBFA).opacity(0.65))
                        .frame(width: geometry.size.width * 0.7, height: geometry.size.height * 0.9)
                        .blur(radius: 100).offset(x: -geometry.size.width * 0.3, y: geometry.size.height * 0.15)
                    Ellipse().fill(Color(hex: 0xD1DAF6).opacity(0.7))
                        .frame(width: geometry.size.width * 0.7, height: geometry.size.height)
                        .blur(radius: 100).offset(x: geometry.size.width * 0.4, y: -geometry.size.height * 0.35)
                    Ellipse().fill(Color(hex: 0xFAF9F1).opacity(0.8))
                        .frame(width: geometry.size.width * 0.6, height: geometry.size.height * 0.8).blur(radius: 80)
                }
            }
        }.clipped().ignoresSafeArea().allowsHitTesting(false)
    }
}

/// Short, decelerating native transitions; reduced motion uses only a crossfade.
enum SpaceMotion {
    static func animation(_ reduced: Bool) -> Animation {
        .timingCurve(0.22, 1, 0.36, 1, duration: reduced ? 0.2 : 0.5)
    }
}
