import Foundation

/// Offline, versioned measurements and a separately identified dynamical model.
/// The model is not a reconstruction of every observed epoch and does not fit
/// the bundled measurements afresh. See alpha-centauri-provenance.md.
public enum AlphaCentauriCatalog {
    public static let modelEpochJulianYear = 1991.25
    public static let coverageSummary = "内置 1940–2019 年公开数据：106 对 A/B 方位角与角距、17,567 条 A/B 径向速度、334 条比邻星相对径向速度。共 18,113 条测量值；不是自首次发现以来的完整观测档案。"
    public static let modelSummary = "采用 Kervella 2016/2017 统一的三星参数，在 J1991.25 构建质心静止、银河坐标轴方向的牛顿引力初值。A/B 内轨道由观测拟合根数计算；比邻星使用论文发表的三维相对位置和速度。"
    public static let limitations = [
        "观测是离散记录，不能直接提供连续三维轨迹。图中的运动来自引力模型；实测表与模型结果分别展示。",
        "公开汇编从 1940 年开始，未覆盖更早的历史观测，也不包含 2020 年之后的数据；可另行导入带来源的 CSV 补充。",
        "比邻星的相对径向速度保留各仪器零点，不能与 A/B 的 km/s 数值直接相加；原始时间与测量单位均保留。",
        "比邻星相对距离约 12,947 ± 260 AU、速度约 273 ± 49 m/s。轨道存在观测不确定度，默认采用中心值，未传播协方差。",
        "内置模型采用一致的 2016/2017 动力学解；2021 观测汇编中的更新拟合解未混入旧外轨道。忽略银河潮汐、后牛顿修正和恒星光度随时间变化。",
        "真实模型仅包含三颗恒星；可选的实验行星是为生成万年历加入的假设，不能视为已确认的真实行星轨道。"
    ]

    public static let sources: [ObservedSystemSource] = [
        .init(id: "akeson2021-astrometry", title: "Akeson et al. 2021 · A/B 相对天体测量（表 6）",
              url: URL(string: "https://vizier.cds.unistra.fr/viz-bin/VizieR?-source=J/AJ/162/14/table6")!,
              coverage: "1940.1900–2019.6505 · 106 对测量",
              notes: "原始方位角（deg）、角距（arcsec）、各自不确定度与参考文献标记。B 相对 A。"),
        .init(id: "akeson2021-harps", title: "Akeson et al. 2021 · A/B HARPS 径向速度（表 7）",
              url: URL(string: "https://vizier.cds.unistra.fr/viz-bin/VizieR?-source=J/AJ/162/14/table7")!,
              coverage: "2004–2018 · A 5,184 条，B 12,383 条",
              notes: "保留作者筛选、校正后的已发表 km/s 数据；原时间为 MJD，原表未指定时间尺度。并非未处理的原始光谱。"),
        .init(id: "suarez2020-proxima", title: "Suárez Mascareño et al. 2020 · 比邻星径向速度（表 A.1）",
              url: URL(string: "https://vizier.cds.unistra.fr/viz-bin/VizieR?-source=J/A+A/639/A77/tablea1")!,
              coverage: "2000–2019 · 334 条相对测量",
              notes: "UVES、HARPS、ESPRESSO；m/s，保留各仪器及升级前后零点。时间为 BJD−2450000。"),
        .init(id: "kervella2016-orbit", title: "Kervella et al. 2016 · A/B 轨道根数",
              url: URL(string: "https://doi.org/10.1051/0004-6361/201629201")!,
              coverage: "2016 年发表的拟合解 · 表 1",
              notes: "P = 79.929 ± 0.013 年，e = 0.5208 ± 0.0011，视差 747.17 ± 0.61 mas；不属于观测时序。"),
        .init(id: "kervella2017-proxima", title: "Kervella et al. 2017 · 比邻星与 A/B 的三维状态",
              url: URL(string: "https://arxiv.org/abs/1611.03495")!,
              coverage: "J1991.25 天体测量参考历元 · 表 1、2、B.1",
              notes: "星表位置、自行、视差和校正径向速度的综合解；作者忽略测量历元间的微小径向加速度。三维量由观测推导。"),
        .init(id: "kervella2017-radii", title: "Kervella et al. 2017 · A/B 半径与光度",
              url: URL(string: "https://arxiv.org/abs/1610.06185")!,
              coverage: "2016 年干涉测量 · 表 5",
              notes: "A/B 光度分别为 1.521 ± 0.015、0.503 ± 0.007 L☉。"),
        .init(id: "ribas2016-proxima", title: "Ribas et al. 2016 · 比邻星辐射参数",
              url: URL(string: "https://doi.org/10.1051/0004-6361/201629576")!,
              coverage: "表 1 的恒星光度参数",
              notes: "比邻星采用光度 0.00155 L☉；光度固定是模拟假设，不重建耀斑历史。")
    ]

