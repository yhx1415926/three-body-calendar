import Foundation

/// Display sampling is independent of the gravitational integrator's tolerance.
enum PlaybackSampling {
    static let samplesPerYear = 120.0
    static let maximumSamplesPerBatch = 256
    static let minimumRate = 0.003
    static let maximumRate = 30.0
    static func rate(at sliderPosition: Double) -> Double {
        minimumRate * pow(maximumRate / minimumRate, min(1, max(0, sliderPosition)))
    }
    static func sliderPosition(for rate: Double) -> Double {
        log(min(maximumRate, max(minimumRate, rate)) / minimumRate) / log(maximumRate / minimumRate)
    }
    static func pointLimit(preference: Int) -> Int { min(2_400, max(100, preference == 0 ? 900 : preference)) }
}

/// Each stored timestamp has one position per body. The latest point may be
/// replaced between physical samples, keeping slow playback bounded as well.
struct OrbitTrailHistory {
    private(set) var points: [String: [SIMD3<Double>]] = [:]
    private(set) var times: [Double] = []

    mutating func append(time: Double, positions: [String: SIMD3<Double>], yearDays: Double, pointLimit: Int) {
        guard time.isFinite, yearDays.isFinite, yearDays > 0 else { return }
        if let last = times.last, time < last || Set(points.keys) != Set(positions.keys) {
            self = Self()
        }
        let interval = yearDays / PlaybackSampling.samplesPerYear
        // Keep the endpoint attached to its body without accumulating 30 points
        // a second during very slow playback.
        let replaceEndpoint = times.last == time || (times.count > 1 && time - times[times.count - 2] < interval * 0.999)
        if replaceEndpoint {
            times.removeLast()
            for key in Array(points.keys) { points[key]?.removeLast() }
        }
        times.append(time)
        for (id, position) in positions { points[id, default: []].append(position) }
        let oldest = time - Double(pointLimit) * interval
        var expired = 0
        while expired + 1 < times.count && times[expired + 1] < oldest { expired += 1 }
        let removeCount = max(expired, times.count - pointLimit - 2)
        if removeCount > 0 {
            times.removeFirst(removeCount)
            for key in Array(points.keys) { points[key]?.removeFirst(removeCount) }
        }
    }
}
