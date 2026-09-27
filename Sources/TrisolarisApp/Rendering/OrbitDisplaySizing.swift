import Foundation

/// Freeze enhanced sizes when framing a scene. A foreground planet must never
/// change a star's radius merely by moving close to it.
struct OrbitDisplaySizing {
    private var radii: [String: Double] = [:]
    init(bodies: [RenderBody] = [], sceneScale: Double = 1) {
        let stars = bodies.filter(\.isStar)
        for body in stars {
            let initialSpacing = bodies.filter { $0.id != body.id }.map {
                let d = $0.position-body.position
                return sqrt(d.x*d.x+d.y*d.y+d.z*d.z)
            }.min() ?? sceneScale
            radii[body.id] = max(body.radius, min(sceneScale*0.025,initialSpacing*0.15))
        }
        let smallestStar = radii.values.min() ?? sceneScale*0.025
        for body in bodies where !body.isStar {
            radii[body.id] = max(body.radius,min(sceneScale*0.011,smallestStar*0.38))
        }
    }
    func radius(for body: RenderBody, enhanced: Bool) -> Double {
        enhanced ? (radii[body.id] ?? body.radius) : body.radius
    }
}
