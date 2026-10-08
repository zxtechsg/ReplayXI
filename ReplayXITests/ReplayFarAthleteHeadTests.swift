import CoreGraphics
import Foundation
import RealityKit
import UIKit
import XCTest
@testable import ReplayXI

private final class ReplayFar116Completion: @unchecked Sendable {
    private let lock = NSLock()
    private var completed = false
    func finish() { lock.withLock { completed = true } }
    var isComplete: Bool { lock.withLock { completed } }
}

@MainActor
final class ReplayFarAthleteHeadTests: XCTestCase {
    override func setUp() {
        super.setUp()
        ReplayFarAthleteHeadProvider.resetForTesting()
        ReplayAthleteHeadProvider.resetForTesting()
    }

    override func tearDown() {
        ReplayFarAthleteHeadProvider.resetForTesting()
        ReplayAthleteHeadProvider.resetForTesting()
        super.tearDown()
    }

    private func fixture() throws -> (ReplayScenario, PlayerTrack) {
        let scenario = try XCTUnwrap(DemoScenarios.scenario(for: .squadReplay))
        return (scenario, try XCTUnwrap(scenario.player(id: "navy-rw")))
    }

    private func prepare() throws {
        try ReplayAthleteHeadProvider.prewarm()
        try ReplayFarAthleteHeadProvider.prewarm()
    }

    func testColdFarBuilderRetainsEllipsoidWithoutImplicitResourceLoads() throws {
        let (_, player) = try fixture()
        try ReplayAthleteFactory.prewarm(for: [player], lods: [.far])
        let rig = try ReplayAthleteFactory.make(for: player, lod: .far)
        XCTAssertFalse(ReplayFarAthleteHeadProvider.isPrewarmed)
        XCTAssertFalse(ReplayAthleteHeadProvider.isPrewarmed)
        XCTAssertEqual(ReplayFarAthleteHeadProvider.preparationAttemptCount, 0)
        XCTAssertEqual(ReplayFarAthleteHeadProvider.meshLoadCount, 0)
        XCTAssertEqual(rig.metrics, .init(modelEntities: 7, verticesPerInstance: 399, trianglesPerInstance: 574))
        XCTAssertEqual(rig.joints[.headRoot].position.y, 0.140)
        let head = try XCTUnwrap(rig.root.findEntity(named: "head") as? ModelEntity)
        XCTAssertTrue(try XCTUnwrap(head.model).materials.first is SimpleMaterial)
    }

    func testDependencyOrderCacheAndPaletteRecoveryDoNotReloadTheAsset() throws {
        for _ in 0..<3 {
            XCTAssertThrowsError(try ReplayFarAthleteHeadProvider.prewarm()) {
                XCTAssertEqual($0 as? ReplayFarAthleteHeadProvider.PreparationError, .materialsNotReady)
            }
        }
        XCTAssertEqual(ReplayFarAthleteHeadProvider.preparationAttemptCount, 0)
        try prepare()
        XCTAssertTrue(ReplayFarAthleteHeadProvider.isPrewarmed)
        let first = try XCTUnwrap(ReplayFarAthleteHeadProvider.make(appearance: .replayXI(index: 0)))
        let mesh = try XCTUnwrap(first.model).mesh
        for index in 0..<5 {
            let head = try XCTUnwrap(ReplayFarAthleteHeadProvider.make(appearance: .replayXI(index: index)))
            let component = try XCTUnwrap(head.model)
            let material = try XCTUnwrap(component.materials.first as? PhysicallyBasedMaterial)
            let shared = try XCTUnwrap(ReplayAthleteHeadProvider.material(at: index))
            XCTAssertTrue(component.mesh === mesh)
            XCTAssertEqual(try XCTUnwrap(material.baseColor.texture).resource, try XCTUnwrap(shared.baseColor.texture).resource)
            XCTAssertEqual(try XCTUnwrap(material.normal.texture).resource, try XCTUnwrap(shared.normal.texture).resource)
            XCTAssertEqual(head.scale, [1.07, 1, 1])
            XCTAssertEqual(head.name, "head")
            XCTAssertTrue(head.jointNames.isEmpty)
        }
        ReplayAthleteHeadProvider.resetForTesting()
        XCTAssertFalse(ReplayFarAthleteHeadProvider.isPrewarmed)
        XCTAssertNil(ReplayFarAthleteHeadProvider.make(appearance: .replayXI(index: 0)))
        try ReplayAthleteHeadProvider.prewarm()
        for _ in 0..<20 {
            try ReplayFarAthleteHeadProvider.prewarm()
            let head = try XCTUnwrap(ReplayFarAthleteHeadProvider.make(appearance: .replayXI(index: 0)))
            XCTAssertTrue(try XCTUnwrap(head.model).mesh === mesh)
        }
        XCTAssertEqual(ReplayFarAthleteHeadProvider.preparationAttemptCount, 1)
        XCTAssertEqual(ReplayFarAthleteHeadProvider.meshLoadCount, 1)
    }

