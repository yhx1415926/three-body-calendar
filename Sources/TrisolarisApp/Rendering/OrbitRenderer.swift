import AppKit
import CoreGraphics
@preconcurrency import MetalKit
import simd

private struct OrbitGPUUniforms {
    var viewProjection: simd_float4x4
    var view: simd_float4x4
    var projection: simd_float4x4
    var viewport: SIMD4<Float>
}

private struct OrbitLineVertex {
    var position: SIMD4<Float>
    var color: SIMD4<Float>
}

private struct OrbitBodyInstance {
    var centerRadius: SIMD4<Float>
    var colorKind: SIMD4<Float>
    var lightSelected: SIMD4<Float>
}

private enum OrbitRenderingError: LocalizedError {
    case unavailable
    case initialization(String)
    var errorDescription: String? {
        switch self {
        case .unavailable: return "此 Mac 未提供可用的 Metal 图形设备。"
        case .initialization(let reason): return reason
        }
    }
}

@MainActor
final class OrbitRenderer: NSObject, MTKViewDelegate {
    private let device: MTLDevice
    private let commandQueue: MTLCommandQueue
    private let backgroundPipeline: MTLRenderPipelineState
    private let linePipeline: MTLRenderPipelineState
    private let spherePipeline: MTLRenderPipelineState
    private let haloPipeline: MTLRenderPipelineState
    private let selectionPipeline: MTLRenderPipelineState
    private let depthWrite: MTLDepthStencilState
    private let depthRead: MTLDepthStencilState
    private let depthAlways: MTLDepthStencilState
    private weak var view: OrbitMetalView?
    private var frame = OrbitSceneFrame()
    private var trails: [String: [SIMD3<Double>]] = [:]
    private var selectedID: String?
    private var followsSelection = false
    private var showGrid = true
    private var exaggeratedSizes = true
    private var resetToken: Int?
    private var camera = OrbitCamera()
    private var hasFramed = false
    private var captureToken = 0
    private var capturePending = false
    private let inFlightFrames = DispatchSemaphore(value: 2)
    private var redrawAfterGPU = false
    private var geometryDirty = true
    private var lineBuffer: MTLBuffer?
    private var lineVertexCount = 0
    private var bodyBuffer: MTLBuffer?
    private var bodyInstanceCount = 0
    private var cachedCenter = SIMD3<Double>(repeating: .infinity)
    private var cachedScale = Double.infinity
    private var cachedDistance = Double.infinity
    var onCapture: ((Data) -> Void)?

    init(view: OrbitMetalView) throws {
        guard let device = view.device, let queue = device.makeCommandQueue() else {
            throw OrbitRenderingError.unavailable
        }
        self.device = device
        self.commandQueue = queue
        self.view = view
        let options = MTLCompileOptions()
        if #available(macOS 15, *) { options.mathMode = .safe }
        else { options.fastMathEnabled = false }
        let library = try device.makeLibrary(source: OrbitShaders.source, options: options)
        func pipeline(_ vertex: String, _ fragment: String, additive: Bool = false) throws -> MTLRenderPipelineState {
            let descriptor = MTLRenderPipelineDescriptor()
            descriptor.label = "Orbit \(vertex)"
            descriptor.vertexFunction = library.makeFunction(name: vertex)
            descriptor.fragmentFunction = library.makeFunction(name: fragment)
            descriptor.colorAttachments[0].pixelFormat = view.colorPixelFormat
            descriptor.depthAttachmentPixelFormat = view.depthStencilPixelFormat
            descriptor.rasterSampleCount = view.sampleCount
            let attachment = descriptor.colorAttachments[0]!
            attachment.isBlendingEnabled = true
            attachment.rgbBlendOperation = .add
            attachment.alphaBlendOperation = .add
            attachment.sourceRGBBlendFactor = .sourceAlpha
            attachment.destinationRGBBlendFactor = additive ? .one : .oneMinusSourceAlpha
            attachment.sourceAlphaBlendFactor = .one
            attachment.destinationAlphaBlendFactor = .oneMinusSourceAlpha
            return try device.makeRenderPipelineState(descriptor: descriptor)
        }
        backgroundPipeline = try pipeline("background_vertex", "background_fragment")
        linePipeline = try pipeline("line_vertex", "line_fragment")
        spherePipeline = try pipeline("sphere_vertex", "sphere_fragment")
        haloPipeline = try pipeline("halo_vertex", "halo_fragment", additive: true)
        selectionPipeline = try pipeline("selection_vertex", "selection_fragment")
        func depth(_ compare: MTLCompareFunction, write: Bool) throws -> MTLDepthStencilState {
            let descriptor = MTLDepthStencilDescriptor()
            descriptor.depthCompareFunction = compare
            descriptor.isDepthWriteEnabled = write
            guard let state = device.makeDepthStencilState(descriptor: descriptor) else {
                throw OrbitRenderingError.initialization("无法创建深度缓冲。")
            }
            return state
        }
        depthWrite = try depth(.lessEqual, write: true)
        depthRead = try depth(.lessEqual, write: false)
        depthAlways = try depth(.always, write: false)
        super.init()
    }

