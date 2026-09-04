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
            AnnotationJoystickMath.sample(for: CGSize(width: -21, height: -29)).steps,
            SIMD2<Int>(-2, -3)
        )
    }

    func testAllFourNotchesHaveDistinctVisibleTravelBeforeKnobSaturation() {
        let translations: [CGFloat] = [13, 21, 29, 37]
        let samples = translations.map {
            AnnotationJoystickMath.sample(for: CGSize(width: $0, height: 0))
        }

        XCTAssertEqual(samples.map(\.steps.x), [1, 2, 3, 4])
        XCTAssertEqual(samples.map(\.knobOffset.width), translations)
        XCTAssertTrue(samples.allSatisfy {
            abs($0.knobOffset.width) <= AnnotationJoystickMath.maximumTravel
                && abs($0.knobOffset.height) <= AnnotationJoystickMath.maximumTravel
        })
    }

    func testAllFourDiagonalNotchesRemainVisuallyDistinct() {
        let translations: [CGFloat] = [13, 21, 29, 37]
        let samples = translations.map {
            AnnotationJoystickMath.sample(for: CGSize(width: $0, height: -$0))
        }

        XCTAssertEqual(samples.map(\.steps), [
            SIMD2<Int>(1, -1),
            SIMD2<Int>(2, -2),
            SIMD2<Int>(3, -3),
            SIMD2<Int>(4, -4),
        ])
        XCTAssertEqual(samples.map(\.knobOffset.width), translations)
        XCTAssertEqual(samples.map(\.knobOffset.height), translations.map { -$0 })
    }

    func testAxisTravelAndStepsAreBounded() {
        let sample = AnnotationJoystickMath.sample(
            for: CGSize(width: 1_000, height: -1_000)
        )

        XCTAssertEqual(sample.knobOffset.width, AnnotationJoystickMath.maximumTravel, accuracy: 0.001)
        XCTAssertEqual(sample.knobOffset.height, -AnnotationJoystickMath.maximumTravel, accuracy: 0.001)
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

    func testSamplesRepresentAbsoluteGestureRequestsAcrossReversal() {
        let outward = AnnotationJoystickMath.sample(
            for: CGSize(width: 1_000, height: -1_000)
        )
        let partiallyReturned = AnnotationJoystickMath.sample(
            for: CGSize(width: 29, height: -21)
        )
        let centred = AnnotationJoystickMath.sample(for: .zero)

        XCTAssertEqual(outward.steps, SIMD2<Int>(4, -4))
        XCTAssertEqual(partiallyReturned.steps, SIMD2<Int>(3, -2))
        XCTAssertEqual(centred.steps, .zero)
    }

    func testFinalGestureSampleIsSubmittedWhenItCrossesANotch() {
        let previouslySubmitted = AnnotationJoystickMath.sample(
            for: CGSize(width: 13, height: 0)
        )
        let authoritativeEnd = AnnotationJoystickMath.sample(
            for: CGSize(width: 21, height: -13)
        )

        XCTAssertTrue(
            AnnotationJoystickGesturePolicy.shouldSubmit(
                sample: authoritativeEnd,
                after: previouslySubmitted.steps
            )
        )
        XCTAssertFalse(
            AnnotationJoystickGesturePolicy.shouldSubmit(
                sample: authoritativeEnd,
                after: authoritativeEnd.steps
            )
        )
    }
}
