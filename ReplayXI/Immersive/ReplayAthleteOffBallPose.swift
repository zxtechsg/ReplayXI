import Foundation
import simd

/// Small presentation-only upper-body intent. This is procedural variation,
/// not recovered match body motion. No root, leg, scale or clock is changed.
enum ReplayAthleteOffBallPose {
    struct ArmSet: Equatable, Sendable {
        let forward: Float
        let outward: Float
        let elbowFlexion: Float
        static let zero = ArmSet(forward: 0, outward: 0, elbowFlexion: 0)

        func shoulder(isLeft: Bool) -> simd_quatf {
            simd_quatf(angle: isLeft ? -outward : outward, axis: [0, 0, 1])
                * simd_quatf(angle: -forward, axis: [1, 0, 0])
        }
    }

    struct Sample: Equatable, Sendable {
        let chestYaw: Float
        let chestPitch: Float
        let chestRoll: Float
        let leftArm: ArmSet
        let rightArm: ArmSet
        let armSetWeight: Float
        let bracingWeight: Float

        static let zero = Sample(chestYaw: 0, chestPitch: 0, chestRoll: 0,
                                 leftArm: .zero, rightArm: .zero, armSetWeight: 0, bracingWeight: 0)
        var isIdentity: Bool {
            chestYaw == 0 && chestPitch == 0 && chestRoll == 0
                && armSetWeight == 0 && bracingWeight == 0
        }
        var chestRotation: simd_quatf {
            simd_quatf(angle: chestPitch, axis: [1, 0, 0])
                * simd_quatf(angle: chestRoll, axis: [0, 0, 1])
                * simd_quatf(angle: chestYaw, axis: [0, 1, 0])
        }

        func arm(isLeft: Bool) -> ArmSet { isLeft ? leftArm : rightArm }

        func shoulderBrace(isLeft: Bool) -> simd_quatf {
            simd_quatf(angle: (isLeft ? -0.07 : 0.07) * bracingWeight, axis: [0, 0, 1])
                * simd_quatf(angle: -0.05 * bracingWeight, axis: [1, 0, 0])
        }

        func shoulder(_ current: simd_quatf, isLeft: Bool) -> simd_quatf {
            guard armSetWeight > 0 || bracingWeight > 0 else { return current }
            let set = ReplayAthleteOffBallPose.blend(current, arm(isLeft: isLeft).shoulder(isLeft: isLeft), armSetWeight)
            return simd_normalize(shoulderBrace(isLeft: isLeft) * set)
        }

        func elbow(_ current: simd_quatf, isLeft: Bool) -> simd_quatf {
            guard armSetWeight > 0 || bracingWeight > 0 else { return current }
            let target = simd_quatf(angle: -arm(isLeft: isLeft).elbowFlexion, axis: [1, 0, 0])
            return simd_normalize(simd_quatf(angle: -0.05 * bracingWeight, axis: [1, 0, 0])
                * ReplayAthleteOffBallPose.blend(current, target, armSetWeight))
        }

        /// Share the existing gaze with the chest, rather than adding another
        /// turn on top of the neck/head. The final anatomical clamp still wins.
        func adjusting(_ look: ReplayAthleteLookPose) -> ReplayAthleteLookPose {
            guard !isIdentity else { return look }
            return .init(neckYawRadians: look.neckYawRadians - chestYaw * 0.42,
                         headYawRadians: look.headYawRadians - chestYaw * 0.58,
                         neckPitchRadians: look.neckPitchRadians - chestPitch * 0.34,
                         headPitchRadians: look.headPitchRadians - chestPitch * 0.66)
        }
    }

    static func sample(playerID: String, at time: TimeInterval,
                       locomotion: PlayerLocomotionSample, look: ReplayAthleteLookPose,
                       actionInfluence: Float, sourceFraction: Float = 0,
                       enabled: Bool = true) -> Sample {
        guard enabled, time.isFinite, locomotion.speedMetresPerSecond.isFinite,
              locomotion.accelerationMetresPerSecondSquared.isFinite,
              look.combinedYawRadians.isFinite, actionInfluence.isFinite,
              sourceFraction.isFinite else { return .zero }
        // Keep the admitted contact and its full-support core exactly intact.
        // The quintic edge avoids a new animation cut during preparation/release.
        let availability = 1 - smooth((actionInfluence - 0.05) / 0.65)
        guard availability > 0 else { return .zero }
        let speed = max(locomotion.speedMetresPerSecond, 0)
        let settled = 1 - smooth((speed - 0.35) / 2.45)
        let effort = locomotion.effort
        let phase = Float(playerID.utf8.reduce(UInt32(2_166_136_261)) {
            ($0 ^ UInt32($1)) &* 16_777_619
        } % 65_521) / 65_521 * (2 * .pi)
        let seconds = Float(min(max(time, -1_000_000), 1_000_000))
        let quietYaw = sin(seconds * 0.71 + phase) * 0.012 * settled
        let breath = sin(seconds * 1.19 + phase * 1.73) * 0.006 * settled
        let balance = sin(seconds * 0.53 + phase * 2.31) * 0.008 * settled
        let share = look.combinedYawRadians * (0.17 - 0.08 * effort)
        // The far/procedural pose already has acceleration lean. Only fill the
        // fraction still owned by the native source run; never replace its legs.
        let acceleration = locomotion.accelerationResponse
        let source = min(max(sourceFraction, 0), 1)
        let sourcePitch = (-max(acceleration, 0) * 0.09 + max(-acceleration, 0) * 0.10) * source
        // A football-ready but relaxed arm set, not a permanent blocking pose.
        // Small independent offsets avoid mirrored mannequins or a shared clock.
        let armWave = sin(seconds * 0.43 + phase)
        let otherWave = sin(seconds * 0.37 + phase * 1.61 + 1.2)
        let leftArm = ArmSet(forward: 0.10 + armWave * 0.025,
                             outward: 0.10 + otherWave * 0.020,
                             elbowFlexion: 0.35 + armWave * 0.050)
        let rightArm = ArmSet(forward: 0.10 + otherWave * 0.025,
                              outward: 0.10 - armWave * 0.020,
                              elbowFlexion: 0.35 + otherWave * 0.050)
        let bracing = smooth((-acceleration - 0.12) / 0.88) * (1 - settled) * availability
        return .init(chestYaw: min(max(share + quietYaw, -0.16), 0.16) * availability,
                     chestPitch: (breath + sourcePitch) * availability,
                     chestRoll: balance * availability, leftArm: leftArm, rightArm: rightArm,
                     armSetWeight: settled * availability, bracingWeight: bracing)
    }

