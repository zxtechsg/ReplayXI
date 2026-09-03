import XCTest
@testable import ReplayXI

final class PlaybackTimelineScrubTests: XCTestCase {
    func testHorizontalTravelUsesCoarseFineAndFrameGain() {
        var state = PlaybackTimelineScrub.begin(at: 20, duration: 100)
        state = PlaybackTimelineScrub.update(
            state,
            duration: 100,
            railWidth: 200,
            horizontalTranslation: 40,
            verticalTranslation: 0
        )
        XCTAssertEqual(state.time, 40, accuracy: 0.000_001)
        XCTAssertEqual(state.precision, .coarse)

        state = PlaybackTimelineScrub.update(
            state,
            duration: 100,
            railWidth: 200,
            horizontalTranslation: 40,
            verticalTranslation: 60
        )
        XCTAssertEqual(state.time, 40, accuracy: 0.000_001)
        XCTAssertEqual(state.precision, .fine)

        let fineGain = PlaybackTimelineScrub.gain(forVerticalTravel: 60)
        state = PlaybackTimelineScrub.update(
            state,
            duration: 100,
            railWidth: 200,
            horizontalTranslation: 80,
            verticalTranslation: 60
        )
        XCTAssertEqual(state.precision, .fine)
        XCTAssertEqual(state.time, 40 + 20 * fineGain, accuracy: 0.000_001)
    }

    func testVerticalPrecisionChangesPreserveReachedTime() {
        var state = PlaybackTimelineScrub.begin(at: 20, duration: 100)
        state = PlaybackTimelineScrub.update(
            state,
            duration: 100,
            railWidth: 200,
            horizontalTranslation: 40,
            verticalTranslation: 0
        )
        let reachedTime = state.time

        for verticalTravel: CGFloat in [41, 42, 60, 95, 96, 120] {
            state = PlaybackTimelineScrub.update(
                state,
                duration: 100,
                railWidth: 200,
                horizontalTranslation: 40,
                verticalTranslation: verticalTravel
            )
            XCTAssertEqual(state.time, reachedTime, accuracy: 0.000_001)
        }

        XCTAssertEqual(PlaybackTimelineScrub.precision(forVerticalTravel: 41), .coarse)
        XCTAssertEqual(PlaybackTimelineScrub.precision(forVerticalTravel: 42), .fine)
        XCTAssertEqual(PlaybackTimelineScrub.precision(forVerticalTravel: 95), .fine)
        XCTAssertEqual(PlaybackTimelineScrub.precision(forVerticalTravel: 96), .frame)
    }

    func testGestureSamplesClampAndRejectInvalidGeometry() {
        let nearEnd = PlaybackTimelineScrub.begin(at: 99, duration: 100)
        XCTAssertEqual(
            PlaybackTimelineScrub.update(
                nearEnd,
                duration: 100,
                railWidth: 200,
                horizontalTranslation: 500,
                verticalTranslation: 0
            ).time,
            100
        )
        let nearStart = PlaybackTimelineScrub.begin(at: 1, duration: 100)
        XCTAssertEqual(
            PlaybackTimelineScrub.update(
                nearStart,
                duration: 100,
                railWidth: 200,
                horizontalTranslation: -500,
                verticalTranslation: 0
            ).time,
            0
        )
        let valid = PlaybackTimelineScrub.begin(at: 12, duration: 100)
        XCTAssertEqual(
            PlaybackTimelineScrub.update(
                valid,
                duration: 100,
                railWidth: 0,
                horizontalTranslation: 80,
                verticalTranslation: 0
            ).time,
            12
        )
    }

    func testAccessibilityAdjustmentUsesOneSecondAndClamps() {
        XCTAssertEqual(
            PlaybackTimelineScrub.adjustedTime(4, direction: 1, duration: 10),
            5
        )
        XCTAssertEqual(
            PlaybackTimelineScrub.adjustedTime(0.2, direction: -1, duration: 10),
            0
        )
        XCTAssertEqual(
            PlaybackTimelineScrub.adjustedTime(9.8, direction: 1, duration: 10),
            10
        )
    }
}