    /// Parse off the main actor. Bundled measurements are factual numeric tables,
    /// with attribution and original column definitions shipped alongside them.
    public static func observations() throws -> [StellarObservation] {
        var rows = [StellarObservation]()
        rows.reserveCapacity(18_113)
        for (index, fields) in try records("alpha-centauri-ab-astrometry").enumerated() {
            guard fields.count >= 6, let epoch = finite(fields[0]),
                  let angle = finite(fields[1]), let angleError = finite(fields[2]),
                  let separation = finite(fields[3]), let separationError = finite(fields[4]) else {
                throw ObservedSystemError.invalidRecord("alpha-centauri-ab-astrometry", index + 1)
            }
            let reference = fields[5...].joined(separator: " ")
            let detail = "原历元 \(fields[0])（原表十进制年）；B 相对 A；参考 \(reference)"
            rows.append(.init(id: "ab-astrometry-\(index)-pa", epochJulianYear: epoch, component: "B 相对 A",
                              kind: .positionAngle, value: angle, uncertainty: angleError, unit: "deg",
                              detail: detail, sourceID: "akeson2021-astrometry"))
            rows.append(.init(id: "ab-astrometry-\(index)-sep", epochJulianYear: epoch, component: "B 相对 A",
                              kind: .separation, value: separation, uncertainty: separationError, unit: "arcsec",
                              detail: detail, sourceID: "akeson2021-astrometry"))
        }
        for (index, fields) in try records("alpha-centauri-ab-harps").enumerated() {
            guard fields.count == 4, let mjd = finite(fields[0]), ["A", "B"].contains(fields[1]),
                  let value = finite(fields[2]), let error = finite(fields[3]) else {
                throw ObservedSystemError.invalidRecord("alpha-centauri-ab-harps", index + 1)
            }
            rows.append(.init(id: "ab-harps-\(index)", epochJulianYear: 2000 + (mjd - 51_544.5) / 365.25,
                              component: "半人马座 α \(fields[1])", kind: .radialVelocity,
                              value: value, uncertainty: error, unit: "km/s",
                              detail: "MJD \(fields[0])；HARPS；作者筛选和校正，时标未在原表标明",
                              sourceID: "akeson2021-harps"))
        }
        let instruments = ["UVES", "HARPS 升级前", "HARPS 升级后", "ESPRESSO 升级前", "ESPRESSO 升级后"]
        for (index, fields) in try records("proxima-radial-velocity").enumerated() {
            guard fields.count == 4, let bjdOffset = finite(fields[0]),
                  let value = finite(fields[1]), let error = finite(fields[2]),
                  let instrument = Int(fields[3]), instruments.indices.contains(instrument) else {
                throw ObservedSystemError.invalidRecord("proxima-radial-velocity", index + 1)
            }
            rows.append(.init(id: "proxima-rv-\(index)", epochJulianYear: 2000 + (bjdOffset - 1545) / 365.25,
                              component: "比邻星", kind: .relativeRadialVelocity,
                              value: value, uncertainty: error, unit: "m/s",
                              detail: "BJD−2450000 = \(fields[0])；\(instruments[instrument])；相对该仪器零点",
                              sourceID: "suarez2020-proxima"))
        }
        return rows.sorted {
            $0.epochJulianYear == $1.epochJulianYear ? $0.id < $1.id : $0.epochJulianYear < $1.epochJulianYear
        }
    }

