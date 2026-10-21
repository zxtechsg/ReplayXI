import Foundation
import simd

/// Turns Tripo palms toward the torso and retains a curled running grip.
/// Every arm, contact, and root joint stays unchanged.
struct ReplayAthleteHandPose {
    private struct Wrist {
        let index: Int
        let parentChain: [Int]
        let palmAxis: SIMD3<Float>
        let reachAxis: SIMD3<Float>
        let medialSign: Float
    }

    private struct Digit {
        let segments: [Segment]
    }

    private struct Segment {
        let index: Int
        let bendAxis: SIMD3<Float>
    }

    private let wrists: [Wrist]
    private let chestChain: [Int]
    private let bodyRightInChest: SIMD3<Float>
    private let bodyDownInChest: SIMD3<Float>
    private let digits: [Digit]
    private let restRotations: [simd_quatf]
    private let targetCurl: [Float]
    private let thumbSourceBlend: Float

    init?(motion: ReplaySkinnedAthleteMotion) {
        guard motion.rigProfile == .tripo52 else { return nil }
        let lookup = Dictionary(uniqueKeysWithValues: motion.joints.enumerated().map {
            ($0.element.sourceName, $0.offset)
        })
        guard let chest = motion.semanticJointIndices["chest"],
              let hips = motion.semanticJointIndices["hips"] else { return nil }
        func chain(to index: Int) -> [Int] {
            var result: [Int] = []
            var cursor = index
            while cursor >= 0 {
                result.append(cursor)
                cursor = motion.joints[cursor].parentIndex
            }
            return result.reversed()
        }
        var wrists: [Wrist] = []
        var digits: [Digit] = []
        let rest = motion.restPose.modelSpaceTransforms
        func position(_ index: Int) -> SIMD3<Float> {
            let column = rest[index].columns.3
            return [column.x, column.y, column.z]
        }
        guard let leftWrist = lookup["mixamorig:LeftHand"],
              let rightWrist = lookup["mixamorig:RightHand"] else { return nil }
        let bodyRight = position(rightWrist) - position(leftWrist)
        guard simd_length(bodyRight) > 0.01 else { return nil }
        chestChain = chain(to: chest)
        bodyRightInChest = simd_quatf(rest[chest]).inverse.act(simd_normalize(bodyRight))
        let bodyDown = position(hips) - position(chest)
        guard simd_length(bodyDown) > 0.01 else { return nil }
        bodyDownInChest = simd_quatf(rest[chest]).inverse.act(simd_normalize(bodyDown))
        for side in ["Left", "Right"] {
            guard let wrist = lookup["mixamorig:\(side)Hand"] else { return nil }
            guard let index = lookup["mixamorig:\(side)HandIndex1"],
                  let middle = lookup["mixamorig:\(side)HandMiddle1"],
                  let pinky = lookup["mixamorig:\(side)HandPinky1"],
                  let thumb = lookup["mixamorig:\(side)HandThumb1"]
            else { return nil }
            let span = position(index) - position(pinky)
            let reach = position(middle) - position(wrist)
            var palmNormal = simd_cross(span, reach)
            guard simd_length(palmNormal) > 0.0001 else { return nil }
            palmNormal = simd_normalize(palmNormal)
            // The two Tripo identities have opposite small Y components in
            // this normal. Orient it with the thumb base, the palmar side of
            // both actual meshes, rather than an arbitrary world-up sign.
            if simd_dot(palmNormal, position(thumb) - position(wrist)) < 0 {
                palmNormal = -palmNormal
            }
            let restWrist = simd_quatf(rest[wrist])
            wrists.append(Wrist(index: wrist, parentChain: chain(to: motion.joints[wrist].parentIndex),
                palmAxis: restWrist.inverse.act(palmNormal),
                reachAxis: restWrist.inverse.act(simd_normalize(reach)),
                medialSign: side == "Left" ? 1 : -1))
            for name in ["Index", "Middle", "Ring", "Pinky", "Thumb"] {
                let indices = (1...3).compactMap { lookup["mixamorig:\(side)Hand\(name)\($0)"] }
                guard indices.count == 3 else { return nil }
                var segments: [Segment] = []
                for (offset, joint) in indices.enumerated() {
                    if name == "Thumb" {
                        segments.append(Segment(index: joint, bendAxis: .zero))
                        continue
                    }
                    let next = indices[min(offset + 1, 2)]
                    let previous = indices[max(offset - 1, 0)]
                    let shaft = offset == 2 ? position(joint) - position(previous)
                                            : position(next) - position(joint)
                    guard simd_length(shaft) > 0.0001 else { return nil }
                    let worldAxis = simd_cross(simd_normalize(shaft), palmNormal)
                    guard simd_length(worldAxis) > 0.0001 else { return nil }
                    let localAxis = simd_quatf(rest[joint]).inverse.act(simd_normalize(worldAxis))
                    segments.append(Segment(index: joint, bendAxis: localAxis))
                }
                digits.append(Digit(segments: segments))
            }
        }
        self.wrists = wrists
        self.digits = digits
        restRotations = motion.restPose.rotations
        // Player A's repaired skin retains only part of each transferred
        // finger weight; it needs a larger bone bend for the same mesh curl.
        targetCurl = motion.sourceCommit.hasPrefix("player-a-glb-")
            ? [0.65, 0.75, 0.35] : [0.35, 0.40, 0.20]
        thumbSourceBlend = motion.sourceCommit.hasPrefix("player-a-glb-") ? 0.22 : 0.80
    }

