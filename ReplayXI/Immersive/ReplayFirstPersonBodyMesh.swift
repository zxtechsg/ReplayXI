import RealityKit
import simd

/// A view-only cut of the admitted skin, not a second avatar or a new rig.
/// Built once per admitted identity/detail before immersion. Retained vertices,
/// UVs and weights stay identical to the third-person body, including boots.
@MainActor
enum ReplayFirstPersonBodyMesh {
    static func make(from model: ModelEntity,
                     motion: ReplaySkinnedAthleteMotion) throws -> MeshResource? {
        guard motion.rigProfile == .tripo52, let mesh = model.model?.mesh,
              let source = mesh.contents.models.first?.parts.first,
              let indices = source.triangleIndices?.elements,
              let normals = source.normals?.elements,
              let uvs = source.textureCoordinates?.elements,
              let weights = source.jointInfluences?.influences.elements,
              let skeleton = mesh.contents.skeletons.first else { return nil }
        let positions = source.positions.elements
        guard !positions.isEmpty, positions.count <= 16_384,
              normals.count == positions.count, uvs.count == positions.count,
              weights.count == positions.count * 4,
              indices.count.isMultiple(of: 3),
              indices.allSatisfy({ Int($0) < positions.count }) else { return nil }

        // Keep the chest and arms: a waist-high cut exposes the hollow inside
        // of the shirt and shorts when looking down. Remove only the skull
        // and upper neck, then close that small opening below the eye camera.
        // Rest-space classification makes the cut identical while seeking.
        let branchRoots = ["neck", "head"]
            .compactMap { motion.semanticJointIndices[$0] }
        guard branchRoots.count == 2 else { return nil }
        let excluded = Set(motion.joints.indices.filter { index in
            var ancestor = index
            while ancestor >= 0 {
                if branchRoots.contains(ancestor) { return true }
                ancestor = motion.joints[ancestor].parentIndex
            }
            return false
        })
        let maximumY = motion.geometry.restMinY + motion.geometry.nominalHeight * 0.86
        let admitted = positions.indices.map { index in
            let excludedWeight = weights[(index * 4)..<(index * 4 + 4)]
                .reduce(Float.zero) { $0 + (excluded.contains($1.jointIndex) ? $1.weight : 0) }
            return positions[index].y <= maximumY && excludedWeight < 0.75
        }
        var remap: [Int: UInt32] = [:]
        var bodyPositions: [SIMD3<Float>] = []
        var bodyNormals: [SIMD3<Float>] = []
        var bodyUVs: [SIMD2<Float>] = []
        var bodyWeights: [MeshJointInfluence] = []
        var bodyIndices: [UInt32] = []
        var removedTrianglePositions = Set<SIMD3<Float>>()
        bodyIndices.reserveCapacity(indices.count)
        for base in stride(from: 0, to: indices.count, by: 3) {
            let a = Int(indices[base]), b = Int(indices[base + 1]), c = Int(indices[base + 2])
            guard admitted[a], admitted[b], admitted[c] else {
                removedTrianglePositions.formUnion([positions[a], positions[b], positions[c]])
                continue
            }
            for index in [a, b, c] {
                if let mapped = remap[index] {
                    bodyIndices.append(mapped)
                } else {
                    let mapped = UInt32(bodyPositions.count)
                    remap[index] = mapped
                    bodyPositions.append(positions[index])
                    bodyNormals.append(normals[index])
                    bodyUVs.append(uvs[index])
                    bodyWeights.append(contentsOf: weights[(index * 4)..<(index * 4 + 4)])
                    bodyIndices.append(mapped)
                }
            }
        }
        guard bodyIndices.count >= 300, bodyIndices.count < indices.count,
              let low = bodyPositions.map(\.y).min(),
              let high = bodyPositions.map(\.y).max(),
              low <= motion.geometry.restMinY + 0.05,
              high >= motion.geometry.restMinY + motion.geometry.nominalHeight * 0.80
        else { return nil }

        var part = MeshResource.Part(id: "first-person-body", materialIndex: source.materialIndex)
        part.positions = MeshBuffers.Positions(bodyPositions)
        part.normals = MeshBuffers.Normals(bodyNormals)
        part.textureCoordinates = MeshBuffers.TextureCoordinates(bodyUVs)
        part.triangleIndices = MeshBuffers.TriangleIndices(bodyIndices)
        part.jointInfluences = .init(influences: MeshBuffers.JointInfluences(bodyWeights), influencesPerVertex: 4)
        part.skeletonID = skeleton.id
        // A cut boundary belongs to both a kept and a removed triangle. The
        // importer duplicates positions across face-varying UV seams (the
        // low B body has no shared rim indices). Match exact source positions,
        // not indices, without welding or changing any retained skin vertex.
        let rim = bodyPositions.indices.filter { index in
            let point = bodyPositions[index]
            guard removedTrianglePositions.contains(point) else { return false }
            guard point.y > motion.geometry.restMinY + motion.geometry.nominalHeight * 0.76,
                  abs(point.x) < 0.16, abs(point.z) < 0.20 else { return false }
            return true
        }
        guard let cap = neckCap(rim: rim, positions: bodyPositions, uvs: bodyUVs,
                                weights: bodyWeights, materialIndex: source.materialIndex,
                                skeletonID: skeleton.id) else { return nil }
        var contents = MeshResource.Contents()
        contents.models = MeshModelCollection([MeshResource.Model(id: "first-person-body", parts: [part, cap])])
        contents.instances = MeshInstanceCollection([MeshResource.Instance(id: "first-person-body-instance",
            model: "first-person-body")])
        contents.skeletons = MeshSkeletonCollection([skeleton])
        return try MeshResource.generate(from: contents)
    }