    /// Actual Biped arm axes, cached once for each admitted skin. The semantic
    /// arm points down -Y in its neutral frame; source local Euler axes do not.
    struct NativeArmBinding {
        let shoulder: Int
        let elbow: Int
        let isLeft: Bool
        let shoulderNeutral: simd_quatf
        let elbowNeutral: simd_quatf

        init?(side: String, motion: ReplaySkinnedAthleteMotion) {
            guard let shoulder = motion.semanticJointIndices[side + "Shoulder"],
                  let elbow = motion.semanticJointIndices[side + "Elbow"],
                  let wrist = motion.semanticJointIndices[side + "Wrist"],
                  let root = motion.semanticJointIndices["hips"] else { return nil }
            func position(_ index: Int) -> SIMD3<Float> {
                let value = motion.restPose.modelSpaceTransforms[index].columns.3
                return [value.x, value.y, value.z]
            }
            let upper = position(elbow) - position(shoulder)
            let lower = position(wrist) - position(elbow)
            guard simd_length(upper) > 0.1, simd_length(lower) > 0.1 else { return nil }
            self.shoulder = shoulder
            self.elbow = elbow
            isLeft = position(shoulder).x < position(root).x
            shoulderNeutral = simd_normalize(simd_quatf(from: simd_normalize(upper), to: [0, -1, 0])
                * simd_quatf(motion.restPose.modelSpaceTransforms[shoulder]))
            elbowNeutral = simd_normalize(simd_quatf(from: simd_normalize(lower), to: [0, -1, 0])
                * simd_quatf(motion.restPose.modelSpaceTransforms[elbow]))
        }

        func apply(_ sample: Sample, torso: simd_quatf, motion: ReplaySkinnedAthleteMotion,
                   to pose: inout ReplaySkinnedAthleteMotion.Pose) {
            guard sample.armSetWeight > 0 || sample.bracingWeight > 0 else { return }
            let upper = ReplayAthleteOffBallPose.modelRotation(shoulder, motion: motion, pose: pose)
            let desiredUpper = torso * sample.arm(isLeft: isLeft).shoulder(isLeft: isLeft) * shoulderNeutral
            let setUpper = ReplayAthleteOffBallPose.blend(upper, desiredUpper, sample.armSetWeight)
            let bracedUpper = simd_normalize(torso * sample.shoulderBrace(isLeft: isLeft) * torso.inverse * setUpper)
            setModelRotation(bracedUpper, joint: shoulder, motion: motion, pose: &pose)
            // Solve the elbow against the actual partially blended upper arm.
            // The hand/fingers keep their existing local pose and ride the bend.
            let upperFrame = bracedUpper * shoulderNeutral.inverse
            let lower = ReplayAthleteOffBallPose.modelRotation(elbow, motion: motion, pose: pose)
            let flexion = simd_quatf(angle: -sample.arm(isLeft: isLeft).elbowFlexion, axis: [1, 0, 0])
            let desiredLower = upperFrame * flexion * elbowNeutral
            let setLower = ReplayAthleteOffBallPose.blend(lower, desiredLower, sample.armSetWeight)
            let brace = simd_quatf(angle: -0.05 * sample.bracingWeight, axis: [1, 0, 0])
            setModelRotation(upperFrame * brace * upperFrame.inverse * setLower,
                             joint: elbow, motion: motion, pose: &pose)
        }

        private func setModelRotation(_ rotation: simd_quatf, joint: Int,
                                      motion: ReplaySkinnedAthleteMotion,
                                      pose: inout ReplaySkinnedAthleteMotion.Pose) {
            let parent = ReplayAthleteOffBallPose.modelRotation(motion.joints[joint].parentIndex,
                                                               motion: motion, pose: pose)
            pose.rotations[joint] = simd_normalize(parent.inverse * rotation)
        }
    }

    static func modelRotation(_ joint: Int, motion: ReplaySkinnedAthleteMotion,
                              pose: ReplaySkinnedAthleteMotion.Pose) -> simd_quatf {
        var index = joint
        var rotation = simd_quatf(real: 1, imag: .zero)
        while index >= 0 {
            rotation = pose.rotations[index] * rotation
            index = motion.joints[index].parentIndex
        }
        return simd_normalize(rotation)
    }

    private static func blend(_ current: simd_quatf, _ target: simd_quatf, _ weight: Float) -> simd_quatf {
        guard weight > 0 else { return current }
        let shortest = simd_dot(current.vector, target.vector) < 0 ? simd_quatf(vector: -target.vector) : target
        return simd_normalize(simd_slerp(current, shortest, weight))
    }

    private static func smooth(_ value: Float) -> Float {
        let x = min(max(value, 0), 1)
        return x * x * x * (x * (x * 6 - 15) + 10)
    }
}