    /// Model epoch J1991.25; axes parallel to the heliocentric Galactic frame,
    /// origin and translational velocity shifted to the triple's barycenter.
    /// No fictitious planet is silently inserted into the observed system.
    public static func initialScenario() -> Scenario {
        let massA = 1.1055, massB = 0.9373, massC = 0.1221
        let massAB = massA + massB, massTotal = massAB + massC
        let parsecAU = 648_000 / Double.pi
        let kilometersPerSecondToAUPerDay = 86400 / 149_597_870.7
        // Kervella 2017 Table B.1, Proxima minus AB; rounded published means.
        let outerPosition = Vector3(-0.05622, -0.00198, -0.02785) * parsecAU
        let outerVelocity = Vector3(-0.099, 0.173, 0.187) * kilometersPerSecondToAUPerDay
        let inner = innerBinaryRelativeState(epochJulianYear: modelEpochJulianYear)
        let positionAB = outerPosition * (-massC / massTotal)
        let velocityAB = outerVelocity * (-massC / massTotal)
        let ids = ["A0000000-0000-4000-8000-000000000001", "A0000000-0000-4000-8000-000000000002", "A0000000-0000-4000-8000-000000000003"].map { UUID(uuidString: $0)! }
        let bodies = [
            CelestialBody(id: ids[0], name: "半人马座 α A", kind: .star, massSolar: massA,
                          radiusAU: 1.2234 * Astronomy.solarRadiusAU, luminositySolar: 1.521,
                          positionAU: positionAB - inner.position * (massB / massAB),
                          velocityAUPerDay: velocityAB - inner.velocity * (massB / massAB)),
            CelestialBody(id: ids[1], name: "半人马座 α B", kind: .star, massSolar: massB,
                          radiusAU: 0.8632 * Astronomy.solarRadiusAU, luminositySolar: 0.503,
                          positionAU: positionAB + inner.position * (massA / massAB),
                          velocityAUPerDay: velocityAB + inner.velocity * (massA / massAB)),
            CelestialBody(id: ids[2], name: "比邻星", kind: .star, massSolar: massC,
                          radiusAU: 0.1542 * Astronomy.solarRadiusAU, luminositySolar: 0.00155,
                          positionAU: outerPosition * (massAB / massTotal),
                          velocityAUPerDay: outerVelocity * (massAB / massTotal))
        ]
        return Scenario(name: "半人马座 α · 观测约束模型 J1991.25", bodies: bodies,
                        referenceStarID: ids[0], referenceDistanceAU: sqrt(1.521),
                        notes: ([modelSummary, coverageSummary] + limitations + sources.map { "\($0.title)：\($0.url.absoluteString)" }).joined(separator: "\n"))
    }

    /// A clearly hypothetical Earth-mass planet makes the observed triple usable
    /// as a calendar experiment without treating a fitted planetary orbit as data.
    public static func scenarioWithExperimentalPlanet() -> Scenario {
        var scenario = initialScenario()
        let host = scenario.bodies[0]
        let companion = scenario.bodies[1]
        let relativePosition = companion.positionAU - host.positionAU
        let relativeVelocity = companion.velocityAUPerDay - host.velocityAUPerDay
        let outward = -relativePosition / relativePosition.length
        let angularMomentum = relativePosition.cross(relativeVelocity)
        let tangent = angularMomentum.cross(outward) / angularMomentum.cross(outward).length
        let radius = scenario.referenceDistanceAU
        let mass = Astronomy.earthMassSolar
        let planet = CelestialBody(
            id: UUID(uuidString: "A0000000-0000-4000-8000-000000000004")!,
            name: "实验行星 · α Cen A", kind: .planet,
            massSolar: mass, radiusAU: Astronomy.earthRadiusAU,
            positionAU: host.positionAU + outward * radius,
            velocityAUPerDay: host.velocityAUPerDay + tangent * sqrt(Astronomy.gravitationalConstant * (host.massSolar + mass) / radius)
        )
        scenario.bodies.append(planet)
        scenario.calendarPlanetID = planet.id
        scenario.name = "半人马座 α · 实验行星"
        scenario.notes += "\n实验行星采用 1 地球质量、1 地球半径，在 A 星单星参考辐照距离起步，初始速度按局部圆轨道设置。它不属于真实观测或已确认轨道；随后由四体引力积分。"
        return scenario
    }

