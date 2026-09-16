import RealityKit
import XCTest
@testable import ReplayXI

@MainActor
final class PlaybackAccessibilityActivationTests: XCTestCase {
    func testArmedLabelActivationCreatesOneMarkAtTheCurrentPlayerPoseAndTime() throws {
        let fixture = try Fixture()
        let player = try XCTUnwrap(fixture.store.selectedScenario.player(id: "red-lb"))
        let target = try fixture.playerTarget(player.id)
        let originalMarks = fixture.store.marks
        let originalPOV = fixture.store.activePerspectiveID
        fixture.store.beginDrawing(.playerLabel)
        fixture.render()
        XCTAssertTrue(target.isEnabledInHierarchy)
        let targetAX = try XCTUnwrap(target.components[AccessibilityComponent.self])
        XCTAssertTrue(targetAX.isAccessibilityElement)
        XCTAssertTrue(targetAX.systemActions.contains(.activate))

        fixture.activate(target)

        XCTAssertEqual(fixture.store.marks.count, originalMarks.count + 1)
        let label = try XCTUnwrap(fixture.store.marks.last { $0.kind == .playerLabel })
        let pose = fixture.store.presentedPlayerPose(for: player, at: 12.25)
        XCTAssertEqual(label.playerID, player.id)
        XCTAssertEqual(label.start, pose.position)
        XCTAssertEqual(label.end, pose.position)
        XCTAssertEqual(label.revealTime, 12.25)
        XCTAssertEqual(fixture.store.playhead, 12.25)
        XCTAssertEqual(fixture.store.activePerspectiveID, originalPOV)
        XCTAssertEqual(fixture.store.viewMode, .tacticalTable)
        XCTAssertFalse(fixture.store.isDrawing)
        XCTAssertNil(fixture.store.pendingDrawStart)
        XCTAssertNil(fixture.selectedAnnotationID)
        XCTAssertEqual(Array(fixture.store.marks.dropLast()), originalMarks)
    }

    func testNormalPlayerActivationPreservesPOVNavigationAndCurrentPOVNoOp() throws {
        let fixture = try Fixture()
        let target = try fixture.playerTarget("red-lb")
        let marks = fixture.store.marks
        fixture.store.setPlaying(true, broadcast: false)

        fixture.activate(target)

        XCTAssertEqual(fixture.store.activePerspectiveID, "red-lb")
        XCTAssertEqual(fixture.store.viewMode, .firstPerson)
        XCTAssertEqual(fixture.store.playhead, 12.25)
        XCTAssertFalse(fixture.store.isPlaying)
        XCTAssertEqual(fixture.store.marks, marks)
        XCTAssertNil(fixture.selectedAnnotationID)

        // A repeated semantic activation of the same still-retained target
        // must not pause the current POV a second time.
        fixture.store.setPlaying(true, broadcast: false)
        let beforeRepeatedActivation = fixture.snapshot
        fixture.activate(target)
        XCTAssertEqual(fixture.snapshot, beforeRepeatedActivation)
    }

    func testExistingAnnotationSelectionStillPrecedesItsReviewSeek() throws {
        let fixture = try Fixture()
        let mark = try XCTUnwrap(fixture.store.selectedScenario.coachMarks.first { $0.kind == .run })
        let target = try fixture.markTarget(mark.id)
        XCTAssertTrue(target.isEnabledInHierarchy)
        fixture.store.setPlaying(true, broadcast: false)

        fixture.activate(target)

        XCTAssertEqual(fixture.selectedAnnotationID, mark.id)
        XCTAssertEqual(fixture.playheadWhenSelected, 12.25)
        XCTAssertEqual(fixture.store.playhead, mark.revealTime)
        XCTAssertFalse(fixture.store.isPlaying)
        XCTAssertEqual(fixture.store.viewMode, .tacticalTable)
    }

