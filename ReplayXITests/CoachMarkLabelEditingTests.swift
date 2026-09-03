import XCTest
@testable import ReplayXI

@MainActor
final class CoachMarkLabelEditingTests: XCTestCase {
    func testSuggestedLabelsAreConciseUniqueAndRelevantToSpatialKinds() {
        for kind in CoachMarkKind.allCases where kind.requiresTwoPitchPoints {
            XCTAssertFalse(kind.suggestedLabels.isEmpty, kind.rawValue)
            XCTAssertEqual(Set(kind.suggestedLabels).count, kind.suggestedLabels.count, kind.rawValue)
            XCTAssertTrue(
                kind.suggestedLabels.allSatisfy {
                    !$0.isEmpty && $0.count <= ReplayStore.maximumCoachMarkLabelLength
                },
                kind.rawValue
            )
        }
        XCTAssertTrue(CoachMarkKind.playerLabel.suggestedLabels.isEmpty)
        XCTAssertTrue(CoachMarkKind.run.suggestedLabels.contains("Overlap"))
        XCTAssertTrue(CoachMarkKind.pass.suggestedLabels.contains("Switch play"))
        XCTAssertTrue(CoachMarkKind.danger.suggestedLabels.contains("Press trigger"))
    }

    func testCoachCanRelabelCreatedAnnotationAndBroadcastsExactlyOnce() throws {
        let store = ReplayStore()
        store.seek(to: 7, broadcast: false)
        store.beginDrawing(.run)
        XCTAssertNil(store.registerPitchTap(PitchPoint(x: 1, z: 3)))
        let original = try XCTUnwrap(store.registerPitchTap(PitchPoint(x: 4, z: 12)))

        var snapshots: [SharedPlaybackSnapshot] = []
        store.onBroadcastSnapshot = { snapshots.append($0) }

        XCTAssertTrue(store.updateCoachMarkLabel(id: original.id, label: "  Third-player\nrun  "))
        let edited = try XCTUnwrap(store.marks.first { $0.id == original.id })
        XCTAssertEqual(edited.label, "Third-player run")
        XCTAssertEqual(edited.start, original.start)
        XCTAssertEqual(edited.end, original.end)
        XCTAssertEqual(edited.revealTime, original.revealTime)
        XCTAssertEqual(edited.hideTime, original.hideTime)
        XCTAssertEqual(snapshots.count, 1)
        XCTAssertEqual(snapshots[0].marks.first { $0.id == original.id }?.label, "Third-player run")
    }

    func testRelabelRejectsInvalidNoOpPlayerAndFixtureMutations() throws {
        let store = ReplayStore()
        store.beginDrawing(.pass)
        XCTAssertNil(store.registerPitchTap(PitchPoint(x: 2, z: 3)))
        let mark = try XCTUnwrap(store.registerPitchTap(PitchPoint(x: 8, z: 14)))
        var broadcastCount = 0
        store.onBroadcastSnapshot = { _ in broadcastCount += 1 }

        XCTAssertFalse(store.updateCoachMarkLabel(id: mark.id, label: mark.label))
        XCTAssertFalse(store.updateCoachMarkLabel(id: mark.id, label: " \n \t "))
        XCTAssertFalse(
            store.updateCoachMarkLabel(
                id: mark.id,
                label: String(repeating: "X", count: ReplayStore.maximumCoachMarkLabelLength + 1)
            )
        )
        XCTAssertFalse(
            store.updateCoachMarkLabel(
                id: try XCTUnwrap(store.selectedScenario.coachMarks.first?.id),
                label: "Do not replace fixture"
            )
        )
        XCTAssertEqual(broadcastCount, 0)

        store.localRole = .player
        XCTAssertFalse(store.updateCoachMarkLabel(id: mark.id, label: "Switch play"))
        XCTAssertEqual(store.marks.first { $0.id == mark.id }?.label, mark.label)
        XCTAssertEqual(broadcastCount, 0)
    }

    func testJoinedPlayerAnnotationReviewAtomicallyLeavesCoachFollow() {
        let store = ReplayStore()
        store.localRole = .player
        store.setCollaborationActive(true)
        store.setPlaying(true, broadcast: false)
        XCTAssertTrue(store.followsCoach)
        XCTAssertFalse(store.isLocallyPaused)

        XCTAssertTrue(store.beginLocalReview(at: 12.4))

        XCTAssertEqual(store.playhead, 12.4, accuracy: 0.000_1)
        XCTAssertFalse(store.isPlaying)
        XCTAssertFalse(store.followsCoach)
        XCTAssertTrue(store.isLocallyPaused)
        XCTAssertEqual(store.statusMessage, "Local comfort review — rejoin when ready")
    }

    func testInvalidLocalReviewTimeDoesNotMutateFollowingPlayer() {
        let store = ReplayStore()
        store.localRole = .player
        store.setCollaborationActive(true)
        store.setPlaying(true, broadcast: false)
        let originalTime = store.playhead

        XCTAssertFalse(store.beginLocalReview(at: .nan))

        XCTAssertEqual(store.playhead, originalTime)
        XCTAssertTrue(store.isPlaying)
        XCTAssertTrue(store.followsCoach)
        XCTAssertFalse(store.isLocallyPaused)
    }
}
