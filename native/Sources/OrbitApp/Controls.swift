import SwiftUI
import OrbitCore

struct SpaceOption<Value: Hashable>: Identifiable {
    let value: Value
    let title: String
    var id: Value { value }
    init(_ value: Value, _ title: String) { self.value = value; self.title = title }
}

/// One full-width trigger and one consistent, keyboard-accessible option surface.
struct SpaceSelect<Value: Hashable>: View {
    let label: String
    @Binding var selection: Value
    let options: [SpaceOption<Value>]
    var width: CGFloat? = nil
    var active = false
    @State private var expanded = false
    @State private var triggerWidth: CGFloat = 0
    @State private var hovered = false
    @FocusState private var focused: Bool
    @Environment(\.colorScheme) private var scheme
    private var palette: OrbitPalette { OrbitPalette(dark: scheme == .dark) }

    var body: some View {
        Button { expanded.toggle() } label: {
            HStack(spacing: 8) {
                Text(options.first { $0.value == selection }?.title ?? label)
                    .lineLimit(1).frame(maxWidth: .infinity, alignment: .leading)
                Image(systemName: "chevron.down").font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(palette.muted)
            }.orbitFont(12).foregroundStyle(active ? palette.accent : palette.text)
                .padding(.horizontal, 12).frame(height: 40)
                .background(hovered || active ? palette.hover : palette.card.opacity(0.7), in: RoundedRectangle(cornerRadius: SpaceStyle.cornerRadius, style: .continuous))
                .overlay { RoundedRectangle(cornerRadius: SpaceStyle.cornerRadius, style: .continuous).strokeBorder(focused || expanded ? palette.accent : palette.border, lineWidth: focused || expanded ? 2 : 1) }
                .contentShape(RoundedRectangle(cornerRadius: SpaceStyle.cornerRadius, style: .continuous))
        }.buttonStyle(.plain).focused($focused).onHover { hovered = $0 }
            .frame(width: width)
            .background { GeometryReader { geometry in
                Color.clear.onAppear { triggerWidth = geometry.size.width }
                    .onChange(of: geometry.size.width) { _, value in triggerWidth = value }
            } }.help(label).accessibilityLabel(label)
            .accessibilityValue(options.first { $0.value == selection }?.title ?? "")
            .popover(isPresented: $expanded, arrowEdge: .bottom) {
                SpaceOptions(selection: $selection, options: options, expanded: $expanded)
                    .frame(width: max(triggerWidth, width ?? 0, 1))
                    .preferredColorScheme(scheme)
            }
    }
}

private struct SpaceOptions<Value: Hashable>: View {
    @Binding var selection: Value
    let options: [SpaceOption<Value>]
    @Binding var expanded: Bool
    @State private var highlighted = 0
    @FocusState private var keyboardFocused: Bool
    @Environment(\.colorScheme) private var scheme
    private var palette: OrbitPalette { OrbitPalette(dark: scheme == .dark) }
    var body: some View {
        ScrollViewReader { scroll in
            VStack(spacing: 0) {
                ScrollView {
                    VStack(spacing: 4) {
                        ForEach(Array(options.enumerated()), id: \.element.id) { index, option in
                            Button { choose(index) } label: {
                                HStack(spacing: 8) {
                                    Image(systemName: "checkmark").font(.system(size: 11, weight: .semibold))
                                        .opacity(selection == option.value ? 1 : 0).frame(width: 16)
                                    Text(option.title).orbitFont(12)
                                    Spacer(minLength: 0)
                                }.padding(.horizontal, 8).frame(height: 36)
                                    .foregroundStyle(selection == option.value ? palette.accent : palette.text)
                                    .background(highlighted == index ? palette.hover : .clear, in: RoundedRectangle(cornerRadius: SpaceStyle.cornerRadius, style: .continuous))
                                    .contentShape(RoundedRectangle(cornerRadius: SpaceStyle.cornerRadius, style: .continuous))
                            }.buttonStyle(.plain).help("选择“\(option.title)”").onHover { if $0 { highlighted = index } }
                                .accessibilityAddTraits(selection == option.value ? .isSelected : [])
                                .id(index)
                        }
                    }.padding(8)
                }.frame(height: min(CGFloat(options.count) * 40 + 12, 320))
            }.glass(palette)
                .focusable().focused($keyboardFocused).focusEffectDisabled()
                .onAppear {
                    highlighted = options.firstIndex { $0.value == selection } ?? 0
                    DispatchQueue.main.async { keyboardFocused = true; scroll.scrollTo(highlighted, anchor: .center) }
                }
                .onKeyPress(.return) { choose(highlighted); return .handled }
                .onKeyPress(.downArrow) {
                    highlighted = min(options.count - 1, highlighted + 1)
                    scroll.scrollTo(highlighted, anchor: .center); return .handled
                }
                .onKeyPress(.upArrow) {
                    highlighted = max(0, highlighted - 1)
                    scroll.scrollTo(highlighted, anchor: .center); return .handled
                }
                .onExitCommand { expanded = false }
        }
    }
    private func choose(_ index: Int) {
        guard options.indices.contains(index) else { return }
        selection = options[index].value; expanded = false
    }
}

