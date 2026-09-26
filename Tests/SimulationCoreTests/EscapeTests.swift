import Foundation
import Testing
@testable import SimulationCore

@Suite("保守逃逸检测")
struct EscapeTests {
    private func farPlanet(speedAUPerDay: Double = 1) -> Scenario {
        var scenario = Presets.stableHierarchy()
        let p = scenario.bodies.firstIndex { $0.kind == .planet }!
        scenario.bodies[p].positionAU = Vector3(10000,0,0)
        scenario.bodies[p].velocityAUPerDay = Vector3(speedAUPerDay,0,0)
        scenario.durationYears = 30
        return scenario
    }

    @Test("远场正能量必须经过持续确认，瞬时状态不立即停止")
    func sustainedConfirmation() {
        let scenario = farPlanet()
        var detector = EscapeDetector(scenario: scenario)
        #expect(detector.check(timeDays: 0,bodies: scenario.bodies) == nil)
        #expect(detector.check(timeDays: 4*scenario.standardYearDays,bodies: scenario.bodies) == nil)
        #expect(detector.check(timeDays: 6*scenario.standardYearDays,bodies: scenario.bodies) != nil)
    }

    @Test("远处宽束缚轨道即使向外运动也不算逃逸")
    func boundWideOrbit() {
        var scenario = farPlanet(speedAUPerDay: 0)
        let p = scenario.bodies.firstIndex { $0.kind == .planet }!
        let mass = scenario.bodies.filter { $0.kind == .star }.reduce(0) { $0+$1.massSolar }
        let circularSpeed = sqrt(Astronomy.gravitationalConstant*mass/10000)
        scenario.bodies[p].velocityAUPerDay = Vector3(circularSpeed*0.2,circularSpeed*0.8,0)
        var detector = EscapeDetector(scenario: scenario)
        for year in [0,5,100,10000] {
            #expect(detector.check(timeDays: Double(year)*scenario.standardYearDays,bodies: scenario.bodies) == nil)
        }
    }

    @Test("普通稳定行星不会被正质心运动误判")
    func stableOrbitIsNotEscape() {
        let scenario = Presets.stableHierarchy()
        var detector = EscapeDetector(scenario: scenario)
        #expect(detector.check(timeDays: 0,bodies: scenario.bodies) == nil)
        #expect(detector.check(timeDays: 10000*scenario.standardYearDays,bodies: scenario.bodies) == nil)
    }

    @Test("大质量行星的恒星系反冲计入束缚能")
    func massiveBoundPlanet() {
        var scenario = farPlanet(speedAUPerDay: 0)
        let stars = scenario.bodies.indices.filter { scenario.bodies[$0].kind == .star }
        for (offset,index) in stars.enumerated() {
            scenario.bodies[index].massSolar = 1
            scenario.bodies[index].positionAU = Vector3(Double(offset-1),0,0)
            scenario.bodies[index].velocityAUPerDay = .zero
        }
        let p = scenario.bodies.firstIndex { $0.kind == .planet }!
        scenario.bodies[p].massSolar = 1
        // K = 3.6 G/r exceeds the fixed-star escape test (3 G/r), but is still bound
        // to the recoiling three-star system whose relative potential is 4 G/r.
        scenario.bodies[p].velocityAUPerDay = Vector3(sqrt(7.2*Astronomy.gravitationalConstant/10000),0,0)
        var detector = EscapeDetector(scenario: scenario)
        #expect(detector.check(timeDays: 0,bodies: scenario.bodies) == nil)
        #expect(detector.check(timeDays: 10000*scenario.standardYearDays,bodies: scenario.bodies) == nil)
    }

    @Test("条件失效清除待确认状态")
    func conditionResets() {
        let scenario = farPlanet()
        var detector = EscapeDetector(scenario: scenario)
        #expect(detector.check(timeDays: 0,bodies: scenario.bodies) == nil)
        var bound = scenario.bodies
        bound[bound.firstIndex { $0.kind == .planet }!].velocityAUPerDay = .zero
        #expect(detector.check(timeDays: 4*scenario.standardYearDays,bodies: bound) == nil)
        #expect(detector.check(timeDays: 6*scenario.standardYearDays,bodies: scenario.bodies) == nil)
        #expect(detector.check(timeDays: 12*scenario.standardYearDays,bodies: scenario.bodies) != nil)
    }

    @Test("逃逸停止实时积分且确认历史随检查点恢复")
    func integrationAndResume() throws {
        let scenario = farPlanet()
        let engine = try NBodySimulation(scenario: scenario)
        try engine.integrate(toDays: 3*scenario.standardYearDays)
        #expect(engine.status == .running)
        let restored = try NBodySimulation(checkpointData: engine.checkpointData())
        try engine.integrate(toDays: 30*scenario.standardYearDays)
        try restored.integrate(toDays: 30*scenario.standardYearDays)
        #expect(engine.status == .escaped)
        #expect(restored.status == .escaped)
        #expect(engine.timeDays == restored.timeDays)
        #expect(engine.snapshot == restored.snapshot)
        #expect(engine.timeDays < 10*scenario.standardYearDays)
        let stopped = engine.snapshot
        try engine.integrate(toDays: 100*scenario.standardYearDays)
        #expect(engine.snapshot == stopped)
        #expect(engine.escapeEvent != nil)
    }

    @Test("逃逸历法只保留已计算年度，不伪造未来")
    func calendarStops() throws {
        let scenario = farPlanet()
        let calendar = try CalendarSimulation(scenario: scenario)
        for _ in 0..<100 {
            if calendar.progress.status != .ready && calendar.progress.status != .running { break }
            try calendar.advance(maxSamples: 256)
        }
        #expect(calendar.progress.status == .escaped)
        #expect(calendar.result.years.count < scenario.durationYears)
        #expect(calendar.result.events.count == 1)
        #expect(calendar.result.intervals.last!.endDays <= calendar.snapshot.timeDays)
        #expect(throws: (any Error).self) { try calendar.extend(toYears: 50) }
        let restored = try CalendarSimulation(checkpointData: calendar.checkpointData())
        #expect(restored.progress.status == .escaped)
        #expect(restored.result.years == calendar.result.years)
    }

    @Test("重复天体标识在导入引擎前被拒绝")
    func duplicateIdentifiers() {
        var scenario = Presets.stableHierarchy()
        scenario.bodies[1].id = scenario.bodies[0].id
        #expect(scenario.validationIssues().contains { $0.message.contains("标识") })
        #expect(throws: (any Error).self) { try NBodySimulation(scenario: scenario) }
    }

    @Test("用户真实混沌种子在万年前识别逃逸", arguments: [UInt64(7842035361616645170),UInt64(1600056934119823229)])
    func reportedRandomSeeds(seed: UInt64) throws {
        var scenario = Presets.random(seed: seed,template: Presets.stableHierarchy(),spatialScaleAU: 8,virialRatio: 0.4)
        scenario.durationYears = 10000
        let calendar = try CalendarSimulation(scenario: scenario)
        // A scientific regression uses the same dense calendar path, not a coarser orbit playback path.
        for _ in 0..<1250 {
            if calendar.progress.status != .ready && calendar.progress.status != .running { break }
            try calendar.advance(maxSamples: 1024)
        }
        #expect(calendar.progress.status == .escaped)
        #expect(calendar.snapshot.timeDays < 2000*scenario.standardYearDays)
        print("Escape regression seed \(seed): \(calendar.snapshot.timeDays/scenario.standardYearDays) years, \(calendar.progress.status.rawValue)")
    }
}
