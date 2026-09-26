import Foundation
import CRebound
import CryptoKit

/// A synchronous, exclusively owned engine. Never use one instance from concurrent tasks.
public final class NBodySimulation {
    public static let engineVersion = "REBOUND 4.4.11 · IAS15 / PRS23"
    public let scenario: Scenario
    public let standardYearDays: Double
    public private(set) var status: RunStatus = .ready
    public private(set) var collisionBodyIDs: [UUID] = []
    public private(set) var escapeEvent: SimulationEvent?
    private var handle: UnsafeMutablePointer<reb_simulation>
    private var baseline: ConservationBaseline
    private var escapeDetector: EscapeDetector

    public init(scenario: Scenario, validate: Bool = true) throws {
        if validate {
            let issues = scenario.validationIssues()
            guard issues.isEmpty else { throw SimulationError.invalidScenario(issues.map(\.message)) }
        }
        guard !scenario.bodies.isEmpty, scenario.bodies.allSatisfy({ $0.massSolar > 0 && $0.positionAU.isFinite && $0.velocityAUPerDay.isFinite }),
              let engine = reb_simulation_create() else { throw SimulationError.engine("无法建立有效的引力模拟。") }
        self.scenario = scenario; standardYearDays = scenario.standardYearDays; handle = engine
        baseline = ConservationBaseline(bodies: scenario.bodies)
        escapeDetector = EscapeDetector(scenario: scenario)
        engine.pointee.G = Astronomy.gravitationalConstant
        engine.pointee.integrator = REB_INTEGRATOR_IAS15
        engine.pointee.ri_ias15.epsilon = scenario.numerics.tolerance
        engine.pointee.ri_ias15.min_dt = 0
        engine.pointee.ri_ias15.adaptive_mode = REB_IAS15_PRS23
        engine.pointee.exact_finish_time = 1
        engine.pointee.dt = min(0.1, standardYearDays.isFinite ? standardYearDays/Double(scenario.numerics.samplesPerYear) : 0.1)
        engine.pointee.save_messages = 1
        for body in scenario.bodies {
            var particle = reb_particle()
            particle.m = body.massSolar; particle.r = body.radiusAU
            particle.x = body.positionAU.x; particle.y = body.positionAU.y; particle.z = body.positionAU.z
            particle.vx = body.velocityAUPerDay.x; particle.vy = body.velocityAUPerDay.y; particle.vz = body.velocityAUPerDay.z
            particle.last_collision = -1
            reb_simulation_add(engine, particle)
        }
        trisolaris_rebound_set_collision_halt(engine)
    }

