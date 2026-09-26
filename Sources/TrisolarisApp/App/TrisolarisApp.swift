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
            Button("打开项目…") { store?.openProject() }.keyboardShortcut("o")
        }
        CommandGroup(replacing: .saveItem) {
            Button("保存项目") { Task { await store?.saveProject() } }.keyboardShortcut("s")
            Button("项目另存为…") { Task { await store?.saveProject(saveAs: true) } }.keyboardShortcut("s", modifiers: [.command, .shift])
            Divider()
            Button("导出纪元区间 CSV…") { store?.exportResult(asCSV: true) }.disabled(store?.result == nil)
            Button("导出年度明细 CSV…") { store?.exportResult(asCSV: true, annualDetails: true) }.disabled(store?.result == nil)
            Button("导出完整结果 JSON…") { store?.exportResult(asCSV: false) }.disabled(store?.result == nil)
            Button("导出三维场景 PNG…") { store?.requestScenePNG() }
        }
        CommandMenu("模拟") {
            Button(store?.isPlaying == true ? "暂停观测" : "开始观测") { store?.togglePlayback() }
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
            ForEach(WorkspacePage.allCases) { page in Button(page.rawValue) { store?.page = page } }
            Divider()
            Button("重置三维视角") { store?.resetToken += 1 }
            Button("切换俯视") { store?.topDown.toggle() }
            Button("跟随所选天体") { store?.followSelected.toggle() }
        }
    }
}
