import SwiftUI
import SimulationCore

struct InspectorView: View {
    @Bindable var store: WorkspaceStore
    @State private var showPosition = false
    @State private var showClimate = false
    @State private var showNumerics = false
    @State private var showOrbitEditor = false
    @State private var seedText = "314159"
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                HStack {
                    Eyebrow(text: "SYSTEM PARAMETERS")
                    Spacer()
                    if store.isDraftChanged { Circle().fill(ObservatoryPalette.amber).frame(width: 6, height: 6).help("参数尚未应用") }
                }
                VStack(alignment: .leading, spacing: 10) {
                    Text("实验配置").font(.system(size: 14, weight: .semibold))
                    TextField("配置名称", text: $store.draft.name).textFieldStyle(.roundedBorder)
                    HStack {
                        Text("历法年数").font(.system(size: 11)).foregroundStyle(.secondary)
                        Spacer()
                        TextField("年数", value: $store.draft.durationYears, format: .number.grouping(.never))
                            .textFieldStyle(.roundedBorder).frame(width: 104).multilineTextAlignment(.trailing)
                    }
                    if !store.draft.bodies.filter({ $0.kind == .planet }).isEmpty {
                        Picker("历法行星", selection: Binding(get: { store.draft.planet?.id }, set: { store.draft.calendarPlanetID = $0 })) {
                            ForEach(store.draft.bodies.filter { $0.kind == .planet }) { Text($0.name).tag(Optional($0.id)) }
                        }.font(.system(size: 11))
                    }
                    Picker("参考恒星", selection: $store.draft.referenceStarID) {
                        ForEach(store.draft.bodies.filter { $0.kind == .star }) { Text($0.name).tag($0.id) }
                    }.font(.system(size: 11))
                    NumberControl(title: "适宜参考距离", value: $store.draft.referenceDistanceAU, unit: "AU")
                    Button("按地球参考辐照计算距离") {
                        if let star = store.draft.referenceStar { store.draft.referenceDistanceAU = sqrt(star.luminositySolar) }
                    }.font(.system(size: 10)).buttonStyle(.link)
                    Text("1 标准年 = \(store.draft.standardYearDays.display(3)) 日\n参考年在计算开始时冻结，换星后仍连续计年。")
                        .font(.system(size: 10)).foregroundStyle(.secondary).lineSpacing(4)
                }
                Divider()
                if let index = store.selectedBodyIndex {
                    bodyEditor(index)
                    Divider()
                }
                DisclosureGroup(isExpanded: $showClimate) {
                    VStack(spacing: 9) {
                        NumberControl(title: "最低适宜温度", value: $store.draft.climateRules.minimumTemperatureC, unit: "℃")
                        NumberControl(title: "最高适宜温度", value: $store.draft.climateRules.maximumTemperatureC, unit: "℃")
                        NumberControl(title: "最低总辐照", value: $store.draft.climateRules.minimumFluxEarth, unit: "F⊕")
                        NumberControl(title: "最高总辐照", value: $store.draft.climateRules.maximumFluxEarth, unit: "F⊕")
                        NumberControl(title: "最大变异系数", value: $store.draft.climateRules.maximumFluxCoefficientOfVariation)
                        NumberControl(title: "波动统计窗口", value: $store.draft.climateRules.rollingWindowYears, unit: "年")
                        NumberControl(title: "最短稳定时长", value: $store.draft.climateRules.minimumStableYears, unit: "年")
                        Divider()
                        NumberControl(title: "反照率", value: $store.draft.climateRules.albedo)
                        NumberControl(title: "温室增温", value: $store.draft.climateRules.greenhouseOffsetK, unit: "K")
                        NumberControl(title: "热响应时间", value: $store.draft.climateRules.thermalResponseDays, unit: "日")
                        Text("简化的全球平均温度模型。恒纪元要求温度、总辐照和波动同时合格，且持续足够时间。")
                            .font(.system(size: 10)).foregroundStyle(.secondary).lineSpacing(3)
                    }.padding(.top, 12)
                } label: { Label("气候与纪元", systemImage: "thermometer.sun").font(.system(size: 12, weight: .medium)) }
                Divider()
                DisclosureGroup(isExpanded: $showNumerics) {
                    VStack(spacing: 10) {
                        NumberControl(title: "积分容差", value: $store.draft.numerics.tolerance)
                        HStack {
                            Text("每年环境采样").font(.system(size: 11)).foregroundStyle(.secondary)
                            Spacer()
                            Picker("每年采样", selection: $store.draft.numerics.samplesPerYear) {
                                Text("256 · 自动加密").tag(256); Text("512").tag(512); Text("1024").tag(1024); Text("2048").tag(2048); Text("4096").tag(4096)
                            }.labelsHidden().frame(width: 90)
                        }
                        Text("IAS15 · 双精度 · 自适应步长\n近距离相遇自动加密。更小的容差不代表混沌系统拥有更长的物理预测期限。")
                            .font(.system(size: 10)).foregroundStyle(.secondary).lineSpacing(4)
                        Divider()
                        HStack {
                            Text("随机种子").font(.system(size: 11)).foregroundStyle(.secondary)
                            TextField("种子", text: $seedText).textFieldStyle(.roundedBorder)
                        }
                        NumberControl(title: "随机空间尺度", value: $store.randomSpatialScaleAU, unit: "AU")
                        NumberControl(title: "动能 / |势能|", value: $store.randomVirialRatio)
                        Button("经典三体随机生成") {
                            if let seed = UInt64(seedText), store.randomSpatialScaleAU.isFinite, store.randomSpatialScaleAU > 0,
                               store.randomVirialRatio.isFinite, store.randomVirialRatio > 0 { store.choosePreset(2, seed: seed) }
                            else { store.errorMessage = "随机种子必须是非负整数。" }
                        }.font(.system(size: 11))
                        Button("自定义恒星与行星数量…") { store.showRandomSystemSheet = true }
                            .font(.system(size: 11))
                        Text("经典生成保留三体算法；多天体系统使用自定义数量入口。").font(.system(size: 10)).foregroundStyle(.secondary)
                    }.padding(.top, 12)
                } label: { Label("数值与随机设置", systemImage: "slider.horizontal.3").font(.system(size: 12, weight: .medium)) }
                if !store.draft.notes.isEmpty {
                    Divider()
                    Text(store.draft.notes).font(.system(size: 10)).foregroundStyle(.secondary).lineSpacing(4)
                }
                if !store.validationMessages.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(store.validationMessages, id: \.self) { Text($0).font(.system(size: 10)).foregroundStyle(.red) }
                    }
                }
                if store.isDraftChanged {
                    Button { Task { await store.resetSimulation() } } label: { Text("应用并重置观测").frame(maxWidth: .infinity) }
                        .buttonStyle(.borderedProminent).tint(ObservatoryPalette.mint).disabled(!store.validationMessages.isEmpty)
                }
            }.padding(18).disabled(store.isComputing)
        }
        .sheet(isPresented: $showOrbitEditor) {
            if let index = store.selectedBodyIndex { OrbitalEditorView(store: store, bodyIndex: index) }
        }
    }

    private func bodyEditor(_ index: Int) -> some View {
        let body = store.draft.bodies[index]
        return VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Circle().fill(ObservatoryPalette.bodyColor(index)).frame(width: 8, height: 8)
                Text(body.kind == .star ? "恒星参数" : "行星参数").font(.system(size: 14, weight: .semibold))
                Spacer()
            }
            TextField("天体名称", text: bodyBinding(index, \.name)).textFieldStyle(.roundedBorder)
            NumberControl(title: "质量", value: scaledBodyBinding(index, \.massSolar, scale: body.kind == .star ? 1 : Astronomy.earthMassSolar), unit: body.kind == .star ? "M☉" : "M⊕")
            NumberControl(title: "半径", value: scaledBodyBinding(index, \.radiusAU, scale: body.kind == .star ? Astronomy.solarRadiusAU : Astronomy.earthRadiusAU), unit: body.kind == .star ? "R☉" : "R⊕")
            if body.kind == .star { NumberControl(title: "光度", value: bodyBinding(index, \.luminositySolar), unit: "L☉") }
            Button("用轨道要素设置初始状态…") { showOrbitEditor = true }.font(.system(size: 11))
            DisclosureGroup("初始位置与速度", isExpanded: $showPosition) {
                VStack(spacing: 8) {
                    NumberControl(title: "位置 x", value: bodyBinding(index, \.positionAU.x), unit: "AU")
                    NumberControl(title: "位置 y", value: bodyBinding(index, \.positionAU.y), unit: "AU")
                    NumberControl(title: "位置 z", value: bodyBinding(index, \.positionAU.z), unit: "AU")
                    Divider()
                    NumberControl(title: "速度 x", value: bodyBinding(index, \.velocityAUPerDay.x), unit: "AU/d")
                    NumberControl(title: "速度 y", value: bodyBinding(index, \.velocityAUPerDay.y), unit: "AU/d")
                    NumberControl(title: "速度 z", value: bodyBinding(index, \.velocityAUPerDay.z), unit: "AU/d")
                }.padding(.top, 10)
            }.font(.system(size: 11))
        }
    }

    private func bodyBinding<T>(_ index: Int, _ keyPath: WritableKeyPath<CelestialBody, T>) -> Binding<T> {
        let body = store.draft.bodies[index]
        return Binding(get: {
            (store.draft.bodies.first { $0.id == body.id } ?? body)[keyPath: keyPath]
        }, set: { value in
            guard let current = store.draft.bodies.firstIndex(where: { $0.id == body.id }) else { return }
            store.draft.bodies[current][keyPath: keyPath] = value
        })
    }
    private func scaledBodyBinding(_ index: Int, _ keyPath: WritableKeyPath<CelestialBody, Double>, scale: Double) -> Binding<Double> {
        let binding = bodyBinding(index, keyPath)
        return Binding(get: { binding.wrappedValue / scale }, set: { binding.wrappedValue = $0 * scale })
    }
}

