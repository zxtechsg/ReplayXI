import CryptoKit
import Foundation
import RealityKit
import XCTest
import simd
@testable import ReplayXI

/// Test-only access for admission checks and later calibrated renderer probes.
/// No application provider, contact envelope or runtime admission is changed.
@MainActor
enum ReplayLowDetailAthleteFixture {
    static let assetHash = "cd8a496a1f89166cf819177c8b959246d130f64ea5dfbd86910488b1dbe849ac"
    static let manifestHash = "9cd03e16888fe635bc1e4d417d48895da33dd98b7be7dbf744e262f1177dd5fd"
    static let assetBytes = 1_263_724

    enum Failure: Error, Equatable {
        case changedIdentity(String)
        case invalid(String)
    }

    struct Document: Decodable {
        struct Asset: Decodable { let filename: String; let sha256: String; let bytes: Int }
        struct Coordinates: Decodable {
            let upAxis: String
            let metresPerUnit: Float
            let forwardAxis: String
            let rootBaseLift: Float
            let rootLiftBakedIntoPoints: Bool
        }
        struct Skeleton: Decodable {
            let jointNames: [String]
            let sourceNames: [String]
            let parentIndices: [Int]
            let bindMatricesColumnMajor: [[Float]]
            let inverseBindMatricesColumnMajor: [[Float]]
            let restLocalMatricesColumnMajor: [[Float]]
        }
        struct Part: Decodable {
            let name: String
            let materialIndex: Int
            let positions: [[Float]]
            let normals: [[Float]]
            let uvs: [[Float]]
            let triangleIndices: [Int]
            let jointIndices: [[Int]]
            let jointWeights: [[Float]]
        }
        struct Pose: Decodable {
            let name: String
            let groundOffset: Float
            let translations: [[Float]]
            let rotations: [[Float]]
            let scales: [[Float]]
            let expectedPositionsWithRootOffset: [String: [[Float]]]
        }
        let schemaVersion: Int
        let candidateOnly: Bool
        let asset: Asset
        let coordinates: Coordinates
        let skeleton: Skeleton
        let parts: [Part]
        let poses: [Pose]
    }

    struct Loaded {
        let root: Entity
        let model: ModelEntity
        let document: Document
    }

    static func checkedData(_ data: Data, hash: String, name: String) throws -> Data {
        let actual = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        guard actual == hash else { throw Failure.changedIdentity(name) }
        return data
    }

    static func load() throws -> Loaded {
        let directory = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent(".codex-derived/ReplayXI-Low102-Canonical-03", isDirectory: true)
        let assetURL = directory.appendingPathComponent("ReplayXILow102Canonical.usdz")
        do {
            let values = try assetURL.resourceValues(forKeys: [.isRegularFileKey])
            guard values.isRegularFile == true else { throw Failure.invalid("Fixture is not a regular file") }
        } catch let error as NSError where error.domain == NSCocoaErrorDomain
            && [NSFileNoSuchFileError, NSFileReadNoSuchFileError].contains(error.code) {
            // Only a genuinely absent optional asset skips. An unreadable,
            // changed or malformed present package/manifest must fail.
            throw XCTSkip("External canonical Low102 USDZ is absent; no native admission attempted")
        }
        let assetData = try checkedData(Data(contentsOf: assetURL, options: .mappedIfSafe),
                                        hash: assetHash, name: "Low102 USDZ")
        guard assetData.count == assetBytes else { throw Failure.invalid("Low102 byte count changed") }
        let manifestURL = directory.appendingPathComponent("native-admission-fixture.json")
        let manifest = try checkedData(Data(contentsOf: manifestURL), hash: manifestHash, name: "Low102 manifest")
        let document = try JSONDecoder().decode(Document.self, from: manifest)
        guard document.schemaVersion == 1, document.candidateOnly,
              document.asset.filename == assetURL.lastPathComponent,
              document.asset.sha256 == assetHash, document.asset.bytes == assetBytes else {
            throw Failure.invalid("Low102 manifest identity contract changed")
        }
        let root = try Entity.load(contentsOf: assetURL)
        root.stopAllAnimations(recursive: true)
        let models = allModels(in: root)
        guard models.count == 1, let model = models.first, model.jointNames.count == 80 else {
            throw Failure.invalid("Expected one native coalesced 80-joint model; found \(models.count) models")
        }
        return Loaded(root: root, model: model, document: document)
    }

