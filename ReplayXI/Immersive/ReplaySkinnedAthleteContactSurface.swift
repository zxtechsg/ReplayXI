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
    /// Rigid skull probes from the admitted asset, not a guessed forehead.
    /// Cached and bounded at load; header aiming never reads a mesh per frame.
    private let headerPoints: [SIMD4<Float>]
    var headerProbeCount: Int { headerPoints.count }

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
        var skull: [SIMD4<Float>] = []
        let headJoint = motion.semanticJointIndices["head"]
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
            if let headJoint, vertex.joints == [headJoint],
               vertex.position[1] >= motion.geometry.restMinY + motion.geometry.nominalHeight - 0.19 {
                skull.append(inverses[headJoint] * point)
            }
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
        if skull.count <= 96 {
            headerPoints = skull
        } else {
            // Evenly cover the source ordering, retaining all six extrema.
            // Sampling is only an aiming aid; full triangle contact tests are
            // still the independent acceptance check for every rendered LOD.
            var chosen = Set((0..<90).map { $0 * (skull.count - 1) / 89 })
            for axis in 0..<3 {
                if let low = skull.indices.min(by: { skull[$0][axis] < skull[$1][axis] }) { chosen.insert(low) }
                if let high = skull.indices.max(by: { skull[$0][axis] < skull[$1][axis] }) { chosen.insert(high) }
            }
            headerPoints = chosen.sorted().map { skull[$0] }
        }
    }

    /// Stop a planted header's chest aim before its real skull probes pass
    /// through the ball. This rotates the torso only; no root/foot relocation,
    /// skeletal stretch, extra full-hierarchy rebuild or scene lookup.
    @MainActor
    func plantedHeaderAim(_ aim: simd_quatf, weight: Float, pivot: SIMD3<Float>,
                          head: simd_float4x4, ball: SIMD3<Float>) -> simd_quatf {
        let identity = simd_quatf(real: 1, imag: .zero)
        let desired = ReplayAthleteInteractionPose.blend(identity, aim, weight)
        guard weight > 0, !headerPoints.isEmpty else { return desired }
        func clearance(_ delta: simd_quatf) -> Float {
            var distance = Float.infinity
            for local in headerPoints {
                let current = head * local
                let point = pivot + delta.act(SIMD3(current.x, current.y, current.z) - pivot)
                distance = min(distance, simd_distance(point, ball))
            }
            return distance - ReplayNativeBallPhysics.radius
        }
        let padding: Float = 0.008
        guard clearance(desired) < padding else { return desired }
        let axis: SIMD3<Float> = abs(aim.angle) > 0.00001 ? aim.axis : [1, 0, 0]
        let retreat = simd_quatf(angle: -0.45 * weight, axis: axis)
        var previous: Float = 0
        var best = desired
        var bestGap = clearance(desired)
        for step in 1...8 {
            let fraction = Float(step) / 8
            let candidate = ReplayAthleteInteractionPose.blend(desired, retreat, fraction)
            let gap = clearance(candidate)
            if gap > bestGap { best = candidate; bestGap = gap }
            if gap >= padding {
                var inside = previous
                var outside = fraction
                for _ in 0..<10 {
                    let middle = (inside + outside) * 0.5
                    let probe = ReplayAthleteInteractionPose.blend(desired, retreat, middle)
                    if clearance(probe) >= padding { outside = middle } else { inside = middle }
                }
                return ReplayAthleteInteractionPose.blend(desired, retreat, outside)
            }
            previous = fraction
        }
        return best
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
