import Foundation

public enum Astronomy {
    /// AU³ / (solar mass · day²); masses and distances use this consistent dynamical convention.
    public static let gravitationalConstant = 2.959122082855911e-4
    public static let solarRadiusAU = 0.004650467260962157
    public static let earthRadiusAU = 0.000042587504556
    public static let earthMassSolar = 0.0000030034896
    public static let solarFluxAtEarth = 1361.166465408575
    public static let stefanBoltzmann = 5.670374419e-8
}

public struct Vector3: Codable, Sendable, Hashable {
    public var x: Double
    public var y: Double
    public var z: Double
    public init(_ x: Double = 0, _ y: Double = 0, _ z: Double = 0) { self.x = x; self.y = y; self.z = z }
    public static let zero = Vector3()
    public var squaredLength: Double { x*x + y*y + z*z }
    public var length: Double { sqrt(squaredLength) }
    public var isFinite: Bool { x.isFinite && y.isFinite && z.isFinite }
    public static func + (a: Self, b: Self) -> Self { Self(a.x+b.x, a.y+b.y, a.z+b.z) }
    public static func - (a: Self, b: Self) -> Self { Self(a.x-b.x, a.y-b.y, a.z-b.z) }
    public static prefix func - (a: Self) -> Self { Self(-a.x, -a.y, -a.z) }
    public static func * (a: Self, b: Double) -> Self { Self(a.x*b, a.y*b, a.z*b) }
    public static func / (a: Self, b: Double) -> Self { a * (1/b) }
    public func dot(_ b: Self) -> Double { x*b.x + y*b.y + z*b.z }
    public func cross(_ b: Self) -> Self { Self(y*b.z-z*b.y, z*b.x-x*b.z, x*b.y-y*b.x) }
}

public enum BodyKind: String, Codable, Sendable, CaseIterable { case star, planet }

public struct CelestialBody: Codable, Sendable, Hashable, Identifiable {
    public var id: UUID
    public var name: String
    public var kind: BodyKind
    public var massSolar: Double
    public var radiusAU: Double
    public var luminositySolar: Double
    public var positionAU: Vector3
    public var velocityAUPerDay: Vector3
    public init(id: UUID = UUID(), name: String, kind: BodyKind, massSolar: Double,
                radiusAU: Double, luminositySolar: Double = 0,
                positionAU: Vector3 = .zero, velocityAUPerDay: Vector3 = .zero) {
        self.id = id; self.name = name; self.kind = kind; self.massSolar = massSolar
        self.radiusAU = radiusAU; self.luminositySolar = luminositySolar
        self.positionAU = positionAU; self.velocityAUPerDay = velocityAUPerDay
    }
}

public struct ClimateRules: Codable, Sendable, Hashable {
    public var minimumTemperatureC: Double = 0
    public var maximumTemperatureC: Double = 50
    public var minimumFluxEarth: Double = 0.7
    public var maximumFluxEarth: Double = 1.5
    public var maximumFluxCoefficientOfVariation: Double = 0.20
    public var rollingWindowYears: Double = 0.1
    public var minimumStableYears: Double = 0.1
    public var albedo: Double = 0.3
    public var greenhouseOffsetK: Double = 33
    public var thermalResponseDays: Double = 30
    public init() {}
    public func equilibriumTemperatureC(fluxEarth: Double) -> Double {
        pow(max(0, fluxEarth) * Astronomy.solarFluxAtEarth * (1-albedo) / (4*Astronomy.stefanBoltzmann), 0.25) + greenhouseOffsetK - 273.15
    }
}

public struct NumericalSettings: Codable, Sendable, Hashable {
    public var tolerance: Double = 1e-9
    public var samplesPerYear: Int = 256
    public init(tolerance: Double = 1e-9, samplesPerYear: Int = 256) {
        self.tolerance = tolerance; self.samplesPerYear = samplesPerYear
    }
    public static let strict = NumericalSettings(tolerance: 1e-11, samplesPerYear: 1024)
}

