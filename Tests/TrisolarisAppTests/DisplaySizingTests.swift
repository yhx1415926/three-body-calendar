import Testing
@testable import TrisolarisApp

@Suite("天体显示尺寸回归")
struct DisplaySizingTests {
    @Test("行星从远处移到恒星前方，不改变恒星显示半径")
    func foregroundPlanetDoesNotShrinkStars() {
        let star = RenderBody(id: "A", name: "A", position: .zero, radius: 0.005, color: .one, isStar: true)
        let companion = RenderBody(id: "B", name: "B", position: SIMD3(20, 0, 0), radius: 0.004, color: .one, isStar: true)
        var planet = RenderBody(id: "P", name: "P", position: SIMD3(1, 0, 0), radius: 0.00004, color: .one, isStar: false)
        let sizing = OrbitDisplaySizing(bodies: [star, companion, planet], sceneScale: 20)
        let radius = sizing.radius(for: star, enhanced: true)
        #expect(radius < 1) // The initial one-AU planet orbit remains outside the visual star.
        for distance in [0.01, 0.005, 0.00001, 1, 100] {
            planet.position = SIMD3(0, 0, distance)
            #expect(sizing.radius(for: star, enhanced: true) == radius)
            #expect(sizing.radius(for: planet, enhanced: true) < radius)
        }
        #expect(sizing.radius(for: star, enhanced: false) == star.radius)
    }
}
