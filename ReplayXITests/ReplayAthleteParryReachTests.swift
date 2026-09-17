import RealityKit
import XCTest
import simd
@testable import ReplayXI

@MainActor
final class ReplayAthleteParryReachTests: XCTestCase {
    override func tearDown() {
        ReplaySkinnedAthleteProvider.resetForTesting()
        ReplayAthleteHeadProvider.resetForTesting()
        super.tearDown()
    }

    private var player: PlayerTrack {
        .init(id: "parry-test", displayName: "Keeper", role: "GK", shirtNumber: 1,
              team: .away, isGoalkeeper: true,
              keyframes: [.init(time: 0, position: .zero, facingDegrees: 0),
                          .init(time: 2, position: .zero, facingDegrees: 0)])
    }

    private func cue(height: Float) -> ReplayAthleteInteractionCue {
        .init(playerID: player.id, kind: .save, contactTime: 1, startTime: 0.7, endTime: 1.4,
              kickingLeg: .right, contactBallWorldPosition: [0, height, 0.4],
              outgoingDirectionWorld: [0, 0, 1], supportFootWorldPosition: [-0.137, 0, 0.035])
    }

    private func palm(_ pose: ReplayAthleteLocomotionPose, left: Bool) -> SIMD3<Float> {
        let hips = pose.bodyPosition + pose.bodyOrientation.act(pose.hipsPosition)
        let hipRotation = pose.bodyOrientation * pose.hipsOrientation
        let spine = hips + hipRotation.act([0, 0.14, 0])
        let torso = hipRotation * pose.spineOrientation
        let shoulder = spine + torso.act([left ? -0.218 : 0.218, 0.470, 0])
        let upper = torso * (left ? pose.leftShoulderOrientation : pose.rightShoulderOrientation)
        let lower = upper * (left ? pose.leftElbowOrientation : pose.rightElbowOrientation)
        let hand = lower * (left ? pose.leftWristOrientation : pose.rightWristOrientation)
        return shoulder + upper.act([0, -0.310, 0]) + lower.act([0, -0.275, 0])
            + hand.act([0, -0.070, 0.020])
    }

    func testLowAndMidHeightParriesReachTheBallWithBothHands() {
        for height: Float in [0.65, 1.25, 1.75] {
            let cue = cue(height: height)
            let pose = ReplayAthleteMotion.locomotionPose(for: player, at: 1,
                lookTargetWorldPosition: cue.contactBallWorldPosition, interaction: cue,
                presentationPose: .init(position: .zero, facingDegrees: 0))
            for left in [false, true] {
                XCTAssertLessThanOrEqual(simd_distance(palm(pose, left: left), cue.contactBallWorldPosition),
                                         0.14, "\(height)m parry must reach the sphere, not stay chest-high")
            }
        }
    }

    func testLicensedNearAndLowParryMarkersReachWithFloorAndRewindIntact() throws {
        try ReplaySkinnedAthleteProvider.prewarm()
        try ReplaySkinnedAthleteProvider.prewarmLowDetail()
        var rows: [[String: Any]] = []
        for detail in [ReplaySkinnedAthleteProvider.Detail.near, .lowDetail] {
            let skin = try ReplaySkinnedAthleteProvider.make(for: player, detail: detail)
            let cue = cue(height: 0.65)
            XCTAssertTrue(skin.update(at: 1, track: player, locomotion: player.locomotion(at: 1),
                lookTarget: cue.contactBallWorldPosition, ballAction: nil, interaction: cue,
                presentationPose: .init(position: .zero, facingDegrees: 0)))
            let first = skin.pose.rotations.map(\.vector)
            for side in ["left", "right"] {
                let elbow = try XCTUnwrap(skin.motion.semanticJointIndices[side + "Elbow"])
                let wrist = try XCTUnwrap(skin.motion.semanticJointIndices[side + "Wrist"])
                func position(_ matrix: simd_float4x4) -> SIMD3<Float> {
                    [matrix.columns.3.x, matrix.columns.3.y, matrix.columns.3.z]
                }
                let rest = skin.motion.restPose.modelSpaceTransforms
                let neutral = simd_quatf(from: simd_normalize(position(rest[wrist]) - position(rest[elbow])),
                                         to: [0, -1, 0]) * simd_quatf(rest[wrist])
                let localMarker = neutral.inverse.act([0, -0.070, 0.020])
                let marker = skin.pose.modelSpaceTransforms[wrist] * SIMD4(localMarker, 1)
                let actual = SIMD3<Float>(marker.x, marker.y - skin.motion.geometry.restMinY, marker.z)
                let distance = simd_distance(actual, cue.contactBallWorldPosition)
                XCTAssertLessThanOrEqual(distance, 0.14)
                rows.append(["detail": String(describing: detail), "hand": side,
                             "palmMarkerToBallCentreMetres": distance,
                             "actualPalmMarker": [actual.x, actual.y, actual.z]])
            }
            let floor = skin.contactSurface.minimumY(in: skin.pose) - skin.motion.geometry.restMinY
            XCTAssertGreaterThanOrEqual(floor, skin.contactSurface.paddingMetres - 0.000_01)
            for time in [1.3, 0.8, 1.0] {
                XCTAssertTrue(skin.update(at: time, track: player, locomotion: player.locomotion(at: time),
                    lookTarget: cue.contactBallWorldPosition, ballAction: nil, interaction: cue,
                    presentationPose: .init(position: .zero, facingDegrees: 0)))
            }
            XCTAssertEqual(first, skin.pose.rotations.map(\.vector))
        }
        let receipt = XCTAttachment(data: try JSONSerialization.data(withJSONObject: rows, options: [.sortedKeys]),
                                    uniformTypeIdentifier: "public.json")
        receipt.name = "ReplayXI-Interaction125-Parry-Reach.json"
        receipt.lifetime = .keepAlways; add(receipt)
    }
}
