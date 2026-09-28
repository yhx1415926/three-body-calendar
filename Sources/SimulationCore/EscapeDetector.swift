import Foundation

/// Conservative far-field escape test. Positive instantaneous energy alone is never sufficient.
struct EscapeDetector: Codable {
    let initialStellarScaleAU: Double
    let referenceDistanceAU: Double
    let standardYearDays: Double
    /// Optional so checkpoints made before multiple planets remain readable.
    let calendarPlanetID: UUID?
    var candidateSinceDays: Double?
    var requiredDurationDays: Double = 0

    init(scenario: Scenario) {
        initialStellarScaleAU = Self.stellarScale(scenario.bodies)
        referenceDistanceAU = scenario.referenceDistanceAU
        standardYearDays = scenario.standardYearDays
        calendarPlanetID = scenario.planet?.id
    }

    mutating func check(timeDays: Double, bodies: [CelestialBody]) -> SimulationEvent? {
        guard let planet = bodies.first(where: { $0.kind == .planet && (calendarPlanetID == nil || $0.id == calendarPlanetID) }) else { return nil }
        let stars = bodies.filter { $0.kind == .star }
        // Other planets also gravitate. Retain their potential and recoil, especially for
        // user-defined massive planets, rather than treating them as massless tracers.
        let companions = bodies.filter { $0.id != planet.id }
        let mass = companions.reduce(0) { $0+$1.massSolar }
        guard mass > 0, standardYearDays.isFinite else { return nil }
        let position = companions.reduce(Vector3.zero) { $0+$1.positionAU*$1.massSolar }/mass
        let velocity = companions.reduce(Vector3.zero) { $0+$1.velocityAUPerDay*$1.massSolar }/mass
        let relativePosition = planet.positionAU-position
        let relativeVelocity = planet.velocityAUPerDay-velocity
        let distance = relativePosition.length
        let radialSpeed = relativePosition.dot(relativeVelocity)/max(distance,1e-30)
        // Freeze the scale at initialization: an escaping star must not drag the stopping radius
        // outward forever. Separate relative-energy/recession checks below handle dispersed stars.
        let threshold = max(100,10*max(initialStellarScaleAU,referenceDistanceAU))
        let nearest = stars.map { ($0.positionAU-planet.positionAU).length }.min() ?? 0
        // The relative planet–system-COM acceleration includes the COM's recoil.
        let potentialMagnitude = (1+planet.massSolar/mass)*companions.reduce(0) {
            $0+Astronomy.gravitationalConstant*$1.massSolar/max(($1.positionAU-planet.positionAU).length,1e-30)
        }
        let kinetic = 0.5*relativeVelocity.squaredLength
        var longestFlightTime = distance/max(radialSpeed,1e-30)
        let individuallyEscaping = companions.allSatisfy { body in
            let r = planet.positionAU-body.positionAU
            let v = planet.velocityAUPerDay-body.velocityAUPerDay
            let radial = r.dot(v)/max(r.length,1e-30)
            if radial > 0 { longestFlightTime = max(longestFlightTime,r.length/radial) }
            return radial > 0 && 0.5*v.squaredLength > 1.1*Astronomy.gravitationalConstant*(body.massSolar+planet.massSolar)/max(r.length,1e-30)
        }
        guard nearest > threshold, radialSpeed > 0, kinetic > 1.1*potentialMagnitude, individuallyEscaping else {
            candidateSinceDays = nil; requiredDurationDays = 0; return nil
        }
        if candidateSinceDays == nil {
            candidateSinceDays = timeDays
            requiredDurationDays = max(5*standardYearDays,0.05*longestFlightTime)
        }
        guard timeDays-(candidateSinceDays ?? timeDays) >= requiredDurationDays else { return nil }
        let message = String(format: "历法行星已确认远场逃逸：距最近恒星 %.1f AU（阈值 %.1f AU），相对其余天体及其质心持续外行，各自比能与总势能检验均具有至少 10%% 余量，连续确认 %.2f 标准年。停止后续历法；此判断基于牛顿模型与保守远场条件。",nearest,threshold,requiredDurationDays/standardYearDays)
        return SimulationEvent(timeDays: timeDays,message: message,bodyIDs: [planet.id])
    }

    private static func stellarScale(_ bodies: [CelestialBody]) -> Double {
        let stars = bodies.filter { $0.kind == .star }
        var maximum = 0.0
        for i in stars.indices { for j in stars.indices where j > i { maximum = max(maximum,(stars[i].positionAU-stars[j].positionAU).length) } }
        return maximum
    }
}
