import RealityKit
import XCTest
@testable import ReplayXI

@MainActor
final class SpatialReviewFocusTests: XCTestCase {
    func testSelectedAnnotationOwnsFocusAndLiftsEditableHandles() throws {
        let scenario = try XCTUnwrap(DemoScenarios.scenario(for: .squadReplay))
        let selected = mark(
            id: "00000000-0000-4000-8000-00000000A141",
            kind: .run,
            start: PitchPoint(x: 18, z: 8),
            end: PitchPoint(x: 25, z: 21),
            label: "Overlap"
        )
        let context = mark(
            id: "00000000-0000-4000-8000-00000000A142",
            kind: .pass,
            start: PitchPoint(x: 14, z: 7),
            end: PitchPoint(x: 25, z: 21),
            label: "Release"
        )
        let root = PitchSceneFactory.makeMatchRoot(for: scenario)

        update(
            root,
            scenario: scenario,
            marks: [selected, context],
            selectedID: selected.id,
            isEditable: true
        )

        let selectedRoot = try markRoot(selected, in: root)
        let contextRoot = try markRoot(context, in: root)
        XCTAssertEqual(
            try XCTUnwrap(selectedRoot.components[OpacityComponent.self]).opacity,
            1,
            accuracy: 0.000_1
        )
        XCTAssertEqual(
            try XCTUnwrap(contextRoot.components[OpacityComponent.self]).opacity,
            PitchSceneFactory.selectedAnnotationContextOpacity,
            accuracy: 0.000_1
        )
        XCTAssertTrue(try annotationLabel(in: selectedRoot).isEnabled)
        XCTAssertFalse(try annotationLabel(in: contextRoot).isEnabled)
        // Editable endpoint handles own input while selected. Keeping the
        // mark's broad body hit volume off prevents it stealing pinch-drags.
        XCTAssertFalse(try bodyTarget(in: selectedRoot).isEnabled)
        XCTAssertFalse(try bodyTarget(in: contextRoot).isEnabled)

        let selection = try XCTUnwrap(
            root.findEntity(named: AnnotationSceneAffordance.selectionRootName)
        )
        let path = try XCTUnwrap(selection.findEntity(named: "annotation-selection-path"))
        XCTAssertEqual(
            path.position.y,
            AnnotationSceneAffordance.selectionLift(for: .tacticalTable),
            accuracy: 0.000_1
        )
        for prefix in ["annotation-target-start-", "annotation-target-end-"] {
            let handle = try descendant(in: selection, withPrefix: prefix)
            XCTAssertEqual(
                handle.position.y,
                AnnotationSceneAffordance.selectionLift(for: .tacticalTable),
                accuracy: 0.000_1
            )
            XCTAssertGreaterThan(handle.scale.x, 3.9)
            XCTAssertNotNil(handle.findEntity(named: "annotation-handle-stem"))
            XCTAssertTrue(
                try XCTUnwrap(handle.findEntity(named: "annotation-handle-label")).isEnabled
            )
        }

        let visiblePlayerLabels = try playerLabels(in: root).filter(\.isEnabled)
        XCTAssertLessThanOrEqual(
            visiblePlayerLabels.count,
            PlaybackSpatialLabels.tacticalFocusedPlayerLabelLimit
        )
        XCTAssertTrue(
            visiblePlayerLabels.contains {
                $0.name == "player-label-\(scenario.defaultPerspectiveID)"
            }
        )
    }

