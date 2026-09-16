import Foundation
import simd

/// A small set of real, weighted skin vertices baked from the audited Blender
/// library. Bone-local points are prepared once; a contact query needs only
/// matrix/vector products, never a mesh readback or all 5,012 body vertices.
struct ReplaySkinnedAthleteContactSurface: Sendable {
    static let maximumVertices = 512
    static let maximumPayloadBytes = 256 * 1_024
    enum DecodeError: Error, Equatable { case invalid(String) }

    private struct Influence: Sendable {
        let joint: Int
        let localPoint: SIMD4<Float>
        let weight: Float
    }

    private struct Document: Decodable {
        let schemaVersion: Int
        let assetSHA256: String
        let motionSHA256: String
        let sourceVertexCount: Int
        let jointCount: Int
        let paddingMetres: Float
        let vertices: [Vertex]

        struct Vertex: Decodable {
            let id: String
            let position: [Float]
            let joints: [Int]
            let weights: [Float]
        }
    }

    let paddingMetres: Float
    private let ranges: [Range<Int>]
    private let influences: [Influence]
    private let jointCount: Int

    var vertexCount: Int { ranges.count }
    var influenceCount: Int { influences.count }

    init(data: Data, motion: ReplaySkinnedAthleteMotion,
         assetSHA256: String, motionSHA256: String) throws {
        guard data.count <= Self.maximumPayloadBytes else { throw DecodeError.invalid("Contact data exceeds budget") }
        let document = try JSONDecoder().decode(Document.self, from: data)
        guard document.schemaVersion == 1,
              document.assetSHA256 == assetSHA256, document.motionSHA256 == motionSHA256,
              document.sourceVertexCount == 5_012,
              document.jointCount == motion.joints.count,
              (8...Self.maximumVertices).contains(document.vertices.count),
              document.paddingMetres.isFinite, (0.001...0.020).contains(document.paddingMetres)
        else { throw DecodeError.invalid("Contact surface does not match the verified skin") }
        let inverses = motion.restPose.modelSpaceTransforms.map(\.inverse)
        var ranges: [Range<Int>] = []
        var influences: [Influence] = []
        ranges.reserveCapacity(document.vertices.count)
        influences.reserveCapacity(document.vertices.count * 4)
        var identities = Set<String>()
        for vertex in document.vertices {
            guard !vertex.id.isEmpty, vertex.id.count <= 40, identities.insert(vertex.id).inserted,
                  vertex.position.count == 3, vertex.position.allSatisfy({ $0.isFinite && abs($0) <= 3 }),
                  vertex.position[1] >= motion.geometry.restMinY - 0.02,
                  vertex.position[1] <= motion.geometry.restMinY + motion.geometry.nominalHeight + 0.02,
                  (1...4).contains(vertex.joints.count), vertex.joints.count == vertex.weights.count,
                  Set(vertex.joints).count == vertex.joints.count,
                  vertex.joints.allSatisfy({ motion.joints.indices.contains($0) }),
                  vertex.weights.allSatisfy({ $0.isFinite && $0 > 0 && $0 <= 1 })
            else { throw DecodeError.invalid("Invalid contact vertex") }
            let total = vertex.weights.reduce(0, +)
            guard abs(total - 1) <= 0.0001 else { throw DecodeError.invalid("Unnormalised contact weights") }
            let point = SIMD4<Float>(vertex.position[0], vertex.position[1], vertex.position[2], 1)
            let start = influences.count
            for (joint, weight) in zip(vertex.joints, vertex.weights) {
                influences.append(Influence(joint: joint, localPoint: inverses[joint] * point, weight: weight / total))
            }
            ranges.append(start..<influences.count)
        }
        self.paddingMetres = document.paddingMetres
        self.ranges = ranges
        self.influences = influences
        self.jointCount = document.jointCount
    }

    /// Same linear skinning rule as the source mesh. The caller's model-space
    /// hierarchy must be current. Uniform root translation moves the result by
    /// exactly the same amount, so one correction grounds the whole body.
    func minimumY(in pose: ReplaySkinnedAthleteMotion.Pose) -> Float {
        guard pose.modelSpaceTransforms.count == jointCount else { return .nan }
        var minimum = Float.infinity
        for range in ranges {
            var height: Float = 0
            for index in range {
                let influence = influences[index]
                height += (pose.modelSpaceTransforms[influence.joint] * influence.localPoint).y * influence.weight
            }
            guard height.isFinite else { return .nan }
            minimum = min(minimum, height)
        }
        return minimum
    }
}
