import CryptoKit
import Foundation
import RealityKit
import simd

/// Original Blender-authored anatomy with three joints per limb, not another
/// full-body skeleton. Explicit cold preparation; make/update never load files.
@MainActor
enum ReplayArticulatedFarProvider {
    static let resourceName = "ReplayXIArticulatedFar"
    static let expectedSHA256 = "1a16ed08fe9c9272f5f2c2f4187ad1f747a39f52bc056ffaaacff9cee0c0a307"
    static let expectedBytes = 25_268

    enum Part: String, CaseIterable {
        case torso = "Torso", shorts = "Shorts", arm = "Arm", leg = "Leg"
        var metrics: ReplayAthleteMeshMetrics {
            switch self {
            case .torso: .init(vertices: 151, triangles: 266)
            case .shorts: .init(vertices: 67, triangles: 120)
            case .arm: .init(vertices: 167, triangles: 300)
            case .leg: .init(vertices: 213, triangles: 380)
            }
        }
        var jointCount: Int { self == .arm || self == .leg ? 3 : 0 }
    }
    enum PreparationError: Error, Equatable {
        case missingResource, invalidIdentity, invalidGeometry, previousFailure, forcedFailure
    }
    struct SupportVertex {
        let position: SIMD3<Float>
        let weights: SIMD3<Float>
    }
    struct LegSupport {
        let vertices: [SupportVertex]
        let inverseBind: [simd_float4x4]
    }
    private static var templates: [Part: ModelEntity] = [:]
    private(set) static var legSupport: LegSupport?
    private static var attempted = false
    static var isPrewarmed: Bool { templates.count == 4 && legSupport != nil }

    static func prewarm(in bundle: Bundle = .main) throws {
        guard !isPrewarmed else { return }
        guard let url = bundle.url(forResource: resourceName, withExtension: "usdz", subdirectory: "Resources/Players")
            ?? bundle.url(forResource: resourceName, withExtension: "usdz") else {
            throw PreparationError.missingResource
        }
        try prepare(url: url)
    }

