import CoreGraphics
import CryptoKit
import Foundation
import RealityKit
import UIKit
import XCTest
import simd
@testable import ReplayXI

/// Optional, test-only static face. No bundle/provider/far-rig admission.
@MainActor
enum ReplayStaticFarHeadFixture {
    static let assetHash = "0e8f602695ca0cca505a462db1e8f6a318b8aa72dcd914e0fcce2986bff3d1ce"
    static let manifestHash = "bb859f9304eb2c089a1643e9ff28e68244b02e50f407ca751af29916d01a946b"
    static let reportHash = "d29af3c7e32dd9c15149c6c6487a79e5156e6ce284370de99c6b5a0bb09d15d6"
    static let sourceHash = "7446de58f31366aacf733060a12748b62c3dfb75a46994ba3ed32576355c1f20"
    static let poseHash = "5e1b700b790bda11c496146d7088390aba44ffafad7fa50822f9a374fbd2785f"

    enum Failure: Error, Equatable { case invalid(String) }
    struct Document: Decodable {
        struct Placement: Decodable { let headRootLocalY: Float; let meshScale: [Float] }
        struct Mesh: Decodable {
            let positions: [[Float]]
            let normals: [[Float]]
            let uvs: [[Float]]
            let triangleIndices: [Int]
        }
        let schemaVersion: Int
        let candidateOnly: Bool
        let assetSHA256: String
        let assetBytes: Int
        let sourceAssetSHA256: String
        let vertices: Int
        let triangles: Int
        let materials: Int
        let skeletons: Int
        let upAxis: String
        let metresPerUnit: Float
        let localBoundsMin: [Float]
        let localBoundsMax: [Float]
        let runtimePlacementContract: Placement
        let mesh: Mesh
    }
    struct Report: Decodable {
        struct Pose: Decodable {
            let name: String
            let nativeTime: Double
            let actorFacingRemovedDegrees: Float
            let nativeHeadQuaternion: [Float]
            let nativeNeckQuaternion: [Float]
        }
        let poseAttachmentSHA256: String
        let nativePoseViews: [Pose]
    }
    struct Loaded {
        let document: Document
        let poses: [Report.Pose]
        let source: ModelEntity
        let candidate: ModelEntity
    }

    static func checked(_ data: Data, hash: String) throws -> Data {
        guard SHA256.hash(data: data).map({ String(format: "%02x", $0) }).joined() == hash else {
            throw Failure.invalid("Fixture identity changed")
        }
        return data
    }