public struct Scenario: Codable, Sendable, Hashable, Identifiable {
    public var id: UUID
    public var name: String
    public var bodies: [CelestialBody]
    public var referenceStarID: UUID
    public var referenceDistanceAU: Double
    public var durationYears: Int
    public var climateRules: ClimateRules
    public var numerics: NumericalSettings
    public var randomSeed: UInt64?
    public var notes: String
    public init(id: UUID = UUID(), name: String, bodies: [CelestialBody], referenceStarID: UUID,
                referenceDistanceAU: Double = 1, durationYears: Int = 10_000,
                climateRules: ClimateRules = ClimateRules(), numerics: NumericalSettings = NumericalSettings(),
                randomSeed: UInt64? = nil, notes: String = "") {
        self.id = id; self.name = name; self.bodies = bodies; self.referenceStarID = referenceStarID
        self.referenceDistanceAU = referenceDistanceAU; self.durationYears = durationYears
        self.climateRules = climateRules; self.numerics = numerics; self.randomSeed = randomSeed; self.notes = notes
    }
    public var planet: CelestialBody? { bodies.first { $0.kind == .planet } }
    public var referenceStar: CelestialBody? { bodies.first { $0.id == referenceStarID && $0.kind == .star } }
    /// Recomputed only when configuring a new run. Running engines freeze this duration.
    public var standardYearDays: Double {
        guard let star = referenceStar else { return .nan }
        return 2 * .pi * sqrt(pow(referenceDistanceAU, 3) / (Astronomy.gravitationalConstant * (star.massSolar + (planet?.massSolar ?? 0))))
    }
    public func validationIssues() -> [ValidationIssue] {
        var issues: [ValidationIssue] = []
        func reject(_ condition: Bool, _ message: String) { if condition { issues.append(ValidationIssue(message)) } }
        reject(bodies.filter { $0.kind == .star }.count != 3, "必须恰好包含三颗恒星。")
        reject(bodies.filter { $0.kind == .planet }.count > 1, "最多添加一颗行星。")
        reject(Set(bodies.map(\.id)).count != bodies.count, "天体标识不能重复。")
        reject(referenceStar == nil, "请选择有效的参考恒星。")
        reject(!referenceDistanceAU.isFinite || referenceDistanceAU <= 0, "参考距离必须是正数。")
        reject(durationYears < 1 || durationYears > 100_000, "历法年数必须为 1 至 100000。")
        reject(!numerics.tolerance.isFinite || numerics.tolerance < 1e-14 || numerics.tolerance > 1e-7, "积分容差必须在 1e-14 至 1e-7 之间。")
        reject(numerics.samplesPerYear < 128 || numerics.samplesPerYear > 16384, "每年采样数必须为 128 至 16384。")
        for body in bodies {
            reject(!body.massSolar.isFinite || body.massSolar <= 0, "\(body.name)：质量必须是正数。")
            reject(!body.radiusAU.isFinite || body.radiusAU <= 0, "\(body.name)：半径必须是正数。")
            reject(!body.luminositySolar.isFinite || body.luminositySolar < 0 || (body.kind == .star && body.luminositySolar == 0), "\(body.name)：恒星光度必须为正数。")
            reject(!body.positionAU.isFinite || !body.velocityAUPerDay.isFinite, "\(body.name)：位置和速度必须是有限数值。")
        }
        for i in bodies.indices { for j in bodies.indices where j > i {
            reject((bodies[i].positionAU-bodies[j].positionAU).length <= bodies[i].radiusAU+bodies[j].radiusAU,
                   "\(bodies[i].name)与\(bodies[j].name)的初始位置发生重叠。")
        } }
        let c = climateRules
        let finite = [c.minimumTemperatureC,c.maximumTemperatureC,c.minimumFluxEarth,c.maximumFluxEarth,c.maximumFluxCoefficientOfVariation,c.rollingWindowYears,c.minimumStableYears,c.albedo,c.greenhouseOffsetK,c.thermalResponseDays].allSatisfy(\.isFinite)
        reject(!finite, "气候参数必须是有限数值。")
        reject(c.minimumTemperatureC >= c.maximumTemperatureC || c.minimumTemperatureC <= -273.15, "适宜温度上下限无效。")
        reject(c.minimumFluxEarth < 0 || c.minimumFluxEarth >= c.maximumFluxEarth, "适宜辐照上下限无效。")
        reject(c.albedo < 0 || c.albedo >= 1, "反照率必须在 0（含）至 1（不含）之间。")
        reject(c.greenhouseOffsetK < 0 || c.thermalResponseDays <= 0, "温室增温不得为负，热响应时间必须为正数。")
        reject(c.rollingWindowYears <= 0 || c.minimumStableYears < 0 || c.maximumFluxCoefficientOfVariation < 0,
               "稳定判据的窗口必须为正，持续时间和波动阈值不得为负。")
        reject(!standardYearDays.isFinite || standardYearDays <= 0, "无法由参考参数计算标准年。")
        return issues
    }
}

