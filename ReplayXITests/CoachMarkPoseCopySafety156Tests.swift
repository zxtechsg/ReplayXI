import Foundation
import XCTest
@testable import ReplayXI

@MainActor
final class CoachMarkPoseCopySafety156Tests: XCTestCase {
    private var temporaryDirectories: [URL] = []

    override func tearDownWithError() throws {
        for directory in temporaryDirectories { try FileManager.default.removeItem(at: directory) }
        temporaryDirectories.removeAll()
    }

    func testEveryGeometryOwnerAndTimelineScrubRejectCopyWithoutChangingStateOrDisk() throws {
        for route in 0..<5 {
            let (store, url, source, other) = try fixture()
            defer { store.flushReviewAutosave() }
            // Keep a real redo entry: blocked copies must not erase its branch.
            XCTAssertTrue(store.nudgeCoachMarkCurve(id: source.id, bendDelta: 0.25, liftDelta: 0))
            XCTAssertTrue(store.undoAnnotationEdit())
            XCTAssertTrue(store.canRedoAnnotationEdit)
            store.setPlaying(true, broadcast: false)
            let original = store.marks, token = UUID()
            switch route {
            case 0:
                XCTAssertTrue(store.previewCoachMarkCurve(id: source.id, gestureID: token,
                    curve: .init(bend: 2, lift: 1)))
            case 1:
                XCTAssertNotNil(store.previewCoachMarkEndpoint(id: source.id, endpoint: .end,
                    gestureID: token, cumulativeDelta: .init(x: 0.5, z: 0.25)))
            case 2:
                XCTAssertTrue(store.previewCoachMarkHandle(id: source.id, endpoint: .end,
                    gestureID: token, point: .init(x: 5, z: 6)))
            case 3:
                XCTAssertTrue(store.updateCoachMarkGeometry(id: source.id, start: source.start,
                    end: .init(x: 5, z: 6), broadcast: false))
            default:
                XCTAssertTrue(store.beginTimelineScrub())
                XCTAssertTrue(store.previewTimelineScrub(to: 6))
            }
            try assertRejectedWithoutMutation(store, ids: [source.id, other.id], url: url)
            switch route {
            case 0:
                XCTAssertTrue(store.isCoachMarkCurvePreviewOwner(id: source.id, gestureID: token))
                XCTAssertTrue(store.cancelCoachMarkCurvePreview(id: source.id, gestureID: token))
            case 1:
                XCTAssertEqual(store.activeCoachMarkEndpointPreviewOwner?.markID, source.id)
                XCTAssertTrue(store.cancelCoachMarkEndpointPreview(id: source.id, gestureID: token))
            case 2:
                XCTAssertTrue(store.isCoachMarkHandlePreviewOwner(id: source.id, gestureID: token))
                XCTAssertTrue(store.cancelCoachMarkHandlePreview(id: source.id, gestureID: token))
            case 3:
                XCTAssertTrue(store.cancelCoachMarkGeometryPreview(id: source.id))
            default:
                XCTAssertTrue(store.hasActiveTimelineScrub)
                store.cancelTimelineScrub()
                XCTAssertEqual(store.playhead, 3)
                XCTAssertTrue(store.isPlaying)
            }
            XCTAssertEqual(store.marks, original)
            XCTAssertTrue(store.canCopyCoachMarkPose(id: other.id))
            XCTAssertTrue(store.redoAnnotationEdit(), "The pre-existing redo entry survives every rejected route")
        }
    }

