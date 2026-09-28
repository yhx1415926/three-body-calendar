import Foundation
import Testing
@testable import SimulationCore

@Suite("多恒星与多行星")
struct MultipleBodyTests {
    @Test("数量边界和混合星系生成均合法", arguments: [(1,0),(1,63),(64,0),(4,3),(3,2)])
    func counts(pair: (Int,Int)) throws {
        let scenario = try Presets.randomSystem(seed: 42,starCount: pair.0,planetCount: pair.1)
        #expect(scenario.bodies.filter { $0.kind == .star }.count == pair.0)
        #expect(scenario.bodies.filter { $0.kind == .planet }.count == pair.1)
        #expect(scenario.validationIssues().isEmpty)
        let engine = try NBodySimulation(scenario: scenario)
        let snapshot = try engine.integrate(toDays: 0.01)
        #expect(snapshot.bodies.count == pair.0+pair.1)
        #expect(snapshot.diagnostics.normalizedEnergyError < 1e-10)
        #expect(snapshot.diagnostics.centerOfMassPositionAU.length < 1e-12)
        #expect(snapshot.diagnostics.centerOfMassVelocityAUPerDay.length < 1e-14)
        #expect((snapshot.fluxEarth != nil) == (pair.1 > 0))
    }

    @Test("种子可重现，非法数量与无法放置的参数被拒绝")
    func randomReproducibilityAndLimits() throws {
        let first = try Presets.randomSystem(seed: 123456,starCount: 5,planetCount: 9)
        let second = try Presets.randomSystem(seed: 123456,starCount: 5,planetCount: 9)
        #expect(first == second)
        var oversized = first
        oversized.bodies = Array(repeating: first.bodies[0],count: Scenario.maximumBodyCount+1)
        #expect(oversized.validationIssues().contains { $0.message.contains("64") })
        #expect(throws: (any Error).self) { try Presets.randomSystem(seed: 1,starCount: 0,planetCount: 1) }
        #expect(throws: (any Error).self) { try Presets.randomSystem(seed: 1,starCount: 64,planetCount: 1) }
        #expect(throws: (any Error).self) { try Presets.randomSystem(seed: 1,starCount: 1,planetCount: -1) }
        #expect(throws: (any Error).self) { try Presets.randomSystem(seed: 1,starCount: Int.max,planetCount: 0) }
        #expect(throws: (any Error).self) { try Presets.randomSystem(seed: 1,starCount: 2,planetCount: 0,spatialScaleAU: 1e-9) }
        #expect(throws: (any Error).self) { try Presets.randomSystem(seed: 1,starCount: 2,planetCount: 0,virialRatio: .nan) }
    }

