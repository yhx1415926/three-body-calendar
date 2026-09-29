import SwiftUI
import AppKit
import UniformTypeIdentifiers
import SimulationCore

struct ObservedSystemView: View {
    @Bindable var store: WorkspaceStore
    @Environment(\.dismiss) private var dismiss
    @State private var observations: [StellarObservation] = []
    @State private var filtered: [StellarObservation] = []
    @State private var component = "全部天体"
    @State private var kind = "全部测量"
    @State private var tablePage = 0
    @State private var issue: String?
    @State private var transferIssue: String?
    @State private var loading = true
    @State private var selection: String?
    @State private var includeExperimentalPlanet = true
    private let pageSize = 200
    private var pageCount: Int { max(1, (filtered.count+pageSize-1)/pageSize) }
    private var currentPage: Int { min(tablePage, pageCount-1) }
    private var visible: [StellarObservation] {
        let first = min(filtered.count, currentPage*pageSize)
        return Array(filtered[first..<min(filtered.count,first+pageSize)])
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                VStack(alignment: .leading, spacing: 5) {
                    Text("半人马座 α · 真实三星系统").font(.title2.weight(.medium))
                    Text("Alpha Centauri A · Alpha Centauri B · Proxima Centauri").font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Text("\(observations.count.formatted()) 条测量值").monospacedDigit().foregroundStyle(.secondary)
            }
            Text(AlphaCentauriCatalog.coverageSummary).font(.callout)
            HStack(spacing: 12) {
                Picker("天体", selection: $component) {
                    Text("全部天体").tag("全部天体")
                    ForEach(Array(Set(observations.map(\.component))).sorted(), id: \.self) { Text($0).tag($0) }
                }.frame(width: 215)
                Picker("测量", selection: $kind) {
                    Text("全部测量").tag("全部测量")
                    ForEach(StellarObservationKind.allCases, id: \.rawValue) { Text($0.rawValue).tag($0.rawValue) }
                }.frame(width: 230)
                Spacer()
                Menu("数据") {
                    Button("导入观测 CSV…", action: importCSV)
                    Button("导出当前筛选 CSV…", action: exportCSV).disabled(filtered.isEmpty)
                }.disabled(loading)
                if loading { ProgressView().controlSize(.small) }
            }
            if let issue {
                ContentUnavailableView("观测数据无法加载", systemImage: "exclamationmark.triangle", description: Text(issue))
            } else {
                Table(visible, selection: $selection) {
                    TableColumn("观测年份") { row in Text(row.epochJulianYear.formatted(.number.precision(.fractionLength(5)).grouping(.never))).monospacedDigit() }.width(105)
                    TableColumn("天体") { row in Text(row.component) }.width(95)
                    TableColumn("测量类型") { row in Text(row.kind.rawValue) }.width(125)
                    TableColumn("观测值") { row in Text(row.value.display(5)).monospacedDigit() }.width(110)
                    TableColumn("± 误差") { row in Text(row.uncertainty?.display(5) ?? "未提供").monospacedDigit() }.width(95)
                    TableColumn("单位") { row in Text(row.unit) }.width(55)
                }.frame(minHeight: 200)
            }
            HStack {
                Text("\(filtered.count.formatted()) 条 · 第 \(currentPage+1) / \(pageCount) 页").foregroundStyle(.secondary)
                Spacer()
                Button("上一页") { tablePage = max(0,currentPage-1) }.disabled(currentPage == 0)
                Button("下一页") { tablePage = min(pageCount-1,currentPage+1) }.disabled(currentPage+1 >= pageCount)
            }.font(.caption)
            if let selected = observations.first(where: { $0.id == selection }) {
                HStack(alignment: .top) {
                    Text(selected.detail).foregroundStyle(.secondary).textSelection(.enabled).lineLimit(3)
                    Spacer(minLength: 8)
                    if let url = sourceURL(for: selected) { Link("查看来源", destination: url) }
                }.font(.caption)
            }
            DisclosureGroup("数据来源与覆盖范围") {
                ScrollView {
                VStack(alignment: .leading, spacing: 7) {
                    ForEach(AlphaCentauriCatalog.sources, id: \.id) { source in
                        HStack(alignment: .top) {
                            Link(source.title, destination: source.url)
                            Text(source.coverage).foregroundStyle(.secondary)
                        }.font(.caption)
                    }
                    ForEach(AlphaCentauriCatalog.limitations, id: \.self) { Text($0).font(.caption).foregroundStyle(.secondary) }
                }.padding(.top, 6)
                }.frame(maxHeight: 130)
            }
            Divider()
            Text("三维模拟初值 · J1991.25 历元").font(.headline)
            Text(AlphaCentauriCatalog.modelSummary).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            Toggle("添加一颗实验行星，以便生成万年历", isOn: $includeExperimentalPlanet)
                .font(.caption)
            HStack {
                Text("恒星来自观测约束模型；实验行星为假设，不是观测数据。").font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button("关闭") { dismiss() }.keyboardShortcut(.cancelAction)
                Button(includeExperimentalPlanet ? "导入并生成可运行场景" : "只导入三星参数") {
                    store.replaceScenario(includeExperimentalPlanet ? AlphaCentauriCatalog.scenarioWithExperimentalPlanet() : AlphaCentauriCatalog.initialScenario())
                    dismiss()
                }.buttonStyle(.borderedProminent).keyboardShortcut(.defaultAction).disabled(loading || issue != nil || !store.canEditBodies)
            }
        }.padding(24).frame(width: 870, height: 700)
        .task {
            do {
                observations = try await ObservedSystemLibrary.shared.observations() + store.importedObservations
                applyFilter()
            } catch { issue = error.localizedDescription }
            loading = false
        }
        .onChange(of: component) { applyFilter() }
        .onChange(of: kind) { applyFilter() }
        .alert("观测数据", isPresented: Binding(get: { transferIssue != nil }, set: { if !$0 { transferIssue = nil } })) {
            Button("好") { transferIssue = nil }
        } message: { Text(transferIssue ?? "") }
    }
    private func sourceURL(for observation: StellarObservation) -> URL? {
        if let source = AlphaCentauriCatalog.sources.first(where: { $0.id == observation.sourceID }) { return source.url }
        guard let url = URL(string: observation.sourceID), ["https", "http"].contains(url.scheme) else { return nil }
        return url
    }
    private func importCSV() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.commaSeparatedText]; panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        loading = true
        Task {
            defer { loading = false }
            do {
                let rows = try await ObservedSystemLibrary.shared.importCSV(url)
                store.importedObservations.append(contentsOf: rows); store.edited()
                observations.append(contentsOf: rows); issue = nil; applyFilter()
            } catch { transferIssue = error.localizedDescription }
        }
    }
    private func exportCSV() {
        let panel = NSSavePanel(); panel.allowedContentTypes = [.commaSeparatedText]
        panel.nameFieldStringValue = "半人马座α-观测记录.csv"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        let rows = filtered
        Task {
            do { try await ObservedSystemLibrary.shared.exportCSV(rows, to: url) }
            catch { transferIssue = error.localizedDescription }
        }
    }
    private func applyFilter() {
        observations.sort { $0.epochJulianYear < $1.epochJulianYear }
        filtered = observations.filter { (component == "全部天体" || $0.component == component) && (kind == "全部测量" || $0.kind.rawValue == kind) }
        tablePage = 0; selection = nil
    }
}
