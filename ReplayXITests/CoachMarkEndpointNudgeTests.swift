import XCTest
@testable import ReplayXI

@MainActor
final class CoachMarkEndpointNudgeTests: XCTestCase {
    func testNudgeMovesOnlyRequestedEndpointAndBroadcastsOnce() throws {
        let store = ReplayStore()
        let original = try makeCoachMark(in: store)
        store.setPlaying(true, broadcast: false)
        var broadcasts: [SharedPlaybackSnapshot] = []
        store.onBroadcastSnapshot = { broadcasts.append($0) }

        XCTAssertTrue(
            store.nudgeCoachMarkEndpoint(
                id: original.id,
                endpoint: .start,
                by: PitchPoint(x: 0.5, z: -0.25)
            )
        )

        let adjusted = try XCTUnwrap(store.marks.first { $0.id == original.id })
        XCTAssertEqual(adjusted.start, PitchPoint(x: 2.5, z: 2.75))
        XCTAssertEqual(adjusted.end, original.end)
        XCTAssertEqual(adjusted.kind, original.kind)
        XCTAssertEqual(adjusted.label, original.label)
        XCTAssertEqual(adjusted.revealTime, original.revealTime)
        XCTAssertEqual(adjusted.hideTime, original.hideTime)
        XCTAssertFalse(store.isPlaying)
        XCTAssertEqual(broadcasts.count, 1)
        XCTAssertFalse(broadcasts[0].isPlaying)
        XCTAssertEqual(
            broadcasts[0].marks.first { $0.id == original.id },
            adjusted
        )
    }

    func testNudgeClampsRequestedEndpointToPitchBounds() throws {
        let store = ReplayStore()
        store.beginDrawing(.run)
        XCTAssertNil(store.registerPitchTap(PitchPoint(x: 33.75, z: 52)))
        let original = try XCTUnwrap(
            store.registerPitchTap(PitchPoint(x: 24, z: 42))
        )
        var broadcastCount = 0
        store.onBroadcastSnapshot = { _ in broadcastCount += 1 }

        XCTAssertTrue(
            store.nudgeCoachMarkEndpoint(
                id: original.id,
                endpoint: .start,
                by: PitchPoint(x: 2, z: 3)
            )
        )

        let adjusted = try XCTUnwrap(store.marks.first { $0.id == original.id })
        XCTAssertEqual(
            adjusted.start,
            PitchPoint(x: ReplayStore.pitchHalfWidth, z: ReplayStore.pitchHalfLength)
        )
        XCTAssertEqual(adjusted.end, original.end)
        XCTAssertEqual(broadcastCount, 1)

        XCTAssertFalse(
            store.nudgeCoachMarkEndpoint(
                id: original.id,
                endpoint: .start,
                by: PitchPoint(x: 1, z: 1)
            )
        )
        XCTAssertEqual(store.marks.first { $0.id == original.id }, adjusted)
        XCTAssertEqual(broadcastCount, 1)
    }

    func testNudgeCanMoveEndWithoutChangingStart() throws {
        let store = ReplayStore()
        let original = try makeCoachMark(in: store)
        store.setPlaying(true, broadcast: false)
        var broadcastCount = 0
        store.onBroadcastSnapshot = { _ in broadcastCount += 1 }

        XCTAssertTrue(
            store.nudgeCoachMarkEndpoint(
                id: original.id,
                endpoint: .end,
                by: PitchPoint(x: -0.25, z: 0.5)
            )
        )

        let adjusted = try XCTUnwrap(store.marks.first { $0.id == original.id })
        XCTAssertEqual(adjusted.start, original.start)
        XCTAssertEqual(adjusted.end, PitchPoint(x: 7.75, z: 12.5))
        XCTAssertFalse(store.isPlaying)
        XCTAssertEqual(broadcastCount, 1)
    }

