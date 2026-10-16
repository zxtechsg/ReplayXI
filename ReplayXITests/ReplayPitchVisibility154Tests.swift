import RealityKit
import XCTest
@testable import ReplayXI

/// Every match review view keeps turf. Physical positioning uses local markers.
@MainActor
final class ReplayPitchVisibility154Tests: XCTestCase {
    func testPreparedPitchVisibilityAcrossAllModesPreservesSubtree154() throws {
        // The immutable pitch template is shared, as in ReplayStrategyPitchTests;
        // it has no test reset. Do not substitute the procedural fallback.
        try ReplayStrategyPitchProvider.prewarm()
        let previousExperiment = PitchSceneFactory.fullSquadSkinsForTesting
        PitchSceneFactory.fullSquadSkinsForTesting = false
        defer { PitchSceneFactory.fullSquadSkinsForTesting = previousExperiment }
        let scenario = try XCTUnwrap(DemoScenarios.scenario(for: .shapeLab))
        let sourcePlayers = scenario.players, sourceBall = scenario.ball
        let root = PitchSceneFactory.makeMatchRoot(for: scenario)
        defer { for child in Array(root.children) { child.removeFromParent() } }
        let pitch = try XCTUnwrap(root.findEntity(named: "pitch"))
        XCTAssertTrue(pitch.components.has(ReplayStrategyPitchProvider.Admission.self))
        let turf = try XCTUnwrap(pitch.findEntity(named: "field-surface") as? ModelEntity)
        let markings = try XCTUnwrap(pitch.findEntity(named: "pitch-markings-and-goals") as? ModelEntity)
        let rim = try XCTUnwrap(pitch.findEntity(named: "tactical-board-rim"))
        let contrast = try XCTUnwrap(pitch.findEntity(named: "first-person-pitch-contrast-state"))
        XCTAssertTrue(markings.isEnabled)

        // Strong refs keep public mesh/texture identities meaningful throughout
        // toggles. Compare textures by resource equality, not Swift wrapper ID.
        let turfMesh = try XCTUnwrap(turf.model?.mesh), markingsMesh = try XCTUnwrap(markings.model?.mesh)
        let turfTextures = try XCTUnwrap(turf.model).materials.map { material in
            try XCTUnwrap(try XCTUnwrap(material as? UnlitMaterial).color.texture?.resource)
        }
        XCTAssertEqual(turfTextures.count, 2)
        let nodes = subtree(pitch)
        let nodeIDs = nodes.map(ObjectIdentifier.init)
        let localTransforms = nodes.map(\.transform)
        let childNames = pitch.children.map(\.name)
        let modes: [ReplayViewMode] = [.tacticalTable, .touchline, .firstPerson, .positional,
                                       .firstPerson, .touchline, .tacticalTable]
        XCTAssertEqual(Set(modes), Set(ReplayViewMode.allCases))

        for mode in modes {
            PitchSceneFactory.update(root: root, scenario: scenario, time: 0, viewMode: mode,
                perspectiveID: scenario.defaultPerspectiveID, marks: scenario.coachMarks,
                showsLaneLens: false, isDrawing: false, positionalOriginTransform: nil)
            let context = "Prepared pitch / \(mode.rawValue)"
            let hasTurf = mode != .positional
            let hasPitch = mode != .positional
            XCTAssertTrue(root.isEnabled, context)
            XCTAssertEqual(pitch.isEnabled, hasPitch, context)
            XCTAssertEqual(pitch.isEnabledInHierarchy, hasPitch, context)
            XCTAssertEqual(turf.isEnabled, hasTurf, context)
            XCTAssertEqual(turf.isEnabledInHierarchy, hasTurf, context)
            XCTAssertTrue(markings.isEnabled, "Markings remain locally enabled: \(context)")
            XCTAssertEqual(markings.isEnabledInHierarchy, hasPitch, context)
            XCTAssertEqual(rim.isEnabled, mode == .tacticalTable, context)
            XCTAssertEqual(rim.isEnabledInHierarchy, mode == .tacticalTable, context)
            XCTAssertEqual(contrast.isEnabled, mode == .firstPerson, context)

            XCTAssertTrue(root.findEntity(named: "pitch") === pitch, context)
            XCTAssertTrue(pitch.components.has(ReplayStrategyPitchProvider.Admission.self), context)
            XCTAssertEqual(pitch.children.map(\.name), childNames, context)
            let currentNodes = subtree(pitch)
            XCTAssertEqual(currentNodes.map(ObjectIdentifier.init), nodeIDs, "No subtree replacement: \(context)")
            XCTAssertTrue(currentNodes.map(\.transform) == localTransforms, "No local import-transform drift: \(context)")
            XCTAssertTrue(turf.model?.mesh === turfMesh, context)
            XCTAssertTrue(markings.model?.mesh === markingsMesh, context)
            let currentTextures = try XCTUnwrap(turf.model).materials.map { material in
                try XCTUnwrap(try XCTUnwrap(material as? UnlitMaterial).color.texture?.resource)
            }
            XCTAssertEqual(currentTextures, turfTextures, context)
            // Contrast is allowed to replace only the markings material, never
            // the authored second net slot or the textured unlit turf.
            XCTAssertEqual(markings.model?.materials.count, 2, context)
            XCTAssertTrue(markings.model?.materials.last is PhysicallyBasedMaterial, context)
        }
        XCTAssertEqual(scenario.players, sourcePlayers)
        XCTAssertEqual(scenario.ball, sourceBall)
    }

    private func subtree(_ root: Entity) -> [Entity] {
        [root] + root.children.flatMap { subtree($0) }
    }
}
