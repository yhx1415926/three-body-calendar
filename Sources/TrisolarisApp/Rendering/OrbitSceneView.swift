import AppKit
import MetalKit
import SwiftUI

/// Positions and radii use the same physical unit; the renderer never changes the simulation.
public struct RenderBody: Identifiable, Equatable, Sendable {
    public var id: String
    public var name: String
    public var position: SIMD3<Double>
    public var radius: Double
    public var color: SIMD3<Float>
    public var isStar: Bool

    public init(id: String, name: String, position: SIMD3<Double>, radius: Double,
                color: SIMD3<Float>, isStar: Bool) {
        self.id = id
        self.name = name
        self.position = position
        self.radius = radius
        self.color = color
        self.isStar = isStar
    }
}

public struct OrbitSceneFrame: Equatable, Sendable {
    public var time: Double
    public var bodies: [RenderBody]

    public init(time: Double = 0, bodies: [RenderBody] = []) {
        self.time = time
        self.bodies = bodies
    }
}

public enum OrbitInteractionMode: String, CaseIterable, Identifiable, Sendable {
    case navigate, moveBodies
    public var id: Self { self }
    public var title: String { self == .navigate ? "观察" : "移动天体" }
    public var symbolName: String { self == .navigate ? "hand.draw" : "cursorarrow" }
    public var help: String {
        self == .navigate ? "拖动旋转，Shift 或右键拖动平移，滚动缩放。" :
            "拖动天体调整初始位置，保持屏幕深度；Esc 取消。拖动空白旋转，Shift 或右键拖动平移。"
    }
}

public enum OrbitBodyMovePhase: Equatable, Sendable {
    case began, changed, ended, cancelled
}

/// SwiftUI owns the draft positions; AppKit reports a bounded editing gesture.
@MainActor
public struct OrbitSceneView: View {
    public var frame: OrbitSceneFrame
    public var trails: [String: [SIMD3<Double>]]
    @Binding public var selectedID: String?
    public var followSelected: Bool
    public var topDown: Bool
    public var showGrid: Bool
    public var exaggeratedSizes: Bool
    public var resetToken: Int
    public var captureToken: Int
    public var onCapture: ((Data) -> Void)?
    public var interactionMode: OrbitInteractionMode
    public var onMoveBody: ((String, SIMD3<Double>, OrbitBodyMovePhase) -> Void)?

    public init(frame: OrbitSceneFrame, trails: [String: [SIMD3<Double>]] = [:],
                selectedID: Binding<String?>, followSelected: Bool = false,
                topDown: Bool = false, showGrid: Bool = true,
                exaggeratedSizes: Bool = true, resetToken: Int = 0,
                captureToken: Int = 0, onCapture: ((Data) -> Void)? = nil,
                interactionMode: OrbitInteractionMode = .navigate,
                onMoveBody: ((String, SIMD3<Double>, OrbitBodyMovePhase) -> Void)? = nil) {
        self.frame = frame
        self.trails = trails
        self._selectedID = selectedID
        self.followSelected = followSelected
        self.topDown = topDown
        self.showGrid = showGrid
        self.exaggeratedSizes = exaggeratedSizes
        self.resetToken = resetToken
        self.captureToken = captureToken
        self.onCapture = onCapture
        self.interactionMode = interactionMode
        self.onMoveBody = onMoveBody
    }

    public var body: some View {
        OrbitMetalRepresentable(scene: self)
            .accessibilityLabel("三维恒星轨道")
            .accessibilityHint(interactionMode.help)
    }
}

@MainActor
private struct OrbitMetalRepresentable: NSViewRepresentable {
    var scene: OrbitSceneView

    func makeNSView(context: Context) -> OrbitMetalView {
        let view = OrbitMetalView()
        updateNSView(view, context: context)
        return view
    }

    func updateNSView(_ view: OrbitMetalView, context: Context) {
        view.interactionMode = scene.interactionMode
        view.onMoveBody = scene.onMoveBody
        view.renderer?.update(frame: scene.frame, trails: scene.trails,
                              selectedID: scene.selectedID, followSelected: scene.followSelected,
                              topDown: scene.topDown, showGrid: scene.showGrid,
                              exaggeratedSizes: scene.exaggeratedSizes, resetToken: scene.resetToken)
        view.onSelect = { scene.selectedID = $0 }
        view.renderer?.requestCapture(token: scene.captureToken, onCapture: scene.onCapture)
        view.needsDisplay = true
    }

    static func dismantleNSView(_ view: OrbitMetalView, coordinator: ()) {
        view.cancelBodyDrag()
        view.isPaused = true
        view.delegate = nil
        view.onSelect = nil
        view.onMoveBody = nil
    }
}

