import AppKit
import SwiftUI

@MainActor
final class WorkspaceRegistry {
    static let shared = WorkspaceRegistry()
    private var entries: [ObjectIdentifier: WeakWorkspace] = [:]
    var stores: [WorkspaceStore] { entries.values.compactMap(\.value) }
    func add(_ store: WorkspaceStore, for window: NSWindow) { entries[ObjectIdentifier(window)] = WeakWorkspace(store) }
    func remove(_ window: NSWindow) { entries.removeValue(forKey: ObjectIdentifier(window)) }
}

@MainActor private final class WeakWorkspace {
    weak var value: WorkspaceStore?
    init(_ value: WorkspaceStore) { self.value = value }
}

struct WindowLifecycle: NSViewRepresentable {
    let store: WorkspaceStore
    func makeCoordinator() -> Coordinator { Coordinator(store: store) }
    func makeNSView(context: Context) -> TrackingView {
        let view = TrackingView()
        view.attached = { [weak coordinator = context.coordinator] window in coordinator?.attach(window) }
        return view
    }
    func updateNSView(_ nsView: TrackingView, context: Context) {}

    final class TrackingView: NSView {
        var attached: ((NSWindow) -> Void)?
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if let window { attached?(window) }
        }
    }

    @MainActor final class Coordinator: NSObject, NSWindowDelegate {
        let store: WorkspaceStore
        private var mayClose = false
        init(store: WorkspaceStore) { self.store = store }
        func attach(_ window: NSWindow) {
            window.delegate = self
            window.setFrameAutosaveName("TrisolarisWorkspace")
            WorkspaceRegistry.shared.add(store, for: window)
        }
        func windowShouldClose(_ sender: NSWindow) -> Bool {
            guard !mayClose, store.hasUnsavedChanges else { return true }
            let alert = NSAlert(); alert.messageText = "保存项目后关闭？"
            alert.informativeText = "当前参数和计算结果包含尚未保存的修改。"
            alert.addButton(withTitle: "保存"); alert.addButton(withTitle: "不保存"); alert.addButton(withTitle: "取消")
            switch alert.runModal() {
            case .alertFirstButtonReturn:
                Task { if await store.saveProject() { mayClose = true; sender.performClose(nil) } }
                return false
            case .alertSecondButtonReturn: return true
            default: return false
            }
        }
        func windowWillClose(_ notification: Notification) {
            store.shutdown()
            if let window = notification.object as? NSWindow { WorkspaceRegistry.shared.remove(window) }
        }
    }
}