    func testFailedPreparationIsMemoizedAndPreservesTheOldFarFallback() throws {
        try ReplayAthleteHeadProvider.prewarm()
        ReplayFarAthleteHeadProvider.resetForTesting(forceFailure: true)
        for _ in 0..<3 { XCTAssertThrowsError(try ReplayFarAthleteHeadProvider.prewarm()) }
        XCTAssertFalse(ReplayFarAthleteHeadProvider.isPrewarmed)
        XCTAssertEqual(ReplayFarAthleteHeadProvider.preparationAttemptCount, 1)
        XCTAssertEqual(ReplayFarAthleteHeadProvider.meshLoadCount, 0)
        let (_, player) = try fixture()
        let rig = try ReplayAthleteFactory.make(for: player, lod: .far)
        XCTAssertEqual(rig.metrics, .init(modelEntities: 7, verticesPerInstance: 399, trianglesPerInstance: 574))
        XCTAssertEqual(rig.joints[.headRoot].position.y, 0.140)
        XCTAssertNil(ReplayFarAthleteHeadProvider.make(appearance: .replayXI(index: 2)))
    }

    func testWrongSizeAndChangedAssetBytesAreRejected() {
        XCTAssertThrowsError(try ReplayFarAthleteHeadProvider.validateAssetData(Data([1, 2, 3]))) {
            XCTAssertEqual($0 as? ReplayFarAthleteHeadProvider.PreparationError, .invalidAsset)
        }
        XCTAssertThrowsError(try ReplayFarAthleteHeadProvider.validateAssetData(
            Data(repeating: 0, count: ReplayFarAthleteHeadProvider.expectedBytes))) {
            XCTAssertEqual($0 as? ReplayFarAthleteHeadProvider.PreparationError, .hashMismatch)
        }
    }

    func testActualFarGeometryUsesOneStaticHeadWithinTheUnchangedBudget() throws {
        try prepare()
        let (_, player) = try fixture()
        let rig = try ReplayAthleteFactory.make(for: player, lod: .far)
        let models = ReplayStaticFarHeadFixture.models(rig.root)
        let parts = models.flatMap { model in model.model!.mesh.contents.models.flatMap { Array($0.parts) } }
        XCTAssertEqual(models.count, 7)
        XCTAssertEqual(parts.reduce(0) { $0 + $1.positions.count }, 820)
        XCTAssertEqual(parts.reduce(0) { $0 + ($1.triangleIndices?.count ?? 0) / 3 }, 1_225)
        XCTAssertEqual(rig.metrics, .init(modelEntities: 7, verticesPerInstance: 820, trianglesPerInstance: 1_225))
        XCTAssertTrue(rig.metrics.fits(ReplayAthleteLOD.far.budget))
        XCTAssertTrue(models.allSatisfy { $0.jointNames.isEmpty && $0.availableAnimations.isEmpty })
        XCTAssertEqual(rig.joints[.headRoot].position.y, 0.125)
        XCTAssertNil(rig.root.findEntity(named: "neck-shell"))
        XCTAssertNotNil(rig.joints.farFloorSupport)
        let head = try XCTUnwrap(rig.root.findEntity(named: "head") as? ModelEntity)
        let contents = try XCTUnwrap(head.model).mesh.contents
        XCTAssertEqual(contents.models.count, 1)
        XCTAssertEqual(contents.instances.count, 1)
        XCTAssertEqual(contents.instances.first?.model, contents.models.first?.id)
        XCTAssertEqual(contents.instances.first?.transform, matrix_identity_float4x4)
    }

