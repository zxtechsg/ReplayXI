import RealityKit
import UIKit

/// Deterministic low-cost stand-in for a reconstructed match environment.
///
/// This is deliberately named and surfaced as a preview: generated pixels do
/// not become tactical geometry. A hash-locked LingBot-Map/point-cloud import
/// can replace these four shared meshes after it passes the world-manifest
/// gate, while player and ball telemetry remain authoritative.
enum ReplayWorldPreviewFactory {
    static let rootName = "synthetic-world-reconstruction-preview"
    static let splatCount = 640
    static let materialGroupCount = 4
    static let estimatedTriangleCount = splatCount * 4
    static let estimatedVertexCount = splatCount * 12

    static func make() -> Entity {
        let root = Entity()
        root.name = rootName

        let colors = [
            UIColor(red: 0.11, green: 0.86, blue: 0.69, alpha: 1),
            UIColor(red: 0.15, green: 0.42, blue: 0.78, alpha: 1),
            UIColor(red: 0.91, green: 0.28, blue: 0.22, alpha: 1),
            UIColor(red: 0.80, green: 0.88, blue: 0.84, alpha: 1),
        ]
        let meshes = makeSurfelMeshes()
        for index in meshes.indices {
            let model = ModelEntity(
                mesh: meshes[index],
                materials: [
                    UnlitMaterial(
                        color: colors[index % colors.count],
                        applyPostProcessToneMap: false
                    )
                ]
            )
            model.name = "world-preview-surfels-\(index)"
            root.addChild(model)
        }
        return root
    }

    private static func makeSurfelMeshes() -> [MeshResource] {
        var builders = Array(
            repeating: SurfelMeshBuilder(),
            count: materialGroupCount
        )
        var random = DeterministicWorldRandom(seed: 0x5245_504C_4159_5849)

        for index in 0..<splatCount {
            let side = index % 4
            let horizontal = random.unit()
            let depth = random.unit()
            let heightBias = pow(random.unit(), 0.72)
            let y = 0.35 + (heightBias * 10.5)
            let centre: SIMD3<Float>
            switch side {
            case 0:
                centre = [38 + (depth * 10), y, -52 + (horizontal * 104)]
            case 1:
                centre = [-38 - (depth * 10), y, -52 + (horizontal * 104)]
            case 2:
                centre = [-34 + (horizontal * 68), y, 57 + (depth * 9)]
            default:
                centre = [-34 + (horizontal * 68), y, -57 - (depth * 9)]
            }
            let size = 0.045 + (random.unit() * 0.085) + (y * 0.0018)
            let group = Int(random.next() % UInt64(materialGroupCount))
            builders[group].appendTetrahedron(centre: centre, radius: size)
        }

        return builders.enumerated().compactMap { index, builder in
            builder.makeMesh(named: "replay-world-preview-\(index)")
        }
    }
}

private struct DeterministicWorldRandom {
    private var state: UInt64

    init(seed: UInt64) {
        state = seed
    }

    mutating func next() -> UInt64 {
        state = state &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
        return state
    }

    mutating func unit() -> Float {
        Float(next() >> 40) / Float(1 << 24)
    }
}

private struct SurfelMeshBuilder {
    private var positions: [SIMD3<Float>] = []
    private var normals: [SIMD3<Float>] = []
    private var indices: [UInt32] = []

    mutating func appendTetrahedron(centre: SIMD3<Float>, radius: Float) {
        let vertices = [
            centre + SIMD3<Float>(0, radius, 0),
            centre + SIMD3<Float>(-radius, -radius * 0.55, radius * 0.80),
            centre + SIMD3<Float>(radius, -radius * 0.55, radius * 0.80),
            centre + SIMD3<Float>(0, -radius * 0.55, -radius),
        ]
        for (a, b, c) in [(0, 2, 1), (0, 3, 2), (0, 1, 3), (1, 2, 3)] {
            let normal = simd_normalize(
                simd_cross(vertices[b] - vertices[a], vertices[c] - vertices[a])
            )
            let base = UInt32(positions.count)
            positions.append(contentsOf: [vertices[a], vertices[b], vertices[c]])
            normals.append(contentsOf: [normal, normal, normal])
            indices.append(contentsOf: [base, base + 1, base + 2])
        }
    }

    func makeMesh(named name: String) -> MeshResource? {
        guard !positions.isEmpty else { return nil }
        var descriptor = MeshDescriptor(name: name)
        descriptor.positions = MeshBuffers.Positions(positions)
        descriptor.normals = MeshBuffers.Normals(normals)
        descriptor.primitives = .triangles(indices)
        return try? MeshResource.generate(from: [descriptor])
    }
}
