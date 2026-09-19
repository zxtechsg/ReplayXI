import XCTest
@testable import ReplayXI

@MainActor
final class PlaybackTimelineScrubControllerTests: XCTestCase {
    func testLateEndAfterCancellationPreservesCheckpointAndAutosave() throws {
        let store = fixture()
        let before = store.makeSavedReviewState()
        let controller = PlaybackTimelineScrubController()
        XCTAssertTrue(controller.preview(in: store, startLocation: 400, railWidth: 1000,
                                         translation: .init(width: 100, height: 0)))
        controller.cancel(in: store)
        XCTAssertFalse(controller.finish(in: store, railWidth: 1000, translation: .init(width: 300, height: 0)))
        XCTAssertEqual(store.playhead, 5)
        XCTAssertTrue(store.isPlaying)
        XCTAssertFalse(store.hasActiveTimelineScrub)
        XCTAssertNil(controller.state)
        XCTAssertTrue(store.flushReviewAutosave())
        XCTAssertEqual(store.autosavedReview?.state, before)
    }

    func testSystemExitThenLateEndDoesNotResumeOrSaveOldGesture() {
        let store = fixture()
        let controller = PlaybackTimelineScrubController()
        XCTAssertTrue(controller.preview(in: store, startLocation: 400, railWidth: 1000, translation: .zero))
        store.prepareForImmersiveExit()
        XCTAssertNotNil(controller.state, "The old UI callback can still hold local state")
        XCTAssertFalse(controller.finish(in: store, railWidth: 1000, translation: .init(width: 200, height: 0)))
        XCTAssertEqual(store.playhead, 5)
        XCTAssertFalse(store.isPlaying)
        XCTAssertNil(store.activeTimelineScrubID)
        XCTAssertTrue(store.flushReviewAutosave())
        XCTAssertEqual(store.autosavedReview?.state.playhead, 5)
    }

    func testOldEndAndCancelCannotChangeReplacementScrub() throws {
        for clearLocalState in [false, true] {
            let store = fixture()
            let old = PlaybackTimelineScrubController()
            XCTAssertTrue(old.preview(in: store, startLocation: 400, railWidth: 1000, translation: .zero))
            if clearLocalState { old.cancel(in: store) } else { store.cancelTimelineScrub() }
            XCTAssertTrue(store.beginTimelineScrub())
            let replacementID = try XCTUnwrap(store.activeTimelineScrubID)
            XCTAssertTrue(store.previewTimelineScrub(to: 9))
            XCTAssertFalse(old.finish(in: store, railWidth: 1000, translation: .init(width: 200, height: 0)))
            old.cancel(in: store)
            XCTAssertEqual(store.activeTimelineScrubID, replacementID)
            XCTAssertTrue(store.hasActiveTimelineScrub)
            XCTAssertEqual(store.playhead, 9)
            XCTAssertEqual(store.makeSavedReviewState().playhead, 5)
            XCTAssertTrue(store.commitTimelineScrub(to: 10))
            XCTAssertEqual(store.playhead, 10)
        }
    }

    func testOldPreviewCannotAdoptReplacementScrub() throws {
        let store = fixture()
        let old = PlaybackTimelineScrubController()
        XCTAssertTrue(old.preview(in: store, startLocation: 400, railWidth: 1000, translation: .zero))
        store.cancelTimelineScrub()
        XCTAssertTrue(store.beginTimelineScrub())
        let replacementID = try XCTUnwrap(store.activeTimelineScrubID)
        XCTAssertTrue(store.previewTimelineScrub(to: 9))
        XCTAssertFalse(old.preview(in: store, startLocation: 400, railWidth: 1000,
                                   translation: .init(width: 200, height: 0)))
        XCTAssertNil(old.state)
        XCTAssertEqual(store.activeTimelineScrubID, replacementID)
        XCTAssertEqual(store.playhead, 9)
        XCTAssertTrue(store.commitTimelineScrub(to: 10))
    }

