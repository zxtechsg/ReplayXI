import XCTest
import RealityKit
import simd
@testable import ReplayXI

@MainActor
final class ReplayNativeBallPhysicsTests: XCTestCase {
    func testRealityKitActuallyAdvancesFreeFallWithoutAuthoredPath() throws {
        let world = try ReplayNativeBallPhysicsWorld(includePitch: false)
        world.placeBall(position: [0, 3, 0])
        try world.start()
        for _ in 0..<60 { try world.advance(ReplayNativeBallPhysics.step) }
        let sample = world.sample(at: 0.5)
        XCTAssertLessThan(sample.position.y, 2.1, "Must tick RealityKit gravity, not hold a source transform")
        XCTAssertGreaterThan(sample.position.y, 1.3)
        XCTAssertLessThan(sample.velocity.y, -4.0)
        XCTAssertEqual(world.ball.components[PhysicsBodyComponent.self]?.mode, .dynamic)
        XCTAssertNotNil(world.root.components[PhysicsSimulationComponent.self])
        XCTAssertTrue(world.ball.components[PhysicsBodyComponent.self]?.isContinuousCollisionDetectionEnabled == true)
    }

    func testNativePitchContactBouncesAndDoesNotTunnelThroughGround() throws {
        let world = try ReplayNativeBallPhysicsWorld()
        world.placeBall(position: [0, 1.4, 0], velocity: [0, -8, 0])
        try world.start()
        var minimumHeight = Float.infinity
        var bounced = false
        for index in 0..<240 {
            try world.advance(ReplayNativeBallPhysics.step)
            let sample = world.sample(at: Double(index + 1) * ReplayNativeBallPhysics.step)
            minimumHeight = min(minimumHeight, sample.position.y)
            bounced = bounced || sample.velocity.y > 0.5
        }
        XCTAssertGreaterThan(minimumHeight, 0.07)
        XCTAssertTrue(bounced, "Pitch restitution must be handled by native contact resolution")
    }

    func testRollingUsesNativeRotationAndLosesPace() throws {
        let world = try ReplayNativeBallPhysicsWorld()
        world.placeBall(position: [0, 0.113, 0], velocity: [4, 0, 0],
                        angularVelocity: [0, 0, -4 / ReplayNativeBallPhysics.radius])
        try world.start()
        var rotations: [simd_quatf] = []
        for index in 0..<360 {
            try world.advance(ReplayNativeBallPhysics.step)
            if index % 30 == 0 { rotations.append(world.ball.orientation) }
        }
        let sample = world.sample(at: 3)
        XCTAssertGreaterThan(sample.position.x, 2)
        XCTAssertLessThan(sample.position.x, 12)
        XCTAssertGreaterThan(sample.position.y, 0.07)
        XCTAssertLessThan(sample.position.y, 0.15)
        XCTAssertLessThan(sample.velocity.x, 3.7)
        XCTAssertTrue(rotations.contains { abs($0.real) < 0.8 }, "Native angular velocity must rotate the ball")
    }

    func testRecordingSeekIsImmutableAndRateIndependent() async throws {
        let track = BallTrack(keyframes: [
            .init(time: 0, position: .zero, height: 2),
            .init(time: 2, position: .zero, height: 0.11)
        ])
        let recording = try await ReplayNativeBallPhysics.bake(track: track, players: [])
        XCTAssertEqual(recording.nativeStepCount, 240)
        XCTAssertEqual(recording.ballTrack.keyframes.count, 241)
        XCTAssertLessThan(recording.pose(at: 0.5).height, 1.2)
        let expected = recording.sample(at: 0.617)
        for time in [1.7, 0.1, 0.617, 2, 0.0, 0.617] { _ = recording.sample(at: time) }
        let repeated = recording.sample(at: 0.617)
        XCTAssertEqual(expected.position, repeated.position)
        XCTAssertEqual(expected.velocity, repeated.velocity)
        XCTAssertEqual(expected.orientation.vector, repeated.orientation.vector)
        XCTAssertEqual(recording.sample(at: -.infinity).position, recording.samples[0].position)
        XCTAssertEqual(recording.sample(at: 200).position, recording.samples.last?.position)
    }