    func testTimelineAndEndpointTransactionsKeepExclusiveOwnership() throws {
        let fixture = try Fixture()
        let playerTarget = try fixture.playerTarget("red-lb")
        let preset = try XCTUnwrap(fixture.store.selectedScenario.coachMarks.first { $0.kind == .run })
        let presetTarget = try fixture.markTarget(preset.id)
        XCTAssertTrue(fixture.store.beginTimelineScrub())
        XCTAssertTrue(fixture.store.previewTimelineScrub(to: 17))
        let scrub = fixture.snapshot
        fixture.activate(playerTarget)
        fixture.activate(presetTarget)
        XCTAssertEqual(fixture.snapshot, scrub)
        fixture.store.cancelTimelineScrub()

        let mark = try fixture.addRun()
        let gestureID = UUID()
        XCTAssertNotNil(fixture.store.previewCoachMarkEndpoint(
            id: mark.id, endpoint: .end, gestureID: gestureID,
            cumulativeDelta: PitchPoint(x: 1, z: 0)
        ))
        let endpoint = fixture.snapshot
        fixture.activate(playerTarget)
        fixture.activate(presetTarget)
        XCTAssertEqual(fixture.snapshot, endpoint)
        XCTAssertTrue(fixture.store.cancelCoachMarkEndpointPreview(id: mark.id, gestureID: gestureID))
    }

    func testTwoPointDraftsIgnorePlayerActivationWithAndWithoutAHeldStroke() throws {
        let fixture = try Fixture()
        let target = try fixture.playerTarget("red-lb")
        for kind in [CoachMarkKind.run, .pass, .danger, .space] {
            fixture.store.beginDrawing(kind)
            for start in [PitchPoint?.none, PitchPoint(x: -20, z: -30)] {
                if let start { XCTAssertNil(fixture.store.registerPitchTap(start)) }
                let before = fixture.snapshot
                fixture.activate(target, hasActiveDrawingStroke: false)
                fixture.activate(target, hasActiveDrawingStroke: true)
                XCTAssertEqual(fixture.snapshot, before, kind.title)
            }
            fixture.store.cancelDrawing()
        }
    }

    func testHeldStrokeDefersAnArmedLabelUntilAFreshPostEndActivation() throws {
        let fixture = try Fixture()
        let target = try fixture.playerTarget("red-lb")
        fixture.store.beginDrawing(.playerLabel)
        fixture.render()
        let before = fixture.snapshot

        fixture.activate(target, hasActiveDrawingStroke: true)
        XCTAssertEqual(fixture.snapshot, before)
        fixture.activate(target, hasActiveDrawingStroke: false)

        XCTAssertEqual(fixture.store.marks.count, before.marks.count + 1)
        XCTAssertEqual(fixture.store.marks.last?.kind, .playerLabel)
        XCTAssertEqual(fixture.store.marks.last?.playerID, "red-lb")
        XCTAssertFalse(fixture.store.isDrawing)
        XCTAssertEqual(fixture.store.viewMode, .tacticalTable)
    }

    func testDisabledPlayerAndDisabledAncestorCannotNavigateThePOV() throws {
        let fixture = try Fixture()
        let target = try fixture.playerTarget("red-lb")
        target.isEnabled = false
        XCTAssertFalse(target.isEnabledInHierarchy)
        var before = fixture.snapshot
        fixture.activate(target)
        XCTAssertEqual(fixture.snapshot, before, "Disabled target")

        fixture.store.setViewMode(.tacticalTable, broadcast: false)
        target.isEnabled = true
        let playerRoot = try XCTUnwrap(fixture.root.findEntity(named: "player-red-lb"))
        playerRoot.isEnabled = false
        XCTAssertFalse(target.isEnabledInHierarchy)
        before = fixture.snapshot
        fixture.activate(target)
        XCTAssertEqual(fixture.snapshot, before, "Disabled ancestor")
    }

    func testErasedAnnotationEventCannotLeaveAStaleSelection() throws {
        let fixture = try Fixture()
        let mark = try fixture.addRun()
        fixture.render()
        let staleTarget = try fixture.markTarget(mark.id)
        XCTAssertTrue(fixture.store.removeCoachMark(id: mark.id))
        // A queued activation can refer to the previous scene frame. Do not
        // substitute a synthetic UUID-only target: retain the actual body.
        fixture.selectedAnnotationID = fixture.store.selectedScenario.coachMarks.first?.id
        let before = fixture.snapshot

        fixture.activate(staleTarget)

        XCTAssertEqual(fixture.snapshot, before)
        XCTAssertFalse(fixture.store.marks.contains { $0.id == mark.id })
    }