    private static func read(_ url: URL, hash: String, maxBytes: Int) throws -> Data {
        let values = try url.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])
        guard values.isRegularFile == true, let size = values.fileSize, size <= maxBytes else {
            throw Failure.invalid("Fixture size/type changed")
        }
        return try checked(Data(contentsOf: url, options: .mappedIfSafe), hash: hash)
    }

    static func load() throws -> Loaded {
        let directory = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent(".codex-derived/ReplayXI-Far114-Head-02", isDirectory: true)
        let candidateURL = directory.appendingPathComponent("ReplayXIFar114Head.usdz")
        do { _ = try candidateURL.resourceValues(forKeys: [.isRegularFileKey]) }
        catch let error as NSError where error.domain == NSCocoaErrorDomain
            && [NSFileNoSuchFileError, NSFileReadNoSuchFileError].contains(error.code) {
            throw XCTSkip("Optional derived static Far114 head is absent")
        }
        let data = try read(candidateURL, hash: assetHash, maxBytes: 1_024 * 1_024)
        guard data.count == 540_760 else { throw Failure.invalid("Static candidate size changed") }
        let document = try JSONDecoder().decode(Document.self, from: read(
            directory.appendingPathComponent("native-admission-fixture.json"), hash: manifestHash, maxBytes: 256 * 1_024))
        let report = try JSONDecoder().decode(Report.self, from: read(
            directory.appendingPathComponent("report.json"), hash: reportHash, maxBytes: 64 * 1_024))
        guard document.schemaVersion == 1, document.candidateOnly,
              document.assetSHA256 == assetHash, document.assetBytes == data.count,
              document.sourceAssetSHA256 == sourceHash, report.poseAttachmentSHA256 == poseHash,
              report.nativePoseViews.count == 4 else { throw Failure.invalid("Static fixture metadata changed") }
        let sourceURL = try XCTUnwrap(Bundle.main.url(forResource: "ReplayXIAthleteHead", withExtension: "usdz",
            subdirectory: "Resources/Players") ?? Bundle.main.url(forResource: "ReplayXIAthleteHead", withExtension: "usdz"))
        _ = try read(sourceURL, hash: sourceHash, maxBytes: 2 * 1_024 * 1_024)
        func model(_ url: URL) throws -> ModelEntity {
            let root = try Entity.load(contentsOf: url)
            let found = models(root)
            guard found.count == 1, let entity = found.first else { throw Failure.invalid("Expected one static model") }
            let matrix = entity.transformMatrix(relativeTo: root)
            for column in 0..<4 where simd_distance(matrix[column], matrix_identity_float4x4[column]) > 0.000_001 {
                throw Failure.invalid("Unexpected imported local transform")
            }
            let component = try XCTUnwrap(entity.model)
            // The admitted head has identity source/root transforms. Extract
            // its shared static mesh just as the existing head provider does.
            return ModelEntity(mesh: component.mesh, materials: component.materials)
        }
        return Loaded(document: document, poses: report.nativePoseViews,
                      source: try model(sourceURL), candidate: try model(candidateURL))
    }

    static func models(_ root: Entity) -> [ModelEntity] {
        ((root as? ModelEntity).map { [$0] } ?? []) + root.children.flatMap { models($0) }
    }

    static func point(_ values: [Float]) throws -> SIMD3<Float> {
        guard values.count == 3, values.allSatisfy(\.isFinite) else { throw Failure.invalid("Invalid point") }
        return [values[0], values[1], values[2]]
    }

    static func quaternion(_ values: [Float]) throws -> simd_quatf {
        guard values.count == 4, values.allSatisfy(\.isFinite) else { throw Failure.invalid("Invalid quaternion") }
        let value = simd_quatf(vector: [values[0], values[1], values[2], values[3]])
        guard abs(simd_length(value.vector) - 1) < 0.000_01 else { throw Failure.invalid("Nonunit native quaternion") }
        return value
    }

    /// Exact existing textured-head placement. Frozen native composites include
    /// body facing; remove only that actor heading for the body-relative crop.
    static func placed(_ model: ModelEntity, pose: Report.Pose) throws -> Entity {
        let inverseHeading = simd_quatf(angle: -pose.actorFacingRemovedDegrees * .pi / 180, axis: [0, 1, 0])
        let head = inverseHeading * (try quaternion(pose.nativeHeadQuaternion))
        let neck = inverseHeading * (try quaternion(pose.nativeNeckQuaternion))
        let root = Entity()
        root.position = neck.act([0, 0.125, 0])
        root.orientation = head
        model.scale = [1.07, 1, 1]
        root.addChild(model)
        return root
    }
}

private final class ReplayStatic114Completion: @unchecked Sendable {
    private let lock = NSLock()
    private var completed = false
    func finish() { lock.withLock { completed = true } }
    var isComplete: Bool { lock.withLock { completed } }
}

@MainActor
final class ReplayStaticFarHeadAdmissionTests: XCTestCase {
    private typealias Fixture = ReplayStaticFarHeadFixture

    func testChangedStaticFixtureFailsInsteadOfSkipping() {
        for hash in [Fixture.assetHash, Fixture.manifestHash, Fixture.reportHash] {
            XCTAssertThrowsError(try Fixture.checked(Data([1, 2, 3]), hash: hash))
        }
    }