    func testNudgeRejectsInvalidOrUnreadablyShortResultWithoutPublishing() throws {
        let store = ReplayStore()
        let original = try makeCoachMark(in: store)
        store.setPlaying(true, broadcast: false)
        var broadcastCount = 0
        store.onBroadcastSnapshot = { _ in broadcastCount += 1 }

        XCTAssertFalse(
            store.nudgeCoachMarkEndpoint(
                id: original.id,
                endpoint: .end,
                by: PitchPoint(x: .nan, z: 1)
            )
        )
        XCTAssertFalse(
            store.nudgeCoachMarkEndpoint(
                id: original.id,
                endpoint: .start,
                by: .zero
            )
        )
        XCTAssertFalse(
            store.nudgeCoachMarkEndpoint(
                id: original.id,
                endpoint: .end,
                by: PitchPoint(
                    x: original.start.x - original.end.x,
                    z: original.start.z - original.end.z
                )
            )
        )

        XCTAssertEqual(store.marks.first { $0.id == original.id }, original)
        XCTAssertTrue(store.isPlaying)
        XCTAssertEqual(broadcastCount, 0)
    }

    func testNudgePreservesAuthoredFixtureMarksAndPlayerLabels() throws {
        let store = ReplayStore()
        let authored = try XCTUnwrap(store.selectedScenario.coachMarks.first)
        let labelledPlayer = try XCTUnwrap(store.selectedScenario.players.first)
        let playerLabel = try XCTUnwrap(store.labelPlayer(labelledPlayer.id))
        let initialMarks = store.marks
        var broadcastCount = 0
        store.onBroadcastSnapshot = { _ in broadcastCount += 1 }

        XCTAssertFalse(
            store.nudgeCoachMarkEndpoint(
                id: authored.id,
                endpoint: .start,
                by: PitchPoint(x: 0.5, z: 0)
            )
        )
        XCTAssertFalse(
            store.nudgeCoachMarkEndpoint(
                id: playerLabel.id,
                endpoint: .end,
                by: PitchPoint(x: 0, z: 0.5)
            )
        )

        XCTAssertEqual(store.marks, initialMarks)
        XCTAssertEqual(broadcastCount, 0)
    }

    func testJoinedPlayerCannotNudgeCoachAnnotation() throws {
        let store = ReplayStore()
        let original = try makeCoachMark(in: store)
        let initialMarks = store.marks
        var broadcastCount = 0
        store.onBroadcastSnapshot = { _ in broadcastCount += 1 }
        store.localRole = .player
        store.setCollaborationActive(true)

        XCTAssertFalse(
            store.nudgeCoachMarkEndpoint(
                id: original.id,
                endpoint: .start,
                by: PitchPoint(x: 0.5, z: 0)
            )
        )

        XCTAssertEqual(store.marks, initialMarks)
        XCTAssertEqual(broadcastCount, 0)
    }

    func testNudgeCannotCommitAnUnfinishedGeometryPreview() throws {
        let store = ReplayStore()
        let original = try makeCoachMark(in: store)
        XCTAssertTrue(
            store.updateCoachMarkGeometry(
                id: original.id,
                start: PitchPoint(x: -2, z: 1),
                end: PitchPoint(x: 9, z: 14),
                broadcast: false
            )
        )
        let preview = try XCTUnwrap(store.marks.first { $0.id == original.id })
        var broadcastCount = 0
        store.onBroadcastSnapshot = { _ in broadcastCount += 1 }

        XCTAssertFalse(
            store.nudgeCoachMarkEndpoint(
                id: original.id,
                endpoint: .end,
                by: PitchPoint(x: 0.5, z: 0)
            )
        )

        XCTAssertEqual(store.marks.first { $0.id == original.id }, preview)
        XCTAssertEqual(broadcastCount, 0)
        XCTAssertEqual(
            store.makeSnapshot().marks.first { $0.id == original.id },
            original
        )
    }

    private func makeCoachMark(in store: ReplayStore) throws -> CoachMark {
        store.seek(to: 6, broadcast: false)
        store.beginDrawing(.pass)
        XCTAssertNil(store.registerPitchTap(PitchPoint(x: 2, z: 3)))
        return try XCTUnwrap(
            store.registerPitchTap(PitchPoint(x: 8, z: 12))
        )
    }
}