struct SpaceSegments: View {
    @Binding var selection: Bool
    let firstSymbol: String
    let secondSymbol: String
    let firstLabel: String
    let secondLabel: String
    var showLabels = false
    @Environment(\.colorScheme) private var scheme
    var body: some View {
        let palette = OrbitPalette(dark: scheme == .dark)
        HStack(spacing: 2) {
            segment(false, symbol: firstSymbol, label: firstLabel, palette: palette)
            segment(true, symbol: secondSymbol, label: secondLabel, palette: palette)
        }.padding(2)
            .background(palette.hover.opacity(0.65), in: RoundedRectangle(cornerRadius: SpaceStyle.cornerRadius, style: .continuous))
            .overlay { RoundedRectangle(cornerRadius: SpaceStyle.cornerRadius, style: .continuous).strokeBorder(palette.border) }
            .accessibilityElement(children: .contain)
    }
    private func segment(_ value: Bool, symbol: String, label: String, palette: OrbitPalette) -> some View {
        Button { selection = value } label: {
            HStack(spacing: 8) {
                Image(systemName: symbol).font(.system(size: 14, weight: .medium))
                if showLabels { Text(label).orbitFont(12) }
            }.frame(minWidth: showLabels ? 64 : 32, minHeight: showLabels ? 36 : 32)
                .padding(.horizontal, showLabels ? 8 : 0)
                .foregroundStyle(selection == value ? palette.accent : palette.secondary)
                .background(selection == value ? palette.card : .clear, in: RoundedRectangle(cornerRadius: SpaceStyle.cornerRadius, style: .continuous))
                .overlay { RoundedRectangle(cornerRadius: SpaceStyle.cornerRadius, style: .continuous).strokeBorder(selection == value ? palette.border : .clear) }
                .contentShape(RoundedRectangle(cornerRadius: SpaceStyle.cornerRadius, style: .continuous))
        }.buttonStyle(.plain).help(label).accessibilityLabel(label)
            .accessibilityAddTraits(selection == value ? .isSelected : [])
    }
}

struct SpaceThemeToggle: View {
    @Binding var dark: Bool
    @Environment(\.colorScheme) private var scheme
    var body: some View {
        let palette = OrbitPalette(dark: scheme == .dark)
        Button { dark.toggle() } label: {
            HStack(spacing: 0) {
                Image(systemName: "sun.max.fill")
                    .foregroundStyle(dark ? palette.secondary : palette.accent)
                    .frame(width: 32, height: 32)
                    .background(!dark ? palette.card : .clear, in: Circle())
                Image(systemName: "moon.fill")
                    .foregroundStyle(dark ? palette.accent : palette.secondary)
                    .frame(width: 32, height: 32)
                    .background(dark ? palette.card : .clear, in: Circle())
            }
            .font(.system(size: 13, weight: .medium))
            .padding(2)
            .background(palette.hover.opacity(0.65), in: Capsule())
            .overlay { Capsule().strokeBorder(palette.border) }
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .help(dark ? "切换到明亮主题" : "切换到暗色主题")
        .accessibilityLabel(dark ? "当前为暗色主题，切换到明亮主题" : "当前为明亮主题，切换到暗色主题")
    }
}

struct SpaceButtonStyle: ButtonStyle {
    var compact = false
    var primary = false
    var danger = false
    @Environment(\.colorScheme) private var scheme
    func makeBody(configuration: Configuration) -> some View {
        let palette = OrbitPalette(dark: scheme == .dark)
        configuration.label.orbitFont(14, weight: .semibold)
            .foregroundStyle(primary ? .white : danger ? palette.red : palette.secondary)
            .padding(.horizontal, 12).frame(height: compact ? 32 : SpaceStyle.controlHeight)
            .background(primary ? palette.primary : palette.hover, in: RoundedRectangle(cornerRadius: SpaceStyle.cornerRadius, style: .continuous))
            .overlay { RoundedRectangle(cornerRadius: SpaceStyle.cornerRadius, style: .continuous).strokeBorder(primary ? .white.opacity(0.15) : palette.border) }
            .opacity(configuration.isPressed ? 0.8 : 1)
    }
}

enum TaskChoices {
    static let priorities = [SpaceOption<TaskPriority?>(nil, "所有优先级")] + TaskPriority.allCases.map { SpaceOption(Optional($0), $0.title + "优先级") }
    static let categories = [SpaceOption<TaskCategory?>(nil, "所有分类")] + TaskCategory.allCases.map { SpaceOption(Optional($0), $0.title) }
    static let dates = [SpaceOption("all", "所有日期"), SpaceOption("today", "今天截止"), SpaceOption("overdue", "已逾期"), SpaceOption("none", "未设置日期")]
    static let sorts = TaskSort.allCases.map { SpaceOption($0, $0.title) }
}

/// Sheet chrome shares a 48pt height and 24pt horizontal inset.
struct SpaceSheetHeader: View {
    let title: String
    let closeLabel: String
    let close: () -> Void
    @Environment(\.colorScheme) private var scheme
    var body: some View {
        HStack(spacing: 8) {
            Text(title).orbitFont(16, weight: .semibold)
            Spacer()
            Button(action: close) {
                Image(systemName: "xmark").font(.system(size: 12, weight: .medium))
                    .frame(width: 24, height: 24).contentShape(Rectangle())
            }.buttonStyle(.plain).help(closeLabel).accessibilityLabel(closeLabel)
                .foregroundStyle(OrbitPalette(dark: scheme == .dark).secondary)
        }.padding(.horizontal, 24).frame(height: 48)
    }
}
