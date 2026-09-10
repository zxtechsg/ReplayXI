import XCTest
@testable import ReplayXI

@MainActor
final class ReplayReviewPersistenceTests: XCTestCase {
    private var temporaryDirectories: [URL] = []

    override func tearDownWithError() throws {
        for directory in temporaryDirectories {
            try FileManager.default.removeItem(at: directory)
        }
        temporaryDirectories.removeAll()
    }

    private func makeURL() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("ReplayReviewTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        temporaryDirectories.append(directory)
        return directory.appendingPathComponent("reviews.json")
    }

    private func library(at url: URL) -> ReplayReviewLibrary {
        ReplayReviewLibrary(scenarios: DemoScenarios.all, fileURL: url)
    }

    private func makeMark(in store: ReplayStore) throws -> CoachMark {
        store.beginDrawing(.pass)
        _ = store.registerPitchTap(PitchPoint(x: 2, z: 3))
        let mark = try XCTUnwrap(store.registerPitchTap(PitchPoint(x: 8, z: 10)))
        store.cancelDrawing()
        return mark
    }

    func testNamedReviewSurvivesRelaunchRenameAndDelete() throws {
        let url = try makeURL()
        let store = ReplayStore(scenarios: DemoScenarios.all, reviewLibrary: library(at: url))
        store.seek(to: 12.5)
        store.setPlaybackRate(2)
        store.setLocalPerspective(store.selectedScenario.awayPlayers[3].id)
        let mark = try makeMark(in: store)
        store.setViewMode(.firstPerson)
        XCTAssertTrue(store.saveReview(named: "  Right-wing return  "))
        let saved = try XCTUnwrap(store.savedReviews.first)
        XCTAssertEqual(saved.name, "Right-wing return")
        XCTAssertTrue(store.renameSavedReview(id: saved.id, name: "Final pass"))

        let restored = ReplayStore(scenarios: DemoScenarios.all, reviewLibrary: library(at: url))
        XCTAssertEqual(restored.savedReviews.first?.name, "Final pass")
        XCTAssertTrue(restored.restoreSavedReview(id: saved.id))
        XCTAssertEqual(restored.playhead, 12.5)
        XCTAssertEqual(restored.playbackRate, 2)
        XCTAssertEqual(restored.localPerspectiveID, store.localPerspectiveID)
        XCTAssertEqual(restored.viewMode, .firstPerson)
        XCTAssertTrue(restored.marks.contains(mark))
        XCTAssertFalse(restored.isPlaying)
        XCTAssertTrue(restored.deleteSavedReview(id: saved.id))
        XCTAssertTrue(library(at: url).savedReviews.isEmpty)
        store.flushReviewAutosave()
        restored.flushReviewAutosave()
    }

    func testAutosaveMasksTimelineAndGeometryPreviewsAndOmitsDrawingState() throws {
        let store = ReplayStore()
        store.seek(to: 5)
        let mark = try makeMark(in: store)
        XCTAssertTrue(store.beginTimelineScrub())
        XCTAssertTrue(store.previewTimelineScrub(to: 18))
        XCTAssertTrue(store.flushReviewAutosave())
        XCTAssertEqual(store.autosavedReview?.state.playhead, 5)
        store.cancelTimelineScrub()

        XCTAssertTrue(store.updateCoachMarkGeometry(
            id: mark.id,
            start: PitchPoint(x: -4, z: 8),
            end: PitchPoint(x: 4, z: 16),
            broadcast: false
        ))
        XCTAssertTrue(store.flushReviewAutosave())
        XCTAssertEqual(store.autosavedReview?.state.marks.first(where: { $0.id == mark.id }), mark)
        XCTAssertFalse(store.saveReview(named: "In progress"))
        XCTAssertTrue(store.cancelCoachMarkGeometryPreview(id: mark.id))
        store.beginDrawing(.run)
        _ = store.registerPitchTap(PitchPoint(x: 10, z: 12))
        XCTAssertTrue(store.flushReviewAutosave())
        XCTAssertEqual(store.autosavedReview?.state.marks.count, store.marks.count)
        store.cancelDrawing()
        XCTAssertTrue(store.restoreAutosavedReview())
        XCTAssertNil(store.pendingDrawStart)
        XCTAssertFalse(store.isDrawing)
        XCTAssertFalse(store.hasActiveTimelineScrub)
        XCTAssertFalse(store.hasActiveCoachMarkGeometryPreview)
    }

