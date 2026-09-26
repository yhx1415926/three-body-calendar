import Foundation
import SimulationCore

/// Large JSON archives and disk writes must never occupy the UI actor.
actor ProjectFileIO {
    static let shared = ProjectFileIO()

    func read(from url: URL) throws -> ProjectArchive {
        try JSONDecoder().decode(ProjectArchive.self, from: Data(contentsOf: url))
    }

    func write(_ archive: ProjectArchive, to url: URL, createDirectory: Bool = false) throws {
        if createDirectory {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        }
        try JSONEncoder().encode(archive).write(to: url, options: .atomic)
    }

    func export(_ result: CalendarResult, to url: URL, asCSV: Bool, annualDetails: Bool) throws {
        if asCSV {
            try CalendarExport.csv(result, annualDetails: annualDetails).write(to: url, atomically: true, encoding: .utf8)
        } else {
            let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            try encoder.encode(result).write(to: url, options: .atomic)
        }
    }
}