    func testNativeBodyCollisionStopsATorsoHeightShot() throws {
        let player = PlayerTrack(id: "physics-blocker", displayName: "Blocker", role: "CB", shirtNumber: 4,
                                 team: .away, isGoalkeeper: false,
                                 keyframes: [.init(time: 0, position: .zero, facingDegrees: 0),
                                             .init(time: 2, position: .zero, facingDegrees: 0)])
        let track = BallTrack(keyframes: [.init(time: 0, position: .init(x: -2, z: 0), height: 1.2),
                                         .init(time: 1, position: .init(x: 2, z: 0), height: 1.2)])
        let world = try ReplayNativeBallPhysicsWorld(gravity: .zero, includePitch: false)
        world.placeBall(position: [-2, 1.2, 0], velocity: [12, 0, 0])
        world.addPlayers([player], ball: track, at: 0)
        try world.start()
        var maximumX: Float = -2
        var deflected = false
        for index in 0..<90 {
            let time = Double(index) * ReplayNativeBallPhysics.step
            world.movePlayers([player], ball: track, time: time, delta: ReplayNativeBallPhysics.step)
            try world.advance(ReplayNativeBallPhysics.step)
            let sample = world.sample(at: time + ReplayNativeBallPhysics.step)
            maximumX = max(maximumX, sample.position.x)
            deflected = deflected || sample.velocity.x < 0
        }
        XCTAssertLessThan(maximumX, -0.25, "Native collision should stop the ball before the torso centre")
        XCTAssertTrue(deflected)
    }

    func testKickAppliesOnlyWithinPlayerReachAndCacheKeepsNumbers() async throws {
        ReplayNativeBallPhysics.resetCacheForTesting()
        let player = PlayerTrack(id: "physics-kicker", displayName: "Kicker", role: "CM", shirtNumber: 8,
                                 team: .home, isGoalkeeper: false,
                                 keyframes: [.init(time: 0, position: .init(x: 0, z: -0.5), facingDegrees: 0),
                                             .init(time: 2, position: .init(x: 0, z: -0.5), facingDegrees: 0)])
        let track = BallTrack(keyframes: [.init(time: 0, position: .zero, height: 0.112),
                                         .init(time: 2, position: .init(x: 0, z: 8), height: 0.11)])
        let plan: [ReplayNativeBallPhysics.PlannedTouch] = [
            .init(time: 0, playerID: player.id, target: .init(x: 0, z: 8), arrivalTime: 2),
            .init(time: 1, playerID: player.id, target: .init(x: 5, z: 8), arrivalTime: 2)
        ]
        let recording = try await ReplayNativeBallPhysics.prewarm(track: track, players: [player], plannedTouches: plan)
        XCTAssertEqual(recording.touches.count, 1)
        XCTAssertEqual(recording.missedTouchCount, 1, "Out-of-reach player must not remotely redirect the ball")
        XCTAssertGreaterThan(recording.samples.last?.position.z ?? 0, 3)
        XCTAssertLessThan(abs(recording.samples.last?.position.x ?? .infinity), 0.5,
                          "Preparing the first boot pose at a different sphere origin must not add a side kick")
        XCTAssertEqual(recording.touches.first?.playerID, player.id)
        XCTAssertGreaterThan(recording.touches.first?.outgoingVelocity.z ?? 0, 4)
        let metrics: [String: Any] = [
            "nativeSteps": recording.nativeStepCount,
            "admittedTouches": recording.touches.count,
            "missedTouches": recording.missedTouchCount,
            "targetZ": 8,
            "actualFinalZ": recording.samples.last?.position.z ?? 0,
            "actualFinalX": recording.samples.last?.position.x ?? 0,
            "actualFinalSpeed": recording.samples.last.map { simd_length($0.velocity) } ?? 0,
            "kickSpeed": recording.touches.first.map { simd_length($0.outgoingVelocity) } ?? 0,
            "earlySamples": recording.diagnostics.map {
                ["time": $0.time, "p": [$0.position.x, $0.position.y, $0.position.z],
                 "v": [$0.velocity.x, $0.velocity.y, $0.velocity.z], "nearest": $0.nearestColliders] as [String: Any]
            }
        ]
        let attachment = XCTAttachment(data: try JSONSerialization.data(withJSONObject: metrics, options: [.prettyPrinted]),
                                       uniformTypeIdentifier: "public.json")
        attachment.name = "NativeBallKickPhysicsMetrics"
        attachment.lifetime = .keepAlways
        add(attachment)
        XCTAssertEqual(ReplayNativeBallPhysics.cacheCountForTesting, 0,
                       "Incomplete explicit plans must not be kept as a successful warm result")
        XCTAssertNil(ReplayNativeBallPhysics.cached(track: track, players: [player], plannedTouches: plan))
        let successfulPlan = [plan[0]]
        let complete = try await ReplayNativeBallPhysics.prewarm(track: track, players: [player], plannedTouches: successfulPlan)
        XCTAssertEqual(complete.missedTouchCount, 0)
        let cached = try await ReplayNativeBallPhysics.prewarm(track: track, players: [player], plannedTouches: successfulPlan)
        XCTAssertTrue(cached === complete)
        XCTAssertEqual(ReplayNativeBallPhysics.cacheCountForTesting, 1)
        XCTAssertNil(ReplayNativeBallPhysics.cached(track: track, players: [player], plannedTouches: []))
    }

