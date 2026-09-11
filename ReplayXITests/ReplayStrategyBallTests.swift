import RealityKit
import XCTest
@testable import ReplayXI

@MainActor
final class ReplayStrategyBallTests: XCTestCase {
    func testBundledBlenderBallLoadsAtFootballScaleWithinRenderBudget() throws {
        try ReplayStrategyBallProvider.prewarm()
        let ball = try XCTUnwrap(ReplayStrategyBallProvider.makeInstance())
        let models = ReplayStrategyBallProvider.models(in: ball)
        XCTAssertEqual(models.count, 1)
        let model = try XCTUnwrap(models.first?.model)
        XCTAssertEqual(model.materials.count, 2)
        let parts = model.mesh.contents.models.flatMap { Array($0.parts) }
        let indexCount = parts.reduce(0) { $0 + ($1.triangleIndices?.count ?? 0) }
        XCTAssertEqual(indexCount / 3, 2_592)
        let bounds = ball.visualBounds(relativeTo: ball)
        for axis in 0..<3 {
            XCTAssertEqual(bounds.extents[axis], 0.22, accuracy: 0.004)
            XCTAssertEqual(bounds.center[axis], 0, accuracy: 0.002)
        }
    }

    func testBallInstancesHaveIndependentTransformsAndKeepReplayIdentity() throws {
        try ReplayStrategyBallProvider.prewarm()
        let first = try XCTUnwrap(ReplayStrategyBallProvider.makeInstance())
        let second = try XCTUnwrap(ReplayStrategyBallProvider.makeInstance())
        first.position = [1, 2, 3]
        XCTAssertFalse(first === second)
        XCTAssertEqual(second.position, .zero)
        let scene = PitchSceneFactory.makeMatchRoot(for: DemoScenarios.all[0])
        let replayBall = try XCTUnwrap(scene.findEntity(named: "ball"))
        XCTAssertNotNil(replayBall.findEntity(named: ReplayStrategyBallProvider.visualRootName))
    }
}
