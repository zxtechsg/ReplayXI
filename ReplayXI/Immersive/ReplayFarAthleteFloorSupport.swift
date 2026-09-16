import RealityKit
import simd

/// The far silhouette is rigid under each hip, not articulated under its knee.
/// Prepare its real support points once so the shared near-leg ground solver
/// cannot bury that longer silhouette. No mesh access occurs during posing.
@MainActor
struct ReplayFarAthleteFloorSupport {
    static let maximumPointCount = 128
    private static let maximumRawVerticesPerLeg = 128

    private struct Leg {
        let hip: Entity
        let points: [SIMD3<Float>]
    }

    private let rigRoot: Entity
    private let bodyRoot: Entity
    private let hips: Entity
    private let legs: [Leg]
    let pointCount: Int

    #if DEBUG
    private(set) static var preparationCount = 0
    private(set) static var sourceVertexReadCount = 0
    private(set) static var queryCount = 0

    static func resetDiagnosticsForTesting() {
        preparationCount = 0
        sourceVertexReadCount = 0
        queryCount = 0
    }
    #endif

    init?(leftHip: Entity, rightHip: Entity) {
        guard let hips = leftHip.parent, rightHip.parent === hips,
              let bodyRoot = hips.parent, let rigRoot = bodyRoot.parent else { return nil }
        var prepared: [Leg] = []
        var total = 0
        for (hip, name) in [(leftHip, "left-leg"), (rightHip, "right-leg")] {
            // Only the factory's integrated far legs qualify. Near/mid use
            // separate thigh, shin and boot meshes and keep their current pose.
            guard let model = hip.children.first(where: { $0.name == name }) as? ModelEntity,
                  model.parent === hip, let component = model.model else { return nil }
            var rawCount = 0
            var points: [SIMD3<Float>] = []
            points.reserveCapacity(Self.maximumPointCount / 2)
            for mesh in component.mesh.contents.models {
                for part in mesh.parts {
                    guard part.positions.count <= Self.maximumRawVerticesPerLeg - rawCount else { return nil }
                    rawCount += part.positions.count
                    for source in part.positions.elements {
                        #if DEBUG
                        Self.sourceVertexReadCount += 1
                        #endif
                        // Capture RealityKit's rendered local transform once.
                        // Entity accepts a zero quaternion as an identity reset;
                        // Transform.matrix instead collapses that stored basis.
                        let point = model.convert(position: source, to: hip)
                        guard point.x.isFinite, point.y.isFinite, point.z.isFinite,
                              abs(point.x) <= 4, abs(point.y) <= 4, abs(point.z) <= 4 else { return nil }
                        if !points.contains(point) {
                            guard points.count < Self.maximumPointCount / 2 else { return nil }
                            points.append(point)
                        }
                    }
                }
            }
            guard !points.isEmpty else { return nil }
            total += points.count
            prepared.append(Leg(hip: hip, points: points))
        }
        guard prepared.count == 2, total <= Self.maximumPointCount else { return nil }
        self.rigRoot = rigRoot
        self.bodyRoot = bodyRoot
        self.hips = hips
        legs = prepared
        pointCount = total
        #if DEBUG
        Self.preparationCount += 1
        #endif
    }

    /// Exact mesh-vertex support for the current hip transforms, in rig-root
    /// space. Appearance/focus scales sit outside this frame and stay intact.
    func minimumY(relativeTo root: Entity) -> Float {
        #if DEBUG
        Self.queryCount += 1
        #endif
        guard root === rigRoot else { return .nan }
        // The validated pose writes unit quaternions to this local chain.
        // Avoid a world/inverse-world round trip: its rounding can depend on
        // the previous miniature/room view even when the authored pose repeats.
        let hipsInRoot = bodyRoot.transform.matrix * hips.transform.matrix
        var minimum = Float.infinity
        for leg in legs {
            let transform = hipsInRoot * leg.hip.transform.matrix
            let x = transform.columns.0.y, y = transform.columns.1.y
            let z = transform.columns.2.y, offset = transform.columns.3.y
            guard x.isFinite, y.isFinite, z.isFinite, offset.isFinite else { return .nan }
            for point in leg.points {
                let height = x * point.x + y * point.y + z * point.z + offset
                guard height.isFinite else { return .nan }
                minimum = min(minimum, height)
            }
        }
        return minimum
    }

    func upwardCorrection(relativeTo root: Entity) -> Float {
        let minimum = minimumY(relativeTo: root)
        // Preserve already-clear standing/flight poses exactly. A continuous
        // max clamp adds no independent clock, contact state or padding step.
        return minimum.isFinite ? max(-minimum, 0) : 0
    }
}
