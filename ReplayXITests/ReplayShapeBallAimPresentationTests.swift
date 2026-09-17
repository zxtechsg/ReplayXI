import RealityKit
import XCTest
@testable import ReplayXI

@MainActor
final class ReplayShapeBallAimPresentationTests: XCTestCase {
    override func setUp() {
        super.setUp()
        ReplaySkinnedAthleteProvider.resetForTesting()
        ReplayImportedAthleteProvider.resetPrewarmForTesting()
    }

    override func tearDown() {
        ReplaySkinnedAthleteProvider.resetForTesting()
        ReplayAthleteHeadProvider.resetForTesting()
        super.tearDown()
    }

    func testProceduralShapeHeadsTargetGroundedBallAndRepeatAfterRewind() throws {
        try checkShape(usingSkin: false)
    }

    func testSkinnedShapeHeadsTargetGroundedBallAndRepeatAfterRewind() throws {
        try checkShape(usingSkin: true)
    }

    func testProceduralMatchViewsKeepRawBallLoftAfterLeavingShape() throws {
        try checkMatchViews(usingSkin: false)
    }

    func testSkinnedMatchViewsKeepRawBallLoftAfterLeavingShape() throws {
        try checkMatchViews(usingSkin: true)
    }

    private func checkShape(usingSkin: Bool) throws {
        if usingSkin { try ReplaySkinnedAthleteProvider.prewarm() }
        let scenario = try XCTUnwrap(DemoScenarios.scenario(for: .shapeLab))
        let root = PitchSceneFactory.makeMatchRoot(for: scenario)
        let authoredBall = scenario.ball
        var report: [[String: Any]] = []
        var firstByStage: [Bool: [String: [Transform]]] = [:]

        for ideal in [false, true, false] {
            for (index, time) in [14.15, 25.4, 14.15].enumerated() {
                update(root, scenario: scenario, time: time, view: .positional, ideal: ideal)
                let ball = try XCTUnwrap(root.findEntity(named: "ball"))
                XCTAssertTrue(ball.isEnabled)
                XCTAssertEqual(ball.scale.y, 1.8)
                XCTAssertEqual(ball.position.y, 0.198, accuracy: 0.00001)
                // Undo only the review marker's radius enlargement. Aim uses
                // the physical centre, not its exaggerated visual size.
                let target = SIMD3<Float>(ball.position.x,
                                          ball.position.y - 0.11 * (ball.scale.y - 1),
                                          ball.position.z)
                XCTAssertEqual(target.y, 0.11, accuracy: 0.00001)
                XCTAssertGreaterThan(scenario.ball.pose(at: time).height, target.y + 0.1)
                let transforms = try checkVisibleRigs(
                    root, scenario: scenario, time: time, view: .positional,
                    ideal: ideal, target: target, usingSkin: usingSkin, report: &report
                )
                XCTAssertGreaterThanOrEqual(transforms.count, 3, "All three Shape roles must be checked")
                if index == 0, firstByStage[ideal] == nil {
                    firstByStage[ideal] = transforms
                } else if index != 1 {
                    XCTAssertEqual(transforms, firstByStage[ideal],
                                   "Rewind and Problem→Ideal→Problem must return exact scene joint poses")
                }
                XCTAssertEqual(scenario.ball, authoredBall, "Presentation must never rewrite the replay")
            }
        }
        try attach(report, name: "ReplayXI-ShapeBallAim-\(usingSkin ? "skin" : "procedural")")
    }

    private func checkMatchViews(usingSkin: Bool) throws {
        if usingSkin { try ReplaySkinnedAthleteProvider.prewarm() }
        let scenario = try XCTUnwrap(DemoScenarios.scenario(for: .shapeLab))
        let root = PitchSceneFactory.makeMatchRoot(for: scenario)
        let ballPlayback = ReplayBallPlaybackMotion(track: scenario.ball, players: scenario.players)
        var report: [[String: Any]] = []

        for view in [ReplayViewMode.tacticalTable, .touchline, .firstPerson] {
            update(root, scenario: scenario, time: 14.15, view: .positional, ideal: true)
            for time in [14.15, 25.4, 14.15] {
                update(root, scenario: scenario, time: time, view: view, ideal: true)
                let presentedBall = ballPlayback.pose(at: time)
                XCTAssertEqual(presentedBall.height, scenario.ball.pose(at: time).height,
                               accuracy: 0.00001, "Authored loft key moments remain fixed")
                let target = SIMD3<Float>(presentedBall.position.x, presentedBall.height, presentedBall.position.z)
                let transforms = try checkVisibleRigs(
                    root, scenario: scenario, time: time, view: view, ideal: true,
                    target: target, usingSkin: usingSkin, report: &report
                )
                XCTAssertFalse(transforms.isEmpty, "Control must inspect a visible detailed rig in \(view)")
            }
        }
        try attach(report, name: "ReplayXI-MatchBallAim-Control-\(usingSkin ? "skin" : "procedural")")
    }

