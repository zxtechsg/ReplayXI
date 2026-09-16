import Foundation
import simd

/// Retargets the existing deterministic fall onto the licensed whole-body skin.
/// Biped's thighs belong to Spine and its clavicles belong to Neck. Recovering
/// real parent-local transforms from model-space targets keeps those unusual
/// bindings from bending the legs with the chest or dragging arms with gaze.
/// This is a bounded replay pose, not a second live physics simulation.
struct ReplaySkinnedAthleteImpactPose {
    private struct Limb {
        let proximal: Int
        let middle: Int
        let distal: Int
        let negativeSide: Bool
        let offset: SIMD3<Float>
        let upperLength: Float
        let lowerLength: Float
        let proximalNeutral: simd_quatf
        let middleNeutral: simd_quatf
        let distalNeutral: simd_quatf
    }

    private struct LimbTarget {
        let proximalPosition: SIMD3<Float>
        let middlePosition: SIMD3<Float>
        let distalPosition: SIMD3<Float>
        let proximalRotation: simd_quatf
        let middleRotation: simd_quatf
        let distalRotation: simd_quatf

        func transform(for index: Int, limb: Limb) -> (SIMD3<Float>, simd_quatf)? {
            switch index {
            case limb.proximal: (proximalPosition, proximalRotation)
            case limb.middle: (middlePosition, middleRotation)
            case limb.distal: (distalPosition, distalRotation)
            default: nil
            }
        }
    }

    /// Small calibrated support envelope. Avoid CPU-skinning all 5,012 vertices
    /// every frame just to keep a reviewed fall above the pitch.
    private struct Support {
        let joint: Int
        let localPoint: SIMD3<Float>
        let radius: Float
    }

    private let root: Int
    private let spine: Int
    private let head: Int
    private let leftLeg: Limb
    private let rightLeg: Limb
    private let leftArm: Limb
    private let rightArm: Limb
    private let drivenIndices: [Int]
    private let supports: [Support]
    private var target: ReplaySkinnedAthleteMotion.Pose

    init?(motion: ReplaySkinnedAthleteMotion) {
        guard let root = motion.semanticJointIndices["hips"],
              let spine = motion.semanticJointIndices["spine"],
              let head = motion.semanticJointIndices["head"],
              let leftLeg = Self.limb("left", isArm: false, pivot: root, motion: motion),
              let rightLeg = Self.limb("right", isArm: false, pivot: root, motion: motion),
              let leftArm = Self.limb("left", isArm: true, pivot: spine, motion: motion),
              let rightArm = Self.limb("right", isArm: true, pivot: spine, motion: motion)
        else { return nil }
        self.root = root
        self.spine = spine
        self.head = head
        self.leftLeg = leftLeg
        self.rightLeg = rightLeg
        self.leftArm = leftArm
        self.rightArm = rightArm
        var driven = Set<Int>()
        for end in [head, leftLeg.distal, rightLeg.distal, leftArm.distal, rightArm.distal] {
            var index = end
            while index >= 0 {
                driven.insert(index)
                index = motion.joints[index].parentIndex
            }
        }
        drivenIndices = driven.sorted()
        supports = Self.supports(motion: motion)
        target = motion.makePoseBuffer()
    }

