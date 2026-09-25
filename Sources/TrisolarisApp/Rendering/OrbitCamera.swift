import AppKit
import simd

struct OrbitCamera {
    var target = SIMD3<Double>.zero
    var panOffset = SIMD3<Double>.zero
    var scale: Double = 1
    var distance: Double = 4
    var yaw: Double = -0.38
    var pitch: Double = 0.66
    var topDown = false
    let fieldOfView: Double = 43 * .pi / 180

    var center: SIMD3<Double> { target + panOffset }

    var basis: (right: SIMD3<Double>, up: SIMD3<Double>, forward: SIMD3<Double>) {
        if topDown { return (SIMD3(1, 0, 0), SIMD3(0, 1, 0), SIMD3(0, 0, -1)) }
        let offset = SIMD3(sin(yaw) * cos(pitch), -cos(yaw) * cos(pitch), sin(pitch))
        let forward = -simd_normalize(offset)
        let right = simd_normalize(simd_cross(forward, SIMD3(0, 0, 1)))
        return (right, simd_cross(right, forward), forward)
    }

    mutating func fit(_ bodies: [RenderBody]) {
        let positions = bodies.map(\.position).filter(\.isRenderable)
        guard !positions.isEmpty else { return }
        target = positions.reduce(.zero) { $0 + $1 / Double(positions.count) }
        panOffset = .zero
        let extent = positions.map { simd_length($0 - target) }.max() ?? 1
        let bodyExtent = bodies.map { max($0.radius, 0) }.max() ?? 0
        scale = max(extent * 1.2, bodyExtent * 5, 0.001)
        distance = scale * 3.5
        yaw = -0.38
        pitch = 0.66
    }

    mutating func rotate(deltaX: Double, deltaY: Double) {
        guard !topDown else { return }
        yaw -= deltaX * 0.007
        pitch = min(max(pitch + deltaY * 0.007, -.pi / 2 + 0.025), .pi / 2 - 0.025)
    }

    mutating func pan(deltaX: Double, deltaY: Double, height: Double) {
        let unitsPerPoint = 2 * distance * tan(fieldOfView / 2) / max(height, 1)
        let axes = basis
        panOffset += (-axes.right * deltaX + axes.up * deltaY) * unitsPerPoint
    }

    mutating func zoom(logDelta: Double) {
        distance = min(max(distance * exp(min(max(logDelta, -1), 1)), scale * 0.002), scale * 100_000)
    }

    func snapshot(size: CGSize) -> OrbitCameraSnapshot {
        let axes = basis
        let right = SIMD3<Float>(axes.right)
        let up = SIMD3<Float>(axes.up)
        let forward = SIMD3<Float>(axes.forward)
        let normalizedDistance = Float(distance / scale)
        let eye = -forward * normalizedDistance
        let view = simd_float4x4(columns: (
            SIMD4(right.x, up.x, -forward.x, 0),
            SIMD4(right.y, up.y, -forward.y, 0),
            SIMD4(right.z, up.z, -forward.z, 0),
            SIMD4(-simd_dot(right, eye), -simd_dot(up, eye), simd_dot(forward, eye), 1)
        ))
        let aspect = Float(max(size.width, 1) / max(size.height, 1))
        let near = max(normalizedDistance * 0.0001, 0.0000001)
        let far = max(normalizedDistance * 100, 100)
        let halfHeight = normalizedDistance * Float(tan(fieldOfView / 2))
        let projection: simd_float4x4
        if topDown {
            projection = simd_float4x4(columns: (
                SIMD4(1 / (halfHeight * aspect), 0, 0, 0),
                SIMD4(0, 1 / halfHeight, 0, 0),
                SIMD4(0, 0, 1 / (near - far), 0),
                SIMD4(0, 0, near / (near - far), 1)
            ))
        } else {
            let y = 1 / Float(tan(fieldOfView / 2))
            projection = simd_float4x4(columns: (
                SIMD4(y / aspect, 0, 0, 0), SIMD4(0, y, 0, 0),
                SIMD4(0, 0, far / (near - far), -1),
                SIMD4(0, 0, near * far / (near - far), 0)
            ))
        }
        return OrbitCameraSnapshot(view: view, projection: projection, center: center, scale: scale,
                                   unitsPerPoint: 2 * Double(halfHeight) / max(size.height, 1),
                                   size: size, topDown: topDown)
    }
}

struct OrbitCameraSnapshot {
    var view: simd_float4x4
    var projection: simd_float4x4
    var center: SIMD3<Double>
    var scale: Double
    var unitsPerPoint: Double
    var size: CGSize
    var topDown: Bool
    var viewProjection: simd_float4x4 { projection * view }

    func normalized(_ position: SIMD3<Double>) -> SIMD3<Float> {
        SIMD3<Float>((position - center) / scale)
    }

    func projected(position: SIMD3<Double>, radius: Double) -> (point: CGPoint, radius: CGFloat, depth: Float)? {
        let p = normalized(position)
        let clip = viewProjection * SIMD4(p, 1)
        guard clip.w > 0, clip.isFiniteVector else { return nil }
        let ndc = clip / clip.w
        guard ndc.z >= 0, ndc.z <= 1, abs(ndc.x) < 1.5, abs(ndc.y) < 1.5 else { return nil }
        let radiusPixels = abs(Float(radius / scale) * projection.columns.1.y / clip.w) * Float(size.height) / 2
        return (CGPoint(x: CGFloat(ndc.x + 1) * size.width / 2,
                        y: CGFloat(ndc.y + 1) * size.height / 2), CGFloat(radiusPixels), ndc.z)
    }
}

struct OrbitProjectedBody {
    var id: String
    var name: String
    var point: CGPoint
    var radius: CGFloat
    var depth: Float
    var color: SIMD3<Float>
    var isSelected: Bool
}

extension SIMD3<Double> {
    var isRenderable: Bool {
        x.isFinite && y.isFinite && z.isFinite && abs(x) < 1e100 && abs(y) < 1e100 && abs(z) < 1e100
    }
}

private extension SIMD4<Float> {
    var isFiniteVector: Bool { x.isFinite && y.isFinite && z.isFinite && w.isFinite }
}
