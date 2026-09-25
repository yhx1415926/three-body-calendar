import Foundation
import SimulationCore

// A reproducible release-validation command, independent of the desktop UI.
let args = CommandLine.arguments
let years = args.count > 1 ? Int(args[1]) ?? 100 : 100
var scenario = Presets.stableHierarchy()
scenario.durationYears = years
if args.contains("--strict") { scenario.numerics = .strict }
let start = Date()
do {
    let simulation = try CalendarSimulation(scenario: scenario)
    var lastYear = -1
    while simulation.progress.status == .ready || simulation.progress.status == .running {
        let progress = try simulation.advance(maxSamples: 4096)
        if progress.completedYears / max(1, years / 10) != lastYear {
            lastYear = progress.completedYears / max(1, years / 10)
            print("Progress: \(progress.completedYears)/\(years)")
        }
    }
    let result = simulation.result
    let stable = result.years.filter { $0.kind == .stable && $0.isComplete }.count
    let report: [String: Any] = [
        "years": years, "completedYears": result.progress.completedYears,
        "stableYears": stable, "status": result.progress.status.rawValue,
        "elapsedSeconds": Date().timeIntervalSince(start),
        "normalizedEnergyError": result.finalSnapshot.diagnostics.normalizedEnergyError,
        "normalizedAngularMomentumError": result.finalSnapshot.diagnostics.normalizedAngularMomentumError,
        "snapshots": result.snapshots.count, "intervals": result.intervals.count,
        "engine": result.engineVersion, "tolerance": scenario.numerics.tolerance
    ]
    let data = try JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys])
    print(String(decoding: data, as: UTF8.self))
    if let index = args.firstIndex(of: "--output"), args.count > index + 1 { try data.write(to: URL(fileURLWithPath: args[index + 1]), options: .atomic) }
    if result.progress.status != .completed || result.progress.completedYears != years { exit(1) }
} catch {
    print("Validation failed: \(error.localizedDescription)")
    exit(1)
}
