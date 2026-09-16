import RealityKit
import XCTest
@testable import ReplayXI

@MainActor
final class ReplayBallGroundClearanceTests: XCTestCase {
    override func tearDown() {
        ReplayStrategyBallProvider.resetForTesting()
        super.tearDown()
    }

    private let views: [(ReplayViewMode, Float)] = [
        (.firstPerson, 1), (.tacticalTable, 3.2), (.touchline, 1.5), (.positional, 1.8),
    ]

    private func scene(usingBlender: Bool) throws -> (ReplayScenario, Entity, Entity, Entity) {
        ReplayStrategyBallProvider.resetForTesting()
        if usingBlender { try ReplayStrategyBallProvider.prewarm() }
        let scenario = try XCTUnwrap(DemoScenarios.scenario(for: .squadReplay))
        let root = PitchSceneFactory.makeMatchRoot(for: scenario)
        let ball = try XCTUnwrap(root.findEntity(named: "ball"))
        let shadow = try XCTUnwrap(root.findEntity(named: "ball-shadow"))
        XCTAssertEqual(ball.findEntity(named: ReplayStrategyBallProvider.visualRootName) != nil, usingBlender)
        XCTAssertEqual(ball.findEntity(named: "ball-shell") != nil, !usingBlender)
        return (scenario, root, ball, shadow)
    }

    private func update(_ root: Entity, scenario: ReplayScenario, time: Double, view: ReplayViewMode) {
        PitchSceneFactory.update(
            root: root, scenario: scenario, time: time, viewMode: view,
            perspectiveID: scenario.defaultPerspectiveID, marks: [], showsLaneLens: false,
            isDrawing: false, positionalOriginTransform: nil
        )
    }

    private func assertPresentation(ball: Entity, shadow: Entity, physicalHeight: Float,
                                    view: ReplayViewMode, scale: Float,
                                    asset: String, time: Double) -> [String: Any] {
        let radius: Float = 0.11
        let presentedHeight: Float = view == .positional ? radius : max(physicalHeight, radius)
        let expectedLift = presentedHeight - radius
        let actualLift = ball.position.y - radius * scale
        let label = "\(asset) \(view.rawValue) at \(time)"
        XCTAssertEqual(ball.scale, SIMD3<Float>(repeating: scale))
        XCTAssertEqual(actualLift, expectedLift, accuracy: 0.00001,
                       "\(label): visual enlargement must preserve the ball's bottom altitude")

        // Inspect the loaded geometry in its own frame. Rotating a sphere's
        // bounding BOX would falsely report penetration despite a clear mesh.
        // A few millimetres cover the fallback's raised decorative panels.
        let geometry = ball.visualBounds(relativeTo: ball)
        XCTAssertEqual(geometry.extents.max(), radius * 2, accuracy: 0.004)
        XCTAssertLessThan(simd_length(geometry.center), 0.002)
        let axisAlignedGeometryLift = ball.position.y + geometry.min.y * scale
        XCTAssertEqual(axisAlignedGeometryLift, expectedLift, accuracy: 0.006,
                       "\(label): loaded ball geometry must not be buried in the turf")

        let expectedSpread = 1 + min(expectedLift * 0.16, 0.65)
        XCTAssertEqual(shadow.position.x, ball.position.x)
        XCTAssertEqual(shadow.position.z, ball.position.z)
        XCTAssertEqual(shadow.position.y, 0.006, accuracy: 0.00001)
        XCTAssertEqual(shadow.scale.x, scale * expectedSpread, accuracy: 0.00001,
                       "\(label): shadow lift must use presented height, not visual size or hidden loft")
        XCTAssertEqual(shadow.scale.y, 1)
        XCTAssertEqual(shadow.scale.z, scale * expectedSpread * 0.74, accuracy: 0.00001)
        return [
            "asset": asset, "view": view.rawValue, "time": time, "scale": scale,
            "physicalHeight": physicalHeight, "presentedHeight": presentedHeight,
            "visualCentreY": ball.position.y, "expectedBottomLift": expectedLift,
            "actualBottomLift": actualLift, "axisAlignedGeometryLift": axisAlignedGeometryLift,
            "shadowScaleX": shadow.scale.x, "expectedShadowScaleX": scale * expectedSpread,
        ]
    }

    private func attach(_ samples: [[String: Any]], name: String) throws {
        let data = try JSONSerialization.data(withJSONObject: ["samples": samples], options: [.sortedKeys])
        let attachment = XCTAttachment(data: data, uniformTypeIdentifier: "public.json")
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    private func checkGround(usingBlender: Bool) throws {
        let (scenario, root, ball, shadow) = try scene(usingBlender: usingBlender)
        let asset = usingBlender ? "blender" : "procedural"
        let time = 13.6
        var samples: [[String: Any]] = []
        for (view, scale) in views {
            update(root, scenario: scenario, time: time, view: view)
            samples.append(assertPresentation(ball: ball, shadow: shadow,
                                              physicalHeight: scenario.ball.pose(at: time).height,
                                              view: view, scale: scale, asset: asset, time: time))
        }
        try attach(samples, name: "ReplayXI-BallGround-\(asset).json")
    }

    func testProceduralBallRestsOnPitchAtEveryViewScale() throws {
        try checkGround(usingBlender: false)
    }

    func testBlenderBallRestsOnPitchAtEveryViewScale() throws {
        try checkGround(usingBlender: true)
    }

    func testLoftClearanceAndShadowStayPhysicalWhilePositionalBallStaysGrounded() throws {
        let time = 14.15
        var samples: [[String: Any]] = []
        for usingBlender in [false, true] {
            let (scenario, root, ball, shadow) = try scene(usingBlender: usingBlender)
            let asset = usingBlender ? "blender" : "procedural"
            XCTAssertEqual(scenario.ball.pose(at: time).height, 0.28, accuracy: 0.00001)
            for (view, scale) in views {
                update(root, scenario: scenario, time: time, view: view)
                samples.append(assertPresentation(ball: ball, shadow: shadow,
                                                  physicalHeight: scenario.ball.pose(at: time).height,
                                                  view: view, scale: scale, asset: asset, time: time))
            }
        }
        try attach(samples, name: "ReplayXI-BallLoft-BothMeshes.json")
    }

    func testBallAndProjectedShadowRepeatExactlyAfterSeekingAndViewChanges() throws {
        for usingBlender in [false, true] {
            let (scenario, root, ball, shadow) = try scene(usingBlender: usingBlender)
            let authored = scenario.ball
            for (view, _) in views {
                update(root, scenario: scenario, time: 13.6, view: view)
                let expectedBall = ball.transform
                let expectedShadow = shadow.transform
                for (time, otherView) in [(25.4, ReplayViewMode.touchline), (0, .tacticalTable),
                                          (14.15, .positional), (13.6, view), (13.6, view)] {
                    update(root, scenario: scenario, time: time, view: otherView)
                }
                XCTAssertEqual(ball.transform, expectedBall)
                XCTAssertEqual(shadow.transform, expectedShadow)
                XCTAssertEqual(scenario.ball, authored)
            }
        }
    }
}
