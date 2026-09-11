import XCTest
@testable import ReplayXI

final class PlaybackControlDeckLayoutTests: XCTestCase {
    func testComfortPresetsStayInsideInitialWorkspaceEnvelope() {
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

    func testViewHUDStaysInUpperLeftComfortQuadrant() {
        for preset in PlaybackControlDeckPreset.allCases {
            let layout = PlaybackViewHUDLayout.resolve(
                preset: preset,
                usesAccessibilityText: false
            )

            XCTAssertGreaterThanOrEqual(layout.attachmentWidth, 500)
            XCTAssertLessThanOrEqual(layout.attachmentWidth, 600)
            XCTAssertLessThan(layout.horizontalOffset, -0.45)
            XCTAssertGreaterThan(layout.verticalOffset, 0.15)
            XCTAssertTrue((-1.25 ... -0.90).contains(layout.forwardOffset))
            XCTAssertTrue((0.90 ... 1.15).contains(layout.uniformScale))
        }
    }

    func testAccessibleViewHUDGrowsTowardTheWearerWithoutCrossingCentre() {
        for preset in PlaybackControlDeckPreset.allCases {
            let normal = PlaybackViewHUDLayout.resolve(
                preset: preset,
                usesAccessibilityText: false
            )
            let accessible = PlaybackViewHUDLayout.resolve(
                preset: preset,
                usesAccessibilityText: true
            )

            XCTAssertGreaterThan(accessible.attachmentWidth, normal.attachmentWidth)
            XCTAssertGreaterThan(accessible.uniformScale, normal.uniformScale)
            XCTAssertGreaterThan(accessible.horizontalOffset, normal.horizontalOffset)
            XCTAssertLessThan(accessible.horizontalOffset, -0.45)
            XCTAssertGreaterThan(accessible.forwardOffset, normal.forwardOffset)
            XCTAssertLessThan(accessible.verticalOffset, normal.verticalOffset)
        }
    }
}