    private static func prepare(url: URL) throws {
        guard !isPrewarmed else { return }
        guard !attempted else { throw PreparationError.previousFailure }
        attempted = true
        #if DEBUG
        preparationCount += 1
        if forcesFailure { throw PreparationError.forcedFailure }
        #endif
        let values = try url.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])
        guard values.isRegularFile == true, values.fileSize == expectedBytes else { throw PreparationError.invalidIdentity }
        let data = try Data(contentsOf: url, options: .mappedIfSafe)
        guard data.count == expectedBytes,
              SHA256.hash(data: data).map({ String(format: "%02x", $0) }).joined() == expectedSHA256
        else { throw PreparationError.invalidIdentity }
        let root = try Entity.load(contentsOf: url)
        let models = allModels(in: root)
        guard models.count == 4, isIdentity(root.transform.matrix) else { throw PreparationError.invalidGeometry }
        var prepared: [Part: ModelEntity] = [:]
        var support: LegSupport?
        for kind in Part.allCases {
            guard let model = models.first(where: { $0.name == kind.rawValue || $0.parent?.name == kind.rawValue }),
                  let component = model.model, component.materials.count == 1,
                  component.materials.first is PhysicallyBasedMaterial,
                  model.jointNames.count == kind.jointCount, model.availableAnimations.isEmpty,
                  isIdentity(model.transformMatrix(relativeTo: root)) else { throw PreparationError.invalidGeometry }
            let contents = component.mesh.contents
            let parts = contents.models.flatMap { Array($0.parts) }
            guard contents.models.count == 1, contents.instances.count == 1,
                  contents.instances.first?.model == contents.models.first?.id,
                  let instance = contents.instances.first, isIdentity(instance.transform),
                  contents.skeletons.count == (kind.jointCount == 0 ? 0 : 1),
                  parts.count == 1, let part = parts.first, part.materialIndex == 0,
                  part.positions.count == kind.metrics.vertices,
                  part.normals?.count == kind.metrics.vertices,
                  part.textureCoordinates?.count == kind.metrics.vertices,
                  part.triangleIndices?.count == kind.metrics.triangles * 3,
                  part.positions.elements.allSatisfy({ finite($0) && simd_length($0) < 1.5 }),
                  part.normals?.elements.allSatisfy({ finite($0) }) == true,
                  part.textureCoordinates?.elements.allSatisfy({ $0.x.isFinite && $0.y.isFinite }) == true,
                  part.triangleIndices?.elements.allSatisfy({ $0 < UInt32(kind.metrics.vertices) }) == true
            else { throw PreparationError.invalidGeometry }
            if kind.jointCount == 3 {
                guard model.jointNames == ["Root", "Root/Bend", "Root/Bend/Tip"],
                      model.jointTransforms.count == 3, let skeleton = contents.skeletons.first,
                      skeleton.joints.count == 3, skeleton.joints.map({ $0.parentIndex ?? -1 }) == [-1,0,1],
                      part.skeletonID == skeleton.id, let buffer = part.jointInfluences
                else { throw PreparationError.invalidGeometry }
                let first: Float = kind == .leg ? 0.39 : 0.31
                let second: Float = kind == .leg ? 0.35 : 0.275
                for (index, y) in [Float.zero, -first, -second].enumerated() {
                    let expected = Transform(translation: [0,y,0]).matrix
                    guard close(skeleton.joints[index].restPoseTransform.matrix, expected) else { throw PreparationError.invalidGeometry }
                    let bindY: Float = index == 0 ? 0 : (index == 1 ? first : first + second)
                    guard close(skeleton.joints[index].inverseBindPoseMatrix, Transform(translation: [0,bindY,0]).matrix)
                    else { throw PreparationError.invalidGeometry }
                }
                let influences = buffer.influences.elements
                let stride = influences.count / kind.metrics.vertices
                guard (1...4).contains(stride), influences.count == stride * kind.metrics.vertices else {
                    throw PreparationError.invalidGeometry
                }
                var vertices: [SupportVertex] = []
                if kind == .leg { vertices.reserveCapacity(kind.metrics.vertices) }
                for index in 0..<kind.metrics.vertices {
                    var weights = SIMD3<Float>.zero
                    for influence in influences[(index * stride)..<((index + 1) * stride)] {
                        guard (0..<3).contains(influence.jointIndex), influence.weight.isFinite,
                              influence.weight >= 0, influence.weight <= 1 else { throw PreparationError.invalidGeometry }
                        weights[influence.jointIndex] += influence.weight
                    }
                    guard abs(weights.x + weights.y + weights.z - 1) < 0.000_01 else { throw PreparationError.invalidGeometry }
                    if kind == .leg { vertices.append(SupportVertex(position: part.positions.elements[index], weights: weights)) }
                }
                if kind == .leg {
                    support = LegSupport(vertices: vertices, inverseBind: skeleton.joints.map(\.inverseBindPoseMatrix))
                }
            } else {
                guard part.skeletonID == nil, part.jointInfluences == nil else { throw PreparationError.invalidGeometry }
            }
            let detached = model.clone(recursive: false)
            detached.transform = .identity
            prepared[kind] = detached
        }
        guard prepared.count == 4, support?.vertices.count == 213 else { throw PreparationError.invalidGeometry }
        // Publish the whole four-part family together; a malformed limb never
        // leaves a partially upgraded rig or ungrounded fallback in the scene.
        templates = prepared
        legSupport = support
    }

    static func make(_ part: Part, material: any Material) -> ModelEntity? {
        guard isPrewarmed, let template = templates[part] else { return nil }
        let model = template.clone(recursive: false)
        guard var component = model.model else { return nil }
        component.materials = [material]
        model.model = component
        return model
    }

    private static func allModels(in root: Entity) -> [ModelEntity] {
        ((root as? ModelEntity).map { [$0] } ?? []) + root.children.flatMap { allModels(in: $0) }
    }
    private static func finite(_ value: SIMD3<Float>) -> Bool { value.x.isFinite && value.y.isFinite && value.z.isFinite }
    private static func close(_ a: simd_float4x4, _ b: simd_float4x4) -> Bool {
        (0..<4).allSatisfy { simd_distance(a[$0], b[$0]) < 0.000_001 }
    }
    private static func isIdentity(_ value: simd_float4x4) -> Bool { close(value, matrix_identity_float4x4) }

    #if DEBUG
    private(set) static var preparationCount = 0
    private static var forcesFailure = false
    static func prewarmForTesting(url: URL) throws { try prepare(url: url) }
    static func resetForTesting(forceFailure: Bool = false) {
        templates = [:]; legSupport = nil; attempted = false
        preparationCount = 0; forcesFailure = forceFailure
    }
    #endif
}

