import XCTest
@testable import ReplayXI

@MainActor
final class AnnotationEndpointNudgeFeedbackTests: XCTestCase {
    func testPartialCardinalStepsReportActualMovementForRunsAndSpaces() throws {
        let cases: [(CoachMarkKind, CoachMarkEndpoint, PitchPoint, PitchPoint, String)] = [
            (.run, .start, PitchPoint(x: 33.9, z: 0), PitchPoint(x: 0.25, z: 0), "10 centimetres right"),
            (.run, .end, PitchPoint(x: -33.9, z: 0), PitchPoint(x: -0.25, z: 0), "10 centimetres left"),
            (.space, .start, PitchPoint(x: 0, z: 52.4), PitchPoint(x: 0, z: 0.25), "10 centimetres upfield"),
            (.space, .end, PitchPoint(x: 0, z: -52.4), PitchPoint(x: 0, z: -0.25), "10 centimetres back")
        ]
        for (kind, endpoint, edge, requested, description) in cases {
            let store = makeStore()
            let mark = try makeMark(in: store, kind: kind,
                start: endpoint == .start ? edge : .zero,
                end: endpoint == .end ? edge : .zero)
            let before = try geometry(of: mark.id, in: store)

            let reported = try XCTUnwrap(AnnotationEndpointNudgeFeedback.apply(
                in: store, id: mark.id, endpoint: endpoint, by: requested))

            let after = try geometry(of: mark.id, in: store)
            assertDelta(reported, equals: difference(at: endpoint, before: before, after: after))
            XCTAssertEqual(point(opposite: endpoint, in: after), point(opposite: endpoint, in: before))
            XCTAssertEqual(AnnotationJoystickAccessibility.movementDescription(reported), description)
        }
    }

    func testDiagonalClampingReportsEachAppliedAxisWithoutMovingTheOtherEndpoint() throws {
        for kind in [CoachMarkKind.run, .space] {
            for endpoint in [CoachMarkEndpoint.start, .end] {
                let store = makeStore()
                let edge = PitchPoint(x: 33.9, z: 10)
                let mark = try makeMark(in: store, kind: kind,
                    start: endpoint == .start ? edge : .zero,
                    end: endpoint == .end ? edge : .zero)
                let before = try geometry(of: mark.id, in: store)

                let reported = try XCTUnwrap(AnnotationEndpointNudgeFeedback.apply(
                    in: store, id: mark.id, endpoint: endpoint, by: PitchPoint(x: 0.25, z: 0.25)))

                let after = try geometry(of: mark.id, in: store)
                assertDelta(reported, equals: difference(at: endpoint, before: before, after: after))
                XCTAssertEqual(point(opposite: endpoint, in: after), point(opposite: endpoint, in: before))
                XCTAssertEqual(AnnotationJoystickAccessibility.movementDescription(reported),
                    "10 centimetres right, 25 centimetres upfield")
            }
        }
    }

    func testZeroMovementAtTheBoundaryKeepsMarksTransportAndUndoUnchanged() throws {
        let store = makeStore()
        let mark = try makeMark(in: store, kind: .run,
            start: PitchPoint(x: 34, z: 52.5), end: PitchPoint(x: 24, z: 42))
        store.setPlaying(true, broadcast: false)
        let before = store.makeSnapshot()
        let undo = store.annotationUndoTitle
        var broadcasts = 0
        store.onBroadcastSnapshot = { _ in broadcasts += 1 }

        XCTAssertNil(AnnotationEndpointNudgeFeedback.apply(
            in: store, id: mark.id, endpoint: .start, by: PitchPoint(x: 0.25, z: 0.25)))

        XCTAssertEqual(store.makeSnapshot(), before)
        XCTAssertEqual(store.annotationUndoTitle, undo)
        XCTAssertTrue(store.isPlaying)
        XCTAssertEqual(broadcasts, 0)
    }

