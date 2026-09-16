import XCTest
@testable import ReplayXI

@MainActor
final class ReplayPhysicalDrillSafetyTests: XCTestCase {
    func testPhysicalActivationRejectsAnUnfinishedDraftWithoutMovingItsTime() throws {
        for shared in [false, true] {
            let store = makeStore()
            store.beginDrawing(.run)
            let start = PitchPoint(x: 4, z: 6)
            XCTAssertNil(store.registerPitchTap(start))
            let originalTime = store.playhead
            let activated = shared
                ? store.activateTrianglePlacement(anchorID: UUID())
                : store.activateLocalTrianglePreview(anchorID: UUID())
            XCTAssertFalse(activated)
            XCTAssertEqual(store.triangleLockMode, .visualise)
            XCTAssertNil(store.sharedPitchAnchorID)
            XCTAssertTrue(store.isDrawing)
            XCTAssertEqual(store.pendingDrawStart, start)
            XCTAssertEqual(store.playhead, originalTime)
            XCTAssertEqual(store.statusMessage, "Finish or cancel the annotation before placing stations")
        }
    }

    func testEveryDrawingToolIsUnavailableDuringPhysicalPlacement() {
        for kind in CoachMarkKind.allCases {
            let store = makeStore()
            store.activateLocalTrianglePreview(anchorID: UUID())
            store.beginDrawing(kind)
            XCTAssertFalse(store.isDrawing, "\(kind)")
            XCTAssertNil(store.pendingDrawStart)
            XCTAssertEqual(store.statusMessage, "End the physical drill before editing annotations")
        }
    }

    func testLabelPresetAndStrandedDraftCannotCreateHiddenMarks() throws {
        let store = makeStore()
        store.activateLocalTrianglePreview(anchorID: UUID())
        let before = store.marks
        XCTAssertNil(store.labelPlayer("navy-rw"))
        store.addPresetMark()
        // Simulate a draft left by an older app build or interrupted callback.
        store.isDrawing = true
        store.selectedTool = .run
        store.pendingDrawStart = PitchPoint(x: 2, z: 3)
        XCTAssertNil(store.registerPitchTap(PitchPoint(x: 8, z: 9)))
        XCTAssertEqual(store.marks, before)
        store.cancelDrawing()
        XCTAssertFalse(store.isDrawing, "Cancellation must remain available in the drill")
        XCTAssertNil(store.pendingDrawStart)
    }

    func testDirectAndJoystickHandleAcquisitionAreRejectedDuringPlacement() throws {
        let (store, mark, _) = try placedStoreWithMark()
        XCTAssertFalse(store.updateCoachMarkGeometry(
            id: mark.id, start: PitchPoint(x: 3, z: 4), end: PitchPoint(x: 7, z: 9), broadcast: false
        ))
        XCTAssertFalse(store.hasActiveCoachMarkGeometryPreview)
        XCTAssertNil(store.previewCoachMarkEndpoint(
            id: mark.id, endpoint: .end, gestureID: UUID(), cumulativeDelta: PitchPoint(x: 0.5, z: 0.5)
        ))
        XCTAssertFalse(store.hasActiveCoachMarkEndpointPreview)
        XCTAssertEqual(store.marks.first { $0.id == mark.id }, mark)
    }

    func testGeometryNudgesTrackingAndMetadataStayReadOnlyDuringPlacement() throws {
        let (store, mark, _) = try placedStoreWithMark()
        XCTAssertFalse(store.updateCoachMarkGeometry(
            id: mark.id, start: PitchPoint(x: 3, z: 4), end: PitchPoint(x: 7, z: 9)
        ))
        XCTAssertFalse(store.nudgeCoachMarkEndpoint(id: mark.id, endpoint: .end, by: PitchPoint(x: 0.5, z: 0)))
        XCTAssertFalse(store.nudgeCoachMarkElevation(id: mark.id, target: .both, by: 0.2))
        XCTAssertFalse(store.setCoachMarkTracking(id: mark.id, playerID: "navy-rw"))
        XCTAssertFalse(store.retimeCoachMark(id: mark.id, to: 17))
        XCTAssertFalse(store.setCoachMarkDuration(id: mark.id, duration: 2))
        XCTAssertFalse(store.updateCoachMarkLabel(id: mark.id, label: "Hidden edit"))
        XCTAssertEqual(store.marks.first { $0.id == mark.id }, mark)
        XCTAssertFalse(store.hasActiveCoachMarkGeometryPreview)
    }

