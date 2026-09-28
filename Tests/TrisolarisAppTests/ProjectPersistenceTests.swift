import Foundation
import Testing
import SimulationCore
@testable import TrisolarisApp

@Suite("后台项目持久化")
struct ProjectPersistenceTests {
    @Test("观测资料随项目往返保存，旧项目不需要新字段")
    func observationsAndLegacyArchive() async throws {
        let scenario = AlphaCentauriCatalog.initialScenario()
        let rows = try ObservationCSV.decode(ObservationCSV.header + "\n2025.5,A,radialVelocity,-22.5,0.1,km/s,https://example.org,测试资料\n")
        let archive = ProjectArchive(draft: scenario, activeScenario: scenario, importedObservations: rows)
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".trisolaris")
        defer { try? FileManager.default.removeItem(at: url) }
        try await ProjectFileIO.shared.write(archive, to: url)
        let loaded = try await ProjectFileIO.shared.read(from: url)
        #expect(loaded.importedObservations == rows)
        var legacy = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(archive)) as? [String: Any])
        legacy.removeValue(forKey: "importedObservations")
        let restored = try JSONDecoder().decode(ProjectArchive.self, from: JSONSerialization.data(withJSONObject: legacy))
        #expect(restored.importedObservations == nil)
        #expect(restored.draft == scenario)
    }

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
