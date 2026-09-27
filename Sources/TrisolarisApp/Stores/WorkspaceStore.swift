import AppKit
import Foundation
import Observation
import SimulationCore
import UniformTypeIdentifiers

@MainActor @Observable
final class WorkspaceStore {
    var draft = Presets.stableHierarchy() {
        didSet { if draft != oldValue { edited() } }
    }
    var activeScenario = Presets.stableHierarchy()
    var page: WorkspacePage = .observatory
    var selectedBodyID: String?
    var snapshot: SimulationSnapshot?
    var result: CalendarResult?
    var previousResult: CalendarResult?
    var progress: SimulationProgress?
    var trails: [String: [SIMD3<Double>]] = [:]
    var isPlaying = false
    var isComputing = false
    var canResume = false
    var isSaving = false
    var isLoading = false
    var hasUnsavedChanges = false
    var playbackRate = 0.12
    var usesManualPlaybackRate = false
    var manualPlaybackPosition = PlaybackSampling.sliderPosition(for: 0.12)
    var randomSpatialScaleAU = 8.0
    var randomVirialRatio = 0.4
    var followSelected = false
    var topDown = false
    var resetToken = 0
    var captureToken = 0
    var selectedYear: Int?
    var replayIndex = 0.0
    var isReplay = false
    var errorMessage: String?
    var notice = "准备就绪"
    var projectURL: URL?
    var verificationSummary: String?
    var calculationStartedAt: Date?
    var elapsedCalculationSeconds = 0.0

    @ObservationIgnored private let worker = SimulationWorker()
    @ObservationIgnored private var playbackTask: Task<Void, Never>?
    @ObservationIgnored private var trailHistory = OrbitTrailHistory()
    @ObservationIgnored private var playbackToken = UUID()
    @ObservationIgnored private var calculationTask: Task<Void, Never>?
    @ObservationIgnored private var autosaveTask: Task<Void, Never>?
    @ObservationIgnored private var sessionToken = UUID()
    @ObservationIgnored private var bootstrapped = false
    @ObservationIgnored private var changeRevision: UInt64 = 0
    @ObservationIgnored private var isVerification = false
    @ObservationIgnored private var captureDestination: URL?
    @ObservationIgnored private var comparisonResult: CalendarResult?
    @ObservationIgnored private let recoveryID = UUID().uuidString
    @ObservationIgnored private static var didRestoreRecovery = false

    var isDraftChanged: Bool { draft != activeScenario }
    var displayedScenario: Scenario { isReplay ? (result?.scenario ?? activeScenario) : activeScenario }
    var standardYearDays: Double { displayedScenario.standardYearDays }
    var currentYear: Double { (snapshot?.timeDays ?? 0) / max(standardYearDays, 1e-20) }
    var validationMessages: [String] { draft.validationIssues().map(\.message) }
    var selectedBodyIndex: Int? { draft.bodies.firstIndex { $0.id.uuidString == selectedBodyID } }
    var frame: OrbitSceneFrame {
        let bodies = snapshot?.bodies ?? activeScenario.bodies
        return OrbitSceneFrame(time: snapshot?.timeDays ?? 0, bodies: bodies.enumerated().map { index, body in
            RenderBody(id: body.id.uuidString, name: body.name,
                       position: SIMD3(body.positionAU.x, body.positionAU.y, body.positionAU.z),
                       radius: body.radiusAU, color: ObservatoryPalette.rgb[index % 4], isStar: body.kind == .star)
        })
    }
    var stableYears: Int { result?.years.filter { $0.isComplete && $0.kind == .stable }.count ?? 0 }
    var totalCompletedYears: Int { result?.years.filter(\.isComplete).count ?? 0 }
    var stablePercentage: Double {
        guard let years = result?.years.filter(\.isComplete), !years.isEmpty else { return 0 }
        return years.reduce(0) { $0 + $1.stableFraction } / Double(years.count) * 100
    }

