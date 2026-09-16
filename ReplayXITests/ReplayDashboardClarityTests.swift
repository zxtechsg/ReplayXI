import XCTest
@testable import ReplayXI

@MainActor
final class ReplayDashboardClarityTests: XCTestCase {
    func testMatchRailOffersHomePOVsWithAnExplicitAction() throws {
        let scenario = try scenario(id: "real-world-match-replay")
        let rail = DashboardPlayerRailContent(scenario: scenario)
        XCTAssertFalse(rail.isSelectingStation)
        XCTAssertEqual(rail.title, "Home XI · quick POV")
        XCTAssertEqual(rail.instruction, "Select a player to enter POV.")
        XCTAssertEqual(rail.players.map(\.id), scenario.homePlayers.map(\.id))
        XCTAssertEqual(rail.players.count, 11)
    }

    func testShapeRailOnlyOffersItsActualRoleStations() throws {
        let scenario = try scenario(id: "triangle-lock")
        let rail = DashboardPlayerRailContent(scenario: scenario)
        XCTAssertTrue(rail.isSelectingStation)
        XCTAssertEqual(rail.title, "Role stations")
        XCTAssertEqual(rail.instruction, "Choose your room role.")
        XCTAssertEqual(rail.players.map(\.id), scenario.formationTargets.map(\.playerID))
        XCTAssertEqual(rail.players.count, 3)
        XCTAssertLessThan(rail.players.count, scenario.homePlayers.count)
    }

    func testMatchRowOnlyClaimsSelectionInFirstPerson() throws {
        let scenario = try scenario(id: "real-world-match-replay")
        let rail = DashboardPlayerRailContent(scenario: scenario)
        let id = try XCTUnwrap(rail.players.first?.id)
        XCTAssertTrue(rail.isSelected(playerID: id, perspectiveID: id, viewMode: .firstPerson))
        XCTAssertFalse(rail.isSelected(playerID: id, perspectiveID: id, viewMode: .tacticalTable))
        XCTAssertFalse(rail.isSelected(playerID: id, perspectiveID: id, viewMode: .touchline))
        XCTAssertFalse(rail.isSelected(playerID: id, perspectiveID: "different-player", viewMode: .firstPerson))
    }

    func testRoleStationSelectionDoesNotClaimAPlayerCamera() throws {
        let rail = DashboardPlayerRailContent(scenario: try scenario(id: "triangle-lock"))
        let id = try XCTUnwrap(rail.players.first?.id)
        XCTAssertTrue(rail.isSelected(playerID: id, perspectiveID: id, viewMode: .positional))
        XCTAssertFalse(rail.isSelected(playerID: id, perspectiveID: "different-player", viewMode: .positional))
    }

    func testMatchRowActuallyEntersSelectedPOVAndKeepsTheTime() throws {
        let store = ReplayStore()
        store.selectScenario(id: "real-world-match-replay")
        store.setViewMode(.tacticalTable)
        store.seek(to: 12)
        store.setPlaying(true)
        let rail = DashboardPlayerRailContent(scenario: store.selectedScenario)
        let id = try XCTUnwrap(rail.players.last?.id)
        rail.select(playerID: id, in: store)
        XCTAssertEqual(store.viewMode, .firstPerson)
        XCTAssertEqual(store.activePerspectiveID, id)
        XCTAssertEqual(store.playhead, 12)
        XCTAssertFalse(store.isPlaying)
    }

    func testRoleRowPreservesThePositionalViewAndShapeStage() throws {
        let store = ReplayStore()
        store.selectScenario(id: "triangle-lock")
        store.setShapeFocusStage(.ideal)
        let rail = DashboardPlayerRailContent(scenario: store.selectedScenario)
        let id = try XCTUnwrap(rail.players.last?.id)
        let time = store.playhead
        rail.select(playerID: id, in: store)
        XCTAssertEqual(store.localPerspectiveID, id)
        XCTAssertEqual(store.viewMode, .positional)
        XCTAssertEqual(store.shapeFocusStage, .ideal)
        XCTAssertEqual(store.playhead, time)
        XCTAssertEqual(store.physicalTriangleTarget(participantID: nil, sharedSession: false)?.playerID, id)
        let player = try XCTUnwrap(store.selectedScenario.player(id: id))
        let target = try XCTUnwrap(store.selectedScenario.formationTargets.first { $0.playerID == id })
        XCTAssertEqual(store.statusMessage, "Role station: #\(player.shirtNumber) · \(target.label)")
        XCTAssertFalse(store.statusMessage.contains("Player POV"))
    }

