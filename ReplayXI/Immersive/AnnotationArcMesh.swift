import RealityKit
import simd

/// One bounded tube mesh per curve, not a draw call per segment. Entity-local
/// keys avoid rebuilding unchanged geometry during playback or selection pulse.
@MainActor
enum AnnotationArcMesh {
    private struct Key: Equatable, Sendable {
        let start: PitchPoint
        let end: PitchPoint
        let startY: Float
        let endY: Float
        let curve: CoachMarkCurve
        let radius: Float
        let baseY: Float
        let control: SIMD3<Float>

        /// Player tracking and keyframed 3D translations need no new GPU mesh.
        /// Comparing all three control points also catches pitch/floor/ceiling
        /// clipping, which changes the shape rather than simply translating it.
        func translation(to other: Key) -> SIMD3<Float>? {
            guard curve == other.curve, radius == other.radius, baseY == other.baseY else { return nil }
            let shift = SIMD3<Float>(other.start.x - start.x, other.startY - startY,
                                     other.start.z - start.z)
            let endShift = SIMD3<Float>(other.end.x - end.x, other.endY - endY,
                                        other.end.z - end.z)
            let controlShift = other.control - control
            // Subtracting pitch-space floats can differ by a few micrometres.
            let toleranceSquared: Float = 0.0001 * 0.0001
            guard simd_length_squared(endShift - shift) <= toleranceSquared,
                  simd_length_squared(controlShift - shift) <= toleranceSquared else { return nil }
            return shift
        }
    }
    private struct CachedGeometry: Component {
        let key: Key
    }

    static func reset(_ entity: ModelEntity, mesh: MeshResource) {
        guard entity.components[CachedGeometry.self] != nil, var model = entity.model else { return }
        entity.components.remove(CachedGeometry.self)
        model.mesh = mesh
        entity.model = model
        entity.transform = .identity
    }

    @discardableResult
    static func update(_ entity: ModelEntity, mark: CoachMark,
                       radius: Float = 0.075, baseY: Float = 0.10) -> Bool {
        let key = Key(start: mark.start, end: mark.end,
                      startY: mark.resolvedStartElevation, endY: mark.resolvedEndElevation,
                      curve: mark.resolvedCurve, radius: radius, baseY: baseY,
                      control: mark.resolvedCurve.controlPoint(for: mark))
        if let original = entity.components[CachedGeometry.self]?.key,
           let shift = original.translation(to: key) {
            entity.transform = Transform(translation: shift)
            return true
        }
        guard let mesh = mesh(for: mark, radius: radius, baseY: baseY), var model = entity.model else { return false }
        model.mesh = mesh
        entity.model = model
        entity.transform = .identity
        entity.components.set(CachedGeometry(key: key))
        return true
    }

    static func mesh(for mark: CoachMark, radius: Float = 0.075,
                     baseY: Float = 0.10) -> MeshResource? {
        let steps = CoachMarkCurve.segmentCount
        let sides = 6
        var positions: [SIMD3<Float>] = []
        var normals: [SIMD3<Float>] = []
        var indices: [UInt32] = []
        positions.reserveCapacity((steps + 1) * sides)
        normals.reserveCapacity((steps + 1) * sides)
        indices.reserveCapacity(steps * sides * 6)
        let curve = mark.resolvedCurve
        let start = curve.point(at: 0, for: mark)
        let end = curve.point(at: 1, for: mark)
        let plane = simd_cross(curve.controlPoint(for: mark) - start, end - start)
        let stablePlaneNormal: SIMD3<Float>? = simd_length_squared(plane) > 0.000_001
            ? simd_normalize(plane) : nil
        for ring in 0...steps {
            let t = Float(ring) / Float(steps)
            let center = curve.point(at: t, for: mark, baseY: baseY)
            let before = curve.point(at: max(0, t - 0.001), for: mark)
            let after = curve.point(at: min(1, t + 0.001), for: mark)
            let delta = after - before
            let tangent = simd_length_squared(delta) > 0.0000001 ? simd_normalize(delta) : SIMD3<Float>(0, 0, 1)
            let reference = abs(tangent.y) > 0.95 ? SIMD3<Float>(1, 0, 0) : SIMD3<Float>(0, 1, 0)
            // Quadratics are planar. A shared binormal avoids the old ring
            // frame flip when an angled 3D arc crosses the vertical threshold.
            let side = stablePlaneNormal ?? simd_normalize(simd_cross(reference, tangent))
            let up = simd_normalize(simd_cross(tangent, side))
            for corner in 0..<sides {
                let angle = Float(corner) * 2 * .pi / Float(sides)
                let normal = side * cos(angle) + up * sin(angle)
                positions.append(center + normal * radius)
                normals.append(normal)
            }
            guard ring < steps else { continue }
            for corner in 0..<sides {
                let a = UInt32(ring * sides + corner)
                let b = UInt32(ring * sides + (corner + 1) % sides)
                let c = a + UInt32(sides)
                let d = b + UInt32(sides)
                indices.append(contentsOf: [a, b, c, b, d, c])
            }
        }
        let last = UInt32(steps * sides)
        for corner in 1..<(sides - 1) {
            indices.append(contentsOf: [0, UInt32(corner + 1), UInt32(corner),
                                       last, last + UInt32(corner), last + UInt32(corner + 1)])
        }
        var descriptor = MeshDescriptor(name: "coach-arc-32x6")
        descriptor.positions = MeshBuffers.Positions(positions)
        descriptor.normals = MeshBuffers.Normals(normals)
        descriptor.primitives = .triangles(indices)
        return try? MeshResource.generate(from: [descriptor])
    }
}
