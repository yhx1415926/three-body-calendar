import Foundation

/// Chunkable synchronous calendar generation. The owning worker decides when to pause or cancel.
public final class CalendarSimulation {
    public private(set) var scenario: Scenario
    public let standardYearDays: Double
    private let engine: NBodySimulation
    private var climate: ClimateHistory?
    private var lastSnapshot: SimulationSnapshot
    private var status: RunStatus = .ready
    private var rawIntervals: [EpochInterval] = []
    private var statistics: [YearStatistics] = []
    private var events: [SimulationEvent] = []
    private var replay: [SimulationSnapshot] = []
    private var nextReplayDays: Double = 0
    private var replayStrideDays: Double

    public init(scenario: Scenario) throws {
        self.scenario = scenario
        engine = try NBodySimulation(scenario: scenario)
        standardYearDays = engine.standardYearDays
        var initial = engine.snapshot
        if let flux = initial.fluxEarth {
            climate = ClimateHistory(rules: scenario.climateRules, standardYearDays: standardYearDays, initialFlux: flux)
            initial.temperatureC = climate!.temperatureC
            initial.fluxCoefficientOfVariation = 0
        }
        lastSnapshot = initial
        replayStrideDays = max(standardYearDays/32, Double(scenario.durationYears)*standardYearDays/4096)
        replay = [initial]; nextReplayDays = replayStrideDays
    }

    public init(checkpointData: Data) throws {
        let saved: CalendarCheckpoint
        do { saved = try JSONDecoder().decode(CalendarCheckpoint.self, from: checkpointData) }
        catch { throw SimulationError.invalidCheckpoint("历法检查点格式无效：\(error.localizedDescription)") }
        guard saved.version == 1, saved.standardYearDays.isFinite, saved.standardYearDays > 0 else {
            throw SimulationError.invalidCheckpoint("不支持此历法检查点版本。")
        }
        scenario = saved.scenario; standardYearDays = saved.standardYearDays
        engine = try NBodySimulation(checkpointData: saved.engineData)
        guard abs(engine.timeDays-saved.lastSnapshot.timeDays) < 1e-8 else {
            throw SimulationError.invalidCheckpoint("历法与引力检查点的时刻不一致。")
        }
        climate = saved.climate; lastSnapshot = saved.lastSnapshot; status = saved.status
        rawIntervals = saved.rawIntervals; statistics = saved.statistics; events = saved.events
        replay = saved.replay; nextReplayDays = saved.nextReplayDays; replayStrideDays = saved.replayStrideDays
    }

    public var snapshot: SimulationSnapshot { lastSnapshot }
    private var targetDays: Double { Double(scenario.durationYears)*standardYearDays }
    private var confirmationDays: Double { climate == nil ? 0 : scenario.climateRules.minimumStableYears*standardYearDays }
    private var horizonDays: Double { targetDays+confirmationDays }
    private var confirmedThroughDays: Double {
        if status == .collision || status == .failed || status == .completed { return min(targetDays,lastSnapshot.timeDays) }
        return min(targetDays,max(0,lastSnapshot.timeDays-confirmationDays))
    }
    public var progress: SimulationProgress {
        SimulationProgress(timeDays: min(lastSnapshot.timeDays,targetDays), targetDays: targetDays,
            completedYears: climate == nil ? 0 : min(scenario.durationYears,Int(floor((confirmedThroughDays+standardYearDays*1e-10)/standardYearDays))),
            requestedYears: scenario.durationYears, status: status)
    }
    public var result: CalendarResult {
        let intervals = finalizedIntervals()
        var years: [CalendarYear] = []
        var intervalIndex = 0
        for stat in statistics where stat.year <= scenario.durationYears {
            let start = Double(stat.year-1)*standardYearDays
            let end = min(stat.endDays, Double(stat.year)*standardYearDays)
            guard end > start else { continue }
            while intervalIndex < intervals.count && intervals[intervalIndex].endDays <= start { intervalIndex += 1 }
            var stableDuration = 0.0
            var i = intervalIndex
            while i < intervals.count && intervals[i].startDays < end {
                if intervals[i].kind == .stable { stableDuration += max(0,min(end,intervals[i].endDays)-max(start,intervals[i].startDays)) }
                i += 1
            }
            let complete = end >= Double(stat.year)*standardYearDays-standardYearDays*1e-10 && confirmedThroughDays >= end-standardYearDays*1e-10
            let fraction = min(1,max(0,stableDuration/(end-start)))
            years.append(CalendarYear(year: stat.year, startDays: start, endDays: end,
                kind: complete && fraction >= 1-1e-10 ? .stable : .chaotic, stableFraction: fraction,
                minimumTemperatureC: stat.minimumTemperatureC, maximumTemperatureC: stat.maximumTemperatureC,
                minimumFluxEarth: stat.minimumFluxEarth, maximumFluxEarth: stat.maximumFluxEarth, isComplete: complete))
        }
        return CalendarResult(scenario: scenario, standardYearDays: standardYearDays, years: years,
            intervals: intervals, events: events, snapshots: replay, progress: progress,
            finalSnapshot: lastSnapshot, engineVersion: NBodySimulation.engineVersion)
    }

