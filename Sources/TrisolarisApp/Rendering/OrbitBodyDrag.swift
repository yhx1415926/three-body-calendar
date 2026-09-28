import CoreGraphics
import simd

struct OrbitDragCandidate {
    let id: String
    let geometry: OrbitBodyDrag
    let camera: OrbitCamera
}

/// A drag stays in the initial camera-facing plane. The grabbed point can be
/// anywhere on the displayed disc, so preserve its offset from the body's center.
struct OrbitBodyDrag {
    let originalPosition: SIMD3<Double>
    private let snapshot: OrbitCameraSnapshot
    private let planePosition: SIMD3<Double>
    private let planeNormal: SIMD3<Double>
    private let grabOffset: SIMD3<Double>

    init?(position: SIMD3<Double>, pointer: CGPoint, snapshot: OrbitCameraSnapshot) {
        guard position.isRenderable, snapshot.scale.isFinite, snapshot.scale > 0 else { return nil }
        let normal = SIMD3<Double>(-Double(snapshot.view.columns.0.z),
                                   -Double(snapshot.view.columns.1.z),
                                   -Double(snapshot.view.columns.2.z))
        let planePosition = (position - snapshot.center) / snapshot.scale
        guard let intersection = snapshot.normalizedIntersection(at: pointer, planePosition: planePosition,
                                                                  planeNormal: normal) else { return nil }
        self.originalPosition = position
        self.snapshot = snapshot
        self.planePosition = planePosition
        self.planeNormal = normal
        self.grabOffset = planePosition - intersection
    }

    func position(at pointer: CGPoint) -> SIMD3<Double>? {
        guard let intersection = snapshot.normalizedIntersection(at: pointer, planePosition: planePosition,
                                                                  planeNormal: planeNormal) else { return nil }
        let position = snapshot.center + (intersection + grabOffset) * snapshot.scale
        return position.isRenderable ? position : nil
    }
}

extension OrbitCameraSnapshot {
    /// Metal clip depth is 0...1. A second point halfway through that range
    /// defines the ray without the poor conditioning of the distant far plane.
    fileprivate func normalizedIntersection(at point: CGPoint, planePosition: SIMD3<Double>,
                                             planeNormal: SIMD3<Double>) -> SIMD3<Double>? {
        guard size.width.isFinite, size.height.isFinite, size.width > 0, size.height > 0,
              point.x.isFinite, point.y.isFinite else { return nil }
        let matrix = viewProjection
        let inverse = simd_inverse(simd_double4x4(columns: (
            SIMD4<Double>(matrix.columns.0), SIMD4<Double>(matrix.columns.1),
            SIMD4<Double>(matrix.columns.2), SIMD4<Double>(matrix.columns.3)
        )))
        let x = Double(point.x / size.width) * 2 - 1
        let y = Double(point.y / size.height) * 2 - 1
        func unproject(_ depth: Double) -> SIMD3<Double>? {
            let homogeneous = inverse * SIMD4(x, y, depth, 1)
            guard homogeneous.w.isFinite, abs(homogeneous.w) > 1e-15 else { return nil }
            let p = SIMD3(homogeneous.x, homogeneous.y, homogeneous.z) / homogeneous.w
            return p.isRenderable ? p : nil
        }
        guard let near = unproject(0), let second = unproject(0.5) else { return nil }
        let direction = second - near
        let denominator = simd_dot(direction, planeNormal)
        guard denominator.isFinite, abs(denominator) > 1e-15 else { return nil }
        let t = simd_dot(planePosition - near, planeNormal) / denominator
        guard t.isFinite, t >= 0 else { return nil }
        let result = near + direction * t
        return result.isRenderable ? result : nil
    }
}
