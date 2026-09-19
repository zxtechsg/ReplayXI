import Foundation
import simd

/// Authored off-ball turning steps for the licensed skin. Root routes and the
/// procedural ball-contact rig are untouched. Absolute heading is the clock:
/// pausing, reverse playback and random seeks cannot accumulate planted drift.
@MainActor
struct ReplaySkinnedAthleteTurnInPlace {
    struct Sample: Equatable {
        let headingDegrees: Float
        let weight: Float

        func foot(left: Bool) -> (yaw: Float, lift: Float, isSupport: Bool) {
            // One foot cycle per quarter-turn; opposite feet are half a cycle
            // apart. Their 40% swing intervals never overlap.
            let cycles = headingDegrees.truncatingRemainder(dividingBy: 360) / 90 + (left ? 0 : 0.5)
            let phase = cycles - floor(cycles)
            let swing = min(max((phase - 0.60) / 0.40, 0), 1)
            // During support d(yaw)/d(heading)=-1, locking the world heading.
            // The quintic return matches value, velocity and acceleration at
            // lift-off, touchdown and the phase wrap, including reverse play.
            let yaw = (0.30 - phase + ReplaySkinnedAthleteTurnInPlace.smooth(swing)) * .pi / 2
            let height = sin(swing * .pi)
            return (yaw, 0.065 * height * height, phase <= 0.60)
        }
    }

    private struct Leg {
        let hip: Int
        let knee: Int
        let ankle: Int
        let left: Bool
        let sole: SIMD3<Float>
        let restSole: SIMD3<Float>
        let restFoot: simd_quatf
    }

    private let root: Int
    private let legs: [Leg]

    init?(motion: ReplaySkinnedAthleteMotion) {
        guard let root = motion.semanticJointIndices["hips"] else { return nil }
        var legs: [Leg] = []
        for side in ["left", "right"] {
            guard let hip = motion.semanticJointIndices[side + "Hip"],
                  let knee = motion.semanticJointIndices[side + "Knee"],
                  let ankle = motion.semanticJointIndices[side + "Ankle"],
                  let contact = motion.footContacts[side],
                  motion.joints[knee].parentIndex == hip,
                  motion.joints[ankle].parentIndex == knee else { return nil }
            legs.append(.init(hip: hip, knee: knee, ankle: ankle, left: side == "left",
                sole: contact.solePoint, restSole: contact.restSoleWorld,
                restFoot: simd_quatf(motion.restPose.modelSpaceTransforms[ankle])))
        }
        self.root = root
        self.legs = legs
    }

    static func sample(track: PlayerTrack, at time: TimeInterval, presentationPose: PlayerPose?,
                       locomotion: PlayerLocomotionSample, interaction: ReplayAthleteInteractionCue?,
                       actionInfluence: Float, enabled: Bool) -> Sample? {
        guard enabled, time.isFinite, let presentationPose, presentationPose.facingDegrees.isFinite,
              locomotion.speedMetresPerSecond.isFinite, locomotion.speedMetresPerSecond >= 0,
              actionInfluence.isFinite, actionInfluence >= 0 else { return nil }
        let slow = 1 - smooth((locomotion.speedMetresPerSecond - 0.08) / 0.27)
        guard slow > 0 else { return nil }
        // A 90°/s start crossing the 10...35°/s admission band in a narrow
        // 240ms window could settle the knee in only67ms. Use a centred480ms
        // window for this PRESENTATION blend, not the actor's facing or phase.
        // This halves that onset/reversal slope without frame-state damping
        // and keeps the full-weight support anchors/steps exactly unchanged.
        let halfWindow: TimeInterval = 0.24
        let before = track.presentationPose(at: time - halfWindow).facingDegrees
        let after = track.presentationPose(at: time + halfWindow).facingDegrees
        guard before.isFinite, after.isFinite else { return nil }
        let delta = (after.truncatingRemainder(dividingBy: 360)
            - before.truncatingRemainder(dividingBy: 360)) * .pi / 180
        let turnRate = abs(atan2(sin(delta), cos(delta))) * 180 / .pi / Float(halfWindow * 2)
        let freedom = 1 - ReplayAthleteMovementIntent.contactProtection(for: interaction, track: track, at: time)
        let weight = slow * smooth((turnRate - 10) / 25) * freedom * (1 - smooth(actionInfluence / 0.05))
        guard weight > 0 else { return nil }
        return Sample(headingDegrees: presentationPose.facingDegrees, weight: weight)
    }