@MainActor
final class OrbitMetalView: MTKView {
    var renderer: OrbitRenderer?
    var onSelect: ((String?) -> Void)?
    var onMoveBody: ((String, SIMD3<Double>, OrbitBodyMovePhase) -> Void)?
    var interactionMode: OrbitInteractionMode = .navigate {
        didSet {
            guard oldValue != interactionMode else { return }
            cancelBodyDrag()
            window?.invalidateCursorRects(for: self)
            setAccessibilityHelp(interactionMode.help)
        }
    }
    private var dragOrigin = NSPoint.zero
    private var hasDragged = false
    private var bodyDrag: OrbitDragCandidate?
    private var isMovingBody = false
    private var draggedPosition: SIMD3<Double>?
    private var ignoresMouseUntilUp = false
    private var tracking: NSTrackingArea?
    private var drawableResizeTask: Task<Void, Never>?

    init() {
        let metalDevice = MTLCreateSystemDefaultDevice()
        super.init(frame: .zero, device: metalDevice)
        colorPixelFormat = .bgra8Unorm
        depthStencilPixelFormat = .depth32Float
        sampleCount = metalDevice?.supportsTextureSampleCount(4) == true ? 4 : 1
        clearColor = MTLClearColor(red: 0.018, green: 0.024, blue: 0.057, alpha: 1)
        isPaused = true
        enableSetNeedsDisplay = true
        preferredFramesPerSecond = 60
        // SwiftUI sidebar transitions can resize the view on every animation
        // frame. Coalesce texture reallocations while the layer scales smoothly.
        autoResizeDrawable = false
        framebufferOnly = false
        setAccessibilityRole(.group)
        setAccessibilityLabel("三维轨道视图")
        setAccessibilityHelp("方向键旋转，正负键缩放，0 键复位，Tab 键选择天体。")
        do {
            renderer = try OrbitRenderer(view: self)
            delegate = renderer
        } catch {
            let message = NSTextField(wrappingLabelWithString: "无法启动三维视图\n\(error.localizedDescription)")
            message.textColor = .secondaryLabelColor
            message.alignment = .center
            message.translatesAutoresizingMaskIntoConstraints = false
            addSubview(message)
            NSLayoutConstraint.activate([
                message.centerXAnchor.constraint(equalTo: centerXAnchor),
                message.centerYAnchor.constraint(equalTo: centerYAnchor),
                message.widthAnchor.constraint(lessThanOrEqualTo: widthAnchor, constant: -40)
            ])
        }
    }