    func testNearAndMidMeshesMetricsAndTransformsAreUnchangedByFarAdmission() throws {
        try ReplayAthleteHeadProvider.prewarm()
        let (_, player) = try fixture()
        let baseline = try [ReplayAthleteLOD.near, .mid].map { try ReplayAthleteFactory.make(for: player, lod: $0) }
        try ReplayFarAthleteHeadProvider.prewarm()
        for before in baseline {
            let after = try ReplayAthleteFactory.make(for: player, lod: before.lod)
            XCTAssertEqual(after.metrics, before.metrics)
            for joint in ReplayAthleteJoint.allCases { XCTAssertEqual(after.joints[joint].transform, before.joints[joint].transform) }
            let first = ReplayStaticFarHeadFixture.models(before.root)
            let second = ReplayStaticFarHeadFixture.models(after.root)
            XCTAssertEqual(first.map(\.name), second.map(\.name))
            for (a, b) in zip(first, second) {
                XCTAssertTrue(try XCTUnwrap(a.model).mesh === XCTUnwrap(b.model).mesh)
                XCTAssertEqual(a.transform, b.transform)
            }
        }
    }

    func testFarHeadFollowsGazeRewindsAndPreservesAllOtherJointAndFloorMotion() throws {
        let (scenario, _) = try fixture()
        let cases: [(String, [Double])] = [
            ("navy-rw", [0, 5, 12, 13.6, 18, 28]),
            ("navy-rb", [11.691666666666666]),
            ("red-lw", [14.083333333333334])
        ]
        let samples = try cases.map { id, times in
            let player = try XCTUnwrap(scenario.player(id: id))
            return (player, try ReplayAthleteFactory.make(for: player, lod: .far), times)
        }
        try prepare()
        for (player, fallback, times) in samples {
            let rig = try ReplayAthleteFactory.make(for: player, lod: .far)
            let head = try XCTUnwrap(rig.root.findEntity(named: "head") as? ModelEntity)
            let part = try XCTUnwrap(head.model?.mesh.contents.models.first?.parts.first)
            let minimum = try XCTUnwrap(part.positions.elements.map(\.y).min())
            let neckline = part.positions.elements.filter { $0.y <= minimum + 0.012 }
            var poses: [Double: simd_float4x4] = [:]
            for time in times + times.reversed() {
                let ball = scenario.ball.pose(at: time)
                let target: SIMD3<Float> = [ball.position.x, ball.height, ball.position.z]
                ReplayAthleteMotion.update(fallback, from: player, at: time, lookTargetWorldPosition: target, ballTrack: scenario.ball)
                ReplayAthleteMotion.update(rig, from: player, at: time, lookTargetWorldPosition: target, ballTrack: scenario.ball)
                for joint in ReplayAthleteJoint.allCases where joint != .headRoot {
                    XCTAssertEqual(rig.joints[joint].transform, fallback.joints[joint].transform, joint.rawValue)
                }
                XCTAssertEqual(rig.joints[.headRoot].orientation, fallback.joints[.headRoot].orientation)
                let transform = head.transformMatrix(relativeTo: rig.root)
                if let first = poses[time] { XCTAssertEqual(transform, first) }
                poses[time] = transform
                let collar = head.transformMatrix(relativeTo: rig.joints[.spine])
                let lowest = try XCTUnwrap(neckline.map { (collar * SIMD4<Float>($0, 1)).y }.min())
                XCTAssertLessThanOrEqual(lowest, 0.580, player.id)
                XCTAssertGreaterThan(lowest, 0.48, player.id)
            }
            if player.id == "navy-rw" { XCTAssertNotEqual(poses[0], poses[18]) }
        }
        XCTAssertEqual(ReplayFarAthleteHeadProvider.meshLoadCount, 1)
    }