    func testDirtyTimingTextBlocksBothSourceAndOtherCopiesWithoutDiscardingDraft() throws {
        let (store, url, source, other) = try fixture()
        defer { store.flushReviewAutosave() }
        store.setPlaying(true, broadcast: false)
        let session = AnnotationTimingDraftSession()
        XCTAssertTrue(session.begin(mark: source, scenarioID: store.selectedScenarioID,
            duration: store.selectedScenario.duration, store: store))
        session.window.startText = "1:"
        XCTAssertTrue(session.hasUnsavedChanges)
        XCTAssertEqual(store.pendingAnnotationTimingEditID, source.id)
        try assertRejectedWithoutMutation(store, ids: [source.id, other.id], url: url)
        XCTAssertEqual(session.window.startText, "1:")
        XCTAssertTrue(session.hasUnsavedChanges)
        XCTAssertEqual(session.markID, source.id)
        XCTAssertEqual(store.pendingAnnotationTimingEditID, source.id)
        XCTAssertTrue(store.isPlaying, "A rejected copy must not pause playback")
        session.discard(in: store)
        XCTAssertNil(store.pendingAnnotationTimingEditID)
        XCTAssertTrue(store.canCopyCoachMarkPose(id: source.id))
    }

    func testDrawingAndPhysicalPlacementKeepTheirExactOwnersWhenCopyIsRejected() throws {
        let (store, url, source, other) = try fixture()
        defer { store.flushReviewAutosave() }
        store.beginDrawing(.run)
        XCTAssertNil(store.registerPitchTap(.init(x: 12, z: 18)))
        XCTAssertTrue(store.isDrawing)
        try assertRejectedWithoutMutation(store, ids: [source.id, other.id], url: url)
        XCTAssertEqual(store.pendingDrawStart, .init(x: 12, z: 18))
        store.cancelDrawing()
        XCTAssertTrue(store.canCopyCoachMarkPose(id: source.id))

        let shape = try XCTUnwrap(DemoScenarios.all.first { $0.kind == .shapeLab })
        let (placed, placementURL, placedSource, placedOther) = try fixture(scenarios: [shape])
        defer { placed.flushReviewAutosave() }
        let anchor = UUID()
        XCTAssertTrue(placed.activateLocalTrianglePreview(anchorID: anchor))
        let savedAnchor = placed.sharedPitchAnchorID
        let consent = placed.hasLocallyAcknowledgedTrianglePlacement
        try assertRejectedWithoutMutation(placed, ids: [placedSource.id, placedOther.id], url: placementURL)
        XCTAssertEqual(placed.triangleLockMode, .place)
        XCTAssertTrue(placed.isLocalTrianglePreview)
        XCTAssertEqual(placed.sharedPitchAnchorID, savedAnchor)
        XCTAssertEqual(placed.hasLocallyAcknowledgedTrianglePlacement, consent)
        placed.endTrianglePlacement()
        XCTAssertTrue(placed.canCopyCoachMarkPose(id: placedSource.id))
    }