    @discardableResult public func advance(maxSamples: Int = 512) throws -> SimulationProgress {
        guard maxSamples > 0, status == .ready || status == .running else { return progress }
        status = .running
        for _ in 0..<maxSamples {
            let remaining = horizonDays-engine.timeDays
            if remaining <= max(1e-9,horizonDays*1e-14) { status = .completed; break }
            let maximum = standardYearDays/Double(scenario.numerics.samplesPerYear)
            let step = min(remaining,engine.recommendedSampleStep(maximumDays: maximum))
            // Landing exactly on boundaries keeps the year aggregation independent of adaptive cadence.
            let nextYear = (floor(engine.timeDays/standardYearDays+1e-11)+1)*standardYearDays
            let end = min(horizonDays,min(engine.timeDays+step,nextYear))
            let previous = lastSnapshot
            do {
                var current = try engine.integrate(toDays: end)
                if var history = climate, let flux = current.fluxEarth, current.timeDays > previous.timeDays {
                    history.append(timeDays: current.timeDays, flux: flux)
                    current.temperatureC = history.temperatureC
                    current.fluxCoefficientOfVariation = history.coefficientOfVariation
                    climate = history
                    appendClimateSegment(from: previous,to: current)
                    appendStatistics(from: previous,to: current)
                }
                lastSnapshot = current
                if current.timeDays >= nextReplayDays || engine.status == .collision || current.timeDays >= horizonDays-1e-8 {
                    replay.append(current)
                    nextReplayDays = current.timeDays+replayStrideDays
                    if replay.count > 8192 {
                        replay = replay.enumerated().filter { $0.offset == 0 || $0.offset % 2 == 1 }.map(\.element)
                        replayStrideDays *= 2
                    }
                }
                if engine.status == .collision {
                    status = .collision
                    let names = current.bodies.filter { engine.collisionBodyIDs.contains($0.id) }.map(\.name).joined(separator: "、")
                    events.append(SimulationEvent(timeDays: current.timeDays, message: "\(names)发生碰撞，模拟终止。后续年份未计算。", bodyIDs: engine.collisionBodyIDs))
                    break
                }
            } catch {
                status = .failed
                events.append(SimulationEvent(timeDays: engine.timeDays, message: error.localizedDescription))
                throw error
            }
            if engine.timeDays >= horizonDays-max(1e-9,horizonDays*1e-14) { status = .completed; break }
        }
        return progress
    }

    /// Extends the same realization, retaining the original year unit and already integrated confirmation tail.
    public func extend(toYears years: Int) throws {
        guard years > scenario.durationYears, years <= 100_000, status != .collision, status != .failed else {
            throw SimulationError.engine("只能延长未碰撞、未失败的模拟，最长为 100000 标准年。")
        }
        scenario.durationYears = years
        if status == .completed { status = .running }
        replayStrideDays = max(replayStrideDays,Double(years)*standardYearDays/4096)
    }

