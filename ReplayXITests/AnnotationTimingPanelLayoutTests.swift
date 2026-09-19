import XCTest
@testable import ReplayXI

@MainActor
final class AnnotationTimingPanelLayoutTests: XCTestCase {
    func testCompactContentDoesNotExpandToScrollCap() {
        XCTAssertEqual(AnnotationTimingPanelLayout.height(contentHeight: 289.25, usesAccessibilityText: false), 290)
        XCTAssertEqual(AnnotationTimingPanelLayout.height(contentHeight: 289.25, usesAccessibilityText: true), 290)
    }

    func testExpandedContentStaysBoundedAtEachTextSize() {
        XCTAssertEqual(AnnotationTimingPanelLayout.height(contentHeight: 1100, usesAccessibilityText: false), 520)
        XCTAssertEqual(AnnotationTimingPanelLayout.height(contentHeight: 1100, usesAccessibilityText: true), 620)
    }

    func testFirstLayoutAndInvalidMeasurementsUseFiniteCap() {
        let measurements: [CGFloat?] = [nil, .nan, .infinity, 0, -1]
        for measurement in measurements {
            XCTAssertEqual(AnnotationTimingPanelLayout.height(contentHeight: measurement, usesAccessibilityText: false), 520)
        }
    }
}
