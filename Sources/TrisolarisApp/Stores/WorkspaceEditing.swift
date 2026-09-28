import Foundation
import SimulationCore

extension WorkspaceStore {
    func clearPositionEditing() {
        positionEditBackup = nil; positionEditInitial = nil; positionEditTrails = [:]
        positionUndo = nil; isPositionPreview = false
    }
    var usesDraftPositions: Bool { isPositionPreview || (interactionMode == .moveBodies && isDraftChanged) }
    var canEditBodies: Bool { !isLoading && !isComputing && positionEditBackup == nil }
    var canRemoveSelectedBody: Bool {
        guard let index = selectedBodyIndex else { return false }
        return draft.bodies[index].kind == .planet || draft.bodies.filter { $0.kind == .star }.count > 1
    }
    var classicRandomTemplate: Scenario {
        // Preserve the original three-star generator and its seed semantics.
        if draft.bodies.filter({ $0.kind == .star }).count == 3,
           draft.bodies.filter({ $0.kind == .planet }).count <= 1 { return draft }
        var template = Presets.stableHierarchy()
        let stars = draft.bodies.filter { $0.kind == .star }
        for index in 0..<min(3, stars.count) {
            template.bodies[index].massSolar = stars[index].massSolar
            template.bodies[index].radiusAU = stars[index].radiusAU
            template.bodies[index].luminositySolar = stars[index].luminositySolar
        }
        return template
    }

    func setInteractionMode(_ mode: OrbitInteractionMode) {
        guard !isLoading, !isComputing else { return }
        stopPlayback()
        interactionMode = mode
        if mode == .moveBodies { followSelected = false }
        notice = mode == .moveBodies ? "箭头模式：拖动天体调整位置；松开应用，Esc 撤销本次拖动" : "手型模式：拖动旋转，Shift 拖动平移"
    }

    func replaceScenario(_ scenario: Scenario) {
        guard canEditBodies else { return }
        stopAll()
        if let result { previousResult = result }
        result = nil; progress = nil; canResume = false; verificationSummary = nil
        clearPositionEditing()
        draft = scenario
        selectedBodyID = draft.bodies.first?.id.uuidString
        page = .observatory
        Task { await resetSimulation() }
    }

    func generateRandomSystem(stars: Int, planets: Int, seed: UInt64) throws {
        let scenario = try Presets.randomSystem(seed: seed, starCount: stars, planetCount: planets,
                                                spatialScaleAU: randomSpatialScaleAU, virialRatio: randomVirialRatio)
        replaceScenario(scenario)
    }

    func addBody(_ kind: BodyKind) {
        guard canEditBodies, draft.bodies.count < Scenario.maximumBodyCount,
              let host = draft.bodies.first(where: { $0.id.uuidString == selectedBodyID && $0.kind == .star }) ?? draft.referenceStar else { return }
        stopPlayback()
        let count = draft.bodies.filter { $0.kind == kind }.count
        let span = draft.bodies.map { ($0.positionAU-host.positionAU).length }.max() ?? 1
        var distance = kind == .star ? max(5,span * 1.5) : max(0.1,draft.referenceDistanceAU) * pow(1.7, Double(count))
        let direction = Vector3(cos(Double(count)*2.399963), sin(Double(count)*2.399963), 0)
        let mass = kind == .star ? 0.7 : Astronomy.earthMassSolar
        let radius = kind == .star ? 0.7*Astronomy.solarRadiusAU : Astronomy.earthRadiusAU
        for _ in 0..<64 {
            let point = host.positionAU + direction*distance
            if draft.bodies.allSatisfy({ ($0.positionAU-point).length > max(($0.radiusAU+radius)*4, distance*0.05) }) { break }
            distance *= 1.4
        }
        let point = host.positionAU + direction*distance
        let speed = sqrt(Astronomy.gravitationalConstant*(host.massSolar+mass)/distance)
        let body = CelestialBody(name: "\(kind == .star ? "恒星" : "行星") \(count+1)", kind: kind,
                                 massSolar: mass, radiusAU: radius, luminositySolar: kind == .star ? 0.2 : 0,
                                 positionAU: point, velocityAUPerDay: host.velocityAUPerDay + Vector3(-direction.y,direction.x,0)*speed)
        var scenario = draft
        scenario.bodies.append(body)
        if kind == .planet && scenario.calendarPlanetID == nil { scenario.calendarPlanetID = scenario.planet?.id }
        scenario.id = UUID()
        scenario.notes += " 天体列表已经手动修改。"
        replaceScenario(scenario)
        selectedBodyID = body.id.uuidString
    }

