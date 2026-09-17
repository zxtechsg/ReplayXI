import RealityKit
import Dispatch
import XCTest
@testable import ReplayXI

@MainActor
final class ReplayBallPlaybackMotionTests: XCTestCase {
    private func frame(_ time: Double, _ x: Float, _ z: Float = 0,
                       _ height: Float = 0.11) -> BallKeyframe {
        .init(time: time, position: .init(x: x, z: z), height: height)
    }

    func testFreeGroundPassDeceleratesWithoutChangingReleaseOrArrivalTimes() {
        let source = BallTrack(keyframes: [frame(0, 0), frame(2, 12)])
        let path = ReplayBallPlaybackMotion(track: source, players: [])
        XCTAssertTrue(path.isValid)
        XCTAssertEqual(path.pose(at: 0).position, source.keyframes[0].position)
        XCTAssertEqual(path.pose(at: 2).position, source.keyframes[1].position)
        let earlyDistance = path.pose(at: 0.4).position.x - path.pose(at: 0.2).position.x
        let lateDistance = path.pose(at: 1.8).position.x - path.pose(at: 1.6).position.x
        XCTAssertGreaterThan(earlyDistance, lateDistance * 1.15)
        XCTAssertGreaterThan(lateDistance, 0)
        for index in 0...400 {
            let pose = path.pose(at: Double(index) / 200)
            XCTAssertGreaterThanOrEqual(pose.position.x, 0)
            XCTAssertLessThanOrEqual(pose.position.x, 12)
            XCTAssertEqual(pose.height, 0.11, accuracy: 0.000001)
        }
    }

    func testLoftPreservesAuthoredHeightsAndRoundsTheApexWithoutGoingBelowTurf() {
        let source = BallTrack(keyframes: [frame(0, 0), frame(0.5, 3, 0, 0.85), frame(1, 6)])
        let path = ReplayBallPlaybackMotion(track: source, players: [])
        for keyframe in source.keyframes {
            XCTAssertEqual(path.pose(at: keyframe.time).height, keyframe.height, accuracy: 0.000001)
        }
        let before = path.pose(at: 0.49).height
        let apex = path.pose(at: 0.5).height
        let after = path.pose(at: 0.51).height
        XCTAssertLessThan(abs(apex - before), 0.002)
        XCTAssertLessThan(abs(apex - after), 0.002)
        for index in 0...300 {
            let pose = path.pose(at: Double(index) / 300)
            XCTAssertGreaterThanOrEqual(pose.height, 0.11)
            XCTAssertLessThanOrEqual(pose.height, 0.85)
        }
    }

    func testRollingUsesTheCorrectedPathAndStopsWhenTheBallStops() {
        let source = BallTrack(keyframes: [frame(0, 0), frame(2, 12), frame(4, 12)])
        let path = ReplayBallPlaybackMotion(track: source, players: [])
        for time in [0.0, 0.2, 0.8, 1.6, 2.0, 3.0, 4.0] {
            let angle = Double(path.pose(at: time).position.x) / 0.11
            let expected = simd_quatf(angle: Float(angle.truncatingRemainder(dividingBy: 2 * .pi)),
                                      axis: [0, 0, -1])
            let actual = path.rolling.orientation(at: time)
            XCTAssertEqual(abs(simd_dot(actual.vector, expected.vector)), 1, accuracy: 0.00002)
        }
        XCTAssertEqual(path.rolling.orientation(at: 2).vector, path.rolling.orientation(at: 4).vector)
    }

    func testDemoBakeIsBoundedPreservesSourceAndRepeatsAcrossUnorderedQueries() throws {
        let scenario = try XCTUnwrap(DemoScenarios.scenario(for: .squadReplay))
        let source = scenario.ball
        let path = ReplayBallPlaybackMotion(track: source, players: scenario.players)
        XCTAssertTrue(path.isValid)
        XCTAssertGreaterThan(path.contactCount, 3)
        XCTAssertGreaterThan(path.adjustedSampleCount, 0)
        XCTAssertLessThanOrEqual(path.sampleCount, ReplayBallPlaybackMotion.maximumSamples)
        let times = (0...384).map { Double($0) / 12 }
        let poses = times.map(path.pose)
        let orientations = times.map { path.rolling.orientation(at: $0).vector }
        for index in times.indices.reversed() {
            XCTAssertEqual(path.pose(at: times[index]), poses[index])
            XCTAssertEqual(path.rolling.orientation(at: times[index]).vector, orientations[index])
        }
        for keyframe in source.keyframes {
            XCTAssertEqual(path.pose(at: keyframe.time).height, keyframe.height, accuracy: 0.00001)
        }
        XCTAssertEqual(scenario.ball, source)
    }

