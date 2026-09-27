import Foundation
import SimulationCore

// Screening only. Every selected candidate still requires the full climate calendar.
let args = CommandLine.arguments
let firstSeed = args.count > 1 ? UInt64(args[1]) ?? 1 : 1
let count = args.count > 2 ? Int(args[2]) ?? 100 : 100
let directory = URL(fileURLWithPath: args.count > 3 ? args[3] : "Validation/Candidates")
try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
let wide = args.contains("--wide")
for seed in firstSeed..<(firstSeed+UInt64(count)) {
    var template = Presets.stableHierarchy()
    for i in template.bodies.indices where template.bodies[i].kind == .star {
        template.bodies[i].massSolar = 1
        template.bodies[i].luminositySolar = 1
        template.bodies[i].radiusAU = Astronomy.solarRadiusAU
    }
    var scenario = Presets.random(seed: seed, template: template,
                                 spatialScaleAU: (wide ? [12.0,16.0,20.0,24.0] : [2.5,4.0,6.0,8.0])[Int(seed%4)], virialRatio: 0.4)
    scenario.durationYears = 10000
    do {
        let engine = try NBodySimulation(scenario: scenario)
        var visits: [UUID: Double] = [:]
        var roughHabitableYears = 0.0
        for step in 0...(wide ? 128000 : 48000) {
            let state = try engine.integrate(toDays: Double(step)/32*scenario.standardYearDays)
            guard let planet = state.bodies.first(where: { $0.kind == .planet }) else { break }
            let nearest = state.bodies.filter { $0.kind == .star }.min {
                ($0.positionAU-planet.positionAU).squaredLength < ($1.positionAU-planet.positionAU).squaredLength
            }!
            if (nearest.positionAU-planet.positionAU).length < 2, visits[nearest.id] == nil {
                visits[nearest.id] = state.timeDays/scenario.standardYearDays
            }
            if let flux = state.fluxEarth, (0.7...1.5).contains(flux) { roughHabitableYears += 1.0/32 }
            if engine.status == .collision || engine.status == .escaped { break }
        }
        if visits.count == 3 && roughHabitableYears > (wide ? 520 : 75) {
            try JSONEncoder().encode(scenario).write(to: directory.appendingPathComponent("candidate-\(seed).json"), options: .atomic)
            let report: [String: Any] = ["seed":seed,"screenedYears":engine.timeDays/scenario.standardYearDays,
                "roughFluxSuitableYears":roughHabitableYears,"visits":visits.map { ["star":$0.key.uuidString,"year":$0.value] as [String:Any] },
                "status":engine.status.rawValue,"screeningOnly":true]
            try JSONSerialization.data(withJSONObject:report,options:[.prettyPrinted,.sortedKeys]).write(to:directory.appendingPathComponent("screen-\(seed).json"))
            FileHandle.standardOutput.write(Data("CANDIDATE \(seed) roughYears=\(roughHabitableYears) visits=3\n".utf8))
        } else {
            FileHandle.standardOutput.write(Data("seed \(seed): \(Int(engine.timeDays/scenario.standardYearDays)) years, visits=\(visits.count), rough=\(Int(roughHabitableYears))\n".utf8))
        }
    } catch { FileHandle.standardOutput.write(Data("seed \(seed): \(error)\n".utf8)) }
}
