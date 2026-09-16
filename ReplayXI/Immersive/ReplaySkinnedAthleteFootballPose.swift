import Foundation
import simd

/// Retargets the existing authored football legs onto the licensed skin. The
/// source Biped thighs are children of Spine, not Pelvis; copying local Euler
/// angles would bend the hips with the chest and put the boots below the turf.
/// Solve in model space, then recover each joint's real parent-local transform.
/// All weights come from telemetry/time, never from the previously rendered frame.
struct ReplaySkinnedAthleteFootballPose {
    private struct Leg {
        let hip: Int
        let knee: Int
        let ankle: Int
        let side: ReplayAthleteLeg
        let hipOffset: SIMD3<Float>
        let upperLength: Float
        let lowerLength: Float
        let hipNeutralRotation: simd_quatf
        let kneeNeutralRotation: simd_quatf
        let ankleNeutralRotation: simd_quatf
        let solePoint: SIMD3<Float>
    }

    private struct LegTarget {
        let hipPosition: SIMD3<Float>
        let kneePosition: SIMD3<Float>
        let anklePosition: SIMD3<Float>
        let hipRotation: simd_quatf
        let kneeRotation: simd_quatf
        let ankleRotation: simd_quatf
    }

    private let rootIndex: Int
    private let left: Leg
    private let right: Leg
    private let modifiedIndices: [Int]
    private var target: ReplaySkinnedAthleteMotion.Pose

    init?(motion: ReplaySkinnedAthleteMotion) {
        guard let root = motion.semanticJointIndices["hips"],
              let left = Self.leg("left", root: root, motion: motion),
              let right = Self.leg("right", root: root, motion: motion) else { return nil }
        rootIndex = root
        self.left = left
        self.right = right
        modifiedIndices = [root, left.hip, left.knee, left.ankle, right.hip, right.knee, right.ankle]
        target = motion.makePoseBuffer()
    }

    static func influence(locomotion: PlayerLocomotionSample, ballAction: ReplayAthleteBallActionPose?) -> Float {
        let speed = locomotion.speedMetresPerSecond.isFinite ? max(locomotion.speedMetresPerSecond, 0) : 0
        let turn = locomotion.turnRateDegreesPerSecond.isFinite ? abs(locomotion.turnRateDegreesPerSecond) : 0
        let walking = smooth((speed - 0.08) / 0.32) * (1 - smooth((speed - 1.35) / 0.90))
        let cutting = smooth((speed - 0.65) / 0.65) * smooth((turn - 38) / 112)
        let contact = smooth(((ballAction?.influence ?? 0) - 0.025) / 0.65)
        return max(walking, cutting, contact)
    }

    /// `pose` is the sampled idle/run source. Reusing the separate target buffer
    /// avoids a copy-on-write array allocation every time a player takes a step.
    mutating func apply(
        _ authored: ReplayAthleteLocomotionPose,
        influence: Float,
        motion: ReplaySkinnedAthleteMotion,
        to pose: inout ReplaySkinnedAthleteMotion.Pose
    ) {
        let weight = influence.isFinite ? min(max(influence, 0), 1) : 0
        guard weight > 0 else { return }
        for index in motion.joints.indices {
            target.translations[index] = pose.translations[index]
            target.rotations[index] = pose.rotations[index]
            target.scales[index] = pose.scales[index]
        }
        let body = simd_normalize(authored.bodyOrientation * authored.hipsOrientation)
        let rootPosition = motion.restPose.translations[rootIndex]
            + authored.bodyPosition + authored.hipsPosition - SIMD3<Float>(0, 0.90, 0)
        target.translations[rootIndex] = rootPosition
        target.rotations[rootIndex] = simd_normalize(body * motion.restPose.rotations[rootIndex])
        let leftTarget = Self.target(for: left, authored: authored, body: body, root: rootPosition)
        let rightTarget = Self.target(for: right, authored: authored, body: body, root: rootPosition)

        // Keep fingers, face, cloth bindings and the source upper-body clip.
        // Only the pelvis and six football leg joints need retargeting.
        for index in motion.joints.indices {
            let parent = motion.joints[index].parentIndex
            let parentMatrix = parent < 0 ? matrix_identity_float4x4 : target.modelSpaceTransforms[parent]
            let desired: (SIMD3<Float>, simd_quatf)?
            switch index {
            case left.hip: desired = (leftTarget.hipPosition, leftTarget.hipRotation)
            case left.knee: desired = (leftTarget.kneePosition, leftTarget.kneeRotation)
            case left.ankle: desired = (leftTarget.anklePosition, leftTarget.ankleRotation)
            case right.hip: desired = (rightTarget.hipPosition, rightTarget.hipRotation)
            case right.knee: desired = (rightTarget.kneePosition, rightTarget.kneeRotation)
            case right.ankle: desired = (rightTarget.anklePosition, rightTarget.ankleRotation)
            default: desired = nil
            }
            if let (position, rotation) = desired {
                let localPosition = parentMatrix.inverse * SIMD4<Float>(position, 1)
                target.translations[index] = SIMD3(localPosition.x, localPosition.y, localPosition.z)
                target.rotations[index] = simd_normalize(simd_quatf(parentMatrix).inverse * rotation)
            }
            var local = simd_float4x4(target.rotations[index])
            local.columns.0 *= target.scales[index].x
            local.columns.1 *= target.scales[index].y
            local.columns.2 *= target.scales[index].z
            local.columns.3 = SIMD4(target.translations[index], 1)
            target.modelSpaceTransforms[index] = parentMatrix * local
        }
        // Walking, planting and striking all retain a support boot. Correct the
        // actual skin's sole anchors, not the shorter procedural rig's lengths.
        let leftSole = target.modelSpaceTransforms[left.ankle] * SIMD4(left.solePoint, 1)
        let rightSole = target.modelSpaceTransforms[right.ankle] * SIMD4(right.solePoint, 1)
        target.translations[rootIndex].y += motion.geometry.restMinY - min(leftSole.y, rightSole.y)
        for index in modifiedIndices {
            pose.translations[index] += (target.translations[index] - pose.translations[index]) * weight
            var rotation = target.rotations[index]
            if simd_dot(pose.rotations[index].vector, rotation.vector) < 0 {
                rotation = simd_quatf(vector: -rotation.vector)
            }
            pose.rotations[index] = simd_normalize(simd_slerp(pose.rotations[index], rotation, weight))
        }
    }

