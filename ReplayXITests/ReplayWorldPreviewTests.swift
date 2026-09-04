import RealityKit
import XCTest
@testable import ReplayXI

@MainActor
final class ReplayWorldPreviewTests: XCTestCase {
    func testSyntheticWorldPreviewUsesFourBatchedMeshesWithinBudget() {
        let root = ReplayWorldPreviewFactory.make()

        XCTAssertEqual(root.name, ReplayWorldPreviewFactory.rootName)
        XCTAssertEqual(root.children.count, ReplayWorldPreviewFactory.materialGroupCount)
        XCTAssertEqual(ReplayWorldPreviewFactory.splatCount, 640)
        XCTAssertEqual(ReplayWorldPreviewFactory.estimatedTriangleCount, 2_560)
        XCTAssertEqual(ReplayWorldPreviewFactory.estimatedVertexCount, 7_680)
        XCTAssertTrue(root.children.allSatisfy { $0 is ModelEntity })
        XCTAssertEqual(
            Set(root.children.map(\.name)),
            Set((0..<4).map { "world-preview-surfels-\($0)" })
        )
    }

    func testWorldScenarioIsExplicitlySyntheticAndUsesTrackBoundTeachingMarks() throws {
        let scenario = try XCTUnwrap(DemoScenarios.scenario(for: .realWorldReplay))

        XCTAssertEqual(scenario.id, "real-world-match-replay")
        XCTAssertTrue(scenario.matchContext.contains("ORIGINAL SYNTHETIC"))
        XCTAssertEqual(scenario.players.count, 22)
        XCTAssertEqual(scenario.duration, 32)
        XCTAssertEqual(scenario.coachMarks.filter(\.followsPlayerTracks).count, 3)
        XCTAssertTrue(scenario.coachMarks.contains { $0.kind == .space && !$0.followsPlayerTracks })
    }

    func testWorldPreviewIsScopedOnlyToRealWorldScenario() throws {
        let world = try XCTUnwrap(DemoScenarios.scenario(for: .realWorldReplay))
        let playback = try XCTUnwrap(DemoScenarios.scenario(for: .squadReplay))

        XCTAssertNotNil(
            PitchSceneFactory.makeMatchRoot(for: world).findEntity(
                named: ReplayWorldPreviewFactory.rootName
            )
        )
        XCTAssertNil(
            PitchSceneFactory.makeMatchRoot(for: playback).findEntity(
                named: ReplayWorldPreviewFactory.rootName
            )
        )
    }
}