    func testUnownedEndPreviewAndCancelCannotTakeAnotherRailsScrub() throws {
        let store = fixture()
        XCTAssertTrue(store.beginTimelineScrub())
        let existingID = try XCTUnwrap(store.activeTimelineScrubID)
        XCTAssertTrue(store.previewTimelineScrub(to: 9))
        let other = PlaybackTimelineScrubController()
        XCTAssertFalse(other.preview(in: store, startLocation: 100, railWidth: 1000, translation: .zero))
        XCTAssertFalse(other.finish(in: store, railWidth: 1000, translation: .zero))
        other.cancel(in: store)
        XCTAssertNil(other.state)
        XCTAssertEqual(store.activeTimelineScrubID, existingID)
        XCTAssertEqual(store.playhead, 9)
        XCTAssertTrue(store.commitTimelineScrub(to: 10))
    }

    func testActiveFinishUsesFinalTranslationAndRestoresPlayback() {
        let store = fixture()
        let controller = PlaybackTimelineScrubController()
        XCTAssertTrue(controller.preview(in: store, startLocation: 250, railWidth: 1000,
                                         translation: .init(width: 100, height: 0)))
        XCTAssertEqual(store.playhead, store.selectedScenario.duration * 0.35, accuracy: 0.000_001)
        XCTAssertTrue(controller.finish(in: store, railWidth: 1000, translation: .init(width: 200, height: 0)))
        XCTAssertEqual(store.playhead, store.selectedScenario.duration * 0.45, accuracy: 0.000_001)
        XCTAssertTrue(store.isPlaying)
        XCTAssertNil(controller.state)
        XCTAssertNil(store.activeTimelineScrubID)
        XCTAssertTrue(store.flushReviewAutosave())
        XCTAssertEqual(store.autosavedReview?.state.playhead, store.playhead)
    }

    func testTapStartsAnywhereAndDuplicateEndDoesNotJumpBack() {
        let store = fixture()
        let controller = PlaybackTimelineScrubController()
        XCTAssertFalse(controller.finish(in: store, railWidth: 1000, translation: .zero))
        XCTAssertEqual(store.playhead, 5)
        XCTAssertTrue(controller.preview(in: store, startLocation: 300, railWidth: 1000, translation: .zero))
        XCTAssertTrue(controller.finish(in: store, railWidth: 1000, translation: .zero))
        XCTAssertEqual(store.playhead, store.selectedScenario.duration * 0.3, accuracy: 0.000_001)
        store.seek(to: 8)
        XCTAssertFalse(controller.finish(in: store, railWidth: 1000, translation: .init(width: 200, height: 0)))
        XCTAssertEqual(store.playhead, 8)
        XCTAssertTrue(store.flushReviewAutosave())
        XCTAssertEqual(store.autosavedReview?.state.playhead, 8)
    }

    func testInvalidFinalSampleCancelsOnlyOwnedScrubAndNextPinchWorks() {
        let store = fixture()
        let controller = PlaybackTimelineScrubController()
        XCTAssertTrue(controller.preview(in: store, startLocation: 400, railWidth: 1000, translation: .zero))
        XCTAssertFalse(controller.finish(in: store, railWidth: 1000, translation: .init(width: CGFloat.nan, height: 0)))
        XCTAssertEqual(store.playhead, 5)
        XCTAssertFalse(store.hasActiveTimelineScrub)
        XCTAssertTrue(controller.preview(in: store, startLocation: 200, railWidth: 1000, translation: .zero))
        XCTAssertTrue(controller.finish(in: store, railWidth: 1000, translation: .zero))
        XCTAssertEqual(store.playhead, store.selectedScenario.duration * 0.2, accuracy: 0.000_001)
    }

    func testControllerFinishNeverAcquiresAndCancellationChecksOwner() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        let source = try String(contentsOf: root.appendingPathComponent(
            "ReplayXI/Immersive/PlaybackTimelineScrubController.swift"), encoding: .utf8)
        let start = try XCTUnwrap(source.range(of: "func finish(in")?.lowerBound)
        let end = try XCTUnwrap(source.range(of: "private func reset()")?.lowerBound)
        let completion = String(source[start..<end])
        XCTAssertFalse(completion.contains("beginTimelineScrub"))
        XCTAssertTrue(completion.contains("guard let state, ownsScrub(in: store)"))
        XCTAssertTrue(completion.contains("if ownsScrub(in: store) { store.cancelTimelineScrub() }"))
    }

    private func fixture() -> ReplayStore {
        let store = ReplayStore()
        store.prepareForLocalExperience()
        store.seek(to: 5)
        store.isPlaying = true
        return store
    }
}
