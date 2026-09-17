import RealityKit
import XCTest
import simd
@testable import ReplayXI

@MainActor
final class ReplayCervicalMotionTests: XCTestCase {
    override func tearDown() {
        ReplaySkinnedAthleteProvider.resetForTesting()
        ReplayAthleteHeadProvider.resetForTesting()
        super.tearDown()
    }

    private func runner(bearing: Float, speed: Float, heading: Float = 0) -> PlayerTrack {
        let angle = (bearing + heading) * .pi / 180
        let velocity = SIMD2<Float>(sin(angle), cos(angle)) * speed
        return PlayerTrack(id: "cervical-motion-126", displayName: "Motion control", role: "RW",
            shirtNumber: 11, team: .home, isGoalkeeper: false,
            keyframes: [
                .init(time: 0, position: .init(x: -velocity.x * 5, z: -velocity.y * 5), facingDegrees: heading),
                .init(time: 10, position: .init(x: velocity.x * 5, z: velocity.y * 5), facingDegrees: heading)
            ])
    }

    private func difference(_ first: simd_quatf, _ second: simd_quatf) -> Float {
        2 * acos(min(max(abs(simd_dot(simd_normalize(first).vector, simd_normalize(second).vector)), 0), 1))
    }

    func testFinalCervicalEnvelopeBoundsCombinedRotationsWithoutMovingNormalGaze() {
        for yaw: Float in [-179, -100, -75, -55, -25, 0, 25, 55, 75, 100, 179] {
            for pitch: Float in [-80, -45, -25, 0, 25, 45, 80] {
                for roll: Float in [-70, -12, 0, 12, 70] {
                    let source = simd_quatf(angle: yaw * .pi / 180, axis: [0, 1, 0])
                        * simd_quatf(angle: pitch * .pi / 180, axis: [1, 0, 0])
                        * simd_quatf(angle: roll * .pi / 180, axis: [0, 0, 1])
                    let bounded = ReplayCervicalConstraint.limited(source)
                    let forward = bounded.act([0, 0, 1])
                    let actualYaw = atan2(forward.x, forward.z)
                    let actualPitch = atan2(-forward.y, hypot(forward.x, forward.z))
                    let swing = simd_quatf(angle: actualYaw, axis: [0, 1, 0])
                        * simd_quatf(angle: actualPitch, axis: [1, 0, 0])
                    let right = (swing.inverse * bounded).act([1, 0, 0])
                    XCTAssertLessThanOrEqual(abs(actualYaw) * 180 / .pi, 70.001)
                    XCTAssertLessThanOrEqual(abs(actualPitch) * 180 / .pi, 40.001)
                    XCTAssertLessThanOrEqual(abs(atan2(right.y, right.x)) * 180 / .pi, 22.001)
                    if abs(yaw) < 55, abs(pitch) < 25, abs(roll) < 12 {
                        XCTAssertLessThan(difference(source, bounded), 0.001)
                    }
                    XCTAssertEqual(bounded.vector, ReplayCervicalConstraint.limited(source).vector)
                }
            }
        }
        XCTAssertEqual(ReplayCervicalConstraint.limited(simd_quatf(vector: [.nan, 0, 0, 1])).vector,
                       simd_quatf(real: 1, imag: .zero).vector)
    }

    func testActualSkinBackpedalRearCrossingIsContinuousAndRewinds() throws {
        try ReplaySkinnedAthleteProvider.prewarm()
        try ReplaySkinnedAthleteProvider.prewarmLowDetail()
        for detail in [ReplaySkinnedAthleteProvider.Detail.near, .lowDetail] {
            let before = runner(bearing: 179.994, speed: 1.1)
            let after = runner(bearing: 180.006, speed: 1.1)
            let skin = try ReplaySkinnedAthleteProvider.make(for: before, detail: detail)
            let head = try XCTUnwrap(skin.motion.semanticJointIndices["head"])
            func update(_ track: PlayerTrack, time: Double) -> simd_quatf {
                XCTAssertTrue(skin.update(at: time, track: track, locomotion: track.locomotion(at: time),
                    lookTarget: nil, ballAction: nil, presentationPose: track.presentationPose(at: time)))
                return simd_quatf(skin.pose.modelSpaceTransforms[head])
            }
            let first = update(before, time: 5)
            let second = update(after, time: 5)
            XCTAssertLessThan(difference(first, second), 0.005,
                              "The complete rendered head must not jump across backward travel's angle seam")
            _ = update(after, time: 5.2)
            _ = update(before, time: 4.7)
            let repeated = update(before, time: 5)
            XCTAssertEqual(first.vector, repeated.vector)
        }
    }