public struct ValidationIssue: Codable, Sendable, Hashable, Identifiable {
    public var message: String
    public var id: String { message }
    public init(_ message: String) { self.message = message }
}

public enum SimulationError: Error, LocalizedError, Sendable {
    case invalidScenario([String]), engine(String), invalidCheckpoint(String), invalidTime
    public var errorDescription: String? {
        switch self {
        case .invalidScenario(let messages): return messages.joined(separator: "\n")
        case .engine(let message), .invalidCheckpoint(let message): return message
        case .invalidTime: return "模拟时间必须有限，且不早于当前时刻。"
        }
    }
}

public struct ConservationDiagnostics: Codable, Sendable, Hashable {
    public var energy: Double
    public var angularMomentum: Vector3
    public var normalizedEnergyError: Double
    public var normalizedAngularMomentumError: Double
    public var centerOfMassPositionAU: Vector3
    public var centerOfMassVelocityAUPerDay: Vector3
    public var minimumSeparationAU: Double
}

public struct SimulationSnapshot: Codable, Sendable, Hashable {
    public var timeDays: Double
    public var bodies: [CelestialBody]
    public var fluxEarth: Double?
    public var temperatureC: Double?
    public var fluxCoefficientOfVariation: Double?
    public var diagnostics: ConservationDiagnostics
}

public enum EpochKind: String, Codable, Sendable, CaseIterable { case stable, chaotic }
public struct EpochInterval: Codable, Sendable, Hashable, Identifiable {
    public var startDays: Double
    public var endDays: Double
    public var kind: EpochKind
    public var id: Double { startDays }
}
public struct CalendarYear: Codable, Sendable, Hashable, Identifiable {
    public var year: Int
    public var startDays: Double
    public var endDays: Double
    public var kind: EpochKind
    public var stableFraction: Double
    public var minimumTemperatureC: Double
    public var maximumTemperatureC: Double
    public var minimumFluxEarth: Double
    public var maximumFluxEarth: Double
    public var isComplete: Bool
    public var id: Int { year }
}
public enum RunStatus: String, Codable, Sendable { case ready, running, completed, collision, escaped, failed }
public struct SimulationEvent: Codable, Sendable, Hashable, Identifiable {
    public var id: UUID = UUID()
    public var timeDays: Double
    public var message: String
    public var bodyIDs: [UUID] = []
}
public struct SimulationProgress: Codable, Sendable, Hashable {
    public var timeDays: Double
    public var targetDays: Double
    public var completedYears: Int
    public var requestedYears: Int
    public var status: RunStatus
    public var fraction: Double { targetDays > 0 ? min(1, max(0, timeDays/targetDays)) : 0 }
}
public struct CalendarResult: Codable, Sendable, Hashable {
    public var scenario: Scenario
    public var standardYearDays: Double
    public var years: [CalendarYear]
    public var intervals: [EpochInterval]
    public var events: [SimulationEvent]
    /// Bounded display samples, independent of the denser climate integration samples.
    public var snapshots: [SimulationSnapshot]
    public var progress: SimulationProgress
    public var finalSnapshot: SimulationSnapshot
    public var engineVersion: String
    public var calculatedThroughDays: Double { finalSnapshot.timeDays }
}
