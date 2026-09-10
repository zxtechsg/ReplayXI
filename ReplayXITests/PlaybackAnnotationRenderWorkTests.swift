import RealityKit
import XCTest
@testable import ReplayXI

@MainActor
final class PlaybackAnnotationRenderWorkTests: XCTestCase {
    func testHiddenTrackedGeometryWaitsUntilRevealAndCatchesUpOnReverseSeek() throws {
        let scenario = try XCTUnwrap(DemoScenarios.scenario(for: .squadReplay))
        let player = try XCTUnwrap(scenario.player(id: "navy-rb"))
        let mark = CoachMark(
            kind: .run,
            start: PitchPoint(x: 0, z: 0),
            end: PitchPoint(x: 2, z: 4),
            label: "Tracked run",
            revealTime: 10,
            hideTime: 15,
            startTrackAnchor: CoachMarkTrackAnchor(playerID: player.id),
            endTrackAnchor: CoachMarkTrackAnchor(
                playerID: player.id,
                offset: PitchPoint(x: 2, z: 4)
            )
        )
        let root = PitchSceneFactory.makeMatchRoot(for: scenario)
        update(root: root, scenario: scenario, marks: [mark], time: 1)
        let markRoot = try XCTUnwrap(root.findEntity(named: "mark-\(mark.id.uuidString)"))
        let rail = try XCTUnwrap(markRoot.findEntity(named: "annotation-mark-segment-0"))
        let authoredTransform = rail.transform

        update(root: root, scenario: scenario, marks: [mark], time: 8)
        XCTAssertFalse(markRoot.isEnabled)
        XCTAssertEqual(rail.transform, authoredTransform)

        update(root: root, scenario: scenario, marks: [mark], time: 12)
        XCTAssertTrue(markRoot.isEnabled)
        let positionAtTwelve = player.presentationPose(at: 12).position
        XCTAssertEqual(rail.position.x, positionAtTwelve.x + 1, accuracy: 0.000_1)
        XCTAssertEqual(rail.position.z, positionAtTwelve.z + 2, accuracy: 0.000_1)
        let visibleTransform = rail.transform

        update(root: root, scenario: scenario, marks: [mark], time: 18)
        XCTAssertFalse(markRoot.isEnabled)
        XCTAssertEqual(rail.transform, visibleTransform)

        update(root: root, scenario: scenario, marks: [mark], time: 10)
        XCTAssertTrue(markRoot.isEnabled)
        let positionAtTen = player.presentationPose(at: 10).position
        XCTAssertEqual(rail.position.x, positionAtTen.x + 1, accuracy: 0.000_1)
        XCTAssertEqual(rail.position.z, positionAtTen.z + 2, accuracy: 0.000_1)
        XCTAssertTrue(rail === markRoot.findEntity(named: "annotation-mark-segment-0"))
    }

    func testCulledMarkDoesNotConsumeFirstPersonCaptionSlot() throws {
        let scenario = try XCTUnwrap(DemoScenarios.scenario(for: .squadReplay))
        let root = PitchSceneFactory.makeMatchRoot(for: scenario)
        let newestPress = mark(kind: .danger, revealTime: 3)
        let culledPress = mark(kind: .danger, revealTime: 2)
        let visibleRun = mark(kind: .run, revealTime: 1)

        update(
            root: root,
            scenario: scenario,
            marks: [newestPress, culledPress, visibleRun],
            time: 4,
            viewMode: .firstPerson
        )

        let pressRoot = try XCTUnwrap(
            root.findEntity(named: "mark-\(newestPress.id.uuidString)")
        )
        let culledRoot = try XCTUnwrap(
            root.findEntity(named: "mark-\(culledPress.id.uuidString)")
        )
        let runRoot = try XCTUnwrap(
            root.findEntity(named: "mark-\(visibleRun.id.uuidString)")
        )
        XCTAssertTrue(pressRoot.isEnabled)
        XCTAssertFalse(culledRoot.isEnabled)
        XCTAssertTrue(runRoot.isEnabled)
        XCTAssertTrue(try XCTUnwrap(pressRoot.findEntity(named: "annotation-label")).isEnabled)
        XCTAssertTrue(try XCTUnwrap(runRoot.findEntity(named: "annotation-label")).isEnabled)
        XCTAssertFalse(try XCTUnwrap(culledRoot.findEntity(named: "annotation-label")).isEnabled)
    }

    private func mark(kind: CoachMarkKind, revealTime: TimeInterval) -> CoachMark {
        CoachMark(
            kind: kind,
            start: PitchPoint(x: 0, z: 0),
            end: PitchPoint(x: 4, z: 6),
            label: kind.title,
            revealTime: revealTime
        )
    }

    private func update(
        root: Entity,
        scenario: ReplayScenario,
        marks: [CoachMark],
        time: TimeInterval,
        viewMode: ReplayViewMode = .tacticalTable
    ) {
        PitchSceneFactory.update(
            root: root,
            scenario: scenario,
            time: time,
            viewMode: viewMode,
            perspectiveID: scenario.defaultPerspectiveID,
            marks: marks,
            showsLaneLens: false,
            isDrawing: false,
            positionalOriginTransform: nil
        )
    }
}
