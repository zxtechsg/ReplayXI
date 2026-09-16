import XCTest
@testable import ReplayXI

@MainActor
final class ReplayReviewSaveFeedbackTests: XCTestCase {
    func testDraftSaveBlockIsVisibleAndKeepsTheChosenSnapshot() throws {
        let (store, mark, chosenState) = try fixture()
        let start = PitchPoint(x: 12, z: 14)
        store.beginDrawing(.run)
        XCTAssertNil(store.registerPitchTap(start))

        assertBlockedSave(
            store, chosenState: chosenState,
            reason: "Finish or cancel the annotation before saving"
        )
        XCTAssertTrue(store.isDrawing)
        XCTAssertEqual(store.pendingDrawStart, start)
        XCTAssertEqual(store.marks.first { $0.id == mark.id }, mark)

        store.cancelDrawing()
        assertSaveCanContinue(store, chosenState: chosenState)
    }

    func testTimelineSaveBlockIsVisibleWithoutDiscardingTheScrub() throws {
        let (store, _, chosenState) = try fixture()
        XCTAssertTrue(store.beginTimelineScrub())
        XCTAssertTrue(store.previewTimelineScrub(to: 18))

        assertBlockedSave(
            store, chosenState: chosenState,
            reason: "Finish or cancel the timeline scrub before saving"
        )
        XCTAssertTrue(store.hasActiveTimelineScrub)
        XCTAssertEqual(store.playhead, 18)
        XCTAssertEqual(store.makeSavedReviewState().playhead, chosenState.playhead)

        store.cancelTimelineScrub()
        assertSaveCanContinue(store, chosenState: chosenState)
    }

    func testDirectHandleSaveBlockIsVisibleAndDoesNotPublishPreviewGeometry() throws {
        let (store, mark, chosenState) = try fixture()
        XCTAssertTrue(store.updateCoachMarkGeometry(
            id: mark.id, start: PitchPoint(x: -4, z: 8),
            end: PitchPoint(x: 4, z: 16), broadcast: false
        ))
        let preview = store.marks

        assertBlockedSave(
            store, chosenState: chosenState,
            reason: "Finish or cancel the annotation adjustment before saving"
        )
        XCTAssertTrue(store.hasActiveCoachMarkGeometryPreview)
        XCTAssertEqual(store.marks, preview)
        XCTAssertNotEqual(store.marks.first { $0.id == mark.id }, mark)
        XCTAssertEqual(store.makeSavedReviewState().marks.first { $0.id == mark.id }, mark)

        XCTAssertTrue(store.cancelCoachMarkGeometryPreview(id: mark.id))
        assertSaveCanContinue(store, chosenState: chosenState)
    }

    func testJoystickSaveBlockIsVisibleAndKeepsTheGestureOwner() throws {
        let (store, mark, chosenState) = try fixture()
        let gestureID = UUID()
        XCTAssertNotNil(store.previewCoachMarkEndpoint(
            id: mark.id, endpoint: .end, gestureID: gestureID,
            cumulativeDelta: PitchPoint(x: 0.5, z: 0.5)
        ))
        let preview = store.marks

        assertBlockedSave(
            store, chosenState: chosenState,
            reason: "Finish or cancel the annotation adjustment before saving"
        )
        XCTAssertTrue(store.hasActiveCoachMarkEndpointPreview)
        XCTAssertEqual(store.activeCoachMarkEndpointPreviewOwner?.markID, mark.id)
        XCTAssertEqual(store.marks, preview)
        XCTAssertEqual(store.makeSavedReviewState().marks.first { $0.id == mark.id }, mark)

        XCTAssertTrue(store.cancelCoachMarkEndpointPreview(id: mark.id, gestureID: gestureID))
        assertSaveCanContinue(store, chosenState: chosenState)
    }

    func testFullLibraryExplainsCapacityRatherThanClaimingAnEditIsActive() throws {
        let (store, _, chosenState) = try fixture()
        XCTAssertEqual(ReplayReviewLibrary.maximumSavedReviews, 40)
        for index in 1..<ReplayReviewLibrary.maximumSavedReviews {
            XCTAssertTrue(store.saveReview(named: "Review \(index)", state: chosenState))
        }
        XCTAssertEqual(store.savedReviews.count, 40)
        XCTAssertTrue(store.canChangePlaybackView)

        assertBlockedSave(
            store, chosenState: chosenState,
            reason: "40 saves reached. Delete a save first."
        )
        let removableID = try XCTUnwrap(store.savedReviews.last?.id)
        XCTAssertTrue(store.deleteSavedReview(id: removableID))
        XCTAssertTrue(store.canSaveReview)
        XCTAssertTrue(store.saveReview(named: "Replacement", state: chosenState))
        XCTAssertEqual(store.savedReviews.count, 40)
        XCTAssertEqual(store.savedReviews.first?.name, "Replacement")
        XCTAssertEqual(store.savedReviews.first?.state, chosenState)
    }