    /// Input model matrices are current. Modify rotations only in the two
    /// chains, preserving their exact segment lengths; a small pelvis settle
    /// gives the support leg room to turn without locking its knee straight.
    func apply(_ sample: Sample, motion: ReplaySkinnedAthleteMotion,
               to pose: inout ReplaySkinnedAthleteMotion.Pose) {
        guard sample.weight.isFinite, (0...1).contains(sample.weight), sample.weight > 0,
              sample.headingDegrees.isFinite else { return }
        let shift = SIMD3<Float>(0, -0.025 * sample.weight, 0)
        pose.translations[root] += shift
        for leg in legs {
            let hipMatrix = pose.modelSpaceTransforms[leg.hip]
            let kneeMatrix = pose.modelSpaceTransforms[leg.knee]
            let ankleMatrix = pose.modelSpaceTransforms[leg.ankle]
            let hip = Self.point(hipMatrix) + shift
            let knee = Self.point(kneeMatrix) + shift
            let ankle = Self.point(ankleMatrix) + shift
            let upperLength = simd_distance(hip, knee)
            let lowerLength = simd_distance(knee, ankle)
            let span = simd_length_squared(ankle - hip)
            guard upperLength.isFinite, lowerLength.isFinite, span.isFinite,
                  (0.05...1.5).contains(upperLength), (0.05...1.5).contains(lowerLength),
                  span > 0.000001 else { continue }
            let currentSole4 = ankleMatrix * SIMD4(leg.sole, 1)
            let currentSole = SIMD3<Float>(currentSole4.x, currentSole4.y, currentSole4.z) + shift
            let step = sample.foot(left: leg.left)
            let turn = simd_quatf(angle: step.yaw, axis: [0, 1, 0])
            var wantedSole = turn.act(leg.restSole)
            wantedSole.y = motion.geometry.restMinY + step.lift
            let goalSole = currentSole + (wantedSole - currentSole) * sample.weight
            let foot = ReplayAthleteInteractionPose.blend(simd_quatf(ankleMatrix),
                turn * leg.restFoot, sample.weight)
            let goal = goalSole - foot.act(leg.sole)
            let axis = simd_normalize(ankle - hip)
            let oldBend = knee - hip - axis * simd_dot(knee - hip, axis)
            let bootForward = turn.act(SIMD3<Float>(0, 0, 1))
            // The two planted boots can differ by45° through a pivot. Driving
            // both knees wholly along those toe-in frames made them converge
            // across the body's midline. Keep a small outward knee lane while
            // allowing a bounded share of the boot's yaw; ankle goals stay put.
            let sideSign: Float = leg.restSole.x < 0 ? -1 : 1
            let forward = simd_normalize(SIMD3<Float>(bootForward.x * 0.15 + sideSign * 0.08,
                                                      0, bootForward.z))
            let oldPole = simd_length_squared(oldBend) > 0.000001 ? simd_normalize(oldBend) : forward
            let pole = oldPole + (forward - oldPole) * sample.weight
            guard let solved = ReplayAthleteTwoBoneIK.solve(hip: hip, ankle: goal,
                upperLength: upperLength, lowerLength: lowerLength, pole: pole)
            else { continue }
            // Swing existing frames onto the IK chain without replacing axial
            // twist at a tiny blend weight. No translations or bones stretch.
            let upper = simd_normalize(simd_quatf(from: simd_normalize(knee - hip),
                to: simd_normalize(solved.knee - hip)) * simd_quatf(hipMatrix))
            let lower = simd_normalize(simd_quatf(from: simd_normalize(ankle - knee),
                to: simd_normalize(solved.ankle - solved.knee)) * simd_quatf(kneeMatrix))
            let parent = motion.joints[leg.hip].parentIndex
            let parentRotation = parent < 0 ? simd_quatf(real: 1, imag: .zero)
                : simd_quatf(pose.modelSpaceTransforms[parent])
            pose.rotations[leg.hip] = simd_normalize(parentRotation.inverse * upper)
            pose.rotations[leg.knee] = simd_normalize(upper.inverse * lower)
            pose.rotations[leg.ankle] = simd_normalize(lower.inverse * foot)
        }
        motion.rebuildModelSpaceTransforms(in: &pose)
    }

    private static func point(_ matrix: simd_float4x4) -> SIMD3<Float> {
        [matrix.columns.3.x, matrix.columns.3.y, matrix.columns.3.z]
    }

    private static func smooth(_ value: Float) -> Float {
        let x = min(max(value, 0), 1)
        return x * x * x * (x * (x * 6 - 15) + 10)
    }
}