    func testHeldStrokeCannotSelectAnAnnotationAndFreshPostEndEventCan() throws {
        let fixture = try Fixture()
        let preset = try XCTUnwrap(fixture.store.selectedScenario.coachMarks.first { $0.kind == .run })
        let target = try fixture.markTarget(preset.id)
        fixture.store.beginDrawing(.run)
        XCTAssertNil(fixture.store.registerPitchTap(PitchPoint(x: -20, z: -30)))
        fixture.render()
        XCTAssertFalse(target.isEnabledInHierarchy)
        let duringStroke = fixture.snapshot

        fixture.activate(target, hasActiveDrawingStroke: true)

        XCTAssertEqual(fixture.snapshot, duringStroke)
        let completed = try XCTUnwrap(fixture.store.registerPitchTap(PitchPoint(x: -16, z: -25)))
        fixture.render()
        let completedTarget = try fixture.markTarget(completed.id)
        XCTAssertTrue(completedTarget.isEnabledInHierarchy)
        fixture.activate(completedTarget, hasActiveDrawingStroke: false)
        XCTAssertEqual(fixture.selectedAnnotationID, completed.id)
        XCTAssertEqual(fixture.store.playhead, completed.revealTime)
        XCTAssertFalse(fixture.store.isDrawing)
    }

    func testPreviousScenarioPlayerTargetCannotNavigateTheNewScenario() throws {
        let fixture = try Fixture()
        let staleTarget = try fixture.playerTarget("red-lb")
        let next = try XCTUnwrap(fixture.store.scenarios.first { $0.kind == .coachFocus })
        fixture.store.selectScenario(id: next.id, broadcast: false)
        let before = fixture.snapshot

        fixture.activate(staleTarget)

        XCTAssertEqual(fixture.snapshot, before)
        XCTAssertNotEqual(fixture.root.name, "match-root-\(fixture.store.selectedScenarioID)")
    }

    func testClosingAndRetiredRoomsRejectActivationWhileTheCurrentRoomStillWorks() throws {
        let fixture = try Fixture()
        let playerTarget = try fixture.playerTarget("red-lb")
        let preset = try XCTUnwrap(fixture.store.selectedScenario.coachMarks.first { $0.kind == .run })
        let markTarget = try fixture.markTarget(preset.id)
        XCTAssertTrue(fixture.store.beginImmersiveClose(fixture.roomPresentationID))
        var before = fixture.snapshot
        fixture.activate(playerTarget)
        fixture.activate(markTarget)
        XCTAssertEqual(fixture.snapshot, before)
        XCTAssertTrue(fixture.store.immersiveRoomDidDisappear(fixture.roomPresentationID))
        fixture.store.completeImmersiveClose(fixture.roomPresentationID)
        let currentRoom = try XCTUnwrap(fixture.store.beginImmersiveOpen())
        XCTAssertTrue(fixture.store.completeImmersiveOpen(currentRoom, opened: true))
        XCTAssertEqual(fixture.store.immersiveRoomDidAppear(currentRoom), currentRoom)
        before = fixture.snapshot
        fixture.activate(playerTarget)
        fixture.activate(markTarget)
        XCTAssertEqual(fixture.snapshot, before)

        fixture.activate(playerTarget, roomPresentationID: currentRoom)
        XCTAssertEqual(fixture.store.activePerspectiveID, "red-lb")
        XCTAssertEqual(fixture.store.viewMode, .firstPerson)
    }