    func testDecisionOptionsSuppressAnnotationClutterAndLimitIdentityTags() throws {
        let scenario = try XCTUnwrap(DemoScenarios.scenario(for: .squadReplay))
        let snapshot = try XCTUnwrap(
            scenario.decisionReview(at: 14.1, playerID: "navy-rw")
        )
        XCTAssertFalse(snapshot.passingOptions.isEmpty)
        let marks = [
            mark(
                id: "00000000-0000-4000-8000-00000000A143",
                kind: .run,
                start: PitchPoint(x: 16, z: 7),
                end: PitchPoint(x: 27, z: 21),
                label: "Overlap"
            ),
            mark(
                id: "00000000-0000-4000-8000-00000000A144",
                kind: .space,
                start: PitchPoint(x: 24, z: 20),
                end: PitchPoint(x: 29, z: 20),
                label: "Attack space"
            ),
        ]
        let root = PitchSceneFactory.makeMatchRoot(for: scenario)

        update(
            root,
            scenario: scenario,
            marks: marks,
            decisionSnapshot: snapshot
        )

        XCTAssertTrue(
            try XCTUnwrap(root.findEntity(named: DecisionOptionSceneOverlay.rootName)).isEnabled
        )
        for mark in marks {
            let entity = try markRoot(mark, in: root)
            XCTAssertEqual(
                try XCTUnwrap(entity.components[OpacityComponent.self]).opacity,
                PitchSceneFactory.decisionAnnotationContextOpacity,
                accuracy: 0.000_1
            )
            XCTAssertFalse(try annotationLabel(in: entity).isEnabled)
            XCTAssertFalse(try bodyTarget(in: entity).isEnabled)
        }

        let visiblePlayerLabels = try playerLabels(in: root).filter(\.isEnabled)
        XCTAssertLessThanOrEqual(
            visiblePlayerLabels.count,
            PlaybackSpatialLabels.tacticalFocusedPlayerLabelLimit
        )
        XCTAssertTrue(
            visiblePlayerLabels.contains { $0.name == "player-label-\(snapshot.playerID)" }
        )
        for option in snapshot.passingOptions.prefix(
            DecisionOptionSceneOverlay.maximumVisibleOptions
        ) {
            XCTAssertTrue(
                visiblePlayerLabels.contains {
                    $0.name == "player-label-\(option.receiverID)"
                },
                option.receiverID
            )
        }
    }

    func testEditablePlayerOriginMarkGivesHandlesExclusiveInput() throws {
        let scenario = try XCTUnwrap(DemoScenarios.scenario(for: .squadReplay))
        let player = try XCTUnwrap(scenario.player(id: "navy-rw"))
        let time: TimeInterval = 14.1
        let playerPoint = player.presentationPose(at: time).position
        let selected = mark(
            id: "00000000-0000-4000-8000-00000000A149",
            kind: .run,
            start: playerPoint,
            end: PitchPoint(x: playerPoint.x + 4, z: playerPoint.z + 6),
            label: "Player-origin run"
        )
        let root = PitchSceneFactory.makeMatchRoot(for: scenario)

        update(
            root,
            scenario: scenario,
            marks: [selected],
            selectedID: selected.id,
            isEditable: true,
            time: time
        )

        let playerRoot = try XCTUnwrap(root.findEntity(named: "player-\(player.id)"))
        let playerTarget = try XCTUnwrap(playerRoot.findEntity(named: "interaction-target"))
        let playerLabel = try XCTUnwrap(
            root.findEntity(named: "player-label-\(player.id)")
        )
        XCTAssertFalse(playerTarget.isEnabled)
        XCTAssertTrue(playerLabel.isEnabled)
        XCTAssertNil(playerLabel.components[InputTargetComponent.self])

        let selection = try XCTUnwrap(
            root.findEntity(named: AnnotationSceneAffordance.selectionRootName)
        )
        XCTAssertTrue(try descendant(in: selection, withPrefix: "annotation-target-start-").isEnabled)
        XCTAssertTrue(try descendant(in: selection, withPrefix: "annotation-target-end-").isEnabled)

        update(root, scenario: scenario, marks: [selected], time: time)
        XCTAssertTrue(playerTarget.isEnabled)
        XCTAssertNotNil(playerLabel.components[InputTargetComponent.self])
    }

