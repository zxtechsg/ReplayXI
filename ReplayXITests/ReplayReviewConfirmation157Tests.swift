import XCTest
@testable import ReplayXI

@MainActor
final class ReplayReviewConfirmation157Tests: XCTestCase {
    func testIdentityDistinguishesSameNamesByScenarioAndFractionalPlayhead() throws {
        let (store, first, second) = try fixture()
        XCTAssertEqual(first.name, second.name)
        let a = ReplayReviewConfirmationIdentity(review: first, scenarios: store.scenarios)
        let b = ReplayReviewConfirmationIdentity(review: second, scenarios: store.scenarios)
        XCTAssertEqual(a.reviewID, first.id)
        XCTAssertEqual(b.reviewID, second.id)
        XCTAssertEqual(a.name, first.name)
        XCTAssertEqual(b.name, second.name)
        XCTAssertEqual(a.scenarioTitle, store.scenarios.first { $0.id == first.state.scenarioID }?.title)
        XCTAssertEqual(b.scenarioTitle, store.scenarios.first { $0.id == second.state.scenarioID }?.title)
        XCTAssertNotEqual(a.scenarioTitle, b.scenarioTitle)
        XCTAssertEqual(a.playheadLabel, "00:05.25")
        XCTAssertEqual(b.playheadLabel, "00:07.75")
        XCTAssertEqual(a.metadata, "\(a.scenarioTitle) · 00:05.25")
        XCTAssertEqual(ReplayReviewConfirmationRequest.delete(first.id).target(in: store.savedReviews), first)
        XCTAssertEqual(ReplayReviewConfirmationRequest.restore(second).target(in: store.savedReviews), second)
    }

    func testRowAndTargetShareBoundedHundredthsWithoutChangingSavedTime() throws {
        let (store, first, _) = try fixture()
        let cases: [(TimeInterval, String)] = [(0, "00:00.00"), (5.01, "00:05.01"),
            (5.04, "00:05.04"), (59.999, "01:00.00"), (61.25, "01:01.25")]
        for (time, expected) in cases {
            XCTAssertEqual(ReplayReviewConfirmationIdentity.formattedPlayhead(time), expected)
        }
        for time in [TimeInterval.nan, .infinity, -1] {
            XCTAssertEqual(ReplayReviewConfirmationIdentity.formattedPlayhead(time), "—")
        }
        let before = first.state
        _ = ReplayReviewConfirmationIdentity(review: first, scenarios: store.scenarios)
        XCTAssertEqual(first.state, before)
        XCTAssertEqual(first.state.playhead, 5.25)
    }

    func testDeleteResolvesLiveUUIDAfterRenameAndDeletesOnlyThatReview() throws {
        let (store, first, second) = try fixture()
        let request = ReplayReviewConfirmationRequest.delete(first.id)
        let before = store.makeSavedReviewState(), autosave = store.autosavedReview
        XCTAssertTrue(store.renameSavedReview(id: first.id, name: "Renamed pending target"))
        let target = try XCTUnwrap(request.target(in: store.savedReviews))
        XCTAssertEqual(target.id, first.id)
        XCTAssertEqual(target.name, "Renamed pending target")
        XCTAssertEqual(ReplayReviewConfirmationIdentity(review: target, scenarios: store.scenarios).name, target.name)
        XCTAssertTrue(request.confirm(in: store))
        XCTAssertEqual(store.savedReviews.map(\.id), [second.id])
        XCTAssertEqual(store.savedReviews.first, second)
        XCTAssertEqual(store.makeSavedReviewState(), before)
        XCTAssertEqual(store.autosavedReview, autosave)
        XCTAssertNil(request.target(in: store.savedReviews))
        XCTAssertFalse(request.confirm(in: store), "A missing UUID must not fall back to a same-name neighbour")
        XCTAssertEqual(store.savedReviews, [second])
    }

    func testRestoreKeepsCapturedSnapshotEvenIfNamedEntryChangesOrDisappears() throws {
        let (store, first, second) = try fixture()
        let request = ReplayReviewConfirmationRequest.restore(first)
        XCTAssertTrue(store.renameSavedReview(id: first.id, name: "Renamed after Load was chosen"))
        XCTAssertEqual(request.target(in: store.savedReviews), first)
        XCTAssertTrue(store.deleteSavedReview(id: first.id))
        XCTAssertEqual(request.target(in: store.savedReviews), first,
                       "Load has always retained the chosen value, unlike live-UUID Delete")
        store.seek(to: 10, broadcast: false)
        store.setPlaying(true, broadcast: false)
        XCTAssertTrue(request.confirm(in: store))
        XCTAssertEqual(store.makeSavedReviewState(), first.state)
        XCTAssertFalse(store.isPlaying)
        XCTAssertEqual(store.savedReviews, [second])
        XCTAssertTrue(store.flushReviewAutosave())
    }