    func removeSelectedBody() {
        guard canEditBodies, canRemoveSelectedBody, let index = selectedBodyIndex else { return }
        var scenario = draft
        let removed = scenario.bodies.remove(at: index)
        if scenario.referenceStarID == removed.id, let star = scenario.bodies.first(where: { $0.kind == .star }) {
            scenario.referenceStarID = star.id
        }
        if scenario.calendarPlanetID == removed.id { scenario.calendarPlanetID = scenario.bodies.first { $0.kind == .planet }?.id }
        scenario.id = UUID()
        scenario.notes += " 天体列表已经手动修改。"
        replaceScenario(scenario)
        selectedBodyID = scenario.bodies[min(index,scenario.bodies.count-1)].id.uuidString
    }

    func moveBody(_ id: String, to position: SIMD3<Double>, phase: OrbitBodyMovePhase) {
        if phase == .cancelled {
            guard let backup = positionEditBackup else { return }
            draft = backup
            hasUnsavedChanges = positionEditWasDirty
            isPositionPreview = positionEditPreviousPreview
            trails = positionEditTrails
            positionEditBackup = nil; positionEditInitial = nil; positionEditTrails = [:]
            notice = "已撤销本次拖动"
            return
        }
        guard !isLoading, !isComputing, position.x.isFinite, position.y.isFinite, position.z.isFinite else { return }
        switch phase {
        case .began:
            stopAll()
            let showingDraft = usesDraftPositions
            positionEditBackup = draft
            positionEditWasDirty = hasUnsavedChanges
            positionEditPreviousPreview = isPositionPreview
            positionEditTrails = trails
            if !showingDraft, let snapshot {
                draft = displayedScenario
                draft.bodies = snapshot.bodies
            }
            positionEditInitial = draft
            selectedBodyID = id; isPositionPreview = true; trails = [:]
        case .changed:
            guard positionEditBackup != nil, let index = draft.bodies.firstIndex(where: { $0.id.uuidString == id }) else { return }
            draft.bodies[index].positionAU = Vector3(position.x,position.y,position.z)
        case .cancelled: break
        case .ended:
            guard let backup = positionEditBackup, let index = draft.bodies.firstIndex(where: { $0.id.uuidString == id }) else { return }
            draft.bodies[index].positionAU = Vector3(position.x,position.y,position.z)
            if let issue = draft.validationIssues().first {
                draft = backup
                hasUnsavedChanges = positionEditWasDirty
                isPositionPreview = positionEditPreviousPreview
                trails = positionEditTrails
                positionEditBackup = nil; positionEditInitial = nil; positionEditTrails = [:]
                notice = "位置未应用：" + issue.message
                return
            }
            positionUndo = positionEditInitial ?? backup
            positionEditBackup = nil; positionEditInitial = nil; positionEditTrails = [:]
            commitPositionEdit()
        }
    }

    func commitPositionEdit() {
        stopAll()
        if let result { previousResult = result }
        result = nil; progress = nil; canResume = false; isReplay = false
        draft.id = UUID()
        if !draft.notes.contains("位置已手动编辑") { draft.notes += " 位置已手动编辑，模拟从修改后的初始状态开始。" }
        Task { await resetSimulation(preserveCamera: true) }
    }

    func undoPositionEdit() {
        guard canEditBodies, let previous = positionUndo else { return }
        draft = previous; positionUndo = nil; isPositionPreview = true
        commitPositionEdit()
    }
}