    func testSelectedAnnotationWinsOverOptionsAndNormalModeRestoresContext() throws {
        let scenario = try XCTUnwrap(DemoScenarios.scenario(for: .squadReplay))
        let snapshot = try XCTUnwrap(
            scenario.decisionReview(at: 14.1, playerID: "navy-rw")
        )
        let selected = mark(
            id: "00000000-0000-4000-8000-00000000A145",
            kind: .danger,
            start: PitchPoint(x: 15, z: 9),
            end: PitchPoint(x: 22, z: 18),
            label: "Press trigger"
        )
        let context = mark(
            id: "00000000-0000-4000-8000-00000000A146",
            kind: .pass,
            start: PitchPoint(x: 11, z: 6),
            end: PitchPoint(x: 23, z: 19),
            label: "Bounce pass"
        )
        let marks = [selected, context]
        let root = PitchSceneFactory.makeMatchRoot(for: scenario)

        update(
            root,
            scenario: scenario,
            marks: marks,
            selectedID: selected.id,
            decisionSnapshot: snapshot
        )
        XCTAssertFalse(
            try XCTUnwrap(root.findEntity(named: DecisionOptionSceneOverlay.rootName)).isEnabled
        )
        XCTAssertTrue(try annotationLabel(in: markRoot(selected, in: root)).isEnabled)
        XCTAssertFalse(try annotationLabel(in: markRoot(context, in: root)).isEnabled)

        update(root, scenario: scenario, marks: marks)
        XCTAssertFalse(
            try XCTUnwrap(root.findEntity(named: DecisionOptionSceneOverlay.rootName)).isEnabled
        )
        for mark in marks {
            let entity = try markRoot(mark, in: root)
            XCTAssertEqual(
                try XCTUnwrap(entity.components[OpacityComponent.self]).opacity,
                1,
                accuracy: 0.000_1
            )
            XCTAssertTrue(try annotationLabel(in: entity).isEnabled)
            XCTAssertTrue(try bodyTarget(in: entity).isEnabled)
        }
        let labels = try playerLabels(in: root)
        XCTAssertEqual(labels.filter(\.isEnabled).count, scenario.players.count)
        let contextLabel = try XCTUnwrap(
            labels.first { $0.name == "player-label-navy-rb" }
        )
        XCTAssertEqual(
            contextLabel.scale.x,
            PlaybackSpatialLabels.tacticalContextLabelScale,
            accuracy: 0.000_1
        )
    }

    func testEditableSelectionSurvivesTemporarySeekOutsideOldWindow() throws {
        let scenario = try XCTUnwrap(DemoScenarios.scenario(for: .squadReplay))
        let selected = CoachMark(
            id: UUID(uuidString: "00000000-0000-4000-8000-00000000A147")!,
            kind: .run,
            start: PitchPoint(x: 12, z: 8),
            end: PitchPoint(x: 23, z: 19),
            label: "Retime me",
            revealTime: 10,
            hideTime: 20
        )
        let root = PitchSceneFactory.makeMatchRoot(for: scenario)

        update(
            root,
            scenario: scenario,
            marks: [selected],
            selectedID: selected.id,
            isEditable: true,
            time: 4
        )
        let markEntity = try markRoot(selected, in: root)
        XCTAssertTrue(markEntity.isEnabled)
        XCTAssertTrue(try annotationLabel(in: markEntity).isEnabled)
        let selection = try XCTUnwrap(
            root.findEntity(named: AnnotationSceneAffordance.selectionRootName)
        )
        XCTAssertTrue(selection.isEnabled)

        let outline = try XCTUnwrap(
            selection.findEntity(named: "annotation-selection-label-outline")
        )
        let label = try annotationLabel(in: markEntity)
        XCTAssertGreaterThan(simd_distance(outline.position, label.position), 0.09)

        // The authored interval takes control again as soon as selection closes.
        update(root, scenario: scenario, marks: [selected], time: 4)
        XCTAssertFalse(markEntity.isEnabled)
        XCTAssertFalse(selection.isEnabled)
    }

