import Foundation
import SimulationCore

// A reproducible release-validation command, independent of the desktop UI.
let args = CommandLine.arguments
let years = args.count > 1 ? Int(args[1]) ?? 100 : 100
var scenario = Presets.stableHierarchy()
if let index = args.firstIndex(of: "--seed"), args.count > index+1, let seed = UInt64(args[index+1]) {
    scenario = Presets.random(seed: seed, template: scenario, spatialScaleAU: 8, virialRatio: 0.4)
}
scenario.durationYears = years
if args.contains("--strict") { scenario.numerics = .strict }
let start = Date()
do {
    if args.contains("--kepler") {
        var checks: [[String: Any]] = []
        for eccentricity in [0.0,0.6] {
            var star = scenario.bodies[0], planet = scenario.planet!
            star.positionAU = .zero; star.velocityAUPerDay = .zero
            planet.positionAU = Vector3(1-eccentricity,0,0)
            planet.velocityAUPerDay = Vector3(0,sqrt(Astronomy.gravitationalConstant*(star.massSolar+planet.massSolar)*(1+eccentricity)/(1-eccentricity)),0)
            var bodies = [star,planet]; Presets.recenter(&bodies)
            let fixture = Scenario(name: "二体解析基准", bodies: bodies, referenceStarID: star.id)
            let engine = try NBodySimulation(scenario: fixture, validate: false)
            let reference = bodies[1].positionAU-bodies[0].positionAU
            var maximumEnergy = 0.0, maximumAngular = 0.0
            for period in 1...years {
                let snapshot = try engine.integrate(toDays: Double(period)*fixture.standardYearDays)
                maximumEnergy = max(maximumEnergy,snapshot.diagnostics.normalizedEnergyError)
                maximumAngular = max(maximumAngular,snapshot.diagnostics.normalizedAngularMomentumError)
            }
            let snapshot = engine.snapshot
            let error = ((snapshot.bodies[1].positionAU-snapshot.bodies[0].positionAU)-reference).length
            checks.append(["eccentricity":eccentricity,"periods":years,"positionErrorAU":error,"maximumEnergyError":maximumEnergy,"maximumAngularMomentumError":maximumAngular])
            guard error <= 1e-6, maximumEnergy <= 1e-10, maximumAngular <= 1e-10 else { throw SimulationError.engine("二体长周期基准未达到误差门槛") }
        }
        let data = try JSONSerialization.data(withJSONObject: ["checks":checks,"elapsedSeconds":Date().timeIntervalSince(start)], options: [.prettyPrinted,.sortedKeys])
        print(String(decoding:data,as:UTF8.self))
        if let index = args.firstIndex(of:"--output"), args.count > index+1 { try data.write(to: URL(fileURLWithPath:args[index+1]),options:.atomic) }
        exit(0)
    }
    let simulation = try CalendarSimulation(scenario: scenario)
    var lastYear = -1
    var maximumEnergy = 0.0, maximumAngular = 0.0
    while simulation.progress.status == .ready || simulation.progress.status == .running {
        let progress = try simulation.advance(maxSamples: 4096)
        maximumEnergy = max(maximumEnergy, simulation.snapshot.diagnostics.normalizedEnergyError)
        maximumAngular = max(maximumAngular, simulation.snapshot.diagnostics.normalizedAngularMomentumError)
        if progress.completedYears / max(1, years / 10) != lastYear {
            lastYear = progress.completedYears / max(1, years / 10)
            FileHandle.standardOutput.write(Data("Progress: \(progress.completedYears)/\(years)\n".utf8))
        }
    }
    let result = simulation.result
    let stable = result.years.filter { $0.kind == .stable && $0.isComplete }.count
    let orbitalElements = result.snapshots.compactMap { snapshot -> (Double,Double)? in
        guard let planet = snapshot.bodies.first(where: { $0.kind == .planet }), let star = snapshot.bodies.first(where: { $0.id == scenario.referenceStarID }) else { return nil }
        let r = planet.positionAU-star.positionAU, v = planet.velocityAUPerDay-star.velocityAUPerDay
        let mu = Astronomy.gravitationalConstant*(planet.massSolar+star.massSolar)
        let a = 1/(2/r.length-v.squaredLength/mu)
        let e = (v.cross(r.cross(v))/mu-r/r.length).length
        return (a,e)
    }
    let report: [String: Any] = [
        "years": years, "completedYears": result.progress.completedYears,
        "stableYears": stable, "status": result.progress.status.rawValue,
        "elapsedSeconds": Date().timeIntervalSince(start),
        "normalizedEnergyError": result.finalSnapshot.diagnostics.normalizedEnergyError,
        "normalizedAngularMomentumError": result.finalSnapshot.diagnostics.normalizedAngularMomentumError,
        "maximumEnergyError": maximumEnergy, "maximumAngularMomentumError": maximumAngular,
        "minimumPlanetSemimajorAxisAU": orbitalElements.map(\.0).min() ?? 0,
        "maximumPlanetSemimajorAxisAU": orbitalElements.map(\.0).max() ?? 0,
        "maximumPlanetEccentricity": orbitalElements.map(\.1).max() ?? 0,
        "snapshots": result.snapshots.count, "intervals": result.intervals.count,
        "engine": result.engineVersion, "tolerance": scenario.numerics.tolerance,
        "simulatedStandardYears": result.finalSnapshot.timeDays/result.standardYearDays,
        "events": result.events.map(\.message)
    ]
    let data = try JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys])
    print(String(decoding: data, as: UTF8.self))
    if let index = args.firstIndex(of: "--output"), args.count > index + 1 { try data.write(to: URL(fileURLWithPath: args[index + 1]), options: .atomic) }
    if let index = args.firstIndex(of: "--project"), args.count > index+1 {
        let archive = ReferenceProject(formatVersion: 1, savedAt: .now, draft: scenario, activeScenario: scenario, result: result, previousResult: nil, checkpoint: try simulation.checkpointData())
        try JSONEncoder().encode(archive).write(to: URL(fileURLWithPath: args[index+1]), options: .atomic)
    }
    if args.contains("--expect-escape") {
        guard result.progress.status.rawValue == "escaped", result.progress.completedYears < years else { exit(3) }
        exit(0)
    }
    if result.progress.status != .completed || result.progress.completedYears != years { exit(1) }
    if maximumEnergy > 1e-9 || (orbitalElements.map(\.0).min() ?? 0) < 0.95 || (orbitalElements.map(\.0).max() ?? 2) > 1.05 || (orbitalElements.map(\.1).max() ?? 1) >= 0.1 { exit(2) }
} catch {
    print("Validation failed: \(error.localizedDescription)")
    exit(1)
}

struct ReferenceProject: Codable {
    var formatVersion: Int
    var savedAt: Date
    var draft: Scenario
    var activeScenario: Scenario
    var result: CalendarResult?
    var previousResult: CalendarResult?
    var checkpoint: Data?
}
