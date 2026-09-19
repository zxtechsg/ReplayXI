import XCTest
@testable import ReplayXI

@MainActor
final class AnnotationTimingDraftTests: XCTestCase {
    private var mark: CoachMark {
        CoachMark(kind: .arc, start: .init(x: 0, z: 0), end: .init(x: 5, z: 5),
                  label: "Run", revealTime: 2, hideTime: 10)
    }

    func testParsesSecondsAndMinuteTimestamps() throws {
        for (text, expected) in [("12.5", 12.5), ("1:12.5", 72.5), (" 0:02.25 ", 2.25),
                                 ("12,5", 12.5), (".5", 0.5), ("0", 0.0)] {
            XCTAssertEqual(try XCTUnwrap(AnnotationTimestamp.parse(text)), expected, accuracy: 0.000_001, text)
        }
    }

    func testRejectsIncompleteMalformedAndNonFiniteTimes() {
        for text in ["", " ", ".", "1:", ":2", "1:60", "1:02:03", "-1", "nan", "inf",
                     "1e3", "1..2", "2 seconds", "2:NaN", "1.5:20"] {
            XCTAssertNil(AnnotationTimestamp.parse(text), text)
        }
    }

    func testInvalidTextDoesNotFallBackToLastValidTime() {
        var draft = AnnotationTimingDraft(mark: mark, duration: 20)
        XCTAssertNil(draft.validationMessage(duration: 20))
        XCTAssertFalse(draft.differs(from: mark))
        draft.startText = "1:"
        XCTAssertNil(draft.start)
        XCTAssertNotNil(draft.validationMessage(duration: 20))
        XCTAssertTrue(draft.differs(from: mark))
        draft.startText = "0:02"
        XCTAssertFalse(draft.differs(from: mark), "Equivalent timestamps should not create an undo entry")
    }

    func testWindowValidationMatchesStoreBounds() {
        var draft = AnnotationTimingDraft(mark: mark, duration: 120)
        for (start, end, valid) in [("2", "2.49", false), ("2", "2.5", true),
                                  ("2", "32", true), ("2", "32.1", false),
                                  ("118", "121", false), ("121", "122", false),
                                  ("119.5", "120", true), ("0", "0", false)] {
            draft.startText = start; draft.endText = end
            XCTAssertEqual(draft.validationMessage(duration: 120) == nil, valid, "\(start)–\(end)")
            if valid, let start = draft.start, let end = draft.end {
                XCTAssertTrue(CoachMarkTimingPolicy.windowFits(revealTime: start,
                    displayDuration: end - start, replayDuration: 120))
            }
        }
    }

    func testThroughEndIgnoresUnusedOutFieldAndIncludesFinalFrame() {
        var draft = AnnotationTimingDraft(mark: mark, duration: 120)
        draft.throughEnd = true
        draft.startText = "120"
        draft.endText = "unfinished"
        XCTAssertNil(draft.validationMessage(duration: 120))
        XCTAssertTrue(draft.differs(from: mark))
        draft.throughEnd = false
        XCTAssertNotNil(draft.validationMessage(duration: 120))
    }

    func testReloadRetainsSubframePrecisionAndToEndMode() {
        let precise = CoachMark(kind: .pass, start: mark.start, end: mark.end,
            label: "Pass", revealTime: 2.123456, hideTime: nil)
        let draft = AnnotationTimingDraft(mark: precise, duration: 60)
        XCTAssertEqual(draft.startText, "2.123456")
        XCTAssertEqual(draft.endText, "60")
        XCTAssertTrue(draft.throughEnd)
        XCTAssertFalse(draft.differs(from: precise))
    }

    func testDisplayCarriesRoundingIntoNextMinuteAndHandlesInvalidInput() {
        XCTAssertEqual(AnnotationTimestamp.display(59.99), "01:00.0")
        XCTAssertEqual(AnnotationTimestamp.display(9.96), "00:10.0")
        XCTAssertEqual(AnnotationTimestamp.display(0), "00:00.0")
        XCTAssertEqual(AnnotationTimestamp.display(.nan), "—")
        XCTAssertEqual(AnnotationTimestamp.display(.infinity), "—")
        XCTAssertEqual(AnnotationTimestamp.editable(10.500000), "10.5")
    }
}
