import RealityKit
import XCTest
@testable import ReplayXI

@MainActor
final class ReplayShapeAthletePresentationTests: XCTestCase {
    override func setUp() {
        super.setUp()
        ReplaySkinnedAthleteProvider.resetForTesting()
    }

    override func tearDown() {
        ReplaySkinnedAthleteProvider.resetForTesting()
        ReplayAthleteHeadProvider.resetForTesting()
        super.tearDown()
    }

    func testIdealStationBodiesUseAnIdlePoseAndLookFromTheirDisplayedOrigin() throws {
        let scenario = try XCTUnwrap(DemoScenarios.scenario(for: .shapeLab))
        let source = try XCTUnwrap(scenario.formationTargets.first {
            $0.playerID == scenario.defaultPerspectiveID
        }).position
        let ball = PitchPoint(x: source.x + 0.55, z: source.z + 0.25)
        let root = PitchSceneFactory.makeMatchRoot(for: scenario)
        for time in [12.5, 14.0, 12.5] {
            update(root, scenario: scenario, time: time, ideal: true)
            for target in scenario.formationTargets {
                let player = try XCTUnwrap(scenario.player(id: target.playerID))
                let body = try XCTUnwrap(root.findEntity(named: "player-\(player.id)"))
                let rig = try XCTUnwrap(body.findEntity(named: "full-rig"))
                let facing = atan2(ball.x - target.position.x, ball.z - target.position.z) * 180 / .pi
                let stationary = PlayerTrack(
                    id: player.id, displayName: player.displayName, role: player.role,
                    shirtNumber: player.shirtNumber, team: player.team,
                    isGoalkeeper: player.isGoalkeeper,
                    keyframes: [
                        MotionKeyframe(time: 0, position: target.position, facingDegrees: facing),
                        MotionKeyframe(time: scenario.duration, position: target.position, facingDegrees: facing)
                    ]
                )
                let expected = try ReplayAthleteFactory.make(for: player, lod: .near)
                ReplayAthleteMotion.update(
                    expected, from: stationary, at: time,
                    lookTargetWorldPosition: [ball.x, 0.11, ball.z]
                )
                XCTAssertEqual(body.position.x, target.position.x, accuracy: 0.000_1)
                XCTAssertEqual(body.position.z, target.position.z, accuracy: 0.000_1)
                for joint in [ReplayAthleteJoint.leftHip, .rightHip, .leftKnee, .rightKnee, .neck, .headRoot] {
                    let actual = try XCTUnwrap(rig.findEntity(named: joint.rawValue))
                    let wanted = expected.joints[joint]
                    XCTAssertGreaterThan(
                        abs(simd_dot(actual.orientation.vector, wanted.orientation.vector)), 0.999_99,
                        "\(player.id) \(joint) must use the stationary displayed pose, not the running telemetry"
                    )
                }
            }
        }
    }

    func testProblemBodiesKeepTheirReplayAnimationAfterAnIdealComparison() throws {
        let scenario = try XCTUnwrap(DemoScenarios.scenario(for: .shapeLab))
        let root = PitchSceneFactory.makeMatchRoot(for: scenario)
        update(root, scenario: scenario, time: 12.5, ideal: true)
        update(root, scenario: scenario, time: 12.5, ideal: false)
        let source = try XCTUnwrap(scenario.player(id: scenario.defaultPerspectiveID)).presentationPose(at: 12.5).position
        let ball = SIMD3<Float>(source.x + 0.55, 0.11, source.z + 0.25)
        for target in scenario.formationTargets {
            let player = try XCTUnwrap(scenario.player(id: target.playerID))
            let body = try XCTUnwrap(root.findEntity(named: "player-\(player.id)"))
            let rig = try XCTUnwrap(body.findEntity(named: "full-rig"))
            let expected = try ReplayAthleteFactory.make(for: player, lod: .near)
            ReplayAthleteMotion.update(expected, from: player, at: 12.5, lookTargetWorldPosition: ball)
            for joint in ReplayAthleteJoint.allCases {
                let actual = try XCTUnwrap(rig.findEntity(named: joint.rawValue))
                XCTAssertEqual(actual.transform, expected.joints[joint].transform)
            }
        }
    }

