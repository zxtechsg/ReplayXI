import XCTest
@testable import ReplayXI

@MainActor
final class DashboardTimelineScrubControllerTests: XCTestCase {
    func testOwnedDragStaysEnabledCommitsFinalSampleAndRestoresPlayback() {
        let (store, controller) = fixture()
        XCTAssertTrue(controller.isEnabled(in: store))
        XCTAssertTrue(controller.begin(in: store))
        XCTAssertTrue(controller.begin(in: store), "Repeated editing=true is idempotent for its own drag")
        XCTAssertTrue(controller.isEnabled(in: store))
        XCTAssertTrue(controller.valueChanged(to: 9, in: store))
        XCTAssertTrue(controller.valueChanged(to: 11, in: store))
        XCTAssertEqual(store.makeSavedReviewState().playhead, 5, "Preview stays out of saves")
        XCTAssertTrue(controller.finish(in: store))
        XCTAssertEqual(store.playhead, 11)
        XCTAssertTrue(store.isPlaying)
        XCTAssertFalse(store.hasActiveTimelineScrub)
        XCTAssertNil(controller.storeScrubID)
        XCTAssertTrue(store.flushReviewAutosave())
        XCTAssertEqual(store.autosavedReview?.state.playhead, 11)
    }

    func testSetterBeforeBeginTapIsStagedWithoutSeekingThenCommitted() {
        let (store, controller) = fixture()
        XCTAssertFalse(controller.valueChanged(to: 7, in: store))
        XCTAssertEqual(store.playhead, 5, "A binding setter alone is not permission to seek")
        XCTAssertTrue(controller.begin(in: store))
        XCTAssertEqual(store.playhead, 7, "A same-turn first sample cannot be swallowed")
        XCTAssertEqual(store.makeSavedReviewState().playhead, 5)
        XCTAssertTrue(controller.finish(in: store))
        XCTAssertEqual(store.playhead, 7)
    }

    func testUnusedPreBeginSampleExpiresBeforeLaterGesture() async throws {
        let (store, controller) = fixture()
        XCTAssertFalse(controller.valueChanged(to: 15, in: store))
        try await Task.sleep(for: .milliseconds(20))
        XCTAssertEqual(store.playhead, 5)
        XCTAssertTrue(controller.begin(in: store))
        XCTAssertEqual(store.playhead, 5, "A delayed callback cannot seed a later gesture")
        XCTAssertTrue(controller.valueChanged(to: 8, in: store))
        XCTAssertTrue(controller.finish(in: store))
        XCTAssertEqual(store.playhead, 8)
    }

    func testForeignScrubBlocksSliderAndCannotBeAdopted() throws {
        let (store, controller) = fixture()
        XCTAssertTrue(store.beginTimelineScrub())
        let foreignID = try XCTUnwrap(store.activeTimelineScrubID)
        XCTAssertTrue(store.previewTimelineScrub(to: 9))
        XCTAssertFalse(controller.isEnabled(in: store))
        XCTAssertFalse(controller.begin(in: store))
        XCTAssertFalse(controller.valueChanged(to: 15, in: store))
        XCTAssertFalse(controller.finish(in: store))
        XCTAssertEqual(store.activeTimelineScrubID, foreignID)
        XCTAssertEqual(store.playhead, 9)
        XCTAssertTrue(store.commitTimelineScrub(to: 10))
        XCTAssertTrue(controller.isEnabled(in: store))
    }

    func testDisappearingUnownedDashboardCannotCancelImmersiveScrub() throws {
        let (store, controller) = fixture()
        let rail = PlaybackTimelineScrubController()
        XCTAssertTrue(rail.preview(in: store, startLocation: 400, railWidth: 1000, translation: .zero))
        let owner = try XCTUnwrap(store.activeTimelineScrubID)
        let preview = store.playhead
        controller.disappear(in: store)
        XCTAssertEqual(store.activeTimelineScrubID, owner)
        XCTAssertEqual(store.playhead, preview)
        XCTAssertFalse(controller.isEnabled(in: store))
        XCTAssertTrue(rail.finish(in: store, railWidth: 1000, translation: .zero))
    }

