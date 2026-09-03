import XCTest
@testable import ReplayXI

final class PlaybackTimelineScrubTests: XCTestCase {
    func testPinchCanStartAnywhereOnRailAndClamps() {
        XCTAssertEqual(
            PlaybackTimelineScrub.begin(
                atRailLocation: 50,
                duration: 120,
                railWidth: 200
            ).time,
            30,
            accuracy: 0.000_001
        )
        XCTAssertEqual(
            PlaybackTimelineScrub.begin(
                atRailLocation: 400,
                duration: 120,
                railWidth: 200
            ).time,
            120,
            accuracy: 0.000_001
        )
        XCTAssertEqual(
            PlaybackTimelineScrub.begin(
                atRailLocation: -.infinity,
                duration: 120,
                railWidth: 200
            ).time,
            0,
            accuracy: 0.000_001
        )
    }

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

    func testFramePrecisionSnapsOnlyAfterHorizontalTravel() {
        var state = PlaybackTimelineScrub.begin(at: 10.017, duration: 100)
        state = PlaybackTimelineScrub.update(
            state,
            duration: 100,
            railWidth: 300,
            horizontalTranslation: 0,
            verticalTranslation: 110
        )
        XCTAssertEqual(
            state.time,
            10.017,
            accuracy: 0.000_001,
            "Lifting into frame mode must not move the playhead"
        )

        state = PlaybackTimelineScrub.update(
            state,
            duration: 100,
            railWidth: 300,
            horizontalTranslation: 7,
            verticalTranslation: 110
        )
        XCTAssertEqual(state.precision, .frame)
        XCTAssertEqual(
            state.time * PlaybackTimelineScrub.frameRate,
            (state.time * PlaybackTimelineScrub.frameRate).rounded(),
            accuracy: 0.000_001
        )
        XCTAssertEqual(
            PlaybackTimelineScrub.snappedToFrame(99.999, duration: 100),
            100,
            accuracy: 0.000_001
        )
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