    public func checkpointData() throws -> Data {
        try JSONEncoder().encode(CalendarCheckpoint(version: 1, scenario: scenario, standardYearDays: standardYearDays,
            engineData: try engine.checkpointData(), climate: climate, lastSnapshot: lastSnapshot,
            status: status, rawIntervals: rawIntervals, statistics: statistics, events: events, replay: replay,
            nextReplayDays: nextReplayDays, replayStrideDays: replayStrideDays))
    }

    private func appendClimateSegment(from first: SimulationSnapshot, to last: SimulationSnapshot) {
        guard let f0 = first.fluxEarth, let f1 = last.fluxEarth,
              let t0 = first.temperatureC, let t1 = last.temperatureC else { return }
        let cv0 = first.fluxCoefficientOfVariation ?? 0, cv1 = last.fluxCoefficientOfVariation ?? 0
        let rules = scenario.climateRules
        var fractions = [0.0,1.0]
        for (a,b,threshold) in [(f0,f1,rules.minimumFluxEarth),(f0,f1,rules.maximumFluxEarth),
                                (t0,t1,rules.minimumTemperatureC),(t0,t1,rules.maximumTemperatureC),
                                (cv0,cv1,rules.maximumFluxCoefficientOfVariation)] where a != b {
            let fraction = (threshold-a)/(b-a)
            if fraction > 0 && fraction < 1 { fractions.append(fraction) }
        }
        fractions.sort()
        for i in 0..<(fractions.count-1) {
            let mid = (fractions[i]+fractions[i+1])/2
            let f = f0+(f1-f0)*mid, t = t0+(t1-t0)*mid, cv = cv0+(cv1-cv0)*mid
            let good = f >= rules.minimumFluxEarth && f <= rules.maximumFluxEarth && t >= rules.minimumTemperatureC && t <= rules.maximumTemperatureC && cv <= rules.maximumFluxCoefficientOfVariation
            let start = first.timeDays+(last.timeDays-first.timeDays)*fractions[i]
            let end = first.timeDays+(last.timeDays-first.timeDays)*fractions[i+1]
            guard end > start else { continue }
            let kind: EpochKind = good ? .stable : .chaotic
            if let previous = rawIntervals.last, previous.kind == kind {
                rawIntervals[rawIntervals.count-1].endDays = end
            } else { rawIntervals.append(EpochInterval(startDays: start,endDays: end,kind: kind)) }
        }
    }

    private func finalizedIntervals() -> [EpochInterval] {
        var intervals: [EpochInterval] = []
        let minimum = confirmationDays
        for raw in rawIntervals where raw.startDays < targetDays {
            let kind: EpochKind = raw.kind == .stable && raw.endDays-raw.startDays+1e-10 >= minimum ? .stable : .chaotic
            let clipped = EpochInterval(startDays: raw.startDays,endDays: min(raw.endDays,targetDays),kind: kind)
            if intervals.last?.kind == kind { intervals[intervals.count-1].endDays = clipped.endDays }
            else { intervals.append(clipped) }
        }
        return intervals
    }

    private func appendStatistics(from first: SimulationSnapshot, to last: SimulationSnapshot) {
        guard let f0 = first.fluxEarth, let f1 = last.fluxEarth, let t0 = first.temperatureC, let t1 = last.temperatureC,
              last.timeDays > first.timeDays else { return }
        var cursor = first.timeDays
        while cursor < last.timeDays-1e-10 {
            let year = Int(floor(cursor/standardYearDays+1e-10))+1
            let end = min(last.timeDays,Double(year)*standardYearDays)
            guard end > cursor else { break }
            let a = (cursor-first.timeDays)/(last.timeDays-first.timeDays), b = (end-first.timeDays)/(last.timeDays-first.timeDays)
            let temperatures = [t0+(t1-t0)*a,t0+(t1-t0)*b], fluxes = [f0+(f1-f0)*a,f0+(f1-f0)*b]
            if statistics.last?.year != year {
                statistics.append(YearStatistics(year: year,endDays: end,minimumTemperatureC: temperatures.min()!,maximumTemperatureC: temperatures.max()!,minimumFluxEarth: fluxes.min()!,maximumFluxEarth: fluxes.max()!))
            } else {
                let i = statistics.count-1
                statistics[i].endDays = end
                statistics[i].minimumTemperatureC = min(statistics[i].minimumTemperatureC,temperatures.min()!)
                statistics[i].maximumTemperatureC = max(statistics[i].maximumTemperatureC,temperatures.max()!)
                statistics[i].minimumFluxEarth = min(statistics[i].minimumFluxEarth,fluxes.min()!)
                statistics[i].maximumFluxEarth = max(statistics[i].maximumFluxEarth,fluxes.max()!)
            }
            cursor = end
        }
    }
}