    func testOwnedDisappearanceRollsBackAndIgnoresLateCallbacks() {
        let (store, controller) = fixture()
        XCTAssertTrue(controller.begin(in: store))
        XCTAssertTrue(controller.valueChanged(to: 12, in: store))
        controller.disappear(in: store)
        XCTAssertEqual(store.playhead, 5)
        XCTAssertTrue(store.isPlaying)
        XCTAssertFalse(controller.valueChanged(to: 15, in: store))
        XCTAssertFalse(controller.begin(in: store))
        XCTAssertFalse(controller.finish(in: store))
        XCTAssertFalse(controller.adjustDiscrete(direction: 1, in: store))
        XCTAssertEqual(store.playhead, 5)
        XCTAssertTrue(store.flushReviewAutosave())
        XCTAssertEqual(store.autosavedReview?.state.playhead, 5)
        controller.appear()
        XCTAssertTrue(controller.begin(in: store))
        XCTAssertTrue(controller.valueChanged(to: 8, in: store))
        XCTAssertTrue(controller.finish(in: store))
        XCTAssertEqual(store.playhead, 8)
    }

    func testCancelledOldCallbacksCannotAdoptOrCancelReplacementGeneration() throws {
        let (store, old) = fixture()
        XCTAssertTrue(old.begin(in: store))
        XCTAssertTrue(old.valueChanged(to: 12, in: store))
        store.cancelTimelineScrub()
        XCTAssertTrue(store.beginTimelineScrub())
        let replacementID = try XCTUnwrap(store.activeTimelineScrubID)
        XCTAssertTrue(store.previewTimelineScrub(to: 9))
        XCTAssertFalse(old.isEnabled(in: store))
        XCTAssertFalse(old.begin(in: store))
        XCTAssertFalse(old.valueChanged(to: 15, in: store))
        XCTAssertFalse(old.finish(in: store))
        old.disappear(in: store)
        XCTAssertEqual(store.activeTimelineScrubID, replacementID)
        XCTAssertEqual(store.playhead, 9)
        XCTAssertEqual(store.makeSavedReviewState().playhead, 5)
        XCTAssertTrue(store.commitTimelineScrub(to: 10))
    }

    func testCancelledCallbacksNeverFallBackToDiscreteSeek() {
        let (store, controller) = fixture()
        XCTAssertTrue(controller.begin(in: store))
        XCTAssertTrue(controller.valueChanged(to: 12, in: store))
        store.cancelTimelineScrub()
        XCTAssertFalse(controller.valueChanged(to: 15, in: store))
        XCTAssertFalse(controller.finish(in: store))
        XCTAssertFalse(controller.valueChanged(to: 17, in: store))
        XCTAssertFalse(controller.finish(in: store), "End-only cannot consume an unowned sample")
        XCTAssertEqual(store.playhead, 5)
        XCTAssertFalse(store.hasActiveTimelineScrub)
        XCTAssertTrue(store.flushReviewAutosave())
        XCTAssertEqual(store.autosavedReview?.state.playhead, 5)
    }

    func testEndOnlyAndDuplicateEndDoNotCommit() {
        let (store, controller) = fixture()
        XCTAssertFalse(controller.finish(in: store))
        XCTAssertTrue(controller.begin(in: store))
        XCTAssertTrue(controller.valueChanged(to: 8, in: store))
        XCTAssertTrue(controller.finish(in: store))
        store.seek(to: 10)
        XCTAssertFalse(controller.finish(in: store))
        XCTAssertEqual(store.playhead, 10)
        XCTAssertFalse(store.hasActiveTimelineScrub)
    }

    func testExplicitAccessibilityStepsWorkWithoutDragAndClampAtEnds() {
        let (store, controller) = fixture()
        XCTAssertTrue(controller.adjustDiscrete(direction: 1, in: store))
        XCTAssertEqual(store.playhead, 5.1, accuracy: 0.000_001)
        XCTAssertTrue(controller.adjustDiscrete(direction: -1, in: store))
        XCTAssertEqual(store.playhead, 5, accuracy: 0.000_001)
        XCTAssertTrue(store.isPlaying)
        XCTAssertFalse(controller.isEditing)
        XCTAssertFalse(store.hasActiveTimelineScrub)
        store.seek(to: 0.05)
        XCTAssertTrue(controller.adjustDiscrete(direction: -1, in: store))
        XCTAssertEqual(store.playhead, 0)
        XCTAssertFalse(controller.adjustDiscrete(direction: -1, in: store))
        store.seek(to: store.selectedScenario.duration - 0.05)
        XCTAssertTrue(controller.adjustDiscrete(direction: 1, in: store))
        XCTAssertEqual(store.playhead, store.selectedScenario.duration)
        XCTAssertFalse(controller.adjustDiscrete(direction: 1, in: store))
        XCTAssertFalse(controller.adjustDiscrete(direction: 0, in: store))
    }

