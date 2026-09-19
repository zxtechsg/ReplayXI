import RealityKit
import simd

/// One bounded tube mesh per curve, not a draw call per segment. Entity-local
/// keys avoid rebuilding unchanged geometry during playback or selection pulse.
@MainActor
enum AnnotationArcMesh {
    private static let sides = 6
    // Every arc uses the same topology and circular section. Keep these
    // immutable buffers out of active keyframe-morph and scrub work.
    private static let crossSection: [SIMD2<Float>] = (0..<sides).map { corner in
        let angle = Float(corner) * 2 * .pi / Float(sides)
        return [cos(angle), sin(angle)]
    }
    private static let triangleIndices: [UInt32] = {
        let steps = CoachMarkCurve.segmentCount
        var indices: [UInt32] = []
        indices.reserveCapacity(steps * sides * 6 + (sides - 2) * 6)
        for ring in 0..<steps {
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
        return indices
    }()

    #if DEBUG
    struct WorkCounters: Equatable {
        var controlPointEvaluations = 0
        var meshBuilds = 0
        var reusedMeshUpdates = 0
        var reusedMeshTransformWrites = 0
    }
    private(set) static var work = WorkCounters()
    static func resetWorkForTesting() { work = WorkCounters() }
    #endif

    private struct Key: Equatable, Sendable {
        let start: PitchPoint
        let end: PitchPoint
        let startY: Float
        let endY: Float
        let curve: CoachMarkCurve
        let radius: Float
        let baseY: Float
        let control: SIMD3<Float>

        init(mark: CoachMark, radius: Float, baseY: Float) {
            start = mark.start
            end = mark.end
            startY = mark.resolvedStartElevation
            endY = mark.resolvedEndElevation
            curve = mark.resolvedCurve
            self.radius = radius
            self.baseY = baseY
            control = curve.controlPoint(for: mark)
        }

        /// Same quadratic and pitch-rounding clamp as CoachMarkCurve.point,
        /// with its roll/bounds work already resolved once for this mesh.
        func point(at t: Float, baseY: Float = 0) -> SIMD3<Float> {
            let a = SIMD3<Float>(start.x, startY, start.z)
            let b = SIMD3<Float>(end.x, endY, end.z)
            let point = (1 - t) * (1 - t) * a + 2 * (1 - t) * t * control + t * t * b
            return [min(max(point.x, -34), 34), point.y + baseY,
                    min(max(point.z, -52.5), 52.5)]
        }

        /// Player tracking and keyframed 3D translations need no new GPU mesh.
        /// Comparing all three control points also catches pitch/floor/ceiling
        /// clipping, which changes the shape rather than simply translating it.
        func translation(to other: Key) -> SIMD3<Float>? {
            guard radius == other.radius, baseY == other.baseY else { return nil }
            let shift = SIMD3<Float>(other.start.x - start.x, other.startY - startY,
                                     other.start.z - start.z)
            let endShift = SIMD3<Float>(other.end.x - end.x, other.endY - endY,
                                        other.end.z - end.z)
            let controlShift = other.control - control
            if curve != other.curve {
                // Clipping can make different bend/lift/roll values render
                // exactly the same quadratic. Reuse only exact resolved
                // translations here: tiny real curve edits must still rebuild.
                guard endShift == shift, controlShift == shift else { return nil }
                return shift
            }
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
        #if DEBUG
        work.controlPointEvaluations &+= 1
        #endif
        let key = Key(mark: mark, radius: radius, baseY: baseY)
        if let original = entity.components[CachedGeometry.self]?.key,
           let shift = original.translation(to: key) {
            #if DEBUG
            work.reusedMeshUpdates &+= 1
            #endif
            let transform = Transform(translation: shift)
            if entity.transform != transform {
                entity.transform = transform
                #if DEBUG
                work.reusedMeshTransformWrites &+= 1
                #endif
            }
            return true
        }
        guard let mesh = mesh(for: key), var model = entity.model else { return false }
        model.mesh = mesh
        entity.model = model
        entity.transform = .identity
        entity.components.set(CachedGeometry(key: key))
        return true
    }

    static func mesh(for mark: CoachMark, radius: Float = 0.075,
                     baseY: Float = 0.10) -> MeshResource? {
        #if DEBUG
        work.controlPointEvaluations &+= 1
        #endif
        return mesh(for: Key(mark: mark, radius: radius, baseY: baseY))
    }

    private static func mesh(for key: Key) -> MeshResource? {
        #if DEBUG
        work.meshBuilds &+= 1
        #endif
        let steps = CoachMarkCurve.segmentCount
        var positions: [SIMD3<Float>] = []
        var normals: [SIMD3<Float>] = []
        positions.reserveCapacity((steps + 1) * sides)
        normals.reserveCapacity((steps + 1) * sides)
        let start = key.point(at: 0)
        let end = key.point(at: 1)
        let plane = simd_cross(key.control - start, end - start)
        let stablePlaneNormal: SIMD3<Float>? = simd_length_squared(plane) > 0.000_001
            ? simd_normalize(plane) : nil
        for ring in 0...steps {
            let t = Float(ring) / Float(steps)
            let center = key.point(at: t, baseY: key.baseY)
            let before = key.point(at: max(0, t - 0.001))
            let after = key.point(at: min(1, t + 0.001))
            let delta = after - before
            let tangent = simd_length_squared(delta) > 0.0000001 ? simd_normalize(delta) : SIMD3<Float>(0, 0, 1)
            let reference = abs(tangent.y) > 0.95 ? SIMD3<Float>(1, 0, 0) : SIMD3<Float>(0, 1, 0)
            // Quadratics are planar. A shared binormal avoids the old ring
            // frame flip when an angled 3D arc crosses the vertical threshold.
            let side = stablePlaneNormal ?? simd_normalize(simd_cross(reference, tangent))
            let up = simd_normalize(simd_cross(tangent, side))
            for section in crossSection {
                let normal = side * section.x + up * section.y
                positions.append(center + normal * key.radius)
                normals.append(normal)
            }
        }
        var descriptor = MeshDescriptor(name: "coach-arc-32x6")
        descriptor.positions = MeshBuffers.Positions(positions)
        descriptor.normals = MeshBuffers.Normals(normals)
        descriptor.primitives = .triangles(triangleIndices)
        return try? MeshResource.generate(from: [descriptor])
    }
}