    func testNativeFullFarBodyAndCollarWithCalibratedPixels() async throws {
        let probe = try ReplayRealityRendererAudit.probe(try await calibrationFrame())
        let matches = probe.candidates.filter { $0.maximumChannelError <= 4 }
        guard matches.count == 1, let calibration = matches.first else {
            throw ReplayRealityRendererAudit.Failure.unsupported("Far116 calibration failed")
        }
        let calibrationAttachment = XCTAttachment(data: try JSONEncoder().encode(calibration), uniformTypeIdentifier: "public.json")
        calibrationAttachment.name = "ReplayXI-Far116-Calibration.json"
        calibrationAttachment.lifetime = .keepAlways
        add(calibrationAttachment)
        let (scenario, _) = try fixture()
        let cases: [(String, Double)] = [
            ("navy-rw", 10), ("navy-rw", 12.1),
            ("navy-rb", 11.691666666666666), ("red-lw", 14.083333333333334)
        ]
        let samples = try cases.map { id, time in
            let player = try XCTUnwrap(scenario.player(id: id))
            return (player, try ReplayAthleteFactory.make(for: player, lod: .far), time)
        }
        try prepare()
        for (player, fallback, time) in samples {
            let rig = try ReplayAthleteFactory.make(for: player, lod: .far)
            let ball = scenario.ball.pose(at: time)
            for (name, instance) in [("fallback", fallback), ("face", rig)] {
                ReplayAthleteMotion.update(instance, from: player, at: time,
                    lookTargetWorldPosition: [ball.position.x, ball.height, ball.position.z], ballTrack: scenario.ball)
                let key = DirectionalLight()
                key.light.intensity = 2_200
                key.look(at: [0, 0.9, 0], from: [3, 4, 3], relativeTo: nil)
                let fill = DirectionalLight()
                fill.light.intensity = 500
                fill.look(at: [0, 0.9, 0], from: [-3, 2, 2], relativeTo: nil)
                let camera = PerspectiveCamera()
                camera.camera = PerspectiveCameraComponent(near: 0.05, far: 20, fieldOfViewInDegrees: 40)
                camera.look(at: [0, 0.9, 0], from: [2.7, 1.5, 4], relativeTo: nil)
                let frame = try await render([instance.root, key, fill, camera], camera: camera, size: 512)
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
                XCTAssertGreaterThan(count, 2_000)
                XCTAssertLessThan(count, 512 * 512 / 2)
                XCTAssertGreaterThan(left, 4); XCTAssertGreaterThan(top, 4)
                XCTAssertLessThan(right, 507); XCTAssertLessThan(bottom, 507)
                let locomotion = player.locomotion(at: time)
                let evidence: [String: Any] = ["playerID": player.id, "time": time, "mode": name, "pixels": count,
                    "speedMetresPerSecond": locomotion.speedMetresPerSecond, "locomotionState": String(describing: locomotion.state),
                    "bounds": [left, top, right, bottom], "modelEntities": instance.metrics.modelEntities,
                    "vertices": instance.metrics.verticesPerInstance, "triangles": instance.metrics.trianglesPerInstance]
                let metadata = XCTAttachment(data: try JSONSerialization.data(withJSONObject: evidence, options: [.sortedKeys]),
                    uniformTypeIdentifier: "public.json")
                metadata.name = "ReplayXI-Far116-\(player.id)-\(time)-\(name).json"; metadata.lifetime = .keepAlways; add(metadata)
                let png = XCTAttachment(data: try ReplayRealityRendererAudit.png(frame, calibration: calibration), uniformTypeIdentifier: "public.png")
                png.name = "ReplayXI-Far116-\(player.id)-\(time)-\(name).png"; png.lifetime = .keepAlways; add(png)
            }
        }
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
        let completion = expectation(description: "Far116 native GPU completion")
        let flag = ReplayFar116Completion()
        try renderer.updateAndRender(deltaTime: 0, cameraOutput: output, onComplete: { _ in flag.finish(); completion.fulfill() })
        await fulfillment(of: [completion], timeout: 10)
        guard flag.isComplete else { throw ReplayRealityRendererAudit.Failure.unsupported("Far116 GPU timeout") }
        return try withExtendedLifetime(renderer) { try ReplayRealityRendererAudit.read(texture) }
    }
}