struct ClimateHistory: Codable {
    let rules: ClimateRules
    let standardYearDays: Double
    var timeDays: Double = 0
    var lastFlux: Double
    var temperatureC: Double
    var coefficientOfVariation: Double = 0
    private var segments: [FluxSegment] = []
    private var segmentHead = 0
    private var area = 0.0
    private var squareArea = 0.0
    init(rules: ClimateRules, standardYearDays: Double, initialFlux: Double) {
        self.rules = rules; self.standardYearDays = standardYearDays; lastFlux = initialFlux
        temperatureC = rules.equilibriumTemperatureC(fluxEarth: initialFlux)
    }
    mutating func append(timeDays end: Double, flux: Double) {
        let dt = end-timeDays
        guard dt > 0 else { return }
        // Exact relaxation for a constant target, with a midpoint target for the sampled varying irradiation.
        let target = (rules.equilibriumTemperatureC(fluxEarth: lastFlux)+rules.equilibriumTemperatureC(fluxEarth: flux))/2
        temperatureC = target+(temperatureC-target)*exp(-dt/rules.thermalResponseDays)
        let new = FluxSegment(start: timeDays,end: end,first: lastFlux,last: flux)
        segments.append(new); area += new.area; squareArea += new.squareArea
        let windowStart = max(0,end-rules.rollingWindowYears*standardYearDays)
        while segmentHead < segments.count && segments[segmentHead].end <= windowStart {
            area -= segments[segmentHead].area; squareArea -= segments[segmentHead].squareArea; segmentHead += 1
        }
        if segmentHead < segments.count, segments[segmentHead].start < windowStart {
            let old = segments[segmentHead]
            let fraction = (windowStart-old.start)/(old.end-old.start)
            let replacement = FluxSegment(start: windowStart,end: old.end,first: old.first+(old.last-old.first)*fraction,last: old.last)
            area += replacement.area-old.area; squareArea += replacement.squareArea-old.squareArea
            segments[segmentHead] = replacement
        }
        if segmentHead > 512 { segments.removeFirst(segmentHead); segmentHead = 0 }
        let duration = end-windowStart, mean = area/duration
        coefficientOfVariation = mean > 0 ? sqrt(max(0,squareArea/duration-mean*mean))/mean : 0
        timeDays = end; lastFlux = flux
    }
}

private struct FluxSegment: Codable {
    var start: Double, end: Double, first: Double, last: Double
    var area: Double { (end-start)*(first+last)/2 }
    var squareArea: Double { (end-start)*(first*first+first*last+last*last)/3 }
}
private struct YearStatistics: Codable {
    var year: Int
    var endDays: Double
    var minimumTemperatureC: Double
    var maximumTemperatureC: Double
    var minimumFluxEarth: Double
    var maximumFluxEarth: Double
}
private struct CalendarCheckpoint: Codable {
    var version: Int
    var scenario: Scenario
    var standardYearDays: Double
    var engineData: Data
    var climate: ClimateHistory?
    var lastSnapshot: SimulationSnapshot
    var status: RunStatus
    var rawIntervals: [EpochInterval]
    var statistics: [YearStatistics]
    var events: [SimulationEvent]
    var replay: [SimulationSnapshot]
    var nextReplayDays: Double
    var replayStrideDays: Double
}