    private func checkVisibleRigs(
        _ root: Entity, scenario: ReplayScenario, time: Double, view: ReplayViewMode,
        ideal: Bool, target: SIMD3<Float>, usingSkin: Bool, report: inout [[String: Any]]
    ) throws -> [String: [Transform]] {
        let presentation = ReplayPlayerPresentation(scenario: scenario, viewMode: view, showsIdealBranch: ideal)
        var checked: [String: [Transform]] = [:]

        for player in scenario.players {
            let body = try XCTUnwrap(root.findEntity(named: "player-\(player.id)"))
            guard body.isEnabled else { continue }
            let stationary = presentation.stationaryPose(
                for: player, at: time, facing: PitchPoint(x: target.x, z: target.z)
            )
            let locomotion = stationary == nil ? player.locomotion(at: time) : player.stationaryLocomotion
            let ballAction = view == .positional ? nil
                : ReplayAthleteMotion.ballActionPose(for: player, ballTrack: scenario.ball, at: time)
            let actual: [Transform]
            let expected: [Transform]

            if usingSkin {
                guard let visual = body.findEntity(named: ReplaySkinnedAthleteProvider.visualRootName),
                      visual.isEnabled else { continue }
                let model = try XCTUnwrap(ReplaySkinnedAthleteProvider.skinnedModels(in: visual).first)
                let reference = try ReplaySkinnedAthleteProvider.make(for: player)
                XCTAssertTrue(reference.update(at: time, track: player, locomotion: locomotion,
                                               lookTarget: target, ballAction: ballAction,
                                               stationaryPose: stationary))
                let neck = try XCTUnwrap(reference.motion.semanticJointIndices["neck"])
                let head = try XCTUnwrap(reference.motion.semanticJointIndices["head"])
                actual = [model.jointTransforms[neck], model.jointTransforms[head]]
                expected = [reference.model.jointTransforms[neck], reference.model.jointTransforms[head]]
            } else {
                guard let rig = body.findEntity(named: "full-rig"), rig.isEnabled else { continue }
                let neck = try XCTUnwrap(rig.findEntity(named: ReplayAthleteJoint.neck.rawValue))
                let head = try XCTUnwrap(rig.findEntity(named: ReplayAthleteJoint.headRoot.rawValue))
                actual = [neck.transform, head.transform]
                let pose = ReplayAthleteMotion.locomotionPose(
                    for: player, at: time, locomotion: locomotion,
                    gaitPhase: stationary == nil ? player.gaitPhase(at: time) : locomotion.motion.locomotionPhase,
                    lookTargetWorldPosition: target, ballAction: ballAction, stationaryPose: stationary
                )
                expected = [Transform(rotation: pose.neckOrientation), Transform(rotation: pose.headOrientation)]
            }

            for index in actual.indices {
                let delta = simd_normalize(actual[index].rotation.inverse * expected[index].rotation)
                let angle = 2 * atan2(simd_length(delta.imag), abs(delta.real))
                let joint = index == 0 ? "neck" : "head"
                XCTAssertLessThan(angle, 0.0001,
                                  "\(view), ideal=\(ideal), \(player.id), \(time), \(joint): aim must use the presented physical ball")
                report.append([
                    "view": view.rawValue, "ideal": ideal, "player": player.id, "time": time,
                    "rig": usingSkin ? "skin" : "procedural", "joint": joint,
                    "rawBallHeight": scenario.ball.pose(at: time).height,
                    "targetHeight": target.y, "angleErrorDegrees": angle * 180 / .pi,
                ])
            }
            checked[player.id] = actual
        }
        return checked
    }

    private func attach(_ report: [[String: Any]], name: String) throws {
        let data = try JSONSerialization.data(withJSONObject: ["samples": report], options: [.sortedKeys])
        let attachment = XCTAttachment(data: data, uniformTypeIdentifier: "public.json")
        attachment.name = name + ".json"
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    private func update(_ root: Entity, scenario: ReplayScenario, time: Double,
                        view: ReplayViewMode, ideal: Bool) {
        PitchSceneFactory.update(
            root: root, scenario: scenario, time: time, viewMode: view,
            perspectiveID: scenario.defaultPerspectiveID, marks: [], showsLaneLens: false,
            isDrawing: false, positionalOriginTransform: nil, showsIdealBranch: ideal
        )
    }
}