    /// Direct canonical local-TRS writes with exactly one external base lift.
    /// A renderer caller may attach the returned root; no animation controller
    /// or old near-body contact correction participates in this pose.
    @discardableResult
    static func applyPose(named name: String, to loaded: Loaded) throws -> Document.Pose {
        guard let pose = loaded.document.poses.first(where: { $0.name == name }),
              pose.translations.count == 80, pose.rotations.count == 80, pose.scales.count == 80,
              pose.groundOffset.isFinite else { throw Failure.invalid("Invalid named canonical pose: \(name)") }
        var transforms: [Transform] = []
        for index in 0..<80 {
            let rotation = pose.rotations[index]
            guard rotation.count == 4, rotation.allSatisfy(\.isFinite) else {
                throw Failure.invalid("Invalid pose quaternion")
            }
            transforms.append(Transform(scale: try point(pose.scales[index]),
                rotation: simd_quatf(vector: SIMD4(rotation[0], rotation[1], rotation[2], rotation[3])),
                translation: try point(pose.translations[index])))
        }
        loaded.root.stopAllAnimations(recursive: true)
        loaded.model.jointTransforms = transforms
        loaded.root.position = [0, pose.groundOffset, 0]
        return pose
    }

    static func loadAndPose(named name: String) throws -> Loaded {
        let loaded = try load()
        try applyPose(named: name, to: loaded)
        return loaded
    }

    static func allModels(in root: Entity) -> [ModelEntity] {
        ((root as? ModelEntity).map { [$0] } ?? []) + root.children.flatMap { allModels(in: $0) }
    }

    static func point(_ values: [Float]) throws -> SIMD3<Float> {
        guard values.count == 3, values.allSatisfy(\.isFinite) else { throw Failure.invalid("Invalid point") }
        return SIMD3(values[0], values[1], values[2])
    }

    static func matrix(_ values: [Float]) throws -> simd_float4x4 {
        guard values.count == 16, values.allSatisfy(\.isFinite) else { throw Failure.invalid("Invalid matrix") }
        return simd_float4x4(columns: (
            SIMD4(values[0], values[1], values[2], values[3]),
            SIMD4(values[4], values[5], values[6], values[7]),
            SIMD4(values[8], values[9], values[10], values[11]),
            SIMD4(values[12], values[13], values[14], values[15])))
    }
}

/// Source/import and CPU skinning parity, not renderer deformation or grounding.
@MainActor
final class ReplayLowDetailAthleteAdmissionTests: XCTestCase {
    private typealias Fixture = ReplayLowDetailAthleteFixture
    private let matrixTolerance: Float = 0.000_1
    private let vertexTolerance: Float = 0.000_1

    func testPresentChangedFixtureIdentityFailsInsteadOfSkipping() {
        for (hash, name) in [(Fixture.assetHash, "Low102 USDZ"), (Fixture.manifestHash, "Low102 manifest")] {
            XCTAssertThrowsError(try Fixture.checkedData(Data([1, 2, 3]), hash: hash, name: name)) { error in
                XCTAssertEqual(error as? Fixture.Failure, .changedIdentity(name))
            }
        }
    }