private struct OrbitalEditorView: View {
    @Bindable var store: WorkspaceStore
    let bodyIndex: Int
    @Environment(\.dismiss) private var dismiss
    @State private var hostID: UUID?
    @State private var semiMajor = 1.0
    @State private var eccentricity = 0.0167
    @State private var inclination = 0.0
    @State private var ascendingNode = 0.0
    @State private var periapsis = 0.0
    @State private var anomaly = 0.0
    @State private var issue: String?
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("设置初始轨道").font(.title2.weight(.medium))
            Text("将二体轨道要素转换为初始位置和速度。开始运行后，天体受整个系统共同引力影响。")
                .font(.system(size: 12)).foregroundStyle(.secondary)
            Picker("参考天体", selection: $hostID) {
                ForEach(store.draft.bodies.filter { $0.id != store.draft.bodies[bodyIndex].id }) { Text($0.name).tag(Optional($0.id)) }
            }
            NumberControl(title: "半长轴", value: $semiMajor, unit: "AU")
            NumberControl(title: "偏心率", value: $eccentricity)
            NumberControl(title: "倾角", value: $inclination, unit: "°")
            NumberControl(title: "升交点经度", value: $ascendingNode, unit: "°")
            NumberControl(title: "近心点幅角", value: $periapsis, unit: "°")
            NumberControl(title: "真近点角", value: $anomaly, unit: "°")
            if let issue { Text(issue).font(.caption).foregroundStyle(.red) }
            HStack {
                Spacer()
                Button("取消") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("应用初始状态", action: apply).buttonStyle(.borderedProminent).keyboardShortcut(.defaultAction)
            }
        }.padding(26).frame(width: 420)
            .onAppear { hostID = store.draft.bodies.first { $0.id != store.draft.bodies[bodyIndex].id && $0.kind == .star }?.id }
    }
    private func apply() {
        guard [semiMajor, eccentricity, inclination, ascendingNode, periapsis, anomaly].allSatisfy(\.isFinite), semiMajor > 0, eccentricity >= 0, eccentricity < 1,
              let host = store.draft.bodies.first(where: { $0.id == hostID }) else {
            issue = "请输入正半长轴、0 至 1（不含）的偏心率及有效角度。"; return
        }
        let body = store.draft.bodies[bodyIndex]
        guard semiMajor * (1 - eccentricity) > host.radiusAU + body.radiusAU else { issue = "近心点距离小于两个天体的半径之和。"; return }
        let f = anomaly * .pi / 180, i = inclination * .pi / 180, o = ascendingNode * .pi / 180, w = periapsis * .pi / 180
        let p = semiMajor * (1 - eccentricity * eccentricity)
        let radius = p / (1 + eccentricity * cos(f))
        let speed = sqrt(Astronomy.gravitationalConstant * (host.massSolar + body.massSolar) / p)
        func rotate(_ x: Double, _ y: Double) -> Vector3 {
            Vector3((cos(o)*cos(w)-sin(o)*sin(w)*cos(i))*x + (-cos(o)*sin(w)-sin(o)*cos(w)*cos(i))*y,
                    (sin(o)*cos(w)+cos(o)*sin(w)*cos(i))*x + (-sin(o)*sin(w)+cos(o)*cos(w)*cos(i))*y,
                    sin(w)*sin(i)*x + cos(w)*sin(i)*y)
        }
        store.draft.bodies[bodyIndex].positionAU = host.positionAU + rotate(radius*cos(f), radius*sin(f))
        store.draft.bodies[bodyIndex].velocityAUPerDay = host.velocityAUPerDay + rotate(-speed*sin(f), speed*(eccentricity+cos(f)))
        store.edited(); dismiss()
    }
}
