import Foundation
import Testing
import SimulationCore
@testable import TrisolarisApp

@MainActor
@Suite("位置编辑工作流")
struct WorkspaceEditingTests {
    @Test("多天体编辑、历法行星删除和经典生成衔接")
    func multipleBodyWorkflow() async throws {
        let store = await makeStore()
        defer { store.shutdown() }
        try store.generateRandomSystem(stars: 5, planets: 3, seed: 314159)
        try await waitForScenarioReset(store)
        #expect(store.activeScenario.bodies.count == 8)
        #expect(store.validationMessages.isEmpty)
        let planets = store.draft.bodies.filter { $0.kind == .planet }
        store.draft.calendarPlanetID = planets[1].id
        store.selectedBodyID = planets[1].id.uuidString
        store.removeSelectedBody()
        try await waitForScenarioReset(store)
        #expect(store.activeScenario.planet?.id == planets[0].id)
        #expect(store.draft.bodies.count == 7)
        store.addBody(.star)
        try await waitForScenarioReset(store)
        #expect(store.draft.bodies.filter { $0.kind == .star }.count == 6)
        #expect(store.validationMessages.isEmpty)
        store.choosePreset(2, seed: 123)
        try await waitForScenarioReset(store)
        #expect(store.draft.bodies.filter { $0.kind == .star }.count == 3)
        #expect(store.draft.bodies.filter { $0.kind == .planet }.count == 1)
        #expect(store.validationMessages.isEmpty)
    }

    @Test("最后一颗恒星不能删除，额外行星可添加和移除")
    func minimumBodies() async throws {
        let store = await makeStore()
        defer { store.shutdown() }
        try store.generateRandomSystem(stars: 1, planets: 0, seed: 1)
        try await waitForScenarioReset(store)
        store.selectedBodyID = store.draft.bodies[0].id.uuidString
        #expect(!store.canRemoveSelectedBody)
        store.removeSelectedBody()
        #expect(store.draft.bodies.count == 1)
        store.addBody(.planet)
        try await waitForScenarioReset(store)
        #expect(store.draft.planet != nil)
        #expect(store.validationMessages.isEmpty)
        store.removeSelectedBody()
        try await waitForScenarioReset(store)
        #expect(store.draft.planet == nil)
        #expect(store.draft.bodies.count == 1)
    }

    @Test("拖动中禁止计算，已提交的位置可撤销")
    func undoAndBlockCalculation() async throws {
        let store = await makeStore()
        defer { store.shutdown() }
        let original = store.draft
        let body = try #require(original.bodies.last)
        let moved = point(body) + SIMD3(0.3, 0.1, 0)
        store.moveBody(body.id.uuidString, to: point(body), phase: .began)
        store.startCalendar()
        store.togglePlayback()
        #expect(!store.isComputing && !store.isPlaying)
        store.moveBody(body.id.uuidString, to: moved, phase: .ended)
        try await waitForCommit(store)
        store.undoPositionEdit()
        try await waitForCommit(store)
        #expect(store.activeScenario.bodies == original.bodies)
        #expect(store.positionUndo == nil)
    }

    private func makeStore() async -> WorkspaceStore {
        let store = WorkspaceStore()
        await store.resetSimulation(markDirty: false)
        store.setInteractionMode(.moveBodies)
        return store
    }

    private func point(_ body: CelestialBody) -> SIMD3<Double> {
        SIMD3(body.positionAU.x, body.positionAU.y, body.positionAU.z)
    }

    @Test("运行后的显示帧转换为草稿，取消完整恢复原草稿与轨迹")
    func currentFrameAndCancellation() async throws {
        let store = await makeStore()
        defer { store.shutdown() }
        let original = store.draft
        let simulation = try NBodySimulation(scenario: original)
        let displayed = try simulation.integrate(toDays: original.standardYearDays / 8)
        store.snapshot = displayed
        let body = try #require(displayed.bodies.last)
        let id = body.id.uuidString
        let originalTrails = [id: [point(body), point(body) + SIMD3(0.1, 0, 0)]]
        store.trails = originalTrails
        store.hasUnsavedChanges = false

        store.moveBody(id, to: point(body), phase: .began)
        #expect(store.draft.bodies == displayed.bodies)
        #expect(store.trails.isEmpty)
        #expect(store.isPositionPreview)
        let moved = point(body) + SIMD3(0.2, -0.1, 0.05)
        store.moveBody(id, to: moved, phase: .changed)
        #expect(store.frame.bodies.last?.position == moved)
        #expect(store.draft.bodies.last?.velocityAUPerDay == body.velocityAUPerDay)
        #expect(store.activeScenario == original)

        store.moveBody(id, to: point(body), phase: .cancelled)
        #expect(store.draft == original)
        #expect(store.snapshot == displayed)
        #expect(store.trails == originalTrails)
        #expect(!store.hasUnsavedChanges)
        #expect(store.positionEditBackup == nil)
        #expect(!store.isPositionPreview)
        #expect(store.frame.bodies.last?.position == point(body))
    }

