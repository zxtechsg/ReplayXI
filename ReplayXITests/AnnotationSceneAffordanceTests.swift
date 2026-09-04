import RealityKit
import XCTest
@testable import ReplayXI

@MainActor
final class AnnotationSceneAffordanceTests: XCTestCase {
    func testPitchWidePinchTargetExistsAndOnlyActivatesWhileDrawing() throws {
        let scenario = try XCTUnwrap(DemoScenarios.scenario(for: .squadReplay))
        let root = PitchSceneFactory.makeMatchRoot(for: scenario)
        let surface = try XCTUnwrap(root.findEntity(named: "annotation-surface"))

        XCTAssertNotNil(surface.components[CollisionComponent.self])
        XCTAssertNotNil(surface.components[InputTargetComponent.self])

        update(
            root,
            scenario: scenario,
            marks: scenario.coachMarks,
            time: 4,
            selected: nil,
            isDrawing: false
        )
        XCTAssertFalse(surface.isEnabled)

        update(
            root,
            scenario: scenario,
            marks: scenario.coachMarks,
            time: 4,
            selected: nil,
            isDrawing: true
        )
        XCTAssertTrue(surface.isEnabled)
    }

    func testSelectedRunExposesBodyAndSemanticEndpointTargets() throws {
        let scenario = try XCTUnwrap(DemoScenarios.scenario(for: .squadReplay))
        let mark = try XCTUnwrap(scenario.coachMarks.first(where: { $0.kind == .run }))
        let root = PitchSceneFactory.makeMatchRoot(for: scenario)

        update(
            root,
            scenario: scenario,
            marks: scenario.coachMarks,
            time: mark.revealTime,
            selected: mark.id,
            isEditable: true
        )

        let selection = try XCTUnwrap(root.findEntity(named: AnnotationSceneAffordance.selectionRootName))
        XCTAssertTrue(selection.isEnabled)
        XCTAssertTrue(try XCTUnwrap(selection.findEntity(named: "annotation-selection-path")).isEnabled)
        XCTAssertFalse(try XCTUnwrap(selection.findEntity(named: "annotation-selection-zone")).isEnabled)

        let start = try targetEntity(in: selection, containing: "annotation-target-start-")
        let end = try targetEntity(in: selection, containing: "annotation-target-end-")
        XCTAssertEqual(
            AnnotationSceneAffordance.targetAncestor(of: start),
            AnnotationSceneTarget(markID: mark.id, role: .start)
        )
        XCTAssertEqual(
            AnnotationSceneAffordance.targetAncestor(of: end),
            AnnotationSceneTarget(markID: mark.id, role: .end)
        )
        XCTAssertEqual(start.position.x, mark.start.x, accuracy: 0.000_1)
        XCTAssertEqual(start.position.z, mark.start.z, accuracy: 0.000_1)
        XCTAssertEqual(end.position.x, mark.end.x, accuracy: 0.000_1)
        XCTAssertEqual(end.position.z, mark.end.z, accuracy: 0.000_1)

        let body = try XCTUnwrap(
            root.findEntity(named: "mark-\(mark.id.uuidString)")?
                .findEntity(named: AnnotationSceneAffordance.bodyTargetName)
        )
        XCTAssertNotNil(body.components[CollisionComponent.self])
        XCTAssertNotNil(body.components[InputTargetComponent.self])
        XCTAssertEqual(
            AnnotationSceneAffordance.targetAncestor(of: body),
            AnnotationSceneTarget(markID: mark.id, role: .body)
        )
        let labelTarget = try XCTUnwrap(
            root.findEntity(named: "mark-\(mark.id.uuidString)")?
                .findEntity(named: AnnotationSceneAffordance.labelTargetName)
        )
        XCTAssertNotNil(labelTarget.components[CollisionComponent.self])
        XCTAssertEqual(
            AnnotationSceneAffordance.targetAncestor(of: labelTarget),
            AnnotationSceneTarget(markID: mark.id, role: .body)
        )
    }

