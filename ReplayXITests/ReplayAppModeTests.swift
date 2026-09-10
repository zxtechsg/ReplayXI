import XCTest
@testable import ReplayXI

final class ReplayAppModeTests: XCTestCase {
    func testTwoModesGroupExistingIDsWithoutDroppingOrDuplicatingScenarios() {
        let catalogue = DemoScenarios.all
        XCTAssertEqual(ReplayAppMode.allCases.count, 2)
        let exercises = ReplayAppMode.situationRoleplay.scenarios(in: catalogue)
        let replays = ReplayAppMode.matchReplay.scenarios(in: catalogue)
        XCTAssertEqual(exercises.map(\.id), [
            "eleven-eyes", "everyone-with-seven", "triangle-lock", "lane-lens", "four-minds"
        ])
        XCTAssertEqual(replays.map(\.id), ["real-world-match-replay"])
        XCTAssertEqual((exercises + replays).map(\.id), catalogue.map(\.id))
        XCTAssertEqual(ReplayAppMode.matchReplay.subtitle, "Synthetic reconstruction preview")
    }

    func testModeSelectionReturnsRememberedScenarioOnlyWhenItBelongsToMode() {
        let catalogue = DemoScenarios.all
        XCTAssertEqual(ReplayAppMode.situationRoleplay.scenarioID(
            in: catalogue, preferredID: "lane-lens"
        ), "lane-lens")
        XCTAssertEqual(ReplayAppMode.situationRoleplay.scenarioID(
            in: catalogue, preferredID: "real-world-match-replay"
        ), "eleven-eyes")
        XCTAssertEqual(ReplayAppMode.matchReplay.scenarioID(
            in: catalogue, preferredID: "missing-scenario"
        ), "real-world-match-replay")
        XCTAssertNil(ReplayAppMode.matchReplay.scenarioID(in: [], preferredID: nil))
    }

    func testSavedScenarioStillResolvesToItsNavigationMode() throws {
        let store = ReplayStore()
        store.selectScenario(id: "real-world-match-replay")
        XCTAssertTrue(store.saveReview(named: "Replay demo"))
        let saved = try XCTUnwrap(store.savedReviews.first)
        store.selectScenario(id: "lane-lens")
        XCTAssertEqual(ReplayAppMode(scenario: store.selectedScenario), .situationRoleplay)
        XCTAssertTrue(store.restoreReview(saved))
        XCTAssertEqual(store.selectedScenarioID, "real-world-match-replay")
        XCTAssertEqual(ReplayAppMode(scenario: store.selectedScenario), .matchReplay)
    }
}
