import SwiftUI
import SimulationCore

struct CalendarView: View {
    @Bindable var store: WorkspaceStore
    @State private var query = ""
    @State private var filter = "all"
    private var years: [CalendarYear] { store.result?.years ?? [] }
    private var filteredYears: [CalendarYear] {
        years.filter { row in
            (query.isEmpty || String(row.year).contains(query)) &&
            (filter == "all" || (row.isComplete && row.kind.rawValue == filter))
        }
    }
    private var selected: CalendarYear? { years.first { $0.year == store.selectedYear } }

    var body: some View {
        if years.isEmpty && !store.isComputing {
            ContentUnavailableView {
                Label("等待第一份年历", systemImage: "calendar.badge.clock")
            } description: {
                Text("设置恒星、行星和宜居条件，然后生成万年历。\n每一年的标签都来自真实模拟的连续时间区间。")
            } actions: {
                Button("生成 \(store.draft.durationYears.formatted()) 年历法") { store.startCalendar() }
                    .buttonStyle(.borderedProminent).tint(ObservatoryPalette.mint).disabled(store.draft.planet == nil)
                if store.previousResult != nil { Button("查看上一份结果") { store.restorePreviousResult() } }
            }
        } else {
            VStack(spacing: 0) {
                HStack(spacing: 20) {
                    MetricTile(title: "已完成年份", value: store.totalCompletedYears.formatted(), unit: "年")
                    MetricTile(title: "全年恒纪元", value: store.stableYears.formatted(), unit: "年", tint: ObservatoryPalette.mint)
                    MetricTile(title: "稳定时间占比", value: store.stablePercentage.display(1), unit: "%", tint: ObservatoryPalette.amber)
                }.padding(22)
                timeline.padding(.horizontal, 22).padding(.bottom, 18)
                Divider()
                HStack(spacing: 12) {
                    TextField("查找年份", text: $query).textFieldStyle(.roundedBorder).frame(width: 135)
                    Picker("筛选", selection: $filter) {
                        Text("全部").tag("all")
                        Text("恒纪元").tag("stable")
                        Text("乱纪元").tag("chaotic")
                    }.pickerStyle(.segmented).frame(maxWidth: 230)
                    Spacer()
                    Menu {
                        Button("导出年度 CSV…") { store.exportResult(asCSV: true) }
                        Button("导出完整 JSON…") { store.exportResult(asCSV: false) }
                    } label: { Label("导出", systemImage: "square.and.arrow.up") }
                }.padding(.horizontal, 22).padding(.vertical, 12)
                Table(filteredYears, selection: $store.selectedYear) {
                    TableColumn("年份") { row in Text(String(format: "%04d", row.year)).monospacedDigit() }.width(min: 65, ideal: 75)
                    TableColumn("纪元") { row in EpochBadge(year: row) }.width(min: 85, ideal: 100)
                    TableColumn("稳定占比") { row in
                        HStack(spacing: 8) {
                            RoundedRectangle(cornerRadius: 2).fill(ObservatoryPalette.mint.opacity(0.18))
                                .overlay(alignment: .leading) { RoundedRectangle(cornerRadius: 2).fill(ObservatoryPalette.mint).frame(width: max(0, row.stableFraction * 44)) }
                                .frame(width: 44, height: 4)
                            Text("\((row.stableFraction * 100).display(1))%").monospacedDigit()
                        }
                    }.width(min: 105, ideal: 115)
                    TableColumn("模型温度 / ℃") { row in Text("\(row.minimumTemperatureC.display(1)) ~ \(row.maximumTemperatureC.display(1))").monospacedDigit().foregroundStyle(.secondary) }
                    TableColumn("总辐照 / F⊕") { row in Text("\(row.minimumFluxEarth.display(3)) ~ \(row.maximumFluxEarth.display(3))").monospacedDigit().foregroundStyle(.secondary) }
                }.font(.system(size: 11))
                if let selected { yearDetail(selected) }
                else {
                    Text("选择年份查看区间详情 · 点击时间轴快速定位")
                        .font(.system(size: 10)).foregroundStyle(.secondary).frame(maxWidth: .infinity).padding(14)
                }
            }
        }
    }

