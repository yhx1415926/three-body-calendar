import Foundation
import Testing
import SimulationCore
@testable import TrisolarisApp

@Suite("后台项目持久化")
struct ProjectPersistenceTests {
    @Test("后台保存保留检查点并可继续完整历法")
    func archiveRoundTrip() async throws {
        var scenario = Presets.stableHierarchy(); scenario.durationYears = 2
        let worker = SimulationWorker()
        _ = try await worker.startCalendar(scenario)
        _ = try await worker.advanceCalendar(includeResult: true)
        let (checkpoint, result) = try await worker.exportState()
        let archive = ProjectArchive(draft: scenario, activeScenario: scenario, result: result, checkpoint: checkpoint)
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("test.trisolaris")
        try await ProjectFileIO.shared.write(archive, to: url, createDirectory: true)
        let loaded = try await ProjectFileIO.shared.read(from: url)
        #expect(loaded.draft == scenario)
        #expect(loaded.checkpoint == checkpoint)
        let restored = SimulationWorker()
        var update = try await restored.restore(#require(loaded.checkpoint))
        while update.progress.status == .running || update.progress.status == .ready {
            update = try #require(await restored.advanceCalendar(includeResult: true))
        }
        #expect(update.progress.status == .completed)
        #expect(update.result?.years.count == 2)
        let csv = directory.appendingPathComponent("epochs.csv")
        try await ProjectFileIO.shared.export(#require(update.result), to: csv, asCSV: true, annualDetails: false)
        let lines = try String(contentsOf: csv, encoding: .utf8).split(separator: "\n")
        #expect(lines.count == 2)
        #expect(lines.last?.hasPrefix("恒纪元,") == true)
    }
}
