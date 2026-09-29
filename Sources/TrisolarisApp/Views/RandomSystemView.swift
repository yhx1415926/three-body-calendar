import SwiftUI
import SimulationCore

struct RandomSystemView: View {
    @Bindable var store: WorkspaceStore
    @Environment(\.dismiss) private var dismiss
    @State private var starsText = "3"
    @State private var planetsText = "1"
    @State private var seed = String(UInt64.random(in: 1...UInt64.max))
    @State private var issue: String?
    private var counts: (stars: Int, planets: Int)? {
        guard let stars = Int(starsText), let planets = Int(planetsText),
              (1...Scenario.maximumBodyCount).contains(stars),
              (0..<Scenario.maximumBodyCount).contains(planets),
              stars + planets <= Scenario.maximumBodyCount else { return nil }
        return (stars, planets)
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("自定义随机星系").font(.title2.weight(.medium))
            Text("设置恒星与行星的数量，生成一组可用种子重现的初始位置和速度。").foregroundStyle(.secondary)
            countControl("恒星数量", text: $starsText, range: 1...Scenario.maximumBodyCount)
            countControl("行星数量", text: $planetsText, range: 0...(Scenario.maximumBodyCount-1))
            if let counts {
                Text("共 \(counts.stars+counts.planets) 个天体 · 最多 \(Scenario.maximumBodyCount) 个")
                    .font(.caption).foregroundStyle(.secondary)
            } else {
                Text("至少 1 颗恒星，最多共 \(Scenario.maximumBodyCount) 个天体；行星可为 0 颗。")
                    .font(.caption).foregroundStyle(.red)
            }
            TextField("随机种子", text: $seed).textFieldStyle(.roundedBorder)
            NumberControl(title: "空间尺度", value: $store.randomSpatialScaleAU, unit: "AU")
            NumberControl(title: "恒星动能 / |势能|", value: $store.randomVirialRatio)
            Text("所有天体共同参与引力计算。每次万年历计算针对一颗指定行星；可在参数面板切换。随机生成不保证长期稳定。").font(.caption).foregroundStyle(.secondary)
            if let issue { Text(issue).font(.caption).foregroundStyle(.red) }
            HStack {
                Button("换一个种子") { seed = String(UInt64.random(in: 1...UInt64.max)) }
                Spacer()
                Button("取消") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("生成星系") {
                    guard let value = UInt64(seed) else { issue = "种子应为非负整数。"; return }
                    guard let counts else { issue = "请填写有效的恒星和行星数量，总数不得超过 64。"; return }
                    do { try store.generateRandomSystem(stars: counts.stars, planets: counts.planets, seed: value); dismiss() }
                    catch { issue = error.localizedDescription }
                }.buttonStyle(.borderedProminent).keyboardShortcut(.defaultAction)
            }
        }.padding(26).frame(width: 440)
    }

    private func countControl(_ title: String, text: Binding<String>, range: ClosedRange<Int>) -> some View {
        HStack(spacing: 12) {
            Text(title)
            Spacer()
            TextField(title, text: text)
                .textFieldStyle(.roundedBorder)
                .multilineTextAlignment(.trailing)
                .frame(width: 76)
                .accessibilityLabel(title)
            Stepper(title, value: Binding(
                get: { min(range.upperBound, max(range.lowerBound, Int(text.wrappedValue) ?? range.lowerBound)) },
                set: { text.wrappedValue = String($0) }
            ), in: range)
                .labelsHidden()
                .help("也可直接输入数量")
        }
    }
}
