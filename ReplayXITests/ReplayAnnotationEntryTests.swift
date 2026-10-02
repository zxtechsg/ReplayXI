import XCTest
@testable import ReplayXI

@MainActor
final class ReplayAnnotationEntryTests: XCTestCase {
    func testEntryIsConsumedOnceByItsRoomAndStudy() {
        let entry = ReplayAnnotationEntrySession()
        let roomID = UUID()
        entry.request(roomID: roomID, scenarioID: "match")
        XCTAssertFalse(entry.consume(roomID: UUID(), scenarioID: "match"))
        XCTAssertNotNil(entry.pending)
        XCTAssertTrue(entry.consume(roomID: roomID, scenarioID: "match"))
        XCTAssertNil(entry.pending)
        XCTAssertFalse(entry.consume(roomID: roomID, scenarioID: "match"))
    }

    func testChangedStudyAndFailedRoomDiscardTheirRequest() {
        let entry = ReplayAnnotationEntrySession()
        let roomID = UUID()
        entry.request(roomID: roomID, scenarioID: "match")
        XCTAssertFalse(entry.consume(roomID: roomID, scenarioID: "another-match"))
        XCTAssertNil(entry.pending)
        entry.request(roomID: roomID, scenarioID: "match")
        entry.cancel(roomID: roomID)
        XCTAssertNil(entry.pending)
    }

    func testLateFailedEntryCannotClearNewRoomRequest() throws {
        let entry = ReplayAnnotationEntrySession()
        let oldRoom = UUID(), newRoom = UUID()
        entry.request(roomID: oldRoom, scenarioID: "match")
        entry.request(roomID: newRoom, scenarioID: "next-match")
        let pending = try XCTUnwrap(entry.pending)
        entry.cancel(roomID: oldRoom)
        XCTAssertFalse(entry.consume(roomID: oldRoom, scenarioID: "match"))
        XCTAssertEqual(entry.pending, pending)
        XCTAssertTrue(entry.consume(roomID: newRoom, scenarioID: "next-match"))
    }

    func testEntryAdmissionProtectsTimelineDrawingGeometryAndTimingOwners() throws {
        let store = ReplayStore(scenarios: FootballReferenceScenarios.all)
        store.seek(to: 2)
        store.setPlaying(true)
        let before = store.makeSavedReviewState()
        XCTAssertNil(ReplayAnnotationEntryPolicy.blockReason(in: store))
        XCTAssertTrue(store.isPlaying)
        XCTAssertEqual(store.makeSavedReviewState(), before)

        XCTAssertTrue(store.beginTimelineScrub())
        XCTAssertNotNil(ReplayAnnotationEntryPolicy.blockReason(in: store))
        store.cancelTimelineScrub()
        store.beginDrawing(.pass)
        XCTAssertNotNil(ReplayAnnotationEntryPolicy.blockReason(in: store))
        _ = store.registerPitchTap(.init(x: 0, z: 0))
        let mark = try XCTUnwrap(store.registerPitchTap(.init(x: 8, z: 10)))
        store.cancelDrawing()
        XCTAssertTrue(store.updateCoachMarkGeometry(id: mark.id, start: .init(x: 1, z: 1),
            end: .init(x: 9, z: 11), broadcast: false))
        XCTAssertNotNil(ReplayAnnotationEntryPolicy.blockReason(in: store))
        XCTAssertTrue(store.cancelCoachMarkGeometryPreview(id: mark.id))
        XCTAssertTrue(store.setAnnotationTimingDraftPending(id: mark.id, isPending: true))
        XCTAssertNotNil(ReplayAnnotationEntryPolicy.blockReason(in: store))
        XCTAssertTrue(store.setAnnotationTimingDraftPending(id: mark.id, isPending: false))
        XCTAssertNil(ReplayAnnotationEntryPolicy.blockReason(in: store))
        store.localRole = .player
        XCTAssertNotNil(ReplayAnnotationEntryPolicy.blockReason(in: store))
        XCTAssertNil(ReplayAnnotationEntryPolicy.navigationBlockReason(in: store))
    }

    func testBothModesPreservePOVTimeAndSavedMarksThroughAnnotationEntry() throws {
        let exercise = try XCTUnwrap(DemoScenarios.all.first)
        let match = try XCTUnwrap(FootballReferenceScenarios.all.first {
            ReplayAppMode(scenario: $0) == .matchReplay
        })
        for scenario in [exercise, match] {
            let store = ReplayStore(scenarios: [scenario])
            store.seek(to: 2.5)
            store.openLocalPlayerPOV(scenario.players[1].id)
            store.beginDrawing(.arc)
            _ = store.registerPitchTap(.init(x: 0, z: 0))
            let mark = try XCTUnwrap(store.registerPitchTap(.init(x: 8, z: 10)))
            store.cancelDrawing()
            let before = store.makeSavedReviewState()
            XCTAssertNil(ReplayAnnotationEntryPolicy.blockReason(in: store))

            let roomID = try XCTUnwrap(store.beginImmersiveOpen())
            let entry = ReplayAnnotationEntrySession()
            entry.request(roomID: roomID, scenarioID: scenario.id)
            XCTAssertNotNil(ReplayAnnotationEntryPolicy.blockReason(in: store))
            XCTAssertEqual(store.makeSavedReviewState(), before)
            XCTAssertFalse(store.isPlaying)
            XCTAssertFalse(store.isDrawing)
            XCTAssertTrue(entry.consume(roomID: roomID, scenarioID: scenario.id))
            XCTAssertTrue(store.completeImmersiveOpen(roomID, opened: false))
            XCTAssertNil(ReplayAnnotationEntryPolicy.blockReason(in: store))

            XCTAssertTrue(store.saveReview(named: "Annotated \(scenario.title)"))
            let review = try XCTUnwrap(store.savedReviews.first)
            XCTAssertTrue(store.removeCoachMark(id: mark.id))
            XCTAssertTrue(store.restoreReview(review))
            XCTAssertEqual(store.makeSavedReviewState(), before)
            XCTAssertTrue(store.marks.contains(mark))
        }
    }
}