    func testDeleteClearAndUndoCannotChangeHiddenAnnotationsOrHistory() throws {
        let (store, mark, _) = try placedStoreWithMark()
        let before = store.marks
        XCTAssertFalse(store.canUndoAnnotationEdit)
        XCTAssertFalse(store.removeCoachMark(id: mark.id))
        store.clearMarks()
        XCTAssertFalse(store.undoAnnotationEdit())
        XCTAssertEqual(store.marks, before)
        store.endTrianglePlacement()
        XCTAssertTrue(store.undoAnnotationEdit(), "The original add must remain the next undo action")
        XCTAssertFalse(store.marks.contains { $0.id == mark.id })
    }

    func testRedoRemainsAvailableAfterTheDrillButCannotEditDuringIt() throws {
        let store = makeStore()
        let mark = try addMark(to: store)
        XCTAssertTrue(store.undoAnnotationEdit())
        store.activateLocalTrianglePreview(anchorID: UUID())
        XCTAssertFalse(store.canRedoAnnotationEdit)
        XCTAssertFalse(store.redoAnnotationEdit())
        XCTAssertFalse(store.marks.contains { $0.id == mark.id })
        store.endTrianglePlacement()
        XCTAssertTrue(store.redoAnnotationEdit())
        XCTAssertEqual(store.marks.first { $0.id == mark.id }, mark)
    }

    func testEndDrillCancelsAStrandedTimelineAndRetiresOnlyItsAnchorOnce() throws {
        let (store, mark, anchorID) = try placedStoreWithMark()
        var retired: [UUID] = []
        store.onRetirePitchAnchor = { retired.append($0) }
        let originalTime = store.playhead
        XCTAssertTrue(store.beginTimelineScrub())
        XCTAssertTrue(store.previewTimelineScrub(to: 20))
        store.endTrianglePlacement()
        XCTAssertEqual(store.triangleLockMode, .visualise)
        XCTAssertNil(store.sharedPitchAnchorID)
        XCTAssertFalse(store.hasActiveTimelineScrub)
        XCTAssertFalse(store.isPlaying)
        XCTAssertEqual(store.playhead, originalTime)
        XCTAssertEqual(store.marks.first { $0.id == mark.id }, mark)
        XCTAssertEqual(retired, [anchorID])
        store.endTrianglePlacement()
        XCTAssertEqual(retired, [anchorID])
    }

    func testEndDrillCancelsAStrandedDraftWithoutDeletingCommittedMarks() throws {
        let (store, mark, anchorID) = try placedStoreWithMark()
        store.isDrawing = true
        store.selectedTool = .pass
        store.pendingDrawStart = PitchPoint(x: 3, z: 5)
        var retired: [UUID] = []
        store.onRetirePitchAnchor = { retired.append($0) }
        store.endTrianglePlacement()
        XCTAssertEqual(store.triangleLockMode, .visualise)
        XCTAssertFalse(store.isDrawing)
        XCTAssertNil(store.pendingDrawStart)
        XCTAssertFalse(store.isPlaying)
        XCTAssertEqual(store.marks.first { $0.id == mark.id }, mark)
        XCTAssertEqual(retired, [anchorID])
        XCTAssertTrue(store.undoAnnotationEdit())
        XCTAssertFalse(store.marks.contains { $0.id == mark.id })
    }

    func testStationSelectionReportsARoleWithoutClaimingAPOV() throws {
        let store = makeStore()
        store.activateLocalTrianglePreview(anchorID: UUID())
        let target = try XCTUnwrap(store.selectedScenario.formationTargets.last)
        let player = try XCTUnwrap(store.selectedScenario.player(id: target.playerID))
        store.setLocalPerspective(target.playerID, entersLocalReview: false)
        XCTAssertEqual(store.localPerspectiveID, target.playerID)
        XCTAssertEqual(store.viewMode, .positional)
        XCTAssertEqual(store.triangleLockMode, .place)
        XCTAssertEqual(store.statusMessage, "Role station: #\(player.shirtNumber) · \(target.label)")
    }

