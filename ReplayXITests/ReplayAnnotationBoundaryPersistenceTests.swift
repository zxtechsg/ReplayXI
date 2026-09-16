import Foundation
import XCTest
@testable import ReplayXI

@MainActor
final class ReplayAnnotationBoundaryPersistenceTests: XCTestCase {
    private var temporaryDirectories: [URL] = []

    override func tearDownWithError() throws {
        for directory in temporaryDirectories {
            try FileManager.default.removeItem(at: directory)
        }
        temporaryDirectories.removeAll()
    }

    func testTouchlineRunRemainsSaveableThroughDiskRelaunch() throws {
        try assertDrawnRunRoundTrips(
            to: PitchPoint(x: -34, z: 35), name: "Touchline run"
        )
    }

    func testInteriorRunRetainsTrackAndTimeThroughDiskRelaunch() throws {
        try assertDrawnRunRoundTrips(
            to: PitchPoint(x: -33.75, z: 35), name: "Interior run"
        )
    }

    func testDrawingBeyondTouchlineIsRejectedWithoutPoisoningTheReview() throws {
        let store = try makeStoreAtRunnerKnot()
        let originalMarks = store.marks
        let runner = try XCTUnwrap(store.selectedScenario.player(id: "navy-rb"))
        let start = store.presentedPlayerPose(for: runner, at: store.playhead).position
        store.beginDrawing(.run)
        XCTAssertNil(store.registerPitchTap(start))

        XCTAssertNil(store.registerPitchTap(PitchPoint(x: -34.01, z: 35)))
        XCTAssertEqual(store.marks, originalMarks)
        XCTAssertEqual(store.pendingDrawStart, start)
        XCTAssertTrue(store.isDrawing)
        store.cancelDrawing()
        XCTAssertTrue(store.saveReview(named: "Unchanged valid review"))
        XCTAssertTrue(store.flushReviewAutosave())
    }

    func testImportedOutwardRoundedAndTrulyOffPitchAnchorsStayInvalid() throws {
        let store = try makeStoreAtRunnerKnot()
        let runner = try XCTUnwrap(store.selectedScenario.player(id: "navy-rb"))
        let start = runner.presentationPose(at: store.playhead).position
        let fallbackEnd = PitchPoint(x: -34, z: 35)

        for requestedX: Float in [-34, -34.01] {
            // Preserve the original arithmetic in this untrusted-payload
            // control. A local anchor-writing fix must not relax import bounds.
            let rawOffset = PitchPoint(
                x: requestedX - start.x, z: fallbackEnd.z - start.z
            )
            let imported = CoachMark(
                kind: .run,
                start: start,
                end: fallbackEnd,
                label: "Imported outward endpoint",
                revealTime: store.playhead,
                hideTime: store.playhead + 8,
                startTrackAnchor: CoachMarkTrackAnchor(playerID: runner.id),
                endTrackAnchor: CoachMarkTrackAnchor(playerID: runner.id, offset: rawOffset)
            )
            let resolved = imported.resolvedGeometry(in: store.selectedScenario, at: store.playhead)
            XCTAssertLessThan(resolved.end.x, -ReplayStore.pitchHalfWidth)
            XCTAssertFalse(ReplayStore.isValidReviewMark(imported, for: store.selectedScenario))

            let baseline = store.makeSavedReviewState()
            var byScenario = baseline.marksByScenario
            byScenario[baseline.scenarioID, default: []].append(imported)
            let payload = SavedReplayState(
                scenarioID: baseline.scenarioID,
                playhead: baseline.playhead,
                playbackRate: baseline.playbackRate,
                viewMode: baseline.viewMode,
                perspectiveID: baseline.perspectiveID,
                showsLaneLens: baseline.showsLaneLens,
                shapeFocusStage: baseline.shapeFocusStage,
                marksByScenario: byScenario
            )
            XCTAssertFalse(store.reviewLibrary.accepts(payload))
            XCTAssertFalse(store.saveReview(named: "Invalid import", state: payload))
        }
        XCTAssertTrue(store.savedReviews.isEmpty)
        XCTAssertTrue(store.flushReviewAutosave())
    }