    func testSelectionIsHiddenOutsideTimestampAndWhileCoachDraws() throws {
        let scenario = try XCTUnwrap(DemoScenarios.scenario(for: .squadReplay))
        let mark = try XCTUnwrap(scenario.coachMarks.first)
        let root = PitchSceneFactory.makeMatchRoot(for: scenario)
        let selection = try XCTUnwrap(root.findEntity(named: AnnotationSceneAffordance.selectionRootName))

        update(root, scenario: scenario, marks: scenario.coachMarks, time: mark.revealTime - 0.01, selected: mark.id)
        XCTAssertFalse(selection.isEnabled)

        update(
            root,
            scenario: scenario,
            marks: scenario.coachMarks,
            time: mark.revealTime,
            selected: mark.id,
            isDrawing: true
        )
        XCTAssertFalse(selection.isEnabled)
        let markEntity = try XCTUnwrap(root.findEntity(named: "mark-\(mark.id.uuidString)"))
        XCTAssertFalse(
            try XCTUnwrap(markEntity.findEntity(named: AnnotationSceneAffordance.bodyTargetName))
                .isEnabled
        )
        XCTAssertFalse(
            try XCTUnwrap(markEntity.findEntity(named: AnnotationSceneAffordance.labelTargetName))
                .isEnabled
        )

        update(root, scenario: scenario, marks: scenario.coachMarks, time: mark.revealTime, selected: nil)
        XCTAssertFalse(selection.isEnabled)
        XCTAssertTrue(
            try XCTUnwrap(markEntity.findEntity(named: AnnotationSceneAffordance.bodyTargetName))
                .isEnabled
        )
        XCTAssertTrue(
            try XCTUnwrap(markEntity.findEntity(named: AnnotationSceneAffordance.labelTargetName))
                .isEnabled
        )
    }

    func testLockedAuthoredMarkHighlightsWithoutEditHandles() throws {
        let scenario = try XCTUnwrap(DemoScenarios.scenario(for: .squadReplay))
        let mark = try XCTUnwrap(scenario.coachMarks.first(where: { $0.kind == .pass }))
        let root = PitchSceneFactory.makeMatchRoot(for: scenario)

        update(root, scenario: scenario, marks: scenario.coachMarks, time: mark.revealTime, selected: mark.id)

        let selection = try XCTUnwrap(root.findEntity(named: AnnotationSceneAffordance.selectionRootName))
        XCTAssertTrue(selection.isEnabled)
        XCTAssertTrue(try XCTUnwrap(selection.findEntity(named: "annotation-selection-path")).isEnabled)
        XCTAssertFalse(
            try targetEntity(in: selection, containing: "annotation-target-start-").isEnabled
        )
        XCTAssertFalse(
            try targetEntity(in: selection, containing: "annotation-target-end-").isEnabled
        )
        XCTAssertTrue(
            try XCTUnwrap(selection.findEntity(named: "annotation-selection-label-outline")).isEnabled
        )
    }

    func testSpaceSelectionUsesOneReusableDashedRing() throws {
        let scenario = try XCTUnwrap(DemoScenarios.scenario(for: .squadReplay))
        let mark = try XCTUnwrap(scenario.coachMarks.first(where: { $0.kind == .space }))
        let root = PitchSceneFactory.makeMatchRoot(for: scenario)
        let selection = try XCTUnwrap(root.findEntity(named: AnnotationSceneAffordance.selectionRootName))
        let originalChildren = selection.children.count

        update(root, scenario: scenario, marks: scenario.coachMarks, time: mark.revealTime, selected: mark.id)

        let zone = try XCTUnwrap(
            selection.findEntity(named: "annotation-selection-zone") as? ModelEntity
        )
        XCTAssertTrue(zone.isEnabled)
        XCTAssertNotNil(zone.components[ModelComponent.self])
        XCTAssertTrue(zone.children.isEmpty)

        update(root, scenario: scenario, marks: scenario.coachMarks, time: mark.revealTime + 1, selected: mark.id)
        XCTAssertEqual(selection.children.count, originalChildren)
        XCTAssertTrue(selection === root.findEntity(named: AnnotationSceneAffordance.selectionRootName))
    }