    /// Small view-only closure, shared with the body skeleton. A convex neck
    /// rim avoids UV-split duplicate edges and concave fan crossings. Original
    /// body vertices remain untouched; cap edge weights match their source.
    private static func neckCap(rim: [Int], positions: [SIMD3<Float>], uvs: [SIMD2<Float>],
                                weights: [MeshJointInfluence], materialIndex: Int,
                                skeletonID: String) -> MeshResource.Part? {
        let ordered = rim.sorted {
            let a = positions[$0], b = positions[$1]
            if a.x != b.x { return a.x < b.x }
            if a.z != b.z { return a.z < b.z }
            return a.y == b.y ? $0 < $1 : a.y > b.y
        }
        var unique: [Int] = []
        for index in ordered {
            if let previous = unique.last,
               abs(positions[index].x - positions[previous].x) < 0.000_01,
               abs(positions[index].z - positions[previous].z) < 0.000_01 { continue }
            unique.append(index)
        }
        guard (3...128).contains(unique.count) else { return nil }
        func cross(_ a: Int, _ b: Int, _ c: Int) -> Float {
            let u = positions[b] - positions[a], v = positions[c] - positions[a]
            return u.x * v.z - u.z * v.x
        }
        func half(_ indices: [Int]) -> [Int] {
            var hull: [Int] = []
            for index in indices {
                while hull.count >= 2 && cross(hull[hull.count - 2], hull[hull.count - 1], index) <= 0 {
                    hull.removeLast()
                }
                hull.append(index)
            }
            return hull
        }
        let hull = Array(half(unique).dropLast()) + Array(half(Array(unique.reversed())).dropLast())
        guard hull.count >= 3 else { return nil }
        let centre = hull.reduce(SIMD3<Float>.zero) { $0 + positions[$1] } / Float(hull.count)
        let centreIndex = UInt32(hull.count)
        var capPositions = hull.map { positions[$0] }
        capPositions.append(centre)
        var capWeights = hull.flatMap { Array(weights[($0 * 4)..<($0 * 4 + 4)]) }
        var totals: [Int: Float] = [:]
        for weight in capWeights { totals[weight.jointIndex, default: 0] += weight.weight }
        let strongest = totals.sorted {
            $0.value == $1.value ? $0.key < $1.key : $0.value > $1.value
        }.prefix(4)
        let total = strongest.reduce(Float.zero) { $0 + $1.value }
        guard total.isFinite && total > 0 else { return nil }
        var centreWeights = strongest.map { MeshJointInfluence(jointIndex: $0.key, weight: $0.value / total) }
        while centreWeights.count < 4 { centreWeights.append(.init(jointIndex: 0, weight: 0)) }
        capWeights.append(contentsOf: centreWeights)
        var triangles: [UInt32] = []
        for index in hull.indices {
            // X/Z counter-clockwise winding points down; reverse for +Y.
            triangles += [centreIndex, UInt32((index + 1) % hull.count), UInt32(index)]
        }
        // Sample one upper-neck texel instead of stretching unrelated UV
        // islands across the small closure. It uses the existing kit atlas.
        let colourSample = hull.max { positions[$0].y < positions[$1].y }!
        var cap = MeshResource.Part(id: "first-person-neck-cap", materialIndex: materialIndex)
        cap.positions = MeshBuffers.Positions(capPositions)
        cap.normals = MeshBuffers.Normals(Array(repeating: [0, 1, 0], count: capPositions.count))
        cap.textureCoordinates = MeshBuffers.TextureCoordinates(Array(repeating: uvs[colourSample], count: capPositions.count))
        cap.triangleIndices = MeshBuffers.TriangleIndices(triangles)
        cap.jointInfluences = .init(influences: MeshBuffers.JointInfluences(capWeights), influencesPerVertex: 4)
        cap.skeletonID = skeletonID
        return cap
    }
}
