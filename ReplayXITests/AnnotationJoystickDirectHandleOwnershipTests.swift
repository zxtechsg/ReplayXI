import XCTest
@testable import ReplayXI

@MainActor
final class AnnotationJoystickDirectHandleOwnershipTests: XCTestCase {
    func testJoystickHelperRejectsDirectGeometryButKeepsItsMatchingOwner() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        let source = try String(contentsOf: root.appendingPathComponent(
            "ReplayXI/Immersive/FootballImmersiveView.swift"), encoding: .utf8)
        let deck = try XCTUnwrap(source.range(of: "private struct ImmersiveControlDeck:")?.lowerBound)
        let start = try XCTUnwrap(source.range(of: "private func annotationJoystickIsEnabled(",
            range: deck..<source.endIndex)?.lowerBound)
        let end = try XCTUnwrap(source.range(of: "private func annotationEndPointAccessibilityTarget",
            range: start..<source.endIndex)?.lowerBound)
        let helper = String(source[start..<end])
        XCTAssertTrue(helper.contains("guard !store.hasActiveTimelineScrub else { return false }"))
        XCTAssertTrue(helper.contains("guard let owner = store.activeCoachMarkEndpointPreviewOwner"))
        XCTAssertTrue(helper.contains("return !store.hasActiveCoachMarkGeometryPreview"),
                      "No joystick owner is not enough: a world handle can own the geometry")
        XCTAssertTrue(helper.contains("return owner == CoachMarkEndpointPreviewOwner(markID: markID, endpoint: endpoint)"),
                      "Do not disable the joystick that owns the active endpoint preview")
    }

    func testDirectHandleRejectsBothJoysticksWithoutLosingItsOwnCommitOrCancel() throws {
        for commits in [false, true] {
            let (store, mark) = try makeMark()
            let endpoint = PitchPoint(x: mark.end.x + 0.5, z: mark.end.z + 0.25)
            XCTAssertTrue(store.updateCoachMarkGeometry(id: mark.id, start: mark.start,
                                                       end: endpoint, broadcast: false))
            let preview = store.marks
            let snapshot = store.makeSnapshot()
            let undo = store.annotationUndoTitle
            XCTAssertTrue(store.hasActiveCoachMarkGeometryPreview)
            XCTAssertFalse(store.hasActiveCoachMarkEndpointPreview)
            XCTAssertNil(store.activeCoachMarkEndpointPreviewOwner)

            for target in [CoachMarkEndpoint.start, .end] {
                let blockedID = UUID()
                XCTAssertNil(store.previewCoachMarkEndpoint(id: mark.id, endpoint: target,
                    gestureID: blockedID, cumulativeDelta: PitchPoint(x: 0.25, z: 0)))
                // A rejected joystick's later lift/cancel must not steal the
                // direct handle's independent geometry transaction.
                XCTAssertNil(store.commitCoachMarkEndpointPreview(id: mark.id, gestureID: blockedID))
                XCTAssertFalse(store.cancelCoachMarkEndpointPreview(id: mark.id, gestureID: blockedID))
                XCTAssertEqual(store.marks, preview)
                XCTAssertEqual(store.makeSnapshot(), snapshot)
                XCTAssertEqual(store.annotationUndoTitle, undo)
                XCTAssertTrue(store.hasActiveCoachMarkGeometryPreview)
                XCTAssertNil(store.activeCoachMarkEndpointPreviewOwner)
            }

            if commits {
                XCTAssertTrue(store.commitCoachMarkGeometryPreview(id: mark.id,
                    start: mark.start, end: endpoint))
                XCTAssertEqual(store.marks.first { $0.id == mark.id }?.end, endpoint)
                XCTAssertTrue(store.undoAnnotationEdit())
            } else {
                XCTAssertTrue(store.cancelCoachMarkGeometryPreview(id: mark.id))
            }
            XCTAssertFalse(store.hasActiveCoachMarkGeometryPreview)
            XCTAssertEqual(store.marks.first { $0.id == mark.id }, mark)
        }
    }

    func testMatchingJoystickContinuesWhileOtherEndpointIsRejected() throws {
        for commits in [false, true] {
            let (store, mark) = try makeMark()
            let gestureID = UUID()
            let owner = CoachMarkEndpointPreviewOwner(markID: mark.id, endpoint: .start)
            XCTAssertNotNil(store.previewCoachMarkEndpoint(id: mark.id, endpoint: .start,
                gestureID: gestureID, cumulativeDelta: PitchPoint(x: 0.25, z: 0)))
            XCTAssertTrue(store.hasActiveCoachMarkGeometryPreview)
            XCTAssertTrue(store.hasActiveCoachMarkEndpointPreview)
            XCTAssertEqual(store.activeCoachMarkEndpointPreviewOwner, owner)
            let firstPreview = store.marks
            XCTAssertNil(store.previewCoachMarkEndpoint(id: mark.id, endpoint: .end,
                gestureID: UUID(), cumulativeDelta: PitchPoint(x: 0.25, z: 0)))
            XCTAssertEqual(store.marks, firstPreview)
            XCTAssertEqual(store.activeCoachMarkEndpointPreviewOwner, owner)

            let delta = PitchPoint(x: 0.75, z: 0.25)
            let continued = try XCTUnwrap(store.previewCoachMarkEndpoint(id: mark.id, endpoint: .start,
                gestureID: gestureID, cumulativeDelta: delta))
            XCTAssertEqual(continued.appliedDelta, delta)
            XCTAssertTrue(continued.hasActiveTransaction)
            XCTAssertEqual(store.activeCoachMarkEndpointPreviewOwner, owner)
            if commits {
                XCTAssertEqual(store.commitCoachMarkEndpointPreview(id: mark.id, gestureID: gestureID), delta)
                XCTAssertTrue(store.undoAnnotationEdit())
            } else {
                XCTAssertTrue(store.cancelCoachMarkEndpointPreview(id: mark.id, gestureID: gestureID))
            }
            XCTAssertFalse(store.hasActiveCoachMarkGeometryPreview)
            XCTAssertNil(store.activeCoachMarkEndpointPreviewOwner)
            XCTAssertEqual(store.marks.first { $0.id == mark.id }, mark)
        }
    }

    func testTimelineOwnershipAndNormalJoystickEntryStaySeparate() throws {
        for commits in [false, true] {
            let (store, mark) = try makeMark()
            store.setPlaying(true, broadcast: false)
            XCTAssertTrue(store.beginTimelineScrub())
            XCTAssertTrue(store.previewTimelineScrub(to: 12))
            XCTAssertFalse(store.hasActiveCoachMarkGeometryPreview)
            XCTAssertNil(store.activeCoachMarkEndpointPreviewOwner)
            XCTAssertNil(store.previewCoachMarkEndpoint(id: mark.id, endpoint: .end,
                gestureID: UUID(), cumulativeDelta: PitchPoint(x: 0.25, z: 0)))
            XCTAssertTrue(store.hasActiveTimelineScrub)
            XCTAssertEqual(store.playhead, 12)
            if commits {
                XCTAssertTrue(store.commitTimelineScrub(to: 12))
            } else {
                store.cancelTimelineScrub()
                XCTAssertEqual(store.playhead, 5)
            }
            XCTAssertTrue(store.isPlaying)
            XCTAssertFalse(store.hasActiveTimelineScrub)
            let gestureID = UUID()
            XCTAssertNotNil(store.previewCoachMarkEndpoint(id: mark.id, endpoint: .end,
                gestureID: gestureID, cumulativeDelta: PitchPoint(x: 0.25, z: 0)))
            XCTAssertTrue(store.cancelCoachMarkEndpointPreview(id: mark.id, gestureID: gestureID))
            XCTAssertEqual(store.marks.first { $0.id == mark.id }, mark)
        }
    }

    private func makeMark() throws -> (ReplayStore, CoachMark) {
        let store = ReplayStore()
        store.prepareForLocalExperience()
        XCTAssertFalse(store.reviewLibrary.usesDisk)
        store.seek(to: 5, broadcast: false)
        store.beginDrawing(.pass)
        XCTAssertNil(store.registerPitchTap(PitchPoint(x: 2, z: 3)))
        let created = try XCTUnwrap(store.registerPitchTap(PitchPoint(x: 8, z: 12)))
        if created.followsPlayerTracks {
            XCTAssertTrue(store.setCoachMarkTracking(id: created.id, playerID: nil))
        }
        return (store, try XCTUnwrap(store.marks.first { $0.id == created.id }))
    }
}