    func testTooShortRunOrSpaceIsRejectedWithoutFeedbackOrAnUndoStep() throws {
        for (kind, length) in [(CoachMarkKind.run, Float(0.9)), (.space, 1.2)] {
            let store = makeStore()
            let mark = try makeMark(in: store, kind: kind,
                start: .zero, end: PitchPoint(x: length, z: 0))
            store.setPlaying(true, broadcast: false)
            let before = store.makeSnapshot()
            let undo = store.annotationUndoTitle

            XCTAssertNil(AnnotationEndpointNudgeFeedback.apply(
                in: store, id: mark.id, endpoint: .start, by: PitchPoint(x: 0.25, z: 0)))

            XCTAssertEqual(store.makeSnapshot(), before)
            XCTAssertEqual(store.annotationUndoTitle, undo)
        }
    }

    func testPlayerBoundEndpointsUseCurrentPresentedGeometryAfterSeeking() throws {
        for endpoint in [CoachMarkEndpoint.start, .end] {
            let store = makeStore()
            let created = try makeMark(in: store, kind: .run,
                start: PitchPoint(x: 4, z: 5), end: PitchPoint(x: 8, z: 10))
            let playerID = store.selectedScenario.defaultPerspectiveID
            XCTAssertTrue(store.setCoachMarkTracking(id: created.id, playerID: playerID))
            store.seek(to: 12, broadcast: false)
            let before = try geometry(of: created.id, in: store)
            XCTAssertGreaterThan(ReplayGeometry.distance(before.start, created.start), 0.01,
                "This fixture must distinguish presented position from the authored position")

            let reported = try XCTUnwrap(AnnotationEndpointNudgeFeedback.apply(
                in: store, id: created.id, endpoint: endpoint, by: PitchPoint(x: 0.25, z: 0)))

            let after = try geometry(of: created.id, in: store)
            assertDelta(reported, equals: difference(at: endpoint, before: before, after: after))
            assertDelta(reported, equals: PitchPoint(x: 0.25, z: 0))
            assertDelta(point(opposite: endpoint, in: after), equals: point(opposite: endpoint, in: before))
            let adjusted = try XCTUnwrap(store.marks.first { $0.id == created.id })
            XCTAssertEqual(adjusted.startTrackAnchor?.playerID, playerID)
            XCTAssertEqual(adjusted.endTrackAnchor?.playerID, playerID)
            XCTAssertEqual(store.playhead, 12)
        }
    }

    func testNormalQuarterMetreControlsStillCommitOnceAndUndoExactly() throws {
        let steps = [PitchPoint(x: 0.25, z: 0), PitchPoint(x: -0.25, z: 0),
                     PitchPoint(x: 0, z: 0.25), PitchPoint(x: 0, z: -0.25)]
        for kind in [CoachMarkKind.run, .space] {
            for endpoint in [CoachMarkEndpoint.start, .end] {
                for requested in steps {
                    let store = makeStore()
                    let mark = try makeMark(in: store, kind: kind,
                        start: PitchPoint(x: 2, z: 3), end: PitchPoint(x: 8, z: 12))
                    let beforeMarks = store.marks
                    let before = try geometry(of: mark.id, in: store)
                    store.setPlaying(true, broadcast: false)
                    var broadcasts = 0
                    store.onBroadcastSnapshot = { _ in broadcasts += 1 }

                    let reported = try XCTUnwrap(AnnotationEndpointNudgeFeedback.apply(
                        in: store, id: mark.id, endpoint: endpoint, by: requested))

                    let after = try geometry(of: mark.id, in: store)
                    assertDelta(reported, equals: requested)
                    assertDelta(reported, equals: difference(at: endpoint, before: before, after: after))
                    XCTAssertEqual(point(opposite: endpoint, in: after), point(opposite: endpoint, in: before))
                    XCTAssertFalse(store.isPlaying)
                    XCTAssertEqual(broadcasts, 1)
                    XCTAssertTrue(store.undoAnnotationEdit())
                    XCTAssertEqual(store.marks, beforeMarks)
                }
            }
        }
    }

