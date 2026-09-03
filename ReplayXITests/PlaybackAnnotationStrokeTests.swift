import RealityKit
import XCTest
@testable import ReplayXI

@MainActor
final class PlaybackAnnotationStrokeTests: XCTestCase {
    func testEntityGestureUsesVisionOSSpatialDistanceWorkaround() {
        XCTAssertEqual(
            PlaybackAnnotationStroke.entityGestureMinimumDistance,
            0.001,
            accuracy: 0.000_001
        )
    }

    func testSpatialGestureSampleProjectsAndClampsToPitch() {
        XCTAssertEqual(
            PlaybackAnnotationStroke.projectedPitchPoint(
                SIMD3<Float>(99, 14, -99)
            ),
            PitchPoint(x: 34, z: -52.5)
        )
    }

    func testSpatialGestureProjectionRejectsNonFiniteGroundCoordinates() {
        XCTAssertNil(
            PlaybackAnnotationStroke.projectedPitchPoint(
                SIMD3<Float>(.nan, 0, 4)
            )
        )
        XCTAssertNil(
            PlaybackAnnotationStroke.projectedPitchPoint(
                SIMD3<Float>(4, 0, .infinity)
            )
        )
    }

    func testPathStrokeClampsToPitchAndCommitsExactlyOnce() throws {
        var stroke = try XCTUnwrap(
            PlaybackAnnotationStroke(
                kind: .run,
                start: PitchPoint(x: 32, z: 50)
            )
        )

        XCTAssertTrue(stroke.update(to: PitchPoint(x: 99, z: 99)))
        XCTAssertEqual(stroke.previewEnd, PitchPoint(x: 34, z: 52.5))
        XCTAssertTrue(stroke.isReadyToCommit)
        XCTAssertEqual(
            stroke.finish(at: PitchPoint(x: 99, z: 99)),
            PitchPoint(x: 34, z: 52.5)
        )
        XCTAssertNil(stroke.finish(at: PitchPoint(x: 0, z: 0)))
        XCTAssertFalse(stroke.update(to: PitchPoint(x: 0, z: 0)))
    }

    func testShortStrokeLeavesTwoTapFallbackUncommitted() throws {
        var stroke = try XCTUnwrap(
            PlaybackAnnotationStroke(kind: .pass, start: .zero)
        )

        XCTAssertNil(stroke.finish(at: PitchPoint(x: 0.2, z: 0.2)))
        XCTAssertEqual(stroke.phase, .finished)
    }

    func testZoneUsesReadableRadiusGate() throws {
        var tooShort = try XCTUnwrap(
            PlaybackAnnotationStroke(kind: .space, start: .zero)
        )
        XCTAssertNil(tooShort.finish(at: PitchPoint(x: 1.09, z: 0)))

        var ready = try XCTUnwrap(
            PlaybackAnnotationStroke(kind: .space, start: .zero)
        )
        XCTAssertEqual(
            ready.finish(at: PitchPoint(x: 1.10, z: 0)),
            PitchPoint(x: 1.10, z: 0)
        )
    }

    func testPlayerLabelAndNonFiniteStartsAreRejected() {
        XCTAssertNil(
            PlaybackAnnotationStroke(kind: .playerLabel, start: .zero)
        )
        XCTAssertNil(
            PlaybackAnnotationStroke(
                kind: .run,
                start: PitchPoint(x: .nan, z: 0)
            )
        )
    }

    func testNonFiniteUpdateDoesNotCorruptActiveStroke() throws {
        var stroke = try XCTUnwrap(
            PlaybackAnnotationStroke(kind: .danger, start: PitchPoint(x: 2, z: 3))
        )

        XCTAssertFalse(stroke.update(to: PitchPoint(x: .infinity, z: 8)))
        XCTAssertEqual(stroke.end, PitchPoint(x: 2, z: 3))
        XCTAssertEqual(stroke.phase, .active)
    }

    func testInvalidFinalSampleNeverCommitsLastValidEndpoint() throws {
        var stroke = try XCTUnwrap(
            PlaybackAnnotationStroke(kind: .run, start: .zero)
        )
        XCTAssertTrue(stroke.update(to: PitchPoint(x: 8, z: 4)))

        XCTAssertNil(stroke.finish(at: PitchPoint(x: .nan, z: 7)))
        XCTAssertEqual(stroke.phase, .finished)
        XCTAssertNil(stroke.finish(at: PitchPoint(x: 9, z: 5)))
    }

    func testContinuousAndTwoTapGeometryUseTheSameMinimums() {
        XCTAssertEqual(
            PlaybackAnnotationStroke.minimumPathLength,
            CoachMarkGeometryPolicy.minimumDirectionalLength
        )
        XCTAssertEqual(
            PlaybackAnnotationStroke.minimumZoneRadius,
            CoachMarkGeometryPolicy.minimumZoneRadius
        )
    }

    func testDraftScenePreviewsDirectionalAndZoneStrokesWithoutRebuilding() throws {
        let scenario = try XCTUnwrap(DemoScenarios.scenario(for: .squadReplay))
        let root = PitchSceneFactory.makeMatchRoot(for: scenario)
        let start = PitchPoint(x: 2, z: 3)
        let end = PitchPoint(x: 7, z: 3)

        func render(kind: CoachMarkKind, end: PitchPoint?) {
            PitchSceneFactory.update(
                root: root,
                scenario: scenario,
                time: 8,
                viewMode: .tacticalTable,
                perspectiveID: scenario.defaultPerspectiveID,
                marks: scenario.coachMarks,
                showsLaneLens: false,
                isDrawing: true,
                draftStart: start,
                draftEnd: end,
                draftKind: kind,
                positionalOriginTransform: nil
            )
        }

        render(kind: .run, end: end)
        let stroke = try XCTUnwrap(root.findEntity(named: "annotation-draft-stroke"))
        let path = try XCTUnwrap(
            stroke.findEntity(named: "annotation-draft-stroke-path") as? ModelEntity
        )
        let arrow = try XCTUnwrap(
            stroke.findEntity(named: "annotation-draft-stroke-arrow") as? ModelEntity
        )
        let zone = try XCTUnwrap(
            stroke.findEntity(named: "annotation-draft-stroke-zone") as? ModelEntity
        )
        XCTAssertTrue(stroke.isEnabled)
        XCTAssertTrue(path.isEnabled)
        XCTAssertTrue(arrow.isEnabled)
        XCTAssertFalse(zone.isEnabled)
        XCTAssertEqual(path.scale.z, 5, accuracy: 0.000_1)

        render(kind: .space, end: end)
        XCTAssertTrue(stroke.isEnabled)
        XCTAssertFalse(path.isEnabled)
        XCTAssertFalse(arrow.isEnabled)
        XCTAssertTrue(zone.isEnabled)
        XCTAssertEqual(zone.scale.x, 5, accuracy: 0.000_1)

        render(kind: .space, end: nil)
        XCTAssertFalse(stroke.isEnabled)
    }
}
