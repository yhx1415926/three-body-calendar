import SwiftUI
import SimulationCore

struct WorkspaceView: View {
    @State private var store = WorkspaceStore()
    @State private var showInspector = true
    @AppStorage("appearance") private var appearance = "system"

    var body: some View {
        NavigationSplitView {
            SidebarView(store: store)
                .navigationSplitViewColumnWidth(min: 180, ideal: 210, max: 250)
        } detail: {
            VStack(spacing: 0) {
                workspaceHeading
                Divider()
                Group {
                    switch store.page {
                    case .observatory: ObservatoryView(store: store)
                    case .calendar: CalendarView(store: store)
                    case .analysis: AnalysisView(store: store)
                    }
                }.frame(maxWidth: .infinity, maxHeight: .infinity)
                WorkspaceStatusBar(store: store)
            }
            .inspector(isPresented: $showInspector) {
                InspectorView(store: store)
                    .inspectorColumnWidth(min: 270, ideal: 290, max: 340)
            }
        }
        .frame(minWidth: 1120, minHeight: 720)
        .navigationTitle("三体人的万年历")
        .navigationSubtitle(store.draft.name)
        .toolbar { workspaceToolbar }
        .focusedSceneValue(\.workspaceStore, store)
        .preferredColorScheme(appearance == "dark" ? .dark : appearance == "light" ? .light : nil)
        .alert("需要处理", isPresented: Binding(get: { store.errorMessage != nil }, set: { if !$0 { store.errorMessage = nil } })) {
            Button("好", role: .cancel) { store.errorMessage = nil }
        } message: { Text(store.errorMessage ?? "") }
        .background(WindowLifecycle(store: store))
        .task { await store.bootstrap() }
        .onOpenURL { store.openProject(at: $0) }
        .onDisappear { store.shutdown() }
    }

    private var workspaceHeading: some View {
        HStack(alignment: .center, spacing: 16) {
            VStack(alignment: .leading, spacing: 5) {
                Eyebrow(text: store.page.english)
                Text(store.page == .observatory ? "在混沌中，寻找秩序。" : store.page == .calendar ? "时间的另一种刻度。" : "让每一个结论，都有依据。")
                    .font(.system(size: 22, weight: .medium))
            }
            Spacer()
            if store.isDraftChanged {
                Button { Task { await store.resetSimulation() } } label: { Label("应用参数", systemImage: "arrow.clockwise") }
                    .buttonStyle(.borderedProminent).tint(ObservatoryPalette.amber).disabled(store.isComputing)
                    .help("将编辑后的初始条件应用到新的观测；已有历法保留其原始参数。")
            } else {
                VStack(alignment: .trailing, spacing: 4) {
                    Text("1 标准年").font(.system(size: 10)).foregroundStyle(.secondary)
                    Text("\(store.standardYearDays.display(3)) 日").font(.system(size: 13, weight: .medium, design: .monospaced))
                }
            }
        }.padding(.horizontal, 24).padding(.vertical, 19)
    }

    @ToolbarContentBuilder private var workspaceToolbar: some ToolbarContent {
        ToolbarItemGroup(placement: .automatic) {
            Menu {
                ForEach(OrbitPreset.Category.allCases) { category in
                    Section(category.rawValue) {
                        ForEach(OrbitPreset.allCases.filter { $0.category == category }) { preset in
                            Button(preset.title) { store.choosePreset(preset.rawValue) }
                                .help(preset.summary)
                        }
                    }
                }
            } label: { Label("初始轨道", systemImage: "square.stack.3d.up") }
            .disabled(store.isComputing)
            Button { store.openProject() } label: { Label("打开", systemImage: "folder") }
            Button { Task { await store.saveProject() } } label: { Label("保存", systemImage: "square.and.arrow.down") }
                .disabled(store.isSaving)
        }
        ToolbarItem(placement: .primaryAction) {
            Button {
                if store.isComputing { store.pauseCalendar() }
                else if store.canResume { store.resumeCalendar() }
                else { store.startCalendar() }
            } label: {
                Label(store.isComputing ? "暂停计算" : store.canResume ? "继续计算" : "生成万年历",
                      systemImage: store.isComputing ? "pause.fill" : "sparkle")
            }.buttonStyle(.borderedProminent).tint(ObservatoryPalette.mint)
                .disabled(store.draft.planet == nil)
        }
        ToolbarItem {
            Button { showInspector.toggle() } label: { Label("参数检查器", systemImage: "sidebar.right") }
        }
    }

}

