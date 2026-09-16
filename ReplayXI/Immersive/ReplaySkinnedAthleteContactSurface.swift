import Foundation
import simd

/// A small set of real, weighted skin vertices baked from the audited Blender
/// library. Bone-local points are prepared once; a contact query needs only
/// matrix/vector products, never a mesh readback or all 5,012 body vertices.
struct ReplaySkinnedAthleteContactSurface: Sendable {
    static let maximumVertices = 512
    static let maximumPayloadBytes = 256 * 1_024
    enum DecodeError: Error, Equatable { case invalid(String) }

    /// The optional low mesh uses every admitted vertex and its actual USD
    /// inverse binds. Its larger payload must not relax the original profile.
    enum Profile: Equatable, Sendable {
        case near
        case fullLowDetail

        var maximumVertices: Int { self == .near ? 512 : 1_800 }
        var maximumPayloadBytes: Int { self == .near ? 256 * 1_024 : 512 * 1_024 }
        var sourceVertexCount: Int { self == .near ? 5_012 : 1_707 }
        var schemaVersion: Int { self == .near ? 1 : 2 }
    }

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
        let profileKind: String?
        let rootBaseLift: Float?
        let rootLiftBakedIntoPoints: Bool?
        let jointNames: [String]?
        let inverseBindMatricesColumnMajor: [[Float]]?

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
         assetSHA256: String, motionSHA256: String, profile: Profile = .near) throws {
        guard data.count <= profile.maximumPayloadBytes else { throw DecodeError.invalid("Contact data exceeds budget") }
        let document = try JSONDecoder().decode(Document.self, from: data)
        guard document.schemaVersion == profile.schemaVersion,
              document.assetSHA256 == assetSHA256, document.motionSHA256 == motionSHA256,
              document.sourceVertexCount == profile.sourceVertexCount,
              document.jointCount == motion.joints.count,
              (8...profile.maximumVertices).contains(document.vertices.count),
              document.paddingMetres.isFinite, (0.001...0.020).contains(document.paddingMetres)
        else { throw DecodeError.invalid("Contact surface does not match the verified skin") }
        let restInverses = motion.restPose.modelSpaceTransforms.map(\.inverse)
        let inverses: [simd_float4x4]
        if profile == .fullLowDetail {
            guard document.profileKind == "full-low-mesh",
                  document.vertices.count == profile.sourceVertexCount,
                  document.jointNames == motion.jointNames,
                  document.rootLiftBakedIntoPoints == false,
                  let rootLift = document.rootBaseLift, rootLift.isFinite,
                  abs(rootLift + motion.geometry.restMinY) < 0.000_001,
                  let matrices = document.inverseBindMatricesColumnMajor,
                  matrices.count == motion.joints.count else {
                throw DecodeError.invalid("Incomplete canonical low contact surface")
            }
            inverses = try matrices.enumerated().map { index, values in
                guard values.count == 16, values.allSatisfy({ $0.isFinite && abs($0) <= 4 }) else {
                    throw DecodeError.invalid("Invalid canonical inverse bind")
                }
                let matrix = simd_float4x4(columns: (
                    SIMD4(values[0], values[1], values[2], values[3]),
                    SIMD4(values[4], values[5], values[6], values[7]),
                    SIMD4(values[8], values[9], values[10], values[11]),
                    SIMD4(values[12], values[13], values[14], values[15])
                ))
                // USD retains slightly more bind precision than the rounded
                // motion sidecar. The measured difference is <0.00014; retain
                // those exact USD values, but reject another skeleton/basis.
                for column in 0..<4 {
                    let difference = abs(matrix[column] - restInverses[index][column])
                    guard difference.max() <= 0.000_2 else {
                        throw DecodeError.invalid("Canonical inverse bind does not match motion")
                    }
                }
                guard abs(values[3]) < 0.000_001, abs(values[7]) < 0.000_001,
                      abs(values[11]) < 0.000_001, abs(values[15] - 1) < 0.000_001 else {
                    throw DecodeError.invalid("Non-affine canonical inverse bind")
                }
                return matrix
            }
        } else {
            inverses = restInverses
        }
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

    /// A sole point alone misses the outside edge of a banked boot. Correct
    /// the final blended skin instead, including between authored gait poses.
    /// Only raise penetrations: running flight phases must never be pulled down.
    /// The validated skeleton has one root at index zero. Its uniform lift can
    /// update the current hierarchy in place without a second matrix rebuild.
    @discardableResult
    func raiseAboveFloor(_ floor: Float, in pose: inout ReplaySkinnedAthleteMotion.Pose) -> Float {
        guard floor.isFinite, pose.translations.count == jointCount else { return 0 }
        let lift = floor - minimumY(in: pose)
        guard lift.isFinite, lift > 0 else { return 0 }
        pose.translations[0].y += lift
        for index in pose.modelSpaceTransforms.indices {
            pose.modelSpaceTransforms[index].columns.3.y += lift
        }
        return lift
    }
}