    func testCanonicalLowSkinImportMetadataClonesAndPoseRewind() throws {
        let loaded = try Fixture.load()
        let fixture = loaded.document
        let model = loaded.model
        let component = try XCTUnwrap(model.model)
        // Retain the wrapper while checking clone identity, rather than count
        // bare addresses whose Swift resource wrappers may have been released.
        let mesh = component.mesh
        let contents = mesh.contents
        let nativeMeshModels = Array(contents.models)
        let nativeMeshInstances = Array(contents.instances)
        let nativeParts = nativeMeshModels.flatMap { Array($0.parts) }
        let nativeSkeletons = Array(contents.skeletons)
        let bounds = loaded.root.visualBounds(relativeTo: nil)
        try attach([
            "assetSHA256": Fixture.assetHash, "manifestSHA256": Fixture.manifestHash,
            "nativeModels": Fixture.allModels(in: loaded.root).count,
            "nativeSkeletons": nativeSkeletons.count, "nativeJointNames": model.jointNames,
            "nativeMeshModels": nativeMeshModels.map { meshModel -> [String: Any] in [
                "id": meshModel.id, "parts": meshModel.parts.map(\.id)
            ] },
            "nativeMeshInstances": nativeMeshInstances.map { instance -> [String: Any] in [
                "id": instance.id, "model": instance.model, "transform": flatten(instance.transform)
            ] },
            "nativeParts": nativeParts.map { part -> [String: Any] in [
                "name": part.id, "materialIndex": part.materialIndex,
                "vertices": part.positions.count, "triangles": (part.triangleIndices?.count ?? 0) / 3,
                "influences": part.jointInfluences?.influences.count ?? 0,
                "skeletonID": part.skeletonID ?? "<none>"
            ] },
            "rootMatrix": flatten(loaded.root.transform.matrix),
            "modelMatrixRelativeToRoot": flatten(model.transformMatrix(relativeTo: loaded.root)),
            "boundsMin": [bounds.min.x, bounds.min.y, bounds.min.z],
            "boundsMax": [bounds.max.x, bounds.max.y, bounds.max.z],
            "notRenderedDeformation": true, "notGroundingAdmission": true
        ], name: "ReplayXI-Low109-NativeImport.json")

        XCTAssertEqual(fixture.coordinates.upAxis, "Y")
        XCTAssertEqual(fixture.coordinates.forwardAxis, "+Z")
        XCTAssertEqual(fixture.coordinates.metresPerUnit, 1)
        XCTAssertFalse(fixture.coordinates.rootLiftBakedIntoPoints)
        XCTAssertEqual(fixture.coordinates.rootBaseLift, 0.01643638945035112, accuracy: 0.000_001)
        XCTAssertEqual(model.jointNames, fixture.skeleton.jointNames)
        XCTAssertEqual(model.jointTransforms.count, 80)
        XCTAssertEqual(component.materials.count, 2)
        XCTAssertTrue(component.materials.allSatisfy { $0 is PhysicallyBasedMaterial })
        // One ModelEntity does not imply one MeshResource.Model. The importer
        // retains Body and Head as separate mesh models under the shared skin.
        XCTAssertEqual(nativeMeshModels.count, 2)
        XCTAssertTrue(nativeMeshModels.allSatisfy { $0.parts.count == 1 })
        XCTAssertEqual(Set(nativeMeshModels.flatMap { $0.parts.map(\.id) }), Set(["Body", "Head"]))
        XCTAssertEqual(nativeMeshInstances.count, nativeMeshModels.count)
        XCTAssertEqual(Set(nativeMeshInstances.map(\.model)), Set(nativeMeshModels.map(\.id)))
        XCTAssertEqual(nativeParts.count, 2)
        XCTAssertEqual(nativeParts.reduce(0) { $0 + $1.positions.count }, 1_707)
        XCTAssertEqual(nativeParts.reduce(0) { $0 + ($1.triangleIndices?.count ?? 0) / 3 }, 2_129)
        XCTAssertTrue([bounds.min.x, bounds.min.y, bounds.min.z,
                       bounds.max.x, bounds.max.y, bounds.max.z].allSatisfy(\.isFinite))
        XCTAssertGreaterThan(bounds.extents.y, 1.5)
        XCTAssertLessThan(bounds.extents.y, 2.1)
        assertMatrix(loaded.root.transform.matrix, matrix_identity_float4x4)
        assertMatrix(model.transformMatrix(relativeTo: loaded.root), matrix_identity_float4x4)
        for instance in contents.instances { assertMatrix(instance.transform, matrix_identity_float4x4) }

        let motionURL = try XCTUnwrap(Bundle.main.url(forResource: "ReplayXIRocketboxMotion", withExtension: "json",
            subdirectory: "Resources/Players") ?? Bundle.main.url(forResource: "ReplayXIRocketboxMotion", withExtension: "json"))
        let motionData = try Fixture.checkedData(Data(contentsOf: motionURL),
            hash: ReplaySkinnedAthleteProvider.motionSHA256, name: "Existing canonical motion")
        let motion = try ReplaySkinnedAthleteMotion(data: motionData)
        XCTAssertEqual(fixture.skeleton.jointNames, motion.jointNames)
        XCTAssertEqual(fixture.skeleton.sourceNames, motion.joints.map(\.sourceName))
        XCTAssertEqual(fixture.skeleton.parentIndices, motion.joints.map(\.parentIndex))
        XCTAssertEqual(nativeSkeletons.count, 1)
        let skeleton = try XCTUnwrap(nativeSkeletons.first)
        XCTAssertEqual(skeleton.joints.count, 80)
        XCTAssertEqual(skeleton.joints.map(\.name), fixture.skeleton.jointNames)
        XCTAssertEqual(skeleton.joints.map { $0.parentIndex ?? -1 }, fixture.skeleton.parentIndices)
        guard skeleton.joints.count == 80 else { return }
        for index in 0..<80 {
            assertMatrix(skeleton.joints[index].inverseBindPoseMatrix,
                         try Fixture.matrix(fixture.skeleton.inverseBindMatricesColumnMajor[index]))
            assertMatrix(skeleton.joints[index].restPoseTransform.matrix,
                         try Fixture.matrix(fixture.skeleton.restLocalMatricesColumnMajor[index]))
        }

        var importedParts: [ImportedPart] = []
        for expected in fixture.parts {
            let part = try XCTUnwrap(nativeParts.first { $0.id == expected.name })
            XCTAssertEqual(part.materialIndex, expected.materialIndex)
            XCTAssertEqual(part.skeletonID, skeleton.id)
            importedParts.append(try compare(part: part, with: expected))
        }
        let clone = loaded.root.clone(recursive: true)
        clone.stopAllAnimations(recursive: true)
        let cloneModel = try XCTUnwrap(Fixture.allModels(in: clone).first)
        XCTAssertFalse(cloneModel === model)
        XCTAssertTrue(try XCTUnwrap(cloneModel.model).mesh === mesh)
        let cloneOriginalPose = cloneModel.jointTransforms
        let cloneOriginalTransform = clone.transform
        let poseNames = ["source-idle", "run", "cut-right", "pass-contact"]
        XCTAssertEqual(fixture.poses.map(\.name), poseNames)
        var referenceJointPoses: [String: [Transform]] = [:]
        var errors: [[String: Any]] = []
        for name in poseNames + poseNames.reversed() {
            let pose = try Fixture.applyPose(named: name, to: loaded)
            let actual = model.jointTransforms
            XCTAssertEqual(actual.count, 80)
            XCTAssertEqual(cloneModel.jointTransforms, cloneOriginalPose, "Pose buffers must belong to each clone")
            XCTAssertEqual(clone.transform, cloneOriginalTransform, "Base lift must not affect the other clone")
            XCTAssertTrue(try XCTUnwrap(model.model).mesh === mesh)
            if let previous = referenceJointPoses[name] {
                XCTAssertEqual(actual, previous, "The same absolute pose must rewind exactly")
            } else { referenceJointPoses[name] = actual }
            let matrices = modelSpaceTransforms(actual, parents: fixture.skeleton.parentIndices)
            XCTAssertEqual(matrices.count, 80)
            for part in importedParts {
                let expectedPoints = try XCTUnwrap(pose.expectedPositionsWithRootOffset[part.name])
                var maximumError: Float = 0
                for vertex in part.positions.indices {
                    let position = part.positions[vertex]
                    var deformed = SIMD4<Float>.zero
                    for influence in part.influences[vertex] {
                        let skinMatrix = matrices[influence.jointIndex]
                            * skeleton.joints[influence.jointIndex].inverseBindPoseMatrix
                        deformed += skinMatrix * SIMD4(position.x, position.y, position.z, 1) * influence.weight
                    }
                    let actualWorld = loaded.root.transform.matrix * deformed
                    let expected = try Fixture.point(expectedPoints[part.fixtureVertexIndices[vertex]])
                    let error = simd_distance(SIMD3(actualWorld.x, actualWorld.y, actualWorld.z), expected)
                    XCTAssertTrue(error.isFinite)
                    maximumError = max(maximumError, error)
                }
                XCTAssertLessThanOrEqual(maximumError, vertexTolerance, "\(name)/\(part.name): imported-weight CPU parity")
                errors.append(["pose": name, "part": part.name, "vertices": part.positions.count,
                               "maximumCPUSkinErrorMetres": maximumError])
            }
        }
        XCTAssertNotEqual(referenceJointPoses["run"], referenceJointPoses["pass-contact"])
        try attach(["samples": errors, "source": "Public imported positions, weights and inverse binds + read-back joint TRS",
                    "method": "CPU linear blend skinning with one external root offset",
                    "notRendererEvaluatedVertices": true, "notGroundingAdmission": true,
                    "runtimeAdmissionUnchanged": true], name: "ReplayXI-Low109-CPUSkinParity.json")
    }

