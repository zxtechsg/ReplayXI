import XCTest
@testable import ReplayXI

@MainActor
final class ReplaySnapshotStorageTests: XCTestCase {
    /// Compare only while both buffers are borrowed. No pointer escapes its lifetime.
    private func sharesStorage(_ a: [CoachMark], _ b: [CoachMark]) -> Bool {
        a.withUnsafeBufferPointer { first in
            b.withUnsafeBufferPointer { second in first.baseAddress == second.baseAddress }
        }
    }

    func testDenseUnpreviewedSnapshotsReuseStorageAndRemainValueIsolated() {
        let store = ReplayStore()
        let prototype = CoachMark(kind: .arc, start: .zero, end: .init(x: 5, z: 5), label: "Run")
        let frames = (0..<64).map { CoachMarkKeyframe(time: Double($0) * store.selectedScenario.duration / 63, mark: prototype) }
        store.marks = (0..<128).map { _ in
            CoachMark(kind: .arc, start: prototype.start, end: prototype.end, label: "Run", keyframes: frames)
        }
        let original = store.marks
        for _ in 0..<200 {
            let snapshot = store.makeSnapshot()
            XCTAssertTrue(sharesStorage(original, snapshot.marks), "No preview should not allocate a mapped mark array")
        }
        let saved = store.makeSavedReviewState()
        XCTAssertTrue(sharesStorage(original, saved.marks))
        store.marks.removeLast()
        XCTAssertEqual(saved.marks.count, 128)
        XCTAssertEqual(store.marks.count, 127)
        XCTAssertEqual(saved.marks.last?.keyframes?.count, 64)
    }

    func testKeyedGeometryPreviewStillMasksAllUncommittedPoseChanges() throws {
        let store = ReplayStore()
        store.seek(to: 2)
        store.beginDrawing(.arc)
        _ = store.registerPitchTap(.zero)
        let mark = try XCTUnwrap(store.registerPitchTap(.init(x: 8, z: 10)))
        XCTAssertTrue(store.captureCoachMarkKeyframe(id: mark.id))
        let original = store.marks
        store.seek(to: 6)
        XCTAssertTrue(store.updateCoachMarkGeometry(id: mark.id, start: .init(x: 2, z: 1),
                                                   end: .init(x: 10, z: 12), broadcast: false))
        XCTAssertNotEqual(store.marks, original)
        let masked = store.makeSnapshot()
        XCTAssertEqual(masked.marks, original)
        XCTAssertFalse(sharesStorage(store.marks, masked.marks))
        XCTAssertEqual(store.makeSavedReviewState().marks, original)
        XCTAssertTrue(store.cancelCoachMarkGeometryPreview(id: mark.id))
        XCTAssertEqual(store.marks, original)
        XCTAssertTrue(sharesStorage(store.marks, store.makeSnapshot().marks))
    }

    func testTimelineOnlyPreviewSharesGeometryButKeepsCommittedTime() throws {
        let store = ReplayStore()
        store.seek(to: 2)
        let original = store.marks
        XCTAssertFalse(original.isEmpty)
        XCTAssertTrue(store.beginTimelineScrub())
        XCTAssertTrue(store.previewTimelineScrub(to: 5))
        let snapshot = store.makeSnapshot()
        XCTAssertEqual(snapshot.playhead, 2)
        XCTAssertTrue(sharesStorage(original, snapshot.marks))
        store.cancelTimelineScrub()
        XCTAssertEqual(store.playhead, 2)
    }
}
