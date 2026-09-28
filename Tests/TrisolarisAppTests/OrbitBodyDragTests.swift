import CoreGraphics
import simd
import Testing
@testable import TrisolarisApp

@Suite("直接拖动天体")
struct OrbitBodyDragTests {
    @Test("透视与俯视拖动均保持屏幕深度和抓取位置", arguments: [false, true])
    func screenPlaneDrag(topDown: Bool) throws {
        var camera = OrbitCamera()
        camera.target = SIMD3(3, -2, 7)
        camera.scale = 10
        camera.distance = 35
        camera.topDown = topDown
        let position = camera.center + camera.basis.right * 1.2 + camera.basis.forward * 2
        let snapshot = camera.snapshot(size: CGSize(width: 1_000, height: 700))
        let initialProjection = try #require(snapshot.projected(position: position, radius: 0))
        let grabPoint = CGPoint(x: initialProjection.point.x + 4, y: initialProjection.point.y - 3)
        let drag = try #require(OrbitBodyDrag(position: position, pointer: grabPoint, snapshot: snapshot))
        let unchanged = try #require(drag.position(at: grabPoint))
        #expect(simd_length(unchanged - position) < 1e-10)

        let moved = try #require(drag.position(at: CGPoint(x: grabPoint.x + 123, y: grabPoint.y - 74)))
        let projection = try #require(snapshot.projected(position: moved, radius: 0))
        #expect(abs(projection.point.x - initialProjection.point.x - 123) < 0.01)
        #expect(abs(projection.point.y - initialProjection.point.y + 74) < 0.01)
        #expect(abs(simd_dot(moved - position, camera.basis.forward)) < 1e-6)
        #expect(abs(projection.depth - initialProjection.depth) < 1e-6)
    }

    @Test("宽三星系统的缩放和相机平移不破坏拖动", arguments: [0.001, 15_000.0])
    func sceneScaleInvariant(scale: Double) throws {
        var camera = OrbitCamera()
        camera.target = SIMD3(3, -2, 7) * scale
        camera.panOffset = SIMD3(0.2, 0.8, -0.1) * scale
        camera.scale = scale
        camera.distance = scale * 3.5
        let snapshot = camera.snapshot(size: CGSize(width: 600, height: 800))
        let point = CGPoint(x: 300, y: 400)
        let drag = try #require(OrbitBodyDrag(position: camera.center, pointer: point, snapshot: snapshot))
        let moved = try #require(drag.position(at: CGPoint(x: 360, y: 425)))
        let projection = try #require(snapshot.projected(position: moved, radius: 0))
        #expect(abs(projection.point.x - 360) < 0.01)
        #expect(abs(projection.point.y - 425) < 0.01)
        #expect(abs(simd_dot((moved - camera.center) / scale, camera.basis.forward)) < 1e-6)
    }

    @Test("无效视口或鼠标坐标不会产生非有限天体位置")
    func rejectInvalidGeometry() throws {
        let camera = OrbitCamera()
        #expect(OrbitBodyDrag(position: .zero, pointer: .zero, snapshot: camera.snapshot(size: .zero)) == nil)
        let snapshot = camera.snapshot(size: CGSize(width: 600, height: 800))
        let drag = try #require(OrbitBodyDrag(position: .zero, pointer: CGPoint(x: 300, y: 400), snapshot: snapshot))
        #expect(drag.position(at: CGPoint(x: CGFloat.nan, y: 400)) == nil)
        #expect(OrbitBodyDrag(position: SIMD3(.infinity, 0, 0), pointer: .zero, snapshot: snapshot) == nil)
    }
}