    private var timeline: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("纪元总览").font(.system(size: 11, weight: .medium))
                Spacer()
                Label("恒纪元", systemImage: "circle.fill").foregroundStyle(ObservatoryPalette.mint)
                Label("乱纪元", systemImage: "circle.fill").foregroundStyle(ObservatoryPalette.coral)
            }.font(.system(size: 9))
            GeometryReader { geometry in
                Canvas { context, size in
                    let count = max(1, years.count)
                    let bins = min(count, max(1, Int(size.width)))
                    for bin in 0..<bins {
                        let start = bin * count / bins, end = max(start + 1, (bin + 1) * count / bins)
                        let group = years[start..<min(end, years.count)]
                        let stable = group.isEmpty ? 0 : group.reduce(0) { $0 + $1.stableFraction } / Double(group.count)
                        let rect = CGRect(x: Double(bin) * size.width / Double(bins), y: 0, width: size.width / Double(bins) + 0.2, height: size.height)
                        context.fill(Path(rect), with: .color(ObservatoryPalette.coral.opacity(0.72)))
                        context.fill(Path(CGRect(x: rect.minX, y: 0, width: rect.width, height: rect.height * stable)), with: .color(ObservatoryPalette.mint))
                    }
                }.clipShape(RoundedRectangle(cornerRadius: 5))
                    .gesture(SpatialTapGesture().onEnded { event in
                        guard !years.isEmpty else { return }
                        let index = min(years.count - 1, max(0, Int(event.location.x / max(1, geometry.size.width) * Double(years.count))))
                        store.selectedYear = years[index].year
                    })
            }.frame(height: 30)
            HStack { Text("第 1 年"); Spacer(); Text("每列按实际时长汇总"); Spacer(); Text("第 \(years.count.formatted()) 年") }
                .font(.system(size: 9, design: .monospaced)).foregroundStyle(.secondary)
        }
    }

    private func yearDetail(_ year: CalendarYear) -> some View {
        let intervals = store.result?.intervals.filter { $0.endDays > year.startDays && $0.startDays < year.endDays } ?? []
        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("第 \(year.year) 年").font(.system(size: 13, weight: .semibold))
                EpochBadge(year: year)
                Spacer()
                Button("回放年初轨道") { store.showYear(year) }.font(.system(size: 11)).disabled(store.isComputing)
            }
            Text(year.isComplete ? (year.kind == .stable ? "整个标准年均处于已确认的恒纪元。" : "该年包含乱纪元区间；稳定时间占比为 \((year.stableFraction * 100).display(4))%。") : "该年度尚未完整计算，最终纪元标签待确认。")
                .font(.system(size: 11)).foregroundStyle(.secondary)
            if !intervals.isEmpty {
                Text(intervals.prefix(4).map { interval in
                    let start = max(year.startDays, interval.startDays) - year.startDays
                    let end = min(year.endDays, interval.endDays) - year.startDays
                    return "第 \(start.display(2))–\(end.display(2)) 日：\(interval.kind == .stable ? "恒纪元" : "乱纪元")"
                }.joined(separator: "　·　"))
                .font(.system(size: 10, design: .monospaced)).foregroundStyle(.secondary).lineLimit(3)
            }
        }.padding(18).frame(maxWidth: .infinity, alignment: .leading).background(.quaternary.opacity(0.25))
    }
}

struct EpochBadge: View {
    let year: CalendarYear
    var body: some View {
        HStack(spacing: 5) {
            Circle().fill(color).frame(width: 5, height: 5)
            Text(!year.isComplete ? "计算中" : year.kind == .stable ? "恒纪元" : "乱纪元")
        }.font(.system(size: 10, weight: .medium)).foregroundStyle(color)
            .padding(.horizontal, 8).padding(.vertical, 4).background(color.opacity(0.10), in: Capsule())
    }
    private var color: Color { !year.isComplete ? .secondary : year.kind == .stable ? ObservatoryPalette.mint : ObservatoryPalette.coral }
}
