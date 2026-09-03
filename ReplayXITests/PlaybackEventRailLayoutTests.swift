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

    func testContextualPagingFindsSelectedAndNearestEvents() {
        XCTAssertEqual(
            PlaybackEventRailLayout.page(containing: 0, eventCount: 10),
            0
        )
        XCTAssertEqual(
            PlaybackEventRailLayout.page(containing: 8, eventCount: 10),
            2
        )
        XCTAssertEqual(
            PlaybackEventRailLayout.page(containing: 99, eventCount: 10),
            3
        )
        XCTAssertEqual(
            PlaybackEventRailLayout.page(nearestTo: 20, eventTimes: [2, 8, 19, 21, 29]),
            0,
            "An equal-distance tie stays on the earlier event and its page"
        )
        XCTAssertEqual(
            PlaybackEventRailLayout.page(nearestTo: 28, eventTimes: [2, 8, 19, 21, 29]),
            1
        )
        XCTAssertEqual(
            PlaybackEventRailLayout.page(nearestTo: .nan, eventTimes: [2, 8, 19]),
            0
        )
        XCTAssertEqual(
            PlaybackEventRailLayout.page(nearestTo: 5, eventTimes: []),
            0
        )
    }

    func testReviewIndexSignatureIgnoresLiveGeometryButTracksRailMetadata() throws {
        let id = try XCTUnwrap(UUID(uuidString: "C63A71EC-F77D-49A4-91B7-10812CB2C33B"))
        let original = CoachMark(
            id: id,
            kind: .run,
            start: PitchPoint(x: 2, z: 3),
            end: PitchPoint(x: 8, z: 12),
            label: "Overlap",
            revealTime: 4,
            hideTime: 9
        )
        let geometryPreview = CoachMark(
            id: id,
            kind: .run,
            start: PitchPoint(x: -20, z: -14),
            end: PitchPoint(x: 18, z: 22),
            label: "Overlap",
            revealTime: 4,
            hideTime: 9
        )

        XCTAssertEqual(
            PlaybackReviewIndexKey(mark: original),
            PlaybackReviewIndexKey(mark: geometryPreview),
            "A live endpoint preview must not rebuild and sort the event rail"
        )

        let retimed = CoachMark(
            id: id,
            kind: .run,
            start: geometryPreview.start,
            end: geometryPreview.end,
            label: "Overlap",
            revealTime: 6,
            hideTime: 11
        )
        let relabelled = CoachMark(
            id: id,
            kind: .run,
            start: geometryPreview.start,
            end: geometryPreview.end,
            label: "Underlap",
            revealTime: 4,
            hideTime: 9
        )
        let resized = CoachMark(
            id: id,
            kind: .run,
            start: geometryPreview.start,
            end: geometryPreview.end,
            label: "Overlap",
            revealTime: 4,
            hideTime: 12
        )

        XCTAssertNotEqual(
            PlaybackReviewIndexKey(mark: original),
            PlaybackReviewIndexKey(mark: retimed)
        )
        XCTAssertNotEqual(
            PlaybackReviewIndexKey(mark: original),
            PlaybackReviewIndexKey(mark: relabelled)
        )
        XCTAssertNotEqual(
            PlaybackReviewIndexKey(mark: original),
            PlaybackReviewIndexKey(mark: resized)
        )
    }
}