    func bootstrap() async {
        guard !bootstrapped else { return }
        bootstrapped = true
        activeScenario = draft
        selectedBodyID = draft.bodies.first?.id.uuidString
        if !Self.didRestoreRecovery {
            Self.didRestoreRecovery = true
            if let path = UserDefaults.standard.string(forKey: "lastRecoveryPath"), FileManager.default.fileExists(atPath: path) {
                do {
                    try await load(URL(fileURLWithPath: path), recovery: true)
                    notice = "已恢复上次工作 · " + notice
                    return
                } catch { notice = "恢复文件无法读取，已打开新项目" }
            }
        }
        await resetSimulation(markDirty: false)
    }

    func edited() { hasUnsavedChanges = true; changeRevision &+= 1 }

    func choosePreset(_ index: Int, seed: UInt64 = UInt64.random(in: 1...UInt64.max)) {
        guard !isLoading, let preset = OrbitPreset(rawValue: index) else { return }
        stopAll()
        if let result { previousResult = result }
        result = nil; progress = nil; canResume = false; verificationSummary = nil
        draft = preset == .random
            ? Presets.random(seed: seed, template: draft, spatialScaleAU: randomSpatialScaleAU, virialRatio: randomVirialRatio)
            : Presets.scenario(for: preset)
        selectedBodyID = draft.bodies.first?.id.uuidString
        Task { await resetSimulation() }
    }

    func resetSimulation(markDirty: Bool = true) async {
        guard !isLoading else { return }
        guard !isComputing else { notice = "请先暂停历法计算，再应用新的初始条件"; return }
        guard validationMessages.isEmpty else { errorMessage = validationMessages.joined(separator: "\n"); return }
        stopPlayback()
        isReplay = false
        let token = UUID(); sessionToken = token
        do {
            let fresh = try await worker.prepareLive(draft)
            guard sessionToken == token else { return }
            activeScenario = draft; snapshot = fresh; trails = [:]; appendTrail(fresh)
            resetToken += 1; notice = "初始条件已应用"
            if markDirty { hasUnsavedChanges = true }
        } catch { errorMessage = error.localizedDescription }
    }

    func togglePlayback() {
        guard !isLoading else { return }
        if isPlaying { stopPlayback(); return }
        if isComputing { notice = "历法正在计算，可在完成后回放"; return }
        Task {
            if isReplay, let result {
                do {
                    _ = try await worker.seekLive(scenario: result.scenario, targetDays: snapshot?.timeDays ?? 0, samples: result.snapshots)
                    activeScenario = result.scenario; isReplay = false
                } catch { errorMessage = error.localizedDescription; return }
            } else if isDraftChanged || snapshot == nil { await resetSimulation() }
            guard validationMessages.isEmpty else { return }
            beginPlayback()
        }
    }

    private func beginPlayback() {
        playbackTask?.cancel()
        let token = UUID()
        playbackToken = token
        isPlaying = true
        playbackTask = Task {
            let clock = ContinuousClock()
            var lastFrame = clock.now
            var firstFrame = true
            while !Task.isCancelled && isPlaying && playbackToken == token {
                do {
                    let now = clock.now
                    let elapsed = lastFrame.duration(to: now).components
                    let seconds = firstFrame ? 1.0 / 30 : min(1.0 / 15, max(1.0 / 120, Double(elapsed.seconds) + Double(elapsed.attoseconds) / 1e18))
                    firstFrame = false
                    lastFrame = now
                    let frames = try await worker.advanceLiveSampled(years: playbackRate * seconds)
                    guard !Task.isCancelled, playbackToken == token else { break }
                    if let frame = frames.last {
                        snapshot = frame
                        appendTrails(frames)
                    }
                    try await clock.sleep(until: now.advanced(by: .milliseconds(33)))
                } catch is CancellationError { break }
                catch {
                    if playbackToken == token { errorMessage = error.localizedDescription; isPlaying = false }
                    break
                }
            }
        }
    }

    func step() {
        guard !isLoading else { return }
        stopPlayback()
        guard !isComputing else { return }
        Task {
            do {
                if isDraftChanged || isReplay { await resetSimulation() }
                if let frame = try await worker.advanceLive(years: 1.0 / 128) { snapshot = frame; appendTrail(frame) }
            } catch { errorMessage = error.localizedDescription }
        }
    }