    func testSpaceRingUsesReusableCircumferenceTargetsInsteadOfTapWall() throws {
        let scenario = try XCTUnwrap(DemoScenarios.scenario(for: .squadReplay))
        let id = UUID(uuidString: "00000000-0000-4000-8000-00000000A148")!
        let original = CoachMark(
            id: id,
            kind: .space,
            start: PitchPoint(x: 18, z: 12),
            end: PitchPoint(x: 22, z: 12),
            label: "Useful space",
            revealTime: 0,
            hideTime: 30
        )
        let root = PitchSceneFactory.makeMatchRoot(for: scenario)
        update(root, scenario: scenario, marks: [original])

        let body = try bodyTarget(in: markRoot(original, in: root))
        XCTAssertNil(body.components[CollisionComponent.self])
        XCTAssertEqual(
            body.children.count,
            AnnotationSceneAffordance.spaceTargetSegmentCount
        )
        XCTAssertTrue(body.children.allSatisfy {
            $0.components[CollisionComponent.self] != nil
                && $0.components[InputTargetComponent.self] != nil
        })
        let firstSegment = try XCTUnwrap(body.children.first)
        XCTAssertEqual(
            AnnotationSceneAffordance.targetAncestor(of: firstSegment),
            AnnotationSceneTarget(markID: id, role: .body)
        )
        let originalLength = firstSegment.scale.z

        let expanded = CoachMark(
            id: id,
            kind: .space,
            start: original.start,
            end: PitchPoint(x: 27, z: 12),
            label: original.label,
            revealTime: original.revealTime,
            hideTime: original.hideTime
        )
        update(root, scenario: scenario, marks: [expanded])
        let updatedBody = try bodyTarget(in: markRoot(expanded, in: root))
        XCTAssertTrue(updatedBody.children.first === firstSegment)
        XCTAssertGreaterThan(firstSegment.scale.z, originalLength)
    }

    private func update(
        _ root: Entity,
        scenario: ReplayScenario,
        marks: [CoachMark],
        selectedID: UUID? = nil,
        isEditable: Bool = false,
        decisionSnapshot: ReplayDecisionSnapshot? = nil,
        time: TimeInterval = 14.1
    ) {
        PitchSceneFactory.update(
            root: root,
            scenario: scenario,
            time: time,
            viewMode: .tacticalTable,
            perspectiveID: scenario.defaultPerspectiveID,
            marks: marks,
            selectedAnnotationID: selectedID,
            selectedAnnotationIsEditable: isEditable,
            decisionSnapshot: decisionSnapshot,
            showsLaneLens: false,
            isDrawing: false,
            positionalOriginTransform: nil
        )
    }

    private func mark(
        id: String,
        kind: CoachMarkKind,
        start: PitchPoint,
        end: PitchPoint,
        label: String
    ) -> CoachMark {
        CoachMark(
            id: UUID(uuidString: id)!,
            kind: kind,
            start: start,
            end: end,
            label: label,
            revealTime: 0,
            hideTime: 30
        )
    }

    private func markRoot(_ mark: CoachMark, in root: Entity) throws -> Entity {
        try XCTUnwrap(root.findEntity(named: "mark-\(mark.id.uuidString)"))
    }

    private func annotationLabel(in root: Entity) throws -> Entity {
        try XCTUnwrap(root.findEntity(named: "annotation-label"))
    }

    private func bodyTarget(in root: Entity) throws -> Entity {
        try XCTUnwrap(root.findEntity(named: AnnotationSceneAffordance.bodyTargetName))
    }

    private func playerLabels(in root: Entity) throws -> [Entity] {
        Array(try XCTUnwrap(root.findEntity(named: "player-labels-root")).children)
    }

    private func descendant(in root: Entity, withPrefix prefix: String) throws -> Entity {
        if root.name.hasPrefix(prefix) { return root }
        for child in root.children {
            if let match = try? descendant(in: child, withPrefix: prefix) {
                return match
            }
        }
        throw LookupError.missing(prefix)
    }

    private enum LookupError: Error {
        case missing(String)
    }
}
