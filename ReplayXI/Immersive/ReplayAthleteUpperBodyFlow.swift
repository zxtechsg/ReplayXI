import Foundation
import simd

/// Restrained follow-through above the planted pelvis. All channels use the
/// travelled gait phase; seeking never depends on the preceding rendered frame.
enum ReplayAthleteUpperBodyFlow {
    struct Arm: Equatable, Sendable {
        let shoulderPitch: Float
        let shoulderRoll: Float
        let elbowFlexion: Float
        let wristPitch: Float
        let wristYaw: Float

        static let zero = Arm(shoulderPitch: 0, shoulderRoll: 0, elbowFlexion: 0,
                              wristPitch: 0, wristYaw: 0)
        var shoulderRotation: simd_quatf {
            simd_quatf(angle: shoulderRoll, axis: [0, 0, 1])
                * simd_quatf(angle: shoulderPitch, axis: [1, 0, 0])
        }
        var elbowRotation: simd_quatf { simd_quatf(angle: -elbowFlexion, axis: [1, 0, 0]) }
        var wristRotation: simd_quatf {
            simd_quatf(angle: wristPitch, axis: [1, 0, 0])
                * simd_quatf(angle: wristYaw, axis: [0, 1, 0])
        }
    }

    struct Sample: Equatable, Sendable {
        let chestYaw: Float
        let chestPitch: Float
        let chestRoll: Float
        let leftArm: Arm
        let rightArm: Arm

        static let zero = Sample(chestYaw: 0, chestPitch: 0, chestRoll: 0,
                                 leftArm: .zero, rightArm: .zero)
        var isIdentity: Bool { self == .zero }
        var chestRotation: simd_quatf {
            simd_quatf(angle: chestPitch, axis: [1, 0, 0])
                * simd_quatf(angle: chestRoll, axis: [0, 0, 1])
                * simd_quatf(angle: chestYaw, axis: [0, 1, 0])
        }
        func arm(isLeft: Bool) -> Arm { isLeft ? leftArm : rightArm }
        func adjusting(_ look: ReplayAthleteLookPose) -> ReplayAthleteLookPose {
            guard !isIdentity else { return look }
            return .init(neckYawRadians: look.neckYawRadians - chestYaw * 0.42,
                         headYawRadians: look.headYawRadians - chestYaw * 0.58,
                         neckPitchRadians: look.neckPitchRadians - chestPitch * 0.34,
                         headPitchRadians: look.headPitchRadians - chestPitch * 0.66)
        }
    }

    static func sample(gaitPhase: Float, locomotion: PlayerLocomotionSample,
                       actionInfluence: Float, armReadiness: Float = 0,
                       enabled: Bool = true) -> Sample {
        guard enabled, gaitPhase.isFinite, locomotion.speedMetresPerSecond.isFinite,
              actionInfluence.isFinite, armReadiness.isFinite else { return .zero }
        let moving = smooth((locomotion.speedMetresPerSecond - 0.35) / 1.45)
        let freedom = 1 - smooth((actionInfluence - 0.05) / 0.65)
        let weight = moving * freedom * (0.55 + 0.45 * locomotion.effort)
        guard weight > 0 else { return .zero }
        let phase = gaitPhase.remainder(dividingBy: 2 * .pi)
        // Distal joints follow the shoulder slightly later. A common phase
        // keeps the hand, elbow and chest connected as speed/turn blends change.
        let armWeight = weight * (1 - min(max(armReadiness, 0), 1))
        func arm(_ offset: Float, side: Float) -> Arm {
            let p = phase + offset
            return .init(shoulderPitch: -sin(p - 0.12) * 0.065 * armWeight,
                         shoulderRoll: side * sin(p - 0.12) * 0.018 * armWeight,
                         elbowFlexion: sin(p - 0.34) * 0.055 * armWeight,
                         wristPitch: sin(p - 0.58) * 0.070 * armWeight,
                         wristYaw: side * sin(p - 0.58) * 0.025 * armWeight)
        }
        return .init(chestYaw: sin(phase - 0.28) * 0.050 * weight,
                     chestPitch: sin(phase * 2 - 0.40) * 0.010 * weight,
                     chestRoll: sin(phase - 0.44) * 0.025 * weight,
                     leftArm: arm(0, side: -1), rightArm: arm(.pi, side: 1))
    }

    /// Cache the real hierarchy once. Rocketbox's first spine owns the thighs;
    /// exclude any such ancestor so added torso articulation cannot move boots.
    struct NativeBinding {
        let torsoJointIndices: [Int]
        private let chest: Int
        private let inverseRestChest: simd_quatf
        private let arms: [NativeArm]

