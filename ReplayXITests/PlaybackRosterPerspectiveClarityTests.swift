import XCTest
@testable import ReplayXI

@MainActor
final class PlaybackRosterPerspectiveClarityTests: XCTestCase {
    func testCompactControlOnlyNamesAnActivePOVInFirstPerson() throws {
        let source = try immersiveSource()
        let compact = try slice(source, after: "private var activePlayerCompactLabel: String",
            before: "private var activePlayerAccessibilityLabel: String")
        XCTAssertTrue(compact.contains("shirtNumber: store.viewMode == .firstPerson"),
            "A retained focus is not the camera currently being viewed")
        let accessible = try slice(source, after: "private var activePlayerAccessibilityLabel: String",
            before: "private var annotationToolsButton:")
        XCTAssertTrue(accessible.contains("guard store.viewMode == .firstPerson,"))
        XCTAssertTrue(accessible.contains("Choose player point of view"))
        XCTAssertEqual(PlaybackControlDeckPresentation.playerControlLabel(shirtNumber: nil), "POV PLAYER")
    }

    func testRosterPillAndSelectedTraitOnlyDescribeTheRenderedPlayerCamera() throws {
        let source = try immersiveSource()
        let roster = try slice(source, after: "private var playerPOVGrid: some View",
            before: "private func perspectiveTeamRow(")
        XCTAssertTrue(roster.contains("if store.viewMode == .firstPerson, let player = store.activePerspective"))
        let playerButton = try slice(source, after: "private func perspectivePlayerButton(_ player: PlayerTrack)",
            before: "private var playerGridInstruction:")
        XCTAssertTrue(playerButton.contains(
            "let isSelected = store.viewMode == .firstPerson && player.id == store.activePerspectiveID"))
        XCTAssertTrue(playerButton.contains("openPlayerPOV(player.id)"), "Keep the existing POV entry action")
        XCTAssertTrue(playerButton.contains(".accessibilityAddTraits(isSelected ? .isSelected : [])"))
    }

    func testStoreRetainsTheFocusAfterLeavingPOVButDoesNotRemainInFirstPerson() throws {
        let store = makeStore()
        let player = try XCTUnwrap(store.selectedScenario.homePlayers.last)
        store.openLocalPlayerPOV(player.id)
        XCTAssertEqual(store.viewMode, .firstPerson)
        for mode in [ReplayViewMode.tacticalTable, .touchline] {
            store.setViewMode(mode, broadcast: false)
            XCTAssertEqual(store.viewMode, mode)
            XCTAssertEqual(store.activePerspectiveID, player.id,
                "The roster must not infer active POV from this retained ID alone")
            XCTAssertEqual(store.activePerspective?.shirtNumber, player.shirtNumber)
        }
    }

    func testChoosingTheRetainedPlayerFromAnotherViewStillEntersPausedPOV() {
        for mode in [ReplayViewMode.tacticalTable, .touchline] {
            let store = makeStore()
            let id = store.activePerspectiveID
            store.setViewMode(mode, broadcast: false)
            store.seek(to: 12, broadcast: false)
            store.setPlaying(true, broadcast: false)

            store.openLocalPlayerPOV(id)

            XCTAssertEqual(store.viewMode, .firstPerson)
            XCTAssertEqual(store.activePerspectiveID, id)
            XCTAssertEqual(store.playhead, 12)
            XCTAssertFalse(store.isPlaying)
        }
    }

    func testBothTeamsStayReachableAndAnActivePOVReselectionStaysNavigationOnly() throws {
        let store = makeStore()
        let home = try XCTUnwrap(store.selectedScenario.homePlayers.last)
        let away = try XCTUnwrap(store.selectedScenario.awayPlayers.last)
        XCTAssertEqual(store.selectedScenario.players.count, 22)
        store.seek(to: 12, broadcast: false)

        for player in [home, away] {
            store.setViewMode(.tacticalTable, broadcast: false)
            store.openLocalPlayerPOV(player.id)
            XCTAssertEqual(store.viewMode, .firstPerson)
            XCTAssertEqual(store.activePerspectiveID, player.id)
            XCTAssertEqual(store.playhead, 12)
            XCTAssertFalse(store.isPlaying)

            store.setPlaying(true, broadcast: false)
            store.openLocalPlayerPOV(player.id)
            XCTAssertTrue(store.isPlaying, "Selecting the camera already being watched stays navigation-only")
            XCTAssertEqual(store.activePerspectiveID, player.id)
        }
    }

