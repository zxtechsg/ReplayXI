import RealityKit
import XCTest
@testable import ReplayXI

@MainActor
final class ReplaySkinnedAthleteGroundingTests: XCTestCase {
    override func tearDown() {
        ReplaySkinnedAthleteProvider.resetForTesting()
        ReplayAthleteHeadProvider.resetForTesting()
        super.tearDown()
    }

    private func prepare() throws -> (PlayerTrack, ReplaySkinnedAthleteInstance) {
        try ReplaySkinnedAthleteProvider.prewarm()
        let scenario = try XCTUnwrap(DemoScenarios.scenario(for: .squadReplay))
        let player = try XCTUnwrap(scenario.player(id: "navy-rw"))
        return (player, try ReplaySkinnedAthleteProvider.make(for: player))
    }

    private func sample(_ player: PlayerTrack, at time: Double, speed: Float, turn: Float) -> PlayerLocomotionSample {
        PlayerLocomotionSample(motion: player.locomotion(at: time).motion,
                               speedMetresPerSecond: speed, accelerationMetresPerSecondSquared: 0,
                               turnRateDegreesPerSecond: turn,
                               state: PlayerLocomotionSample.classify(speedMetresPerSecond: speed,
                                                                     turnRateDegreesPerSecond: turn))
    }

    private func attachment(_ skin: ReplaySkinnedAthleteInstance, name: String, time: Double) -> [String: Any] {
        ["name": name, "time": time, "groundOffset": -skin.motion.geometry.restMinY,
         "translations": skin.pose.translations.map { [$0.x, $0.y, $0.z] },
         "rotations": skin.pose.rotations.map { [$0.vector.x, $0.vector.y, $0.vector.z, $0.vector.w] },
         "scales": skin.pose.scales.map { [$0.x, $0.y, $0.z] }]
    }

    func testSkinSupportHeightThroughWalkRunAndCutTransitions() throws {
        let (player, skin) = try prepare()
        var gallery: [[String: Any]] = []
        var report: [[String: Any]] = []
        var minimum = Float.infinity
        // Keep the original worst frames as stable before/after render fixtures,
        // while still scanning the complete range for new regressions.
        for (name, speed, turn, galleryTime) in [
            ("slow-walk", Float(0.35), Float(0), 12.666666666666666), ("walk", 1.1, 0, 13.866666666666667),
            ("walk-run-blend", 1.7, 0, 13.4), ("run", 3.6, 0, 14.333333333333334),
            ("cut-left", 3.0, -180, 15.0), ("cut-right", 3.0, 180, 11.4)
        ] {
            var worst = Float.infinity
            var worstTime: Double = 0
            for time in stride(from: 11.0, through: 15.0, by: 1.0 / 30) {
                XCTAssertTrue(skin.update(at: time, track: player,
                                          locomotion: sample(player, at: time, speed: speed, turn: turn),
                                          lookTarget: nil, ballAction: nil))
                let clearance = skin.contactSurface.minimumY(in: skin.pose) - skin.motion.geometry.restMinY
                XCTAssertTrue(clearance.isFinite)
                if clearance < worst {
                    worst = clearance
                    worstTime = time
                }
            }
            minimum = min(minimum, worst)
            XCTAssertTrue(skin.update(at: galleryTime, track: player,
                                      locomotion: sample(player, at: galleryTime, speed: speed, turn: turn),
                                      lookTarget: nil, ballAction: nil))
            gallery.append(attachment(skin, name: name, time: galleryTime))
            report.append(["name": name, "minimumClearance": worst, "time": worstTime,
                           "speed": speed, "turn": turn])
        }
        let data = try JSONSerialization.data(withJSONObject: ["samples": gallery, "report": report],
                                              options: [.sortedKeys])
        let poses = XCTAttachment(data: data, uniformTypeIdentifier: "public.json")
        poses.name = "ReplayXI-GroundedLocomotion-Poses.json"
        poses.lifetime = .keepAlways
        add(poses)
        XCTAssertGreaterThanOrEqual(minimum, skin.contactSurface.paddingMetres - 0.00001,
                                    "The actual weighted boots must not sink through turf between gait poses")
    }

    func testFloorCorrectionPreservesHierarchyAndDoesNotLowerAirbornePoses() throws {
        let (_, skin) = try prepare()
        let motion = skin.motion
        var pose = motion.makePoseBuffer()
        motion.sample(clip: .run, at: 0.31, into: &pose)
        let before = pose
        let minimum = skin.contactSurface.minimumY(in: pose)
        let lift = skin.contactSurface.raiseAboveFloor(minimum + 0.075, in: &pose)
        XCTAssertEqual(lift, 0.075, accuracy: 0.000001)
        XCTAssertEqual(pose.translations[0].y, before.translations[0].y + lift, accuracy: 0.000001)
        XCTAssertEqual(Array(pose.translations.dropFirst()), Array(before.translations.dropFirst()))
        XCTAssertEqual(pose.rotations.map(\.vector), before.rotations.map(\.vector))
        XCTAssertEqual(pose.scales, before.scales)
        var rebuilt = pose
        motion.rebuildModelSpaceTransforms(in: &rebuilt)
        for (actual, expected) in zip(pose.modelSpaceTransforms, rebuilt.modelSpaceTransforms) {
            for column in 0..<4 { XCTAssertLessThan(simd_distance(actual[column], expected[column]), 0.00001) }
        }
        let unchanged = pose
        XCTAssertEqual(skin.contactSurface.raiseAboveFloor(minimum, in: &pose), 0,
                       "An airborne boot must keep its authored height")
        XCTAssertEqual(pose.translations, unchanged.translations)
        XCTAssertEqual(pose.modelSpaceTransforms, unchanged.modelSpaceTransforms)
        XCTAssertEqual(skin.contactSurface.raiseAboveFloor(.nan, in: &pose), 0)
        pose.translations.removeAll()
        XCTAssertEqual(skin.contactSurface.raiseAboveFloor(1, in: &pose), 0)
    }

    func testSourceRunFlightAndNumberAnchorsSurviveTheFloorGuard() throws {
        let (player, skin) = try prepare()
        var source = skin.motion.makePoseBuffer()
        var airborneCount = 0
        for time in stride(from: 11.0, through: 15.0, by: 1.0 / 30) {
            let locomotion = sample(player, at: time, speed: 3.6, turn: 0)
            skin.motion.sample(time: time, locomotionEffort: locomotion.effort,
                               gaitPhase: player.gaitPhase(at: time), into: &source)
            let clearance = skin.contactSurface.minimumY(in: source) - skin.motion.geometry.restMinY
            XCTAssertTrue(skin.update(at: time, track: player, locomotion: locomotion,
                                      lookTarget: nil, ballAction: nil))
            if clearance > skin.contactSurface.paddingMetres + 0.00001 {
                airborneCount += 1
                XCTAssertEqual(skin.pose.translations[0], source.translations[0],
                               "The floor guard must not flatten the source run's airborne step")
            }
            let chest = skin.pose.modelSpaceTransforms[skin.motion.numberAnchors.jointIndex]
            for (number, point) in [(skin.front, skin.motion.numberAnchors.front),
                                    (skin.back, skin.motion.numberAnchors.back)] {
                let expected = chest * SIMD4(point, 1)
                XCTAssertLessThan(simd_distance(number.position, SIMD3(expected.x, expected.y, expected.z)), 0.00001)
            }
        }
        XCTAssertGreaterThan(airborneCount, 0, "The fixture must exercise actual source flight frames")
    }
}
