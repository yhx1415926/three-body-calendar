import Foundation

/// Stable raw values keep the existing preset and seeded-random entry points compatible.
public enum OrbitPreset: Int, CaseIterable, Identifiable, Sendable {
    case quietHierarchy = 0, figureEight = 1, random = 2
    case compactHierarchy = 3, inclinedHierarchy = 4, eccentricPlanet = 5
    case circumbinaryPlanet = 6, retrogradePlanet = 7, redDwarfPlanet = 8, distantBinary = 9

    public enum Category: String, CaseIterable, Identifiable, Sendable {
        case singleStar = "行星绕单星"
        case binary = "双星与行星"
        case choreography = "周期与随机"
        public var id: String { rawValue }
    }
    /// The menu keeps one single-host reference; legacy cases remain readable for existing projects.
    public static var catalog: [OrbitPreset] { [.quietHierarchy, .circumbinaryPlanet, .figureEight, .random] }
    public var id: Int { rawValue }
    public var category: Category {
        switch self {
        case .circumbinaryPlanet, .distantBinary: return .binary
        case .figureEight, .random: return .choreography
        default: return .singleStar
        }
    }
    public var title: String {
        switch self {
        case .quietHierarchy: return "宁静层级 · 20 / 200 AU"
        case .compactHierarchy: return "紧凑层级 · 8 / 60 AU"
        case .inclinedHierarchy: return "倾斜星系 · 55° 伴星轨道"
        case .eccentricPlanet: return "冷暖长年 · 偏心率 0.60"
        case .circumbinaryPlanet: return "双日世界 · 行星绕双星"
        case .retrogradePlanet: return "逆行世界 · 180° 行星轨道"
        case .redDwarfPlanet: return "红矮星家园 · 约 36 日标准年"
        case .distantBinary: return "远方双日 · 行星绕远主星"
        case .figureEight: return "八字共舞 · 等质量三星"
        case .random: return "混沌星海 · 随机初始轨道"
        }
    }
    public var summary: String {
        switch self {
        case .quietHierarchy: return "宽层级三星与近圆地球型行星，便于比较数值精度和历法。"
        case .compactHierarchy: return "缩短恒星层级尺度，观察比宽层级示例更明显的伴星扰动。"
        case .inclinedHierarchy: return "行星、内伴星和外伴星处于不同轨道平面，观察三维运动。"
        case .eccentricPlanet: return "行星从 0.4 AU 到 1.6 AU 往返，展示辐照与温度的周期变化。"
        case .circumbinaryPlanet: return "0.72 AU 行星环绕一对相距约 0.15 AU 的恒星，第三星远在外层。"
        case .retrogradePlanet: return "行星绕主星的方向与两颗伴星相反，可与顺行示例比较。"
        case .redDwarfPlanet: return "低质量、低光度主星与近轨行星，展示标准年的质量和距离依赖。"
        case .distantBinary: return "B、C 构成紧双星，A 携带行星在其远处运行，展示另一种三星层级。"
        case .figureEight: return "理想等质量三体的已知周期初值；默认不添加会扰动它的行星。"
        case .random: return "保留当前天体参数，按种子、空间尺度和动能比例生成初值。"
        }
    }
}

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

    public static func scenario(for preset: OrbitPreset, seed: UInt64 = 42) -> Scenario {
        switch preset {
        case .quietHierarchy: return stableHierarchy()
        case .figureEight: return figureEight(includePlanet: false)
        case .random: return random(seed: seed)
        case .compactHierarchy: return compactHierarchy()
        case .inclinedHierarchy: return inclinedHierarchy()
        case .eccentricPlanet: return eccentricPlanet()
        case .circumbinaryPlanet: return circumbinaryPlanet()
        case .retrogradePlanet: return retrogradePlanet()
        case .redDwarfPlanet: return redDwarfPlanet()
        case .distantBinary: return distantBinary()
        }
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

    public static func compactHierarchy(includePlanet: Bool = true) -> Scenario {
        var bodies = [star(0, mass: 1, radius: 1, luminosity: 1)]
        if includePlanet {
            bodies = combine(bodies, [earth()], semiMajorAxis: 1, eccentricity: 0.025,
                             inclinationDegrees: 0, trueAnomalyDegrees: 45)
        }
        bodies = combine(bodies, [star(1, mass: 0.65, radius: 0.67, luminosity: 0.16)],
                         semiMajorAxis: 8, eccentricity: 0.12, inclinationDegrees: 4, trueAnomalyDegrees: 150)
        bodies = combine(bodies, [star(2, mass: 0.45, radius: 0.46, luminosity: 0.035)],
                         semiMajorAxis: 60, eccentricity: 0.12, inclinationDegrees: 12, trueAnomalyDegrees: 65)
        return example(name: "紧凑的层级三星", bodies: bodies,
                       notes: "行星半长轴 1 AU；两级恒星相对半长轴 8、60 AU，偏心率均为 0.12。相比宽层级示例，伴星扰动更明显，可比较轨道与辐照的长期变化。")
    }

    public static func inclinedHierarchy(includePlanet: Bool = true) -> Scenario {
        var bodies = [star(0, mass: 1, radius: 1, luminosity: 1)]
        if includePlanet {
            bodies = combine(bodies, [earth()], semiMajorAxis: 1, eccentricity: 0.03,
                             inclinationDegrees: 0, trueAnomalyDegrees: 30)
        }
        bodies = combine(bodies, [star(1, mass: 0.7, radius: 0.7, luminosity: 0.2)],
                         semiMajorAxis: 18, eccentricity: 0.15, inclinationDegrees: 55,
                         trueAnomalyDegrees: 100, ascendingNodeDegrees: 35)
        bodies = combine(bodies, [star(2, mass: 0.5, radius: 0.5, luminosity: 0.05)],
                         semiMajorAxis: 150, eccentricity: 0.1, inclinationDegrees: 25,
                         trueAnomalyDegrees: 210, ascendingNodeDegrees: 120)
        return example(name: "交错的轨道平面", bodies: bodies,
                       notes: "以行星初始平面为参考：B 的相对轨道倾角 55°、升交点 35°，C 的轨道倾角 25°、升交点 120°。适合旋转三维视图观察；长时倾角和偏心率耦合需由积分检验。")
    }

    public static func eccentricPlanet(includePlanet: Bool = true) -> Scenario {
        var bodies = [star(0, mass: 1, radius: 1, luminosity: 1)]
        if includePlanet {
            bodies = combine(bodies, [earth()], semiMajorAxis: 1, eccentricity: 0.60,
                             inclinationDegrees: 0, trueAnomalyDegrees: 180)
        }
        bodies = combine(bodies, [star(1, mass: 0.7, radius: 0.7, luminosity: 0.2)],
                         semiMajorAxis: 30, eccentricity: 0.1, inclinationDegrees: 0, trueAnomalyDegrees: 90)
        bodies = combine(bodies, [star(2, mass: 0.5, radius: 0.5, luminosity: 0.05)],
                         semiMajorAxis: 240, eccentricity: 0.1, inclinationDegrees: 6, trueAnomalyDegrees: 240)
        return example(name: "冷暖交替的长年", bodies: bodies,
                       notes: "行星半长轴 1 AU、偏心率 0.60，从远星点出发；初始二体近、远星点为 0.4、1.6 AU。仅主星辐照即约为地球的 6.25 至 0.39 倍，适合观察热惯性和恒乱纪元切换。")
    }

    public static func circumbinaryPlanet(includePlanet: Bool = true) -> Scenario {
        var bodies = combine([star(0, mass: 0.75, radius: 0.76, luminosity: 0.32)],
                             [star(1, mass: 0.65, radius: 0.67, luminosity: 0.16)],
                             semiMajorAxis: 0.15, eccentricity: 0.05,
                             inclinationDegrees: 0, trueAnomalyDegrees: 40)
        if includePlanet {
            bodies = combine(bodies, [earth()], semiMajorAxis: 0.72, eccentricity: 0.02,
                             inclinationDegrees: 2, trueAnomalyDegrees: 150)
        }
        bodies = combine(bodies, [star(2, mass: 0.35, radius: 0.36, luminosity: 0.015)],
                         semiMajorAxis: 35, eccentricity: 0.1, inclinationDegrees: 8, trueAnomalyDegrees: 250)
        return example(name: "双日下的环双星行星", bodies: bodies, referenceDistanceAU: sqrt(0.32),
                       notes: "A、B 的相对半长轴为 0.15 AU，行星绕双星质心的初始半长轴为 0.72 AU，C 在 35 AU 外层。标准年仍固定采用 A 与其地球等辐照距离 √0.32 AU 的二体参考年，不等于行星绕双星的实际周期。")
    }

    public static func retrogradePlanet(includePlanet: Bool = true) -> Scenario {
        var bodies = [star(0, mass: 1, radius: 1, luminosity: 1)]
        if includePlanet {
            bodies = combine(bodies, [earth()], semiMajorAxis: 1, eccentricity: 0.025,
                             inclinationDegrees: 180, trueAnomalyDegrees: 45)
        }
        bodies = combine(bodies, [star(1, mass: 0.8, radius: 0.8, luminosity: 0.4)],
                         semiMajorAxis: 12, eccentricity: 0.15, inclinationDegrees: 0, trueAnomalyDegrees: 120)
        bodies = combine(bodies, [star(2, mass: 0.5, radius: 0.5, luminosity: 0.05)],
                         semiMajorAxis: 100, eccentricity: 0.1, inclinationDegrees: 10, trueAnomalyDegrees: 250)
        return example(name: "逆行于群星之间", bodies: bodies,
                       notes: "行星相对于 B 的轨道平面倾角为 180°，因此绕 A 逆行；两级恒星相对半长轴为 12、100 AU。逆行仅改变初始轨道方向，不能据此保证系统长期稳定。")
    }

    public static func redDwarfPlanet(includePlanet: Bool = true) -> Scenario {
        let referenceDistance = sqrt(0.025)
        var bodies = [star(0, mass: 0.4, radius: 0.4, luminosity: 0.025)]
        if includePlanet {
            bodies = combine(bodies, [earth()], semiMajorAxis: referenceDistance, eccentricity: 0.01,
                             inclinationDegrees: 0, trueAnomalyDegrees: 45)
        }
        bodies = combine(bodies, [star(1, mass: 0.3, radius: 0.31, luminosity: 0.012)],
                         semiMajorAxis: 3, eccentricity: 0.08, inclinationDegrees: 3, trueAnomalyDegrees: 135)
        bodies = combine(bodies, [star(2, mass: 0.2, radius: 0.22, luminosity: 0.004)],
                         semiMajorAxis: 25, eccentricity: 0.1, inclinationDegrees: 8, trueAnomalyDegrees: 230)
        return example(name: "红矮星的短年", bodies: bodies, referenceDistanceAU: referenceDistance,
                       notes: "主星为 0.4 个太阳质量、0.025 个太阳光度；行星参考距离 √0.025 ≈ 0.158 AU，标准年约 36 日。展示引力尺度与历法尺度的关系；未加入潮汐锁定、耀斑和光谱气候模型，不能据此判定真实红矮星宜居性。")
    }

    public static func distantBinary(includePlanet: Bool = true) -> Scenario {
        var primary = [star(0, mass: 1, radius: 1, luminosity: 1)]
        if includePlanet {
            primary = combine(primary, [earth()], semiMajorAxis: 1, eccentricity: 0.02,
                              inclinationDegrees: 0, trueAnomalyDegrees: 30)
        }
        let binary = combine([star(1, mass: 0.65, radius: 0.67, luminosity: 0.16)],
                             [star(2, mass: 0.55, radius: 0.56, luminosity: 0.07)],
                             semiMajorAxis: 0.2, eccentricity: 0.08,
                             inclinationDegrees: 20, trueAnomalyDegrees: 100, ascendingNodeDegrees: 45)
        let bodies = combine(primary, binary, semiMajorAxis: 20, eccentricity: 0.12,
                             inclinationDegrees: 7, trueAnomalyDegrees: 230)
        return example(name: "远方的紧双星", bodies: bodies,
                       notes: "B、C 形成相对半长轴 0.2 AU 的紧双星；A 与它们的质心相距约 20 AU，并携带 1 AU 行星。与环双星行星示例对照，可观察围绕单星与围绕双星质心的不同结构。")
    }

    private static func example(name: String, bodies: [CelestialBody], referenceDistanceAU: Double = 1,
                                notes: String) -> Scenario {
        var centered = bodies
        recenter(&centered)
        centered.sort { $0.kind == $1.kind ? $0.name < $1.name : $0.kind == .star }
        return Scenario(name: name, bodies: centered, referenceStarID: identifiers[0],
                        referenceDistanceAU: referenceDistanceAU,
                        notes: notes + " 本示例是自洽的层级开普勒初值，恒星参数为教学示例；短期数值检查不构成万年稳定证明。")
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
                                eccentricity e: Double, inclinationDegrees: Double, trueAnomalyDegrees: Double,
                                ascendingNodeDegrees: Double = 0) -> [CelestialBody] {
        let lm = left.reduce(0) { $0+$1.massSolar }, rm = right.reduce(0) { $0+$1.massSolar }
        let f = trueAnomalyDegrees * .pi/180, inc = inclinationDegrees * .pi/180
        let p = a*(1-e*e), distance = p/(1+e*cos(f))
        let node = ascendingNodeDegrees * .pi/180
        func rotateNode(_ value: Vector3) -> Vector3 {
            Vector3(value.x*cos(node)-value.y*sin(node), value.x*sin(node)+value.y*cos(node), value.z)
        }
        let r = rotateNode(Vector3(distance*cos(f), distance*sin(f)*cos(inc), distance*sin(f)*sin(inc)))
        let vScale = sqrt(Astronomy.gravitationalConstant*(lm+rm)/p)
        let v = rotateNode(Vector3(-sin(f), (e+cos(f))*cos(inc), (e+cos(f))*sin(inc)))*vScale
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
