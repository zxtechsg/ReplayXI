import Foundation
import simd

/// Pure placement from measured horizontal plane geometry. The complete board
/// footprint must fit the observed triangle mesh, including holes and edges.
enum ReplayPitchSurfaceSnap {
    enum Kind: String, Sendable { case floor = "Floor", table = "Table", surface = "Surface" }

    struct Triangle: Equatable, Sendable {
        let a: SIMD2<Float>
        let b: SIMD2<Float>
        let c: SIMD2<Float>
    }

    struct Surface: Identifiable, Equatable, Sendable {
        let id: UUID
        let kind: Kind
        let worldFromExtent: simd_float4x4
        let extent: SIMD2<Float>
        let triangles: [Triangle]

        var worldPosition: SIMD3<Float> {
            let p = worldFromExtent.columns.3
            return [p.x, p.y, p.z]
        }
    }

    struct Placement: Equatable, Sendable {
        let surfaceID: UUID
        let surfaceKind: Kind
        let surfaceWorldPosition: SIMD3<Float>
        /// Yaw-only transform: the pitch remains level even with noisy planes.
        let worldTransform: simd_float4x4
        /// Relative to the supplied footprint; never grows the current board.
        let scaleFactor: Float
    }

    /// Actual board rim: 68x105m pitch plus frame, at the default table scale.
    nonisolated static let defaultFootprint = SIMD2<Float>(73.2, 112.2) * 0.0255
    nonisolated static let defaultBottomOffset: Float = 0.56 * 0.0255

    static func placement(on surfaces: [Surface], near position: SIMD3<Float>, yawRadians: Float,
                          footprint: SIMD2<Float> = defaultFootprint,
                          bottomOffset: Float = defaultBottomOffset,
                          preferredSurfaceID: UUID? = nil,
                          maximumDistance: Float = 3, minimumScaleFactor: Float = 0.25) -> Placement? {
        guard finite(position), yawRadians.isFinite, footprint.x.isFinite, footprint.y.isFinite,
              footprint.x > 0.05, footprint.y > 0.05, bottomOffset.isFinite, bottomOffset >= 0,
              maximumDistance.isFinite, maximumDistance > 0,
              minimumScaleFactor.isFinite, minimumScaleFactor > 0, minimumScaleFactor <= 1 else { return nil }
        var result: Placement?, bestDistance = Float.infinity
        for surface in surfaces.sorted(by: { $0.id.uuidString < $1.id.uuidString }) {
            if let preferredSurfaceID, surface.id != preferredSurfaceID { continue }
            guard valid(surface) else { continue }
            let local4 = surface.worldFromExtent.inverse * SIMD4<Float>(position, 1)
            let desired = SIMD2<Float>(local4.x, local4.z)
            let axis = surface.worldFromExtent.columns.2
            let relativeYaw = yawRadians - atan2(axis.x, axis.z)
            let cosine = cos(relativeYaw), sine = sin(relativeYaw)
            let margin: Float = 0.015
            let projected = SIMD2<Float>(abs(cosine) * footprint.x + abs(sine) * footprint.y,
                                         abs(sine) * footprint.x + abs(cosine) * footprint.y)
            var factor = min(1, (surface.extent.x - 2 * margin) / projected.x,
                             (surface.extent.y - 2 * margin) / projected.y)
            func smaller(_ factor: Float) -> Float {
                factor <= minimumScaleFactor ? 0 : max(minimumScaleFactor, factor * 0.94)
            }
            // Descending fits avoid shrinking an already fitting board. Every
            // accepted size is checked against measured mesh area, not its AABB.
            while factor >= minimumScaleFactor {
                let half = footprint * factor * 0.5 + SIMD2<Float>(repeating: margin)
                let bound = SIMD2<Float>(abs(cosine) * half.x + abs(sine) * half.y,
                                         abs(sine) * half.x + abs(cosine) * half.y)
                let room = surface.extent * 0.5 - bound
                guard room.x >= -0.00001, room.y >= -0.00001 else { factor = smaller(factor); continue }
                let clamped = simd_clamp(desired, -simd_max(room, .zero), simd_max(room, .zero))
                let centres = [clamped, SIMD2<Float>.zero]
                var fitted = false
                for centre in centres {
                    guard covers(half: half, centre: centre, cosine: cosine, sine: sine,
                                 triangles: surface.triangles) else { continue }
                    let point4 = surface.worldFromExtent * SIMD4<Float>(centre.x, 0, centre.y, 1)
                    let point = SIMD3<Float>(point4.x, point4.y, point4.z)
                    let distance = simd_distance(point, position)
                    guard distance <= maximumDistance else { continue }
                    fitted = true
                    if distance < bestDistance {
                        var transform = simd_float4x4(simd_quatf(angle: yawRadians, axis: [0, 1, 0]))
                        transform.columns.3 = SIMD4(point + SIMD3<Float>(0, bottomOffset * factor + 0.002, 0), 1)
                        result = .init(surfaceID: surface.id, surfaceKind: surface.kind,
                            surfaceWorldPosition: point, worldTransform: transform, scaleFactor: factor)
                        bestDistance = distance
                    }
                }
                if fitted { break }
                factor = smaller(factor)
            }
        }
        return result
    }

