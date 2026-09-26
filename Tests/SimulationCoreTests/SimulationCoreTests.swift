import Foundation
import Testing
@testable import SimulationCore

@Suite("物理与历法验证")
struct SimulationCoreTests {
    private func finish(_ simulation: CalendarSimulation, chunk: Int = 73) throws -> CalendarResult {
        for _ in 0..<100_000 {
            if simulation.progress.status != .ready && simulation.progress.status != .running { return simulation.result }
            try simulation.advance(maxSamples: chunk)
        }
        throw SimulationError.engine("测试模拟未在预期采样预算内完成")
    }

    @Test("稳定四体生成完整历法，按持续时间统计")
    func stableCalendar() throws {
        var configuration = Presets.stableHierarchy(); configuration.durationYears = 3
        let result = try finish(CalendarSimulation(scenario: configuration))
        #expect(result.progress.status == .completed)
        #expect(result.years.count == 3)
        #expect(result.years.allSatisfy { $0.isComplete && $0.kind == .stable && abs($0.stableFraction-1) < 1e-12 })
        #expect(abs(result.intervals.last!.endDays-configuration.standardYearDays*3) < 1e-8)
        #expect(result.finalSnapshot.timeDays >= configuration.standardYearDays*3.099)
        #expect(result.finalSnapshot.diagnostics.normalizedEnergyError < 1e-10)
    }

    @Test("过热阈值产生乱纪元而非伪造稳定")
    func hostileClimate() throws {
        var configuration = Presets.stableHierarchy(); configuration.durationYears = 1
        configuration.climateRules.minimumTemperatureC = 100
        configuration.climateRules.maximumTemperatureC = 200
        let result = try finish(CalendarSimulation(scenario: configuration))
        #expect(result.years.count == 1)
        #expect(result.years[0].kind == .chaotic)
        #expect(result.years[0].stableFraction == 0)
    }

    @Test("窄辐照越界与更密采样的事件时间收敛")
    func thresholdConvergence() throws {
        var configuration = Presets.stableHierarchy(); configuration.durationYears = 1
        configuration.climateRules.maximumFluxEarth = 1.025
        configuration.climateRules.minimumStableYears = 0.03
        let standard = try finish(CalendarSimulation(scenario: configuration))
        configuration.numerics = .strict
        let strict = try finish(CalendarSimulation(scenario: configuration))
        #expect(standard.years[0].kind == .chaotic)
        #expect(standard.years[0].stableFraction > 0 && standard.years[0].stableFraction < 1)
        #expect(standard.intervals.count == strict.intervals.count)
        for (a,b) in zip(standard.intervals,strict.intervals) {
            #expect(abs(a.startDays-b.startDays)/configuration.standardYearDays < 1e-4)
            #expect(abs(a.endDays-b.endDays)/configuration.standardYearDays < 1e-4)
        }
    }

    @Test("完整检查点恢复与连续计算逐位一致")
    func resumeExactly() throws {
        var configuration = Presets.stableHierarchy(); configuration.durationYears = 2
        configuration.climateRules.maximumFluxEarth = 1.02
        let original = try CalendarSimulation(scenario: configuration)
        try original.advance(maxSamples: 217)
        let recovered = try CalendarSimulation(checkpointData: original.checkpointData())
        let uninterrupted = try finish(original, chunk: 31)
        let resumed = try finish(recovered, chunk: 119)
        #expect(uninterrupted.years == resumed.years)
        #expect(uninterrupted.intervals == resumed.intervals)
        #expect(uninterrupted.finalSnapshot == resumed.finalSnapshot)
    }

    @Test("延长计算维持标准年且没有重复年度")
    func extend() throws {
        var configuration = Presets.stableHierarchy(); configuration.durationYears = 1
        let simulation = try CalendarSimulation(scenario: configuration)
        _ = try finish(simulation)
        let year = simulation.standardYearDays
        try simulation.extend(toYears: 3)
        let result = try finish(simulation)
        #expect(result.years.map(\.year) == [1,2,3])
        #expect(result.years.allSatisfy { $0.isComplete && $0.kind == .stable })
        #expect(result.standardYearDays == year)
        let restored = try CalendarSimulation(checkpointData: simulation.checkpointData())
        #expect(restored.result.years == result.years)
    }

    @Test("滑动方差按时间权重，温度具有解析热响应")
    func climateMath() {
        var rules = ClimateRules(); rules.rollingWindowYears = 10
        var climate = ClimateHistory(rules: rules, standardYearDays: 1, initialFlux: 1)
        climate.append(timeDays: 0.1, flux: 3)
        climate.append(timeDays: 1, flux: 3)
        let expected = sqrt((0.1*13/3+0.9*9)-2.9*2.9)/2.9
        #expect(abs(climate.coefficientOfVariation-expected) < 1e-12)
        var thermal = ClimateHistory(rules: rules, standardYearDays: 365, initialFlux: 1)
        let equilibrium = thermal.temperatureC
        thermal.temperatureC += 10
        thermal.append(timeDays: rules.thermalResponseDays, flux: 1)
        #expect(abs(thermal.temperatureC-equilibrium-10/exp(1)) < 1e-12)
    }