    func testReferencePOVLabelsDistinguishBothTeamsWithTheSameShirtNumber() throws {
        for scenario in FootballReferenceScenarios.all {
            let home = try XCTUnwrap(scenario.homePlayers.first { home in
                scenario.awayPlayers.contains { $0.shirtNumber == home.shirtNumber }
            })
            let away = try XCTUnwrap(scenario.awayPlayers.first { $0.shirtNumber == home.shirtNumber })
            func label(_ player: PlayerTrack) -> String {
                PlaybackControlDeckPresentation.playerControlLabel(shirtNumber: player.shirtNumber,
                    teamAbbreviation: FootballReferenceScenarios.teamAbbreviation(player.team, in: scenario))
            }
            XCTAssertNotEqual(label(home), label(away), scenario.id)
            for player in [home, away] {
                let spoken = PlaybackControlDeckPresentation.playerControlAccessibilityLabel(player: player, scenario: scenario)
                XCTAssertTrue(spoken.contains(FootballReferenceScenarios.teamTitle(player.team, in: scenario)))
                XCTAssertTrue(spoken.contains(player.displayName))
                XCTAssertTrue(spoken.contains("number \(player.shirtNumber)"))
                XCTAssertTrue(spoken.contains(player.role))
            }
            XCTAssertEqual(PlaybackControlDeckPresentation.playerControlLabel(shirtNumber: nil,
                teamAbbreviation: FootballReferenceScenarios.teamAbbreviation(home.team, in: scenario)), "POV PLAYER")
        }
    }

    func testReferenceCodesAreDistinctAndIncludeManchesterCity() throws {
        let city = try XCTUnwrap(FootballReferenceScenarios.all.first { $0.id == "city-45-overlap-header" })
        XCTAssertEqual(FootballReferenceScenarios.teamAbbreviation(.home, in: city), "MCI")
        XCTAssertEqual(FootballReferenceScenarios.teamAbbreviation(.away, in: city), "LIV")
        let final = try XCTUnwrap(FootballReferenceScenarios.all.first { $0.id == "final-81-volley-v2" })
        XCTAssertEqual(FootballReferenceScenarios.teamAbbreviation(.home, in: final), "ARG")
        XCTAssertEqual(FootballReferenceScenarios.teamAbbreviation(.away, in: final), "FRA")
        let practice = ReplayStore().selectedScenario
        XCTAssertEqual(FootballReferenceScenarios.teamAbbreviation(.home, in: practice), "HOME")
        XCTAssertEqual(FootballReferenceScenarios.teamAbbreviation(.away, in: practice), "AWAY")
    }

    func testImmersiveCompactControlAndRosterUseTeamAwareIdentity() throws {
        let source = try immersiveSource()
        let labels = try slice(source, after: "private var activePlayerCompactLabel: String",
            before: "private var annotationToolsButton:")
        XCTAssertTrue(labels.contains("teamAbbreviation: store.activePerspective.map"))
        XCTAssertTrue(labels.contains("PlaybackControlDeckPresentation.playerControlAccessibilityLabel("))
        let roster = try slice(source, after: "private var playerPOVGrid: some View",
            before: "private func perspectivePlayerButton(")
        XCTAssertTrue(roster.contains("FootballReferenceScenarios.teamAbbreviation(player.team, in: store.selectedScenario)"))
        XCTAssertTrue(roster.contains("FootballReferenceScenarios.teamAbbreviation(team, in: store.selectedScenario)"))
    }

    private func makeStore() -> ReplayStore {
        let store = ReplayStore()
        store.prepareForLocalExperience()
        return store
    }

    private func immersiveSource() throws -> String {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        return try String(contentsOf: root.appendingPathComponent(
            "ReplayXI/Immersive/FootballImmersiveView.swift"), encoding: .utf8)
    }

    private func slice(_ source: String, after start: String, before end: String) throws -> String {
        let lower = try XCTUnwrap(source.range(of: start)?.upperBound)
        let upper = try XCTUnwrap(source.range(of: end, range: lower..<source.endIndex)?.lowerBound)
        return String(source[lower..<upper])
    }
}