    private init(saved: NBodyCheckpoint) throws {
        guard saved.version == 1, saved.engineVersion == Self.engineVersion else { throw SimulationError.invalidCheckpoint("检查点的积分器版本不兼容。") }
        guard saved.archive.count >= 64, saved.archive.count < 16_777_216,
              Self.digest(saved.archive) == saved.archiveDigest else { throw SimulationError.invalidCheckpoint("积分检查点校验失败，文件可能已损坏。") }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString+".rebound")
        defer { try? FileManager.default.removeItem(at: url) }
        try saved.archive.write(to: url)
        var path = url.path.utf8CString
        guard let engine = path.withUnsafeMutableBufferPointer({ reb_simulation_create_from_file($0.baseAddress, -1) }) else {
            throw SimulationError.invalidCheckpoint("REBOUND 检查点无法读取。")
        }
        guard Int(engine.pointee.N) == saved.scenario.bodies.count else {
            reb_simulation_free(engine); throw SimulationError.invalidCheckpoint("检查点的天体数不一致。")
        }
        handle = engine; scenario = saved.scenario; standardYearDays = saved.standardYearDays
        baseline = saved.baseline; status = saved.status; collisionBodyIDs = saved.collisionBodyIDs
        escapeDetector = saved.escapeDetector ?? EscapeDetector(scenario: saved.scenario)
        escapeEvent = saved.escapeEvent
        engine.pointee.save_messages = 1
        // Function pointers are intentionally not serialized by REBOUND.
        trisolaris_rebound_set_collision_halt(engine)
    }
    public convenience init(checkpointData: Data) throws {
        try self.init(saved: JSONDecoder().decode(NBodyCheckpoint.self, from: checkpointData))
    }
    private init(copying original: NBodySimulation) throws {
        guard let copy = trisolaris_rebound_copy(original.handle) else { throw SimulationError.engine("无法创建积分器检查点。") }
        handle = copy; scenario = original.scenario; standardYearDays = original.standardYearDays
        baseline = original.baseline; status = original.status; collisionBodyIDs = original.collisionBodyIDs
        escapeDetector = original.escapeDetector; escapeEvent = original.escapeEvent
        trisolaris_rebound_set_collision_halt(copy)
    }
    func fork() throws -> NBodySimulation { try NBodySimulation(copying: self) }
    deinit { reb_simulation_free(handle) }
    public var timeDays: Double { handle.pointee.t }
    public var snapshot: SimulationSnapshot {
        let bodies = currentBodies()
        return SimulationSnapshot(timeDays: timeDays, bodies: bodies, fluxEarth: Self.flux(for: bodies), temperatureC: nil,
                                  fluxCoefficientOfVariation: nil, diagnostics: baseline.diagnostics(bodies: bodies))
    }
    /// Live orbit snapshots deliberately leave temperature nil. Only the climate engine evolves thermal inertia.
    @discardableResult public func integrate(toDays target: Double) throws -> SimulationSnapshot {
        guard target.isFinite, target >= timeDays else { throw SimulationError.invalidTime }
        if status == .collision || status == .escaped || target == timeDays { return snapshot }
        guard status != .failed else { throw SimulationError.engine("积分器已停止，请重置模拟。") }
        status = .running
        while timeDays < target {
            // Even a large caller jump must observe the sustained far-field condition over time.
            let checkStep = standardYearDays.isFinite && standardYearDays > 0 ? standardYearDays/4 : target-timeDays
            let next = min(target,timeDays+checkStep)
            let outcome = reb_simulation_integrate(handle, next)
            if outcome == REB_STATUS_COLLISION {
                status = .collision
                collisionBodyIDs = scenario.bodies.indices.compactMap { i in
                    abs(handle.pointee.particles[i].last_collision-timeDays) < 1e-8 ? scenario.bodies[i].id : nil
                }
                break
            } else if outcome != REB_STATUS_SUCCESS {
                status = .failed
                throw SimulationError.engine("引力积分停止（REBOUND 状态 \(outcome.rawValue)）。已计算结果保留。")
            }
            if let event = escapeDetector.check(timeDays: timeDays,bodies: currentBodies()) {
                escapeEvent = event; status = .escaped; break
            }
        }
        let result = snapshot
        guard result.timeDays.isFinite, result.bodies.allSatisfy({ $0.positionAU.isFinite && $0.velocityAUPerDay.isFinite }), result.diagnostics.energy.isFinite else {
            status = .failed; throw SimulationError.engine("引力积分产生非有限数值，已停止。")
        }
        return result
    }
    public func checkpointData() throws -> Data {
        var pointer: UnsafeMutablePointer<CChar>?
        var count = 0
        reb_simulation_save_to_stream(handle, &pointer, &count)
        guard let pointer, count > 0 else { throw SimulationError.engine("无法保存 REBOUND 完整积分状态。") }
        defer { free(pointer) }
        let archive = Data(bytes: pointer, count: count)
        return try JSONEncoder().encode(NBodyCheckpoint(version: 1, engineVersion: Self.engineVersion,
            scenario: scenario, standardYearDays: standardYearDays, baseline: baseline, status: status,
            collisionBodyIDs: collisionBodyIDs, escapeDetector: escapeDetector, escapeEvent: escapeEvent,
            archive: archive, archiveDigest: Self.digest(archive)))
    }
    private static func digest(_ data: Data) -> String { SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined() }
    /// Sampling follows the local crossing/free-fall scales and becomes finer near every pair.
    public func recommendedSampleStep(maximumDays: Double) -> Double {
        let bodies = currentBodies()
        var step = maximumDays
        for i in bodies.indices { for j in bodies.indices where j > i {
            let r = (bodies[i].positionAU-bodies[j].positionAU).length
            let v = (bodies[i].velocityAUPerDay-bodies[j].velocityAUPerDay).length
            let dynamical = sqrt(r*r*r/(Astronomy.gravitationalConstant*(bodies[i].massSolar+bodies[j].massSolar)))
            step = min(step, 0.04*dynamical)
            if v > 0 { step = min(step, 0.04*r/v) }
        } }
        return max(step, max(abs(timeDays)*Double.ulpOfOne*16, 1e-10))
    }
    public static func flux(for bodies: [CelestialBody]) -> Double? {
        guard let planet = bodies.first(where: { $0.kind == .planet }) else { return nil }
        return bodies.filter { $0.kind == .star }.reduce(0) { total, star in
            total + star.luminositySolar/max((star.positionAU-planet.positionAU).squaredLength, 1e-30)
        }
    }
    private func currentBodies() -> [CelestialBody] {
        scenario.bodies.enumerated().map { i, original in
            var body = original
            let p = handle.pointee.particles[i]
            body.positionAU = Vector3(p.x,p.y,p.z); body.velocityAUPerDay = Vector3(p.vx,p.vy,p.vz)
            return body
        }
    }
}