    func testSkinnedStationsMatchStandingReferenceAndReturnAfterProblemAndSeek() throws {
        try ReplaySkinnedAthleteProvider.prewarm()
        let scenario = try XCTUnwrap(DemoScenarios.scenario(for: .shapeLab))
        let root = PitchSceneFactory.makeMatchRoot(for: scenario)
        var firstTransforms: [String: [Transform]] = [:]
        var sceneSamples: [[String: Any]] = []
        let stages: [(time: Double, ideal: Bool)] = [(12.5, true), (14, true), (12.5, false), (12.5, true)]

        for (index, stage) in stages.enumerated() {
            update(root, scenario: scenario, time: stage.time, ideal: stage.ideal)
            let source = try XCTUnwrap(scenario.player(id: scenario.defaultPerspectiveID))
            let origin: PitchPoint
            if stage.ideal {
                origin = try XCTUnwrap(scenario.formationTargets.first { $0.playerID == source.id }).position
            } else {
                origin = source.presentationPose(at: stage.time).position
            }
            let ball = PitchPoint(x: origin.x + 0.55, z: origin.z + 0.25)
            for target in scenario.formationTargets {
                let player = try XCTUnwrap(scenario.player(id: target.playerID))
                let body = try XCTUnwrap(root.findEntity(named: "player-\(player.id)"))
                let visual = try XCTUnwrap(body.findEntity(named: ReplaySkinnedAthleteProvider.visualRootName))
                let model = try XCTUnwrap(ReplaySkinnedAthleteProvider.skinnedModels(in: visual).first)
                XCTAssertTrue(visual.isEnabled)
                let reference = stage.ideal
                    ? standingReference(player, at: target.position, facing: ball, duration: scenario.duration)
                    : player
                let expected = try ReplaySkinnedAthleteProvider.make(for: player)
                XCTAssertTrue(expected.update(
                    at: stage.time, track: reference, locomotion: reference.locomotion(at: stage.time),
                    lookTarget: [ball.x, 0.11, ball.z], ballAction: nil
                ))
                XCTAssertEqual(model.jointTransforms.count, expected.model.jointTransforms.count)
                for (actual, wanted) in zip(model.jointTransforms, expected.model.jointTransforms) {
                    XCTAssertLessThan(simd_distance(actual.translation, wanted.translation), 0.000_02)
                    XCTAssertGreaterThan(abs(simd_dot(actual.rotation.vector, wanted.rotation.vector)), 0.999_99)
                    XCTAssertEqual(actual.scale, wanted.scale)
                }
                if index == 0 {
                    firstTransforms[player.id] = model.jointTransforms
                } else if index == 1 {
                    XCTAssertNotEqual(model.jointTransforms, firstTransforms[player.id], "Subtle idle motion stays alive")
                } else if index == 3 {
                    XCTAssertEqual(model.jointTransforms, firstTransforms[player.id], "Returning to Ideal is seek-stable")
                }
                if index < 2 {
                    // Export the actual scene model, not the standing reference.
                    let transforms = model.jointTransforms
                    let groundOffset = try XCTUnwrap(visual.children.first).position.y
                    sceneSamples.append([
                        "name": "shape-\(player.id)-\(index == 0 ? "125" : "140")",
                        "time": stage.time,
                        "groundOffset": groundOffset,
                        "source": "PitchSceneFactory scene jointTransforms",
                        "bodyPosition": [body.position.x, body.position.y, body.position.z],
                        "bodyRotation": [body.orientation.vector.x, body.orientation.vector.y,
                                         body.orientation.vector.z, body.orientation.vector.w],
                        "translations": transforms.map { [$0.translation.x, $0.translation.y, $0.translation.z] },
                        "rotations": transforms.map { [$0.rotation.vector.x, $0.rotation.vector.y,
                                                       $0.rotation.vector.z, $0.rotation.vector.w] },
                        "scales": transforms.map { [$0.scale.x, $0.scale.y, $0.scale.z] }
                    ])
                }
            }
        }
        XCTAssertEqual(sceneSamples.count, 6)
        let data = try JSONSerialization.data(withJSONObject: ["samples": sceneSamples], options: [.sortedKeys])
        let attachment = XCTAttachment(data: data, uniformTypeIdentifier: "public.json")
        attachment.name = "ReplayXI-ShapeIdeal-ScenePoses.json"
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    func testTrackingFallbackShowsTheSameIdleStationPose() throws {
        let scenario = try XCTUnwrap(DemoScenarios.scenario(for: .shapeLab))
        let root = PitchSceneFactory.makeMatchRoot(for: scenario)
        let time = 16.0
        let source = try XCTUnwrap(scenario.formationTargets.first { $0.playerID == scenario.defaultPerspectiveID })
        let ball = PitchPoint(x: source.position.x + 0.55, z: source.position.z + 0.25)
        var firstFallback: [String: [Transform]] = [:]

        for ready in [true, false, true, false] {
            PitchSceneFactory.update(
                root: root, scenario: scenario, time: time, viewMode: .positional,
                perspectiveID: scenario.defaultPerspectiveID, marks: scenario.coachMarks,
                showsLaneLens: false, isDrawing: false,
                positionalOriginTransform: ready ? matrix_identity_float4x4 : nil,
                triangleLockMode: .place, isTrianglePlacementReady: ready, showsIdealBranch: true
            )
            for target in scenario.formationTargets {
                let player = try XCTUnwrap(scenario.player(id: target.playerID))
                let body = try XCTUnwrap(root.findEntity(named: "player-\(player.id)"))
                XCTAssertEqual(body.isEnabled, !ready)
                guard !ready else { continue }
                let rig = try XCTUnwrap(body.findEntity(named: "full-rig"))
                let reference = standingReference(player, at: target.position, facing: ball, duration: scenario.duration)
                let expected = try ReplayAthleteFactory.make(for: player, lod: .near)
                ReplayAthleteMotion.update(
                    expected, from: reference, at: time,
                    lookTargetWorldPosition: [ball.x, 0.11, ball.z]
                )
                var actualTransforms: [Transform] = []
                for joint in ReplayAthleteJoint.allCases {
                    let actual = try XCTUnwrap(rig.findEntity(named: joint.rawValue))
                    actualTransforms.append(actual.transform)
                    XCTAssertGreaterThan(
                        abs(simd_dot(actual.orientation.vector, expected.joints[joint].orientation.vector)), 0.999_99
                    )
                }
                if let previous = firstFallback[player.id] {
                    XCTAssertEqual(actualTransforms, previous)
                } else {
                    firstFallback[player.id] = actualTransforms
                }
            }
        }
    }

    func testStationaryContextIsLimitedToIdealTargetsNotDefendersOrReplayViews() throws {
        let scenario = try XCTUnwrap(DemoScenarios.scenario(for: .shapeLab))
        let ideal = ReplayPlayerPresentation(scenario: scenario, viewMode: .positional, showsIdealBranch: true)
        for player in scenario.players {
            let pose = ideal.stationaryPose(for: player, at: 12.5, facing: .zero)
            XCTAssertEqual(pose != nil, scenario.formationTargets.contains { $0.playerID == player.id })
            for mode in [ReplayViewMode.firstPerson, .tacticalTable, .touchline] {
                let replay = ReplayPlayerPresentation(scenario: scenario, viewMode: mode, showsIdealBranch: true)
                XCTAssertNil(replay.stationaryPose(for: player, at: 12.5, facing: .zero))
            }
            let problem = ReplayPlayerPresentation(scenario: scenario, viewMode: .positional)
            XCTAssertNil(problem.stationaryPose(for: player, at: 12.5, facing: .zero))
        }

        let root = PitchSceneFactory.makeMatchRoot(for: scenario)
        update(root, scenario: scenario, time: 12.5, ideal: true)
        let defender = try XCTUnwrap(scenario.awayPlayers.first {
            root.findEntity(named: "player-\($0.id)")?.isEnabled == true
        })
        let body = try XCTUnwrap(root.findEntity(named: "player-\(defender.id)"))
        let rig = try XCTUnwrap(body.findEntity(named: "full-rig"))
        let ball = try XCTUnwrap(root.findEntity(named: "ball")).position
        let expected = try ReplayAthleteFactory.make(for: defender, lod: .near)
        ReplayAthleteMotion.update(
            expected, from: defender, at: 12.5,
            lookTargetWorldPosition: [ball.x, 0.11, ball.z]
        )
        for joint in ReplayAthleteJoint.allCases {
            XCTAssertEqual(
                try XCTUnwrap(rig.findEntity(named: joint.rawValue)).transform,
                expected.joints[joint].transform
            )
        }
    }

    private func standingReference(
        _ player: PlayerTrack, at position: PitchPoint, facing ball: PitchPoint, duration: Double
    ) -> PlayerTrack {
        let facing = atan2(ball.x - position.x, ball.z - position.z) * 180 / .pi
        return PlayerTrack(
            id: player.id, displayName: player.displayName, role: player.role,
            shirtNumber: player.shirtNumber, team: player.team, isGoalkeeper: player.isGoalkeeper,
            keyframes: [
                MotionKeyframe(time: 0, position: position, facingDegrees: facing),
                MotionKeyframe(time: duration, position: position, facingDegrees: facing)
            ]
        )
    }

    private func update(_ root: Entity, scenario: ReplayScenario, time: Double, ideal: Bool) {
        PitchSceneFactory.update(
            root: root, scenario: scenario, time: time, viewMode: .positional,
            perspectiveID: scenario.defaultPerspectiveID, marks: scenario.coachMarks,
            showsLaneLens: false, isDrawing: false, positionalOriginTransform: nil,
            showsIdealBranch: ideal
        )
    }
}
