import SwiftUI
import OrbitCore

struct SpaceDatePicker: View {
    @Binding var selection: String
    var fieldName = "截止日期"
    var allowsClear = true
    @State private var expanded = false
    @State private var month = Date()
    @Environment(\.colorScheme) private var scheme
    private var palette: OrbitPalette { OrbitPalette(dark: scheme == .dark) }
    private var calendar: Calendar { OrbitDate.calendar }
    private var firstDay: Date { calendar.date(from: calendar.dateComponents([.year, .month], from: month))! }
    private var days: [Date] {
        let offset = calendar.component(.weekday, from: firstDay) - 1
        return (0..<42).map { calendar.date(byAdding: .day, value: $0 - offset, to: firstDay)! }
    }
    var body: some View {
        Button { expanded.toggle() } label: {
            HStack(spacing: 8) {
                Image(systemName: "calendar").foregroundStyle(palette.accent)
                Text(selection.isEmpty ? "未设置" + fieldName : selection).orbitFont(14)
                Spacer()
                Image(systemName: "chevron.down").font(.system(size: 10))
            }.foregroundStyle(selection.isEmpty ? palette.muted : palette.text)
                .padding(.horizontal, 12).frame(height: 40).glass(palette)
        }.buttonStyle(.plain).help("选择或清除任务" + fieldName + "，按北京时间计算")
            .accessibilityLabel("选择" + fieldName).accessibilityValue(selection.isEmpty ? "未设置" : selection)
            .popover(isPresented: $expanded, arrowEdge: .top) {
                VStack(spacing: 12) {
                    HStack(spacing: 8) {
                        OrbitIconButton(symbol: "chevron.left", label: "上一个月") { changeMonth(-1) }
                        Spacer()
                        Text(String(format: "%d年%d月", calendar.component(.year, from: month), calendar.component(.month, from: month))).orbitFont(16, weight: .semibold)
                        Spacer()
                        OrbitIconButton(symbol: "chevron.right", label: "下一个月") { changeMonth(1) }
                    }
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 4), count: 7), spacing: 4) {
                        ForEach(["日", "一", "二", "三", "四", "五", "六"], id: \.self) { Text($0).orbitFont(12).foregroundStyle(palette.muted).frame(height: 24) }
                        ForEach(days, id: \.self) { date in
                            let key = OrbitDate.day(date), selected = key == selection
                            Button { select(key) } label: {
                                Text(String(calendar.component(.day, from: date))).orbitFont(12, weight: selected ? .semibold : .regular)
                                    .frame(maxWidth: .infinity).frame(height: 32)
                                    .foregroundStyle(selected ? .white : palette.text.opacity(calendar.isDate(date, equalTo: month, toGranularity: .month) ? 1 : 0.35))
                                    .background(selected ? palette.primary : key == OrbitDate.day() ? palette.hover : .clear,
                                                in: RoundedRectangle(cornerRadius: SpaceStyle.cornerRadius, style: .continuous))
                                    .overlay { RoundedRectangle(cornerRadius: SpaceStyle.cornerRadius, style: .continuous).strokeBorder(key == OrbitDate.day() && !selected ? palette.accent : .clear) }
                            }.buttonStyle(.plain).help("\(fieldName)：\(key)").accessibilityLabel("选择\(key)")
                        }
                    }
                    HStack(spacing: 8) {
                        Button("今天") { select(OrbitDate.day()) }.help("将" + fieldName + "设为今天")
                        Button("明天") { select(OrbitDate.offsetDay(1)) }.help("将" + fieldName + "设为明天")
                        Spacer(minLength: 0)
                        if allowsClear { Button("清除") { select("") }.help("移除" + fieldName) }
                    }.buttonStyle(SpaceButtonStyle())
                }.padding(16).frame(width: 304).foregroundStyle(palette.text).glass(palette).preferredColorScheme(scheme)
                    .onAppear { month = OrbitDate.parseDay(selection) ?? Date() }
                    .onExitCommand { expanded = false }
            }
    }
    private func changeMonth(_ amount: Int) { month = calendar.date(byAdding: .month, value: amount, to: firstDay)! }
    private func select(_ value: String) { selection = value; expanded = false }
}