    func testTheLiveSceneForwardsRealEventsAndItsStrokeOwnerToTheRouter() throws {
        let file = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("ReplayXI/Immersive/FootballImmersiveView.swift")
        let source = try String(contentsOf: file, encoding: .utf8)
        XCTAssertTrue(source.contains("to: AccessibilityEvents.Activate.self"))
        XCTAssertTrue(source.contains("handleAccessibilityActivation(event)"))
        XCTAssertTrue(source.contains("PlaybackAccessibilityActivationRouter.handle("))
        XCTAssertTrue(source.contains("hasActiveDrawingStroke: annotationStroke != nil"))
        XCTAssertTrue(source.contains("PlaybackAccessibilityActivationRouter.playerIDAncestor(of: entity)"))
        XCTAssertTrue(source.contains("PlaybackAccessibilityActivationRouter.reviewAnnotation(mark, in: store)"))
    }

    private struct Snapshot: Equatable {
        let marks: [CoachMark]
        let scenarioID: String
        let playhead: TimeInterval
        let perspectiveID: String
        let viewMode: ReplayViewMode
        let isPlaying: Bool
        let isDrawing: Bool
        let pendingStart: PitchPoint?
        let ownsTimeline: Bool
        let ownsEndpoint: Bool
        let selectedAnnotationID: UUID?
    }

    @MainActor
    private final class Fixture {
        let store: ReplayStore
        let roomPresentationID: UUID
        let root: Entity
        var selectedAnnotationID: UUID?
        var playheadWhenSelected: TimeInterval?

        init() throws {
            let store = ReplayStore()
            store.prepareForLocalExperience()
            store.seek(to: 12.25, broadcast: false)
            let request = try XCTUnwrap(store.beginImmersiveOpen())
            XCTAssertTrue(store.completeImmersiveOpen(request, opened: true))
            XCTAssertEqual(store.immersiveRoomDidAppear(request), request)
            self.store = store
            roomPresentationID = request
            root = PitchSceneFactory.makeMatchRoot(for: store.selectedScenario)
            render()
        }

        var snapshot: Snapshot {
            Snapshot(
                marks: store.marks, scenarioID: store.selectedScenarioID,
                playhead: store.playhead, perspectiveID: store.activePerspectiveID,
                viewMode: store.viewMode, isPlaying: store.isPlaying,
                isDrawing: store.isDrawing, pendingStart: store.pendingDrawStart,
                ownsTimeline: store.hasActiveTimelineScrub,
                ownsEndpoint: store.hasActiveCoachMarkGeometryPreview,
                selectedAnnotationID: selectedAnnotationID
            )
        }

        func activate(
            _ entity: Entity,
            hasActiveDrawingStroke: Bool = false,
            roomPresentationID: UUID? = nil
        ) {
            PlaybackAccessibilityActivationRouter.handle(
                AccessibilityEvents.Activate(entity: entity),
                store: store,
                roomPresentationID: roomPresentationID ?? self.roomPresentationID,
                hasActiveDrawingStroke: hasActiveDrawingStroke
            ) { annotationID in
                selectedAnnotationID = annotationID
                playheadWhenSelected = store.playhead
            }
        }

        func playerTarget(_ id: String) throws -> Entity {
            let player = try XCTUnwrap(root.findEntity(named: "player-\(id)"))
            return try XCTUnwrap(player.findEntity(named: "interaction-target"))
        }

        func markTarget(_ id: UUID) throws -> Entity {
            let mark = try XCTUnwrap(root.findEntity(named: "mark-\(id.uuidString)"))
            return try XCTUnwrap(mark.findEntity(named: AnnotationSceneAffordance.bodyTargetName))
        }

        func addRun() throws -> CoachMark {
            store.beginDrawing(.run)
            XCTAssertNil(store.registerPitchTap(PitchPoint(x: -20, z: -30)))
            return try XCTUnwrap(store.registerPitchTap(PitchPoint(x: -16, z: -25)))
        }

        func render() {
            PitchSceneFactory.update(
                root: root, scenario: store.selectedScenario, time: store.playhead,
                viewMode: store.viewMode, perspectiveID: store.activePerspectiveID,
                marks: store.marks, selectedAnnotationID: selectedAnnotationID,
                selectedAnnotationIsEditable: false, showsLaneLens: false,
                isDrawing: store.isDrawing, positionalOriginTransform: nil
            )
        }
    }
}