    func testEveryEdgeAndCornerStaysBoundedFromActualPlayerPoses() throws {
        let destinations: [PitchPoint] = [
            PitchPoint(x: -34, z: 0), PitchPoint(x: 34, z: 0),
            PitchPoint(x: 0, z: -52.5), PitchPoint(x: 0, z: 52.5),
            PitchPoint(x: -34, z: -52.5), PitchPoint(x: -34, z: 52.5),
            PitchPoint(x: 34, z: -52.5), PitchPoint(x: 34, z: 52.5)
        ]
        let scenario = try XCTUnwrap(DemoScenarios.scenario(for: .squadReplay))
        for time: TimeInterval in [0, 8.125, 15.6, 25.4, 32] {
            for player in scenario.players {
                let store = makeStore(at: nil)
                store.seek(to: time)
                let origin = store.presentedPlayerPose(for: player, at: time).position
                for destination in destinations {
                    let context = "\(player.id) at \(time), to \(destination)"
                    store.beginDrawing(.run)
                    XCTAssertNil(store.registerPitchTap(origin), context)
                    let mark = try XCTUnwrap(store.registerPitchTap(destination), context)
                    XCTAssertEqual(mark.start, origin, context)
                    XCTAssertEqual(mark.end, destination, context)
                    XCTAssertEqual(mark.revealTime, time, context)
                    let startAnchor = try XCTUnwrap(mark.startTrackAnchor, context)
                    let endAnchor = try XCTUnwrap(mark.endTrackAnchor, context)
                    XCTAssertEqual(startAnchor.playerID, endAnchor.playerID, context)
                    let resolved = store.presentedCoachMarkGeometry(mark, at: time)
                    XCTAssertLessThanOrEqual(abs(resolved.end.x), ReplayStore.pitchHalfWidth, context)
                    XCTAssertLessThanOrEqual(abs(resolved.end.z), ReplayStore.pitchHalfLength, context)
                    XCTAssertEqual(resolved.end.x, destination.x, accuracy: 0.00001, context)
                    XCTAssertEqual(resolved.end.z, destination.z, accuracy: 0.00001, context)
                    XCTAssertTrue(ReplayStore.isValidReviewMark(mark, for: scenario), context)

                    // At a co-located track knot the deterministic nearest
                    // player may be a teammate, but its sampled origin agrees.
                    let attachedPlayer = try XCTUnwrap(scenario.player(id: endAnchor.playerID))
                    let attachedOrigin = store.presentedPlayerPose(for: attachedPlayer, at: time).position
                    XCTAssertEqual(attachedOrigin, origin, context)
                    assertOffsetUsesAtMostOneInwardStep(
                        origin: origin.x, endpoint: destination.x,
                        offset: endAnchor.offset.x, limit: ReplayStore.pitchHalfWidth
                    )
                    assertOffsetUsesAtMostOneInwardStep(
                        origin: origin.z, endpoint: destination.z,
                        offset: endAnchor.offset.z, limit: ReplayStore.pitchHalfLength
                    )
                }
                XCTAssertTrue(store.saveReview(named: "Eight pitch boundaries"))
                XCTAssertTrue(store.flushReviewAutosave())
            }
        }
    }

    func testOrdinaryOffsetsRemainExactlyTheSameForBothTeams() throws {
        let scenario = try XCTUnwrap(DemoScenarios.scenario(for: .squadReplay))
        for time: TimeInterval in [8.125, 15.6, 25.4] {
            for player in scenario.players {
                let store = makeStore(at: nil)
                store.seek(to: time)
                let origin = store.presentedPlayerPose(for: player, at: time).position
                let destination = PitchPoint(
                    x: origin.x + (origin.x > 0 ? -2 : 2),
                    z: origin.z + (origin.z > 0 ? -4 : 4)
                )
                store.beginDrawing(.run)
                _ = store.registerPitchTap(origin)
                let mark = try XCTUnwrap(store.registerPitchTap(destination))
                XCTAssertEqual(
                    mark.endTrackAnchor?.offset,
                    PitchPoint(x: destination.x - origin.x, z: destination.z - origin.z),
                    "Ordinary offsets must not be quantised or rounded globally"
                )
                XCTAssertTrue(ReplayStore.isValidReviewMark(mark, for: scenario))
                XCTAssertTrue(store.flushReviewAutosave())
            }
        }
    }

    func testDirectEditsAndTrackingUseTheSameBoundedTouchlineRepresentation() throws {
        let store = try makeStoreAtRunnerKnot()
        let runner = try XCTUnwrap(store.selectedScenario.player(id: "navy-rb"))
        let origin = store.presentedPlayerPose(for: runner, at: store.playhead).position
        let touchline = PitchPoint(x: -34, z: 35)
        store.beginDrawing(.run)
        _ = store.registerPitchTap(origin)
        let created = try XCTUnwrap(store.registerPitchTap(PitchPoint(x: -33.75, z: 35)))
        XCTAssertTrue(store.updateCoachMarkGeometry(id: created.id, start: origin, end: touchline))
        let edited = try XCTUnwrap(store.marks.first { $0.id == created.id })
        XCTAssertEqual(edited.end, touchline)
        XCTAssertEqual(edited.revealTime, created.revealTime)
        XCTAssertEqual(edited.endTrackAnchor?.playerID, runner.id)
        XCTAssertGreaterThanOrEqual(
            store.presentedCoachMarkGeometry(edited, at: store.playhead).end.x,
            -ReplayStore.pitchHalfWidth
        )

        // Freeze it, set the unbound endpoint exactly on the line, then attach
        // again through the user-facing Follow action instead of the draw path.
        XCTAssertTrue(store.setCoachMarkTracking(id: created.id, playerID: nil))
        XCTAssertTrue(store.updateCoachMarkGeometry(id: created.id, start: origin, end: touchline))
        XCTAssertTrue(store.setCoachMarkTracking(id: created.id, playerID: runner.id))
        let tracked = try XCTUnwrap(store.marks.first { $0.id == created.id })
        XCTAssertEqual(tracked.id, created.id)
        XCTAssertEqual(tracked.end, touchline)
        XCTAssertEqual(tracked.revealTime, created.revealTime)
        XCTAssertEqual(tracked.endTrackAnchor, edited.endTrackAnchor)
        XCTAssertTrue(ReplayStore.isValidReviewMark(tracked, for: store.selectedScenario))
        XCTAssertTrue(store.saveReview(named: "Edited touchline run"))
        XCTAssertTrue(store.flushReviewAutosave())
    }

