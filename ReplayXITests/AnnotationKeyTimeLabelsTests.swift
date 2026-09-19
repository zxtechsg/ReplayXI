import XCTest
@testable import ReplayXI

final class AnnotationKeyTimeLabelsTests: XCTestCase {
    func testOrdinaryKeysKeepCompactTenths() {
        let labels = AnnotationKeyTimeLabels(times: [2, 4.5, 12])
        XCTAssertEqual(labels.label(at: 2), "00:02.0")
        XCTAssertEqual(labels.label(at: 4.5), "00:04.5")
    }

    func testSubframeKeysAreDistinguishableWithoutExcessPrecision() {
        let hundredths = AnnotationKeyTimeLabels(times: [2.01, 2.04])
        XCTAssertEqual(hundredths.label(at: 2.01), "00:02.01")
        XCTAssertEqual(hundredths.label(at: 2.04), "00:02.04")
        let micros = AnnotationKeyTimeLabels(times: [2.000001, 2.000003])
        XCTAssertEqual(micros.label(at: 2.000001), "00:02.000001")
        XCTAssertEqual(micros.label(at: 2.000003), "00:02.000003")
    }

    func testMinuteRoundingAndLargeInvalidInputsStaySafe() {
        XCTAssertEqual(AnnotationTimestamp.display(59.9999, fractionalDigits: 3), "01:00.000")
        XCTAssertEqual(AnnotationTimestamp.display(60.0001, fractionalDigits: 4), "01:00.0001")
        for invalid in [Double.nan, .infinity, -.infinity, -1, Double.greatestFiniteMagnitude, Double(Int.max)] {
            XCTAssertEqual(AnnotationTimestamp.display(invalid, fractionalDigits: 6), "—")
        }
        XCTAssertEqual(AnnotationTimestamp.display(2, fractionalDigits: -1), "00:02.0")
        XCTAssertEqual(AnnotationTimestamp.display(2, fractionalDigits: 90), "00:02.000000")
    }

    func testDuplicateOrInvalidTimesDoNotInflateValidLabels() {
        let labels = AnnotationKeyTimeLabels(times: [2, 2, 4, .nan, .infinity, -1])
        XCTAssertEqual(labels.label(at: 2), "00:02.0")
        XCTAssertEqual(labels.label(at: .nan), "—")
        XCTAssertEqual(labels.label(at: 7), "00:07.0")
    }

    func testRetimingAndRemovalRecomputeTheMinimumPrecision() {
        let first = AnnotationKeyTimeLabels(times: [2.01, 2.04])
        let moved = AnnotationKeyTimeLabels(times: [2.01, 3])
        let removed = AnnotationKeyTimeLabels(times: [2.01])
        XCTAssertEqual(first.label(at: 2.01), "00:02.01")
        XCTAssertEqual(moved.label(at: 2.01), "00:02.0")
        XCTAssertEqual(removed.label(at: 2.01), "00:02.0")
    }
}
