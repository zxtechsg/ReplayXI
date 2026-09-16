import RealityKit
import XCTest
@testable import ReplayXI

@MainActor
final class ReplayAnnotationBindingReuseTests: XCTestCase {
    func testUnrelatedRevisionStillRepairsMissingGeometryForEveryMarkKind() throws {
        let scenario = try XCTUnwrap(DemoScenarios.scenario(for: .squadReplay))
        let missingParts: [(CoachMarkKind, String)] = [
            (.run, "annotation-mark-arrow"),
            (.pass, "annotation-mark-segment-0"),
            (.danger, "annotation-mark-segment-6"),
            (.space, "annotation-mark-space"),
            (.playerLabel, AnnotationSceneAffordance.playerAttachmentName),
            (.run, "annotation-mark-start-elevation-guide"),
            (.space, "annotation-mark-end-elevation-guide"),
        ]
        for (kind, part) in missingParts {
            let damaged = mark(kind: kind, label: "Repair \(kind.title)")
            let edited = mark(label: "Edited run")
            let untouched = mark(label: "Untouched run")
            let root = PitchSceneFactory.makeMatchRoot(for: scenario)
            update(root, scenario: scenario, marks: [damaged, edited, untouched])
            let oldDamaged = try markRoot(damaged, in: root)
            let oldEdited = try markRoot(edited, in: root)
            let oldUntouched = try markRoot(untouched, in: root)
            try remove(part: part, from: oldDamaged)
            XCTAssertNil(oldDamaged.findEntity(named: part))

            PitchSceneFactory.resetAnnotationSceneWorkForTesting()
            let moved = replacement(of: edited, end: PitchPoint(x: 5, z: 8))
            update(root, scenario: scenario, marks: [damaged, moved, untouched])
            let repaired = try markRoot(damaged, in: root)
            XCTAssertFalse(repaired === oldDamaged, "Repair \(kind.title): \(part)")
            XCTAssertNotNil(repaired.findEntity(named: part))
            XCTAssertTrue(try markRoot(moved, in: root) === oldEdited)
            XCTAssertTrue(try markRoot(untouched, in: root) === oldUntouched)
            XCTAssertEqual(PitchSceneFactory.annotationSceneWork.markTreeBuilds, 1)
        }
    }

    func testUnrelatedRevisionStillRepairsReleasedBodyTargetOnly() throws {
        let scenario = try XCTUnwrap(DemoScenarios.scenario(for: .squadReplay))
        let damaged = mark(label: "Lost body target")
        let edited = mark(label: "Edited run")
        let untouched = mark(label: "Untouched run")
        let root = PitchSceneFactory.makeMatchRoot(for: scenario)
        update(root, scenario: scenario, marks: [damaged, edited, untouched])
        let oldDamaged = try markRoot(damaged, in: root)
        let oldEdited = try markRoot(edited, in: root)
        let oldUntouched = try markRoot(untouched, in: root)
        // Drop the removed target instead of retaining an external strong
        // reference. This exercises the existing weak-binding repair contract.
        try remove(part: AnnotationSceneAffordance.bodyTargetName, from: oldDamaged)

        PitchSceneFactory.resetAnnotationSceneWorkForTesting()
        let moved = replacement(of: edited, end: PitchPoint(x: 5, z: 8))
        update(root, scenario: scenario, marks: [damaged, moved, untouched])
        let repaired = try markRoot(damaged, in: root)
        XCTAssertFalse(repaired === oldDamaged)
        XCTAssertNotNil(repaired.findEntity(named: AnnotationSceneAffordance.bodyTargetName))
        XCTAssertTrue(try markRoot(moved, in: root) === oldEdited)
        XCTAssertTrue(try markRoot(untouched, in: root) === oldUntouched)
        XCTAssertEqual(PitchSceneFactory.annotationSceneWork.markTreeBuilds, 1)
    }

    func testRelabelAndKindChangesRebuildOnlyTheChangedBinding() throws {
        let scenario = try XCTUnwrap(DemoScenarios.scenario(for: .squadReplay))
        let original = mark(label: "Original run")
        let untouched = mark(label: "Retained run")
        let root = PitchSceneFactory.makeMatchRoot(for: scenario)
        update(root, scenario: scenario, marks: [original, untouched])
        let originalRoot = try markRoot(original, in: root)
        let untouchedRoot = try markRoot(untouched, in: root)

        PitchSceneFactory.resetAnnotationSceneWorkForTesting()
        let relabelled = replacement(of: original, label: "Different instruction")
        update(root, scenario: scenario, marks: [relabelled, untouched])
        let relabelledRoot = try markRoot(relabelled, in: root)
        XCTAssertFalse(relabelledRoot === originalRoot)
        XCTAssertTrue(try markRoot(untouched, in: root) === untouchedRoot)
        XCTAssertEqual(PitchSceneFactory.annotationSceneWork.markTreeBuilds, 1)

        PitchSceneFactory.resetAnnotationSceneWorkForTesting()
        let space = replacement(of: relabelled, kind: .space)
        update(root, scenario: scenario, marks: [space, untouched])
        let spaceRoot = try markRoot(space, in: root)
        XCTAssertFalse(spaceRoot === relabelledRoot)
        XCTAssertNotNil(spaceRoot.findEntity(named: "annotation-mark-space"))
        XCTAssertNil(spaceRoot.findEntity(named: "annotation-mark-arrow"))
        XCTAssertTrue(try markRoot(untouched, in: root) === untouchedRoot)
        XCTAssertEqual(PitchSceneFactory.annotationSceneWork.markTreeBuilds, 1)
    }