    func testStaticCandidateImportsExactTopologyUVsBoundsAndNoSkeleton() throws {
        let loaded = try Fixture.load()
        let expected = loaded.document
        let model = loaded.candidate
        let component = try XCTUnwrap(model.model)
        let mesh = component.mesh
        let contents = mesh.contents
        let parts = contents.models.flatMap { Array($0.parts) }
        let bounds = model.visualBounds(relativeTo: model)
        try attachJSON([
            "assetSHA256": Fixture.assetHash, "models": contents.models.count,
            "parts": parts.count, "materials": component.materials.count,
            "skeletons": contents.skeletons.count, "jointNames": model.jointNames,
            "vertices": parts.reduce(0) { $0 + $1.positions.count },
            "triangles": parts.reduce(0) { $0 + ($1.triangleIndices?.count ?? 0) / 3 },
            "boundsMin": [bounds.min.x, bounds.min.y, bounds.min.z],
            "boundsMax": [bounds.max.x, bounds.max.y, bounds.max.z]
        ], name: "ReplayXI-Static114-NativeImport.json")
        XCTAssertEqual(expected.vertices, 486)
        XCTAssertEqual(expected.triangles, 749)
        XCTAssertEqual(expected.materials, 1)
        XCTAssertEqual(expected.skeletons, 0)
        XCTAssertEqual(expected.upAxis, "Y")
        XCTAssertEqual(expected.metresPerUnit, 1)
        XCTAssertEqual(expected.runtimePlacementContract.headRootLocalY, 0.125)
        XCTAssertEqual(expected.runtimePlacementContract.meshScale, [1.07, 1, 1])
        XCTAssertEqual(contents.models.count, 1)
        XCTAssertEqual(parts.count, 1)
        XCTAssertEqual(contents.skeletons.count, 0)
        XCTAssertEqual(model.jointNames, [])
        XCTAssertEqual(model.jointTransforms, [])
        XCTAssertEqual(component.materials.count, 1)
        let material = try XCTUnwrap(component.materials.first as? PhysicallyBasedMaterial)
        XCTAssertNotNil(material.baseColor.texture)
        XCTAssertNotNil(material.normal.texture)
        XCTAssertEqual(material.baseColor.texture?.resource.width, 512)
        XCTAssertEqual(material.normal.texture?.resource.width, 512)
        XCTAssertLessThanOrEqual(simd_distance(bounds.min, try Fixture.point(expected.localBoundsMin)), 0.000_002)
        XCTAssertLessThanOrEqual(simd_distance(bounds.max, try Fixture.point(expected.localBoundsMax)), 0.000_002)
        let part = try XCTUnwrap(parts.first)
        XCTAssertEqual(part.materialIndex, 0)
        XCTAssertNil(part.skeletonID)
        XCTAssertNil(part.jointInfluences)
        let positions = part.positions.elements
        let normals = try XCTUnwrap(part.normals).elements
        let uvs = try XCTUnwrap(part.textureCoordinates).elements
        let indices = try XCTUnwrap(part.triangleIndices).elements.map(Int.init)
        XCTAssertEqual(positions.count, 486)
        XCTAssertEqual(indices.count, 749 * 3)
        guard positions.count == expected.vertices, normals.count == positions.count, uvs.count == positions.count else {
            throw Fixture.Failure.invalid("Native static vertex layout changed")
        }
        let expectedPoints = try expected.mesh.positions.map(Fixture.point)
        let expectedNormals = try expected.mesh.normals.map(Fixture.point)
        var mapping: [Int] = [], used = Set<Int>()
        for vertex in positions.indices {
            let match = expectedPoints.indices.first { index in
                !used.contains(index) && simd_distance(positions[vertex], expectedPoints[index]) < 0.000_002
                    && simd_distance(normals[vertex], expectedNormals[index]) < 0.000_01
                    && simd_distance(uvs[vertex], SIMD2(expected.mesh.uvs[index][0], expected.mesh.uvs[index][1])) < 0.000_002
            }
            let index = try XCTUnwrap(match, "Static imported point/normal/UV changed")
            used.insert(index); mapping.append(index)
        }
        XCTAssertEqual(used.count, 486)
        guard indices.allSatisfy(positions.indices.contains) else { throw Fixture.Failure.invalid("Native triangle index invalid") }
        XCTAssertEqual(triangles(indices.map { mapping[$0] }), triangles(expected.mesh.triangleIndices))
        let clone = try XCTUnwrap(model.clone(recursive: true) as? ModelEntity)
        XCTAssertTrue(try XCTUnwrap(clone.model).mesh === mesh)
        let cloneTransform = clone.transform
        var previous: [String: simd_float4x4] = [:]
        for pose in loaded.poses + loaded.poses.reversed() {
            let root = try Fixture.placed(model, pose: pose)
            let transform = model.transformMatrix(relativeTo: nil)
            if let first = previous[pose.name] { XCTAssertEqual(transform, first) }
            previous[pose.name] = transform
            XCTAssertEqual(clone.transform, cloneTransform)
            XCTAssertTrue(try XCTUnwrap(model.model).mesh === mesh)
            withExtendedLifetime(root) {}
        }
    }

