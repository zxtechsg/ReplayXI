import XCTest
@testable import ReplayXI

final class PlaybackAnnotationEligibilityTests: XCTestCase {
    func testHiddenRecentMarksCannotConsumeAnOlderVisibleMarksBudget() {
        let hidden = mark(.danger, time: 8)
        let visible = (0..<4).map { mark(.space, time: Double($0)) }
        let marks = [hidden] + visible
        let ids = admitted(marks, selectedID: nil) { $0.id != hidden.id }
        XCTAssertEqual(ids, Set(visible.map(\.id)))
        XCTAssertEqual(PlaybackSceneRenderBudget.estimatedAnnotationDraws(for: marks, visibleIDs: ids), 16)
    }

    func testHiddenSelectionDoesNotReserveOverlayDrawsOrBypassEligibility() {
        let hidden = mark(.danger, time: 8)
        let visible = (0..<4).map { mark(.space, time: Double($0)) }
        let ids = admitted([hidden] + visible, selectedID: hidden.id) { $0.id != hidden.id }
        XCTAssertEqual(ids, Set(visible.map(\.id)))
        XCTAssertFalse(ids.contains(hidden.id))
    }

    func testMissingOrExpiredSelectionDoesNotStarveVisibleHistory() {
        let visible = (0..<4).map { mark(.space, time: Double($0)) }
        XCTAssertEqual(admitted(visible, selectedID: UUID()), Set(visible.map(\.id)))
        let expired = CoachMark(kind: .run, start: .zero, end: PitchPoint(x: 2, z: 4),
                                label: "Expired", revealTime: 0, hideTime: 1)
        let marks = [expired] + visible
        XCTAssertEqual(PlaybackSceneRenderBudget.visibleAnnotationIDs(
            in: marks, priorityIndices: PlaybackSceneRenderBudget.priorityIndices(for: marks),
            at: 10, selectedID: expired.id, selectedIsEditable: false,
            decisionReviewIsVisible: false
        ), Set(visible.map(\.id)))
    }

    func testFullyHiddenPresentationHasNoAdmittedGeometry() {
        let marks = CoachMarkKind.allCases.map { mark($0, time: 0) }
        XCTAssertTrue(admitted(marks, selectedID: marks.first?.id) { _ in false }.isEmpty)
    }

    func testVisibleSelectionStillHasPriorityWithinTheExistingEnvelope() {
        let selected = mark(.danger, time: 0)
        let marks = [selected] + (1..<12).map { mark(.space, time: Double($0)) }
        let ids = admitted(marks, selectedID: selected.id)
        XCTAssertTrue(ids.contains(selected.id))
        XCTAssertLessThanOrEqual(
            PlaybackSceneRenderBudget.estimatedAnnotationDraws(for: marks, visibleIDs: ids)
                + PlaybackSceneRenderBudget.selectedEditableOverlayDraws,
            PlaybackSceneRenderBudget.selectedAnnotationSystemDrawLimit
        )
    }

    private func mark(_ kind: CoachMarkKind, time: TimeInterval) -> CoachMark {
        CoachMark(kind: kind, start: .zero, end: PitchPoint(x: 2, z: 4),
                  label: kind.title, revealTime: time)
    }

    private func admitted(
        _ marks: [CoachMark], selectedID: UUID?,
        isEligible: (CoachMark) -> Bool = { _ in true }
    ) -> Set<UUID> {
        PlaybackSceneRenderBudget.visibleAnnotationIDs(
            in: marks, priorityIndices: PlaybackSceneRenderBudget.priorityIndices(for: marks),
            at: 15, selectedID: selectedID, selectedIsEditable: true,
            decisionReviewIsVisible: false, isEligible: isEligible
        )
    }
}