    /// The source pose already includes football gait and look. Blend back to
    /// exactly that pose at recovery, so seeking either cue edge never swaps a
    /// mesh or snaps to an unrelated idle frame. Caller rebuilds final hierarchy.
    mutating func apply(_ impact: PlayerRagdollPose, influence: Float,
                        motion: ReplaySkinnedAthleteMotion,
                        to pose: inout ReplaySkinnedAthleteMotion.Pose) {
        let weight = influence.isFinite ? min(max(influence, 0), 1) : 0
        guard weight > 0 else { return }
        motion.rebuildModelSpaceTransforms(in: &pose)
        let originalSupport = minimumSupportY(in: pose)
        for index in motion.joints.indices {
            target.translations[index] = pose.translations[index]
            target.rotations[index] = pose.rotations[index]
            target.scales[index] = pose.scales[index]
        }
        // Face, fingers and toes retain the sampled clip. Only the articulated
        // body chains return to their audited neutral basis before retargeting.
        for index in drivenIndices {
            target.translations[index] = motion.restPose.translations[index]
            target.rotations[index] = motion.restPose.rotations[index]
            target.scales[index] = motion.restPose.scales[index]
        }
        let body = simd_quatf(angle: impact.fallAngle, axis: impact.fallAxis)
            * simd_quatf(angle: impact.bodyTwist, axis: [0, 1, 0])
        let restRoot = Self.position(motion.restPose.modelSpaceTransforms[root])
        let restSpine = Self.position(motion.restPose.modelSpaceTransforms[spine])
        let rootPosition = impact.bodyCenter + body.act(restRoot - SIMD3(0, 0.92, 0))
        let spinePosition = rootPosition + body.act(restSpine - restRoot)
        let torso = body * simd_quatf(angle: impact.spineRoll, axis: [0, 0, 1])
            * simd_quatf(angle: impact.spinePitch, axis: [1, 0, 0])
        let headRotation = torso * simd_quatf(angle: impact.headPitch, axis: [1, 0, 0])
            * simd_quatf(angle: impact.headYaw, axis: [0, 1, 0])
        let leftLegTarget = Self.legTarget(leftLeg, impact: impact, body: body, root: rootPosition)
        let rightLegTarget = Self.legTarget(rightLeg, impact: impact, body: body, root: rootPosition)
        let leftArmTarget = Self.groundArm(
            Self.armTarget(leftArm, impact: impact, torso: torso, spine: spinePosition),
            limb: leftArm, floor: motion.geometry.restMinY
        )
        let rightArmTarget = Self.groundArm(
            Self.armTarget(rightArm, impact: impact, torso: torso, spine: spinePosition),
            limb: rightArm, floor: motion.geometry.restMinY
        )

        for index in motion.joints.indices {
            let parent = motion.joints[index].parentIndex
            let parentMatrix = parent < 0 ? matrix_identity_float4x4 : target.modelSpaceTransforms[parent]
            let desired: (SIMD3<Float>, simd_quatf)?
            switch index {
            case root:
                desired = (rootPosition, body * simd_quatf(motion.restPose.modelSpaceTransforms[root]))
            case spine:
                desired = (spinePosition, torso * simd_quatf(motion.restPose.modelSpaceTransforms[spine]))
            case head:
                let offset = Self.position(motion.restPose.modelSpaceTransforms[head]) - restSpine
                desired = (spinePosition + torso.act(offset),
                           headRotation * simd_quatf(motion.restPose.modelSpaceTransforms[head]))
            default:
                desired = leftLegTarget.transform(for: index, limb: leftLeg)
                    ?? rightLegTarget.transform(for: index, limb: rightLeg)
                    ?? leftArmTarget.transform(for: index, limb: leftArm)
                    ?? rightArmTarget.transform(for: index, limb: rightArm)
            }
            if let (position, rotation) = desired {
                let localPosition = parentMatrix.inverse * SIMD4(position, 1)
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
        let floor = motion.geometry.restMinY
        target.translations[root].y += max(floor - minimumSupportY(in: target), 0)
        for index in drivenIndices {
            pose.translations[index] += (target.translations[index] - pose.translations[index]) * weight
            var rotation = target.rotations[index]
            if simd_dot(pose.rotations[index].vector, rotation.vector) < 0 {
                rotation = simd_quatf(vector: -rotation.vector)
            }
            pose.rotations[index] = simd_normalize(simd_slerp(pose.rotations[index], rotation, weight))
        }
        // Quaternion blending can arc a hand/boot through the turf even when
        // both endpoint poses clear it. Ground the blended pose too. Preserve
        // existing source-clip tolerances at the edges instead of adding a pop.
        motion.rebuildModelSpaceTransforms(in: &pose)
        let blendedFloor = min(originalSupport, floor) * (1 - weight) + floor * weight
        pose.translations[root].y += max(blendedFloor - minimumSupportY(in: pose), 0)
    }

    func minimumSupportY(in pose: ReplaySkinnedAthleteMotion.Pose) -> Float {
        supports.reduce(Float.infinity) { result, support in
            min(result, (pose.modelSpaceTransforms[support.joint] * SIMD4(support.localPoint, 1)).y - support.radius)
        }
    }

    private static func limb(_ name: String, isArm: Bool, pivot: Int,
                             motion: ReplaySkinnedAthleteMotion) -> Limb? {
        guard let proximal = motion.semanticJointIndices[name + (isArm ? "Shoulder" : "Hip")],
              let middle = motion.semanticJointIndices[name + (isArm ? "Elbow" : "Knee")],
              let distal = motion.semanticJointIndices[name + (isArm ? "Wrist" : "Ankle")]
        else { return nil }
        let first = position(motion.restPose.modelSpaceTransforms[proximal])
        let second = position(motion.restPose.modelSpaceTransforms[middle])
        let third = position(motion.restPose.modelSpaceTransforms[distal])
        let upper = second - first
        let lower = third - second
        guard simd_length(upper) > 0.1, simd_length(lower) > 0.1 else { return nil }
        let upperToDown = simd_quatf(from: simd_normalize(upper), to: [0, -1, 0])
        let lowerToDown = simd_quatf(from: simd_normalize(lower), to: [0, -1, 0])
        return Limb(
            proximal: proximal, middle: middle, distal: distal, negativeSide: first.x < 0,
            offset: first - position(motion.restPose.modelSpaceTransforms[pivot]),
            upperLength: simd_length(upper), lowerLength: simd_length(lower),
            proximalNeutral: simd_normalize(upperToDown * simd_quatf(motion.restPose.modelSpaceTransforms[proximal])),
            middleNeutral: simd_normalize(lowerToDown * simd_quatf(motion.restPose.modelSpaceTransforms[middle])),
            distalNeutral: simd_normalize((isArm ? lowerToDown : simd_quatf())
                * simd_quatf(motion.restPose.modelSpaceTransforms[distal]))
        )
    }

    private static func legTarget(_ limb: Limb, impact: PlayerRagdollPose,
                                  body: simd_quatf, root: SIMD3<Float>) -> LimbTarget {
        let left = limb.negativeSide
        return target(limb, pivot: root, base: body,
                      proximal: simd_quatf(angle: left ? impact.leftHip : impact.rightHip, axis: [1, 0, 0]),
                      middle: simd_quatf(angle: left ? impact.leftKnee : impact.rightKnee, axis: [1, 0, 0]),
                      distal: simd_quatf(angle: left ? impact.leftAnkle : impact.rightAnkle, axis: [1, 0, 0]))
    }

    private static func armTarget(_ limb: Limb, impact: PlayerRagdollPose,
                                  torso: simd_quatf, spine: SIMD3<Float>) -> LimbTarget {
        let left = limb.negativeSide
        return target(limb, pivot: spine, base: torso,
                      proximal: simd_quatf(angle: left ? impact.leftShoulderRoll : impact.rightShoulderRoll, axis: [0, 0, 1])
                        * simd_quatf(angle: left ? impact.leftShoulderPitch : impact.rightShoulderPitch, axis: [1, 0, 0]),
                      // Elbows flex forward; unlike knees, their hinge is -X
                      // when both segments hang along -Y in the neutral pose.
                      middle: simd_quatf(angle: -(left ? impact.leftElbow : impact.rightElbow), axis: [1, 0, 0]),
                      distal: simd_quatf(angle: left ? impact.leftWrist : impact.rightWrist, axis: [0, 1, 0]))
    }

    private static func target(_ limb: Limb, pivot: SIMD3<Float>, base: simd_quatf,
                               proximal: simd_quatf, middle: simd_quatf, distal: simd_quatf) -> LimbTarget {
        let upper = base * proximal
        let lower = upper * middle
        let end = lower * distal
        let first = pivot + base.act(limb.offset)
        let second = first + upper.act(SIMD3(0, -limb.upperLength, 0))
        return LimbTarget(proximalPosition: first, middlePosition: second,
                          distalPosition: second + lower.act(SIMD3(0, -limb.lowerLength, 0)),
                          proximalRotation: simd_normalize(upper * limb.proximalNeutral),
                          middleRotation: simd_normalize(lower * limb.middleNeutral),
                          distalRotation: simd_normalize(end * limb.distalNeutral))
    }

    /// Solve a contacted arm on its two-bone reach circle. Simply translating
    /// the whole body until a dangling hand clears the floor produces a floating
    /// plank. Keep the shoulder with the torso and let the elbow fold instead.
    private static func groundArm(_ original: LimbTarget, limb: Limb, floor: Float) -> LimbTarget {
        let elbowFloor = floor + 0.055
        let wristFloor = floor + 0.12
        guard original.middlePosition.y < elbowFloor || original.distalPosition.y < wristFloor else {
            return original
        }
        let start = original.proximalPosition
        var end = original.distalPosition
        end.y = max(end.y, wristFloor)
        let reach = end - start
        let distance = simd_length(reach)
        guard distance > 0.0001 else { return original }
        let axis = reach / distance
        let length = min(max(distance, abs(limb.upperLength - limb.lowerLength) + 0.0001),
                         limb.upperLength + limb.lowerLength - 0.0001)
        end = start + axis * length
        let along = (limb.upperLength * limb.upperLength - limb.lowerLength * limb.lowerLength
                     + length * length) / (2 * length)
        let centre = start + axis * along
        let radius = sqrt(max(limb.upperLength * limb.upperLength - along * along, 0))
        let up = SIMD3<Float>(0, 1, 0)
        let vertical = up - axis * axis.y
        let verticalLength = simd_length(vertical)
        guard radius > 0.00001, verticalLength > 0.00001 else { return original }
        let circleUp = vertical / verticalLength
        let circleSide = simd_normalize(simd_cross(axis, circleUp))
        let originalAxis = simd_normalize(original.distalPosition - start)
        let originalUpper = original.middlePosition - start
        let originalPole = originalUpper - originalAxis * simd_dot(originalUpper, originalAxis)
        let poleLength = simd_length(originalPole)
        // Transport the authored bend plane with the wrist target. Projecting
        // the old elbow onto the new reach line can cross that line and flip
        // the forearm's twist by 180 degrees as the palm first meets the turf.
        let pole = poleLength > 0.00001
            ? simd_quatf(from: originalAxis, to: axis).act(originalPole / poleLength)
            : circleUp
        let minimumUp = min(max((elbowFloor - centre.y) / (radius * verticalLength), -1), 1)
        let poleUp = min(max(simd_dot(pole, circleUp), minimumUp), 1)
        let sideSign: Float = simd_dot(pole, circleSide) < 0 ? -1 : 1
        let elbow = centre + radius * (circleUp * poleUp
            + circleSide * (sideSign * sqrt(max(1 - poleUp * poleUp, 0))))
        let upperDirection = simd_normalize(elbow - start)
        let lowerDirection = simd_normalize(end - elbow)
        let hinge = simd_normalize(simd_cross(lowerDirection, upperDirection))
        func rotation(_ direction: SIMD3<Float>) -> simd_quatf {
            let up = -direction
            let forward = simd_normalize(simd_cross(hinge, up))
            return simd_normalize(simd_quatf(simd_float3x3(columns: (hinge, up, forward))))
        }
        let upperRotation = rotation(upperDirection) * limb.proximalNeutral
        let lowerRotation = rotation(lowerDirection) * limb.middleNeutral
        let wristOffset = original.middleRotation.inverse * original.distalRotation
        return LimbTarget(proximalPosition: start, middlePosition: elbow, distalPosition: end,
                          proximalRotation: simd_normalize(upperRotation),
                          middleRotation: simd_normalize(lowerRotation),
                          distalRotation: simd_normalize(lowerRotation * wristOffset))
    }

    private static func supports(motion: ReplaySkinnedAthleteMotion) -> [Support] {
        var result: [Support] = []
        func append(_ name: String, offset: SIMD3<Float> = .zero, radius: Float) {
            guard let joint = motion.semanticJointIndices[name] else { return }
            let rest = motion.restPose.modelSpaceTransforms[joint]
            let local = rest.inverse * SIMD4(position(rest) + offset, 1)
            result.append(Support(joint: joint, localPoint: SIMD3(local.x, local.y, local.z), radius: radius))
        }
        append("hips", radius: 0.13)
        append("spine", offset: [0, 0.04, 0], radius: 0.14)
        append("chest", offset: [0, 0.06, 0], radius: 0.16)
        append("head", offset: [0, 0.10, 0], radius: 0.125)
        for side in ["left", "right"] {
            append(side + "Hip", radius: 0.10)
            append(side + "Knee", radius: 0.07)
            append(side + "Ankle", radius: 0.05)
            append(side + "Shoulder", radius: 0.075)
            append(side + "Elbow", radius: 0.05)
            append(side + "Wrist", radius: 0.04)
            if let elbow = motion.semanticJointIndices[side + "Elbow"],
               let wrist = motion.semanticJointIndices[side + "Wrist"] {
                let direction = simd_normalize(position(motion.restPose.modelSpaceTransforms[wrist])
                    - position(motion.restPose.modelSpaceTransforms[elbow]))
                append(side + "Wrist", offset: direction * 0.065, radius: 0.055)
            }
            if let foot = motion.footContacts[side] {
                let inverse = motion.restPose.modelSpaceTransforms[foot.footJointIndex].inverse
                for x: Float in [-0.045, 0.045] {
                    for z: Float in [-0.09, 0.11] {
                        let local = inverse * SIMD4(foot.restSoleWorld + SIMD3(x, 0, z), 1)
                        result.append(Support(joint: foot.footJointIndex,
                                              localPoint: SIMD3(local.x, local.y, local.z), radius: 0))
                    }
                }
            }
        }
        return result
    }

    private static func position(_ matrix: simd_float4x4) -> SIMD3<Float> {
        SIMD3(matrix.columns.3.x, matrix.columns.3.y, matrix.columns.3.z)
    }
}
