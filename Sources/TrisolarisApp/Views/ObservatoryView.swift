import SwiftUI
import SimulationCore

struct ObservatoryView: View {
    @Bindable var store: WorkspaceStore
    @AppStorage("showGrid") private var showGrid = true
    @AppStorage("exaggeratedSizes") private var exaggeratedSizes = true
    var body: some View {
        VStack(spacing: 0) {
            sceneLegend
            OrbitSceneView(frame: store.frame, trails: store.trails, selectedID: $store.selectedBodyID,
                           followSelected: store.followSelected, topDown: store.topDown, showGrid: showGrid,
                           exaggeratedSizes: exaggeratedSizes, resetToken: store.resetToken,
                           captureToken: store.captureToken, onCapture: store.receiveScenePNG)
                .frame(minHeight: 280)
            sceneCaption
            playbackControls
            Divider()
            HStack(spacing: 24) {
                MetricTile(title: "经过时间", value: store.currentYear.display(3), unit: "标准年")
                MetricTile(title: store.snapshot?.temperatureC == nil ? "瞬时平衡温度" : "模型温度", value: temperatureDisplay, unit: "℃", tint: ObservatoryPalette.amber)
                MetricTile(title: "总辐照", value: store.snapshot?.fluxEarth?.display(3) ?? "—", unit: "F⊕", tint: ObservatoryPalette.mint)
                MetricTile(title: "归一化能量误差", value: store.snapshot?.diagnostics.normalizedEnergyError.scientific ?? "—")
            }.padding(22)
        }
    }

    private var temperatureDisplay: String {
        if let temperature = store.snapshot?.temperatureC { return temperature.display(1) }
        if let flux = store.snapshot?.fluxEarth { return store.activeScenario.climateRules.equilibriumTemperatureC(fluxEarth: flux).display(1) }
        return "—"
    }

    private var sceneLegend: some View {
        HStack(spacing: 14) {
            ForEach(Array(store.frame.bodies.enumerated()), id: \.element.id) { index, body in
                Button { store.selectedBodyID = body.id } label: {
                    HStack(spacing: 5) {
                        Circle().fill(ObservatoryPalette.bodyColors[index % 4]).frame(width: 7, height: 7)
                        Text(body.name).font(.system(size: 10))
                        if store.selectedBodyID == body.id { Image(systemName: "checkmark").font(.system(size: 9)) }
                    }
                }.buttonStyle(.plain)
            }
            Spacer(minLength: 4)
            Button { store.resetToken += 1 } label: { Image(systemName: "arrow.up.left.and.arrow.down.right") }.help("重置视角 ⌘0")
            Toggle("俯视", isOn: $store.topDown).toggleStyle(.checkbox)
            Toggle("跟随所选天体", isOn: $store.followSelected).toggleStyle(.checkbox)
            Button { store.requestScenePNG() } label: { Image(systemName: "camera") }.help("导出场景 PNG")
        }.font(.system(size: 10)).buttonStyle(.borderless).padding(.horizontal, 18).padding(.vertical, 10).background(.bar)
    }

    private var sceneCaption: some View {
        HStack {
            Text("拖动旋转 · 滚动缩放 · ⇧ 拖动平移 · 点击选择")
            Spacer()
            Text(exaggeratedSizes ? "增强显示 · 天体半径固定" : "真实天体半径")
        }.font(.system(size: 9)).foregroundStyle(.secondary).padding(.horizontal, 18).padding(.vertical, 7).background(.bar)
    }

    private var playbackControls: some View {
        VStack(spacing: 10) {
            HStack(spacing: 14) {
                Button { Task { await store.resetSimulation() } } label: { Image(systemName: "backward.end.fill") }.help("回到初始时刻")
                Button { store.togglePlayback() } label: {
                    Image(systemName: store.isPlaying ? "pause.fill" : "play.fill").font(.system(size: 15)).frame(width: 30, height: 28)
                }.buttonStyle(.borderedProminent).tint(ObservatoryPalette.mint).keyboardShortcut(.space, modifiers: [])
                Button { store.step() } label: { Image(systemName: "forward.frame.fill") }.help("向前推进 1/128 标准年")
                Divider().frame(height: 18)
                Text("速度").font(.system(size: 10)).foregroundStyle(.secondary)
                Picker("播放速度", selection: $store.playbackRate) {
                    Text("0.03 年/秒").tag(0.03)
                    Text("0.12 年/秒").tag(0.12)
                    Text("1 年/秒").tag(1.0)
                    Text("10 年/秒").tag(10.0)
                }.labelsHidden().frame(width: 112)
                Spacer()
                if store.isReplay { Text("离散采样回放").font(.system(size: 10)).foregroundStyle(ObservatoryPalette.amber) }
                Toggle("网格", isOn: $showGrid).toggleStyle(.checkbox).font(.system(size: 10))
            }.buttonStyle(.borderless).disabled(store.isComputing)
            if let samples = store.result?.snapshots, samples.count > 1 {
                HStack {
                    Text("历法回放").font(.system(size: 10)).foregroundStyle(.secondary)
                    Slider(value: Binding(get: { store.replayIndex }, set: { store.seekReplay($0) }), in: 0...Double(samples.count - 1), step: 1)
                        .tint(ObservatoryPalette.mint).disabled(store.isComputing)
                    Text("\((samples.last!.timeDays / store.standardYearDays).display(0)) 年").font(.system(size: 10, design: .monospaced)).foregroundStyle(.secondary)
                }
            }
        }.padding(.horizontal, 22).padding(.vertical, 12)
    }
}