    func testRoleRailRejectsPlayersWithoutAStation() throws {
        let store = ReplayStore()
        store.selectScenario(id: "triangle-lock")
        let rail = DashboardPlayerRailContent(scenario: store.selectedScenario)
        let invalidID = try XCTUnwrap(store.selectedScenario.homePlayers.first {
            !rail.players.contains($0)
        }?.id)
        let originalID = store.localPerspectiveID
        let originalStatus = store.statusMessage
        rail.select(playerID: invalidID, in: store)
        XCTAssertEqual(store.localPerspectiveID, originalID)
        XCTAssertEqual(store.viewMode, .positional)
        XCTAssertEqual(store.statusMessage, originalStatus)
    }

    func testReselectingTheCurrentRoleReportsAStationNotAPOV() throws {
        let store = ReplayStore()
        store.selectScenario(id: "triangle-lock")
        let rail = DashboardPlayerRailContent(scenario: store.selectedScenario)
        let player = try XCTUnwrap(rail.players.first)
        let target = try XCTUnwrap(store.selectedScenario.formationTargets.first { $0.playerID == player.id })
        store.setLocalPerspective(player.id, entersLocalReview: false)
        rail.select(playerID: player.id, in: store)
        XCTAssertEqual(store.localPerspectiveID, player.id)
        XCTAssertEqual(store.viewMode, .positional)
        XCTAssertEqual(store.statusMessage, "Role station: #\(player.shirtNumber) · \(target.label)")
    }

    func testBlockedRoleReselectionKeepsTheAnnotationRejectionMessage() throws {
        let store = ReplayStore()
        store.selectScenario(id: "triangle-lock")
        let rail = DashboardPlayerRailContent(scenario: store.selectedScenario)
        let id = try XCTUnwrap(rail.players.first?.id)
        store.setLocalPerspective(id, entersLocalReview: false)
        store.beginDrawing(.pass)
        rail.select(playerID: id, in: store)
        XCTAssertEqual(store.localPerspectiveID, id)
        XCTAssertEqual(store.viewMode, .positional)
        XCTAssertTrue(store.isDrawing)
        XCTAssertEqual(store.statusMessage, "Finish or cancel the annotation first")
    }

    func testBlockedRoleReselectionKeepsTheTimelineRejectionMessage() throws {
        let store = ReplayStore()
        store.selectScenario(id: "triangle-lock")
        let rail = DashboardPlayerRailContent(scenario: store.selectedScenario)
        let id = try XCTUnwrap(rail.players.first?.id)
        store.setLocalPerspective(id, entersLocalReview: false)
        XCTAssertTrue(store.beginTimelineScrub())
        rail.select(playerID: id, in: store)
        XCTAssertEqual(store.localPerspectiveID, id)
        XCTAssertEqual(store.viewMode, .positional)
        XCTAssertTrue(store.hasActiveTimelineScrub)
        XCTAssertEqual(store.statusMessage, "Finish or cancel the timeline scrub first")
        store.cancelTimelineScrub()
    }

    func testStaleRoleRailCannotOverwriteTheNewScenarioStatus() throws {
        let store = ReplayStore()
        store.selectScenario(id: "triangle-lock")
        let oldRail = DashboardPlayerRailContent(scenario: store.selectedScenario)
        let oldID = try XCTUnwrap(oldRail.players.first?.id)
        store.selectScenario(id: "real-world-match-replay")
        let originalID = store.localPerspectiveID
        let originalView = store.viewMode
        let originalStatus = store.statusMessage
        oldRail.select(playerID: oldID, in: store)
        XCTAssertEqual(store.localPerspectiveID, originalID)
        XCTAssertEqual(store.viewMode, originalView)
        XCTAssertEqual(store.statusMessage, originalStatus)
    }

