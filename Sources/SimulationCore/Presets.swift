import Foundation

public enum Presets {
    private static let identifiers = [
        UUID(uuidString: "00000000-0000-4000-8000-000000000001")!,
        UUID(uuidString: "00000000-0000-4000-8000-000000000002")!,
        UUID(uuidString: "00000000-0000-4000-8000-000000000003")!,
        UUID(uuidString: "00000000-0000-4000-8000-000000000004")!
    ]
    private static func star(_ index: Int, mass: Double, radius: Double, luminosity: Double) -> CelestialBody {
        CelestialBody(id: identifiers[index], name: ["恒星 A", "恒星 B", "恒星 C"][index], kind: .star,
                      massSolar: mass, radiusAU: radius*Astronomy.solarRadiusAU, luminositySolar: luminosity)
    }
    private static func earth() -> CelestialBody {
        CelestialBody(id: identifiers[3], name: "三体行星", kind: .planet, massSolar: Astronomy.earthMassSolar,
                      radiusAU: Astronomy.earthRadiusAU)
    }

    /// A deliberately widely separated hierarchy. Stability is a numerical property to be checked, not guaranteed.
    public static func stableHierarchy(includePlanet: Bool = true) -> Scenario {
        var a = [star(0, mass: 1, radius: 1, luminosity: 1)]
        if includePlanet {
            a = combine(a, [earth()], semiMajorAxis: 1, eccentricity: 0.0167, inclinationDegrees: 0, trueAnomalyDegrees: 0)
        }
        a = combine(a, [star(1, mass: 0.7, radius: 0.7, luminosity: 0.2)], semiMajorAxis: 20,
                    eccentricity: 0.1, inclinationDegrees: 0, trueAnomalyDegrees: 90)
        a = combine(a, [star(2, mass: 0.5, radius: 0.5, luminosity: 0.05)], semiMajorAxis: 200,
                    eccentricity: 0.1, inclinationDegrees: 5, trueAnomalyDegrees: 120)
        a.sort { $0.kind == $1.kind ? $0.name < $1.name : $0.kind == .star }
        return Scenario(name: "宁静的层级三星", bodies: a, referenceStarID: identifiers[0],
                        notes: "地球型行星绕太阳型主星；伴星相对半长轴为 20、200 AU。强层级初值是长期稳定候选，实际结论以本次积分为准。")
    }

    public static func figureEight(includePlanet: Bool = true, scaleAU: Double = 10) -> Scenario {
        let length = max(0.1, scaleAU)
        let speed = sqrt(Astronomy.gravitationalConstant/length)
        var bodies = (0..<3).map { star($0, mass: 1, radius: 1, luminosity: 1) }
        let r = Vector3(-0.97000436, 0.24308753, 0)
        let v = Vector3(0.466203685, 0.43236573, 0)
        bodies[0].positionAU = r*length; bodies[1].positionAU = -r*length
        bodies[0].velocityAUPerDay = v*speed; bodies[1].velocityAUPerDay = v*speed
        bodies[2].velocityAUPerDay = v*(-2*speed)
        if includePlanet { addEarth(to: &bodies, distanceAU: 1) }
        recenter(&bodies)
        return Scenario(name: "八字共舞", bodies: bodies, referenceStarID: identifiers[0],
                        notes: "Chenciner–Montgomery / Simó 等质量八字轨道，使用公开舍入初值。来源：https://people.ucsc.edu/~rmont/NbdyB.html 。已知周期性指理想三体解；添加有限质量行星或改变恒星参数后不能保证周期稳定。")
    }

    public static func random(seed: UInt64, includePlanet: Bool = true) -> Scenario {
        var rng = SplitMix64(state: seed)
        var bodies: [CelestialBody] = []
        for index in 0..<3 {
            let mass = 0.5 + rng.unit()
            var b = star(index, mass: mass, radius: pow(mass, 0.8), luminosity: pow(mass, 3.5))
            var candidate = Vector3.zero
            for _ in 0..<1000 {
                candidate = Vector3(rng.signed()*8, rng.signed()*8, rng.signed()*4)
                if bodies.allSatisfy({ ($0.positionAU-candidate).length > 3 }) { break }
            }
            b.positionAU = candidate
            b.velocityAUPerDay = Vector3(rng.signed(), rng.signed(), rng.signed())
            bodies.append(b)
        }
        recenter(&bodies)
        var kinetic = 0.0, potential = 0.0
        for i in bodies.indices {
            kinetic += 0.5*bodies[i].massSolar*bodies[i].velocityAUPerDay.squaredLength
            for j in bodies.indices where j > i {
                potential -= Astronomy.gravitationalConstant*bodies[i].massSolar*bodies[j].massSolar/(bodies[i].positionAU-bodies[j].positionAU).length
            }
        }
        let velocityScale = sqrt(0.4*abs(potential)/max(kinetic, 1e-30))
        for i in bodies.indices { bodies[i].velocityAUPerDay = bodies[i].velocityAUPerDay*velocityScale }
        let referenceDistance = sqrt(bodies[0].luminositySolar)
        if includePlanet { addEarth(to: &bodies, distanceAU: referenceDistance) }
        recenter(&bodies)
        return Scenario(name: "混沌星海 · \(seed)", bodies: bodies, referenceStarID: identifiers[0],
                        referenceDistanceAU: referenceDistance, randomSeed: seed,
                        notes: "可重现的随机初值，初始三星动能/势能绝对值比为 0.4。恒星半径、光度采用示例缩放，可自行修改。不保证长期束缚或行星存活。")
    }