    func testAccessibilityCannotInterruptOwnedForeignOrSpatialGesture() {
        let (store, controller) = fixture()
        XCTAssertTrue(controller.begin(in: store))
        XCTAssertFalse(controller.adjustDiscrete(direction: 1, in: store))
        XCTAssertEqual(store.playhead, 5)
        XCTAssertTrue(controller.finish(in: store))
        XCTAssertTrue(store.beginTimelineScrub())
        XCTAssertTrue(store.previewTimelineScrub(to: 9))
        XCTAssertFalse(controller.adjustDiscrete(direction: -1, in: store))
        XCTAssertEqual(store.playhead, 9)
        store.cancelTimelineScrub()
        store.beginDrawing(.arc)
        XCTAssertFalse(controller.adjustDiscrete(direction: 1, in: store))
        XCTAssertFalse(controller.isEnabled(in: store))
        store.cancelDrawing()
    }

    func testStagedSampleCannotCrossIntoForeignOwnership() throws {
        let (store, controller) = fixture()
        XCTAssertFalse(controller.valueChanged(to: 15, in: store))
        XCTAssertTrue(store.beginTimelineScrub())
        let owner = try XCTUnwrap(store.activeTimelineScrubID)
        XCTAssertTrue(store.previewTimelineScrub(to: 9))
        XCTAssertFalse(controller.begin(in: store))
        XCTAssertFalse(controller.finish(in: store))
        XCTAssertEqual(store.activeTimelineScrubID, owner)
        XCTAssertEqual(store.playhead, 9)
        store.cancelTimelineScrub()
        XCTAssertTrue(controller.begin(in: store))
        XCTAssertEqual(store.playhead, 5, "Rejected begin clears staged samples")
        XCTAssertTrue(controller.finish(in: store))
    }

    func testMissingEndAfterExternalCancelCannotLeaveSliderDisabled() {
        let (store, controller) = fixture()
        XCTAssertTrue(controller.begin(in: store))
        XCTAssertTrue(controller.valueChanged(to: 12, in: store))
        store.cancelTimelineScrub()
        XCTAssertTrue(controller.isEnabled(in: store))
        XCTAssertFalse(controller.valueChanged(to: 15, in: store), "Old binding samples are still rejected")
        XCTAssertTrue(controller.begin(in: store), "New explicit start recovers without an old end callback")
        XCTAssertTrue(controller.valueChanged(to: 8, in: store))
        XCTAssertTrue(controller.finish(in: store))
        XCTAssertEqual(store.playhead, 8)
    }

    func testRejectedBeginRecoversForAccessibilityAndNewDragWithoutEndCallback() {
        let (store, controller) = fixture()
        XCTAssertTrue(store.beginTimelineScrub())
        XCTAssertFalse(controller.begin(in: store))
        store.cancelTimelineScrub()
        XCTAssertTrue(controller.isEnabled(in: store))
        XCTAssertTrue(controller.adjustDiscrete(direction: 1, in: store))
        XCTAssertEqual(store.playhead, 5.1, accuracy: 0.000_001)
        XCTAssertFalse(controller.isEditing)
        XCTAssertTrue(controller.begin(in: store))
        XCTAssertTrue(controller.valueChanged(to: 8, in: store))
        XCTAssertTrue(controller.finish(in: store))
        XCTAssertEqual(store.playhead, 8)
    }

    private func fixture() -> (ReplayStore, DashboardTimelineScrubController) {
        let store = ReplayStore()
        store.prepareForLocalExperience()
        store.seek(to: 5)
        store.isPlaying = true
        let controller = DashboardTimelineScrubController()
        controller.appear()
        return (store, controller)
    }
}
