import SwiftUI

struct PreferencesView: View {
    @AppStorage("appearance") private var appearance = "system"
    @AppStorage("showGrid") private var showGrid = true
    @AppStorage("exaggeratedSizes") private var exaggeratedSizes = true
    @AppStorage("trailPoints") private var trailPoints = 900
    var body: some View {
        Form {
            Section("外观") {
                Picker("界面外观", selection: $appearance) {
                    Text("跟随系统").tag("system")
                    Text("浅色").tag("light")
                    Text("深色").tag("dark")
                }
                Toggle("显示轨道参考网格", isOn: $showGrid)
                Toggle("增强天体显示大小", isOn: $exaggeratedSizes)
                Picker("轨迹保留范围", selection: $trailPoints) {
                    Text("短 · 2.5 标准年").tag(300)
                    Text("标准 · 7.5 标准年").tag(900)
                    Text("长 · 20 标准年").tag(2400)
                }
                Text("轨迹按模拟时间逐渐消退，播放越快，旧轨迹在屏幕上停留越短；采样精细度保持一致。")
                    .font(.system(size: 11)).foregroundStyle(.secondary)
            }
            Section("计算与单位") {
                Text("引力计算采用双精度 IAS15 自适应积分。播放速度仅控制观测时间，画面帧率不改变计算精度。")
                Text("距离：AU　质量：太阳质量　时间：日（86,400 秒）\n标准年由项目中的参考恒星和参考距离确定。")
                Text("宜居条件和温度均为可调整的简化模型。具体规则在项目检查器中设置。")
            }.font(.system(size: 12)).foregroundStyle(.secondary)
        }.formStyle(.grouped).frame(width: 500, height: 420)
    }
}
