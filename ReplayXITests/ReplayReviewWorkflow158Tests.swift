import XCTest
@testable import ReplayXI

/// One local review across the actual transport, POV, annotation and disk APIs.
@MainActor
final class ReplayReviewWorkflow158Tests: XCTestCase {
    func testScrubPOVKeyframedArcAndWindowSurviveSaveAndRelaunch() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("ReplayXI-workflow-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("reviews.json")
        let scenarios = FootballReferenceScenarios.all
        let scenario = try XCTUnwrap(scenarios.first { $0.id == "final-108-rebound-v2" })
        let store = ReplayStore(scenarios: scenarios,
                                reviewLibrary: ReplayReviewLibrary(scenarios: scenarios, fileURL: url))
        store.selectScenario(id: scenario.id)
        let opponent = try XCTUnwrap(scenario.awayPlayers.first)
        store.openLocalPlayerPOV(opponent.id)
        store.seek(to: 1)

        store.beginDrawing(.arc)
        XCTAssertNil(store.registerPitchTap(.init(x: 0, z: 0)))
        let initial = try XCTUnwrap(store.registerPitchTap(.init(x: 8, z: 10)))
        XCTAssertFalse(store.isDrawing)
        XCTAssertTrue(store.captureCoachMarkKeyframe(id: initial.id))
        store.seek(to: 2)
        XCTAssertTrue(store.updateCoachMarkGeometry(id: initial.id,
            start: .init(x: 2, z: 0), end: .init(x: 10, z: 10)))
        XCTAssertTrue(store.setCoachMarkWindow(id: initial.id, start: 1, end: 3))
        let authored = try XCTUnwrap(store.marks.first { $0.id == initial.id })
        XCTAssertEqual(authored.keyframes?.map(\.time), [1, 2])
        XCTAssertEqual(authored.revealTime, 1)
        XCTAssertEqual(authored.hideTime, 3)

        XCTAssertTrue(store.beginTimelineScrub())
        XCTAssertTrue(store.previewTimelineScrub(to: 1.5))
        XCTAssertTrue(store.commitTimelineScrub(to: 1.5))
        XCTAssertEqual(store.playhead, 1.5)
        XCTAssertEqual(store.viewMode, .firstPerson)
        XCTAssertEqual(store.activePerspectiveID, opponent.id)
        let midpoint = authored.sampled(at: store.playhead)
        XCTAssertTrue(store.saveReview(named: "Rebound arc review"))
        let savedID = try XCTUnwrap(store.savedReviews.first?.id)
        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))

        let relaunched = ReplayStore(scenarios: scenarios,
            reviewLibrary: ReplayReviewLibrary(scenarios: scenarios, fileURL: url))
        XCTAssertTrue(relaunched.restoreSavedReview(id: savedID))
        XCTAssertEqual(relaunched.selectedScenarioID, scenario.id)
        XCTAssertEqual(relaunched.playhead, 1.5)
        XCTAssertEqual(relaunched.viewMode, .firstPerson)
        XCTAssertEqual(relaunched.activePerspectiveID, opponent.id)
        XCTAssertFalse(relaunched.isPlaying)
        XCTAssertFalse(relaunched.hasActiveTimelineScrub)
        let restored = try XCTUnwrap(relaunched.marks.first { $0.id == initial.id })
        XCTAssertEqual(restored, authored)
        XCTAssertEqual(restored.sampled(at: 1.5), midpoint)
        XCTAssertEqual(restored.sampled(at: 1), authored.sampled(at: 1))
        XCTAssertEqual(restored.sampled(at: 2), authored.sampled(at: 2))
    }
}