    // Exposed internally for a projection-vs-Hipparcos regression test, so a
    // swapped node/periastron convention cannot silently mirror the orbit.
    static func innerBinaryRelativeState(epochJulianYear: Double) -> (position: Vector3, velocity: Vector3) {
        let periodDays = 79.929 * 365.25, eccentricity = 0.5208
        let mu = Astronomy.gravitationalConstant * (1.1055 + 0.9373)
        // Fit masses are rounded independently: enforce Kepler consistency with
        // the published period rather than introducing an artificial drift.
        let a = cbrt(mu * pow(periodDays / (2 * .pi), 2))
        let mean = (2 * .pi * (epochJulianYear - 1955.604) / 79.929).remainder(dividingBy: 2 * .pi)
        var eccentric = mean
        for _ in 0..<20 {
            let correction = (eccentric - eccentricity * sin(eccentric) - mean) / (1 - eccentricity * cos(eccentric))
            eccentric -= correction
            if abs(correction) < 1e-14 { break }
        }
        let root = sqrt(1 - eccentricity * eccentricity)
        let rate = (2 * .pi / periodDays) / (1 - eccentricity * cos(eccentric))
        let position = Vector3(a * (cos(eccentric) - eccentricity), a * root * sin(eccentric), 0)
        let velocity = Vector3(-a * sin(eccentric) * rate, a * root * cos(eccentric) * rate, 0)
        return (orbitalPlaneToGalactic(position), orbitalPlaneToGalactic(velocity))
    }

    static func equatorialToGalactic(_ p: Vector3) -> Vector3 {
        // ICRS-to-Galactic orthogonal rotation (IAU Galactic axes in ICRS).
        Vector3(-0.0548755604162154 * p.x - 0.8734370902348850 * p.y - 0.4838350155487132 * p.z,
                 0.4941094278755837 * p.x - 0.4448296299600112 * p.y + 0.7469822444972189 * p.z,
                -0.8676661490190047 * p.x - 0.1980763734312015 * p.y + 0.4559837761750669 * p.z)
    }

    private static func orbitalPlaneToGalactic(_ p: Vector3) -> Vector3 {
        let i = 79.320 * Double.pi / 180, omega = 232.006 * Double.pi / 180, node = 205.064 * Double.pi / 180
        let north = (cos(node) * cos(omega) - sin(node) * sin(omega) * cos(i)) * p.x
            + (-cos(node) * sin(omega) - sin(node) * cos(omega) * cos(i)) * p.y
        let east = (sin(node) * cos(omega) + cos(node) * sin(omega) * cos(i)) * p.x
            + (-sin(node) * sin(omega) + cos(node) * cos(omega) * cos(i)) * p.y
        let away = sin(omega) * sin(i) * p.x + cos(omega) * sin(i) * p.y
        let ra = (14 + 39.0 / 60 + 40.2068 / 3600) * 15 * .pi / 180
        let dec = -(60 + 50.0 / 60 + 13.673 / 3600) * .pi / 180
        let unitEast = Vector3(-sin(ra), cos(ra), 0)
        let unitNorth = Vector3(-cos(ra) * sin(dec), -sin(ra) * sin(dec), cos(dec))
        let unitAway = Vector3(cos(ra) * cos(dec), sin(ra) * cos(dec), sin(dec))
        return equatorialToGalactic(unitNorth * north + unitEast * east + unitAway * away)
    }

    private static func finite(_ text: String) -> Double? {
        guard let value = Double(text), value.isFinite else { return nil }
        return value
    }

    private static func records(_ name: String) throws -> [[String]] {
        // SwiftPM's generated accessor looks beside the main executable bundle,
        // while a distributed macOS app keeps resources in Contents/Resources.
        let embedded = Bundle.main.resourceURL?.appendingPathComponent("TrisolarisCalendar_SimulationCore.bundle")
        let resourceBundle = embedded.flatMap { Bundle(url: $0) } ?? Bundle.module
        guard let url = resourceBundle.url(forResource: name, withExtension: "dat") else {
            throw ObservedSystemError.missingResource(name)
        }
        return try String(contentsOf: url, encoding: .utf8).split(whereSeparator: \.isNewline)
            .map { $0.split(whereSeparator: \.isWhitespace).map(String.init) }
    }
}
