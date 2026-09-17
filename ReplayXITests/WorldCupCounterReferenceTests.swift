import XCTest
@testable import ReplayXI

@MainActor
final class WorldCupCounterReferenceTests: XCTestCase {
    func testAllFeaturedSprintPathsStayBelowElevenMetresPerSecond() {
        for scenario in FootballReferenceScenarios.all {
            for player in scenario.players {
                var peak: Float = 0
                let step = 1.0 / 120.0
                for index in 1...Int(scenario.duration / step) {
                    let before = player.presentationPose(at: Double(index - 1) * step).position
                    let after = player.presentationPose(at: Double(index) * step).position
                    peak = max(peak, ReplayGeometry.distance(before, after) / Float(step))
                }
                XCTAssertLessThanOrEqual(peak, 11,
                    "\(scenario.id)/\(player.id): authored path has an excessive sprint burst (\(peak)m/s)")
            }
        }
    }
}
