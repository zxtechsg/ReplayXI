import XCTest
@testable import ReplayXI

@MainActor
final class ReplayLiveReview185Tests: XCTestCase {
    func testTimedBindingsXYZCurvesAndLongWindowsRequireProtectedSchema() throws {
        let scenario = DemoScenarios.all[0]
        let player = scenario.players[0]
        let position = player.presentationPose(at: 0).position
        let tracked = CoachMark(kind: .pass, start: position, end: .init(x: -10, z: -10),
            label: "Timed link", revealTime: 0,
            startTrackAnchor: .init(playerID: player.id)).recordingPose(at: 0)
        let base = CoachMark(kind: .arc, start: .init(x: -20, z: -20), end: .init(x: -10, z: -10),
            label: "XYZ", revealTime: 0)
        let xyz = CoachMark(kind: .arc, start: base.start, end: base.end,
            curve: base.resolvedCurve.settingControlPoint([-14, 5, -18], for: base),
            label: base.label, revealTime: 0)
        let long = CoachMark(kind: .pass, start: base.start, end: base.end,
            label: "Long live mark", revealTime: 0, hideTime: 31)
        XCTAssertGreaterThanOrEqual(scenario.duration, 31)
        for mark in [tracked, xyz, long] {
            let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            defer { try? FileManager.default.removeItem(at: folder) }
            let url = folder.appendingPathComponent("reviews.json")
            let library = ReplayReviewLibrary(scenarios: [scenario], fileURL: url)
            func state(_ marks: [CoachMark]) -> SavedReplayState {
                .init(scenarioID: scenario.id, playhead: 0, playbackRate: 1,
                    viewMode: .tacticalTable, perspectiveID: scenario.defaultPerspectiveID,
                    showsLaneLens: false, shapeFocusStage: .problem, marksByScenario: [scenario.id: marks])
            }
            XCTAssertTrue(library.save(named: mark.label, state: state([mark])))
            let id = try XCTUnwrap(library.savedReviews.first?.id)
            XCTAssertEqual(try version(at: url), 3)
            library.resetPersistenceWorkForTesting()
            XCTAssertTrue(library.autosave(state([])))
            XCTAssertEqual(library.persistenceWork.namedReviewFragmentReuses, 1)
            XCTAssertEqual(try version(at: url), 3, "Cached named reviews must keep their schema")
            let reopened = ReplayReviewLibrary(scenarios: [scenario], fileURL: url)
            XCTAssertFalse(reopened.isReadOnly)
            XCTAssertEqual(reopened.savedReviews.first?.state.marks, [mark])
            XCTAssertTrue(library.delete(id: id))
            XCTAssertEqual(try version(at: url), 1, "Legacy-only data remains compatible")
        }
    }

    func testOldKeysWithoutTrackingStillDecodeAsFixedPitch() throws {
        let data = Data("""
        {"time":1,"start":{"x":0,"z":0},"end":{"x":4,"z":4},"startElevation":0,"endElevation":0}
        """.utf8)
        let frame = try JSONDecoder().decode(CoachMarkKeyframe.self, from: data)
        XCTAssertNil(frame.tracking)
        var mark = CoachMark(kind: .pass, start: frame.start, end: frame.end, label: "Legacy", revealTime: 0)
        mark.keyframes = [frame]
        XCTAssertNil(mark.sampled(at: 2).startTrackAnchor)
        XCTAssertNil(mark.sampled(at: 2).endTrackAnchor)
        XCTAssertEqual(mark.sampled(at: 2).end, frame.end)
    }

    func testLegacyKeyedReviewCanGainTimedPlayerLinkWithoutChangingEarlierBinding() throws {
        let frame = try JSONDecoder().decode(CoachMarkKeyframe.self, from: Data("""
        {"time":1,"start":{"x":0,"z":0},"end":{"x":4,"z":4},"startElevation":0,"endElevation":0}
        """.utf8))
        let store = ReplayStore()
        store.prepareForLocalExperience()
        var mark = CoachMark(kind: .pass, start: frame.start, end: frame.end,
            label: "Legacy motion", revealTime: 0)
        mark.keyframes = [frame]
        XCTAssertTrue(store.appendRemoteCoachMark(mark))
        store.seek(to: 2)
        let player = store.selectedScenario.players[0]
        XCTAssertTrue(store.setCoachMarkEndpointTracking(id: mark.id, endpoint: .end, playerID: player.id))
        let linked = try XCTUnwrap(store.marks.first { $0.id == mark.id })
        XCTAssertNil(linked.sampled(at: 1).endTrackAnchor)
        XCTAssertEqual(linked.sampled(at: 2).endTrackAnchor?.playerID, player.id)
        XCTAssertTrue(ReplayStore.isValidReviewMark(linked, for: store.selectedScenario))
        let poses = store.playerPresentation.poses(in: store.selectedScenario, at: 3)
        let expected = linked.resolvedGeometry(in: store.selectedScenario, at: 3, presentedPlayerPoses: poses)
        XCTAssertEqual(store.presentedCoachMarkGeometry(linked, at: 3), expected)
        XCTAssertEqual(linked.resolvingTrackGeometry(in: store.selectedScenario, at: 3,
            presentedPlayerPoses: poses).end, expected.end)
    }

    private func version(at url: URL) throws -> Int {
        struct Header: Decodable { let version: Int }
        return try JSONDecoder().decode(Header.self, from: Data(contentsOf: url)).version
    }
}