    func testNonCoachEndCannotCancelAnotherRolesGestureOrRetireTheAnchor() throws {
        let (store, _, anchorID) = try placedStoreWithMark()
        store.localRole = .player
        XCTAssertTrue(store.beginTimelineScrub())
        var retired: [UUID] = []
        store.onRetirePitchAnchor = { retired.append($0) }
        store.endTrianglePlacement()
        XCTAssertEqual(store.triangleLockMode, .place)
        XCTAssertEqual(store.sharedPitchAnchorID, anchorID)
        XCTAssertTrue(store.hasActiveTimelineScrub)
        XCTAssertTrue(retired.isEmpty)
    }

    func testActivationRechecksNewTimelineAndGeometryTransactions() throws {
        for shared in [false, true] {
            for input in ["timeline", "handle", "joystick"] {
                let store = makeStore()
                let mark = try addMark(to: store)
                XCTAssertNil(store.trianglePlacementInputBlockReason)
                switch input {
                case "timeline":
                    XCTAssertTrue(store.beginTimelineScrub())
                    XCTAssertTrue(store.previewTimelineScrub(to: 18))
                case "handle":
                    XCTAssertTrue(store.updateCoachMarkGeometry(
                        id: mark.id, start: PitchPoint(x: 3, z: 4),
                        end: PitchPoint(x: 7, z: 9), broadcast: false
                    ))
                default:
                    XCTAssertNotNil(store.previewCoachMarkEndpoint(
                        id: mark.id, endpoint: .end, gestureID: UUID(),
                        cumulativeDelta: PitchPoint(x: 0.5, z: 0.5)
                    ))
                }
                let timeBefore = store.playhead
                let marksBefore = store.marks
                let blockReason = try XCTUnwrap(store.trianglePlacementInputBlockReason)
                let activated = shared
                    ? store.activateTrianglePlacement(anchorID: UUID())
                    : store.activateLocalTrianglePreview(anchorID: UUID())
                XCTAssertFalse(activated, input)
                XCTAssertEqual(store.triangleLockMode, .visualise)
                XCTAssertNil(store.sharedPitchAnchorID)
                XCTAssertEqual(store.playhead, timeBefore)
                XCTAssertEqual(store.marks, marksBefore)
                XCTAssertEqual(store.statusMessage, blockReason)
                XCTAssertTrue(store.hasActiveTimelineScrub || store.hasActiveCoachMarkGeometryPreview)
            }
        }
    }

    func testDirectHandleEndCannotRecreateACancelledEditBeforeDuringOrAfterDrill() throws {
        let store = makeStore()
        let mark = try addMark(to: store)
        let start = PitchPoint(x: 3, z: 4)
        let end = PitchPoint(x: 7, z: 9)
        XCTAssertTrue(store.updateCoachMarkGeometry(id: mark.id, start: start, end: end, broadcast: false))
        XCTAssertTrue(store.cancelCoachMarkGeometryPreview(id: mark.id))
        XCTAssertFalse(store.commitCoachMarkGeometryPreview(id: mark.id, start: start, end: end))
        XCTAssertTrue(store.activateLocalTrianglePreview(anchorID: UUID()))
        XCTAssertFalse(store.commitCoachMarkGeometryPreview(id: mark.id, start: start, end: end))
        store.endTrianglePlacement()
        XCTAssertFalse(store.commitCoachMarkGeometryPreview(id: mark.id, start: start, end: end))
        XCTAssertEqual(store.marks.first { $0.id == mark.id }, mark)
        XCTAssertFalse(store.hasActiveCoachMarkGeometryPreview)
        XCTAssertTrue(store.undoAnnotationEdit(), "A stale lift must not add another undo checkpoint")
        XCTAssertFalse(store.marks.contains { $0.id == mark.id })
    }

