import RealityKit
import simd

/// Shared low-draw geometry for the pitch and coach overlays.
///
/// RealityKit counts each independently rendered `ModelEntity` against the
/// scene budget even when every entity shares one box mesh and material. A
/// football pitch contains dozens of short line segments, so batching those
/// segments into one immutable mesh removes a large fixed cost from every
/// headset without changing their appearance or data contract.
@MainActor
enum ReplayPitchMeshLibrary {
    static let markingsAndGoals: MeshResource = makeMarkingsAndGoals()
    static let annotationSpaceRing: MeshResource = makeAnnotationSpaceRing()

    private static func makeMarkingsAndGoals() -> MeshResource {
        var builder = SegmentMeshBuilder()
        let halfWidth: Float = 34
        let halfLength: Float = 52.5
        let lineY: Float = 0.016

        builder.appendSegment(from: [-halfWidth, lineY, -halfLength], to: [halfWidth, lineY, -halfLength], width: 0.11)
        builder.appendSegment(from: [halfWidth, lineY, -halfLength], to: [halfWidth, lineY, halfLength], width: 0.11)
        builder.appendSegment(from: [halfWidth, lineY, halfLength], to: [-halfWidth, lineY, halfLength], width: 0.11)
        builder.appendSegment(from: [-halfWidth, lineY, halfLength], to: [-halfWidth, lineY, -halfLength], width: 0.11)
        builder.appendSegment(from: [-halfWidth, lineY, 0], to: [halfWidth, lineY, 0], width: 0.09)

        let circleRadius: Float = 9.15
        let circleSegments = 48
        for index in 0..<circleSegments {
            let startAngle = (Float(index) / Float(circleSegments)) * 2 * .pi
            let endAngle = (Float(index + 1) / Float(circleSegments)) * 2 * .pi
            builder.appendSegment(
                from: [sin(startAngle) * circleRadius, lineY, cos(startAngle) * circleRadius],
                to: [sin(endAngle) * circleRadius, lineY, cos(endAngle) * circleRadius],
                width: 0.075
            )
        }

        for (goalLine, direction) in [(Float(-52.5), Float(1)), (Float(52.5), Float(-1))] {
            let edgeZ = goalLine + (direction * 16.5)
            builder.appendSegment(from: [-20.16, lineY, goalLine], to: [-20.16, lineY, edgeZ], width: 0.09)
            builder.appendSegment(from: [20.16, lineY, goalLine], to: [20.16, lineY, edgeZ], width: 0.09)
            builder.appendSegment(from: [-20.16, lineY, edgeZ], to: [20.16, lineY, edgeZ], width: 0.09)
        }

        // Goal frames use the same ivory material, so they can share this draw
        // with the flat markings despite their vertical geometry.
        for goalZ in [Float(-53.15), Float(53.15)] {
            builder.appendSegment(from: [-3.66, 0, goalZ], to: [-3.66, 2.44, goalZ], width: 0.09)
            builder.appendSegment(from: [3.66, 0, goalZ], to: [3.66, 2.44, goalZ], width: 0.09)
            builder.appendSegment(from: [-3.66, 2.44, goalZ], to: [3.66, 2.44, goalZ], width: 0.09)
        }

        return builder.makeMesh(named: "replay-pitch-markings")
            ?? .generateBox(size: [68, 0.02, 0.10])
    }

    /// One dashed annulus replaces twenty independently rendered segment
    /// entities. The mesh is unit radius; callers scale X/Z by the requested
    /// coaching-zone radius without generating geometry during playback.
    private static func makeAnnotationSpaceRing() -> MeshResource {
        var builder = SegmentMeshBuilder()
        let segmentCount = 20
        let radius: Float = 1
        let visibleArcFraction: Float = 0.72
        let arcLength = (2 * Float.pi * radius / Float(segmentCount)) * visibleArcFraction
        for index in 0..<segmentCount {
            let angle = (Float(index) / Float(segmentCount)) * 2 * .pi
            let tangent = SIMD3<Float>(cos(angle), 0, -sin(angle))
            let centre = SIMD3<Float>(sin(angle) * radius, 0, cos(angle) * radius)
            builder.appendSegment(
                from: centre - (tangent * arcLength * 0.5),
                to: centre + (tangent * arcLength * 0.5),
                width: 0.115,
                thickness: 0.034
            )
        }
        return builder.makeMesh(named: "replay-annotation-space-ring")
            ?? .generateCylinder(height: 0.034, radius: 1)
    }

    private struct SegmentMeshBuilder {
        var positions: [SIMD3<Float>] = []
        var normals: [SIMD3<Float>] = []
        var indices: [UInt32] = []

        mutating func appendSegment(
            from start: SIMD3<Float>,
            to end: SIMD3<Float>,
            width: Float,
            thickness: Float? = nil
        ) {
            let vector = end - start
            let length = simd_length(vector)
            guard length.isFinite, length > 0.000_1, width.isFinite, width > 0 else { return }

            let axis = vector / length
            let reference: SIMD3<Float> = abs(simd_dot(axis, [0, 1, 0])) > 0.92
                ? [1, 0, 0]
                : [0, 1, 0]
            let side = simd_normalize(simd_cross(axis, reference))
            let normal = simd_normalize(simd_cross(side, axis))
            let halfWidth = width * 0.5
            let halfThickness = (thickness ?? width) * 0.5
            let centre = (start + end) * 0.5
            let along = axis * (length * 0.5)
            let across = side * halfWidth
            let vertical = normal * halfThickness

            let corners = [
                centre - along - across - vertical,
                centre + along - across - vertical,
                centre + along + across - vertical,
                centre - along + across - vertical,
                centre - along - across + vertical,
                centre + along - across + vertical,
                centre + along + across + vertical,
                centre - along + across + vertical,
            ]
            let faces: [(Int, Int, Int, Int, SIMD3<Float>)] = [
                (0, 1, 2, 3, -normal),
                (4, 7, 6, 5, normal),
                (0, 4, 5, 1, -side),
                (3, 2, 6, 7, side),
                (0, 3, 7, 4, -axis),
                (1, 5, 6, 2, axis),
            ]
            for face in faces {
                let base = UInt32(positions.count)
                positions.append(contentsOf: [
                    corners[face.0], corners[face.1], corners[face.2], corners[face.3],
                ])
                normals.append(contentsOf: Array(repeating: face.4, count: 4))
                indices.append(contentsOf: [base, base + 1, base + 2, base, base + 2, base + 3])
            }
        }

        func makeMesh(named name: String) -> MeshResource? {
            guard !positions.isEmpty, indices.count.isMultiple(of: 3) else { return nil }
            var descriptor = MeshDescriptor(name: name)
            descriptor.positions = MeshBuffers.Positions(positions)
            descriptor.normals = MeshBuffers.Normals(normals)
            descriptor.primitives = .triangles(indices)
            return try? MeshResource.generate(from: [descriptor])
        }
    }
}
