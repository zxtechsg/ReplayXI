import XCTest
@testable import ReplayXI

final class PlaybackTimelineFrameAccumulationTests: XCTestCase {
    private let duration: TimeInterval = 32
    private let width: CGFloat = 640

    func testSmallFrameSamplesAccumulateLikeOneContinuousDrag() {
        for direction: CGFloat in [-1, 1] {
            let direct = frameState(start: 10, translations: [40 * direction])
            for samples in [8, 40, 160] {
                let translations = (1...samples).map { CGFloat($0) * 40 / CGFloat(samples) * direction }
                let incremental = frameState(start: 10, translations: translations)
                XCTAssertEqual(incremental.time, direct.time, accuracy: 0.000_001,
                    "Frame travel must not depend on the number of hand-tracking samples")
            }
            XCTAssertNotEqual(direct.time, 10)
        }
    }

    func testSlowFrameDragCanReverseToItsStartingFrame() {
        let outward = (1...40).map { CGFloat($0) }
        let back = (0..<40).reversed().map { CGFloat($0) }
        let result = frameState(start: 10, translations: outward + back)
        XCTAssertEqual(result.time, 10, accuracy: 0.000_001)
        let outwardResult = frameState(start: 10, translations: outward)
        XCTAssertGreaterThan(outwardResult.time, result.time)
    }

    func testPrecisionChangesAloneNeverExposeHiddenFractionalTravel() {
        var state = frameState(start: 10, translations: [3])
        XCTAssertEqual(state.time, 10, accuracy: 0.000_001)
        for vertical: CGFloat in [130, 90, 0, 110] {
            state = update(state, x: 3, y: vertical)
            XCTAssertEqual(state.time, 10, accuracy: 0.000_001)
        }
    }

    func testLeavingFrameModeRebasesToVisibleTimeBeforeFurtherTravel() {
        var state = frameState(start: 10, translations: [5])
        let visible = state.time
        // At 0.020 s of travel the displayed frame rounds forward, leaving a
        // negative fraction. It must not make a later rightward drag go left.
        state = update(state, x: 5, y: 0)
        XCTAssertEqual(state.time, visible, accuracy: 0.000_001)
        state = update(state, x: 5.1, y: 0)
        XCTAssertEqual(state.time, visible + 0.005, accuracy: 0.000_001)
    }

    func testBoundaryOvershootIsDiscardedBeforeReversing() {
        let cases: [(Double, CGFloat)] = [(31.99, 1), (0.01, -1)]
        for (start, direction) in cases {
            var state = frameState(start: start, translations: [400 * direction])
            let boundary = direction > 0 ? duration : 0
            XCTAssertEqual(state.time, boundary)
            state = update(state, x: 390 * direction, y: 110)
            let expected = PlaybackTimelineScrub.snappedToFrame(
                boundary - 0.04 * Double(direction), duration: duration)
            XCTAssertEqual(state.time, expected, accuracy: 0.000_001)
        }
    }

    func testIgnoredGeometryKeepsAccumulatedFractionWithoutTakingTravel() {
        var state = frameState(start: 10, translations: [3])
        state = PlaybackTimelineScrub.update(state, duration: duration, railWidth: 0,
            horizontalTranslation: 200, verticalTranslation: 110)
        state = update(state, x: 6, y: 110)
        let direct = frameState(start: 10, translations: [6])
        XCTAssertEqual(state.time, direct.time, accuracy: 0.000_001)
    }

    private func frameState(start: TimeInterval, translations: [CGFloat]) -> PlaybackTimelineScrub.GestureState {
        var state = PlaybackTimelineScrub.begin(at: start, duration: duration)
        state = update(state, x: 0, y: 110)
        for x in translations { state = update(state, x: x, y: 110) }
        return state
    }

    private func update(_ state: PlaybackTimelineScrub.GestureState, x: CGFloat, y: CGFloat)
        -> PlaybackTimelineScrub.GestureState {
        PlaybackTimelineScrub.update(state, duration: duration, railWidth: width,
            horizontalTranslation: x, verticalTranslation: y)
    }
}