    private static func valid(_ surface: Surface) -> Bool {
        guard surface.extent.x.isFinite, surface.extent.y.isFinite,
              surface.extent.x > 0.05, surface.extent.y > 0.05,
              surface.extent.x < 100, surface.extent.y < 100,
              !surface.triangles.isEmpty, surface.triangles.count <= 65_536 else { return false }
        for column in 0..<4 {
            let value = surface.worldFromExtent[column]
            guard value.x.isFinite, value.y.isFinite, value.z.isFinite, value.w.isFinite else { return false }
        }
        let up = surface.worldFromExtent.columns.1
        // ARKit classifies a horizontal plane, but reject a corrupt/slanted
        // matrix instead of claiming a level board rests on a vertical surface.
        guard up.y > 0.996, abs(up.x) < 0.087, abs(up.z) < 0.087,
              abs(simd_determinant(surface.worldFromExtent) - 1) < 0.01 else { return false }
        return surface.triangles.allSatisfy {
            [$0.a, $0.b, $0.c].allSatisfy { $0.x.isFinite && $0.y.isFinite }
        }
    }

    private static func covers(half: SIMD2<Float>, centre: SIMD2<Float>, cosine: Float, sine: Float,
                               triangles: [Triangle]) -> Bool {
        func local(_ p: SIMD2<Float>) -> SIMD2<Float> {
            let d = p - centre
            return [cosine * d.x - sine * d.y, sine * d.x + cosine * d.y]
        }
        var area: Float = 0
        for triangle in triangles {
            var polygon = [local(triangle.a), local(triangle.b), local(triangle.c)]
            for axis in 0..<2 {
                polygon = clip(polygon, axis: axis, limit: half[axis], upper: true)
                polygon = clip(polygon, axis: axis, limit: -half[axis], upper: false)
            }
            guard polygon.count >= 3 else { continue }
            var twiceArea: Float = 0
            for index in polygon.indices {
                let a = polygon[index], b = polygon[(index + 1) % polygon.count]
                twiceArea += a.x * b.y - a.y * b.x
            }
            area += abs(twiceArea) * 0.5
        }
        let required = 4 * half.x * half.y
        return abs(area - required) <= max(0.00001, required * 0.0001)
    }

    private static func clip(_ polygon: [SIMD2<Float>], axis: Int, limit: Float, upper: Bool) -> [SIMD2<Float>] {
        guard let last = polygon.last else { return [] }
        func inside(_ p: SIMD2<Float>) -> Bool { upper ? p[axis] <= limit : p[axis] >= limit }
        var result: [SIMD2<Float>] = [], previous = last
        var previousInside = inside(last)
        for point in polygon {
            let pointInside = inside(point)
            if pointInside != previousInside {
                let denominator = point[axis] - previous[axis]
                if abs(denominator) > 0.0000001 {
                    result.append(previous + (point - previous) * ((limit - previous[axis]) / denominator))
                }
            }
            if pointInside { result.append(point) }
            previous = point; previousInside = pointInside
        }
        return result
    }

    private static func finite(_ value: SIMD3<Float>) -> Bool {
        value.x.isFinite && value.y.isFinite && value.z.isFinite
    }
}