    public static func recenter(_ bodies: inout [CelestialBody]) {
        let mass = bodies.reduce(0) { $0+$1.massSolar }
        guard mass > 0 else { return }
        let position = bodies.reduce(Vector3.zero) { $0+$1.positionAU*$1.massSolar }/mass
        let velocity = bodies.reduce(Vector3.zero) { $0+$1.velocityAUPerDay*$1.massSolar }/mass
        for i in bodies.indices { bodies[i].positionAU = bodies[i].positionAU-position; bodies[i].velocityAUPerDay = bodies[i].velocityAUPerDay-velocity }
    }

    public static func random(seed: UInt64, template: Scenario, spatialScaleAU: Double, virialRatio: Double) -> Scenario {
        var result = template
        var rng = SplitMix64(state: seed)
        var bodies = template.bodies.filter { $0.kind == .star }
        guard bodies.count == 3, spatialScaleAU.isFinite, spatialScaleAU > 0, virialRatio.isFinite, virialRatio > 0 else { return template }
        for index in bodies.indices {
            for _ in 0..<1000 {
                let position = Vector3(rng.signed(), rng.signed(), rng.signed()) * spatialScaleAU
                bodies[index].positionAU = position
                if bodies[..<index].allSatisfy({ ($0.positionAU-position).length > max(($0.radiusAU+bodies[index].radiusAU)*3, spatialScaleAU*0.2) }) { break }
            }
            bodies[index].velocityAUPerDay = Vector3(rng.signed(), rng.signed(), rng.signed())
        }
        recenter(&bodies)
        var kinetic = 0.0, potential = 0.0
        for i in bodies.indices {
            kinetic += 0.5*bodies[i].massSolar*bodies[i].velocityAUPerDay.squaredLength
            for j in bodies.indices where j > i {
                potential += Astronomy.gravitationalConstant*bodies[i].massSolar*bodies[j].massSolar / max((bodies[i].positionAU-bodies[j].positionAU).length, 1e-20)
            }
        }
        let speedScale = sqrt(virialRatio*potential/max(kinetic,1e-30))
        for i in bodies.indices { bodies[i].velocityAUPerDay = bodies[i].velocityAUPerDay*speedScale }
        if var planet = template.planet, let host = bodies.first(where: { $0.id == template.referenceStarID }) {
            let companion = bodies.filter { $0.id != host.id }.min { ($0.positionAU-host.positionAU).length < ($1.positionAU-host.positionAU).length }!
            let radial = (host.positionAU-companion.positionAU)/(host.positionAU-companion.positionAU).length
            var tangent = radial.cross(Vector3(0,0,1))
            if tangent.length < 1e-8 { tangent = radial.cross(Vector3(0,1,0)) }
            tangent = tangent/tangent.length
            planet.positionAU = host.positionAU+radial*template.referenceDistanceAU
            planet.velocityAUPerDay = host.velocityAUPerDay+tangent*sqrt(Astronomy.gravitationalConstant*(host.massSolar+planet.massSolar)/template.referenceDistanceAU)
            bodies.append(planet)
        }
        recenter(&bodies)
        result.bodies = bodies; result.randomSeed = seed; result.name = "混沌星海 · \(seed)"
        result.notes = "保留天体参数的种子随机初值。空间尺度 \(spatialScaleAU) AU，初始三星动能 / |势能| = \(virialRatio)。不保证长期束缚或行星存活。"
        return result
    }

    private static func addEarth(to bodies: inout [CelestialBody], distanceAU: Double) {
        var planet = earth()
        // Orient away from the closest companion to avoid an accidental initial overlap.
        let host = bodies[0]
        let companion = bodies.dropFirst().min { ($0.positionAU-host.positionAU).length < ($1.positionAU-host.positionAU).length }!
        let away = host.positionAU-companion.positionAU
        let radial = away/away.length
        var tangent = radial.cross(Vector3(0, 0, 1))
        if tangent.length < 1e-8 { tangent = radial.cross(Vector3(0, 1, 0)) }
        tangent = tangent/tangent.length
        let relativeVelocity = tangent*sqrt(Astronomy.gravitationalConstant*(host.massSolar+planet.massSolar)/distanceAU)
        planet.positionAU = host.positionAU+radial*distanceAU
        planet.velocityAUPerDay = host.velocityAUPerDay+relativeVelocity
        bodies.append(planet)
    }

    private static func combine(_ left: [CelestialBody], _ right: [CelestialBody], semiMajorAxis a: Double,
                                eccentricity e: Double, inclinationDegrees: Double, trueAnomalyDegrees: Double) -> [CelestialBody] {
        let lm = left.reduce(0) { $0+$1.massSolar }, rm = right.reduce(0) { $0+$1.massSolar }
        let f = trueAnomalyDegrees * .pi/180, inc = inclinationDegrees * .pi/180
        let p = a*(1-e*e), distance = p/(1+e*cos(f))
        let r = Vector3(distance*cos(f), distance*sin(f)*cos(inc), distance*sin(f)*sin(inc))
        let vScale = sqrt(Astronomy.gravitationalConstant*(lm+rm)/p)
        let v = Vector3(-sin(f), (e+cos(f))*cos(inc), (e+cos(f))*sin(inc))*vScale
        func moved(_ bodies: [CelestialBody], fraction: Double) -> [CelestialBody] {
            bodies.map { original in
                var body = original
                body.positionAU = body.positionAU+r*fraction
                body.velocityAUPerDay = body.velocityAUPerDay+v*fraction
                return body
            }
        }
        return moved(left, fraction: -rm/(lm+rm))+moved(right, fraction: lm/(lm+rm))
    }
}

private struct SplitMix64 {
    var state: UInt64
    mutating func next() -> UInt64 {
        state &+= 0x9E3779B97F4A7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
        z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
        return z ^ (z >> 31)
    }
    mutating func unit() -> Double { Double(next() >> 11) / 9007199254740992.0 }
    mutating func signed() -> Double { unit()*2-1 }
}