    func testInvalidInputCannotEnterTheSolverOrCache() async throws {
        ReplayNativeBallPhysics.resetCacheForTesting()
        let invalid = BallTrack(keyframes: [.init(time: 0, position: .zero, height: 0.11),
                                           .init(time: 91, position: .zero, height: 0.11)])
        do {
            _ = try await ReplayNativeBallPhysics.prewarm(track: invalid, players: [])
            XCTFail("Over-budget simulation must be rejected")
        } catch {
            XCTAssertEqual(error as? ReplayNativeBallPhysics.Failure, .invalidInput)
        }
        XCTAssertEqual(ReplayNativeBallPhysics.cacheCountForTesting, 0)
    }

    func testNativeGoalPostDeflectsAndBackNetContainsTheShot() throws {
        for x: Float in [0, 3.72] {
            let world = try ReplayNativeBallPhysicsWorld(gravity: .zero)
            world.placeBall(position: [x, 1.2, 50], velocity: [0, 0, 20])
            try world.start()
            var maximumZ: Float = 50
            var reversed = false
            for index in 0..<90 {
                try world.advance(ReplayNativeBallPhysics.step)
                let sample = world.sample(at: Double(index + 1) * ReplayNativeBallPhysics.step)
                maximumZ = max(maximumZ, sample.position.z)
                reversed = reversed || sample.velocity.z < -0.1
            }
            XCTAssertTrue(reversed, "An actual static goal surface must respond to the dynamic ball")
            XCTAssertLessThan(maximumZ, x == 0 ? 54.70 : 52.50)
            if x == 0 { XCTAssertGreaterThan(maximumZ, 53) }
        }
    }

    func testHeaderAndSaveHaveSeparateHeightAndPlayerAdmission() throws {
        func player(keeper: Bool) -> PlayerTrack {
            PlayerTrack(id: keeper ? "keeper" : "header", displayName: "Player", role: "Test", shirtNumber: 1,
                        team: .home, isGoalkeeper: keeper,
                        keyframes: [.init(time: 0, position: .zero, facingDegrees: 0),
                                    .init(time: 1, position: .zero, facingDegrees: 0)])
        }
        let world = try ReplayNativeBallPhysicsWorld(gravity: .zero, includePitch: false)
        world.placeBall(position: [0, 1.72, 0.4])
        try world.start()
        let header = ReplayNativeBallPhysics.Intent(time: 0, player: player(keeper: false),
                                                    target: [0, 0.11, 5], arrivalTime: 0.6, loft: 0.11,
                                                    kind: .header, kickingLeg: .right)
        XCTAssertEqual(try world.strike(intent: header, time: 0)?.kind, .header)
        // The first 120 Hz update can initialise an internal physics tick.
        // Require the impulse to produce real motion across four updates.
        for _ in 0..<4 { try world.advance(ReplayNativeBallPhysics.step) }
        XCTAssertGreaterThan(world.sample(at: ReplayNativeBallPhysics.step * 4).velocity.z, 0)
        XCTAssertGreaterThan(world.ball.position.z, 0.4)
        world.placeBall(position: [0, 0.11, 0.4])
        XCTAssertNil(try world.strike(intent: header, time: 0), "A low ball cannot be headed")
        let invalidSave = ReplayNativeBallPhysics.Intent(time: 0, player: player(keeper: false),
                                                         target: [0, 0.11, 5], arrivalTime: 0.6, loft: 0.11,
                                                         kind: .save, kickingLeg: .right)
        XCTAssertNil(try world.strike(intent: invalidSave, time: 0))
        let save = ReplayNativeBallPhysics.Intent(time: 0, player: player(keeper: true),
                                                  target: [0, 0.11, 5], arrivalTime: 0.6, loft: 0.11,
                                                  kind: .save, kickingLeg: .right)
        XCTAssertEqual(try world.strike(intent: save, time: 0)?.kind, .save)
    }