        init?(motion: ReplaySkinnedAthleteMotion) {
            guard let chest = motion.semanticJointIndices["chest"],
                  let spine = motion.semanticJointIndices["spine"],
                  let leftHip = motion.semanticJointIndices["leftHip"],
                  let rightHip = motion.semanticJointIndices["rightHip"],
                  let left = NativeArm(side: "left", motion: motion),
                  let right = NativeArm(side: "right", motion: motion) else { return nil }
            func contains(_ ancestor: Int, _ joint: Int) -> Bool {
                var index = joint
                while index >= 0 {
                    if index == ancestor { return true }
                    index = motion.joints[index].parentIndex
                }
                return false
            }
            guard contains(spine, chest) else { return nil }
            var chain: [Int] = [], index = chest
            while index >= 0 {
                if !contains(index, leftHip), !contains(index, rightHip) { chain.append(index) }
                if index == spine { break }
                index = motion.joints[index].parentIndex
            }
            guard !chain.isEmpty else { return nil }
            torsoJointIndices = chain.reversed()
            self.chest = chest
            inverseRestChest = simd_quatf(motion.restPose.modelSpaceTransforms[chest]).inverse
            arms = [left, right]
        }

        func apply(_ sample: Sample, motion: ReplaySkinnedAthleteMotion,
                   to pose: inout ReplaySkinnedAthleteMotion.Pose) {
            guard !sample.isIdentity else { return }
            let count = torsoJointIndices.count
            let total = Float(count * (count + 1)) / 2
            // Fractions of one model-space rotation compose to the same chest
            // turn, while the lower/mid spine bend along with the shoulders.
            for (offset, index) in torsoJointIndices.enumerated() {
                let fraction = Float(offset + 1) / total
                let delta = simd_slerp(simd_quatf(real: 1, imag: .zero), sample.chestRotation, fraction)
                let parent = modelRotation(motion.joints[index].parentIndex, motion: motion, pose: pose)
                pose.rotations[index] = simd_normalize(parent.inverse * delta * parent * pose.rotations[index])
            }
            let torso = modelRotation(chest, motion: motion, pose: pose) * inverseRestChest
            for arm in arms { arm.apply(sample.arm(isLeft: arm.isLeft), torso: torso, motion: motion, to: &pose) }
        }
    }

    private struct NativeArm {
        let shoulder: Int
        let elbow: Int
        let wrist: Int
        let isLeft: Bool
        let shoulderNeutral: simd_quatf
        let elbowNeutral: simd_quatf

        init?(side: String, motion: ReplaySkinnedAthleteMotion) {
            guard let binding = ReplayAthleteOffBallPose.NativeArmBinding(side: side, motion: motion),
                  let wrist = motion.semanticJointIndices[side + "Wrist"] else { return nil }
            shoulder = binding.shoulder; elbow = binding.elbow; self.wrist = wrist
            isLeft = binding.isLeft
            shoulderNeutral = binding.shoulderNeutral; elbowNeutral = binding.elbowNeutral
        }

        func apply(_ arm: Arm, torso: simd_quatf, motion: ReplaySkinnedAthleteMotion,
                   to pose: inout ReplaySkinnedAthleteMotion.Pose) {
            guard arm != .zero else { return }
            rotate(shoulder, by: arm.shoulderRotation, in: torso, motion: motion, pose: &pose)
            let upper = modelRotation(shoulder, motion: motion, pose: pose) * shoulderNeutral.inverse
            rotate(elbow, by: arm.elbowRotation, in: upper, motion: motion, pose: &pose)
            let lower = modelRotation(elbow, motion: motion, pose: pose) * elbowNeutral.inverse
            rotate(wrist, by: arm.wristRotation, in: lower, motion: motion, pose: &pose)
        }

        private func rotate(_ joint: Int, by delta: simd_quatf, in frame: simd_quatf,
                            motion: ReplaySkinnedAthleteMotion, pose: inout ReplaySkinnedAthleteMotion.Pose) {
            let parent = modelRotation(motion.joints[joint].parentIndex, motion: motion, pose: pose)
            pose.rotations[joint] = simd_normalize(parent.inverse * frame * delta * frame.inverse
                * parent * pose.rotations[joint])
        }
    }

    private static func modelRotation(_ index: Int, motion: ReplaySkinnedAthleteMotion,
                                      pose: ReplaySkinnedAthleteMotion.Pose) -> simd_quatf {
        ReplayAthleteOffBallPose.modelRotation(index, motion: motion, pose: pose)
    }

    private static func smooth(_ value: Float) -> Float {
        let x = min(max(value, 0), 1)
        return x * x * x * (x * (x * 6 - 15) + 10)
    }
}
