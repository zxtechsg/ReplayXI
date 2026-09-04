import XCTest
@testable import ReplayXI

@MainActor
final class CoachMarkGeometryTransactionTests: XCTestCase {
    func testTooShortPreviewIsRejectedWithoutStartingOrPausingTransaction() throws {
        let (store, mark) = try makePlayingJoinedCoach()
        var broadcasts: [SharedPlaybackSnapshot] = []
        store.onBroadcastSnapshot = { broadcasts.append($0) }
        let geometryBefore = try geometry(of: mark.id, in: store)

        XCTAssertFalse(
            store.updateCoachMarkGeometry(
                id: mark.id,
                start: PitchPoint(x: 4, z: 6),
                end: PitchPoint(x: 4.2, z: 6.1),
                broadcast: false
            )
        )

        XCTAssertEqual(try geometry(of: mark.id, in: store), geometryBefore)
        XCTAssertTrue(store.isPlaying)
        XCTAssertTrue(broadcasts.isEmpty)
        XCTAssertFalse(store.cancelCoachMarkGeometryPreview(id: mark.id))
    }

    func testInvalidCommitRollsBackWithoutCommitSnapshotAndKeepsSquadPaused() throws {
        let (store, mark) = try makePlayingJoinedCoach()
        var broadcasts: [SharedPlaybackSnapshot] = []
        store.onBroadcastSnapshot = { broadcasts.append($0) }
        let geometryBefore = try geometry(of: mark.id, in: store)
        let previewStart = PitchPoint(x: -5, z: 4)
        let previewEnd = PitchPoint(x: 3, z: 17)

        XCTAssertTrue(
            store.updateCoachMarkGeometry(
                id: mark.id,
                start: previewStart,
                end: previewEnd,
                broadcast: false
            )
        )
        XCTAssertFalse(store.isPlaying)
        XCTAssertEqual(broadcasts.count, 1)
        XCTAssertFalse(try XCTUnwrap(broadcasts.last).isPlaying)
        XCTAssertEqual(
            try geometry(of: mark.id, in: XCTUnwrap(broadcasts.last)),
            geometryBefore
        )

        XCTAssertFalse(
            store.updateCoachMarkGeometry(
                id: mark.id,
                start: previewEnd,
                end: previewEnd,
                broadcast: true
            )
        )

        XCTAssertEqual(try geometry(of: mark.id, in: store), geometryBefore)
        XCTAssertEqual(broadcasts.count, 1)
        XCTAssertFalse(store.isPlaying)
        XCTAssertFalse(try XCTUnwrap(broadcasts.last).isPlaying)
        XCTAssertFalse(store.cancelCoachMarkGeometryPreview(id: mark.id))
    }

    func testCancelledPreviewRestoresGeometryWithoutExtraSnapshotAndKeepsSquadPaused() throws {
        let (store, mark) = try makePlayingJoinedCoach()
        var broadcasts: [SharedPlaybackSnapshot] = []
        store.onBroadcastSnapshot = { broadcasts.append($0) }
        let geometryBefore = try geometry(of: mark.id, in: store)

        XCTAssertTrue(
            store.updateCoachMarkGeometry(
                id: mark.id,
                start: PitchPoint(x: -4, z: 5),
                end: PitchPoint(x: 5, z: 19),
                broadcast: false
            )
        )
        XCTAssertEqual(broadcasts.count, 1)
        XCTAssertFalse(store.isPlaying)
        XCTAssertFalse(try XCTUnwrap(broadcasts.last).isPlaying)

        XCTAssertTrue(store.cancelCoachMarkGeometryPreview(id: mark.id))

        XCTAssertEqual(try geometry(of: mark.id, in: store), geometryBefore)
        XCTAssertEqual(broadcasts.count, 1)
        XCTAssertFalse(store.isPlaying)
        XCTAssertFalse(try XCTUnwrap(broadcasts.last).isPlaying)
    }

    func testValidCommitPublishesExactlyOneGeometrySnapshotAfterSharedPause() throws {
        let (store, mark) = try makePlayingJoinedCoach()
        var broadcasts: [SharedPlaybackSnapshot] = []
        store.onBroadcastSnapshot = { broadcasts.append($0) }
        let geometryBefore = try geometry(of: mark.id, in: store)
        let previewStart = PitchPoint(x: -4, z: 5)
        let previewEnd = PitchPoint(x: 5, z: 19)
        let finalEnd = PitchPoint(x: 7, z: 21)

        XCTAssertTrue(
            store.updateCoachMarkGeometry(
                id: mark.id,
                start: previewStart,
                end: previewEnd,
                broadcast: false
            )
        )
        XCTAssertEqual(broadcasts.count, 1)
        XCTAssertEqual(
            try geometry(of: mark.id, in: XCTUnwrap(broadcasts.last)),
            geometryBefore
        )

        XCTAssertTrue(
            store.updateCoachMarkGeometry(
                id: mark.id,
                start: previewStart,
                end: finalEnd,
                broadcast: false
            )
        )
        XCTAssertEqual(broadcasts.count, 1)

        XCTAssertTrue(
            store.updateCoachMarkGeometry(
                id: mark.id,
                start: previewStart,
                end: finalEnd,
                broadcast: true
            )
        )

        let expected = MarkGeometry(start: previewStart, end: finalEnd)
        XCTAssertEqual(try geometry(of: mark.id, in: store), expected)
        XCTAssertEqual(broadcasts.count, 2)
        XCTAssertEqual(
            try geometry(of: mark.id, in: XCTUnwrap(broadcasts.last)),
            expected
        )
        XCTAssertFalse(store.isPlaying)
        XCTAssertFalse(try XCTUnwrap(broadcasts.last).isPlaying)
        XCTAssertFalse(store.cancelCoachMarkGeometryPreview(id: mark.id))
    }

    private struct MarkGeometry: Equatable {
        let start: PitchPoint
        let end: PitchPoint
    }

    private func makePlayingJoinedCoach() throws -> (ReplayStore, CoachMark) {
        let store = ReplayStore()
        store.seek(to: 6, broadcast: false)
        store.beginDrawing(.run)
        XCTAssertNil(store.registerPitchTap(PitchPoint(x: 1, z: 2)))
        let mark = try XCTUnwrap(
            store.registerPitchTap(PitchPoint(x: 7, z: 11))
        )
        store.setCollaborationActive(true)
        store.setPlaying(true, broadcast: false)
        return (store, mark)
    }

    private func geometry(of id: UUID, in store: ReplayStore) throws -> MarkGeometry {
        let mark = try XCTUnwrap(store.marks.first { $0.id == id })
        return MarkGeometry(start: mark.start, end: mark.end)
    }

    private func geometry(
        of id: UUID,
        in snapshot: SharedPlaybackSnapshot
    ) throws -> MarkGeometry {
        let mark = try XCTUnwrap(snapshot.marks.first { $0.id == id })
        return MarkGeometry(start: mark.start, end: mark.end)
    }
}
