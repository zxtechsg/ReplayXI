import CoreGraphics
import XCTest
@testable import ReplayXI

final class AnnotationJoystickMathTests: XCTestCase {
    func testDeadZonePreventsAccidentalMovement() {
        let sample = AnnotationJoystickMath.sample(
            for: CGSize(width: 8, height: -11)
        )

        XCTAssertEqual(sample.steps, .zero)
        XCTAssertEqual(sample.knobOffset.width, 8, accuracy: 0.001)
        XCTAssertEqual(sample.knobOffset.height, -11, accuracy: 0.001)
    }

    func testDirectionsMapToIndependentPitchSteps() {
        XCTAssertEqual(
            AnnotationJoystickMath.sample(for: CGSize(width: 13, height: 0)).steps,
            SIMD2<Int>(1, 0)
        )
        XCTAssertEqual(
            AnnotationJoystickMath.sample(for: CGSize(width: -31, height: -49)).steps,
            SIMD2<Int>(-2, -3)
        )
    }

    func testTravelAndStepsAreBounded() {
        let sample = AnnotationJoystickMath.sample(
            for: CGSize(width: 1_000, height: -1_000)
        )
        let travel = hypot(sample.knobOffset.width, sample.knobOffset.height)

        XCTAssertEqual(travel, AnnotationJoystickMath.maximumTravel, accuracy: 0.001)
        XCTAssertEqual(
            sample.steps,
            SIMD2<Int>(
                AnnotationJoystickMath.maximumSteps,
                -AnnotationJoystickMath.maximumSteps
            )
        )
    }

    func testInvalidInputReturnsNeutralSample() {
        XCTAssertEqual(
            AnnotationJoystickMath.sample(
                for: CGSize(width: CGFloat.infinity, height: 10)
            ),
            .zero
        )
        XCTAssertEqual(
            AnnotationJoystickMath.sample(
                for: CGSize(width: 10, height: CGFloat.nan)
            ),
            .zero
        )
    }

    func testStepDeltaSupportsReversingWithinOneGesture() {
        XCTAssertEqual(
            AnnotationJoystickMath.delta(
                from: SIMD2<Int>(3, -2),
                to: SIMD2<Int>(-1, 1)
            ),
            SIMD2<Int>(-4, 3)
        )
    }

    func testRejectedNudgeDoesNotBecomeAReverseMoveWhenStickReturnsToCentre() {
        let committed = SIMD2<Int>.zero
        let rejectedOutward = SIMD2<Int>(1, 0)
        let afterRejection = AnnotationJoystickMath.committedSteps(
            from: committed,
            toward: rejectedOutward,
            mutationSucceeded: false
        )

        XCTAssertEqual(afterRejection, committed)
        XCTAssertEqual(
            AnnotationJoystickMath.delta(from: afterRejection, to: .zero),
            .zero,
            "Returning to centre after a rejected boundary move must not nudge inward."
        )

        let accepted = AnnotationJoystickMath.committedSteps(
            from: committed,
            toward: rejectedOutward,
            mutationSucceeded: true
        )
        XCTAssertEqual(accepted, rejectedOutward)
        XCTAssertEqual(
            AnnotationJoystickMath.delta(from: accepted, to: .zero),
            SIMD2<Int>(-1, 0),
            "Only a successfully applied outward step should be reversible."
        )
    }
}
