import Foundation
import simd

/// Softens the fixed Tripo grip while keeping the admitted source clips and
/// every arm, contact, and root joint unchanged. Constructed once per player.
struct ReplayAthleteHandPose {
    private struct Digit {
        let segments: [Segment]
        let sourceWeight: Float
    }

    private struct Segment {
        let index: Int
        let bendAxis: SIMD3<Float>
    }

    private let wrists: [Int]
    private let digits: [Digit]
    private let restRotations: [simd_quatf]

    init?(motion: ReplaySkinnedAthleteMotion) {
        guard motion.rigProfile == .tripo52 else { return nil }
        let lookup = Dictionary(uniqueKeysWithValues: motion.joints.enumerated().map {
            ($0.element.sourceName, $0.offset)
        })
        var wrists: [Int] = []
        var digits: [Digit] = []
        let rest = motion.restPose.modelSpaceTransforms
        func position(_ index: Int) -> SIMD3<Float> {
            let column = rest[index].columns.3
            return [column.x, column.y, column.z]
        }
        for side in ["Left", "Right"] {
            guard let wrist = lookup["mixamorig:\(side)Hand"] else { return nil }
            wrists.append(wrist)
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
            for (name, weight) in [
                ("Index", Float(0.43)), ("Middle", 0.47),
                ("Ring", 0.51), ("Pinky", 0.55), ("Thumb", 0.22)
            ] {
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
                digits.append(Digit(segments: segments, sourceWeight: weight))
            }
        }
        self.wrists = wrists
        self.digits = digits
        restRotations = motion.restPose.rotations
    }

    func apply(to pose: inout ReplaySkinnedAthleteMotion.Pose, preserveWrist: Bool = false) {
        guard pose.rotations.count == restRotations.count else { return }
        if !preserveWrist {
            for wrist in wrists {
                let rest = restRotations[wrist]
                let source = pose.rotations[wrist]
                // Source clips hold a roughly 75° wrist twist. Limit its full
                // rest-relative rotation without changing the forearm or hand pivot.
                let dot = min(abs(simd_dot(rest.vector, source.vector)), 1)
                let angle = 2 * acos(dot)
                let limit: Float = 50 * .pi / 180
                if angle > limit {
                    pose.rotations[wrist] = simd_normalize(simd_slerp(rest, source, limit / angle))
                }
            }
        }
        for digit in digits {
            for segment in digit.segments {
                let index = segment.index
                if segment.bendAxis == .zero {
                    pose.rotations[index] = simd_normalize(simd_slerp(
                        restRotations[index], pose.rotations[index], digit.sourceWeight))
                } else {
                    let source = pose.rotations[index]
                    let dot = min(abs(simd_dot(restRotations[index].vector, source.vector)), 1)
                    let sourceAngle = 2 * acos(dot)
                    let bend = min(sourceAngle * digit.sourceWeight, 0.43)
                    pose.rotations[index] = simd_normalize(restRotations[index]
                        * simd_quatf(angle: bend, axis: segment.bendAxis))
                }
            }
        }
    }
}