    func testNativeSourceAndCandidateHeadTurnsWithCalibratedPixels() async throws {
        let loaded = try Fixture.load()
        let probe = try ReplayRealityRendererAudit.probe(try await renderCalibration())
        let matches = probe.candidates.filter { $0.maximumChannelError <= 4 }
        guard matches.count == 1, let calibration = matches.first else {
            throw ReplayRealityRendererAudit.Failure.unsupported("Static head preview failed native calibration")
        }
        let calibrationData = try JSONEncoder().encode(calibration)
        let calibrationAttachment = XCTAttachment(data: calibrationData, uniformTypeIdentifier: "public.json")
        calibrationAttachment.name = "ReplayXI-Static114-Calibration.json"
        calibrationAttachment.lifetime = .keepAlways
        add(calibrationAttachment)
        for pose in loaded.poses {
            var sourcePixels: [UInt8]?
            for (label, template) in [("source", loaded.source), ("candidate", loaded.candidate)] {
                let model = try XCTUnwrap(template.clone(recursive: true) as? ModelEntity)
                let root = try Fixture.placed(model, pose: pose)
                let key = DirectionalLight()
                key.light.intensity = 2_200
                key.look(at: [0, 0.12, 0], from: [3, 4, 3], relativeTo: nil)
                let fill = DirectionalLight()
                fill.light.intensity = 500
                fill.look(at: [0, 0.12, 0], from: [-3, 2, 2], relativeTo: nil)
                let camera = PerspectiveCamera()
                camera.camera = PerspectiveCameraComponent(near: 0.01, far: 5, fieldOfViewInDegrees: 40)
                camera.look(at: [0, 0.12, 0], from: [0.26, 0.26, 0.75], relativeTo: nil)
                let frame = try await render([root, key, fill, camera], camera: camera, size: 512)
                var count = 0, left = 512, top = 512, right = -1, bottom = -1
                for y in 0..<frame.height {
                    let row = calibration.rawRowsAreTopFirst ? y : frame.height - y - 1
                    for x in 0..<frame.width {
                        let offset = (row * frame.width + x) * 4
                        if frame.bgra[offset] > 8 || frame.bgra[offset + 1] > 8 || frame.bgra[offset + 2] > 8 {
                            count += 1; left = min(left, x); right = max(right, x)
                            top = min(top, y); bottom = max(bottom, y)
                        }
                    }
                }
                try attachJSON(["pose": pose.name, "source": label, "nativeTime": pose.nativeTime,
                    "assetSHA256": label == "source" ? Fixture.sourceHash : Fixture.assetHash,
                    "nonBackgroundPixels": count, "pixelBounds": [left, top, right, bottom],
                    "headRootLocalY": 0.125, "meshScale": [1.07, 1, 1]],
                    name: "ReplayXI-Static114-\(pose.name)-\(label).json")
                guard count > 1_000, count < 512 * 512 * 7 / 10,
                      left > 4, top > 4, right < 507, bottom < 507 else {
                    throw ReplayRealityRendererAudit.Failure.unsupported("Static head is empty/clipped; no PNG exported")
                }
                if label == "source" { sourcePixels = frame.bgra }
                else { XCTAssertNotEqual(frame.bgra, sourcePixels, "Different geometry must not render as a reused source") }
                let data = try ReplayRealityRendererAudit.png(frame, calibration: calibration)
                let attachment = XCTAttachment(data: data, uniformTypeIdentifier: "public.png")
                attachment.name = "ReplayXI-Static114-\(pose.name)-\(label).png"
                attachment.lifetime = .keepAlways
                add(attachment)
            }
        }
    }

