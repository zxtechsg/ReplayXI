import XCTest
@testable import ReplayXI

@MainActor
final class ReplayRoomEntryTests: XCTestCase {
    func testEnterRejectsOwnedTimelineWithoutDiscardingItsPreview() throws {
        let store = ReplayStore()
        store.seek(to: 5, broadcast: false)
        store.setPlaying(true, broadcast: false)
        XCTAssertTrue(store.beginTimelineScrub())
        XCTAssertTrue(store.previewTimelineScrub(to: 12))

        XCTAssertNil(store.beginImmersiveOpen(), "Enter must not take ownership before its pause can be applied")
        XCTAssertEqual(store.roomPresentation.phase, .closed)
        XCTAssertTrue(store.hasActiveTimelineScrub)
        XCTAssertEqual(store.playhead, 12)
        XCTAssertFalse(store.isPlaying)
        XCTAssertEqual(store.statusMessage, "Finish or cancel the timeline scrub first")

        store.cancelTimelineScrub()
        XCTAssertEqual(store.playhead, 5)
        XCTAssertTrue(store.isPlaying, "The rejected Enter must leave the gesture's original transport checkpoint intact")
        XCTAssertNotNil(store.beginImmersiveOpen())
        XCTAssertFalse(store.isPlaying, "A subsequent accepted Enter must apply its definitive pause")
    }

    func testEnterRejectsOwnedEndpointAdjustmentWithoutChangingItsGeometry() throws {
        let store = ReplayStore()
        let mark = try makeMark(in: store)
        let gestureID = UUID()
        XCTAssertNotNil(store.previewCoachMarkEndpoint(
            id: mark.id,
            endpoint: .end,
            gestureID: gestureID,
            cumulativeDelta: PitchPoint(x: 0.5, z: 0.5)
        ))
        let preview = try XCTUnwrap(store.marks.first { $0.id == mark.id })

        XCTAssertNil(store.beginImmersiveOpen())
        XCTAssertEqual(store.roomPresentation.phase, .closed)
        XCTAssertTrue(store.hasActiveCoachMarkEndpointPreview)
        XCTAssertEqual(store.marks.first { $0.id == mark.id }, preview)
        XCTAssertEqual(store.statusMessage, "Finish or cancel the annotation adjustment first")
        XCTAssertTrue(store.cancelCoachMarkEndpointPreview(id: mark.id, gestureID: gestureID))
        XCTAssertEqual(store.marks.first { $0.id == mark.id }, mark)
        XCTAssertNotNil(store.beginImmersiveOpen())
    }

    func testEnterRejectsDirectGeometryAdjustmentWithoutCancellingIt() throws {
        let store = ReplayStore()
        let mark = try makeMark(in: store)
        XCTAssertTrue(store.updateCoachMarkGeometry(
            id: mark.id,
            start: PitchPoint(x: 3, z: 4),
            end: PitchPoint(x: 7, z: 9),
            broadcast: false
        ))
        let preview = try XCTUnwrap(store.marks.first { $0.id == mark.id })

        XCTAssertNil(store.beginImmersiveOpen())
        XCTAssertEqual(store.roomPresentation.phase, .closed)
        XCTAssertTrue(store.hasActiveCoachMarkGeometryPreview)
        XCTAssertFalse(store.hasActiveCoachMarkEndpointPreview)
        XCTAssertEqual(store.marks.first { $0.id == mark.id }, preview)
        XCTAssertEqual(store.statusMessage, "Finish or cancel the annotation adjustment first")
        XCTAssertTrue(store.cancelCoachMarkGeometryPreview(id: mark.id))
        XCTAssertEqual(store.marks.first { $0.id == mark.id }, mark)
    }

    func testSuccessfulOpenReplacesTheOpeningProgressMessage() throws {
        let store = ReplayStore()
        let requestID = try XCTUnwrap(store.beginImmersiveOpen())
        store.statusMessage = "Opening spatial replay…"
        XCTAssertEqual(store.immersiveRoomDidAppear(requestID), requestID)
        XCTAssertTrue(store.completeImmersiveOpen(requestID, opened: true))
        XCTAssertEqual(store.statusMessage, "Spatial replay ready")
        XCTAssertFalse(store.isPlaying)
    }

    func testPausedDrawingDraftCanCarryIntoTheRoomWithoutBeingDiscarded() throws {
        let store = ReplayStore()
        store.seek(to: 6, broadcast: false)
        store.beginDrawing(.run)
        let start = PitchPoint(x: 4, z: 6)
        XCTAssertNil(store.registerPitchTap(start))
        let markCount = store.marks.count

        let requestID = try XCTUnwrap(store.beginImmersiveOpen())
        XCTAssertEqual(store.immersiveRoomDidAppear(requestID), requestID)
        XCTAssertTrue(store.completeImmersiveOpen(requestID, opened: true))
        XCTAssertTrue(store.isDrawing)
        XCTAssertEqual(store.selectedTool, .run)
        XCTAssertEqual(store.pendingDrawStart, start)
        XCTAssertEqual(store.playhead, 6)
        XCTAssertEqual(store.marks.count, markCount)
        XCTAssertFalse(store.isPlaying)
        let completedMark = try XCTUnwrap(store.registerPitchTap(PitchPoint(x: 9, z: 12)))
        XCTAssertEqual(completedMark.start, start)
        XCTAssertEqual(completedMark.revealTime, 6)
        XCTAssertFalse(store.isDrawing)
    }