    @Test("取消不丢失已有参数草稿及其未保存标记")
    func preserveExistingDraft() async throws {
        let store = await makeStore()
        defer { store.shutdown() }
        store.draft.name = "尚未应用的自定义参数"
        store.draft.bodies[0].massSolar *= 1.1
        let before = store.draft
        let body = try #require(before.bodies.last)
        store.moveBody(body.id.uuidString, to: point(body), phase: .began)
        store.moveBody(body.id.uuidString, to: point(body) + SIMD3(0.2, 0, 0), phase: .changed)
        store.moveBody(body.id.uuidString, to: point(body), phase: .cancelled)
        #expect(store.draft == before)
        #expect(store.hasUnsavedChanges)
        #expect(store.isDraftChanged)
        #expect(store.usesDraftPositions)
    }

    @Test("松开使用最终坐标，重建一次初始状态且保留视角")
    func commitFinalPosition() async throws {
        let store = await makeStore()
        defer { store.shutdown() }
        let original = store.draft
        let body = try #require(original.bodies.last)
        let id = body.id.uuidString
        let resetToken = store.resetToken
        let final = point(body) + SIMD3(0.3, 0.2, 0.1)
        store.moveBody(id, to: point(body), phase: .began)
        store.moveBody(id, to: point(body) + SIMD3(0.1, 0, 0), phase: .changed)
        store.moveBody(id, to: final, phase: .ended)
        try await waitForCommit(store)
        #expect(store.frame.bodies.last?.position == final)
        #expect(store.activeScenario.bodies.last?.positionAU == Vector3(final.x, final.y, final.z))
        #expect(store.activeScenario.bodies.last?.velocityAUPerDay == body.velocityAUPerDay)
        #expect(Array(store.activeScenario.bodies.dropLast()) == Array(original.bodies.dropLast()))
        #expect(store.snapshot?.timeDays == 0)
        #expect(store.resetToken == resetToken)
        #expect(store.positionEditBackup == nil)
        #expect(!store.isPositionPreview)
        #expect(store.positionUndo != nil)
    }

    @Test("恒星内部的落点不能替换有效物理状态")
    func overlappingDropDoesNotCommit() async throws {
        let store = await makeStore()
        defer { store.shutdown() }
        let original = store.activeScenario
        let snapshot = store.snapshot
        let body = try #require(store.draft.bodies.last)
        let star = try #require(store.draft.bodies.first)
        store.moveBody(body.id.uuidString, to: point(body), phase: .began)
        store.moveBody(body.id.uuidString, to: point(star), phase: .changed)
        store.moveBody(body.id.uuidString, to: point(star), phase: .ended)
        // Give any erroneously scheduled reset a chance to execute.
        try await Task.sleep(for: .milliseconds(10))
        #expect(store.activeScenario == original)
        #expect(store.snapshot == snapshot)
        #expect(store.positionEditBackup == nil)
        #expect(!store.notice.isEmpty)
    }

    private func waitForScenarioReset(_ store: WorkspaceStore) async throws {
        for _ in 0..<1_000 {
            if store.draft == store.activeScenario { return }
            try await Task.sleep(for: .milliseconds(1))
        }
        Issue.record("新星系未完成初始化")
    }

    private func waitForCommit(_ store: WorkspaceStore) async throws {
        for _ in 0..<1_000 {
            if !store.isPositionPreview { return }
            try await Task.sleep(for: .milliseconds(1))
        }
        Issue.record("拖动提交未完成")
    }
}