    private func assertOffsetUsesAtMostOneInwardStep(
        origin: Float,
        endpoint: Float,
        offset: Float,
        limit: Float,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let raw = endpoint - origin
        let reconstructed = origin + raw
        let expected = reconstructed > limit
            ? raw.nextDown
            : reconstructed < -limit ? raw.nextUp : raw
        XCTAssertEqual(offset, expected, file: file, line: line)
    }

    private func assertDrawnRunRoundTrips(
        to destination: PitchPoint,
        name: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws {
        let url = try makeURL()
        let store = makeStore(at: url)
        // A rejected new save must leave this real, valid baseline intact.
        XCTAssertTrue(store.saveReview(named: "Before drawing"), file: file, line: line)
        XCTAssertTrue(store.flushReviewAutosave(), file: file, line: line)
        store.seek(to: 15.6)
        let runner = try XCTUnwrap(store.selectedScenario.player(id: "navy-rb"))
        let start = store.presentedPlayerPose(for: runner, at: store.playhead).position
        XCTAssertEqual(start, PitchPoint(x: 30.8, z: 32.7), file: file, line: line)
        store.beginDrawing(.run)
        XCTAssertNil(store.registerPitchTap(start), file: file, line: line)
        let mark = try XCTUnwrap(store.registerPitchTap(destination), file: file, line: line)
        XCTAssertFalse(store.isDrawing, file: file, line: line)
        XCTAssertEqual(mark.startTrackAnchor?.playerID, runner.id, file: file, line: line)
        XCTAssertEqual(mark.endTrackAnchor?.playerID, runner.id, file: file, line: line)
        XCTAssertEqual(mark.end, destination, file: file, line: line)
        XCTAssertEqual(mark.revealTime, 15.6, file: file, line: line)
        let resolved = mark.resolvedGeometry(in: store.selectedScenario, at: store.playhead)
        XCTAssertGreaterThanOrEqual(
            resolved.end.x, -ReplayStore.pitchHalfWidth,
            "An on-pitch endpoint must remain on pitch after track-offset reconstruction", file: file, line: line
        )
        XCTAssertEqual(resolved.end.x, destination.x, accuracy: 0.00001, file: file, line: line)
        XCTAssertTrue(
            ReplayStore.isValidReviewMark(mark, for: store.selectedScenario),
            "The Store must not append an annotation that its own saved-review validator rejects", file: file, line: line
        )
        XCTAssertTrue(store.saveReview(named: name), file: file, line: line)
        XCTAssertTrue(store.flushReviewAutosave(), file: file, line: line)

        let reopened = makeStore(at: url)
        defer { _ = reopened.flushReviewAutosave() }
        let saved = reopened.savedReviews.first { $0.name == name }
        XCTAssertNotNil(saved, file: file, line: line)
        if let saved {
            XCTAssertTrue(reopened.restoreSavedReview(id: saved.id), file: file, line: line)
            XCTAssertEqual(reopened.marks.first { $0.id == mark.id }, mark, file: file, line: line)
            XCTAssertEqual(reopened.playhead, mark.revealTime, file: file, line: line)
        }
        XCTAssertTrue(reopened.restoreAutosavedReview(), file: file, line: line)
        XCTAssertEqual(reopened.marks.first { $0.id == mark.id }, mark, file: file, line: line)
        XCTAssertEqual(reopened.playhead, mark.revealTime, file: file, line: line)
        XCTAssertFalse(reopened.isPlaying, file: file, line: line)
    }

    private func makeStoreAtRunnerKnot() throws -> ReplayStore {
        let store = makeStore(at: nil)
        store.seek(to: 15.6)
        XCTAssertEqual(store.selectedScenario.kind, .squadReplay)
        return store
    }

    private func makeStore(at url: URL?) -> ReplayStore {
        let library = ReplayReviewLibrary(scenarios: DemoScenarios.all, fileURL: url)
        let store = ReplayStore(scenarios: DemoScenarios.all, reviewLibrary: library)
        store.prepareForLocalExperience()
        return store
    }

    private func makeURL() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("ReplayAnnotationBoundaryTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        temporaryDirectories.append(directory)
        return directory.appendingPathComponent("reviews.json")
    }
}
