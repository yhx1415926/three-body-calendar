import Foundation
import Testing
@testable import SimulationCore

@Suite("轨道示例物理检查")
struct PresetCatalogTests {
    @Test("每个预设都具有完整合法的初始状态", arguments: OrbitPreset.allCases)
    func validInitialConditions(preset: OrbitPreset) throws {
        let scenario = Presets.scenario(for: preset, seed: 42)
        #expect(scenario.validationIssues().isEmpty)
        #expect(scenario.bodies.filter { $0.kind == .star }.count == 3)
        #expect(scenario.planet != nil || preset == .figureEight)
        #expect(scenario.standardYearDays.isFinite && scenario.standardYearDays > 0)
        #expect(!scenario.notes.isEmpty)
        let state = try NBodySimulation(scenario: scenario).snapshot
        #expect(state.diagnostics.centerOfMassPositionAU.length < 1e-12)
        #expect(state.diagnostics.centerOfMassVelocityAUPerDay.length < 1e-14)
    }

    @Test("层级示例五标准年无碰撞且守恒量收敛", arguments: OrbitPreset.allCases.filter { $0 != .random && $0 != .figureEight })
    func fiveYearSanity(preset: OrbitPreset) throws {
        let scenario = Presets.scenario(for: preset)
        let simulation = try NBodySimulation(scenario: scenario)
        for step in 1...40 {
            let state = try simulation.integrate(toDays: Double(step) / 8 * scenario.standardYearDays)
            #expect(simulation.status != .collision && simulation.status != .failed)
            #expect(state.bodies.count == 4)
            #expect(state.bodies.allSatisfy { $0.positionAU.isFinite && $0.velocityAUPerDay.isFinite })
            #expect(state.fluxEarth?.isFinite == true)
            #expect(state.diagnostics.normalizedEnergyError < 1e-9)
            #expect(state.diagnostics.normalizedAngularMomentumError < 1e-9)
            for i in state.bodies.indices {
                for j in state.bodies.indices where j > i {
                    #expect((state.bodies[i].positionAU - state.bodies[j].positionAU).length >
                            state.bodies[i].radiusAU + state.bodies[j].radiusAU)
                }
            }
        }
    }

    @Test("高偏心与逆行示例保留其明确的轨道含义")
    func eccentricityAndDirection() throws {
        let eccentric = Presets.eccentricPlanet()
        let planet = try #require(eccentric.planet)
        let host = try #require(eccentric.referenceStar)
        let r = planet.positionAU - host.positionAU
        let v = planet.velocityAUPerDay - host.velocityAUPerDay
        let mu = Astronomy.gravitationalConstant * (planet.massSolar + host.massSolar)
        let eccentricity = (v.cross(r.cross(v)) / mu - r / r.length).length
        #expect(abs(eccentricity - 0.60) < 1e-12)
        #expect(abs(r.length - 1.6) < 1e-12)

        let retrograde = Presets.retrogradePlanet()
        let retrogradePlanet = try #require(retrograde.planet)
        let retrogradeHost = try #require(retrograde.referenceStar)
        let angular = (retrogradePlanet.positionAU - retrogradeHost.positionAU)
            .cross(retrogradePlanet.velocityAUPerDay - retrogradeHost.velocityAUPerDay)
        #expect(angular.z < 0)
    }

    @Test("双日世界的行星绕双星质心而非一颗恒星")
    func circumbinaryStructure() throws {
        let scenario = Presets.circumbinaryPlanet()
        let stars = scenario.bodies.filter { $0.kind == .star }
        let planet = try #require(scenario.planet)
        let binaryMass = stars[0].massSolar + stars[1].massSolar
        let center = (stars[0].positionAU * stars[0].massSolar + stars[1].positionAU * stars[1].massSolar) / binaryMass
        let centerVelocity = (stars[0].velocityAUPerDay * stars[0].massSolar + stars[1].velocityAUPerDay * stars[1].massSolar) / binaryMass
        let relativePosition = planet.positionAU - center
        let relativeVelocity = planet.velocityAUPerDay - centerVelocity
        let mu = Astronomy.gravitationalConstant * (binaryMass + planet.massSolar)
        let semiMajorAxis = 1 / (2 / relativePosition.length - relativeVelocity.squaredLength / mu)
        #expect(abs(semiMajorAxis - 0.72) < 1e-11)
        #expect(abs(scenario.referenceDistanceAU - sqrt(0.32)) < 1e-12)
        #expect(relativePosition.length > (stars[0].positionAU - stars[1].positionAU).length * 4)
    }

    @Test("示例目录与旧的入口编号保持一致")
    func catalogIdentity() {
        #expect(Set(OrbitPreset.allCases.map(\.id)).count == 10)
        #expect(OrbitPreset(rawValue: 0) == .quietHierarchy)
        #expect(OrbitPreset(rawValue: 1) == .figureEight)
        #expect(OrbitPreset(rawValue: 2) == .random)
        #expect(Presets.redDwarfPlanet().standardYearDays > 35)
        #expect(Presets.redDwarfPlanet().standardYearDays < 38)
    }
}