    func testSuccessfulOpenBeforeAppearanceReplacesPreparationProgress() throws {
        let store = ReplayStore()
        let requestID = try XCTUnwrap(store.beginImmersiveOpen())
        XCTAssertTrue(store.completeImmersiveOpen(requestID, opened: true))
        XCTAssertEqual(store.statusMessage, "Spatial replay ready")
        XCTAssertEqual(store.immersiveRoomDidAppear(requestID), requestID)
    }

    func testLateOpenCompletionDoesNotOverwriteANewerInteractionMessage() throws {
        let store = ReplayStore()
        let requestID = try XCTUnwrap(store.beginImmersiveOpen())
        store.statusMessage = "Opening spatial replay…"
        XCTAssertEqual(store.immersiveRoomDidAppear(requestID), requestID)
        store.beginDrawing(.run)
        let newerMessage = store.statusMessage

        XCTAssertTrue(store.completeImmersiveOpen(requestID, opened: true))
        XCTAssertEqual(store.statusMessage, newerMessage)
        XCTAssertTrue(store.isDrawing)
    }

    func testSystemDismissalKeepsItsPausedStatusAfterALateOpenResult() throws {
        let store = ReplayStore()
        let requestID = try XCTUnwrap(store.beginImmersiveOpen())
        store.statusMessage = "Opening spatial replay…"
        XCTAssertEqual(store.immersiveRoomDidAppear(requestID), requestID)
        XCTAssertTrue(store.immersiveRoomDidDisappear(requestID))
        let closedMessage = store.statusMessage
        XCTAssertEqual(closedMessage, "Replay paused outside the immersive room")

        XCTAssertFalse(store.completeImmersiveOpen(requestID, opened: true))
        XCTAssertEqual(store.statusMessage, closedMessage)
        XCTAssertEqual(store.roomPresentation.phase, .closed)
        XCTAssertFalse(store.isPlaying)
    }

    func testDuplicateEnterCannotReplaceTheCurrentRoomsGestureStatus() throws {
        let store = ReplayStore()
        let requestID = try XCTUnwrap(store.beginImmersiveOpen())
        XCTAssertEqual(store.immersiveRoomDidAppear(requestID), requestID)
        XCTAssertTrue(store.completeImmersiveOpen(requestID, opened: true))
        XCTAssertTrue(store.beginTimelineScrub())
        store.statusMessage = "Current room gesture"

        XCTAssertNil(store.beginImmersiveOpen())
        XCTAssertEqual(store.statusMessage, "Current room gesture")
        XCTAssertTrue(store.hasActiveTimelineScrub)
        XCTAssertEqual(store.roomPresentation.requestID, requestID)
    }

    func testAllDashboardEntryActionsUseTheGestureGateAndTransitionInputLock() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        let source = try String(
            contentsOf: root.appendingPathComponent("ReplayXI/UI/ReplayDashboardView.swift"),
            encoding: .utf8
        )
        let shapeStart = try XCTUnwrap(source.range(of: "private struct ShapeFocusDashboard: View")?.lowerBound)
        let shapeEnd = try XCTUnwrap(source.range(of: "private struct ShapeFocusStepButton: View")?.lowerBound)
        let shape = String(source[shapeStart..<shapeEnd])
        let railStart = try XCTUnwrap(source.range(of: "private struct RoomRail: View")?.lowerBound)
        let rail = String(source[railStart...])

        XCTAssertTrue(source.contains(".disabled(store.isOpeningImmersive || store.isClosingImmersive)"))
        XCTAssertTrue(shape.contains("&& !store.hasActiveTimelineScrub && !store.hasActiveCoachMarkGeometryPreview"))
        XCTAssertTrue(shape.contains("enabled: item == .physical ? canEnterSpatialSetup : canCompareShapes"))
        XCTAssertTrue(shape.contains(".disabled(!canEnterSpatialSetup)"))
        XCTAssertTrue(shape.contains("guard canEnterSpatialSetup else { return }"))
        XCTAssertTrue(shape.contains("roomEntryGestureHint(for: store)"))
        XCTAssertTrue(rail.contains(".disabled(store.isRoomPresentationBusy)"))
        XCTAssertTrue(rail.contains(".disabled(store.hasActiveTimelineScrub || store.hasActiveCoachMarkGeometryPreview)"))
        XCTAssertTrue(rail.contains("return roomEntryGestureHint(for: store)"))
        XCTAssertTrue(source.contains("Finish the timeline drag before entering."))
        XCTAssertTrue(source.contains("Finish the annotation adjustment before entering."))
    }

    private func makeMark(in store: ReplayStore) throws -> CoachMark {
        store.beginDrawing(.pass)
        XCTAssertNil(store.registerPitchTap(PitchPoint(x: 2, z: 3)))
        return try XCTUnwrap(store.registerPitchTap(PitchPoint(x: 6, z: 8)))
    }
}
