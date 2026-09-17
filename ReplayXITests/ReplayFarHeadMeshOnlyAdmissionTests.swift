import CoreGraphics
import Foundation
import RealityKit
import UIKit
import XCTest
import simd
@testable import ReplayXI

private final class ReplayFar122Completion: @unchecked Sendable {
    private let lock = NSLock()
    private var completed = false
    func finish() { lock.withLock { completed = true } }
    var isComplete: Bool { lock.withLock { completed } }
}

/// Derived-only package comparison. Does not change bundled assets or providers.
@MainActor
final class ReplayFarHeadMeshOnlyAdmissionTests: XCTestCase {
    private typealias Fixture = ReplayStaticFarHeadFixture
    private static let candidateHash = "30b5213f5967da5fa2574f39dfe942b989fe94629994cd10ad7a739c45e32b3f"

    override func setUp() {
        super.setUp()
        ReplayFarAthleteHeadProvider.resetForTesting()
        ReplayAthleteHeadProvider.resetForTesting()
        ReplayFarAthletePaletteProvider.resetForTesting()
    }

    override func tearDown() {
        ReplayFarAthleteHeadProvider.resetForTesting()
        ReplayAthleteHeadProvider.resetForTesting()
        ReplayFarAthletePaletteProvider.resetForTesting()
        super.tearDown()
    }