    func update(frame: OrbitSceneFrame, trails: [String: [SIMD3<Double>]], selectedID: String?,
                followSelected: Bool, topDown: Bool, showGrid: Bool,
                exaggeratedSizes: Bool, resetToken: Int) {
        let changedFollow = self.selectedID != selectedID || followsSelection != followSelected
        let filteredFrame = OrbitSceneFrame(time: frame.time, bodies: frame.bodies.filter {
            $0.position.isRenderable && $0.radius.isFinite && $0.radius >= 0
        })
        if self.frame != filteredFrame || self.trails != trails || self.selectedID != selectedID ||
            self.showGrid != showGrid || self.exaggeratedSizes != exaggeratedSizes {
            geometryDirty = true
        }
        self.frame = filteredFrame
        self.trails = trails
        self.selectedID = selectedID
        self.followsSelection = followSelected
        self.showGrid = showGrid
        self.exaggeratedSizes = exaggeratedSizes
        camera.topDown = topDown
        if (!hasFramed && !self.frame.bodies.isEmpty) || self.resetToken != resetToken {
            resetCamera()
        }
        self.resetToken = resetToken
        if followSelected, let body = self.frame.bodies.first(where: { $0.id == selectedID }) {
            camera.target = body.position
            if changedFollow {
                camera.panOffset = .zero
                let nearest = self.frame.bodies.filter { $0.id != body.id }.map { simd_length($0.position-body.position) }.min() ?? 1
                camera.scale = max(nearest*1.5,body.radius*20,0.001)
                camera.distance = camera.scale*3.5
            }
        }
    }

    func requestCapture(token: Int, onCapture: ((Data) -> Void)?) {
        self.onCapture = onCapture
        if token != captureToken { capturePending = onCapture != nil }
        captureToken = token
    }

    func resetCamera() {
        camera.fit(frame.bodies)
        hasFramed = !frame.bodies.isEmpty
        if followsSelection, let body = frame.bodies.first(where: { $0.id == selectedID }) {
            camera.target = body.position
        }
    }

    func rotate(deltaX: Double, deltaY: Double) { camera.rotate(deltaX: deltaX, deltaY: deltaY) }
    func pan(deltaX: Double, deltaY: Double, height: Double) { camera.pan(deltaX: deltaX, deltaY: deltaY, height: height) }
    func zoom(logDelta: Double) { camera.zoom(logDelta: logDelta) }

    func nextSelection(reverse: Bool) -> String? {
        guard !frame.bodies.isEmpty else { return nil }
        let current = frame.bodies.firstIndex { $0.id == selectedID } ?? (reverse ? 0 : -1)
        return frame.bodies[(current + (reverse ? -1 : 1) + frame.bodies.count) % frame.bodies.count].id
    }

    func body(at point: CGPoint, in size: CGSize) -> String? {
        projectedBodies(size: size).filter {
            hypot($0.point.x - point.x, $0.point.y - point.y) <= max($0.radius + 5, 11)
        }.sorted {
            if abs($0.depth - $1.depth) > 0.00001 { return $0.depth < $1.depth }
            return hypot($0.point.x - point.x, $0.point.y - point.y) < hypot($1.point.x - point.x, $1.point.y - point.y)
        }.first?.id
    }

    private func displayRadius(_ body: RenderBody) -> Double {
        guard exaggeratedSizes else { return body.radius }
        let nearest = frame.bodies.filter { $0.id != body.id }.map { simd_length($0.position-body.position) }.min() ?? camera.scale
        return max(body.radius, min(nearest*0.20, camera.scale * (body.isStar ? 0.025 : 0.011)))
    }