    func testDirectHandleEndCommitsAnOwnedPreviewOutsideTheDrill() throws {
        let store = makeStore()
        let mark = try addMark(to: store)
        let start = PitchPoint(x: 3, z: 4)
        let end = PitchPoint(x: 7, z: 9)
        XCTAssertTrue(store.updateCoachMarkGeometry(id: mark.id, start: start, end: end, broadcast: false))
        XCTAssertTrue(store.commitCoachMarkGeometryPreview(id: mark.id, start: start, end: end))
        XCTAssertFalse(store.hasActiveCoachMarkGeometryPreview)
        let changed = try XCTUnwrap(store.marks.first { $0.id == mark.id })
        let presented = store.presentedCoachMarkGeometry(changed, at: store.playhead)
        XCTAssertEqual(presented.start, start)
        XCTAssertEqual(presented.end, end)
        XCTAssertTrue(store.undoAnnotationEdit())
        XCTAssertEqual(store.marks.first { $0.id == mark.id }, mark)
    }

    func testDirectHandleEndCannotConsumeAJoystickTransaction() throws {
        let store = makeStore()
        let mark = try addMark(to: store)
        let gestureID = UUID()
        XCTAssertNotNil(store.previewCoachMarkEndpoint(
            id: mark.id, endpoint: .end, gestureID: gestureID,
            cumulativeDelta: PitchPoint(x: 0.5, z: 0.5)
        ))
        let preview = store.marks
        XCTAssertFalse(store.commitCoachMarkGeometryPreview(
            id: mark.id, start: PitchPoint(x: 3, z: 4), end: PitchPoint(x: 7, z: 9)
        ))
        XCTAssertEqual(store.marks, preview)
        XCTAssertTrue(store.hasActiveCoachMarkEndpointPreview)
        XCTAssertTrue(store.cancelCoachMarkEndpointPreview(id: mark.id, gestureID: gestureID))
        XCTAssertEqual(store.marks.first { $0.id == mark.id }, mark)
    }

    func testBlockedStationSelectionPreservesRoleAndReportsTheOwnedGesture() throws {
        let store = makeStore()
        XCTAssertTrue(store.activateLocalTrianglePreview(anchorID: UUID()))
        let target = try XCTUnwrap(store.selectedScenario.formationTargets.last)
        let originalRole = store.localPerspectiveID
        XCTAssertTrue(store.beginTimelineScrub())
        store.setLocalPerspective(target.playerID, entersLocalReview: false)
        XCTAssertEqual(store.localPerspectiveID, originalRole)
        XCTAssertEqual(store.statusMessage, "Finish or cancel the timeline scrub first")
        XCTAssertEqual(store.viewMode, .positional)
        XCTAssertTrue(store.hasActiveTimelineScrub)
    }

    func testRetiredAnchorRemovalCannotCancelANewTabletopTimelineScrub() throws {
        let (store, mark, retiredAnchorID) = try placedStoreWithMark()
        store.endTrianglePlacement()
        let originalTime = store.playhead
        XCTAssertTrue(store.beginTimelineScrub())
        XCTAssertTrue(store.previewTimelineScrub(to: 20))
        store.statusMessage = "Current tabletop scrub"

        store.handleSharedPitchAnchorRemoval(retiredAnchorID)

        XCTAssertTrue(store.hasActiveTimelineScrub)
        XCTAssertEqual(store.playhead, 20)
        XCTAssertEqual(store.statusMessage, "Current tabletop scrub")
        XCTAssertEqual(store.marks.first { $0.id == mark.id }, mark)
        XCTAssertEqual(store.triangleLockMode, .visualise)
        XCTAssertNil(store.sharedPitchAnchorID)
        store.cancelTimelineScrub()
        XCTAssertEqual(store.playhead, originalTime)
    }

    func testRetiredAnchorRemovalCannotCancelANewTabletopGeometryPreview() throws {
        let (store, mark, retiredAnchorID) = try placedStoreWithMark()
        store.endTrianglePlacement()
        XCTAssertTrue(store.updateCoachMarkGeometry(
            id: mark.id, start: PitchPoint(x: 3, z: 4),
            end: PitchPoint(x: 7, z: 9), broadcast: false
        ))
        let preview = store.marks
        store.statusMessage = "Current tabletop adjustment"

        store.handleSharedPitchAnchorRemoval(retiredAnchorID)

        XCTAssertTrue(store.hasActiveCoachMarkGeometryPreview)
        XCTAssertEqual(store.marks, preview)
        XCTAssertEqual(store.statusMessage, "Current tabletop adjustment")
        XCTAssertEqual(store.triangleLockMode, .visualise)
        XCTAssertNil(store.sharedPitchAnchorID)
        XCTAssertTrue(store.cancelCoachMarkGeometryPreview(id: mark.id))
        XCTAssertEqual(store.marks.first { $0.id == mark.id }, mark)
    }