    func testAutosaveNeverRestoresRoomAuthorityAnchorsConsentOrRunningState() throws {
        let url = try makeURL()
        let store = ReplayStore(scenarios: DemoScenarios.all, reviewLibrary: library(at: url))
        store.setCollaborationActive(true)
        store.participantSeatAssignments[UUID()] = store.localPerspectiveID
        store.broadcastPerspective(store.selectedScenario.awayPlayers[0].id)
        store.setPlaying(true)
        XCTAssertTrue(store.flushReviewAutosave())
        let json = try String(contentsOf: url, encoding: .utf8)
        for prohibitedKey in ["seatAssignments", "sharedPitchAnchorID", "coachLockEnabled", "isPlaying", "consent", "isCollaborationActive"] {
            XCTAssertFalse(json.contains("\"\(prohibitedKey)\""), prohibitedKey)
        }
        let restored = ReplayStore(scenarios: DemoScenarios.all, reviewLibrary: library(at: url))
        XCTAssertTrue(restored.restoreAutosavedReview())
        XCTAssertFalse(restored.isPlaying)
        XCTAssertFalse(restored.isCollaborationActive)
        XCTAssertFalse(restored.coachLockEnabled)
        XCTAssertNil(restored.coachFocusPerspectiveID)
        XCTAssertNil(restored.sharedPitchAnchorID)
        XCTAssertTrue(restored.participantSeatAssignments.isEmpty)
        XCTAssertFalse(restored.hasLocallyAcknowledgedTrianglePlacement)
        restored.flushReviewAutosave()
    }

    func testScenarioChangesRetainMarksAndSavedReviewRestoresAllVisitedScenarios() throws {
        let store = ReplayStore()
        let firstID = store.selectedScenarioID
        let firstMark = try makeMark(in: store)
        store.seek(to: 9)
        store.selectScenario(id: firstID)
        XCTAssertTrue(store.marks.contains(firstMark), "Tapping the selected scenario must not discard marks")
        XCTAssertEqual(store.playhead, 9)
        let secondID = store.scenarios[1].id
        store.selectScenario(id: secondID)
        let secondMark = try makeMark(in: store)
        XCTAssertTrue(store.saveReview(named: "Two scenarios"))
        let id = try XCTUnwrap(store.savedReviews.first?.id)
        store.selectScenario(id: firstID)
        XCTAssertTrue(store.marks.contains(firstMark))
        store.resetScenario()
        XCTAssertFalse(store.marks.contains(firstMark))
        XCTAssertTrue(store.restoreSavedReview(id: id))
        XCTAssertTrue(store.marks.contains(secondMark))
        store.selectScenario(id: firstID)
        XCTAssertTrue(store.marks.contains(firstMark))
    }

    func testCorruptPrimaryRecoversPreviousValidDocumentAndPreservesDamagedBytes() throws {
        let url = try makeURL()
        let store = ReplayStore(scenarios: DemoScenarios.all, reviewLibrary: library(at: url))
        XCTAssertTrue(store.saveReview(named: "Previous"))
        XCTAssertTrue(store.saveReview(named: "Newest"))
        let damage = Data("broken document".utf8)
        try damage.write(to: url)
        let recovered = library(at: url)
        XCTAssertEqual(recovered.savedReviews.map(\.name), ["Previous"])
        XCTAssertEqual(recovered.status, "Recovered the previous save")
        let preserved = try FileManager.default.contentsOfDirectory(
            at: url.deletingLastPathComponent(), includingPropertiesForKeys: nil
        ).filter { $0.lastPathComponent.hasPrefix("reviews-damaged-") }
        XCTAssertEqual(preserved.count, 1)
        XCTAssertEqual(try Data(contentsOf: XCTUnwrap(preserved.first)), damage)
        XCTAssertEqual(library(at: url).savedReviews.map(\.name), ["Previous"])
    }

    func testNewerSchemaIsReadOnlyAndNeverOverwritten() throws {
        let url = try makeURL()
        let futureData = Data("{\"version\":999,\"futureField\":true}".utf8)
        try futureData.write(to: url)
        let library = library(at: url)
        XCTAssertTrue(library.isReadOnly)
        XCTAssertFalse(library.autosave(ReplayStore().makeSavedReviewState()))
        XCTAssertEqual(try Data(contentsOf: url), futureData)
    }

    func testInvalidRenamePreservesTheReviewAndExplainsTheFailure() throws {
        let library = ReplayReviewLibrary(scenarios: DemoScenarios.all)
        XCTAssertTrue(library.save(named: "Overlap", state: ReplayStore().makeSavedReviewState()))
        let saved = try XCTUnwrap(library.savedReviews.first)
        XCTAssertFalse(library.rename(id: saved.id, name: "Two\nlines"))
        XCTAssertEqual(library.savedReviews.first, saved)
        XCTAssertEqual(library.status, "Use 1–60 characters without line breaks")
    }

