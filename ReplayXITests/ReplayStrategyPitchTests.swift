import RealityKit
import XCTest
@testable import ReplayXI

@MainActor
final class ReplayStrategyPitchTests: XCTestCase {
    func testBlenderPitchLoadsUprightWithBoundedMeshesAndTextures() throws {
        try ReplayStrategyPitchProvider.prewarm()
        let pitch = try XCTUnwrap(ReplayStrategyPitchProvider.makeInstance())
        XCTAssertTrue(pitch.components.has(ReplayStrategyPitchProvider.Admission.self))
        let models = ReplayStrategyPitchProvider.models(in: pitch)
        XCTAssertEqual(models.count, 2)
        XCTAssertEqual(models.compactMap { $0.model?.materials.count }.reduce(0, +), 4)
        XCTAssertEqual(ReplayStrategyPitchProvider.triangleCount(in: pitch), 7_926)
        let bounds = pitch.visualBounds(relativeTo: pitch)
        XCTAssertEqual(bounds.extents.x, 72, accuracy: 0.02)
        XCTAssertEqual(bounds.extents.z, 111, accuracy: 0.02)
        XCTAssertEqual(bounds.extents.y, 2.56, accuracy: 0.02)
        XCTAssertEqual(bounds.min.y, 0, accuracy: 0.01)
        let turf = try XCTUnwrap(pitch.findEntity(named: "field-surface"))
        XCTAssertEqual(turf.visualBounds(relativeTo: pitch).extents.y, 0, accuracy: 0.01)
        let turfModel = try XCTUnwrap((turf as? ModelEntity)?.model)
        for material in turfModel.materials {
            let stable = try XCTUnwrap(material as? UnlitMaterial)
            XCTAssertNotNil(stable.color.texture, "Both original turf tiles must survive USDZ packaging")
        }
        let markings = try XCTUnwrap(pitch.findEntity(named: "pitch-markings-and-goals") as? ModelEntity)
        XCTAssertTrue(markings.model?.materials.first is UnlitMaterial,
            "Cold tactical entry must not depend on an environment light to show white lines")
        XCTAssertTrue(markings.model?.materials.last is PhysicallyBasedMaterial)
    }

    func testClonesKeepIndependentVisibilityAndFactoryUsesPreparedAsset() throws {
        try ReplayStrategyPitchProvider.prewarm()
        let first = try XCTUnwrap(ReplayStrategyPitchProvider.makeInstance())
        let second = try XCTUnwrap(ReplayStrategyPitchProvider.makeInstance())
        first.findEntity(named: "field-surface")?.isEnabled = false
        XCTAssertTrue(try XCTUnwrap(second.findEntity(named: "field-surface")).isEnabled)
        let scene = PitchSceneFactory.makeMatchRoot(for: DemoScenarios.all[0])
        let pitch = try XCTUnwrap(scene.findEntity(named: "pitch"))
        XCTAssertTrue(pitch.components.has(ReplayStrategyPitchProvider.Admission.self))
    }

    func testViewChangesPreserveNetMaterialAndHideFieldForLocalDrill() throws {
        try ReplayStrategyPitchProvider.prewarm()
        let scenario = try XCTUnwrap(DemoScenarios.scenario(for: .shapeLab))
        let root = PitchSceneFactory.makeMatchRoot(for: scenario)
        let pitch = try XCTUnwrap(root.findEntity(named: "pitch"))
        let markings = try XCTUnwrap(pitch.findEntity(named: "pitch-markings-and-goals") as? ModelEntity)
        for mode: ReplayViewMode in [.firstPerson, .tacticalTable, .positional] {
            PitchSceneFactory.update(
                root: root, scenario: scenario, time: 0, viewMode: mode,
                perspectiveID: scenario.defaultPerspectiveID, marks: scenario.coachMarks,
                showsLaneLens: false, isDrawing: false, positionalOriginTransform: nil
            )
            XCTAssertEqual(markings.model?.materials.count, 2)
            XCTAssertTrue(markings.model?.materials.last is PhysicallyBasedMaterial)
            XCTAssertEqual(pitch.isEnabled, mode != .positional)
        }
    }
}
