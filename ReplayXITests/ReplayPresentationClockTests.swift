import XCTest
@testable import ReplayXI

final class ReplayPresentationClockTests: XCTestCase {
    func testActiveCadenceIsApproximatelySixtyHertz() {
        let seconds = ReplayPresentationClock.seconds(
            ReplayPresentationClock.activeInterval
        )
        XCTAssertEqual(seconds, 1 / 60, accuracy: 0.000_001)
    }

    func testPausedCadencePollsLessOftenThanActivePlayback() {
        XCTAssertEqual(
            ReplayPresentationClock.interval(shouldAdvance: true),
            ReplayPresentationClock.activeInterval
        )
        XCTAssertEqual(
            ReplayPresentationClock.interval(shouldAdvance: false),
            ReplayPresentationClock.idleInterval
        )
        XCTAssertGreaterThan(
            ReplayPresentationClock.seconds(ReplayPresentationClock.idleInterval),
            ReplayPresentationClock.seconds(ReplayPresentationClock.activeInterval)
        )
    }

    func testDurationConversionPreservesSubsecondPrecision() {
        XCTAssertEqual(
            ReplayPresentationClock.seconds(.milliseconds(275)),
            0.275,
            accuracy: 0.000_000_1
        )
    }
}