    func stopPlayback() { playbackToken = UUID(); isPlaying = false; playbackTask?.cancel(); playbackTask = nil }

    func setManualPlaybackPosition(_ position: Double) {
        manualPlaybackPosition = min(1, max(0, position))
        usesManualPlaybackRate = true
        playbackRate = PlaybackSampling.rate(at: manualPlaybackPosition)
    }

    var trailRetentionYears: Double {
        Double(PlaybackSampling.pointLimit(preference: UserDefaults.standard.integer(forKey: "trailPoints"))) / PlaybackSampling.samplesPerYear
    }

    func startCalendar(strict: Bool = false) {
        guard !isLoading else { return }
        guard !isComputing else { return }
        guard validationMessages.isEmpty else { errorMessage = validationMessages.joined(separator: "\n"); return }
        guard draft.planet != nil else { errorMessage = "请先添加一颗行星，再生成万年历。"; return }
        stopPlayback(); calculationTask?.cancel()
        comparisonResult = strict ? result : nil
        isVerification = strict
        if let result { previousResult = result }
        var configuration = strict ? (result?.scenario ?? draft) : draft
        if strict { configuration.numerics = .strict }
        isComputing = true; canResume = false; isReplay = false
        calculationStartedAt = .now; elapsedCalculationSeconds = 0
        notice = strict ? "正在进行更严格的独立复算" : "正在生成万年历"
        let token = UUID(); sessionToken = token
        calculationTask = Task {
            do {
                let initial = try await worker.startCalendar(configuration)
                guard sessionToken == token, !Task.isCancelled else { return }
                activeScenario = configuration
                draft = configuration
                result = nil; trails = [:]
                accept(initial)
                await calculationLoop(token: token)
            } catch { calculationFailed(error, token: token) }
        }
    }

    func pauseCalendar() {
        guard isComputing else { return }
        calculationTask?.cancel(); calculationTask = nil
        isComputing = false; canResume = true; notice = "计算已暂停，可保存后继续"
        let token = sessionToken
        Task {
            if let update = await worker.calendarUpdate(includeResult: true), sessionToken == token, !isComputing { accept(update) }
            await autosave()
        }
    }

    func resumeCalendar() {
        guard !isLoading, canResume, !isComputing else { return }
        stopPlayback(); isComputing = true; canResume = false; notice = "继续计算万年历"
        if let result { activeScenario = result.scenario }
        isReplay = false
        calculationStartedAt = Date().addingTimeInterval(-elapsedCalculationSeconds)
        let token = sessionToken
        calculationTask = Task { await calculationLoop(token: token) }
    }

    func cancelCalendar() {
        guard !isLoading else { return }
        calculationTask?.cancel(); calculationTask = nil
        isComputing = false; canResume = false; notice = "计算已取消，已完成年份已保留"
        let token = sessionToken
        Task {
            if let update = await worker.calendarUpdate(includeResult: true), sessionToken == token, !isComputing { accept(update) }
            if sessionToken == token { await autosave() }
        }
    }

    func extendCalendar() {
        guard !isLoading else { return }
        guard let result, draft.durationYears > result.scenario.durationYears else { return }
        var candidate = draft; candidate.durationYears = result.scenario.durationYears
        guard candidate == result.scenario else { errorMessage = "延长计算要求除年数以外的参数与原结果一致。请还原其他改动，或开始新的计算。"; return }
        Task {
            do {
                if let update = try await worker.extend(to: draft.durationYears, expectedScenario: result.scenario) {
                    activeScenario = draft; accept(update); canResume = true; resumeCalendar()
                }
            } catch { errorMessage = error.localizedDescription }
        }
    }

