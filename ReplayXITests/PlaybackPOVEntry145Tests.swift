import XCTest
@testable import ReplayXI

@MainActor
final class PlaybackPOVEntry145Tests: XCTestCase {
    func testEveryReferenceViewButtonEntersPOVPausedAtTheSameInstantAsRoster() throws {
        for scenario in FootballReferenceScenarios.all {
            for spectator in [ReplayViewMode.tacticalTable, .touchline] {
                for team in FootballTeam.allCases {
                    let player = try XCTUnwrap(scenario.players.last { $0.team == team })
                    let store = ReplayStore(scenarios: [scenario])
                    store.prepareForLocalExperience()
                    store.openLocalPlayerPOV(player.id)
                    store.setViewMode(spectator, broadcast: false)
                    let time = scenario.duration * 0.4
                    store.seek(to: time, broadcast: false)
                    store.setPlaybackRate(2, broadcast: false)
                    store.setPlaying(true, broadcast: false)
                    let marks = store.marks
                    var broadcasts = 0
                    store.onBroadcastSnapshot = { _ in broadcasts += 1 }

                    store.setViewMode(.firstPerson, broadcast: false)

                    XCTAssertFalse(store.isPlaying, "\(scenario.id), \(spectator), \(team)")
                    XCTAssertEqual(store.playhead, time)
                    XCTAssertEqual(store.playbackRate, 2)
                    XCTAssertEqual(store.activePerspectiveID, player.id)
                    XCTAssertEqual(store.viewMode, .firstPerson)
                    XCTAssertEqual(store.marks, marks)
                    XCTAssertEqual(broadcasts, 0)
                    XCTAssertTrue(store.flushReviewAutosave())
                    XCTAssertEqual(store.autosavedReview?.state.viewMode, .firstPerson)
                    XCTAssertEqual(store.autosavedReview?.state.playhead, time)

                    store.setPlaying(true, broadcast: false)
                    store.setViewMode(.firstPerson, broadcast: false)
                    XCTAssertTrue(store.isPlaying, "Re-selecting the current POV does not interrupt playback")
                }
            }
        }
    }

    func testSpectatorViewSwitchKeepsPlaybackRunning() {
        let store = ReplayStore()
        store.setViewMode(.tacticalTable, broadcast: false)
        store.seek(to: 3, broadcast: false)
        store.setPlaying(true, broadcast: false)
        store.setViewMode(.touchline, broadcast: false)
        XCTAssertTrue(store.isPlaying)
        XCTAssertEqual(store.playhead, 3)
        XCTAssertEqual(store.viewMode, .touchline)
    }

    func testCurrentPOVReselectionDoesNotChangeSharedFollowOrPublish() throws {
        let coach = ReplayStore()
        coach.broadcastPerspective("red-lb")
        coach.setPlaying(true, broadcast: false)
        let player = ReplayStore()
        player.localRole = .player
        player.setCollaborationActive(true)
        XCTAssertTrue(player.applyRemote(coach.makeSnapshot()))
        let before = player.makeSnapshot()
        let status = player.statusMessage
        var broadcasts = 0
        player.onBroadcastSnapshot = { _ in broadcasts += 1 }
        player.setViewMode(.firstPerson)
        XCTAssertTrue(player.followsCoach)
        XCTAssertFalse(player.isLocallyPaused)
        XCTAssertTrue(player.isPlaying)
        XCTAssertEqual(player.makeSnapshot(), before)
        XCTAssertEqual(player.statusMessage, status)
        XCTAssertEqual(broadcasts, 0)
    }

    func testDrawingAndScrubRejectPOVEntryWithoutMovingTheCamera() {
        let store = ReplayStore()
        store.setViewMode(.touchline, broadcast: false)
        store.seek(to: 3, broadcast: false)
        store.beginDrawing(.pass)
        _ = store.registerPitchTap(.init(x: -20, z: -20))
        store.setViewMode(.firstPerson)
        XCTAssertEqual(store.viewMode, .touchline)
        XCTAssertTrue(store.isDrawing)
        XCTAssertNotNil(store.pendingDrawStart)
        store.cancelDrawing()
        XCTAssertTrue(store.beginTimelineScrub())
        XCTAssertTrue(store.previewTimelineScrub(to: 4))
        store.setViewMode(.firstPerson)
        XCTAssertEqual(store.viewMode, .touchline)
        XCTAssertEqual(store.playhead, 4)
        XCTAssertTrue(store.hasActiveTimelineScrub)
        store.cancelTimelineScrub()
    }

    func testCameraHintsDescribePausedEntryButNotAnAlreadySelectedView() {
        XCTAssertEqual(PlaybackControlDeckPresentation.cameraActionHint(.firstPerson, currentMode: .touchline),
            "Enters free-look player view paused at this moment")
        for mode in [ReplayViewMode.firstPerson, .tacticalTable, .touchline, .positional] {
            XCTAssertEqual(PlaybackControlDeckPresentation.cameraActionHint(mode, currentMode: mode),
                "Current view; playback is unchanged")
        }
        XCTAssertEqual(PlaybackControlDeckPresentation.cameraActionHint(.touchline, currentMode: .tacticalTable),
            "Changes the replay camera")
    }
}