    func testFiveStudyPresentedCopiesKeepNewIDsThroughDiskRoundTripAndOneUndoRedo() throws {
        let scenarios = FootballReferenceScenarios.all
        XCTAssertEqual(scenarios.count, 5)
        let url = try makeURL()
        let store = ReplayStore(scenarios: scenarios,
            reviewLibrary: ReplayReviewLibrary(scenarios: scenarios, fileURL: url))
        defer { store.flushReviewAutosave() }
        var copyIDs = Set<UUID>()
        for scenario in scenarios {
            store.selectScenario(id: scenario.id, broadcast: false)
            store.seek(to: min(3, scenario.duration / 2), broadcast: false)
            let player = try XCTUnwrap(scenario.players.first {
                let p = $0.presentationPose(at: store.playhead).position
                return abs(p.x) < 20 && abs(p.z) < 35
            })
            let source = CoachMark(kind: .arc, start: .init(x: 10, z: 10), end: .init(x: 13, z: 14),
                startElevation: 0.7, endElevation: 1.2, curve: .init(bend: 1, lift: 0.5, rollDegrees: 30),
                label: "Copy disk fixture", revealTime: 0, hideTime: 1, author: "Original author",
                startTrackAnchor: .init(playerID: player.id, offset: .zero),
                endTrackAnchor: .init(playerID: player.id, offset: .init(x: 3, z: 4)))
            XCTAssertTrue(store.appendRemoteCoachMark(source))
            XCTAssertFalse(source.isVisible(at: store.playhead))
            for view: ReplayViewMode in [.tacticalTable, .firstPerson, .touchline] {
                store.setViewMode(view)
                let position = store.presentedPlayerPose(for: player, at: store.playhead).position
                let expectedEnd = PitchPoint(x: position.x + 3, z: position.z + 4)
                let before = store.marks, playhead = store.playhead
                store.setPlaying(true, broadcast: false)
                XCTAssertTrue(store.canCopyCoachMarkPose(id: source.id))
                let copy = try XCTUnwrap(store.copyCoachMarkPose(id: source.id))
                XCTAssertTrue(copyIDs.insert(copy.id).inserted)
                XCTAssertNotEqual(copy.id, source.id)
                XCTAssertEqual(copy.start, position)
                XCTAssertEqual(copy.end, expectedEnd)
                XCTAssertEqual(copy.startElevation, source.startElevation)
                XCTAssertEqual(copy.endElevation, source.endElevation)
                XCTAssertEqual(copy.curve, source.resolvedCurve.stabilized(start: position, end: expectedEnd))
                XCTAssertEqual(copy.author, "Coach")
                XCTAssertEqual(copy.revealTime, playhead)
                XCTAssertEqual(copy.hideTime, CoachMarkTimingPolicy.defaultHideTime(
                    revealTime: playhead, replayDuration: scenario.duration))
                XCTAssertNil(copy.startTrackAnchor)
                XCTAssertNil(copy.endTrackAnchor)
                XCTAssertNil(copy.keyframes)
                XCTAssertNil(copy.playerID)
                XCTAssertEqual(store.marks.first { $0.id == source.id }, source)
                XCTAssertFalse(store.isPlaying)
                XCTAssertEqual(store.playhead, playhead)
                let after = store.marks
                XCTAssertTrue(store.flushReviewAutosave())
                XCTAssertEqual(ReplayReviewLibrary(scenarios: scenarios, fileURL: url).autosavedReview?.state.marks, after)
                XCTAssertTrue(store.undoAnnotationEdit())
                XCTAssertEqual(store.marks, before, "One Undo removes only this copy")
                XCTAssertTrue(store.flushReviewAutosave())
                XCTAssertEqual(ReplayReviewLibrary(scenarios: scenarios, fileURL: url).autosavedReview?.state.marks, before)
                XCTAssertTrue(store.redoAnnotationEdit())
                XCTAssertEqual(store.marks, after, "Redo retains the same new ID and fixed pose")
                XCTAssertFalse(store.canRedoAnnotationEdit)
            }
        }
        XCTAssertEqual(copyIDs.count, 15)
        let expected = store.makeSavedReviewState()
        XCTAssertTrue(store.saveReview(named: "Five studies copied poses"))
        XCTAssertTrue(store.flushReviewAutosave())
        let reopened = ReplayReviewLibrary(scenarios: scenarios, fileURL: url)
        XCTAssertEqual(reopened.autosavedReview?.state, expected)
        XCTAssertEqual(reopened.savedReviews.first?.state, expected)
        let restored = ReplayStore(scenarios: scenarios, reviewLibrary: reopened)
        defer { restored.flushReviewAutosave() }
        XCTAssertTrue(restored.restoreAutosavedReview())
        XCTAssertEqual(restored.makeSavedReviewState(), expected)
        for scenario in scenarios {
            restored.selectScenario(id: scenario.id, broadcast: false)
            XCTAssertEqual(restored.marks, expected.marksByScenario[scenario.id])
        }
    }

