import XCTest
@testable import SimulationCore

final class SimulationCoreTests: XCTestCase {
    func testScenarioRequiresExactlyThreeStarsAndAtMostOnePlanet() throws {
        var scenario = Presets.stableHierarchy()
        scenario.bodies.removeAll { $0.id == scenario.referenceStarID }
        XCTAssertTrue(scenario.validationIssues().contains { $0.message.contains("三颗恒星") })
        XCTAssertThrowsError(try NBodySimulation(scenario: scenario))

        scenario = Presets.stableHierarchy()
        var extraPlanet = try XCTUnwrap(scenario.planet)
        extraPlanet.id = UUID()
        extraPlanet.positionAU = extraPlanet.positionAU + Vector3(0.1, 0, 0)
        scenario.bodies.append(extraPlanet)
        XCTAssertTrue(scenario.validationIssues().contains { $0.message.contains("最多添加一颗行星") })
        XCTAssertThrowsError(try NBodySimulation(scenario: scenario))
    }

    func testCheckpointResumeMatchesContinuousCalendar() throws {
        var scenario = Presets.stableHierarchy()
        scenario.durationYears = 2

        let continuous = try CalendarSimulation(scenario: scenario)
        try finish(continuous)

        let interrupted = try CalendarSimulation(scenario: scenario)
        try interrupted.advance(maxSamples: 256)
        XCTAssertEqual(interrupted.progress.status, .running)
        XCTAssertGreaterThan(interrupted.snapshot.timeDays, 0)

        let resumed = try CalendarSimulation(checkpointData: interrupted.checkpointData())
        try finish(resumed)

        let expected = continuous.result
        let actual = resumed.result
        XCTAssertEqual(actual.progress.status, .completed)
        XCTAssertEqual(actual.progress.completedYears, 2)
        XCTAssertEqual(actual.years.count, expected.years.count)
        for (lhs, rhs) in zip(actual.years, expected.years) {
            XCTAssertEqual(lhs.year, rhs.year)
            XCTAssertEqual(lhs.kind, rhs.kind)
            XCTAssertEqual(lhs.isComplete, rhs.isComplete)
            XCTAssertEqual(lhs.stableFraction, rhs.stableFraction, accuracy: 1e-8)
        }
        XCTAssertEqual(actual.finalSnapshot.timeDays, expected.finalSnapshot.timeDays, accuracy: 1e-8)
        XCTAssertTrue(actual.finalSnapshot.diagnostics.normalizedEnergyError.isFinite)
    }

    private func finish(_ simulation: CalendarSimulation) throws {
        for _ in 0..<100 {
            if simulation.progress.status != .ready && simulation.progress.status != .running { return }
            try simulation.advance(maxSamples: 256)
        }
        XCTFail("Two-year calendar did not finish within the expected number of batches")
    }
}