private struct WorkspaceStatusBar: View {
    let store: WorkspaceStore
    var body: some View {
        VStack(spacing: 0) {
            if store.isComputing { ProgressView(value: store.progress?.fraction ?? 0).progressViewStyle(.linear).tint(ObservatoryPalette.mint) }
            HStack(spacing: 8) {
                Circle().fill(store.isComputing ? ObservatoryPalette.mint : .secondary.opacity(0.5)).frame(width: 5, height: 5)
                Text(store.notice).lineLimit(1)
                Spacer()
                if let progress = store.progress {
                    Text("\(progress.completedYears.formatted()) / \(progress.requestedYears.formatted()) 年")
                        .monospacedDigit()
                }
                if store.hasUnsavedChanges { Text("· 未保存") }
            }.font(.system(size: 10)).foregroundStyle(.secondary).padding(.horizontal, 16).frame(height: 29)
        }.background(.bar)
    }
}

private struct SidebarView: View {
    @Bindable var store: WorkspaceStore
    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Image(systemName: "sun.max.circle.fill").font(.system(size: 30, weight: .light)).foregroundStyle(ObservatoryPalette.amber)
                VStack(alignment: .leading, spacing: 3) {
                    Text("三体观测站").font(.system(size: 15, weight: .semibold))
                    Text("TRISOLARIS").font(.system(size: 9, weight: .medium, design: .monospaced)).tracking(2).foregroundStyle(.secondary)
                }
                Spacer()
            }.padding(.horizontal, 18).padding(.vertical, 22)
            List(selection: $store.page) {
                Section("工作空间") {
                    ForEach(WorkspacePage.allCases) { page in Label(page.rawValue, systemImage: page.symbol).tag(page) }
                }
                Section("天体系统") {
                    ForEach(Array(store.draft.bodies.enumerated()), id: \.element.id) { index, body in
                        Button {
                            store.selectedBodyID = body.id.uuidString
                            store.page = .observatory
                        } label: {
                            HStack(spacing: 10) {
                                Circle().fill(ObservatoryPalette.bodyColors[index % 4]).frame(width: 9, height: 9)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(body.name).foregroundStyle(.primary).lineLimit(1)
                                    Text(body.kind == .star ? "\(body.massSolar.display(2)) M☉" : "\((body.massSolar / Astronomy.earthMassSolar).display(2)) M⊕")
                                        .font(.system(size: 10, design: .monospaced)).foregroundStyle(.secondary)
                                }
                                Spacer(minLength: 0)
                                if body.id.uuidString == store.selectedBodyID { Image(systemName: "scope").font(.system(size: 10)).foregroundStyle(.secondary) }
                            }.contentShape(Rectangle())
                        }.buttonStyle(.plain).padding(.vertical, 3)
                    }
                    Button { store.addOrRemovePlanet() } label: {
                        Label(store.draft.planet == nil ? "添加行星" : "移除行星", systemImage: store.draft.planet == nil ? "plus.circle" : "minus.circle")
                    }.buttonStyle(.plain).font(.system(size: 11)).foregroundStyle(.secondary).disabled(store.isComputing)
                }
            }.listStyle(.sidebar)
            VStack(alignment: .leading, spacing: 9) {
                Divider()
                Text("从三个太阳开始，\n写下一个世界的年历。").font(.system(size: 11)).foregroundStyle(.secondary).lineSpacing(5)
                HStack(spacing: 5) { Circle().fill(ObservatoryPalette.mint).frame(width: 4, height: 4); Text("IAS15 / 双精度积分") }
                    .font(.system(size: 9, design: .monospaced)).foregroundStyle(.tertiary)
            }.padding(18)
        }
    }
}