    private struct ImportedPart {
        let name: String
        let positions: [SIMD3<Float>]
        let influences: [[MeshJointInfluence]]
        let fixtureVertexIndices: [Int]
    }

    private func compare(part: MeshResource.Part, with expected: Fixture.Document.Part) throws -> ImportedPart {
        let positions = part.positions.elements
        let normals = try XCTUnwrap(part.normals).elements
        let uvs = try XCTUnwrap(part.textureCoordinates).elements
        let influences = try XCTUnwrap(part.jointInfluences, "Public imported skin influences must be exposed").influences.elements
        XCTAssertEqual(positions.count, expected.positions.count)
        XCTAssertEqual(normals.count, positions.count)
        XCTAssertEqual(uvs.count, positions.count)
        guard !positions.isEmpty, influences.count % positions.count == 0 else {
            throw Fixture.Failure.invalid("Invalid imported influence layout")
        }
        let stride = influences.count / positions.count
        XCTAssertTrue((1...4).contains(stride))
        guard (1...4).contains(stride), uvs.count == positions.count, normals.count == positions.count else {
            throw Fixture.Failure.invalid("Unsupported imported vertex buffers")
        }
        let expectedPoints = try expected.positions.map(Fixture.point)
        let expectedWeights = expected.jointIndices.indices.map { vertex in
            weights(indices: expected.jointIndices[vertex], values: expected.jointWeights[vertex])
        }
        var used = Set<Int>()
        var mapping: [Int] = []
        var actualInfluences: [[MeshJointInfluence]] = []
        for vertex in positions.indices {
            let vertexInfluences = Array(influences[(vertex * stride)..<((vertex + 1) * stride)])
            XCTAssertTrue(vertexInfluences.allSatisfy { (0..<80).contains($0.jointIndex) && $0.weight.isFinite && $0.weight >= 0 })
            guard vertexInfluences.allSatisfy({ (0..<80).contains($0.jointIndex) && $0.weight.isFinite && $0.weight >= 0 }) else {
                throw Fixture.Failure.invalid("Invalid imported skin influence")
            }
            let actualWeights = weights(indices: vertexInfluences.map(\.jointIndex), values: vertexInfluences.map(\.weight))
            XCTAssertEqual(actualWeights.values.reduce(0, +), 1, accuracy: 0.000_01)
            let match = expectedPoints.indices.first { index in
                !used.contains(index) && simd_distance(positions[vertex], expectedPoints[index]) <= 0.000_01
                    && simd_distance(uvs[vertex], SIMD2(expected.uvs[index][0], expected.uvs[index][1])) <= 0.000_01
                    && sameWeights(actualWeights, expectedWeights[index])
            }
            let matched = try XCTUnwrap(match, "No one-to-one position/UV/weight match for \(part.id) vertex \(vertex)")
            used.insert(matched)
            mapping.append(matched)
            actualInfluences.append(vertexInfluences)
            XCTAssertLessThanOrEqual(simd_distance(normals[vertex], try Fixture.point(expected.normals[matched])), 0.000_1)
        }
        XCTAssertEqual(used.count, expected.positions.count)
        let indices = try XCTUnwrap(part.triangleIndices).elements.map(Int.init)
        XCTAssertEqual(indices.count, expected.triangleIndices.count)
        guard indices.allSatisfy(positions.indices.contains) else { throw Fixture.Failure.invalid("Invalid triangle index") }
        XCTAssertEqual(triangleCounts(indices.map { mapping[$0] }), triangleCounts(expected.triangleIndices),
                       "Importer may reorder vertices/faces but must preserve oriented topology")
        return ImportedPart(name: part.id, positions: positions, influences: actualInfluences, fixtureVertexIndices: mapping)
    }

