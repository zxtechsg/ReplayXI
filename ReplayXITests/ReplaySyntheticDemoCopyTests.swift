import XCTest
@testable import ReplayXI

@MainActor
final class ReplaySyntheticDemoCopyTests: XCTestCase {
    func testVisibleTitleAndObjectiveIdentifyAnAuthoredSyntheticDemo() throws {
        let replay = try syntheticReplay()

        // Home reads these values directly; its nearby notice already says
        // “Demo match · no video loaded.” Keep the main heading consistent.
        XCTAssertEqual(replay.title, "Synthetic match replay")
        XCTAssertTrue(replay.matchContext.contains("AUTHORED PLAYER PATHS"))
        XCTAssertTrue(replay.objective.lowercased().contains("authored"))
        XCTAssertTrue(replay.objective.lowercased().contains("not recovered from video"))
        XCTAssertEqual(ReplayAppMode(scenario: replay), .matchReplay)
        XCTAssertEqual(ReplayAppMode.matchReplay.subtitle, "Synthetic match demo")
    }

    func testDemoCuesDoNotClaimGeneratedFootageOrACompletedWorldHandoff() throws {
        let replay = try syntheticReplay()
        // Headlines appear in Home. The immersive Timeline uses kickers and
        // exposes headlines to accessibility; explanations must agree too.
        let copy = replay.moments.map {
            "\($0.kicker) \($0.headline) \($0.explanation)"
        }.joined(separator: " ").lowercased()

        for unsupportedClaim in ["generated clip", "reconstruct", "telemetry", "world manifest"] {
            XCTAssertFalse(copy.contains(unsupportedClaim), unsupportedClaim)
        }
    }

    func testCopyKeepsTheExistingReplayIdentityTracksCueTimesAndMarks() throws {
        let replay = try syntheticReplay()
        let sharedSequence = try XCTUnwrap(DemoScenarios.scenario(for: .squadReplay))

        XCTAssertEqual(replay.id, "real-world-match-replay")
        XCTAssertEqual(replay.kind, .realWorldReplay)
        XCTAssertEqual(replay.duration, 32)
        XCTAssertEqual(replay.defaultViewMode, .tacticalTable)
        XCTAssertEqual(replay.defaultPerspectiveID, "navy-rw")
        XCTAssertEqual(replay.featuredPerspectiveIDs, ["navy-rw", "navy-rb", "navy-rcm", "red-lb"])
        XCTAssertEqual(replay.players.count, 22)
        XCTAssertEqual(replay.players, sharedSequence.players)
        XCTAssertEqual(replay.ball, sharedSequence.ball)
        XCTAssertEqual(replay.moments.map(\.id), [
            "world-source", "world-register", "world-overlap",
            "world-release", "world-cutback", "world-proof"
        ])
        XCTAssertEqual(replay.moments.map(\.time), [0, 8.8, 11.3, 13.6, 17.5, 24])
        XCTAssertEqual(replay.coachMarks.map(\.id.uuidString), [
            "00000000-0000-4000-8000-000000000601",
            "00000000-0000-4000-8000-000000000602",
            "00000000-0000-4000-8000-000000000603",
            "00000000-0000-4000-8000-000000000604"
        ])
        XCTAssertEqual(replay.coachMarks.map(\.kind), [.run, .pass, .danger, .space])
        XCTAssertEqual(replay.coachMarks.map(\.start), [
            PitchPoint(x: 28, z: 14), PitchPoint(x: 27, z: 23),
            PitchPoint(x: 27, z: 24), PitchPoint(x: 12, z: 24)
        ])
        XCTAssertEqual(replay.coachMarks.map(\.end), [
            PitchPoint(x: 31, z: 35), PitchPoint(x: 31, z: 29),
            PitchPoint(x: 30, z: 30), PitchPoint(x: 17, z: 31)
        ])
        XCTAssertEqual(replay.coachMarks.map(\.revealTime), [11.3, 13.6, 13.6, 16.2])
        XCTAssertEqual(replay.coachMarks.map(\.startTrackAnchor?.playerID), [
            "navy-rb", "navy-rw", "red-lb", nil
        ])
        XCTAssertEqual(replay.coachMarks.map(\.endTrackAnchor?.playerID), [
            "navy-rb", "navy-rb", "red-lb", nil
        ])
        XCTAssertEqual(replay.coachMarks.map(\.label), [
            "#2 tracked overlap", "#7 → #2 release", "#3 recovery line", "Cut-back pocket"
        ])
        XCTAssertEqual(replay.formationTargets.map(\.id), [
            "world-rw", "world-rb", "world-rcm", "world-lb"
        ])
    }

    func testExistingSavedNamesAndReplayStateSurviveThePresentationChange() throws {
        let store = ReplayStore()
        store.selectScenario(id: "real-world-match-replay")
        store.seek(to: 13.6)
        store.setPlaybackRate(0.75)
        store.openLocalPlayerPOV("red-lb")
        let originalState = store.makeSavedReviewState()

        // Includes the old suggested title: changing scenario copy must never
        // rewrite a name the user already saved. This library is memory-only.
        for name in ["Real World Match Replay", "Tuesday overlap notes"] {
            XCTAssertTrue(store.saveReview(named: name))
            let saved = try XCTUnwrap(store.savedReviews.first { $0.name == name })
            let encoded = try JSONEncoder().encode(saved)
            let restoredRecord = try JSONDecoder().decode(SavedReplayReview.self, from: encoded)
            XCTAssertEqual(restoredRecord, saved)

            store.selectScenario(id: "triangle-lock")
            XCTAssertTrue(store.restoreReview(restoredRecord))
            XCTAssertEqual(store.makeSavedReviewState(), originalState)
            XCTAssertEqual(store.savedReviews.first { $0.id == saved.id }?.name, name)
            XCTAssertEqual(ReplayAppMode(scenario: store.selectedScenario), .matchReplay)
        }
    }

    private func syntheticReplay() throws -> ReplayScenario {
        try XCTUnwrap(DemoScenarios.scenario(for: .realWorldReplay))
    }
}
