import Foundation
import Testing
@testable import SimulationCore

@Suite("真实半人马座观测数据与初值")
struct AlphaCentauriTests {
    @Test("真实三星导入可附实验行星并实际生成历法")
    func importedScenarioCanRunCalendar() throws {
        var scenario = AlphaCentauriCatalog.scenarioWithExperimentalPlanet()
        scenario.durationYears = 1
        #expect(scenario.validationIssues().isEmpty)
        #expect(scenario.bodies.filter { $0.kind == .star }.count == 3)
        let planet = try #require(scenario.planet)
        #expect(planet.name.contains("实验行星"))
        #expect(abs((planet.positionAU - scenario.bodies[0].positionAU).length - scenario.referenceDistanceAU) < 1e-10)
        let calendar = try CalendarSimulation(scenario: scenario)
        while calendar.progress.status == .ready || calendar.progress.status == .running {
            try calendar.advance(maxSamples: 512)
        }
        #expect(calendar.progress.status == .completed)
        #expect(calendar.result.years.count == 1)
        #expect(calendar.result.years[0].isComplete)
    }

    @Test("公开观测表完整读取且保留单位、误差、原始时间和仪器")
    func publishedTables() throws {
        let rows = try AlphaCentauriCatalog.observations()
        #expect(rows.count == 18_113)
        #expect(Set(rows.map(\.id)).count == rows.count)
        #expect(rows.filter { $0.kind == .positionAngle }.count == 106)
        #expect(rows.filter { $0.kind == .separation }.count == 106)
        #expect(rows.filter { $0.kind == .radialVelocity }.count == 17_567)
        #expect(rows.filter { $0.kind == .relativeRadialVelocity }.count == 334)
        #expect(rows.first?.epochJulianYear == 1940.19)
        let firstHARPS = try #require(rows.first { $0.id == "ab-harps-0" })
        #expect(firstHARPS.value == -22.73789)
        #expect(firstHARPS.uncertainty == 0.00201)
        #expect(firstHARPS.unit == "km/s")
        #expect(abs(firstHARPS.epochJulianYear - 2004.09271151266) < 1e-9)
        #expect(firstHARPS.detail.contains("53039.36288"))
        let firstProxima = try #require(rows.first { $0.id == "proxima-rv-0" })
        #expect(firstProxima.value == 3.41)
        #expect(firstProxima.uncertainty == 0.60)
        #expect(firstProxima.unit == "m/s")
        #expect(firstProxima.detail.contains("UVES"))
        #expect(firstProxima.detail.contains("1634.731"))
        #expect(abs(firstProxima.epochJulianYear - 2000.24567008898) < 1e-9)
        let sourceIDs = Set(AlphaCentauriCatalog.sources.map(\.id))
        #expect(rows.allSatisfy { sourceIDs.contains($0.sourceID) && $0.value.isFinite && ($0.uncertainty ?? -1) > 0 })
    }

    @Test("三星在同一质心参考系，重现论文外轨道距离速度且不虚构行星")
    func physicalInitialState() throws {
        let scenario = AlphaCentauriCatalog.initialScenario()
        #expect(scenario.validationIssues().isEmpty)
        #expect(scenario.bodies.count == 3)
        #expect(scenario.planet == nil)
        let bodies = scenario.bodies
        let mAB = bodies[0].massSolar + bodies[1].massSolar
        let comAB = (bodies[0].positionAU * bodies[0].massSolar + bodies[1].positionAU * bodies[1].massSolar) / mAB
        let velocityAB = (bodies[0].velocityAUPerDay * bodies[0].massSolar + bodies[1].velocityAUPerDay * bodies[1].massSolar) / mAB
        let separation = (bodies[2].positionAU - comAB).length
        let relativeVelocity = (bodies[2].velocityAUPerDay - velocityAB).length * 149_597_870.7 / 86400
        #expect(abs(separation - 12_947) < 3)
        #expect(abs(relativeVelocity - 0.273) < 0.001)
        let weightedPosition = bodies.reduce(Vector3.zero) { $0 + $1.positionAU * $1.massSolar }
        let momentum = bodies.reduce(Vector3.zero) { $0 + $1.velocityAUPerDay * $1.massSolar }
        #expect(weightedPosition.length < 1e-10)
        #expect(momentum.length < 1e-16)
        let relativeEnergy = pow(relativeVelocity * 86400 / 149_597_870.7, 2) / 2
            - Astronomy.gravitationalConstant * (mAB + bodies[2].massSolar) / separation
        #expect(relativeEnergy < 0)
        let engine = try NBodySimulation(scenario: scenario)
        try engine.integrate(toDays: 80 * 365.25)
        #expect(engine.snapshot.bodies.allSatisfy { $0.positionAU.isFinite && $0.velocityAUPerDay.isFinite })
        #expect(engine.snapshot.diagnostics.normalizedEnergyError < 1e-8)
    }

    @Test("轨道旋转投影匹配2016实际天体测量，避免升交点或近心点镜像")
    func orbitalOrientationMatchesMeasurement() {
        let state = AlphaCentauriCatalog.innerBinaryRelativeState(epochJulianYear: 2016.1893)
        let ra = (14 + 39.0 / 60 + 40.2068 / 3600) * 15 * Double.pi / 180
        let dec = -(60 + 50.0 / 60 + 13.673 / 3600) * Double.pi / 180
        let east = AlphaCentauriCatalog.equatorialToGalactic(Vector3(-sin(ra), cos(ra), 0))
        let north = AlphaCentauriCatalog.equatorialToGalactic(Vector3(-cos(ra) * sin(dec), -sin(ra) * sin(dec), cos(dec)))
        let x = state.position.dot(east), y = state.position.dot(north)
        let pa = (atan2(x, y) * 180 / .pi + 360).truncatingRemainder(dividingBy: 360)
        let separation = hypot(x, y) * 0.74717
        // Kervella 2016 measurement, also archived in Akeson 2021 Table 6.
        #expect(abs(pa - 305.19) < 0.30)
        #expect(abs(separation - 4.013) < 0.020)
    }
}
