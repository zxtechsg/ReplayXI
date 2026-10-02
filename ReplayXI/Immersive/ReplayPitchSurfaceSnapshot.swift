import ARKit
import Foundation
import Metal
import simd

@available(visionOS 26.0, *)
extension ReplayPitchSurfaceSnap {
    /// Copy only validated geometry from ARKit's Metal buffers. No buffer or
    /// provider escapes into playback or the pure placement solver.
    static func surface(from anchor: PlaneAnchor) -> Surface? {
        guard anchor.alignment == .horizontal else { return nil }
        let kind: Kind
        switch anchor.surfaceClassification {
        case .floor: kind = .floor
        case .table: kind = .table
        case .none: kind = .surface
        default: return nil
        }
        let geometry = anchor.geometry
        let vertices = geometry.meshVertices, faces = geometry.meshFaces
        guard vertices.format == .float3, vertices.componentsPerVector == 3,
              vertices.count > 2, vertices.count <= 65_536,
              vertices.offset >= 0, vertices.stride >= 12,
              vertices.offset + (vertices.count - 1) * vertices.stride + 12 <= vertices.buffer.length,
              faces.primitive == .triangle, faces.count > 0, faces.count <= 65_536,
              faces.bytesPerIndex == 2 || faces.bytesPerIndex == 4,
              faces.count * 3 * faces.bytesPerIndex <= faces.buffer.length else { return nil }
        let extentFromAnchor = geometry.extent.anchorFromExtentTransform.inverse
        let vertexBytes = vertices.buffer.contents()
        var points: [SIMD2<Float>] = []
        points.reserveCapacity(vertices.count)
        for index in 0..<vertices.count {
            let pointer = vertexBytes.advanced(by: vertices.offset + index * vertices.stride)
            let point = SIMD4<Float>(pointer.loadUnaligned(as: Float.self),
                pointer.advanced(by: 4).loadUnaligned(as: Float.self),
                pointer.advanced(by: 8).loadUnaligned(as: Float.self), 1)
            let local = extentFromAnchor * point
            guard local.x.isFinite, local.y.isFinite, local.z.isFinite else { return nil }
            points.append([local.x, local.z])
        }
        let indexBytes = faces.buffer.contents()
        func index(_ offset: Int) -> Int {
            let pointer = indexBytes.advanced(by: offset * faces.bytesPerIndex)
            return faces.bytesPerIndex == 2 ? Int(pointer.loadUnaligned(as: UInt16.self))
                : Int(pointer.loadUnaligned(as: UInt32.self))
        }
        var triangles: [Triangle] = []
        triangles.reserveCapacity(faces.count)
        for face in 0..<faces.count {
            let a = index(face * 3), b = index(face * 3 + 1), c = index(face * 3 + 2)
            guard a < points.count, b < points.count, c < points.count else { return nil }
            triangles.append(.init(a: points[a], b: points[b], c: points[c]))
        }
        return .init(id: anchor.id, kind: kind,
            worldFromExtent: anchor.originFromAnchorTransform * geometry.extent.anchorFromExtentTransform,
            extent: [geometry.extent.width, geometry.extent.height], triangles: triangles)
    }
}