    func testPlayerLabelTetherTracksPlayerAndResolvesAttachedTarget() throws {
        let scenario = try XCTUnwrap(DemoScenarios.scenario(for: .squadReplay))
        let player = try XCTUnwrap(scenario.player(id: "navy-rw"))
        let initialPose = player.presentationPose(at: 8)
        let mark = CoachMark(
            id: UUID(uuidString: "00000000-0000-4000-8000-00000000F001")!,
            kind: .playerLabel,
            start: initialPose.position,
            end: initialPose.position,
            label: "#7 Adebayo · RW",
            revealTime: 8,
            hideTime: 18,
            playerID: player.id
        )
        let marks = scenario.coachMarks + [mark]
        let root = PitchSceneFactory.makeMatchRoot(for: scenario)

        update(root, scenario: scenario, marks: marks, time: 8, selected: mark.id)

        let markEntity = try XCTUnwrap(root.findEntity(named: "mark-\(mark.id.uuidString)"))
        let attachment = try XCTUnwrap(
            markEntity.findEntity(named: AnnotationSceneAffordance.playerAttachmentName)
        )
        XCTAssertEqual(attachment.position.x, initialPose.position.x, accuracy: 0.000_1)
        XCTAssertEqual(attachment.position.z, initialPose.position.z, accuracy: 0.000_1)
        XCTAssertGreaterThan(
            try XCTUnwrap(attachment.findEntity(named: "annotation-attachment-stem")).scale.y,
            1
        )

        let selectedTarget = try targetEntity(
            in: try XCTUnwrap(root.findEntity(named: AnnotationSceneAffordance.selectionRootName)),
            containing: "annotation-target-attached-player-"
        )
        XCTAssertEqual(
            AnnotationSceneAffordance.targetAncestor(of: selectedTarget),
            AnnotationSceneTarget(markID: mark.id, role: .attachedPlayer)
        )

        update(root, scenario: scenario, marks: marks, time: 12, selected: mark.id)
        let laterPose = player.presentationPose(at: 12)
        XCTAssertEqual(attachment.position.x, laterPose.position.x, accuracy: 0.000_1)
        XCTAssertEqual(attachment.position.z, laterPose.position.z, accuracy: 0.000_1)
    }

    func testAffordanceScaleKeepsTabletopTargetsAcquirable() {
        XCTAssertEqual(AnnotationSceneAffordance.visualScale(for: .firstPerson), 1)
        XCTAssertGreaterThan(AnnotationSceneAffordance.visualScale(for: .tacticalTable), 3)
        XCTAssertGreaterThan(AnnotationSceneAffordance.visualScale(for: .touchline), 1)
        XCTAssertGreaterThan(AnnotationSceneAffordance.visualScale(for: .positional), 2)
    }

    private func update(
        _ root: Entity,
        scenario: ReplayScenario,
        marks: [CoachMark],
        time: TimeInterval,
        selected: UUID?,
        isDrawing: Bool = false,
        isEditable: Bool = false
    ) {
        PitchSceneFactory.update(
            root: root,
            scenario: scenario,
            time: time,
            viewMode: .tacticalTable,
            perspectiveID: scenario.defaultPerspectiveID,
            marks: marks,
            selectedAnnotationID: selected,
            selectedAnnotationIsEditable: isEditable,
            showsLaneLens: false,
            isDrawing: isDrawing,
            positionalOriginTransform: nil
        )
    }

    private func targetEntity(in root: Entity, containing prefix: String) throws -> Entity {
        if root.name.hasPrefix(prefix) {
            return root
        }
        for child in root.children {
            if let target = try? targetEntity(in: child, containing: prefix) {
                return target
            }
        }
        throw TargetLookupError.missing(prefix)
    }

    private enum TargetLookupError: Error {
        case missing(String)
    }
}
