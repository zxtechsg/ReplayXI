import XCTest
@testable import ReplayXI

@MainActor
final class AnnotationExistingKeyHint162Tests: XCTestCase {
    func testAddHereExplainsExistingKeyAtStoreTolerance() throws {
        let store = ReplayStore()
        store.seek(to: 2)
        store.beginDrawing(.arc)
        _ = store.registerPitchTap(.init(x: 0, z: 0))
        let created = try XCTUnwrap(store.registerPitchTap(.init(x: 8, z: 10)))
        XCTAssertTrue(store.captureCoachMarkKeyframe(id: created.id))
        let mark = try XCTUnwrap(store.marks.first { $0.id == created.id })
        XCTAssertEqual(mark.keyframes?.count, 1)
        XCTAssertTrue(store.captureCoachMarkKeyframe(id: created.id), "Store capture upserts the same key")
        let replaced = try XCTUnwrap(store.marks.first { $0.id == created.id })
        XCTAssertEqual(replaced.keyframes, mark.keyframes)
        XCTAssertEqual(replaced.sampled(at: 2), mark.sampled(at: 2),
                       "An upsert may normalize nil elevations to zero but must preserve the visible pose")
        let duplicate = "A position is already saved at this time. Adjust shape to update it, or seek to add another."

        XCTAssertEqual(AnnotationTimingEditor.keyframeHint(for: mark, at: 2,
            windowIsDirty: false, positionIsDirty: false), duplicate)
        XCTAssertEqual(AnnotationTimingEditor.keyframeHint(for: mark, at: 2.0000005,
            windowIsDirty: false, positionIsDirty: false), duplicate)
        XCTAssertEqual(AnnotationTimingEditor.keyframeHint(for: mark, at: 2.1,
            windowIsDirty: false, positionIsDirty: false),
            "Tap a timestamp to preview or move it. Seek + Adjust shape saves a new position.")
    }

    func testFullCapacityHintNeverSuggestsAddingAtExistingOrFreeTime() {
        var mark = CoachMark(kind: .arc, start: .zero, end: .init(x: 8, z: 10), label: "Arc")
        for index in 0..<CoachMark.maximumKeyframes {
            mark = mark.recordingPose(at: Double(index) / 10)
        }
        XCTAssertEqual(mark.keyframes?.count, CoachMark.maximumKeyframes)
        let full = "64 keys saved. Adjust an existing position, or delete a key."
        XCTAssertEqual(AnnotationTimingEditor.keyframeHint(for: mark, at: 2,
            windowIsDirty: false, positionIsDirty: false), full)
        XCTAssertEqual(AnnotationTimingEditor.keyframeHint(for: mark, at: 2.05,
            windowIsDirty: false, positionIsDirty: false), full)
    }

    func testPendingDraftHintTakesPriorityOverExistingKey() throws {
        let mark = CoachMark(kind: .arc, start: .zero, end: .init(x: 8, z: 10), label: "Arc")
            .recordingPose(at: 2)
        XCTAssertEqual(AnnotationTimingEditor.keyframeHint(for: mark, at: 2,
            windowIsDirty: true, positionIsDirty: false),
            "Apply or reset times before adjusting shape.")
        XCTAssertEqual(AnnotationTimingEditor.keyframeHint(for: mark, at: 2,
            windowIsDirty: true, positionIsDirty: true),
            "Move or reset this position time before switching.")
    }
}