    func testBackpedalDirectionCrossingRearAxisDoesNotWhipTheHead() {
        for heading: Float in [0, 90, 180, -90] {
            for speed: Float in [0.5, 1.1, 2.2, 4.0] {
                let before = runner(bearing: 179.994, speed: speed, heading: heading)
                let after = runner(bearing: 180.006, speed: speed, heading: heading)
                for target: SIMD3<Float>? in [nil, [0, 0.11, 20]] {
                    let a = ReplayAthleteMotion.lookPose(for: before, at: 5, targetWorldPosition: target)
                    let b = ReplayAthleteMotion.lookPose(for: after, at: 5, targetWorldPosition: target)
                    XCTAssertLessThan(abs(a.combinedYawRadians - b.combinedYawRadians), 0.005,
                        "A tiny change in backward travel must not flip shoulder checks")
                }
            }
        }
    }

    func testActualSkinnedHeadStaysWithinChestRelativeLimits() throws {
        try ReplaySkinnedAthleteProvider.prewarm()
        try ReplaySkinnedAthleteProvider.prewarmLowDetail()
        var rows: [[String: Any]] = []
        for detail in [ReplaySkinnedAthleteProvider.Detail.near, .lowDetail] {
            let player = runner(bearing: 0, speed: 3.6)
            let skin = try ReplaySkinnedAthleteProvider.make(for: player, detail: detail)
            let chest = try XCTUnwrap(skin.motion.semanticJointIndices["chest"])
            let head = try XCTUnwrap(skin.motion.semanticJointIndices["head"])
            let restChest = simd_quatf(skin.motion.restPose.modelSpaceTransforms[chest])
            let restHead = simd_quatf(skin.motion.restPose.modelSpaceTransforms[head])
            var maximumYaw: Float = 0
            var maximumPitch: Float = 0
            var maximumFrameTurn: Float = 0
            for bearing: Float in [-180, -150, -90, -45, 0, 45, 90, 150, 180] {
                var previous: simd_quatf?
                for index in 0...60 {
                    let time = 4 + Double(index) / 30
                    let pose = player.presentationPose(at: time)
                    let radians = bearing * .pi / 180
                    let ball: SIMD3<Float> = [pose.position.x + sin(radians) * 10, 0.11,
                                             pose.position.z + cos(radians) * 10]
                    XCTAssertTrue(skin.update(at: time, track: player, locomotion: player.locomotion(at: time),
                        lookTarget: ball, ballAction: nil, presentationPose: pose))
                    // Read back the transforms sent to RealityKit, then measure
                    // the complete chain relative to the chest and rest axes.
                    let submitted = skin.model.jointTransforms
                    var visible = skin.pose
                    for joint in submitted.indices {
                        visible.translations[joint] = submitted[joint].translation
                        visible.rotations[joint] = submitted[joint].rotation
                        visible.scales[joint] = submitted[joint].scale
                    }
                    skin.motion.rebuildModelSpaceTransforms(in: &visible)
                    let chestDelta = simd_quatf(visible.modelSpaceTransforms[chest]) * restChest.inverse
                    let relative = simd_normalize(chestDelta.inverse
                        * simd_quatf(visible.modelSpaceTransforms[head]) * restHead.inverse)
                    let forward = relative.act([0, 0, 1])
                    let yaw = abs(atan2(forward.x, forward.z)) * 180 / .pi
                    let pitch = abs(atan2(-forward.y, hypot(forward.x, forward.z))) * 180 / .pi
                    maximumYaw = max(maximumYaw, yaw)
                    maximumPitch = max(maximumPitch, pitch)
                    if let previous { maximumFrameTurn = max(maximumFrameTurn, difference(previous, relative) * 180 / .pi) }
                    previous = relative
                }
            }
            XCTAssertLessThanOrEqual(maximumYaw, 70, "The whole neck/head chain, not just the added gaze, must be bounded")
            XCTAssertLessThanOrEqual(maximumPitch, 40, "Imported animation cannot compound gaze into an extreme neck pitch")
            XCTAssertLessThanOrEqual(maximumFrameTurn, 12, "Steady running gaze must not snap between adjacent frames")
            rows.append(["detail": String(describing: detail), "maximumChestRelativeYawDegrees": maximumYaw,
                         "maximumChestRelativePitchDegrees": maximumPitch,
                         "maximumFrameTurnDegrees": maximumFrameTurn])
        }
        let attachment = XCTAttachment(data: try JSONSerialization.data(withJSONObject: rows, options: [.sortedKeys]),
            uniformTypeIdentifier: "public.json")
        attachment.name = "ReplayXI-Cervical126-ActualSkin.json"
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