    private func calculationLoop(token: UUID) async {
        var lastResult = Date.distantPast
        var lastPublished = Date.distantPast
        var lastRecovery = Date.now
        do {
            while !Task.isCancelled && isComputing && sessionToken == token {
                let includeResult = Date().timeIntervalSince(lastResult) > 0.8
                guard let update = try await worker.advanceCalendar(includeResult: includeResult) else { break }
                guard !Task.isCancelled, sessionToken == token else { return }
                if includeResult || Date().timeIntervalSince(lastPublished) >= 0.15 || update.progress.status != .running {
                    accept(update); lastPublished = .now
                }
                if includeResult { lastResult = .now }
                if let started = calculationStartedAt { elapsedCalculationSeconds = Date().timeIntervalSince(started) }
                if update.progress.status != .running && update.progress.status != .ready {
                    isComputing = false; canResume = false
                    notice = update.progress.status == .completed ? "万年历计算完成" : "计算已停止，请查看事件记录"
                    if isVerification { compareVerification() }
                    await autosave(); return
                }
                if Date().timeIntervalSince(lastRecovery) > 20 { await autosave(); lastRecovery = .now }
                await Task.yield()
            }
        } catch is CancellationError {
            return
        } catch { calculationFailed(error, token: token) }
    }

    private func calculationFailed(_ error: Error, token: UUID) {
        guard sessionToken == token else { return }
        isComputing = false; canResume = false
        errorMessage = error.localizedDescription; notice = "计算停止：已有结果保留"
        Task {
            if let update = await worker.calendarUpdate(includeResult: true), sessionToken == token { accept(update) }
            if sessionToken == token { await autosave() }
        }
    }

    private func accept(_ update: WorkUpdate) {
        snapshot = update.snapshot; progress = update.progress
        if let result = update.result { self.result = result }
        appendTrail(update.snapshot); edited()
    }

    func appendTrail(_ frame: SimulationSnapshot) {
        appendTrails([frame])
    }

    private func appendTrails(_ frames: [SimulationSnapshot]) {
        if trails.isEmpty { trailHistory = OrbitTrailHistory() }
        let limit = PlaybackSampling.pointLimit(preference: UserDefaults.standard.integer(forKey: "trailPoints"))
        for frame in frames {
            let positions = Dictionary(uniqueKeysWithValues: frame.bodies.map {
                ($0.id.uuidString, SIMD3($0.positionAU.x, $0.positionAU.y, $0.positionAU.z))
            })
            trailHistory.append(time: frame.timeDays, positions: positions, yearDays: standardYearDays, pointLimit: limit)
        }
        trails = trailHistory.points
    }

    func showYear(_ year: CalendarYear) {
        selectedYear = year.year
        showOrbit(at: year.startDays, label: "第 \(year.year) 年年初")
    }

    func showOrbit(at timeDays: Double, label: String) {
        guard !isLoading, !isComputing, let result, !result.snapshots.isEmpty else { return }
        stopPlayback(); page = .observatory; notice = "正在恢复\(label)的轨道"
        let token = sessionToken
        Task {
            do {
                let frames = try await worker.seekLive(scenario: result.scenario, targetDays: timeDays, samples: result.snapshots)
                guard sessionToken == token else { return }
                trails = [:]
                for frame in frames { appendTrail(frame) }
                snapshot = frames.last; isReplay = true; activeScenario = result.scenario
                notice = "\(label)轨道 · 从保存状态重新积分定位"
            } catch { errorMessage = error.localizedDescription }
        }
    }

    func seekReplay(_ index: Double) {
        guard !isLoading, !isComputing, let samples = result?.snapshots, !samples.isEmpty else { return }
        stopPlayback(); isReplay = true
        let i = min(samples.count - 1, max(0, Int(index.rounded())))
        replayIndex = Double(i); snapshot = samples[i]; trails = [:]
        for sample in samples[max(0, i - 150)...i] { appendTrail(sample) }
    }

    private func compareVerification() {
        guard let original = comparisonResult, let verified = result else { return }
        let pairs = zip(original.years, verified.years).filter { $0.isComplete && $1.isComplete }
        let differing = pairs.filter { $0.kind != $1.kind }.count
        let maximumFractionDifference = pairs.map { abs($0.stableFraction - $1.stableFraction) }.max() ?? 0
        verificationSummary = differing == 0 ? "\(pairs.count) 个已完成年度标签一致；稳定占比最大差异 \((maximumFractionDifference * 100).display(5))%。" : "\(differing) 个年度标签发生分歧；混沌轨迹或边界敏感性需要进一步分析。"
        isVerification = false; comparisonResult = nil
    }