    func testHeldTimelineRejectsAtomicFeedbackAndCanStillCommit() throws {
        let store = makeStore()
        let mark = try makeMark(in: store, kind: .run,
            start: PitchPoint(x: 2, z: 3), end: PitchPoint(x: 8, z: 12))
        let marks = store.marks
        XCTAssertTrue(store.beginTimelineScrub())
        XCTAssertTrue(store.previewTimelineScrub(to: 14))

        XCTAssertNil(AnnotationEndpointNudgeFeedback.apply(
            in: store, id: mark.id, endpoint: .end, by: PitchPoint(x: 0.25, z: 0)))

        XCTAssertTrue(store.hasActiveTimelineScrub)
        XCTAssertEqual(store.playhead, 14)
        XCTAssertEqual(store.marks, marks)
        XCTAssertTrue(store.commitTimelineScrub(to: 14))
    }

    func testMissingMarkDoesNotReportMovementOrChangeTheReplay() {
        let store = makeStore()
        let before = store.makeSnapshot()
        XCTAssertNil(AnnotationEndpointNudgeFeedback.apply(
            in: store, id: UUID(), endpoint: .start, by: PitchPoint(x: 0.25, z: 0)))
        XCTAssertEqual(store.makeSnapshot(), before)
    }

    func testVisibleAndAssistiveFeedbackBothUseTheProductionAdapterResult() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        let source = try String(contentsOf: root.appendingPathComponent(
            "ReplayXI/Immersive/FootballImmersiveView.swift"), encoding: .utf8)
        let nudge = try slice(source, after: "private func nudgeAnnotation(",
            before: "private func nudgeAnnotationElevation(")
        XCTAssertTrue(nudge.contains("AnnotationEndpointNudgeFeedback.apply("))
        XCTAssertTrue(nudge.contains("hypot(appliedDelta.x, appliedDelta.z)"))
        XCTAssertTrue(nudge.contains("return appliedDelta"))
        let atomic = try slice(source, after: "private func atomicNudge(x:",
            before: "private var accessibilityValue:")
        XCTAssertTrue(atomic.contains("guard let appliedDelta = onAtomicNudge(x, z)"))
        XCTAssertTrue(atomic.contains("AnnotationJoystickAccessibility.movementDescription(appliedDelta)"))
        XCTAssertFalse(atomic.contains("movementDescription(PitchPoint(x: x, z: z))"))
    }

    private func makeStore() -> ReplayStore {
        let store = ReplayStore()
        store.prepareForLocalExperience()
        store.seek(to: 5, broadcast: false)
        return store
    }

    private func makeMark(in store: ReplayStore, kind: CoachMarkKind,
                          start: PitchPoint, end: PitchPoint) throws -> CoachMark {
        store.beginDrawing(kind)
        XCTAssertNil(store.registerPitchTap(start))
        let mark = try XCTUnwrap(store.registerPitchTap(end))
        if mark.followsPlayerTracks {
            XCTAssertTrue(store.setCoachMarkTracking(id: mark.id, playerID: nil))
        }
        return try XCTUnwrap(store.marks.first { $0.id == mark.id })
    }

    private func geometry(of id: UUID, in store: ReplayStore) throws -> ResolvedCoachMarkGeometry {
        let mark = try XCTUnwrap(store.marks.first { $0.id == id })
        return store.presentedCoachMarkGeometry(mark, at: store.playhead)
    }

    private func point(opposite endpoint: CoachMarkEndpoint,
                       in geometry: ResolvedCoachMarkGeometry) -> PitchPoint {
        endpoint == .start ? geometry.end : geometry.start
    }

    private func difference(at endpoint: CoachMarkEndpoint,
                            before: ResolvedCoachMarkGeometry,
                            after: ResolvedCoachMarkGeometry) -> PitchPoint {
        let from = endpoint == .start ? before.start : before.end
        let to = endpoint == .start ? after.start : after.end
        return PitchPoint(x: to.x - from.x, z: to.z - from.z)
    }

    private func assertDelta(_ reported: PitchPoint, equals actual: PitchPoint,
                             file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(reported.x, actual.x, accuracy: 0.000_1, file: file, line: line)
        XCTAssertEqual(reported.z, actual.z, accuracy: 0.000_1, file: file, line: line)
    }

    private func slice(_ source: String, after start: String, before end: String) throws -> String {
        let lower = try XCTUnwrap(source.range(of: start)?.upperBound)
        let upper = try XCTUnwrap(source.range(of: end, range: lower..<source.endIndex)?.lowerBound)
        return String(source[lower..<upper])
    }
}