    func testMissingPrimaryRecoversBackupAfterInterruptedRecovery() throws {
        let url = try makeURL()
        let library = library(at: url)
        XCTAssertTrue(library.save(named: "First", state: ReplayStore().makeSavedReviewState()))
        XCTAssertTrue(library.save(named: "Second", state: ReplayStore().makeSavedReviewState()))
        try FileManager.default.removeItem(at: url)
        let recovered = self.library(at: url)
        XCTAssertEqual(recovered.savedReviews.map(\.name), ["First"])
        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))
    }

    func testInvalidPlayerGeometryDuplicateMarksAndInvalidNamesCannotBeSaved() throws {
        let store = ReplayStore()
        XCTAssertFalse(store.saveReview(named: "  "))
        XCTAssertFalse(store.saveReview(named: String(repeating: "x", count: 61)))
        XCTAssertFalse(store.saveReview(named: "A\nB"))
        let mark = try makeMark(in: store)
        store.marks.append(mark)
        XCTAssertFalse(store.flushReviewAutosave())
        store.marks = [CoachMark(
            kind: .run, start: PitchPoint(x: 999, z: 0), end: .zero, label: "Outside pitch"
        )]
        XCTAssertFalse(store.flushReviewAutosave())
        store.marks = []
        store.localPerspectiveID = "missing-player"
        XCTAssertFalse(store.flushReviewAutosave())
        XCTAssertNil(store.autosavedReview)
    }

    func testFailedDiskWriteDoesNotClaimSuccessOrMutateSavedList() throws {
        let url = try makeURL()
        try Data("parent is a file".utf8).write(to: url)
        let unavailableURL = url.appendingPathComponent("reviews.json")
        let library = library(at: unavailableURL)
        XCTAssertFalse(library.save(named: "Can't write", state: ReplayStore().makeSavedReviewState()))
        XCTAssertTrue(library.savedReviews.isEmpty)
        XCTAssertNil(library.autosavedReview)
        XCTAssertEqual(library.status, "Save failed. Check device storage.")
    }

    func testRestoreCannotReplaceSharedStateOrActiveGesture() throws {
        let store = ReplayStore()
        XCTAssertTrue(store.saveReview(named: "Baseline"))
        let id = try XCTUnwrap(store.savedReviews.first?.id)
        store.seek(to: 8)
        store.setCollaborationActive(true)
        XCTAssertFalse(store.restoreSavedReview(id: id))
        XCTAssertEqual(store.playhead, 8)
        store.setCollaborationActive(false)
        XCTAssertTrue(store.beginTimelineScrub())
        XCTAssertFalse(store.restoreSavedReview(id: id))
        store.cancelTimelineScrub()
        XCTAssertTrue(store.restoreSavedReview(id: id))
        XCTAssertEqual(store.playhead, 0)
    }

    func testDebouncedAutosavePersistsLatestCommittedSeekWithoutExplicitFlush() async throws {
        let url = try makeURL()
        let store = ReplayStore(scenarios: DemoScenarios.all, reviewLibrary: library(at: url))
        store.seek(to: 5)
        store.seek(to: 12)
        store.setPlaybackRate(1.5)
        try await Task.sleep(for: .milliseconds(850))
        let loaded = library(at: url)
        XCTAssertEqual(loaded.autosavedReview?.state.playhead, 12)
        XCTAssertEqual(loaded.autosavedReview?.state.playbackRate, 1.5)
        XCTAssertTrue(loaded.savedReviews.isEmpty)
        store.flushReviewAutosave()
    }

    func testSaveAndLoadUseTheExactSnapshotChosenBeforeConfirmation() throws {
        let store = ReplayStore()
        store.seek(to: 7)
        let selectedState = store.makeSavedReviewState()
        store.seek(to: 16)
        XCTAssertTrue(store.saveReview(named: "Chosen moment", state: selectedState))
        XCTAssertEqual(store.savedReviews.first?.state.playhead, 7)

        store.flushReviewAutosave()
        let selectedAutosave = try XCTUnwrap(store.autosavedReview)
        store.seek(to: 24)
        store.flushReviewAutosave()
        XCTAssertEqual(store.autosavedReview?.state.playhead, 24)
        XCTAssertTrue(store.restoreReview(selectedAutosave))
        XCTAssertEqual(store.playhead, 16, "Confirmation must load the selected row's snapshot")
        XCTAssertFalse(store.isPlaying)
    }

    func testPassivePlaybackDoesNotRewriteLibraryUntilCommittedPause() async throws {
        let url = try makeURL()
        let store = ReplayStore(scenarios: DemoScenarios.all, reviewLibrary: library(at: url))
        store.setPlaying(true)
        store.flushReviewAutosave()
        let before = try Data(contentsOf: url)
        store.advance(by: 6)
        try await Task.sleep(for: .milliseconds(800))
        XCTAssertEqual(try Data(contentsOf: url), before)
        store.setPlaying(false)
        try await Task.sleep(for: .milliseconds(800))
        XCTAssertEqual(library(at: url).autosavedReview?.state.playhead, 6)
        store.flushReviewAutosave()
    }
}