    @Test("旧项目缺省选择首颗行星，新项目保留历法目标")
    func selectionPersistence() throws {
        var scenario = try Presets.randomSystem(seed: 4,starCount: 2,planetCount: 2)
        let planets = scenario.bodies.filter { $0.kind == .planet }
        scenario.calendarPlanetID = planets[1].id
        let decoded = try JSONDecoder().decode(Scenario.self,from: JSONEncoder().encode(scenario))
        #expect(decoded.planet?.id == planets[1].id)
        var legacy = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(scenario)) as? [String:Any])
        legacy.removeValue(forKey: "calendarPlanetID")
        let old = try JSONDecoder().decode(Scenario.self,from: JSONSerialization.data(withJSONObject: legacy))
        #expect(old.calendarPlanetID == nil)
        #expect(old.planet?.id == planets[0].id)
        scenario.calendarPlanetID = scenario.referenceStarID
        #expect(scenario.planet == nil)
        #expect(!scenario.validationIssues().isEmpty)
        #expect(throws: (any Error).self) { try NBodySimulation(scenario: scenario) }
    }

    @Test("辐照与标准年针对所选行星，第二颗行星也对恒星施加引力")
    func selectedFluxAndGravity() throws {
        let star = CelestialBody(name: "主星",kind: .star,massSolar: 1,radiusAU: Astronomy.solarRadiusAU,luminositySolar: 1)
        let inner = CelestialBody(name: "内行星",kind: .planet,massSolar: 0.1,radiusAU: Astronomy.earthRadiusAU,positionAU: Vector3(1,0,0))
        let outer = CelestialBody(name: "外行星",kind: .planet,massSolar: 0.2,radiusAU: Astronomy.earthRadiusAU,positionAU: Vector3(-2,0,0))
        let scenario = Scenario(name: "多行星引力检验",bodies: [star,inner,outer],referenceStarID: star.id,calendarPlanetID: outer.id)
        let engine = try NBodySimulation(scenario: scenario)
        #expect(engine.snapshot.fluxEarth == 0.25)
        #expect(NBodySimulation.flux(for: scenario.bodies) == 1)
        #expect(abs(scenario.standardYearDays-2 * .pi/sqrt(Astronomy.gravitationalConstant*1.2)) < 1e-12)
        let step = 0.001
        let state = try engine.integrate(toDays: step)
        let expectedAcceleration = Astronomy.gravitationalConstant*(0.1-0.2/4)
        #expect(abs(state.bodies[0].velocityAUPerDay.x/step-expectedAcceleration) < 1e-12)
    }

    @Test("历法热响应与纪元分类使用所选的第二颗行星")
    func selectedCalendar() throws {
        let star = CelestialBody(name: "主星",kind: .star,massSolar: 1,radiusAU: Astronomy.solarRadiusAU,luminositySolar: 1)
        let inner = CelestialBody(name: "内行星",kind: .planet,massSolar: Astronomy.earthMassSolar,radiusAU: Astronomy.earthRadiusAU,
            positionAU: Vector3(1,0,0),velocityAUPerDay: Vector3(0,sqrt(Astronomy.gravitationalConstant),0))
        let outer = CelestialBody(name: "外行星",kind: .planet,massSolar: Astronomy.earthMassSolar,radiusAU: Astronomy.earthRadiusAU,
            positionAU: Vector3(-2,0,0),velocityAUPerDay: Vector3(0,-sqrt(Astronomy.gravitationalConstant/2),0))
        let scenario = Scenario(name: "双行星历法",bodies: [star,inner,outer],referenceStarID: star.id,durationYears: 1,calendarPlanetID: outer.id)
        let calendar = try CalendarSimulation(scenario: scenario)
        for _ in 0..<20 where calendar.progress.status == .ready || calendar.progress.status == .running {
            try calendar.advance(maxSamples: 256)
        }
        #expect(calendar.progress.status == .completed)
        let year = try #require(calendar.result.years.first)
        #expect(year.kind == .chaotic && year.stableFraction == 0)
        #expect(abs(year.minimumFluxEarth-0.25) < 0.001)
        #expect(abs(year.maximumFluxEarth-0.25) < 0.001)
    }

    @Test("仅历法目标触发逃逸，目标与确认历史保存在检查点")
    func selectedEscapeAndCheckpoint() throws {
        var scenario = Presets.stableHierarchy()
        let firstPlanet = try #require(scenario.planet)
        var escaping = firstPlanet
        escaping.id = UUID(); escaping.name = "远方行星"
        escaping.positionAU = Vector3(10000,0,0); escaping.velocityAUPerDay = Vector3(1,0,0)
        scenario.bodies.append(escaping)
        var detector = EscapeDetector(scenario: scenario)
        #expect(detector.check(timeDays: 0,bodies: scenario.bodies) == nil)
        #expect(detector.check(timeDays: 6*scenario.standardYearDays,bodies: scenario.bodies) == nil)
        scenario.calendarPlanetID = escaping.id
        let engine = try NBodySimulation(scenario: scenario)
        try engine.integrate(toDays: 3*scenario.standardYearDays)
        let resumed = try NBodySimulation(checkpointData: engine.checkpointData())
        try resumed.integrate(toDays: 10*scenario.standardYearDays)
        #expect(resumed.status == .escaped)
        #expect(resumed.escapeEvent?.bodyIDs == [escaping.id])
        #expect(resumed.scenario.planet?.id == escaping.id)
    }

    @Test("旧单行星检查点兼容新增目标字段")
    func legacyCheckpoint() throws {
        let engine = try NBodySimulation(scenario: Presets.stableHierarchy())
        try engine.integrate(toDays: 1)
        var object = try #require(JSONSerialization.jsonObject(with: engine.checkpointData()) as? [String:Any])
        var detector = try #require(object["escapeDetector"] as? [String:Any])
        detector.removeValue(forKey: "calendarPlanetID"); object["escapeDetector"] = detector
        let resumed = try NBodySimulation(checkpointData: JSONSerialization.data(withJSONObject: object))
        #expect(resumed.snapshot == engine.snapshot)
        try resumed.integrate(toDays: 2)
        try engine.integrate(toDays: 2)
        #expect(resumed.snapshot == engine.snapshot)
    }
}
