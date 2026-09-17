import RealityKit
import XCTest
@testable import ReplayXI

@MainActor
final class ReplayBallRollingTests: XCTestCase {
    private let matchViews: [ReplayViewMode] = [.firstPerson, .tacticalTable, .touchline]

    private func update(_ root: Entity, scenario: ReplayScenario, time: Double,
                        view: ReplayViewMode = .firstPerson) throws -> simd_quatf {
        PitchSceneFactory.update(
            root: root, scenario: scenario, time: time, viewMode: view,
            perspectiveID: scenario.defaultPerspectiveID, marks: [], showsLaneLens: false,
            isDrawing: false, positionalOriginTransform: nil
        )
        return try XCTUnwrap(root.findEntity(named: "ball")).orientation
    }

    private func scenario(ball: BallTrack, includesPlayer: Bool = true) -> ReplayScenario {
        let player = PlayerTrack(
            id: "ball-roll-viewer", displayName: "Viewer", role: "Midfielder", shirtNumber: 8,
            team: .home, isGoalkeeper: false,
            keyframes: [.init(time: 0, position: .init(x: -30, z: -40), facingDegrees: 0)]
        )
        return ReplayScenario(
            id: "ball-roll-fixture", kind: .squadReplay, title: "Rolling fixture", strapline: "",
            matchContext: "Synthetic test", objective: "", coachPrompt: "", proofPoint: "",
            duration: max(ball.keyframes.last?.time ?? 0, 1), defaultViewMode: .firstPerson,
            defaultPerspectiveID: player.id, featuredPerspectiveIDs: [player.id],
            players: includesPlayer ? [player] : [],
            ball: ball, moments: [], coachMarks: [], formationTargets: []
        )
    }

    private func frame(_ time: Double, x: Float, z: Float) -> BallKeyframe {
        .init(time: time, position: .init(x: x, z: z), height: 0.11)
    }

    private func assertRotation(_ actual: simd_quatf, matches expected: simd_quatf,
                                _ context: String, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(simd_length(actual.vector), 1, accuracy: 0.00001, context, file: file, line: line)
        XCTAssertEqual(simd_length(expected.vector), 1, accuracy: 0.00001, context, file: file, line: line)
        XCTAssertEqual(abs(simd_dot(simd_normalize(actual).vector, simd_normalize(expected).vector)),
                       1, accuracy: 0.00001, context, file: file, line: line)
    }

    private func assertIdentity(_ actual: simd_quatf, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(actual.vector, SIMD4<Float>(0, 0, 0, 1), file: file, line: line)
        XCTAssertEqual(simd_length(actual.vector), 1, accuracy: 0.00001, file: file, line: line)
    }