    func addOrRemovePlanet() {
        guard !isLoading, !isComputing else { return }
        if let planet = draft.planet { draft.bodies.removeAll { $0.id == planet.id } }
        else if let star = draft.referenceStar {
            let radius = draft.referenceDistanceAU
            let speed = sqrt(Astronomy.gravitationalConstant * (star.massSolar + Astronomy.earthMassSolar) / radius)
            let body = CelestialBody(name: "行星 · 文明之舟", kind: .planet, massSolar: Astronomy.earthMassSolar, radiusAU: Astronomy.earthRadiusAU,
                                     positionAU: star.positionAU + Vector3(radius, 0, 0), velocityAUPerDay: star.velocityAUPerDay + Vector3(0, speed, 0))
            draft.bodies.append(body); selectedBodyID = body.id.uuidString
        }
        edited()
    }

    func restorePreviousResult() {
        guard let previousResult, !isComputing else { return }
        let current = result; result = previousResult; self.previousResult = current
        activeScenario = previousResult.scenario; draft = previousResult.scenario
        snapshot = previousResult.finalSnapshot; progress = previousResult.progress
        canResume = false; isReplay = true; trails = [:]; resetToken += 1
        notice = "正在查看上一份结果；续算请重新载入对应项目"
    }

    func stopAll() {
        sessionToken = UUID(); stopPlayback(); calculationTask?.cancel(); calculationTask = nil; isComputing = false
    }

    func shutdown() { stopAll(); autosaveTask?.cancel() }

    func openProject() {
        let panel = NSOpenPanel(); panel.allowedContentTypes = [.json, UTType(filenameExtension: "trisolaris") ?? .data]
        panel.allowsMultipleSelection = false; panel.canChooseDirectories = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        openProject(at: url)
    }

    func openProject(at url: URL) {
        guard !isLoading else { return }
        Task {
            if hasUnsavedChanges {
                let alert = NSAlert(); alert.messageText = "打开另一个项目前保存当前项目？"
                alert.informativeText = "当前项目有尚未保存的修改。"
                alert.addButton(withTitle: "保存"); alert.addButton(withTitle: "不保存"); alert.addButton(withTitle: "取消")
                let response = alert.runModal()
                if response == .alertThirdButtonReturn { return }
                if response == .alertFirstButtonReturn, !(await saveProject()) { return }
            }
            do { try await load(url) } catch { errorMessage = error.localizedDescription }
        }
    }

    @discardableResult func saveProject(saveAs: Bool = false) async -> Bool {
        guard !isLoading, !isSaving else { return false }
        var destination = projectURL
        if saveAs || destination == nil {
            let panel = NSSavePanel(); panel.allowedContentTypes = [UTType(filenameExtension: "trisolaris") ?? .json]
            panel.nameFieldStringValue = draft.name + ".trisolaris"
            guard panel.runModal() == .OK, let url = panel.url else { return false }
            destination = url
        }
        guard let destination else { return false }
        isSaving = true
        let revision = changeRevision
        let token = sessionToken
        defer { isSaving = false }
        do {
            let archive = try await makeArchive()
            try await ProjectFileIO.shared.write(archive, to: destination)
            guard sessionToken == token else { return true }
            projectURL = destination
            if revision == changeRevision { hasUnsavedChanges = false }
            notice = "项目已保存"
            return true
        } catch { errorMessage = error.localizedDescription; return false }
    }

    private func makeArchive() async throws -> ProjectArchive {
        let token = sessionToken
        let savedDraft = draft, savedActive = activeScenario, savedResult = result, savedPrevious = previousResult
        let (checkpoint, latestResult) = try await worker.exportState()
        guard sessionToken == token else { throw SimulationError.invalidCheckpoint("保存期间项目发生切换，请在当前项目中重新保存。") }
        let matching = latestResult != nil && (latestResult?.scenario == savedResult?.scenario || (savedResult == nil && latestResult?.scenario == savedActive))
        return ProjectArchive(draft: savedDraft, activeScenario: savedActive, result: matching ? (latestResult ?? savedResult) : savedResult,
                              previousResult: savedPrevious, checkpoint: matching ? checkpoint : nil)
    }

