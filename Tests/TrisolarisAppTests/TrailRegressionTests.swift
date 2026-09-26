import Foundation
import Testing
import SimulationCore
@testable import TrisolarisApp

@Suite("应用稳定性回归")
@MainActor
struct TrailRegressionTests {
    @Test("轨迹越过900点后持续更新不会触发独占访问崩溃")
    func trailCapacityRegression() throws {
        let store = WorkspaceStore()
        let simulation = try NBodySimulation(scenario: Presets.stableHierarchy())
        var snapshot = simulation.snapshot
        for i in 0..<3500 {
            snapshot.timeDays = Double(i)
            snapshot.bodies[0].positionAU.x = Double(i)
            store.appendTrail(snapshot)
        }
        let limit = PlaybackSampling.pointLimit(preference: UserDefaults.standard.integer(forKey: "trailPoints"))
        #expect(store.trails.count == 4)
        #expect(store.trails.values.allSatisfy { $0.count > 1 && $0.count <= limit + 2 })
        #expect(store.trails[snapshot.bodies[0].id.uuidString]?.last?.x == 3499)
    }

    @Test("10年每秒与1年每秒使用相同的真实轨道采样精度")
    func speedIndependentSampling() async throws {
        let worker = SimulationWorker()
        let scenario = Presets.stableHierarchy()
        _ = try await worker.prepareLive(scenario)
        let slow = try await worker.advanceLiveSampled(years: 1.0 / 30)
        _ = try await worker.prepareLive(scenario)
        let fast = try await worker.advanceLiveSampled(years: 10.0 / 30)
        #expect(slow.count == 4)
        #expect(fast.count == 40)
        for frames in [slow, fast] {
            var previous = 0.0
            for frame in frames {
                #expect(frame.timeDays - previous <= scenario.standardYearDays / 120 * (1 + 1e-10))
                previous = frame.timeDays
            }
        }
    }

    @Test("轨迹按物理时间消退，慢放不会无限积累点")
    func boundedTrailHistory() {
        var history = OrbitTrailHistory()
        for index in 0...40_000 {
            let time = Double(index) / 1000
            history.append(time: time, positions: ["star": SIMD3(time, 0, 0)], yearDays: 1, pointLimit: 300)
        }
        #expect(history.times.count <= 302)
        #expect(history.times.last == 40)
        #expect((history.times.last! - history.times.first!) <= 2.52)
        #expect(history.points["star"]?.count == history.times.count)
        history.append(time: 0, positions: ["star": .zero], yearDays: 1, pointLimit: 300)
        #expect(history.times == [0])
    }

    @Test("手动滑轨采用连续对数映射")
    func logarithmicPlaybackSlider() {
        #expect(abs(PlaybackSampling.rate(at: 0) - 0.003) < 1e-12)
        #expect(abs(PlaybackSampling.rate(at: 1) - 30) < 1e-12)
        #expect(abs(PlaybackSampling.rate(at: 0.5) - 0.3) < 1e-12)
        for position in stride(from: 0.0, through: 1.0, by: 0.05) {
            #expect(abs(PlaybackSampling.sliderPosition(for: PlaybackSampling.rate(at: position)) - position) < 1e-12)
        }
    }
}