    func testReadOnlySaveBlockKeepsTheSpecificLibraryDiagnosticAndBytes() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("ReplaySaveFeedback-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("reviews.json")
        let futureData = Data("{\"version\":999,\"futureField\":true}".utf8)
        try futureData.write(to: url)
        let library = ReplayReviewLibrary(scenarios: DemoScenarios.all, fileURL: url)
        let store = ReplayStore(scenarios: DemoScenarios.all, reviewLibrary: library)

        XCTAssertTrue(library.isReadOnly)
        XCTAssertEqual(library.status, "Saves need a newer app version")
        assertBlockedSave(
            store, chosenState: store.makeSavedReviewState(),
            reason: "Saves need a newer app version"
        )
        XCTAssertEqual(try Data(contentsOf: url), futureData)
    }

    func testIdleAndOpenRoomNamedSavesRemainAvailable() throws {
        let (store, _, chosenState) = try fixture()
        XCTAssertTrue(store.canSaveReview)
        XCTAssertEqual(store.reviewSaveStatus, "Review saved · saves are temporary")
        let requestID = try XCTUnwrap(store.beginImmersiveOpen())
        XCTAssertEqual(store.immersiveRoomDidAppear(requestID), requestID)
        XCTAssertTrue(store.completeImmersiveOpen(requestID, opened: true))
        XCTAssertTrue(store.canSaveReview)
        XCTAssertTrue(store.saveReview(named: "Open room", state: chosenState))
        XCTAssertEqual(store.savedReviews.first?.state, chosenState)
        XCTAssertEqual(store.reviewSaveStatus, "Review saved · saves are temporary")
    }

    func testDrawerUsesSharedSaveFeedbackWithoutDisablingCancelOrRecapturingTheMoment() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        let source = try String(
            contentsOf: root.appendingPathComponent("ReplayXI/UI/ReplayReviewLibraryView.swift"),
            encoding: .utf8
        )
        XCTAssertTrue(source.contains("Text(store.reviewSaveStatus)"))
        XCTAssertTrue(source.contains("store.reviewSaveBlockReason == nil ? Color.secondary : ReplayTheme.orange"))
        XCTAssertTrue(source.contains(".accessibilityHint(store.reviewSaveBlockReason ??"))
        XCTAssertTrue(source.contains("pendingSaveState = store.makeSavedReviewState()"))
        XCTAssertTrue(source.contains("store.saveReview(named: reviewName, state: pendingSaveState)"))
        XCTAssertTrue(source.contains("Button(\"Cancel\") { self.action = nil }.frame(minHeight: 60)"))
    }

    private func fixture() throws -> (ReplayStore, CoachMark, SavedReplayState) {
        let store = ReplayStore()
        store.prepareForLocalExperience()
        store.seek(to: 5, broadcast: false)
        store.beginDrawing(.pass)
        XCTAssertNil(store.registerPitchTap(PitchPoint(x: 2, z: 3)))
        let mark = try XCTUnwrap(store.registerPitchTap(PitchPoint(x: 8, z: 10)))
        let chosenState = store.makeSavedReviewState()
        XCTAssertTrue(store.saveReview(named: "Existing review", state: chosenState))
        XCTAssertEqual(store.reviewLibrary.status, "Review saved")
        return (store, mark, chosenState)
    }

    private func assertBlockedSave(
        _ store: ReplayStore,
        chosenState: SavedReplayState,
        reason: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let before = store.savedReviews
        XCTAssertFalse(store.canSaveReview, file: file, line: line)
        XCTAssertEqual(store.reviewSaveStatus, reason, "The drawer must explain the current block, not show an older success", file: file, line: line)
        XCTAssertFalse(store.saveReview(named: "Blocked copy", state: chosenState), file: file, line: line)
        XCTAssertEqual(store.statusMessage, reason, file: file, line: line)
        XCTAssertEqual(store.reviewSaveStatus, reason, file: file, line: line)
        XCTAssertEqual(store.savedReviews, before, file: file, line: line)
    }

    private func assertSaveCanContinue(
        _ store: ReplayStore,
        chosenState: SavedReplayState,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertTrue(store.canSaveReview, file: file, line: line)
        XCTAssertTrue(store.saveReview(named: "Chosen copy", state: chosenState), file: file, line: line)
        XCTAssertEqual(store.savedReviews.first?.state, chosenState, file: file, line: line)
        XCTAssertEqual(store.savedReviews.count, 2, file: file, line: line)
        XCTAssertEqual(store.reviewSaveStatus, "Review saved · saves are temporary", file: file, line: line)
    }
}