    private func load(_ url: URL, recovery: Bool = false) async throws {
        stopAll()
        let token = sessionToken
        isLoading = true
        notice = "正在读取项目与历法…"
        defer { isLoading = false }
        let archive = try await ProjectFileIO.shared.read(from: url)
        guard token == sessionToken, !Task.isCancelled else { throw CancellationError() }
        guard archive.formatVersion == 1 else { throw SimulationError.invalidCheckpoint("项目格式版本不受支持。") }
        let issues = archive.draft.validationIssues()
        guard issues.isEmpty else { throw SimulationError.invalidScenario(issues.map(\.message)) }
        notice = "正在恢复计算状态…"
        var restoredUpdate: WorkUpdate?
        var restoredLive: SimulationSnapshot?
        var recoveryWarning: String?
        if let checkpoint = archive.checkpoint {
            do { restoredUpdate = try await worker.restore(checkpoint) }
            catch {
                guard archive.result != nil else { throw error }
                await worker.discardCalendar()
                recoveryWarning = "已打开保存结果；检查点不兼容或已损坏，可查看与回放，继续历法请重新生成"
            }
        } else {
            await worker.discardCalendar()
            if archive.result == nil { restoredLive = try await worker.prepareLive(archive.activeScenario) }
        }
        guard token == sessionToken, !Task.isCancelled else { throw CancellationError() }
        draft = archive.draft; activeScenario = archive.activeScenario; result = archive.result; previousResult = archive.previousResult
        if let update = restoredUpdate {
            accept(update); canResume = update.progress.status == .running || update.progress.status == .ready
            if let savedResult = update.result { activeScenario = savedResult.scenario }
        } else {
            if let savedSnapshot = archive.result?.finalSnapshot { snapshot = savedSnapshot }
            else { snapshot = restoredLive }
            progress = archive.result?.progress; canResume = false
        }
        selectedBodyID = draft.bodies.first?.id.uuidString
        projectURL = recovery ? nil : url; trails = [:]; resetToken += 1
        isReplay = result != nil; hasUnsavedChanges = recovery
        notice = recoveryWarning ?? (canResume ? "计算保持暂停，可继续计算" : "项目已打开")
    }

    private func autosave() async {
        do {
            let directory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("TrisolarisCalendar/Recovery", isDirectory: true)
            let url = directory.appendingPathComponent(recoveryID + ".trisolaris")
            let archive = try await makeArchive()
            try await ProjectFileIO.shared.write(archive, to: url, createDirectory: true)
            UserDefaults.standard.set(url.path, forKey: "lastRecoveryPath")
        } catch { notice = "自动恢复副本写入失败，请手动保存项目" }
    }

    func exportResult(asCSV: Bool, annualDetails: Bool = false) {
        guard let result else { return }
        let panel = NSSavePanel(); panel.allowedContentTypes = [asCSV ? .commaSeparatedText : .json]
        panel.nameFieldStringValue = result.scenario.name + (asCSV ? (annualDetails ? "-年度明细.csv" : "-纪元区间.csv") : "-计算结果.json")
        guard panel.runModal() == .OK, let url = panel.url else { return }
        notice = "正在导出结果"
        Task {
            do {
                try await ProjectFileIO.shared.export(result, to: url, asCSV: asCSV, annualDetails: annualDetails)
                notice = "结果已导出"
            } catch { errorMessage = error.localizedDescription }
        }
    }

    func requestScenePNG() {
        let panel = NSSavePanel(); panel.allowedContentTypes = [.png]
        panel.nameFieldStringValue = draft.name + "-轨道.png"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        captureDestination = url; page = .observatory; captureToken += 1
        notice = "正在导出三维场景"
    }

    func receiveScenePNG(_ data: Data) {
        guard let destination = captureDestination else { return }
        captureDestination = nil
        do { try data.write(to: destination, options: .atomic); notice = "轨道图像已导出" }
        catch { errorMessage = error.localizedDescription }
    }
}