    private static func leg(_ name: String, root: Int, motion: ReplaySkinnedAthleteMotion) -> Leg? {
        guard let hip = motion.semanticJointIndices[name + "Hip"],
              let knee = motion.semanticJointIndices[name + "Knee"],
              let ankle = motion.semanticJointIndices[name + "Ankle"],
              let contact = motion.footContacts[name] else { return nil }
        func position(_ index: Int) -> SIMD3<Float> {
            let value = motion.restPose.modelSpaceTransforms[index].columns.3
            return SIMD3(value.x, value.y, value.z)
        }
        let upper = position(knee) - position(hip)
        let lower = position(ankle) - position(knee)
        guard simd_length(upper) > 0.1, simd_length(lower) > 0.1 else { return nil }
        let down = SIMD3<Float>(0, -1, 0)
        // The legacy procedural side IDs use negative-X = left. The licensed
        // source uses anatomical names viewed from the front. Map by position
        // so a touch on +X never animates the boot on the opposite side.
        let side: ReplayAthleteLeg = position(hip).x < position(root).x ? .left : .right
        return Leg(
            hip: hip, knee: knee, ankle: ankle, side: side,
            hipOffset: position(hip) - position(root),
            upperLength: simd_length(upper), lowerLength: simd_length(lower),
            hipNeutralRotation: simd_normalize(simd_quatf(from: simd_normalize(upper), to: down)
                * simd_quatf(motion.restPose.modelSpaceTransforms[hip])),
            kneeNeutralRotation: simd_normalize(simd_quatf(from: simd_normalize(lower), to: down)
                * simd_quatf(motion.restPose.modelSpaceTransforms[knee])),
            ankleNeutralRotation: simd_normalize(simd_quatf(motion.restPose.modelSpaceTransforms[ankle])),
            solePoint: contact.solePoint
        )
    }

    private static func target(
        for leg: Leg, authored: ReplayAthleteLocomotionPose,
        body: simd_quatf, root: SIMD3<Float>
    ) -> LegTarget {
        let hip = leg.side == .left ? authored.leftHipOrientation : authored.rightHipOrientation
        let knee = leg.side == .left ? authored.leftKneeOrientation : authored.rightKneeOrientation
        let ankle = leg.side == .left ? authored.leftAnkleOrientation : authored.rightAnkleOrientation
        let hipDelta = body * hip
        let kneeDelta = hipDelta * knee
        let ankleDelta = kneeDelta * ankle
        let hipPosition = root + body.act(leg.hipOffset)
        let kneePosition = hipPosition + hipDelta.act(SIMD3(0, -leg.upperLength, 0))
        return LegTarget(
            hipPosition: hipPosition, kneePosition: kneePosition,
            anklePosition: kneePosition + kneeDelta.act(SIMD3(0, -leg.lowerLength, 0)),
            hipRotation: simd_normalize(hipDelta * leg.hipNeutralRotation),
            kneeRotation: simd_normalize(kneeDelta * leg.kneeNeutralRotation),
            ankleRotation: simd_normalize(ankleDelta * leg.ankleNeutralRotation)
        )
    }

    private static func smooth(_ value: Float) -> Float {
        let x = value.isFinite ? min(max(value, 0), 1) : 0
        return x * x * x * (x * (x * 6 - 15) + 10)
    }
}