    func testPlacementUIExplainsDraftsAndCleansOnlyTheRejectedAttemptAnchor() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        let source = try String(
            contentsOf: root.appendingPathComponent("ReplayXI/Immersive/FootballImmersiveView.swift"),
            encoding: .utf8
        )
        let panelStart = try XCTUnwrap(source.range(of: "private struct PositioningPanel: View")?.lowerBound)
        let panel = String(source[panelStart...])
        XCTAssertTrue(panel.contains("if let reason = store.trianglePlacementInputBlockReason"))
        XCTAssertTrue(panel.contains("Button(\"Cancel annotation\") { store.cancelDrawing() }"))
        XCTAssertTrue(panel.contains(".disabled(!stageIsEnabled(.physical))"))
        XCTAssertTrue(panel.contains(".disabled(!canPlaceLocalStations)"))

        let preflightStart = try XCTUnwrap(panel.range(of: "private func beginPhysicalPreflight()")?.lowerBound)
        let admissionStart = try XCTUnwrap(panel.range(of: "private var canPlaceLocalStations: Bool")?.lowerBound)
        let admissionEnd = try XCTUnwrap(panel.range(of: "private var placementButtonTitle")?.lowerBound)
        XCTAssertTrue(panel[preflightStart..<admissionStart].contains("store.trianglePlacementInputBlockReason == nil"))
        XCTAssertTrue(panel[admissionStart..<admissionEnd].contains("store.trianglePlacementInputBlockReason == nil"))

        let rejectionStart = try XCTUnwrap(panel.range(of: "guard store.activateLocalTrianglePreview(anchorID: anchorID) else")?.lowerBound)
        let selectionStart = try XCTUnwrap(panel.range(of: "sharedSpace.selectSharedPitchAnchor(id: anchorID)")?.lowerBound)
        let rejection = panel[rejectionStart..<selectionStart]
        XCTAssertTrue(rejection.contains("removeLocallyPlacedPitchAnchor(ifMatching: anchorID)"))
        XCTAssertTrue(rejection.contains("placementAttempt.owns(requestID), !Task.isCancelled"))
        XCTAssertTrue(rejection.contains("!store.isClosingImmersive"))
        let cleanup = try XCTUnwrap(rejection.range(of: "await sharedSpace.removeLocallyPlacedPitchAnchor(ifMatching: anchorID)")?.lowerBound)
        let currentHint = try XCTUnwrap(rejection.range(of: "placementError = store.trianglePlacementInputBlockReason")?.lowerBound)
        XCTAssertLessThan(cleanup, currentHint, "Re-read the current edit blocker after asynchronous cleanup")
        XCTAssertTrue(rejection.contains("Placement was cancelled. Try placing stations again."))

        let dragStart = try XCTUnwrap(source.range(of: "private func handleAnnotationDragEnded(")?.lowerBound)
        let dragEnd = try XCTUnwrap(source.range(of: "private func handleAnnotationStrokeChanged(")?.lowerBound)
        let drag = source[dragStart..<dragEnd]
        XCTAssertTrue(drag.contains("store.commitCoachMarkGeometryPreview("))
        XCTAssertFalse(drag.contains("store.updateCoachMarkGeometry("))
    }

    private func makeStore() -> ReplayStore {
        let store = ReplayStore()
        store.prepareForLocalExperience()
        store.selectScenario(id: "triangle-lock", broadcast: false)
        return store
    }

    private func addMark(to store: ReplayStore) throws -> CoachMark {
        store.beginDrawing(.run)
        XCTAssertNil(store.registerPitchTap(PitchPoint(x: 2, z: 3)))
        return try XCTUnwrap(store.registerPitchTap(PitchPoint(x: 6, z: 8)))
    }

    private func placedStoreWithMark() throws -> (ReplayStore, CoachMark, UUID) {
        let store = makeStore()
        let mark = try addMark(to: store)
        let anchorID = UUID()
        store.activateLocalTrianglePreview(anchorID: anchorID)
        return (store, mark, anchorID)
    }
}