    func testBootProxyUsesTheActualAnimatedProceduralJointChain() throws {
        let scenario = try XCTUnwrap(DemoScenarios.scenario(for: .squadReplay))
        for (id, time) in [("navy-rw", 13.6), ("navy-rb", 17.5), ("navy-cf", 24.0)] {
            let player = try XCTUnwrap(scenario.player(id: id))
            let pose = player.presentationPose(at: time)
            let rig = try ReplayAthleteFactory.make(for: player, lod: .near)
            rig.root.position = [pose.position.x, 0, pose.position.z]
            rig.root.orientation = simd_quatf(angle: pose.facingDegrees * .pi / 180, axis: [0, 1, 0])
            ReplayAthleteMotion.update(rig, from: player, at: time, ballTrack: scenario.ball)
            let envelope = ReplayBallPlayerContact(player: player, ball: scenario.ball, time: time)
            for (name, expected) in [("left-ankle", envelope.leftToe), ("right-ankle", envelope.rightToe)] {
                let ankle = try XCTUnwrap(rig.root.findEntity(named: name))
                let actual = ankle.convert(position: [0, -0.050, 0.245], to: nil)
                XCTAssertLessThan(simd_distance(actual, expected), 0.00002, "\(id) \(name)")
            }
        }
    }

    func testEntireAuthoredDemoClearsBodyAndAnimatedBootProxiesAt240Hz() throws {
        let scenario = try XCTUnwrap(DemoScenarios.scenario(for: .squadReplay))
        let started = DispatchTime.now().uptimeNanoseconds
        let path = ReplayBallPlaybackMotion(track: scenario.ball, players: scenario.players)
        let preparationMilliseconds = Double(DispatchTime.now().uptimeNanoseconds - started) / 1_000_000
        var minimumBody: Float = .greatestFiniteMagnitude
        var minimumLeg: Float = .greatestFiniteMagnitude
        var maximumSourceOffset: Float = 0
        var maximumHorizontalSpeed: Float = 0
        var previousPosition: PitchPoint?
        var bodyContext = ""
        var legContext = ""
        for index in 0...7_680 {
            let time = Double(index) / 240
            let ball = path.pose(at: time)
            let point = SIMD3<Float>(ball.position.x, ball.height, ball.position.z)
            if let previousPosition {
                maximumHorizontalSpeed = max(maximumHorizontalSpeed,
                                              ReplayGeometry.distance(previousPosition, ball.position) * 240)
            }
            previousPosition = ball.position
            maximumSourceOffset = max(maximumSourceOffset,
                                      ReplayGeometry.distance(ball.position, scenario.ball.pose(at: time).position))
            for player in scenario.players {
                let origin = player.presentationPose(at: time).position
                let separation = ReplayGeometry.distance(ball.position, origin)
                guard separation < 1.65 else { continue }
                if ball.height < ReplayBallPlaybackMotion.bodyCollisionCentreCeiling {
                    let clearance = separation - ReplayBallPlaybackMotion.bodyClearance
                    if clearance < minimumBody {
                        minimumBody = clearance
                        bodyContext = "\(player.id) at \(time)"
                    }
                }
                guard ball.height < 1.0 else { continue }
                let legs = ReplayBallPlayerContact(player: player, ball: scenario.ball, time: time)
                for (name, capsule) in [("left shin", legs.leftShin), ("right shin", legs.rightShin),
                                         ("left boot", legs.leftBoot), ("right boot", legs.rightBoot)] {
                    let clearance = simd_distance(point, capsule.nearestPoint(to: point))
                        - capsule.radius - ReplayBallPlaybackMotion.ballRadius
                    if clearance < minimumLeg {
                        minimumLeg = clearance
                        legContext = "\(player.id) \(name) at \(time)"
                    }
                }
            }
        }
        let report: [String: Any] = [
            "preparedSamples": path.sampleCount, "contactCount": path.contactCount,
            "adjustedSamples": path.adjustedSampleCount, "preparationMilliseconds": preparationMilliseconds,
            "minimumBodyClearanceMetres": minimumBody, "bodyContext": bodyContext,
            "minimumAnimatedLegClearanceMetres": minimumLeg, "legContext": legContext,
            "maximumSourceOffsetMetres": maximumSourceOffset, "validationSamplesPerSecond": 240,
            "maximumHorizontalSpeedMetresPerSecond": maximumHorizontalSpeed,
            "scope": "Authored synthetic replay; procedural body/shin/boot proxies, not exact skin meshes or FPS",
        ]
        let data = try JSONSerialization.data(withJSONObject: report, options: [.sortedKeys])
        let attachment = XCTAttachment(data: data, uniformTypeIdentifier: "public.json")
        attachment.name = "ReplayXI-BallPlayback-Clearance-Preparation.json"
        attachment.lifetime = .keepAlways
        add(attachment)
        XCTAssertGreaterThanOrEqual(minimumBody, -0.003, bodyContext)
        XCTAssertGreaterThanOrEqual(minimumLeg, -0.004, legContext)
        XCTAssertLessThanOrEqual(maximumSourceOffset, ReplayBallPlaybackMotion.maximumPresentationOffset + 0.002,
                                "Repair must remain local to the SOURCE move, not its already-eased path")
        XCTAssertLessThan(maximumHorizontalSpeed, 25, "Repair must not introduce a teleport-like ball step")
    }

