import Foundation
import SimulationCore

struct WorkUpdate: Sendable {
    let snapshot: SimulationSnapshot
    let progress: SimulationProgress
    let result: CalendarResult?
}

actor SimulationWorker {
    private var live: NBodySimulation?
    private var calendar: CalendarSimulation?
    private var liveScenario: Scenario?
    private var liveTimeOffset = 0.0

    func prepareLive(_ scenario: Scenario) throws -> SimulationSnapshot {
        live = try NBodySimulation(scenario: scenario)
        liveScenario = scenario
        liveTimeOffset = 0
        return live!.snapshot
    }

    func advanceLive(years: Double) throws -> SimulationSnapshot? {
        try advanceLiveSampled(years: years).last
    }

    /// Sample the actual integrated orbit at fixed physical resolution, independently
    /// of playback speed. This actor keeps the extra integration work off the UI thread.
    func advanceLiveSampled(years: Double) throws -> [SimulationSnapshot] {
        guard let live, let liveScenario else { return [] }
        guard live.status != .collision else { throw SimulationError.engine("天体发生碰撞，观测已停止。请修改初始条件或重置模拟。") }
        guard live.status != .escaped else { throw SimulationError.engine(live.escapeEvent?.message ?? "天体已逃逸，观测已停止。请修改初始条件或重置模拟。") }
        guard years.isFinite, years > 0 else { return [] }
        let boundedYears = min(years, Double(PlaybackSampling.maximumSamplesPerBatch) / PlaybackSampling.samplesPerYear)
        let count = max(1, Int(ceil(boundedYears * PlaybackSampling.samplesPerYear)))
        let start = live.snapshot.timeDays
        let duration = boundedYears * liveScenario.standardYearDays
        var frames: [SimulationSnapshot] = []
        frames.reserveCapacity(count)
        for index in 1...count {
            try Task.checkCancellation()
            var snapshot = try live.integrate(toDays: start + duration * Double(index) / Double(count))
            snapshot.timeDays += liveTimeOffset
            frames.append(snapshot)
            if live.status == .collision || live.status == .escaped { break }
        }
        return frames
    }

    /// Reintegrate the physical state from the closest earlier full-precision display snapshot.
    /// This does not replace the archived calendar or its climate history.
    func seekLive(scenario: Scenario, targetDays: Double, samples: [SimulationSnapshot]) throws -> [SimulationSnapshot] {
        let source = samples.last { $0.timeDays <= targetDays }
        var replayScenario = scenario
        if let source { replayScenario.bodies = source.bodies }
        live = try NBodySimulation(scenario: replayScenario)
        liveScenario = scenario
        liveTimeOffset = source?.timeDays ?? 0
        guard let live else { return [] }
        let end = max(0, targetDays - liveTimeOffset)
        let trailStart = max(0, end - scenario.standardYearDays * 0.15)
        _ = try live.integrate(toDays: trailStart)
        var frames: [SimulationSnapshot] = []
        for step in 0...48 {
            var frame = try live.integrate(toDays: trailStart + (end - trailStart) * Double(step) / 48)
            frame.timeDays += liveTimeOffset
            frames.append(frame)
        }
        return frames
    }

    func startCalendar(_ scenario: Scenario) throws -> WorkUpdate {
        calendar = try CalendarSimulation(scenario: scenario)
        return calendarUpdate(includeResult: true)!
    }

    func advanceCalendar(includeResult: Bool) throws -> WorkUpdate? {
        guard let calendar else { return nil }
        let started = ContinuousClock.now
        repeat {
            try Task.checkCancellation()
            _ = try calendar.advance(maxSamples: 256)
        } while calendar.progress.status == .running && started.duration(to: .now) < .milliseconds(40)
        return calendarUpdate(includeResult: includeResult || calendar.progress.status != .running)
    }

    func calendarUpdate(includeResult: Bool) -> WorkUpdate? {
        guard let calendar else { return nil }
        return WorkUpdate(snapshot: calendar.snapshot, progress: calendar.progress, result: includeResult ? calendar.result : nil)
    }

    func exportState() throws -> (Data?, CalendarResult?) {
        guard let calendar else { return (nil, nil) }
        return (try calendar.checkpointData(), calendar.result)
    }

    func restore(_ checkpoint: Data) throws -> WorkUpdate {
        calendar = try CalendarSimulation(checkpointData: checkpoint)
        return calendarUpdate(includeResult: true)!
    }

    func discardCalendar() { calendar = nil }

    func extend(to years: Int, expectedScenario: Scenario) throws -> WorkUpdate? {
        guard let calendar else { return nil }
        guard calendar.result.scenario == expectedScenario else { throw SimulationError.invalidCheckpoint("当前续算状态不属于所选结果，请重新打开对应项目文件。") }
        try calendar.extend(toYears: years)
        return calendarUpdate(includeResult: true)
    }
}

struct ProjectArchive: Codable, Sendable {
    var formatVersion: Int = 1
    var savedAt: Date = .now
    var draft: Scenario
    var activeScenario: Scenario
    var result: CalendarResult?
    var previousResult: CalendarResult?
    var checkpoint: Data?
    var importedObservations: [StellarObservation]? = nil
}
