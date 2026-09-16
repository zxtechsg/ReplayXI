import XCTest
@testable import ReplayXI

final class ReplayDecisionAvailabilityTests: XCTestCase {
    func testCheapAvailabilityMatchesAnalysisForEveryBundledPlayerAndTimeBoundary() {
        for scenario in DemoScenarios.all {
            for player in scenario.players {
                for time in [-1, 0, 12.5, scenario.duration, scenario.duration + 1] {
                    XCTAssertEqual(
                        ReplayDecisionReview.canCreateSnapshot(scenario: scenario, at: time, playerID: player.id),
                        scenario.decisionReview(at: time, playerID: player.id) != nil
                    )
                }
            }
        }
    }

    func testInvalidInputsDoNotEnableTheDecisionsButton() throws {
        let scenario = try XCTUnwrap(DemoScenarios.all.first)
        let player = try XCTUnwrap(scenario.players.first)
        for time in [Double.nan, .infinity, -.infinity] {
            XCTAssertFalse(ReplayDecisionReview.canCreateSnapshot(
                scenario: scenario, at: time, playerID: player.id
            ))
        }
        XCTAssertFalse(ReplayDecisionReview.canCreateSnapshot(
            scenario: scenario, at: 0, playerID: "missing-player"
        ))
    }

    func testButtonAvailabilityDoesNotBuildAnUnusedDecisionSnapshot() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        let source = try String(contentsOf: root.appendingPathComponent(
            "ReplayXI/Immersive/FootballImmersiveView.swift"
        ), encoding: .utf8)
        let start = try XCTUnwrap(source.range(of: "private var decisionReviewButton: some View"))
        let end = try XCTUnwrap(source.range(of: "private var annotationEventStrip: some View", range: start.upperBound..<source.endIndex))
        let button = String(source[start.lowerBound..<end.lowerBound])
        XCTAssertTrue(button.contains("!canShowDecisionOptions"))
        XCTAssertFalse(button.contains("decisionSnapshot == nil"))
        XCTAssertFalse(button.contains(".decisionReview("))
    }
}
