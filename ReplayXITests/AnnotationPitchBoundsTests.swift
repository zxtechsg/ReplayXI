import XCTest
@testable import ReplayXI

@MainActor
final class AnnotationPitchBoundsTests: XCTestCase {
    func testPitchDrawingAcceptsTouchlinesAndRejectsOffPitchPoints() throws {
        let store = ReplayStore()

        store.beginDrawing(.run)
        XCTAssertNil(
            store.registerPitchTap(
                PitchPoint(x: ReplayStore.pitchHalfWidth, z: ReplayStore.pitchHalfLength)
            )
        )
        let edgeMark = try XCTUnwrap(
            store.registerPitchTap(PitchPoint(x: -34, z: -52.5))
        )
        XCTAssertEqual(edgeMark.start.x, 34)
        XCTAssertEqual(edgeMark.end.z, -52.5)

        store.beginDrawing(.pass)
        XCTAssertNil(store.registerPitchTap(PitchPoint(x: 34.01, z: 0)))
        XCTAssertNil(store.pendingDrawStart)
        XCTAssertEqual(store.statusMessage, "Choose a point on the pitch")

        XCTAssertNil(store.registerPitchTap(PitchPoint(x: 0, z: -52.51)))
        XCTAssertNil(store.pendingDrawStart)
    }

    func testHandlePreviewAndCommitCannotEscapePitch() throws {
        let store = ReplayStore()
        store.beginDrawing(.space)
        XCTAssertNil(store.registerPitchTap(PitchPoint(x: 2, z: 3)))
        let mark = try XCTUnwrap(store.registerPitchTap(PitchPoint(x: 8, z: 9)))

        XCTAssertFalse(
            store.updateCoachMarkGeometry(
                id: mark.id,
                start: mark.start,
                end: PitchPoint(x: 35, z: 9),
                broadcast: false
            )
        )
        XCTAssertEqual(store.marks.first { $0.id == mark.id }, mark)

        XCTAssertFalse(
            store.updateCoachMarkGeometry(
                id: mark.id,
                start: PitchPoint(x: 2, z: 53),
                end: mark.end,
                broadcast: true
            )
        )
        XCTAssertEqual(store.marks.first { $0.id == mark.id }, mark)
    }

    func testTwoTapFallbackRejectsUnreadablyShortMarksAndKeepsStart() throws {
        let store = ReplayStore()
        let initialMarkCount = store.marks.count

        store.beginDrawing(.run)
        let runStart = PitchPoint(x: 2, z: 3)
        XCTAssertNil(store.registerPitchTap(runStart))
        XCTAssertNil(store.registerPitchTap(PitchPoint(x: 2.2, z: 3.2)))
        XCTAssertTrue(store.isDrawing)
        XCTAssertEqual(store.pendingDrawStart, runStart)
        XCTAssertEqual(store.marks.count, initialMarkCount)

        let run = try XCTUnwrap(store.registerPitchTap(PitchPoint(x: 3, z: 3)))
        XCTAssertEqual(run.kind, .run)

        store.beginDrawing(.space)
        let zoneStart = PitchPoint(x: -4, z: 5)
        XCTAssertNil(store.registerPitchTap(zoneStart))
        XCTAssertNil(store.registerPitchTap(PitchPoint(x: -3, z: 5)))
        XCTAssertEqual(store.pendingDrawStart, zoneStart)
        XCTAssertNotNil(store.registerPitchTap(PitchPoint(x: -2.8, z: 5)))
    }

    func testRemoteAnnotationOutsideRenderedPitchIsRejected() {
        let store = ReplayStore()
        let offPitch = CoachMark(
            kind: .danger,
            start: PitchPoint(x: 0, z: 0),
            end: PitchPoint(x: ReplayStore.pitchHalfWidth + 0.01, z: 1),
            label: "Malformed wide mark",
            revealTime: 1,
            hideTime: 4
        )

        XCTAssertFalse(store.appendRemoteCoachMark(offPitch))
        XCTAssertFalse(store.marks.contains(where: { $0.id == offPitch.id }))
    }
}