    required init(coder: NSCoder) { fatalError("Use init()") }
    override var acceptsFirstResponder: Bool { true }

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        scheduleDrawableResize()
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        updateDrawableSize()
    }

    override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        updateDrawableSize()
    }

    private func scheduleDrawableResize() {
        needsDisplay = true
        guard drawableResizeTask == nil else { return }
        drawableResizeTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(40))
            guard let self, !Task.isCancelled else { return }
            self.drawableResizeTask = nil
            self.updateDrawableSize()
        }
    }

    private func updateDrawableSize() {
        let backingSize = convertToBacking(bounds).size
        let target = CGSize(width: max(1, backingSize.width.rounded(.up)), height: max(1, backingSize.height.rounded(.up)))
        if drawableSize != target { drawableSize = target }
        needsDisplay = true
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let tracking { removeTrackingArea(tracking) }
        let area = NSTrackingArea(rect: .zero, options: [.activeInKeyWindow, .inVisibleRect, .cursorUpdate],
                                  owner: self, userInfo: nil)
        addTrackingArea(area)
        tracking = area
    }

    private var restingCursor: NSCursor { interactionMode == .navigate ? .openHand : .arrow }
    override func cursorUpdate(with event: NSEvent) {
        (hasDragged && !isMovingBody ? NSCursor.closedHand : restingCursor).set()
    }

    override func resetCursorRects() { addCursorRect(bounds, cursor: restingCursor) }

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        dragOrigin = convert(event.locationInWindow, from: nil)
        hasDragged = false
        ignoresMouseUntilUp = false
        bodyDrag = interactionMode == .moveBodies && onMoveBody != nil && !event.modifierFlags.contains(.shift)
            ? renderer?.dragCandidate(at: dragOrigin, in: bounds.size) : nil
    }

    override func mouseDragged(with event: NSEvent) {
        guard !ignoresMouseUntilUp else { return }
        let point = convert(event.locationInWindow, from: nil)
        if hypot(point.x - dragOrigin.x, point.y - dragOrigin.y) > 3 { hasDragged = true }
        guard hasDragged else { return }
        if let candidate = bodyDrag {
            if !isMovingBody {
                isMovingBody = true
                draggedPosition = candidate.geometry.originalPosition
                renderer?.beginBodyDrag(candidate)
                onSelect?(candidate.id)
                onMoveBody?(candidate.id, candidate.geometry.originalPosition, .began)
            }
            guard let position = candidate.geometry.position(at: point) else { return }
            draggedPosition = position
            renderer?.previewBodyDrag(id: candidate.id, position: position)
            onMoveBody?(candidate.id, position, .changed)
            NSCursor.arrow.set()
            needsDisplay = true
            return
        }
        NSCursor.closedHand.set()
        if event.modifierFlags.contains(.shift) {
            renderer?.pan(deltaX: event.deltaX, deltaY: event.deltaY, height: bounds.height)
        } else {
            renderer?.rotate(deltaX: event.deltaX, deltaY: event.deltaY)
        }
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        if ignoresMouseUntilUp { ignoresMouseUntilUp = false; return }
        if isMovingBody, let candidate = bodyDrag {
            let position = candidate.geometry.position(at: convert(event.locationInWindow, from: nil))
                ?? draggedPosition ?? candidate.geometry.originalPosition
            finishBodyDrag(position: position, phase: .ended)
            return
        }
        if !hasDragged {
            onSelect?(renderer?.body(at: convert(event.locationInWindow, from: nil), in: bounds.size))
        }
        bodyDrag = nil
        hasDragged = false
        restingCursor.set()
    }

    func cancelBodyDrag() {
        if isMovingBody, let candidate = bodyDrag {
            ignoresMouseUntilUp = true
            finishBodyDrag(position: candidate.geometry.originalPosition, phase: .cancelled)
        } else { bodyDrag = nil }
    }

    private func finishBodyDrag(position: SIMD3<Double>, phase: OrbitBodyMovePhase) {
        guard let candidate = bodyDrag else { return }
        bodyDrag = nil
        isMovingBody = false
        hasDragged = false
        draggedPosition = nil
        renderer?.previewBodyDrag(id: candidate.id, position: position)
        renderer?.endBodyDrag()
        onMoveBody?(candidate.id, position, phase)
        restingCursor.set()
        needsDisplay = true
    }

    override func resignFirstResponder() -> Bool {
        cancelBodyDrag()
        return super.resignFirstResponder()
    }

    override func rightMouseDown(with event: NSEvent) { window?.makeFirstResponder(self) }
    override func rightMouseDragged(with event: NSEvent) {
        guard !isMovingBody else { return }
        NSCursor.closedHand.set()
        renderer?.pan(deltaX: event.deltaX, deltaY: event.deltaY, height: bounds.height)
        needsDisplay = true
    }
    override func rightMouseUp(with event: NSEvent) { restingCursor.set() }

    override func otherMouseDragged(with event: NSEvent) { rightMouseDragged(with: event) }

    override func scrollWheel(with event: NSEvent) {
        guard !isMovingBody else { return }
        let scale = event.hasPreciseScrollingDeltas ? 0.012 : 0.09
        renderer?.zoom(logDelta: Double(event.scrollingDeltaY) * scale)
        needsDisplay = true
    }

    override func magnify(with event: NSEvent) {
        guard !isMovingBody else { return }
        renderer?.zoom(logDelta: -Double(event.magnification) * 2.0)
        needsDisplay = true
    }

    override func keyDown(with event: NSEvent) {
        if event.modifierFlags.contains(.command) { super.keyDown(with: event); return }
        if isMovingBody {
            if event.keyCode == 53 { cancelBodyDrag() }
            return
        }
        switch event.keyCode {
        case 123: renderer?.rotate(deltaX: -12, deltaY: 0)
        case 124: renderer?.rotate(deltaX: 12, deltaY: 0)
        case 125: renderer?.rotate(deltaX: 0, deltaY: 12)
        case 126: renderer?.rotate(deltaX: 0, deltaY: -12)
        case 53: onSelect?(nil)
        case 48:
            if let renderer { onSelect?(renderer.nextSelection(reverse: event.modifierFlags.contains(.shift))) }
        default:
            switch event.charactersIgnoringModifiers {
            case "+", "=": renderer?.zoom(logDelta: -0.15)
            case "-", "_": renderer?.zoom(logDelta: 0.15)
            case "0": renderer?.resetCamera()
            default: super.keyDown(with: event); return
            }
        }
        needsDisplay = true
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        bounds.contains(convert(point, from: superview)) ? self : nil
    }
}