    func testTrackBoundGeometryStillCatchesUpAfterUnrelatedEditsAndReverseSeek() throws {
        let scenario = try XCTUnwrap(DemoScenarios.scenario(for: .squadReplay))
        let player = try XCTUnwrap(scenario.player(id: "navy-rb"))
        let tracked = CoachMark(
            kind: .run,
            start: PitchPoint(x: 0, z: 0),
            end: PitchPoint(x: 2, z: 4),
            label: "Tracked run",
            revealTime: 5,
            hideTime: 15,
            startTrackAnchor: CoachMarkTrackAnchor(playerID: player.id),
            endTrackAnchor: CoachMarkTrackAnchor(
                playerID: player.id, offset: PitchPoint(x: 2, z: 4)
            )
        )
        let edited = mark(label: "Unrelated run")
        let root = PitchSceneFactory.makeMatchRoot(for: scenario)
        update(root, scenario: scenario, marks: [tracked, edited], time: 10)
        let retained = try markRoot(tracked, in: root)
        let rail = try XCTUnwrap(retained.findEntity(named: "annotation-mark-segment-0"))
        let atTen = rail.transform
        try assertTrackedPosition(tracked, in: root, player: player, at: 10)

        let moved = replacement(of: edited, end: PitchPoint(x: 5, z: 8))
        update(root, scenario: scenario, marks: [tracked, moved], time: 10)
        XCTAssertEqual(rail.transform, atTen)
        update(root, scenario: scenario, marks: [tracked, moved], time: 20)
        XCTAssertFalse(retained.isEnabled)
        let movedAgain = replacement(of: moved, end: PitchPoint(x: 6, z: 8))
        update(root, scenario: scenario, marks: [tracked, movedAgain], time: 20)
        XCTAssertFalse(retained.isEnabled)

        update(root, scenario: scenario, marks: [tracked, movedAgain], time: 8)
        try assertTrackedPosition(tracked, in: root, player: player, at: 8)
        update(root, scenario: scenario, marks: [tracked, movedAgain], time: 10)
        try assertTrackedPosition(tracked, in: root, player: player, at: 10)
        XCTAssertEqual(rail.transform, atTen)
        XCTAssertTrue(try markRoot(tracked, in: root) === retained)
    }

    private func mark(kind: CoachMarkKind = .run, label: String) -> CoachMark {
        CoachMark(
            kind: kind,
            start: PitchPoint(x: 0, z: 0),
            end: PitchPoint(x: 4, z: 8),
            label: label,
            revealTime: 0,
            playerID: kind == .playerLabel ? "navy-rw" : nil
        )
    }

    private func replacement(
        of mark: CoachMark,
        end: PitchPoint? = nil,
        label: String? = nil,
        kind: CoachMarkKind? = nil
    ) -> CoachMark {
        CoachMark(
            id: mark.id, kind: kind ?? mark.kind,
            start: mark.start, end: end ?? mark.end,
            startElevation: mark.startElevation, endElevation: mark.endElevation,
            label: label ?? mark.label,
            revealTime: mark.revealTime, hideTime: mark.hideTime,
            author: mark.author, playerID: mark.playerID,
            startTrackAnchor: mark.startTrackAnchor, endTrackAnchor: mark.endTrackAnchor
        )
    }

    private func remove(part: String, from root: Entity) throws {
        let entity = try XCTUnwrap(root.findEntity(named: part))
        entity.removeFromParent()
    }

    private func markRoot(_ mark: CoachMark, in root: Entity) throws -> Entity {
        try XCTUnwrap(root.findEntity(named: "mark-\(mark.id.uuidString)"))
    }

    private func assertTrackedPosition(
        _ mark: CoachMark,
        in root: Entity,
        player: PlayerTrack,
        at time: TimeInterval
    ) throws {
        let markRoot = try markRoot(mark, in: root)
        let rail = try XCTUnwrap(markRoot.findEntity(named: "annotation-mark-segment-0"))
        XCTAssertTrue(markRoot.isEnabled)
        let pose = player.presentationPose(at: time)
        XCTAssertEqual(rail.position.x, pose.position.x + 1, accuracy: 0.000_1)
        XCTAssertEqual(rail.position.z, pose.position.z + 2, accuracy: 0.000_1)
    }

    private func update(
        _ root: Entity,
        scenario: ReplayScenario,
        marks: [CoachMark],
        time: TimeInterval = 0
    ) {
        PitchSceneFactory.update(
            root: root, scenario: scenario, time: time,
            viewMode: .tacticalTable, perspectiveID: scenario.defaultPerspectiveID,
            marks: marks, showsLaneLens: false, isDrawing: false,
            positionalOriginTransform: nil
        )
    }
}