    private func weights(indices: [Int], values: [Float]) -> [Int: Float] {
        var result: [Int: Float] = [:]
        for (index, value) in zip(indices, values) where value > 0 { result[index, default: 0] += value }
        return result
    }

    private func sameWeights(_ first: [Int: Float], _ second: [Int: Float]) -> Bool {
        Set(first.keys) == Set(second.keys) && first.allSatisfy { abs($0.value - (second[$0.key] ?? 0)) <= 0.000_01 }
    }

    private func triangleCounts(_ indices: [Int]) -> [String: Int] {
        var result: [String: Int] = [:]
        for offset in stride(from: 0, to: indices.count - 2, by: 3) {
            let triangle = Array(indices[offset..<(offset + 3)])
            let start = triangle.indices.min { triangle[$0] < triangle[$1] }!
            let key = (0..<3).map { String(triangle[(start + $0) % 3]) }.joined(separator: ",")
            result[key, default: 0] += 1
        }
        return result
    }

    private func modelSpaceTransforms(_ transforms: [Transform], parents: [Int]) -> [simd_float4x4] {
        var result: [simd_float4x4] = []
        for index in transforms.indices {
            let local = transforms[index].matrix
            let parent = parents[index]
            result.append(parent >= 0 ? result[parent] * local : local)
        }
        return result
    }

    private func assertMatrix(_ actual: simd_float4x4, _ expected: simd_float4x4,
                              file: StaticString = #filePath, line: UInt = #line) {
        for column in 0..<4 {
            XCTAssertTrue(actual[column].x.isFinite && actual[column].y.isFinite
                          && actual[column].z.isFinite && actual[column].w.isFinite, file: file, line: line)
            XCTAssertLessThanOrEqual(simd_distance(actual[column], expected[column]), matrixTolerance, file: file, line: line)
        }
    }

    private func flatten(_ matrix: simd_float4x4) -> [Float] {
        (0..<4).flatMap { column in (0..<4).map { matrix[column][$0] } }
    }

    private func attach(_ value: [String: Any], name: String) throws {
        let data = try JSONSerialization.data(withJSONObject: value, options: [.sortedKeys])
        let attachment = XCTAttachment(data: data, uniformTypeIdentifier: "public.json")
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