private struct NBodyCheckpoint: Codable {
    var version: Int
    var engineVersion: String
    var scenario: Scenario
    var standardYearDays: Double
    var baseline: ConservationBaseline
    var status: RunStatus
    var collisionBodyIDs: [UUID]
    var escapeDetector: EscapeDetector?
    var escapeEvent: SimulationEvent?
    var archive: Data
    var archiveDigest: String
}

private struct ConservationBaseline: Codable {
    var energy: Double
    var angularMomentum: Vector3
    var energyScale: Double
    var angularMomentumScale: Double
    init(bodies: [CelestialBody]) {
        let values = Self.values(bodies)
        energy = values.kinetic+values.potential; angularMomentum = values.angular
        energyScale = max(values.kinetic+abs(values.potential), 1e-30)
        angularMomentumScale = max(bodies.reduce(0) { $0+$1.massSolar*$1.positionAU.length*$1.velocityAUPerDay.length }, 1e-30)
    }
    func diagnostics(bodies: [CelestialBody]) -> ConservationDiagnostics {
        let values = Self.values(bodies), currentEnergy = values.kinetic+values.potential
        let totalMass = bodies.reduce(0) { $0+$1.massSolar }
        let com = bodies.reduce(Vector3.zero) { $0+$1.positionAU*$1.massSolar }/totalMass
        let velocity = bodies.reduce(Vector3.zero) { $0+$1.velocityAUPerDay*$1.massSolar }/totalMass
        return ConservationDiagnostics(energy: currentEnergy, angularMomentum: values.angular,
            normalizedEnergyError: abs(currentEnergy-energy)/energyScale,
            normalizedAngularMomentumError: (values.angular-angularMomentum).length/angularMomentumScale,
            centerOfMassPositionAU: com, centerOfMassVelocityAUPerDay: velocity, minimumSeparationAU: values.minimumSeparation)
    }
    private static func values(_ bodies: [CelestialBody]) -> (kinetic: Double, potential: Double, angular: Vector3, minimumSeparation: Double) {
        var kinetic = 0.0, potential = 0.0, angular = Vector3.zero, minimum = Double.greatestFiniteMagnitude
        for i in bodies.indices {
            let body = bodies[i]
            kinetic += 0.5*body.massSolar*body.velocityAUPerDay.squaredLength
            angular = angular+body.positionAU.cross(body.velocityAUPerDay)*body.massSolar
            for j in bodies.indices where j > i {
                let r = (body.positionAU-bodies[j].positionAU).length
                minimum = min(minimum,r)
                potential -= Astronomy.gravitationalConstant*body.massSolar*bodies[j].massSolar/max(r,1e-30)
            }
        }
        return (kinetic,potential,angular,minimum)
    }
}