    @Test("随机轨道重现且保留质量、光度和半径")
    func reproducibleRandom() {
        let template = Presets.stableHierarchy()
        let a = Presets.random(seed: 123456, template: template, spatialScaleAU: 12, virialRatio: 0.4)
        let b = Presets.random(seed: 123456, template: template, spatialScaleAU: 12, virialRatio: 0.4)
        #expect(a == b)
        #expect(a.bodies.map(\.massSolar) == template.bodies.map(\.massSolar))
        #expect(a.bodies.map(\.radiusAU) == template.bodies.map(\.radiusAU))
        #expect(a.validationIssues().isEmpty)
    }

    @Test("错误参数和损坏检查点被拒绝")
    func invalidInput() throws {
        var configuration = Presets.stableHierarchy()
        configuration.bodies[0].massSolar = .nan
        #expect(!configuration.validationIssues().isEmpty)
        #expect(throws: (any Error).self) { try NBodySimulation(scenario: configuration) }
        #expect(throws: (any Error).self) { try CalendarSimulation(checkpointData: Data("bad archive".utf8)) }
        let simulation = try NBodySimulation(scenario: Presets.stableHierarchy())
        var object = try #require(JSONSerialization.jsonObject(with: simulation.checkpointData()) as? [String: Any])
        object["archiveDigest"] = "corrupt"
        let corrupt = try JSONSerialization.data(withJSONObject: object)
        #expect(throws: (any Error).self) { try NBodySimulation(checkpointData: corrupt) }
    }

    @Test("二体圆轨道与偏心轨道解析基准", arguments: [0.0, 0.6])
    func keplerOrbit(eccentricity: Double) throws {
        let configuration = Self.twoBody(eccentricity: eccentricity)
        let engine = try NBodySimulation(scenario: configuration, validate: false)
        let initial = engine.snapshot
        let period = configuration.standardYearDays
        for i in 1...100 { try engine.integrate(toDays: Double(i)*period) }
        let final = engine.snapshot
        let initialRelative = initial.bodies[1].positionAU-initial.bodies[0].positionAU
        let finalRelative = final.bodies[1].positionAU-final.bodies[0].positionAU
        #expect((finalRelative-initialRelative).length < 1e-7)
        #expect(final.diagnostics.normalizedEnergyError < 1e-11)
        #expect(final.diagnostics.normalizedAngularMomentumError < 1e-11)
    }

    @Test("三体八字的一个周期闭合，零角动量归一化有效")
    func figureEight() throws {
        let configuration = Presets.figureEight(includePlanet: false, scaleAU: 1)
        let engine = try NBodySimulation(scenario: configuration)
        let initial = engine.snapshot
        let period = 6.32591398/sqrt(Astronomy.gravitationalConstant)
        let final = try engine.integrate(toDays: period)
        let maximumError = zip(initial.bodies,final.bodies).map { ($0.positionAU-$1.positionAU).length }.max()!
        #expect(maximumError < 3e-6)
        #expect(final.diagnostics.normalizedAngularMomentumError.isFinite)
        #expect(final.fluxEarth == nil)
    }

    @Test("碰撞终止计算，不生成未来年份")
    func collision() throws {
        var configuration = Presets.stableHierarchy(); configuration.durationYears = 10
        configuration.bodies[0].positionAU = Vector3(-1,0,0)
        configuration.bodies[1].positionAU = Vector3(1,0,0)
        configuration.bodies[0].velocityAUPerDay = Vector3(1,0,0)
        configuration.bodies[1].velocityAUPerDay = Vector3(-1,0,0)
        configuration.bodies[0].radiusAU = 0.1; configuration.bodies[1].radiusAU = 0.1
        configuration.bodies[2].positionAU = Vector3(0,100,0)
        configuration.bodies[3].positionAU = Vector3(-1,2,0)
        let result = try finish(CalendarSimulation(scenario: configuration), chunk: 16)
        #expect(result.progress.status == .collision)
        #expect(result.progress.completedYears == 0)
        #expect(result.years.count <= 1)
        #expect(!result.events.isEmpty)
        #expect(result.finalSnapshot.timeDays < 1)
    }

    static func twoBody(eccentricity e: Double) -> Scenario {
        var star = Presets.stableHierarchy().bodies[0]
        var planet = Presets.stableHierarchy().planet!
        star.positionAU = .zero; star.velocityAUPerDay = .zero
        planet.positionAU = Vector3(1-e,0,0)
        planet.velocityAUPerDay = Vector3(0,sqrt(Astronomy.gravitationalConstant*(star.massSolar+planet.massSolar)*(1+e)/(1-e)),0)
        var bodies = [star,planet]; Presets.recenter(&bodies)
        return Scenario(name: "Kepler validation", bodies: bodies, referenceStarID: star.id)
    }
}
