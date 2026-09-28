import SwiftUI
import Charts
import SimulationCore

struct AnalysisView: View {
    @Bindable var store: WorkspaceStore
    private var chartYears: [CalendarYear] {
        let rows = store.result?.years ?? []
        let stride = max(1, rows.count / 700)
        return rows.enumerated().compactMap { $0.offset % stride == 0 ? $0.element : nil }
    }
    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                ConservationMetrics(store: store)
                if !chartYears.isEmpty {
                    Panel(title: "模型温度的长期变化", subtitle: "YEAR / °C") {
                        temperatureChart
                        Text("阴影表示每年的温度范围；曲线为范围中点。长历法按年份抽样显示，完整数值可导出。")
                            .font(.system(size: 10)).foregroundStyle(.secondary)
                    }
                    Panel(title: "所有恒星的总辐照", subtitle: "YEAR / F⊕") { fluxChart }
                }
                Panel(title: "精度复核", subtitle: "NUMERICAL VERIFICATION") {
                    Text(store.verificationSummary ?? "当前结果尚未与更严格设置独立复算比较。守恒诊断可以揭示数值问题，但不能保证混沌轨迹的长期唯一性。")
                        .font(.system(size: 12)).foregroundStyle(.secondary).lineSpacing(4)
                    HStack {
                        Button("使用更严格参数复算") { store.startCalendar(strict: true) }
                            .disabled(store.result == nil || store.isComputing)
                        if store.previousResult != nil { Button("切换到上一份结果") { store.restorePreviousResult() }.disabled(store.isComputing) }
                        Spacer()
                    }
                    Text("复核设置：IAS15 ε = 10⁻¹¹，每标准年至少 1024 次环境采样。")
                        .font(.system(size: 10, design: .monospaced)).foregroundStyle(.tertiary)
                }
                if let result = store.result, !result.events.isEmpty {
                    Panel(title: "模拟事件", subtitle: "EVENT LOG") {
                        ForEach(result.events) { event in
                            HStack(alignment: .top, spacing: 16) {
                                Text("\((event.timeDays / result.standardYearDays).display(5)) 年")
                                    .font(.system(size: 10, design: .monospaced)).foregroundStyle(ObservatoryPalette.amber).frame(width: 110, alignment: .leading)
                                Text(event.message).font(.system(size: 11)).foregroundStyle(.secondary)
                            }
                        }
                    }
                }
                Panel(title: "模型与判定依据", subtitle: "MODEL NOTES") {
                    VStack(alignment: .leading, spacing: 12) {
                        modelLine("引力", "所有恒星与有质量行星相互作用；双精度牛顿引力，有限半径碰撞终止。")
                        modelLine("标准年", "T = 2π√[a³ / G(M★ + Mₚ)]。参考恒星与距离在本次运行中固定。")
                        modelLine("气候", "合并所有恒星的辐照，为指定历法行星计算全球平均模型温度，考虑反照率、温室增温和热响应时间。")
                        modelLine("纪元", "满足温度、总辐照、波动及最短持续时间的区间为恒纪元；全年覆盖才标为恒纪元年。")
                        modelLine("边界", "未包含完整大气、昼夜和季节、遮掩、恒星演化及相对论效应。宜居阈值为可调整的作品规则。")
                        modelLine("复现", "随机种子、完整初值、计算设置、规则与内核版本随项目保存。跨版本或架构不承诺逐位相同。")
                    }
                    HStack {
                        Link("IAS15 方法", destination: URL(string: "https://arxiv.org/abs/1409.4779")!)
                        Link("REBOUND 源码", destination: URL(string: "https://github.com/hannorein/rebound/tree/4.4.11")!)
                        Spacer()
                        Text("REBOUND 4.4.11 · GPL-3.0-or-later").foregroundStyle(.tertiary)
                    }.font(.system(size: 10))
                }
            }.padding(22)
        }
    }
    private var temperatureChart: some View {
        Chart(chartYears) { year in
            AreaMark(x: .value("年", year.year), yStart: .value("最低", year.minimumTemperatureC), yEnd: .value("最高", year.maximumTemperatureC))
                .foregroundStyle(ObservatoryPalette.amber.opacity(0.16))
            LineMark(x: .value("年", year.year), y: .value("范围中点", (year.minimumTemperatureC + year.maximumTemperatureC) / 2))
                .foregroundStyle(ObservatoryPalette.amber).lineStyle(StrokeStyle(lineWidth: 1.3))
        }.chartYAxis { AxisMarks(position: .leading) }.frame(height: 170)
    }
    private var fluxChart: some View {
        Chart(chartYears) { year in
            AreaMark(x: .value("年", year.year), yStart: .value("最低", year.minimumFluxEarth), yEnd: .value("最高", year.maximumFluxEarth))
                .foregroundStyle(ObservatoryPalette.mint.opacity(0.16))
            LineMark(x: .value("年", year.year), y: .value("范围中点", (year.minimumFluxEarth + year.maximumFluxEarth) / 2))
                .foregroundStyle(ObservatoryPalette.mint).lineStyle(StrokeStyle(lineWidth: 1.3))
        }.chartYAxis { AxisMarks(position: .leading) }.frame(height: 140)
    }
    private func modelLine(_ title: String, _ content: String) -> some View {
        HStack(alignment: .top, spacing: 15) {
            Text(title).font(.system(size: 11, weight: .medium)).frame(width: 42, alignment: .leading)
            Text(content).font(.system(size: 11)).foregroundStyle(.secondary).lineSpacing(3)
        }
    }
}

private struct ConservationMetrics: View {
    let store: WorkspaceStore
    var body: some View {
        HStack(spacing: 22) {
            MetricTile(title: "能量相对特征尺度漂移", value: store.snapshot?.diagnostics.normalizedEnergyError.scientific ?? "—", tint: ObservatoryPalette.mint)
            MetricTile(title: "角动量归一化漂移", value: store.snapshot?.diagnostics.normalizedAngularMomentumError.scientific ?? "—")
            MetricTile(title: "最近天体间距", value: store.snapshot?.diagnostics.minimumSeparationAU.display(4) ?? "—", unit: "AU")
        }.padding(.vertical, 3)
    }
}
