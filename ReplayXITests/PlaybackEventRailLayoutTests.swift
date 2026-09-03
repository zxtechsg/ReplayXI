import XCTest
@testable import ReplayXI

final class PlaybackEventRailLayoutTests: XCTestCase {
    func testPagingNeverProducesPartialOrMissingEvents() {
        XCTAssertEqual(PlaybackEventRailLayout.pageCount(eventCount: 0), 1)
        XCTAssertEqual(PlaybackEventRailLayout.pageCount(eventCount: 3), 1)
        XCTAssertEqual(PlaybackEventRailLayout.pageCount(eventCount: 4), 2)
        XCTAssertEqual(PlaybackEventRailLayout.pageCount(eventCount: 10), 4)

        XCTAssertEqual(
            PlaybackEventRailLayout.visibleRange(eventCount: 4, page: 0),
            0..<3
        )
        XCTAssertEqual(
            PlaybackEventRailLayout.visibleRange(eventCount: 4, page: 1),
            3..<4
        )
        XCTAssertEqual(
            PlaybackEventRailLayout.visibleRange(eventCount: 4, page: 99),
            3..<4
        )
        XCTAssertEqual(
            PlaybackEventRailLayout.visibleRange(eventCount: 4, page: -99),
            0..<3
        )
    }

    func testCoachRailFitsWithoutCompressingAtConsoleWidth() {
        // 1,200-point deck minus its 44 points of deck padding and the event
        // shelf's 20 points of inset leaves 1,136 points of usable width.
        let availableContentWidth: CGFloat = 1_136
        XCTAssertLessThanOrEqual(
            PlaybackEventRailLayout.minimumCoachContentWidth,
            availableContentWidth
        )
        XCTAssertEqual(PlaybackEventRailLayout.minimumCoachContentWidth, 988)
    }

    func testRangeLabelCommunicatesExactlyWhatPagingWillReveal() {
        XCTAssertEqual(
            PlaybackEventRailLayout.rangeLabel(eventCount: 0, page: 0),
            "NO EVENTS"
        )
        XCTAssertEqual(
            PlaybackEventRailLayout.rangeLabel(eventCount: 7, page: 0),
            "1–3 OF 7"
        )
        XCTAssertEqual(
            PlaybackEventRailLayout.rangeLabel(eventCount: 7, page: 2),
            "7–7 OF 7"
        )
    }
}