    func testMalformedInputsHaveAFiniteStationaryFallback() {
        let malformed: [BallTrack] = [
            .init(keyframes: []), .init(keyframes: [frame(0, 0)]),
            .init(keyframes: [frame(1, 0), frame(0, 1)]),
            .init(keyframes: [frame(0, 0), frame(0, 1)]),
            .init(keyframes: [frame(0, .nan), frame(1, 1)]),
            .init(keyframes: [frame(0, 0), frame(.infinity, 1)]),
            .init(keyframes: [frame(0, 0), frame(1, 1, 0, -.infinity)]),
            .init(keyframes: [frame(0, 0), frame(1, 1, 0, -0.001)]),
            .init(keyframes: [frame(0, 0), frame(1, 1, 0, 20.001)]),
            .init(keyframes: [frame(0, 0), frame(1, 1, 0, 10_000)]),
            .init(keyframes: [frame(0, 0), frame(1, 150.001)]),
            .init(keyframes: [frame(0, 0), frame(1, 0, -150.001)]),
        ]
        for source in malformed {
            let path = ReplayBallPlaybackMotion(track: source, players: [])
            XCTAssertFalse(path.isValid)
            XCTAssertFalse(path.usesAuthoredFallback)
            XCTAssertEqual(path.sampleCount, 1)
            for time: Double in [-1, 0, 0.5, 1, .nan, .infinity] {
                let pose = path.pose(at: time)
                XCTAssertTrue(pose.position.x.isFinite && pose.position.z.isFinite && pose.height.isFinite)
                XCTAssertGreaterThanOrEqual(pose.height, 0.11)
                XCTAssertEqual(path.rolling.orientation(at: time).vector, SIMD4<Float>(0, 0, 0, 1))
            }
        }
    }

    func testValidLongTrackKeepsOriginalTimeAndRollWhenPreparationBudgetIsExceeded() {
        let source = BallTrack(keyframes: [frame(0, 0), frame(1_000, 10)])
        let path = ReplayBallPlaybackMotion(track: source, players: [])
        let sourceRolling = ReplayBallRollingMotion(track: source)
        XCTAssertFalse(path.isValid, "Budget fallback must not advertise repaired contacts")
        XCTAssertTrue(path.usesAuthoredFallback)
        XCTAssertEqual(path.sampleCount, 2)
        XCTAssertEqual(path.contactCount, 0)
        for time in [0.0, 125, 500, 999, 1_000, 500] {
            XCTAssertEqual(path.pose(at: time), source.pose(at: time))
            XCTAssertEqual(path.rolling.orientation(at: time).vector, sourceRolling.orientation(at: time).vector)
        }
        XCTAssertEqual(path.pose(at: 500).position.x, 5)
    }

    func testDenseFiniteTrackAbovePreparationBudgetRemainsLiveAndIsNotCachedAsRepaired() {
        let source = BallTrack(keyframes: (0...ReplayBallPlaybackMotion.maximumSourceFrames).map {
            frame(Double($0) / 120, Float($0) * 0.001)
        })
        ReplayBallPlaybackMotion.resetPreparationCacheForTesting()
        defer { ReplayBallPlaybackMotion.resetPreparationCacheForTesting() }
        let path = ReplayBallPlaybackMotion.prepared(track: source, players: [])
        XCTAssertFalse(path.isValid)
        XCTAssertTrue(path.usesAuthoredFallback)
        XCTAssertEqual(path.sampleCount, source.keyframes.count)
        XCTAssertEqual(ReplayBallPlaybackMotion.cachedPathCountForTesting, 0)
        for time in [0.0, 3.25, 8.12, 18, 32, 18, 3.25] {
            XCTAssertEqual(path.pose(at: time), source.pose(at: time))
        }
        XCTAssertGreaterThan(path.pose(at: 32).position.x, 3.8)
    }

    func testAuthoredFallbackRejectsSourceBeyondTheExistingHardFrameLimit() {
        let source = BallTrack(keyframes: (0...ReplayBallRollingMotion.maximumKeyframes).map {
            frame(Double($0) / 120, 0)
        })
        let path = ReplayBallPlaybackMotion(track: source, players: [])
        XCTAssertFalse(path.isValid)
        XCTAssertFalse(path.usesAuthoredFallback)
        XCTAssertEqual(path.sampleCount, 1)
        XCTAssertEqual(path.pose(at: 100), BallPose(position: .zero, height: 0.11))
    }
}
