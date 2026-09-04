import XCTest
@testable import ReplayXI

final class PlaybackControlDeckLayoutTests: XCTestCase {
    func testComfortPresetsStayInsideSafeHeadFollowEnvelope() {
        let near = PlaybackControlDeckLayout.resolve(
            preset: .near,
            usesAccessibilityText: false
        )
        let standard = PlaybackControlDeckLayout.resolve(
            preset: .standard,
            usesAccessibilityText: false
        )
        let large = PlaybackControlDeckLayout.resolve(
            preset: .large,
            usesAccessibilityText: false
        )

        XCTAssertGreaterThan(near.forwardOffset, standard.forwardOffset)
        XCTAssertGreaterThan(large.forwardOffset, standard.forwardOffset)
        XCTAssertGreaterThan(large.uniformScale, standard.uniformScale)

        for layout in [near, standard, large] {
            XCTAssertGreaterThanOrEqual(layout.attachmentWidth, 1_200)
            XCTAssertLessThanOrEqual(layout.attachmentWidth, 1_420)
            XCTAssertTrue((-1.45 ... -0.90).contains(layout.forwardOffset))
            XCTAssertTrue((-0.60 ... -0.35).contains(layout.verticalOffset))
            XCTAssertTrue((0.90 ... 1.25).contains(layout.uniformScale))
        }
    }

    func testAccessibilityTextExpandsLayoutWithoutMovingControlsOutOfReach() {
        for preset in PlaybackControlDeckPreset.allCases {
            let normal = PlaybackControlDeckLayout.resolve(
                preset: preset,
                usesAccessibilityText: false
            )
            let accessible = PlaybackControlDeckLayout.resolve(
                preset: preset,
                usesAccessibilityText: true
            )

            XCTAssertGreaterThanOrEqual(accessible.attachmentWidth, normal.attachmentWidth)
            XCTAssertGreaterThanOrEqual(accessible.contentWidth, normal.contentWidth)
            XCTAssertEqual(accessible.contentWidth, accessible.attachmentWidth - 40)
            XCTAssertGreaterThan(accessible.uniformScale, normal.uniformScale)
            XCTAssertGreaterThan(accessible.verticalOffset, normal.verticalOffset)
            XCTAssertGreaterThan(accessible.forwardOffset, normal.forwardOffset)
            XCTAssertGreaterThanOrEqual(accessible.attachmentWidth, 1_420)
            XCTAssertTrue((-1.30 ... -0.90).contains(accessible.forwardOffset))
            XCTAssertLessThanOrEqual(accessible.uniformScale, 1.31)
        }
    }
}