    func apply(to pose: inout ReplaySkinnedAthleteMotion.Pose, preserveWrist: Bool = false) {
        guard pose.rotations.count == restRotations.count else { return }
        if !preserveWrist {
            let chestRotation = orientation(chestChain, in: pose)
            for wrist in wrists {
                let parentRotation = orientation(wrist.parentChain, in: pose)
                var handRotation = parentRotation * pose.rotations[wrist.index]
                var reach = simd_normalize(handRotation.act(wrist.reachAxis))
                // A running swing can leave a hand level across the waist.
                // Flex only the wrist, by at most 34 degrees, toward the
                // chest-to-hips axis; save/parry IK skips this whole block.
                let down = simd_normalize(chestRotation.act(bodyDownInChest))
                let downDot = min(max(simd_dot(reach, down), -1), 1)
                if downDot < 0.55 {
                    let axis = simd_cross(reach, down)
                    if simd_length(axis) > 0.001 {
                        let bend = min(acos(downDot) - acos(0.55), 0.60)
                        let localAxis = handRotation.inverse.act(simd_normalize(axis))
                        pose.rotations[wrist.index] = simd_normalize(pose.rotations[wrist.index]
                            * simd_quatf(angle: bend, axis: localAxis))
                        handRotation = parentRotation * pose.rotations[wrist.index]
                        reach = simd_normalize(handRotation.act(wrist.reachAxis))
                    }
                }
                // Pronate around the hand's own long axis. The chest defines
                // medial, so this follows body turns and either arm's swing.
                let palm = simd_normalize(handRotation.act(wrist.palmAxis))
                let medial = chestRotation.act(bodyRightInChest) * wrist.medialSign
                let projected = medial - reach * simd_dot(medial, reach)
                guard simd_length(projected) > 0.1 else { continue }
                let target = simd_normalize(projected)
                let twist = atan2(simd_dot(reach, simd_cross(palm, target)),
                                  simd_dot(palm, target))
                pose.rotations[wrist.index] = simd_normalize(pose.rotations[wrist.index]
                    * simd_quatf(angle: twist, axis: wrist.reachAxis))
            }
        }
        for digit in digits {
            for (ordinal, segment) in digit.segments.enumerated() {
                let index = segment.index
                if segment.bendAxis == .zero {
                    pose.rotations[index] = simd_normalize(simd_slerp(
                        restRotations[index], pose.rotations[index], thumbSourceBlend))
                } else {
                    // Count bend about this phalanx's own hinge, not the full
                    // source rotation: gait splay must not consume curl budget.
                    let source = pose.rotations[index]
                    let relative = simd_normalize(simd_inverse(restRotations[index]) * source)
                    let sign: Float = relative.real < 0 ? -1 : 1
                    let sourceBend = 2 * atan2(sign * simd_dot(relative.imag, segment.bendAxis),
                        sign * relative.real)
                    let curl = max(targetCurl[ordinal] - max(-sourceBend, 0), 0)
                    pose.rotations[index] = simd_normalize(pose.rotations[index]
                        * simd_quatf(angle: -curl, axis: segment.bendAxis))
                }
            }
        }
    }

    private func orientation(_ chain: [Int], in pose: ReplaySkinnedAthleteMotion.Pose) -> simd_quatf {
        chain.reduce(simd_quatf(angle: 0, axis: [0, 1, 0])) {
            simd_normalize($0 * pose.rotations[$1])
        }
    }
}