    private func assertRejectedWithoutMutation(_ store: ReplayStore, ids: [UUID], url: URL,
                                               file: StaticString = #filePath, line: UInt = #line) throws {
        XCTAssertTrue(store.flushReviewAutosave(), file: file, line: line)
        let bytes = try Data(contentsOf: url)
        let live = store.marks, saved = store.makeSavedReviewState(), snapshot = store.makeSnapshot()
        let time = store.playhead, playing = store.isPlaying, localPause = store.isLocallyPaused
        let undo = store.annotationUndoTitle, redo = store.annotationRedoTitle
        let history = store.hasAnnotationEditHistory, index = store.reviewIndexVersion
        let scrubID = store.activeTimelineScrubID, endpoint = store.activeCoachMarkEndpointPreviewOwner
        let drawing = store.isDrawing, drawStart = store.pendingDrawStart
        let pending = store.pendingAnnotationTimingEditID
        var broadcasts = 0
        store.onBroadcastSnapshot = { _ in broadcasts += 1 }
        defer { store.onBroadcastSnapshot = nil }
        for id in ids {
            let status = store.statusMessage, attempts = store.annotationTimingNavigationAttempt
            for _ in 0..<3 { XCTAssertFalse(store.canCopyCoachMarkPose(id: id), file: file, line: line) }
            XCTAssertEqual(store.statusMessage, status, "Capability checks are pure", file: file, line: line)
            XCTAssertEqual(store.annotationTimingNavigationAttempt, attempts, file: file, line: line)
            XCTAssertNil(store.copyCoachMarkPose(id: id), file: file, line: line)
        }
        XCTAssertEqual(store.marks, live, file: file, line: line)
        XCTAssertEqual(store.makeSavedReviewState(), saved, file: file, line: line)
        XCTAssertEqual(store.makeSnapshot(), snapshot, file: file, line: line)
        XCTAssertEqual(store.playhead, time, file: file, line: line)
        XCTAssertEqual(store.isPlaying, playing, file: file, line: line)
        XCTAssertEqual(store.isLocallyPaused, localPause, file: file, line: line)
        XCTAssertEqual(store.annotationUndoTitle, undo, file: file, line: line)
        XCTAssertEqual(store.annotationRedoTitle, redo, file: file, line: line)
        XCTAssertEqual(store.hasAnnotationEditHistory, history, file: file, line: line)
        XCTAssertEqual(store.reviewIndexVersion, index, file: file, line: line)
        XCTAssertEqual(store.activeTimelineScrubID, scrubID, file: file, line: line)
        XCTAssertEqual(store.activeCoachMarkEndpointPreviewOwner, endpoint, file: file, line: line)
        XCTAssertEqual(store.isDrawing, drawing, file: file, line: line)
        XCTAssertEqual(store.pendingDrawStart, drawStart, file: file, line: line)
        XCTAssertEqual(store.pendingAnnotationTimingEditID, pending, file: file, line: line)
        XCTAssertNil(store.scheduledReviewAutosaveID, file: file, line: line)
        XCTAssertEqual(broadcasts, 0, file: file, line: line)
        XCTAssertTrue(store.flushReviewAutosave(), file: file, line: line)
        XCTAssertEqual(try Data(contentsOf: url), bytes, file: file, line: line)
    }

    private func fixture(scenarios suppliedScenarios: [ReplayScenario]? = nil) throws -> (ReplayStore, URL, CoachMark, CoachMark) {
        let scenarios = suppliedScenarios ?? DemoScenarios.all
        let url = try makeURL()
        let store = ReplayStore(scenarios: scenarios,
            reviewLibrary: ReplayReviewLibrary(scenarios: scenarios, fileURL: url))
        store.seek(to: 3, broadcast: false)
        let source = CoachMark(kind: .arc, start: .zero, end: .init(x: 4, z: 6),
                               curve: .init(bend: 1, lift: 0), label: "Owned source")
        let other = CoachMark(kind: .run, start: .init(x: 8, z: 10), end: .init(x: 12, z: 16),
                              label: "Unrelated source")
        XCTAssertTrue(store.appendRemoteCoachMark(source))
        XCTAssertTrue(store.appendRemoteCoachMark(other))
        XCTAssertTrue(store.flushReviewAutosave())
        return (store, url, source, other)
    }

    private func makeURL() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("ReplayXI-CopySafety156-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        temporaryDirectories.append(directory)
        return directory.appendingPathComponent("reviews.json")
    }
}
