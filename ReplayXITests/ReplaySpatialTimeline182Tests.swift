import XCTest
@testable import ReplayXI

@MainActor
final class ReplaySpatialTimeline182Tests: XCTestCase {
    private func mark(start: TimeInterval = 10, end: TimeInterval? = 20,
                      keys: [TimeInterval] = []) -> CoachMark {
        let base = CoachMark(kind: .run, start: .init(x: 0, z: 0),
            end: .init(x: 5, z: 5), label: "Run", revealTime: start, hideTime: end)
        guard !keys.isEmpty else { return base }
        return CoachMark(id: base.id, kind: base.kind, start: base.start, end: base.end,
            label: base.label, revealTime: start, hideTime: end,
            keyframes: keys.map { CoachMarkKeyframe(time: $0, mark: base) })
    }

    func testTimeMappingClipsAndRejectsMalformedDimensions() {
        XCTAssertEqual(SpatialAnnotationTimelineMath.time(at: 50, width: 100, duration: 40), 20)
        XCTAssertEqual(SpatialAnnotationTimelineMath.time(at: -10, width: 100, duration: 40), 0)
        XCTAssertEqual(SpatialAnnotationTimelineMath.time(at: 200, width: 100, duration: 40), 40)
        for (x, width, duration) in [
            (CGFloat.nan, CGFloat(100), TimeInterval(40)),
            (CGFloat(50), CGFloat.nan, TimeInterval(40)),
            (CGFloat(50), CGFloat(0), TimeInterval(40)),
            (CGFloat(50), CGFloat(100), TimeInterval.nan),
            (CGFloat(50), CGFloat(100), TimeInterval(0))
        ] {
            XCTAssertEqual(SpatialAnnotationTimelineMath.time(at: x, width: width, duration: duration), 0)
        }
    }

    func testExplicitWindowTrimRespectsMinMaxAndReplayEdges() {
        let short = mark()
        let startEarly = SpatialAnnotationTimelineMath.trim(.start, mark: short, delta: -100, duration: 40)
        XCTAssertEqual(startEarly.start, 0)
        XCTAssertEqual(startEarly.end, 20)
        let startLate = SpatialAnnotationTimelineMath.trim(.start, mark: short, delta: 100, duration: 40)
        XCTAssertEqual(startLate.start, 19.5)
        XCTAssertEqual(startLate.end, 20)
        let endEarly = SpatialAnnotationTimelineMath.trim(.end, mark: short, delta: -100, duration: 40)
        XCTAssertEqual(endEarly.start, 10)
        XCTAssertEqual(endEarly.end, 10.5)
        let endLate = SpatialAnnotationTimelineMath.trim(.end, mark: short, delta: 100, duration: 40)
        XCTAssertEqual(endLate.start, 10)
        XCTAssertNil(endLate.end, "The clip edge means through end")

        let long = mark(start: 2, end: 38)
        XCTAssertEqual(SpatialAnnotationTimelineMath.trim(.start, mark: long, delta: -100,
            duration: 40).start, 8, "Explicit windows stay within the 30-second authoring limit")
        XCTAssertEqual(SpatialAnnotationTimelineMath.trim(.end, mark: mark(start: 2, end: 10),
            delta: 50, duration: 100).end, 32)
    }

    func testThroughEndWindowDoesNotJumpOnZeroOrSmallStartDrag() {
        let throughEnd = mark(start: 10, end: nil)
        let unchangedStart = SpatialAnnotationTimelineMath.trim(.start, mark: throughEnd,
            delta: 0, duration: 100)
        XCTAssertEqual(unchangedStart.start, 10)
        XCTAssertNil(unchangedStart.end)
        let movedStart = SpatialAnnotationTimelineMath.trim(.start, mark: throughEnd,
            delta: 2, duration: 100)
        XCTAssertEqual(movedStart.start, 12)
        XCTAssertNil(movedStart.end)
        XCTAssertEqual(SpatialAnnotationTimelineMath.trim(.start, mark: throughEnd,
            delta: -200, duration: 100).start, 0)
        XCTAssertEqual(SpatialAnnotationTimelineMath.trim(.start, mark: throughEnd,
            delta: 200, duration: 100).start, 100,
            "A through-end mark can begin on the final paused frame")

        let unchangedEnd = SpatialAnnotationTimelineMath.trim(.end, mark: throughEnd,
            delta: 0, duration: 100)
        XCTAssertEqual(unchangedEnd.start, 10)
        XCTAssertNil(unchangedEnd.end)
        XCTAssertNil(SpatialAnnotationTimelineMath.trim(.end, mark: throughEnd,
            delta: -1, duration: 100).end,
            "A small end drag must not collapse a long through-end window")
        XCTAssertEqual(SpatialAnnotationTimelineMath.trim(.end, mark: throughEnd,
            delta: -70, duration: 100).end, 30,
            "Dragging within the explicit limit may create a finite end")
    }

    func testMovingWindowKeepsFirstAndLastKeysInsideClip() {
        let keyed = mark(keys: [5, 30])
        XCTAssertEqual(SpatialAnnotationTimelineMath.movedStart(mark: keyed,
            delta: -100, duration: 40), 5)
        XCTAssertEqual(SpatialAnnotationTimelineMath.movedStart(mark: keyed,
            delta: 100, duration: 40), 20)
        XCTAssertEqual(SpatialAnnotationTimelineMath.movedStart(mark: keyed,
            delta: 0, duration: 40), 10)

        let unkeyed = mark()
        XCTAssertEqual(SpatialAnnotationTimelineMath.movedStart(mark: unkeyed,
            delta: -100, duration: 40), 0)
        XCTAssertEqual(SpatialAnnotationTimelineMath.movedStart(mark: unkeyed,
            delta: 100, duration: 40), 30)
    }

    func testInvalidTrimAndMoveInputsKeepAuthoredTimes() {
        let original = mark(start: 7, end: 17, keys: [4, 22])
        for invalid in [TimeInterval.nan, .infinity, -.infinity] {
            let trimmed = SpatialAnnotationTimelineMath.trim(.start, mark: original,
                delta: invalid, duration: 40)
            XCTAssertEqual(trimmed.start, 7)
            XCTAssertEqual(trimmed.end, 17)
            XCTAssertEqual(SpatialAnnotationTimelineMath.movedStart(mark: original,
                delta: invalid, duration: 40), 7)
        }
        for invalidDuration in [TimeInterval.nan, .infinity, 0, -1] {
            let trimmed = SpatialAnnotationTimelineMath.trim(.end, mark: original,
                delta: 2, duration: invalidDuration)
            XCTAssertEqual(trimmed.start, 7)
            XCTAssertEqual(trimmed.end, 17)
            XCTAssertEqual(SpatialAnnotationTimelineMath.movedStart(mark: original,
                delta: 2, duration: invalidDuration), 7)
        }
    }
}
