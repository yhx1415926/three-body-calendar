import SwiftUI
import SimulationCore

struct RandomSystemView: View {
    @Bindable var store: WorkspaceStore
    @Environment(\.dismiss) private var dismiss
    @State private var stars = 3
    @State private var planets = 1
    @State private var seed = String(UInt64.random(in: 1...UInt64.max))
    @State private var issue: String?
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("自定义随机星系").font(.title2.weight(.medium))
            Text("设置恒星与行星的数量，生成一组可用种子重现的初始位置和速度。").foregroundStyle(.secondary)
            Stepper("恒星：\(stars)", value: $stars, in: 1...(Scenario.maximumBodyCount-planets))
            Stepper("行星：\(planets)", value: $planets, in: 0...(Scenario.maximumBodyCount-stars))
            Text("共 \(stars+planets) 个天体 · 最多 \(Scenario.maximumBodyCount) 个").font(.caption).foregroundStyle(.secondary)
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
                    do { try store.generateRandomSystem(stars: stars, planets: planets, seed: value); dismiss() }
                    catch { issue = error.localizedDescription }
                }.buttonStyle(.borderedProminent).keyboardShortcut(.defaultAction)
            }
        }.padding(26).frame(width: 440)
    }
}