/// Four small pose buffers. Geometry and weighted sole support are shared;
/// only joint transforms vary per player. No whole-scene/world inversion.
@MainActor
final class ReplayArticulatedFarBinding {
    private struct Limb {
        let model: ModelEntity
        let pivot: Entity
        let bend: Entity
        let tip: Entity
        var pose = [Transform.identity, Transform.identity, Transform.identity]
    }
    private let root: Entity
    private let body: Entity
    private let hips: Entity
    private let support: ReplayArticulatedFarProvider.LegSupport
    private var limbs: [Limb]
    var supportPointCount: Int { support.vertices.count * 2 }

    init?(root: Entity, joints: [ReplayAthleteJoint: Entity]) {
        guard let support = ReplayArticulatedFarProvider.legSupport,
              let body = joints[.bodyRoot], let hips = joints[.hips] else { return nil }
        let definitions: [(String, ReplayAthleteJoint, ReplayAthleteJoint, ReplayAthleteJoint)] = [
            ("left-leg",.leftHip,.leftKnee,.leftAnkle), ("right-leg",.rightHip,.rightKnee,.rightAnkle),
            ("left-arm",.leftShoulder,.leftElbow,.leftWrist), ("right-arm",.rightShoulder,.rightElbow,.rightWrist)]
        var prepared: [Limb] = []
        for (name, pivotName, bendName, tipName) in definitions {
            guard let pivot = joints[pivotName], let bend = joints[bendName], let tip = joints[tipName],
                  let model = pivot.children.first(where: { $0.name == name }) as? ModelEntity,
                  model.jointNames == ["Root", "Root/Bend", "Root/Bend/Tip"],
                  model.jointTransforms.count == 3, bend.parent === pivot, tip.parent === bend,
                  model.transform.matrix == matrix_identity_float4x4 else { return nil }
            prepared.append(Limb(model: model, pivot: pivot, bend: bend, tip: tip))
        }
        self.root = root; self.body = body; self.hips = hips
        self.support = support; self.limbs = prepared
    }

    func update() {
        for index in limbs.indices {
            limbs[index].pose[0] = .identity
            limbs[index].pose[1] = limbs[index].bend.transform
            limbs[index].pose[2] = limbs[index].tip.transform
            limbs[index].model.jointTransforms = limbs[index].pose
        }
    }

    func minimumY(relativeTo target: Entity) -> Float {
        guard target === root else { return .nan }
        let pelvis = body.transform.matrix * hips.transform.matrix
        var minimum = Float.infinity
        for index in 0..<2 {
            let leg = limbs[index]
            let first = pelvis * leg.pivot.transform.matrix
            let second = first * leg.bend.transform.matrix
            let third = second * leg.tip.transform.matrix
            let m0 = first * support.inverseBind[0]
            let m1 = second * support.inverseBind[1]
            let m2 = third * support.inverseBind[2]
            let row0 = SIMD4(m0[0].y,m0[1].y,m0[2].y,m0[3].y)
            let row1 = SIMD4(m1[0].y,m1[1].y,m1[2].y,m1[3].y)
            let row2 = SIMD4(m2[0].y,m2[1].y,m2[2].y,m2[3].y)
            for vertex in support.vertices {
                let point = SIMD4(vertex.position, 1)
                let y0 = simd_dot(row0,point)
                let y1 = simd_dot(row1,point)
                let y2 = simd_dot(row2,point)
                let y = simd_dot(SIMD3(y0,y1,y2),vertex.weights)
                guard y.isFinite else { return .nan }
                minimum = min(minimum,y)
            }
        }
        return minimum
    }

    func upwardCorrection(relativeTo root: Entity) -> Float {
        let y = minimumY(relativeTo: root)
        return y.isFinite ? max(-y,0) : 0
    }
}
