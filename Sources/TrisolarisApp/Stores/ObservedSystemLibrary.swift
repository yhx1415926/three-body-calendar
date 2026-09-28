import Foundation
import SimulationCore

actor ObservedSystemLibrary {
    static let shared = ObservedSystemLibrary()
    private var cached: [StellarObservation]?
    func importCSV(_ url: URL) throws -> [StellarObservation] {
        let data = try Data(contentsOf: url, options: .mappedIfSafe)
        guard data.count <= 32_000_000, let text = String(data: data, encoding: .utf8) else {
            throw SimulationError.invalidScenario(["请选择不超过 32 MB 的 UTF-8 CSV 文件。"])
        }
        return try ObservationCSV.decode(text)
    }
    func exportCSV(_ rows: [StellarObservation], to url: URL) throws {
        try ObservationCSV.encode(rows).write(to: url, atomically: true, encoding: .utf8)
    }
    func observations() throws -> [StellarObservation] {
        if let cached { return cached }
        let loaded = try AlphaCentauriCatalog.observations()
        cached = loaded
        return loaded
    }
}