    func testLastSessionConfirmationIdentityDoesNotFollowLaterAutosave() throws {
        let (store, _, _) = try fixture()
        store.seek(to: 3.125, broadcast: false)
        XCTAssertTrue(store.flushReviewAutosave())
        let chosen = try XCTUnwrap(store.autosavedReview)
        let request = ReplayReviewConfirmationRequest.restore(chosen)
        store.seek(to: 8.5, broadcast: false)
        XCTAssertTrue(store.flushReviewAutosave())
        XCTAssertEqual(store.autosavedReview?.id, chosen.id)
        XCTAssertNotEqual(store.autosavedReview?.state, chosen.state)
        let shown = try XCTUnwrap(request.target(in: store.savedReviews))
        XCTAssertEqual(shown, chosen)
        XCTAssertEqual(ReplayReviewConfirmationIdentity(review: shown, scenarios: store.scenarios).name, "Last session")
        XCTAssertEqual(ReplayReviewConfirmationIdentity(review: shown, scenarios: store.scenarios).playheadLabel, "00:03.13")
        XCTAssertTrue(request.confirm(in: store))
        XCTAssertEqual(store.makeSavedReviewState(), chosen.state)
        XCTAssertTrue(store.flushReviewAutosave())
    }

    func testResolvingAndCancellingPendingTargetDoesNotWriteOrMutateReplay() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("ReviewConfirmation157-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("reviews.json")
        let library = ReplayReviewLibrary(scenarios: DemoScenarios.all, fileURL: url)
        let store = ReplayStore(scenarios: DemoScenarios.all, reviewLibrary: library)
        store.seek(to: 5.25, broadcast: false)
        XCTAssertTrue(store.flushReviewAutosave())
        XCTAssertTrue(store.saveReview(named: "Target to keep"))
        let review = try XCTUnwrap(store.savedReviews.first)
        let before = store.makeSnapshot(), reviews = store.savedReviews, autosave = store.autosavedReview
        let bytes = try Data(contentsOf: url)
        library.resetPersistenceWorkForTesting()
        for request in [ReplayReviewConfirmationRequest.delete(review.id), .restore(review)] {
            var pending: ReplayReviewConfirmationRequest? = request
            let target = try XCTUnwrap(pending?.target(in: store.savedReviews))
            _ = ReplayReviewConfirmationIdentity(review: target, scenarios: store.scenarios)
            pending = nil // The production Cancel closure clears only its local action.
            XCTAssertNil(pending)
            XCTAssertEqual(store.makeSnapshot(), before)
            XCTAssertEqual(store.savedReviews, reviews)
            XCTAssertEqual(store.autosavedReview, autosave)
            XCTAssertEqual(try Data(contentsOf: url), bytes)
        }
        XCTAssertEqual(library.persistenceWork.documentEncoding.calls, 0)
        XCTAssertEqual(library.persistenceWork.primaryWrite.calls, 0)
    }

    func testProductionConfirmationKeepsBoundedScrollAndExistingCancelAnd60PointActions() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        let source = try String(contentsOf: root.appendingPathComponent(
            "ReplayXI/UI/ReplayReviewLibraryView.swift"), encoding: .utf8)
        XCTAssertTrue(source.contains("confirmation(.delete(id))"))
        XCTAssertTrue(source.contains("confirmation(.restore(review))"))
        XCTAssertTrue(source.contains("cancel: { action = nil }, confirm:"))
        XCTAssertTrue(source.contains("request.target(in: store.savedReviews)"))
        XCTAssertTrue(source.contains("request.confirm(in: store)"))
        XCTAssertTrue(source.contains(".frame(height: layout.contentHeight)"))
        XCTAssertTrue(source.contains(".id(action == nil)"))
        XCTAssertTrue(source.contains("Button(\"Cancel\", action: cancel).frame(minHeight: 60)"))
        XCTAssertTrue(source.contains(".disabled(targetIsUnavailable)"))
        let identityStart = try XCTUnwrap(source.range(of: "if let target {")?.lowerBound)
        let identityEnd = try XCTUnwrap(source.range(of: "Text(detail)", range: identityStart..<source.endIndex)?.lowerBound)
        let identity = source[identityStart..<identityEnd]
        XCTAssertTrue(identity.contains("Text(target.name)"))
        XCTAssertTrue(identity.contains("Text(target.metadata)"))
        XCTAssertFalse(identity.contains(".lineLimit("), "The target must be readable, not silently truncated")
        XCTAssertTrue(source.contains("ReplayReviewConfirmationIdentity.formattedPlayhead(playhead)"),
                      "Review rows and captured-moment copy must share the confirmation timestamp format")
    }

    private func fixture() throws -> (ReplayStore, SavedReplayReview, SavedReplayReview) {
        let store = ReplayStore()
        store.prepareForLocalExperience()
        store.seek(to: 5.25, broadcast: false)
        XCTAssertTrue(store.saveReview(named: "Same review name"))
        let first = try XCTUnwrap(store.savedReviews.first)
        let other = try XCTUnwrap(store.scenarios.first { $0.id != first.state.scenarioID })
        store.selectScenario(id: other.id)
        store.seek(to: 7.75, broadcast: false)
        XCTAssertTrue(store.saveReview(named: "Same review name"))
        let second = try XCTUnwrap(store.savedReviews.first { $0.id != first.id })
        XCTAssertTrue(store.flushReviewAutosave())
        return (store, first, second)
    }
}
