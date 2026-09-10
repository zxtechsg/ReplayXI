import XCTest
@testable import ReplayXI

@MainActor
final class ReplayReviewSharedScenarioTests: XCTestCase {
    private var temporaryDirectories: [URL] = []

    override func tearDownWithError() throws {
        for directory in temporaryDirectories {
            try FileManager.default.removeItem(at: directory)
        }
        temporaryDirectories.removeAll()
    }

    func testPausedPhysicalScenarioSwitchKeepsSavedMarksUnderTheirCorrectScenario() throws {
        let (url, player, originalScenarioID, originalMarks) = try makePlayerFixture()
        defer { player.flushReviewAutosave() }
        let shapeLab = try XCTUnwrap(DemoScenarios.scenario(for: .shapeLab))
        let coach = ReplayStore()
        coach.selectScenario(id: shapeLab.id, broadcast: false)
        _ = try addMark(to: coach)
        coach.setPlaybackRate(2, broadcast: false)
        coach.activateTrianglePlacement(anchorID: UUID())
        let incoming = coach.makeSnapshot()
        player.setFollowingCoach(false)
        XCTAssertNotEqual(player.playhead, incoming.playhead)

        XCTAssertTrue(player.applyRemote(incoming))

        XCTAssertEqual(player.selectedScenarioID, shapeLab.id)
        XCTAssertEqual(player.marks, incoming.marks)
        XCTAssertEqual(player.playhead, incoming.playhead)
        XCTAssertEqual(player.playbackRate, incoming.playbackRate)
        XCTAssertTrue(player.isLocallyPaused)
        XCTAssertFalse(player.isPlaying)
        XCTAssertEqual(player.triangleLockMode, .place)
        XCTAssertFalse(player.hasLocallyAcknowledgedTrianglePlacement)
        XCTAssertTrue(player.flushReviewAutosave())
        let saved = try reloadedState(at: url)
        XCTAssertEqual(saved.scenarioID, shapeLab.id)
        XCTAssertEqual(saved.marks, incoming.marks)
        XCTAssertEqual(saved.playhead, incoming.playhead)
        XCTAssertEqual(saved.marksByScenario[originalScenarioID], originalMarks)

        player.resetCollaborationState()
        player.selectScenario(id: originalScenarioID, broadcast: false)
        XCTAssertEqual(player.marks, originalMarks)
    }

    func testFollowingRemoteScenarioSwitchRetainsPreviousReviewForAutosaveAndSoloReturn() throws {
        let (url, player, originalScenarioID, originalMarks) = try makePlayerFixture()
        defer { player.flushReviewAutosave() }
        let passingChannels = try XCTUnwrap(DemoScenarios.scenario(for: .passingChannels))
        let coach = ReplayStore()
        coach.selectScenario(id: passingChannels.id, broadcast: false)
        coach.seek(to: 12.5, broadcast: false)
        _ = try addMark(to: coach)
        coach.setPlaybackRate(1.5, broadcast: false)
        coach.setViewMode(.touchline, broadcast: false)
        let incoming = coach.makeSnapshot()
        XCTAssertFalse(player.isLocallyPaused)

        XCTAssertTrue(player.applyRemote(incoming))

        XCTAssertEqual(player.selectedScenarioID, passingChannels.id)
        XCTAssertEqual(player.marks, incoming.marks)
        XCTAssertEqual(player.playhead, incoming.playhead)
        XCTAssertEqual(player.viewMode, incoming.viewMode)
        XCTAssertEqual(player.playbackRate, incoming.playbackRate)
        XCTAssertTrue(player.flushReviewAutosave())
        let saved = try reloadedState(at: url)
        XCTAssertEqual(saved.scenarioID, passingChannels.id)
        XCTAssertEqual(saved.marks, incoming.marks)
        XCTAssertEqual(saved.playhead, incoming.playhead)
        XCTAssertEqual(saved.marksByScenario[originalScenarioID], originalMarks)

        player.resetCollaborationState()
        player.selectScenario(id: originalScenarioID, broadcast: false)
        XCTAssertEqual(player.marks, originalMarks)
    }

    func testPhysicalSnapshotKeepsSameScenarioComfortReviewPausedAtItsLocalMoment() throws {
        let shapeLab = try XCTUnwrap(DemoScenarios.scenario(for: .shapeLab))
        let player = ReplayStore()
        player.selectScenario(id: shapeLab.id, broadcast: false)
        player.seek(to: 7, broadcast: false)
        _ = try addMark(to: player)
        player.setPlaybackRate(0.75, broadcast: false)
        let localMarks = player.marks
        player.localRole = .player
        player.setCollaborationActive(true)
        player.setFollowingCoach(false)
        let coach = ReplayStore()
        coach.selectScenario(id: shapeLab.id, broadcast: false)
        coach.setPlaybackRate(2, broadcast: false)
        let anchorID = UUID()
        coach.activateTrianglePlacement(anchorID: anchorID)

        XCTAssertTrue(player.applyRemote(coach.makeSnapshot()))

        XCTAssertEqual(player.selectedScenarioID, shapeLab.id)
        XCTAssertEqual(player.marks, localMarks)
        XCTAssertEqual(player.playhead, 7)
        XCTAssertEqual(player.playbackRate, 0.75)
        XCTAssertTrue(player.isLocallyPaused)
        XCTAssertFalse(player.isPlaying)
        XCTAssertEqual(player.triangleLockMode, .place)
        XCTAssertEqual(player.sharedPitchAnchorID, anchorID)
        XCTAssertFalse(player.hasLocallyAcknowledgedTrianglePlacement)
    }

    private func makePlayerFixture() throws -> (URL, ReplayStore, String, [CoachMark]) {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("ReplaySharedScenario-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        temporaryDirectories.append(directory)
        let url = directory.appendingPathComponent("reviews.json")
        let library = ReplayReviewLibrary(scenarios: DemoScenarios.all, fileURL: url)
        let player = ReplayStore(scenarios: DemoScenarios.all, reviewLibrary: library)
        player.seek(to: 5, broadcast: false)
        _ = try addMark(to: player)
        let originalScenarioID = player.selectedScenarioID
        let originalMarks = player.marks
        XCTAssertTrue(player.flushReviewAutosave())
        player.localRole = .player
        player.setCollaborationActive(true)
        return (url, player, originalScenarioID, originalMarks)
    }

    private func addMark(to store: ReplayStore) throws -> CoachMark {
        store.beginDrawing(.pass)
        XCTAssertNil(store.registerPitchTap(PitchPoint(x: 2, z: 3)))
        let mark = try XCTUnwrap(store.registerPitchTap(PitchPoint(x: 8, z: 10)))
        store.cancelDrawing()
        return mark
    }

    private func reloadedState(at url: URL) throws -> SavedReplayState {
        let library = ReplayReviewLibrary(scenarios: DemoScenarios.all, fileURL: url)
        return try XCTUnwrap(library.autosavedReview?.state)
    }
}