    private func load() throws -> (Fixture.Loaded, ModelEntity) {
        let source = try Fixture.load() // Pins the exact frozen114 package and actual head-turn poses.
        let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent(".codex-derived/ReplayXI-Far122-MeshOnly-01/ReplayXIFar122Head.usdz")
        let values: URLResourceValues
        do { values = try url.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey]) }
        catch let error as NSError where error.domain == NSCocoaErrorDomain
            && [NSFileNoSuchFileError, NSFileReadNoSuchFileError].contains(error.code) {
            throw XCTSkip("Optional derived mesh-only122 package is absent")
        }
        guard values.isRegularFile == true, values.fileSize == 21_563 else {
            throw Fixture.Failure.invalid("Mesh-only122 fixture size/type changed")
        }
        _ = try Fixture.checked(Data(contentsOf: url, options: .mappedIfSafe), hash: Self.candidateHash)
        let root = try Entity.load(contentsOf: url)
        let models = Fixture.models(root)
        XCTAssertEqual(models.count, 1)
        let model = try XCTUnwrap(models.first)
        XCTAssertEqual(root.transform.matrix, matrix_identity_float4x4)
        XCTAssertEqual(model.transformMatrix(relativeTo: root), matrix_identity_float4x4)
        let component = try XCTUnwrap(model.model)
        return (source, ModelEntity(mesh: component.mesh, materials: component.materials))
    }

    func testChangedMeshOnlyFixtureFailsInsteadOfSkipping() {
        XCTAssertThrowsError(try Fixture.checked(Data([1, 2, 3]), hash: Self.candidateHash))
    }

    func testNativeMeshOnlyImportRetainsExactAttributesTopologyAndTangentBasis() throws {
        let (loaded, candidate) = try load()
        let source = loaded.candidate
        let a = try XCTUnwrap(source.model)
        let b = try XCTUnwrap(candidate.model)
        for component in [a, b] {
            let contents = component.mesh.contents
            XCTAssertEqual(contents.models.count, 1)
            XCTAssertEqual(contents.instances.count, 1)
            XCTAssertEqual(contents.instances.first?.model, contents.models.first?.id)
            XCTAssertEqual(contents.instances.first?.transform, matrix_identity_float4x4)
            XCTAssertTrue(contents.skeletons.isEmpty)
            XCTAssertEqual(component.materials.count, 1)
            XCTAssertTrue(component.materials.first is PhysicallyBasedMaterial)
        }
        for model in [source, candidate] {
            XCTAssertEqual(model.transform.matrix, matrix_identity_float4x4)
            XCTAssertTrue(model.jointNames.isEmpty)
            XCTAssertTrue(model.jointTransforms.isEmpty)
            XCTAssertTrue(model.availableAnimations.isEmpty)
        }
        let beforeParts = a.mesh.contents.models.flatMap { Array($0.parts) }
        let afterParts = b.mesh.contents.models.flatMap { Array($0.parts) }
        XCTAssertEqual(beforeParts.count, 1)
        XCTAssertEqual(afterParts.count, 1)
        let before = try XCTUnwrap(beforeParts.first)
        let after = try XCTUnwrap(afterParts.first)
        XCTAssertEqual(before.positions.count, 486)
        XCTAssertEqual(before.triangleIndices?.count, 749 * 3)
        XCTAssertEqual(after.materialIndex, before.materialIndex)
        XCTAssertEqual(after.materialIndex, 0)
        XCTAssertNil(before.skeletonID)
        XCTAssertNil(after.skeletonID)
        XCTAssertNil(before.jointInfluences)
        XCTAssertNil(after.jointInfluences)
        XCTAssertEqual(after.positions.elements, before.positions.elements)
        XCTAssertEqual(after.normals?.elements, before.normals?.elements)
        XCTAssertEqual(after.textureCoordinates?.elements, before.textureCoordinates?.elements)
        XCTAssertEqual(after.triangleIndices?.elements, before.triangleIndices?.elements)
        // The normal-map connection is the only plausible native tangent-generation
        // difference. Compare both presence and exact values, not just the mesh bounds.
        XCTAssertEqual(after.tangents?.elements, before.tangents?.elements)
        XCTAssertEqual(after.bitangents?.elements, before.bitangents?.elements)
        let boundsA = source.visualBounds(relativeTo: source)
        let boundsB = candidate.visualBounds(relativeTo: candidate)
        XCTAssertEqual(boundsA.min, boundsB.min)
        XCTAssertEqual(boundsA.max, boundsB.max)
        let oldMaterial = try XCTUnwrap(a.materials.first as? PhysicallyBasedMaterial)
        let newMaterial = try XCTUnwrap(b.materials.first as? PhysicallyBasedMaterial)
        XCTAssertNotNil(oldMaterial.baseColor.texture)
        XCTAssertNotNil(oldMaterial.normal.texture)
        XCTAssertNil(newMaterial.baseColor.texture)
        XCTAssertNil(newMaterial.normal.texture)
        XCTAssertEqual(newMaterial.roughness.scale, oldMaterial.roughness.scale)
        XCTAssertEqual(newMaterial.metallic.scale, oldMaterial.metallic.scale)
        try attachJSON([
            "sourceSHA256": Fixture.assetHash, "candidateSHA256": Self.candidateHash,
            "sourceBytes": 540_760, "candidateBytes": 21_563,
            "vertices": before.positions.count, "triangles": (before.triangleIndices?.count ?? 0) / 3,
            "sourceTangents": before.tangents?.count ?? 0, "candidateTangents": after.tangents?.count ?? 0,
            "sourceBitangents": before.bitangents?.count ?? 0, "candidateBitangents": after.bitangents?.count ?? 0,
            "exactPositionEquality": before.positions.elements == after.positions.elements,
            "exactNormalEquality": before.normals?.elements == after.normals?.elements,
            "exactUVEquality": before.textureCoordinates?.elements == after.textureCoordinates?.elements,
            "exactIndexEquality": before.triangleIndices?.elements == after.triangleIndices?.elements,
            "exactTangentEquality": before.tangents?.elements == after.tangents?.elements,
            "exactBitangentEquality": before.bitangents?.elements == after.bitangents?.elements,
            "boundsMin": [boundsB.min.x, boundsB.min.y, boundsB.min.z],
            "boundsMax": [boundsB.max.x, boundsB.max.y, boundsB.max.z],
            "nativeImportOnly": true, "memoryOrLoadingBenefitMeasured": false
        ], name: "ReplayXI-MeshOnly122-NativeImport.json")
    }

    func testSharedPaletteHeadTurnsAndRunningBodiesRetainExactCalibratedPixels() async throws {
        let (loaded, candidate) = try load()
        let probe = try ReplayRealityRendererAudit.probe(try await calibrationFrame())
        let matches = probe.candidates.filter { $0.maximumChannelError <= 4 }
        guard matches.count == 1, let calibration = matches.first else {
            throw ReplayRealityRendererAudit.Failure.unsupported("MeshOnly122 native calibration failed")
        }
        let attachment = XCTAttachment(data: try JSONEncoder().encode(calibration), uniformTypeIdentifier: "public.json")
        attachment.name = "ReplayXI-MeshOnly122-Calibration.json"
        attachment.lifetime = .keepAlways
        add(attachment)
        try ReplayAthleteHeadProvider.prewarm()
        let templates = [("source", loaded.candidate), ("candidate", candidate)]
        for (poseIndex, pose) in loaded.poses.enumerated() {
            let paletteIndex = poseIndex.isMultiple(of: 2) ? 0 : 4
            let material = try XCTUnwrap(ReplayAthleteHeadProvider.material(at: paletteIndex))
            var sourcePixels: [UInt8]?
            for (name, template) in templates {
                let component = try XCTUnwrap(template.model)
                let model = ModelEntity(mesh: component.mesh, materials: [material])
                let root = try Fixture.placed(model, pose: pose)
                let frame = try await litFrame(root, isHead: true)
                let count = try inspectAndAttach(frame, calibration: calibration,
                    name: "ReplayXI-MeshOnly122-head-\(pose.name)-\(name)",
                    minimumPixels: 1_000, maximumPixels: 512 * 512 * 7 / 10)
                if let sourcePixels {
                    let changed = zip(sourcePixels, frame.bgra).reduce(0) { $0 + ($1.0 == $1.1 ? 0 : 1) }
                    XCTAssertEqual(changed, 0, "Same geometry, placement and shared palette must render identically")
                    try attachJSON(["pose": pose.name, "nativeTime": pose.nativeTime, "palette": paletteIndex,
                        "comparedChannels": frame.bgra.count, "changedChannels": changed,
                        "nonBackgroundPixels": count, "sourceSHA256": Fixture.assetHash,
                        "candidateSHA256": Self.candidateHash], name: "ReplayXI-MeshOnly122-head-\(pose.name)-parity.json")
                } else { sourcePixels = frame.bgra }
            }
        }

        // The same physical head-root placement is also tested inside the current
        // seven-model far rig in two actual authored running poses. Only the head
        // mesh changes between paired frames; no motion/floor/camera is adjusted.
        try ReplayFarAthleteHeadProvider.prewarm()
        let scenario = try XCTUnwrap(DemoScenarios.scenario(for: .squadReplay))
        try ReplayAthleteFactory.prewarm(for: scenario.players, lods: [.far])
        for (playerID, time) in [("navy-rb", 11.691666666666666), ("red-lw", 14.083333333333334)] {
            let player = try XCTUnwrap(scenario.player(id: playerID))
            let rig = try ReplayAthleteFactory.make(for: player, lod: .far)
            let ball = scenario.ball.pose(at: time)
            ReplayAthleteMotion.update(rig, from: player, at: time,
                lookTargetWorldPosition: [ball.position.x, ball.height, ball.position.z], ballTrack: scenario.ball)
            let head = try XCTUnwrap(rig.root.findEntity(named: "head") as? ModelEntity)
            let material = try XCTUnwrap(head.model?.materials.first as? PhysicallyBasedMaterial)
            for name in ["left-leg", "right-leg", "left-arm", "right-arm"] {
                let limb = try XCTUnwrap(rig.root.findEntity(named: name) as? ModelEntity)
                let palette = try XCTUnwrap(limb.model?.materials.first as? SimpleMaterial)
                XCTAssertNotNil(palette.color.texture, "Far body palette must be prepared explicitly")
            }
            let originalTransform = head.transform
            var sourcePixels: [UInt8]?
            for (name, template) in templates {
                head.model = ModelComponent(mesh: try XCTUnwrap(template.model).mesh, materials: [material])
                XCTAssertEqual(head.transform, originalTransform)
                XCTAssertEqual(Fixture.models(rig.root).count, 7)
                let frame = try await litFrame(rig.root, isHead: false)
                let count = try inspectAndAttach(frame, calibration: calibration,
                    name: "ReplayXI-MeshOnly122-run-\(playerID)-\(name)",
                    minimumPixels: 2_000, maximumPixels: 512 * 512 / 2)
                if let sourcePixels {
                    let changed = zip(sourcePixels, frame.bgra).reduce(0) { $0 + ($1.0 == $1.1 ? 0 : 1) }
                    XCTAssertEqual(changed, 0, "Head package change must preserve the same running rig image")
                    try attachJSON(["playerID": playerID, "time": time, "changedChannels": changed,
                        "comparedChannels": frame.bgra.count, "nonBackgroundPixels": count,
                        "bodyModels": 7, "sourceSHA256": Fixture.assetHash, "candidateSHA256": Self.candidateHash],
                        name: "ReplayXI-MeshOnly122-run-\(playerID)-parity.json")
                } else { sourcePixels = frame.bgra }
            }
        }
    }

    private func litFrame(_ root: Entity, isHead: Bool) async throws -> ReplayRealityRendererAudit.Frame {
        let target: SIMD3<Float> = isHead ? [0, 0.12, 0] : [0, 0.9, 0]
        let key = DirectionalLight()
        key.light.intensity = 2_200
        key.look(at: target, from: [3, 4, 3], relativeTo: nil)
        let fill = DirectionalLight()
        fill.light.intensity = 500
        fill.look(at: target, from: [-3, 2, 2], relativeTo: nil)
        let camera = PerspectiveCamera()
        camera.camera = PerspectiveCameraComponent(near: isHead ? 0.01 : 0.05, far: isHead ? 5 : 20, fieldOfViewInDegrees: 40)
        camera.look(at: target, from: isHead ? [0.26, 0.26, 0.75] : [2.7, 1.5, 4], relativeTo: nil)
        return try await render([root, key, fill, camera], camera: camera, size: 512)
    }

    private func inspectAndAttach(_ frame: ReplayRealityRendererAudit.Frame,
                                  calibration: ReplayRealityRendererAudit.Calibration,
                                  name: String, minimumPixels: Int, maximumPixels: Int) throws -> Int {
        var count = 0, left = 512, top = 512, right = -1, bottom = -1
        for y in 0..<512 {
            let row = calibration.rawRowsAreTopFirst ? y : 511 - y
            for x in 0..<512 {
                let offset = (row * 512 + x) * 4
                if frame.bgra[offset] > 8 || frame.bgra[offset + 1] > 8 || frame.bgra[offset + 2] > 8 {
                    count += 1; left = min(left, x); right = max(right, x)
                    top = min(top, y); bottom = max(bottom, y)
                }
            }
        }
        guard count > minimumPixels, count < maximumPixels,
              left > 4, top > 4, right < 507, bottom < 507 else {
            throw ReplayRealityRendererAudit.Failure.unsupported("MeshOnly122 frame is empty/clipped")
        }
        let attachment = XCTAttachment(data: try ReplayRealityRendererAudit.png(frame, calibration: calibration),
                                       uniformTypeIdentifier: "public.png")
        attachment.name = name + ".png"; attachment.lifetime = .keepAlways
        add(attachment)
        return count
    }

    private func calibrationFrame() async throws -> ReplayRealityRendererAudit.Frame {
        let root = Entity()
        let space = try XCTUnwrap(CGColorSpace(name: CGColorSpace.sRGB))
        for (index, bytes) in ReplayRealityRendererAudit.swatches.enumerated() {
            let colour = try XCTUnwrap(CGColor(colorSpace: space, components: bytes.map { CGFloat($0) / 255 } + [1]))
            let material = UnlitMaterial(color: UIColor(cgColor: colour), applyPostProcessToneMap: false)
            let model = ModelEntity(mesh: .generateBox(size: [1.2, 0.6, 0.01]), materials: [material])
            model.position = ReplayRealityRendererAudit.swatchPosition(index)
            root.addChild(model)
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
        let completion = expectation(description: "MeshOnly122 native GPU completion")
        let flag = ReplayFar122Completion()
        try renderer.updateAndRender(deltaTime: 0, cameraOutput: output, onComplete: { _ in flag.finish(); completion.fulfill() })
        await fulfillment(of: [completion], timeout: 10)
        guard flag.isComplete else { throw ReplayRealityRendererAudit.Failure.unsupported("MeshOnly122 GPU timeout") }
        return try withExtendedLifetime(renderer) { try ReplayRealityRendererAudit.read(texture) }
    }

    private func attachJSON(_ value: [String: Any], name: String) throws {
        let attachment = XCTAttachment(data: try JSONSerialization.data(withJSONObject: value, options: [.sortedKeys]),
                                       uniformTypeIdentifier: "public.json")
        attachment.name = name; attachment.lifetime = .keepAlways
        add(attachment)
    }
}