    private func projectedBodies(size: CGSize) -> [OrbitProjectedBody] {
        let snapshot = camera.snapshot(size: size)
        return frame.bodies.compactMap { body in
            guard let p = snapshot.projected(position: body.position, radius: displayRadius(body)) else { return nil }
            return OrbitProjectedBody(id: body.id, name: body.name, point: p.point, radius: p.radius,
                                      depth: p.depth, color: body.color, isSelected: body.id == selectedID)
        }
    }

    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) { view.needsDisplay = true }

    func draw(in metalView: MTKView) {
        // Never wait for the GPU on the AppKit thread during sidebar animations.
        guard inFlightFrames.wait(timeout: .now()) == .success else {
            redrawAfterGPU = true
            return
        }
        guard metalView.drawableSize.width > 0, metalView.drawableSize.height > 0,
              let drawable = metalView.currentDrawable,
              let descriptor = metalView.currentRenderPassDescriptor,
              let command = commandQueue.makeCommandBuffer(),
              let encoder = command.makeRenderCommandEncoder(descriptor: descriptor) else {
            inFlightFrames.signal()
            return
        }
        let snapshot = camera.snapshot(size: metalView.bounds.size)
        let backingScale = Float(metalView.drawableSize.width / max(metalView.bounds.width, 1))
        var uniforms = OrbitGPUUniforms(viewProjection: snapshot.viewProjection, view: snapshot.view,
                                       projection: snapshot.projection,
                                       viewport: SIMD4(Float(metalView.drawableSize.width),
                                                       Float(metalView.drawableSize.height), backingScale,
                                                       Float(frame.time.truncatingRemainder(dividingBy: 10_000))))
        encoder.label = "Three-body orbital scene"
        encoder.setVertexBytes(&uniforms, length: MemoryLayout<OrbitGPUUniforms>.stride, index: 1)
        encoder.setFragmentBytes(&uniforms, length: MemoryLayout<OrbitGPUUniforms>.stride, index: 1)
        encoder.setDepthStencilState(depthAlways)
        encoder.setRenderPipelineState(backgroundPipeline)
        encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
        encoder.setDepthStencilState(depthRead)

        if geometryDirty || cachedCenter != snapshot.center || cachedScale != snapshot.scale || cachedDistance != camera.distance {
            let lines = makeLines(snapshot: snapshot)
            lineBuffer = makeBuffer(lines)
            lineVertexCount = lines.count
            let bodies = makeBodies(snapshot: snapshot)
            bodyBuffer = makeBuffer(bodies)
            bodyInstanceCount = bodies.count
            cachedCenter = snapshot.center
            cachedScale = snapshot.scale
            cachedDistance = camera.distance
            geometryDirty = false
        }
        if lineVertexCount > 0, let buffer = lineBuffer {
            encoder.setRenderPipelineState(linePipeline)
            encoder.setVertexBuffer(buffer, offset: 0, index: 0)
            encoder.drawPrimitives(type: .line, vertexStart: 0, vertexCount: lineVertexCount)
        }

        if bodyInstanceCount > 0, let buffer = bodyBuffer {
            encoder.setVertexBuffer(buffer, offset: 0, index: 0)
            encoder.setRenderPipelineState(haloPipeline)
            encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 6, instanceCount: bodyInstanceCount)
            encoder.setDepthStencilState(depthWrite)
            encoder.setRenderPipelineState(spherePipeline)
            encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 6, instanceCount: bodyInstanceCount)
            encoder.setDepthStencilState(depthAlways)
            encoder.setRenderPipelineState(selectionPipeline)
            encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 6, instanceCount: bodyInstanceCount)
        }
        encoder.endEncoding()
        if capturePending { encodeCapture(texture: drawable.texture, command: command) }
        let completionSignal = inFlightFrames
        command.addCompletedHandler { [weak self] _ in
            completionSignal.signal()
            Task { @MainActor [weak self] in
                guard let self, self.redrawAfterGPU else { return }
                self.redrawAfterGPU = false
                self.view?.needsDisplay = true
            }
        }
        command.present(drawable)
        command.commit()
        view?.updateLabels(projectedBodies(size: metalView.bounds.size))
    }

    private func makeBuffer<T>(_ data: [T]) -> MTLBuffer? {
        data.withUnsafeBytes { bytes in
            guard let base = bytes.baseAddress else { return nil }
            return device.makeBuffer(bytes: base, length: bytes.count, options: .storageModeShared)
        }
    }

    private func makeBodies(snapshot: OrbitCameraSnapshot) -> [OrbitBodyInstance] {
        frame.bodies.map { body in
            let position = snapshot.normalized(body.position)
            let closestStar = frame.bodies.filter { $0.isStar && $0.id != body.id }.min {
                simd_length_squared($0.position - body.position) < simd_length_squared($1.position - body.position)
            }
            let direction = closestStar.map { simd_normalize($0.position - body.position) } ?? SIMD3(0.3, -0.5, 1)
            let light = direction.isRenderable ? SIMD3<Float>(direction) : SIMD3<Float>(0.3, -0.5, 1)
            return OrbitBodyInstance(centerRadius: SIMD4(position, Float(displayRadius(body) / camera.scale)),
                                     colorKind: SIMD4(body.color, body.isStar ? 1 : 0),
                                     lightSelected: SIMD4(light, body.id == selectedID ? 1 : 0))
        }
    }

    private func makeLines(snapshot: OrbitCameraSnapshot) -> [OrbitLineVertex] {
        var vertices: [OrbitLineVertex] = []
        vertices.reserveCapacity(20_000)
        func append(_ a: SIMD3<Double>, _ b: SIMD3<Double>, colorA: SIMD4<Float>, colorB: SIMD4<Float>) {
            guard a.isRenderable, b.isRenderable else { return }
            let pa = snapshot.normalized(a)
            let pb = snapshot.normalized(b)
            guard simd_length_squared(pa) < 1e20, simd_length_squared(pb) < 1e20 else { return }
            vertices.append(OrbitLineVertex(position: SIMD4(pa, 1), color: colorA))
            vertices.append(OrbitLineVertex(position: SIMD4(pb, 1), color: colorB))
        }
        if showGrid {
            let desired = camera.distance / 8
            let base = pow(10, floor(log10(max(desired, 1e-20))))
            let ratio = desired / base
            let step = base * (ratio < 2 ? 1 : (ratio < 5 ? 2 : 5))
            let originX = floor(camera.center.x / step) * step
            let originY = floor(camera.center.y / step) * step
            let count = 14
            let extent = Double(count) * step
            for i in -count...count {
                let x = originX + Double(i) * step
                let y = originY + Double(i) * step
                let fade = Float(1 - abs(Double(i)) / Double(count + 1))
                let regular = SIMD4<Float>(0.25, 0.40, 0.56, 0.13 * fade)
                let xColor = abs(x) < step * 1e-6 ? SIMD4<Float>(0.32, 0.56, 0.68, 0.27) : regular
                let yColor = abs(y) < step * 1e-6 ? SIMD4<Float>(0.42, 0.47, 0.69, 0.27) : regular
                append(SIMD3(x, originY - extent, 0), SIMD3(x, originY + extent, 0), colorA: xColor, colorB: xColor)
                append(SIMD3(originX - extent, y, 0), SIMD3(originX + extent, y, 0), colorA: yColor, colorB: yColor)
            }
        }
        for body in frame.bodies {
            guard let trail = trails[body.id], trail.count > 1 else { continue }
            let strideSize = max(1, Int(ceil(Double(trail.count) / 4_096)))
            var indices = Array(stride(from: 0, to: trail.count, by: strideSize))
            if indices.last != trail.count - 1 { indices.append(trail.count - 1) }
            for index in 1..<indices.count {
                let previous = indices[index - 1]
                let next = indices[index]
                let a = Float(previous) / Float(trail.count - 1)
                let b = Float(next) / Float(trail.count - 1)
                let opacity: Float = body.id == selectedID ? 0.88 : 0.64
                append(trail[previous], trail[next], colorA: SIMD4(body.color, (0.08 + 0.92 * a) * opacity),
                       colorB: SIMD4(body.color, (0.08 + 0.92 * b) * opacity))
            }
        }
        return vertices
    }

    private func encodeCapture(texture: MTLTexture, command: MTLCommandBuffer) {
        let width = texture.width
        let height = texture.height
        let bytesPerRow = (width * 4 + 255) & ~255
        guard let buffer = device.makeBuffer(length: bytesPerRow * height, options: .storageModeShared),
              let blit = command.makeBlitCommandEncoder() else { return }
        blit.copy(from: texture, sourceSlice: 0, sourceLevel: 0, sourceOrigin: MTLOrigin(x: 0, y: 0, z: 0),
                  sourceSize: MTLSize(width: width, height: height, depth: 1), to: buffer,
                  destinationOffset: 0, destinationBytesPerRow: bytesPerRow,
                  destinationBytesPerImage: bytesPerRow * height)
        blit.endEncoding()
        capturePending = false
        let capturedBuffer = SendableMetalBuffer(buffer)
        command.addCompletedHandler { [weak self] completed in
            guard completed.status == .completed else { return }
            let pixels = Data(bytes: capturedBuffer.value.contents(), count: bytesPerRow * height)
            Task { @MainActor [weak self] in
                guard let provider = CGDataProvider(data: pixels as CFData),
                      let cgImage = CGImage(width: width, height: height, bitsPerComponent: 8,
                                            bitsPerPixel: 32, bytesPerRow: bytesPerRow,
                                            space: CGColorSpaceCreateDeviceRGB(),
                                            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedFirst.rawValue)
                                                .union(.byteOrder32Little), provider: provider,
                                            decode: nil, shouldInterpolate: false, intent: .defaultIntent),
                      let png = NSBitmapImageRep(cgImage: cgImage).representation(using: .png, properties: [:]) else { return }
                self?.onCapture?(png)
            }
        }
    }
}

/// The buffer is only read after its command buffer completes; ownership is retained for that callback.
private struct SendableMetalBuffer: @unchecked Sendable { let value: MTLBuffer; init(_ value: MTLBuffer) { self.value = value } }