    private func renderCalibration() async throws -> ReplayRealityRendererAudit.Frame {
        let root = Entity()
        let space = try XCTUnwrap(CGColorSpace(name: CGColorSpace.sRGB))
        for (index, bytes) in ReplayRealityRendererAudit.swatches.enumerated() {
            let colour = try XCTUnwrap(CGColor(colorSpace: space, components: bytes.map { CGFloat($0) / 255 } + [1]))
            let material = UnlitMaterial(color: UIColor(cgColor: colour), applyPostProcessToneMap: false)
            let swatch = ModelEntity(mesh: .generateBox(size: [1.2, 0.6, 0.01]), materials: [material])
            swatch.position = ReplayRealityRendererAudit.swatchPosition(index)
            root.addChild(swatch)
        }
        let camera = PerspectiveCamera()
        camera.camera = PerspectiveCameraComponent(near: 0.05, far: 10, fieldOfViewInDegrees: 90)
        camera.position = [0, 0, 2]
        return try await render([root, camera], camera: camera, size: 256)
    }

    private func render(_ entities: [Entity], camera: Entity, size: Int) async throws -> ReplayRealityRendererAudit.Frame {
        let renderer = try RealityRenderer()
        renderer.entities.append(contentsOf: entities)
        renderer.activeCamera = camera
        renderer.cameraSettings.isToneMappingEnabled = true
        renderer.cameraSettings.antialiasing = .none
        renderer.cameraSettings.colorBackground = .color(CGColor(gray: 0, alpha: 1))
        let texture = try ReplayRealityRendererAudit.makeTexture(size: size)
        let output = try RealityRenderer.CameraOutput(.singleProjection(colorTexture: texture))
        let completion = expectation(description: "Static114 native GPU completion")
        let flag = ReplayStatic114Completion()
        try renderer.updateAndRender(deltaTime: 0, cameraOutput: output, onComplete: { _ in
            flag.finish(); completion.fulfill()
        })
        await fulfillment(of: [completion], timeout: 10)
        guard flag.isComplete else { throw ReplayRealityRendererAudit.Failure.unsupported("Static114 GPU timeout") }
        return try withExtendedLifetime(renderer) { try ReplayRealityRendererAudit.read(texture) }
    }

    private func triangles(_ indices: [Int]) -> [String: Int] {
        var result: [String: Int] = [:]
        for offset in stride(from: 0, to: indices.count, by: 3) {
            let triangle = Array(indices[offset..<offset + 3])
            let start = triangle.indices.min { triangle[$0] < triangle[$1] }!
            let key = (0..<3).map { String(triangle[(start + $0) % 3]) }.joined(separator: ",")
            result[key, default: 0] += 1
        }
        return result
    }

    private func attachJSON(_ object: [String: Any], name: String) throws {
        let data = try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
        let attachment = XCTAttachment(data: data, uniformTypeIdentifier: "public.json")
        attachment.name = name; attachment.lifetime = .keepAlways
        add(attachment)
    }
}