    func testStaleRailCannotChangeTheNewScenario() throws {
        let store = ReplayStore()
        store.selectScenario(id: "real-world-match-replay")
        let oldRail = DashboardPlayerRailContent(scenario: store.selectedScenario)
        let oldID = try XCTUnwrap(oldRail.players.last?.id)
        store.selectScenario(id: "triangle-lock")
        let originalID = store.localPerspectiveID
        oldRail.select(playerID: oldID, in: store)
        XCTAssertEqual(store.localPerspectiveID, originalID)
        XCTAssertEqual(store.viewMode, .positional)
    }

    func testRowSelectionRespectsAnUnfinishedAnnotation() throws {
        let store = ReplayStore()
        store.selectScenario(id: "real-world-match-replay")
        store.setViewMode(.tacticalTable)
        let rail = DashboardPlayerRailContent(scenario: store.selectedScenario)
        let originalID = store.localPerspectiveID
        store.beginDrawing(.pass)
        rail.select(playerID: try XCTUnwrap(rail.players.last?.id), in: store)
        XCTAssertEqual(store.localPerspectiveID, originalID)
        XCTAssertEqual(store.viewMode, .tacticalTable)
        XCTAssertTrue(store.isDrawing)
    }

    func testRowSelectionRespectsTimelineScrubOwnership() throws {
        let store = ReplayStore()
        store.selectScenario(id: "real-world-match-replay")
        store.setViewMode(.tacticalTable)
        let rail = DashboardPlayerRailContent(scenario: store.selectedScenario)
        let originalID = store.localPerspectiveID
        XCTAssertTrue(store.beginTimelineScrub())
        rail.select(playerID: try XCTUnwrap(rail.players.last?.id), in: store)
        XCTAssertEqual(store.localPerspectiveID, originalID)
        XCTAssertEqual(store.viewMode, .tacticalTable)
        XCTAssertTrue(store.hasActiveTimelineScrub)
        store.cancelTimelineScrub()
    }

    func testExistingOpponentPOVRouteRemainsAvailable() throws {
        let store = ReplayStore()
        store.selectScenario(id: "real-world-match-replay")
        let opponent = try XCTUnwrap(store.selectedScenario.awayPlayers.last)
        store.openLocalPlayerPOV(opponent.id)
        XCTAssertEqual(store.viewMode, .firstPerson)
        XCTAssertEqual(store.activePerspectiveID, opponent.id)
        let rail = DashboardPlayerRailContent(scenario: store.selectedScenario)
        XCTAssertTrue(rail.players.allSatisfy {
            !rail.isSelected(playerID: $0.id, perspectiveID: opponent.id, viewMode: store.viewMode)
        }, "A home row must not falsely claim an opponent POV")
    }

    func testDashboardWiresRoomLabelsAndInputBarriersWithoutDisablingItsOwnSlider() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        let source = try String(
            contentsOf: root.appendingPathComponent("ReplayXI/UI/ReplayDashboardView.swift"),
            encoding: .utf8
        )
        XCTAssertTrue(source.contains("case .open: \"Room open\""))
        XCTAssertTrue(source.contains("case .closing: \"Closing room…\""))
        XCTAssertTrue(source.contains(".disabled(store.isRoomPresentationBusy)"))
        XCTAssertTrue(source.contains("store.isDrawing || store.hasActiveCoachMarkGeometryPreview"))
        XCTAssertTrue(source.contains(".disabled(!store.canChangePlaybackView)"))
        XCTAssertTrue(source.contains("ForEach(FootballTeam.allCases)"))
        XCTAssertTrue(source.contains("rosterTeam == .home ? scenario.homePlayers : scenario.awayPlayers"))
        XCTAssertTrue(source.contains("minHeight: 44"))
        XCTAssertFalse(source.contains("private struct SeatRow"))
        XCTAssertFalse(source.contains("\"VIEWING\" : \"SIM\""))
    }

    private func scenario(id: String) throws -> ReplayScenario {
        try XCTUnwrap(DemoScenarios.all.first { $0.id == id })
    }
}
