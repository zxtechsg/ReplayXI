import RealityKit
import simd

/// Two real boot vertices admitted from the imported skin on its cold path.
/// Toe descendants return to rest during an explicit contact, so each selected
/// marker remains rigid relative to its ankle. No per-frame mesh inspection.
struct ReplaySkinnedAthleteBootMarkers: Sendable {
    struct Marker: Sendable {
        let ankleIndex: Int
        let ankleLocalPosition: SIMD3<Float>
        let restModelPosition: SIMD3<Float>
        let toeDescendants: [Int]
    }

    let markers: [Marker]

    @MainActor
    init?(model: ModelEntity, motion: ReplaySkinnedAthleteMotion) {
        guard let component = model.model,
              let skeleton = component.mesh.contents.skeletons.first,
              skeleton.joints.count == motion.joints.count else { return nil }
        let parts = component.mesh.contents.models.flatMap { Array($0.parts) }
        guard parts.reduce(0, { $0 + $1.positions.count }) <= ReplaySkinnedAthleteProvider.skinVertices
        else { return nil }
        var result: [Marker] = []
        for name in ["left", "right"] {
            guard let contact = motion.footContacts[name] else { return nil }
            let ankle = contact.footJointIndex
            let descendants = motion.joints.indices.filter { index in
                var cursor = index
                while cursor >= 0 {
                    if cursor == contact.toeJointIndex { return true }
                    cursor = motion.joints[cursor].parentIndex
                }
                return false
            }
            let allowed = Set(descendants + [ankle])
            let ankleRest = motion.restPose.modelSpaceTransforms[ankle]
            var selected: SIMD3<Float>?
            for part in parts {
                guard let joints = part.jointInfluences, !part.positions.elements.isEmpty else { continue }
                let influences = joints.influences.elements
                let stride = influences.count / part.positions.count
                guard (1...8).contains(stride), influences.count == stride * part.positions.count else { return nil }
                for (index, point) in part.positions.elements.enumerated() {
                    var ownership: Float = 0
                    var rest = SIMD4<Float>.zero
                    for influence in influences[(index * stride)..<((index + 1) * stride)] {
                        guard motion.joints.indices.contains(influence.jointIndex),
                              influence.weight.isFinite, influence.weight >= 0 else { return nil }
                        if allowed.contains(influence.jointIndex) { ownership += influence.weight }
                        rest += motion.restPose.modelSpaceTransforms[influence.jointIndex]
                            * skeleton.joints[influence.jointIndex].inverseBindPoseMatrix
                            * SIMD4(point, 1) * influence.weight
                    }
                    guard ownership > 0.999, abs(rest.w - 1) < 0.001,
                          rest.y < ankleRest.columns.3.y + 0.04 else { continue }
                    let candidate = SIMD3<Float>(rest.x, rest.y, rest.z)
                    guard candidate.x.isFinite, candidate.y.isFinite, candidate.z.isFinite else { return nil }
                    if selected == nil || candidate.z > selected!.z { selected = candidate }
                }
            }
            guard let selected else { return nil }
            let local = ankleRest.inverse * SIMD4(selected, 1)
            result.append(Marker(ankleIndex: ankle, ankleLocalPosition: [local.x, local.y, local.z],
                                 restModelPosition: selected, toeDescendants: descendants))
        }
        markers = result
    }

    func marker(for ankle: Int) -> Marker? { markers.first { $0.ankleIndex == ankle } }
}