    func testMotionlessDemoTailDoesNotKeepSpinning() throws {
        let scenario = try XCTUnwrap(DemoScenarios.scenario(for: .squadReplay))
        let root = PitchSceneFactory.makeMatchRoot(for: scenario)
        var report: [[String: Any]] = []
        for view in matchViews {
            let expected = try update(root, scenario: scenario, time: 27, view: view)
            let position = scenario.ball.pose(at: 27)
            for time in [28.0, 29, 30, 32] {
                XCTAssertEqual(scenario.ball.pose(at: time).position, position.position)
                XCTAssertEqual(scenario.ball.pose(at: time).height, position.height, accuracy: 0.000001)
                let actual = try update(root, scenario: scenario, time: time, view: view)
                let agreement = abs(simd_dot(expected.vector, actual.vector))
                report.append(["view": view.rawValue, "time": time, "rotationAgreement": agreement,
                               "orientation": [actual.vector.x, actual.vector.y, actual.vector.z, actual.vector.w]])
                assertRotation(actual, matches: expected, "\(view.rawValue) still ball at \(time)")
            }
        }
        let data = try JSONSerialization.data(withJSONObject: ["samples": report], options: [.sortedKeys])
        let attachment = XCTAttachment(data: data, uniformTypeIdentifier: "public.json")
        attachment.name = "ReplayXI-BallRolling-StationaryTail.json"
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    func testStraightGroundTravelRollsAboutTheCorrectAxisByDistance() throws {
        let quarterTurnDistance: Float = 0.11 * .pi / 2
        for (end, axis) in [
            (PitchPoint(x: quarterTurnDistance, z: 0), SIMD3<Float>(0, 0, -1)),
            (PitchPoint(x: -quarterTurnDistance, z: 0), SIMD3<Float>(0, 0, 1)),
            (PitchPoint(x: 0, z: quarterTurnDistance), SIMD3<Float>(1, 0, 0)),
            (PitchPoint(x: 0, z: -quarterTurnDistance), SIMD3<Float>(-1, 0, 0)),
        ] {
            let scenario = scenario(ball: .init(keyframes: [frame(0, x: 0, z: 0),
                                                            frame(1, x: end.x, z: end.z)]))
            let root = PitchSceneFactory.makeMatchRoot(for: scenario)
            for time in [0.0, 0.25, 0.5, 1.0] {
                let actual = try update(root, scenario: scenario, time: time)
                let expected = simd_quatf(angle: Float(time) * .pi / 2, axis: axis)
                assertRotation(actual, matches: expected, "\(end) at \(time)")
            }
        }
    }

    func testDirectionChangePreservesAccumulatedRotationAndThenStops() throws {
        let distance: Float = 0.11 * .pi / 2
        let scenario = scenario(ball: .init(keyframes: [
            frame(0, x: 0, z: 0), frame(1, x: distance, z: 0),
            frame(2, x: distance, z: distance), frame(3, x: distance, z: distance),
        ]))
        let root = PitchSceneFactory.makeMatchRoot(for: scenario)
        let first = simd_quatf(angle: .pi / 2, axis: [0, 0, -1])
        let path = ReplayBallPlaybackMotion(track: scenario.ball, players: scenario.players)
        for time in [1.0, 1.25, 1.5, 1.75, 2, 2.5, 3] {
            let nextAngle = path.pose(at: time).position.z / ReplayBallRollingMotion.nominalRadius
            let expected = simd_quatf(angle: nextAngle, axis: [1, 0, 0]) * first
            assertRotation(try update(root, scenario: scenario, time: time), matches: expected,
                           "World-space segment rotations must compose, not restart, at \(time)")
        }
    }

    func testDemoRollingDoesNotJumpAtAuthoredPassAndStopBoundaries() throws {
        let scenario = try XCTUnwrap(DemoScenarios.scenario(for: .squadReplay))
        let root = PitchSceneFactory.makeMatchRoot(for: scenario)
        for frame in scenario.ball.keyframes.dropFirst().dropLast() {
            let before = try update(root, scenario: scenario, time: frame.time - 0.0001)
            let after = try update(root, scenario: scenario, time: frame.time + 0.0001)
            XCTAssertGreaterThan(abs(simd_dot(before.vector, after.vector)), 0.999,
                                 "Ball spin jumped at \(frame.time)")
        }
    }

    func testGroundedPositionalMarkerHasFixedOrientation() throws {
        let scenario = try XCTUnwrap(DemoScenarios.scenario(for: .shapeLab))
        let root = PitchSceneFactory.makeMatchRoot(for: scenario)
        for time in [0.0, 5, 13.6, 14.15, 25.4, 32, 13.6] {
            assertRotation(try update(root, scenario: scenario, time: time, view: .positional),
                           matches: simd_quatf(real: 1, imag: .zero), "Grounded Shape marker at \(time)")
        }
    }

    func testRollingRepeatsExactlyAcrossReverseSeekCadenceAndMatchViews() throws {
        let scenario = try XCTUnwrap(DemoScenarios.scenario(for: .squadReplay))
        let source = scenario.ball
        let root = PitchSceneFactory.makeMatchRoot(for: scenario)
        let times: [Double] = [0, 0.5, 2.8, 4, 6.2, 10.1, 13.6, 14.15, 17.5, 27, 29, 32]
        let expected = try times.map { try update(root, scenario: scenario, time: $0).vector }
        for view in matchViews {
            for index in times.indices.reversed() {
                XCTAssertEqual(try update(root, scenario: scenario, time: times[index], view: view).vector,
                               expected[index])
            }
            for index in [3, 0, 11, 7, 3, 9, 2, 6, 3] {
                XCTAssertEqual(try update(root, scenario: scenario, time: times[index], view: view).vector,
                               expected[index])
            }
        }
        XCTAssertEqual(scenario.ball, source)
    }

    func testMalformedTracksAndRadiiFailClosedToFiniteIdentity() {
        let first = frame(0, x: 0, z: 0)
        let last = frame(1, x: 1, z: 0)
        let malformed: [[BallKeyframe]] = [
            [], [first], [first, first], [last, first],
            [frame(.nan, x: 0, z: 0), last], [first, frame(.infinity, x: 1, z: 0)],
            [first, frame(1_000_001, x: 1, z: 0)],
            [frame(-1_000_001, x: 0, z: 0), last],
            [first, frame(1, x: .nan, z: 0)], [first, frame(1, x: 0, z: .infinity)],
            [first, frame(1, x: 10_001, z: 0)], [first, frame(1, x: 0, z: -10_001)],
            [first, .init(time: 1, position: .zero, height: .nan)],
            [first, .init(time: 1, position: .zero, height: 10_001)],
            [first, last, frame(0.5, x: 3, z: 4)],
        ]
        let queries: [Double] = [-1, 0, 0.5, 1, 10, .nan, .infinity, -.infinity]
        for frames in malformed {
            let motion = ReplayBallRollingMotion(track: .init(keyframes: frames))
            XCTAssertFalse(motion.isValid)
            XCTAssertEqual(motion.segmentCount, 0)
            for time in queries { assertIdentity(motion.orientation(at: time)) }
        }
        for radius: Float in [0, -1, .nan, .infinity, 0.0001, 10.001] {
            let motion = ReplayBallRollingMotion(track: .init(keyframes: [first, last]), radius: radius)
            XCTAssertFalse(motion.isValid)
            for time in queries { assertIdentity(motion.orientation(at: time)) }
        }
    }

    func testPreparedDataHasAHardKeyframeBound() {
        let frames = (0..<ReplayBallRollingMotion.maximumKeyframes).map {
            frame(Double($0), x: 0, z: 0)
        }
        let maximum = ReplayBallRollingMotion(track: .init(keyframes: frames))
        XCTAssertTrue(maximum.isValid)
        XCTAssertEqual(maximum.segmentCount, ReplayBallRollingMotion.maximumKeyframes - 1)
        assertIdentity(maximum.orientation(at: 0))
        assertIdentity(maximum.orientation(at: 40_000.5))
        var tooMany = frames
        tooMany.append(frame(Double(frames.count), x: 0, z: 0))
        let rejected = ReplayBallRollingMotion(track: .init(keyframes: tooMany))
        XCTAssertFalse(rejected.isValid)
        XCTAssertEqual(rejected.segmentCount, 0)
    }

    func testFiniteQueriesClampToEndpointsAndNonFiniteQueriesReturnIdentity() {
        let distance: Float = 0.11 * .pi / 2
        let motion = ReplayBallRollingMotion(track: .init(keyframes: [
            frame(2, x: 0, z: 0), frame(4, x: distance, z: 0),
        ]))
        XCTAssertTrue(motion.isValid)
        let final = motion.orientation(at: 4).vector
        for time in [-Double.greatestFiniteMagnitude, -1, 0, 2] {
            assertIdentity(motion.orientation(at: time))
        }
        for time in [4.0, 5, Double.greatestFiniteMagnitude] {
            XCTAssertEqual(motion.orientation(at: time).vector, final)
            XCTAssertEqual(simd_length(motion.orientation(at: time).vector), 1, accuracy: 0.00001)
        }
        for time: Double in [.nan, .infinity, -.infinity] {
            assertIdentity(motion.orientation(at: time))
        }
    }

    func testManyTurnSegmentsRetainDoublePrecisionAndUnitRotations() {
        let distance: Float = 9_999
        let radius = ReplayBallRollingMotion.nominalRadius
        let motion = ReplayBallRollingMotion(track: .init(keyframes: [
            frame(0, x: 0, z: 0), frame(10, x: distance, z: 0),
        ]))
        for step in 0...400 {
            let fraction = Double(step) / 400
            let actual = motion.orientation(at: fraction * 10)
            let reference = simd_quatd(angle: Double(distance) * fraction / Double(radius), axis: [0, 0, -1])
            let expected = simd_quatf(vector: SIMD4<Float>(Float(reference.vector.x), Float(reference.vector.y),
                                                          Float(reference.vector.z), Float(reference.vector.w)))
            assertRotation(actual, matches: expected, "Many-turn sample \(step)")
            XCTAssertEqual(simd_length(actual.vector), 1, accuracy: 0.00001)
        }
    }

    func testAirborneSpinIsOnlyTheSameHorizontalPathApproximation() {
        let grounded = BallTrack(keyframes: [frame(0, x: 0, z: 0), frame(1, x: 2, z: 3)])
        let airborne = BallTrack(keyframes: [
            .init(time: 0, position: .zero, height: 0.11),
            .init(time: 1, position: .init(x: 2, z: 3), height: 4),
        ])
        let groundMotion = ReplayBallRollingMotion(track: grounded)
        let airMotion = ReplayBallRollingMotion(track: airborne)
        for step in 0...100 {
            let time = Double(step) / 100
            XCTAssertEqual(groundMotion.orientation(at: time).vector, airMotion.orientation(at: time).vector)
        }
        let verticalOnly = ReplayBallRollingMotion(track: .init(keyframes: [
            .init(time: 0, position: .zero, height: 0.11),
            .init(time: 1, position: .zero, height: 4),
        ]))
        assertIdentity(verticalOnly.orientation(at: 0))
        assertIdentity(verticalOnly.orientation(at: 0.5))
    }

    func testSamplerIsPreparedOncePerRootAndSurvivesAnnotationCacheEviction() throws {
        let scenario = scenario(ball: .init(keyframes: [frame(0, x: 0, z: 0), frame(2, x: 1, z: 2)]))
        let root = PitchSceneFactory.makeMatchRoot(for: scenario)
        let prepared = try XCTUnwrap(PitchSceneFactory.ballRollingMotionForTesting(in: root))
        XCTAssertEqual(prepared.segmentCount, 180)
        var otherRoots: [Entity] = []
        for _ in 0..<8 { otherRoots.append(PitchSceneFactory.makeMatchRoot(for: scenario)) }
        let other = try XCTUnwrap(PitchSceneFactory.ballRollingMotionForTesting(in: otherRoots[0]))
        XCTAssertFalse(prepared === other)
        for view in matchViews + [.positional] {
            for time in [0.0, 1, 2, 0.5, 1.5, 0] {
                _ = try update(root, scenario: scenario, time: time, view: view)
                XCTAssertTrue(PitchSceneFactory.ballRollingMotionForTesting(in: root) === prepared)
            }
        }
        XCTAssertEqual(otherRoots.count, 8)
    }

    func testRollingCacheDoesNotOutliveItsMatchRoot() {
        let scenario = scenario(ball: .init(keyframes: [frame(0, x: 0, z: 0), frame(1, x: 1, z: 0)]),
                                includesPlayer: false)
        weak var releasedRoot: Entity?
        weak var releasedMotion: ReplayBallRollingMotion?
        autoreleasepool {
            let root = PitchSceneFactory.makeMatchRoot(for: scenario)
            releasedRoot = root
            releasedMotion = PitchSceneFactory.ballRollingMotionForTesting(in: root)
            XCTAssertNotNil(releasedMotion)
        }
        XCTAssertNil(releasedRoot)
        XCTAssertNil(releasedMotion)
    }
}
