import SwiftUI
import AppKit

@main
struct TrisolarisApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    var body: some Scene {
        WindowGroup("三体人的万年历", id: "workspace") { WorkspaceView() }
            .defaultSize(width: 1450, height: 900)
            .commands { ObservatoryCommands() }
        Settings { PreferencesView() }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        let unsaved = WorkspaceRegistry.shared.stores.filter(\.hasUnsavedChanges)
        guard !unsaved.isEmpty else { return .terminateNow }
        let alert = NSAlert()
        alert.messageText = "退出前保存项目？"
        alert.informativeText = "有 \(unsaved.count) 个项目包含尚未保存的修改或计算结果。"
        alert.addButton(withTitle: "保存并退出")
        alert.addButton(withTitle: "不保存")
        alert.addButton(withTitle: "取消")
        switch alert.runModal() {
        case .alertFirstButtonReturn:
            Task {
                for store in unsaved {
                    if !(await store.saveProject()) { sender.reply(toApplicationShouldTerminate: false); return }
                }
                sender.reply(toApplicationShouldTerminate: true)
            }
            return .terminateLater
        case .alertSecondButtonReturn: return .terminateNow
        default: return .terminateCancel
        }
    }
}

private struct WorkspaceStoreKey: FocusedValueKey { typealias Value = WorkspaceStore }
extension FocusedValues {
    var workspaceStore: WorkspaceStore? {
        get { self[WorkspaceStoreKey.self] }
        set { self[WorkspaceStoreKey.self] = newValue }
    }
}

struct ObservatoryCommands: Commands {
    @FocusedValue(\.workspaceStore) private var store
    var body: some Commands {
        CommandGroup(after: .newItem) {
            Button("打开项目…") { store?.openProject() }.keyboardShortcut("o").disabled(store?.isLoading == true)
            Button("关闭窗口") { NSApp.keyWindow?.performClose(nil) }.keyboardShortcut("w")
        }
        CommandGroup(replacing: .saveItem) {
            Button("保存项目") { Task { await store?.saveProject() } }.keyboardShortcut("s")
            Button("项目另存为…") { Task { await store?.saveProject(saveAs: true) } }.keyboardShortcut("s", modifiers: [.command, .shift])
            Divider()
            Button("导出纪元区间 CSV…") { store?.exportResult(asCSV: true) }.keyboardShortcut("e", modifiers: [.command, .shift]).disabled(store?.result == nil)
            Button("导出年度明细 CSV…") { store?.exportResult(asCSV: true, annualDetails: true) }.disabled(store?.result == nil)
            Button("导出完整结果 JSON…") { store?.exportResult(asCSV: false) }.disabled(store?.result == nil)
            Button("导出三维场景 PNG…") { store?.requestScenePNG() }
        }
        CommandMenu("模拟") {
            Button(store?.isPlaying == true ? "暂停观测" : "开始观测") { store?.togglePlayback() }.keyboardShortcut(.return, modifiers: [.command]).disabled(store?.isLoading == true || store?.isComputing == true)
            Button("单步推进") { store?.step() }.keyboardShortcut(".", modifiers: [.command])
            Button("回到初始状态") { Task { await store?.resetSimulation() } }.keyboardShortcut("r", modifiers: [.command])
            Divider()
            Button("生成万年历") { store?.startCalendar() }.keyboardShortcut("g", modifiers: [.command]).disabled(store?.isComputing == true)
            Button("暂停计算") { store?.pauseCalendar() }.disabled(store?.isComputing != true)
            Button("继续计算") { store?.resumeCalendar() }.disabled(store?.canResume != true)
            Button("取消计算") { store?.cancelCalendar() }.disabled(store?.isComputing != true && store?.canResume != true)
            Button("延长现有历法") { store?.extendCalendar() }.disabled(store?.result == nil || store?.isComputing == true)
            Divider()
            Button("严格精度复核") { store?.startCalendar(strict: true) }.disabled(store?.result == nil || store?.isComputing == true)
        }
        CommandMenu("视图") {
            ForEach(Array(WorkspacePage.allCases.enumerated()), id: \.element.id) { index, page in
                Toggle(page.rawValue, isOn: Binding(get: { store?.page == page }, set: { if $0 { store?.page = page } }))
                    .keyboardShortcut(KeyEquivalent(Character(String(index + 1))))
            }
            Divider()
            Button("重置三维视角") { store?.resetToken += 1 }.keyboardShortcut("0")
            Toggle("俯视轨道", isOn: Binding(get: { store?.topDown ?? false }, set: { store?.topDown = $0 })).keyboardShortcut("t", modifiers: [.command, .shift])
            Toggle("跟随所选天体", isOn: Binding(get: { store?.followSelected ?? false }, set: { store?.followSelected = $0 })).keyboardShortcut("f", modifiers: [.command, .shift])
        }
    }
}