    func testNativeAimHitsGroundAndLoftTargetsWithoutSteeringAfterLaunch() throws {
        for (distance, height, duration): (Float, Float, Double) in [(8, 0.11, 2), (20, 0.11, 2.2), (15, 1.65, 1.5)] {
            let start = SIMD3<Float>(0, 0.112, 0)
            let target = SIMD3<Float>(distance, height, 0)
            let velocity = try ReplayNativeBallPhysicsAim.velocity(from: start, to: target, duration: duration, spinScale: 1)
            let world = try ReplayNativeBallPhysicsWorld(includeGoals: false)
            world.placeBall(position: start)
            try world.start()
            world.applyContactVelocity(velocity, spinScale: 1)
            let steps = Int(ceil(duration / ReplayNativeBallPhysics.step))
            for index in 0..<steps {
                try world.advance(min(ReplayNativeBallPhysics.step, duration - Double(index) * ReplayNativeBallPhysics.step))
            }
            let result = world.sample(at: duration)
            XCTAssertEqual(result.position.x, distance, accuracy: 0.15)
            XCTAssertEqual(result.position.z, 0, accuracy: 0.001)
            XCTAssertEqual(result.position.y, height, accuracy: 0.10)
        }
    }

    func testNativeAimPreviewCannotAdvanceOrMoveTheActualMatchWorld() throws {
        let actual = try ReplayNativeBallPhysicsWorld()
        actual.placeBall(position: [3, 2, -4], velocity: [1, 0, 2])
        try actual.start()
        let before = actual.sample(at: 0)
        _ = try ReplayNativeBallPhysicsAim.velocity(from: [0, 0.112, 0], to: [20, 0.11, 0],
                                                    duration: 2.2, spinScale: 1)
        let after = actual.sample(at: 0)
        XCTAssertEqual(before.position, after.position)
        XCTAssertEqual(before.velocity, after.velocity)
        XCTAssertEqual(before.orientation.vector, after.orientation.vector)
    }

    func testHeadHeightShotCollidesButClearlyOverheadBallPasses() throws {
        let player = PlayerTrack(id: "head-blocker", displayName: "Player", role: "CB", shirtNumber: 4,
                                 team: .away, isGoalkeeper: false,
                                 keyframes: [.init(time: 0, position: .zero, facingDegrees: 0),
                                             .init(time: 1, position: .zero, facingDegrees: 0)])
        for height: Float in [1.85, 2.30] {
            let track = BallTrack(keyframes: [.init(time: 0, position: .init(x: -2, z: 0), height: height),
                                             .init(time: 1, position: .init(x: 2, z: 0), height: height)])
            let world = try ReplayNativeBallPhysicsWorld(gravity: .zero, includePitch: false)
            world.placeBall(position: [-2, height, 0], velocity: [8, 0, 0])
            world.addPlayers([player], ball: track, at: 0)
            try world.start()
            for index in 0..<60 {
                world.movePlayers([player], ball: track, time: Double(index) * ReplayNativeBallPhysics.step,
                                  delta: ReplayNativeBallPhysics.step)
                try world.advance(ReplayNativeBallPhysics.step)
            }
            if height < 2 { XCTAssertLessThan(world.ball.position.x, 0) }
            else { XCTAssertGreaterThan(world.ball.position.x, 1) }
        }
    }
}
