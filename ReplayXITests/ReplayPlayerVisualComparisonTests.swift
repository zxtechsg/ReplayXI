import CoreGraphics
import CryptoKit
import Foundation
import Metal
import RealityKit
import UIKit
import XCTest
@testable import ReplayXI

private final class ReplayPlayerCaptureCompletion: @unchecked Sendable {
    private let lock = NSLock()
    private var complete = false
    func finish() { lock.withLock { complete = true } }
    var isComplete: Bool { lock.withLock { complete } }
}

/// Matched native pixels, not a Blender preview or a headset/UI screenshot.
/// The final far pair compares current cold fallback with articulated body +
/// kit. Face, limb palette, pose, physical scale, camera and lights stay matched.
@MainActor
final class ReplayPlayerVisualComparisonTests: XCTestCase {
    private let time: TimeInterval = 13.6
    private let playerIDs = ["navy-rb", "red-lb"]
    private let views: [(name: String, direction: Float)] = [("front", 1), ("back", -1)]

    func testCapturesBothTeamsColdAndArticulatedFarWithMatchedNativeViews() async throws {
        resetProviders()
        defer { resetProviders() }
        let scenario = try XCTUnwrap(DemoScenarios.scenario(for: .squadReplay))
        let players = try playerIDs.map { try XCTUnwrap(scenario.player(id: $0)) }
        XCTAssertEqual(Set(players.map(\.team)), Set([FootballTeam.home, .away]))
        try ReplayAthleteFactory.prewarm(for: players, lods: [.far])
        try ReplayAthleteHeadProvider.prewarm()
        try ReplayFarAthleteHeadProvider.prewarm()
        XCTAssertFalse(ReplayArticulatedFarProvider.isPrewarmed)
        let baseline = try players.map { try ReplayAthleteFactory.make(for: $0, lod: .far) }
        XCTAssertTrue(baseline.allSatisfy { $0.joints.articulatedFar == nil })
        try ReplayArticulatedFarProvider.prewarm()
        try ReplayArticulatedFarKitProvider.prewarm()
        XCTAssertEqual(ReplayArticulatedFarKitProvider.cachedTextureCount, 6)
        let articulated = try players.map { try ReplayAthleteFactory.make(for: $0, lod: .far) }
        XCTAssertTrue(articulated.allSatisfy { $0.joints.articulatedFar != nil })
        let calibration = try await calibrate()
        var comparisonRows: [Comparison] = []
        let ball = scenario.ball.pose(at: time)
        let look = SIMD3<Float>(ball.position.x, ball.height, ball.position.z)
        for (index, player) in players.enumerated() {
            let old = baseline[index], new = articulated[index]
            XCTAssertEqual(old.root.transform, new.root.transform)
            XCTAssertEqual(old.root.scale, SIMD3<Float>(repeating: 1))
            XCTAssertEqual(old.configuration, new.configuration)
            let oldHead = try XCTUnwrap(old.root.findEntity(named: "head") as? ModelEntity)
            let newHead = try XCTUnwrap(new.root.findEntity(named: "head") as? ModelEntity)
            let retainedHeadMesh = try XCTUnwrap(oldHead.model?.mesh)
            XCTAssertTrue(newHead.model?.mesh === retainedHeadMesh)
            XCTAssertEqual(oldHead.scale, newHead.scale)
            ReplayAthleteMotion.update(old, from: player, at: time,
                lookTargetWorldPosition: look, ballTrack: scenario.ball)
            ReplayAthleteMotion.update(new, from: player, at: time,
                lookTargetWorldPosition: look, ballTrack: scenario.ball)
            XCTAssertEqual(allModels(in: old.root).filter { !$0.jointNames.isEmpty }.count, 0)
            XCTAssertEqual(allModels(in: new.root).filter { $0.jointNames.count == 3 }.count, 4)
            XCTAssertEqual(new.metrics.modelEntities, 7)
            XCTAssertEqual(new.metrics.verticesPerInstance, 1_464)
            XCTAssertEqual(new.metrics.trianglesPerInstance, 2_495)
            var identities = ["head": ReplayFarAthleteHeadProvider.expectedSHA256,
                              "articulatedBody": ReplayArticulatedFarProvider.expectedSHA256]
            for part in ["torso", "shorts"] {
                let entity = try XCTUnwrap(new.root.findEntity(named: part) as? ModelEntity)
                let material = try XCTUnwrap(entity.model?.materials.first as? PhysicallyBasedMaterial)
                XCTAssertNotNil(material.baseColor.texture)
                let name = "ReplayXIFar\(player.team == .home ? "Home" : "Away")\(part.capitalized)"
                identities[name] = try bundledPNGHash(name)
            }
            for view in views {
                let cold = try await capture(old.root, player: player, variant: "far-cold",
                    view: view, calibration: calibration,
                    identities: ["head": ReplayFarAthleteHeadProvider.expectedSHA256])
                let upgraded = try await capture(new.root, player: player, variant: "far-articulated-kit",
                    view: view, calibration: calibration,
                    identities: identities)
                let difference = differentPixels(cold, upgraded)
                XCTAssertGreaterThan(difference, 0, "Imported articulation must affect actual rendered pixels")
                comparisonRows.append(Comparison(playerID: player.id, view: view.name,
                    first: "far-cold", second: "far-articulated-kit", differentRGBPixels: difference))
            }
        }
        try attachJSON(comparisonRows, named: "ReplayXI-BothTeams-Far-Comparison.json")
    }

    func testCapturesBothTeamsNearAndLowKitRefinementWithMatchedNativeViews() async throws {
        let fixture = try kitFixture()
        resetProviders()
        defer { resetProviders() }
        try ReplaySkinnedAthleteProvider.prewarm()
        try ReplaySkinnedAthleteProvider.prewarmLowDetail()
        let scenario = try XCTUnwrap(DemoScenarios.scenario(for: .squadReplay))
        let calibration = try await calibrate()
        let ball = scenario.ball.pose(at: time)
        let look = SIMD3<Float>(ball.position.x, ball.height, ball.position.z)
        var comparisons: [Comparison] = []
        for playerID in playerIDs {
            let player = try XCTUnwrap(scenario.player(id: playerID))
            let skinIndex = (player.shirtNumber + (player.team == .away ? 2 : 0)) % 5
            let kitName = "ReplayXIRocketbox\(player.team == .home ? "Home" : "Away")Skin\(skinIndex)"
            let entry = try XCTUnwrap(fixture.manifest.textures.first { $0.file == kitName + ".png" })
            XCTAssertEqual(entry.size, [512, 512])
            let paletteStages = [("baseline", entry.beforeSHA256), ("refined", entry.afterSHA256)]
            let palettes = try paletteStages.map { stage, expectedHash in
                let url = fixture.root.appendingPathComponent(stage).appendingPathComponent(entry.file)
                let data = try Data(contentsOf: url)
                let actual = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
                guard actual == expectedHash else {
                    throw ReplayRealityRendererAudit.Failure.unsupported("Present kit fixture has wrong SHA: \(stage)/\(entry.file)")
                }
                return (name: stage, texture: try TextureResource.load(contentsOf: url), hash: actual, data: data)
            }
            // Xcode may re-encode a copied PNG. Keep the source fixture's
            // strict file identity, but compare packaged images by exact
            // canonical pixels and dimensions, never their compressed bytes.
            let refined = try XCTUnwrap(palettes.first { $0.name == "refined" })
            let shippingData = try Data(contentsOf: bundledPNGURL(kitName))
            let shippingRGBA = try ReplayArticulatedFarKitProvider.canonicalRGBA(
                data: shippingData, expectedSize: 512, maximumEncodedBytes: 1_048_576)
            let refinedRGBA = try ReplayArticulatedFarKitProvider.canonicalRGBA(
                data: refined.data, expectedSize: 512, maximumEncodedBytes: 1_048_576)
            XCTAssertEqual(shippingRGBA.count, 512 * 512 * 4)
            XCTAssertTrue(shippingRGBA == refinedRGBA,
                          "Shipping kit decoded pixels must exactly match the pinned refined input")
            let shippingEncodedHash = SHA256.hash(data: shippingData).map { String(format: "%02x", $0) }.joined()
            let shippingPixelHash = SHA256.hash(data: shippingRGBA).map { String(format: "%02x", $0) }.joined()
            let action = ReplayAthleteMotion.ballActionPose(for: player, ballTrack: scenario.ball, at: time)
            for detail in [ReplaySkinnedAthleteProvider.Detail.near, .lowDetail] {
                let instance = try ReplaySkinnedAthleteProvider.make(for: player, detail: detail)
                XCTAssertTrue(instance.update(at: time, track: player, locomotion: player.locomotion(at: time),
                    lookTarget: look, ballAction: action))
                XCTAssertEqual(instance.root.scale, SIMD3<Float>(repeating: 1))
                XCTAssertEqual(instance.model.jointNames.count, 80)
                XCTAssertTrue(instance.front.isEnabledInHierarchy)
                XCTAssertTrue(instance.back.isEnabledInHierarchy)
                let name = detail == .near ? "near-kit" : "low-kit"
                let bodyHash = detail == .near ? ReplaySkinnedAthleteProvider.assetSHA256
                    : ReplaySkinnedAthleteProvider.lowAssetSHA256
                let retainedMesh = try XCTUnwrap(instance.model.model?.mesh)
                let retainedPose = instance.model.jointTransforms
                let retainedRoot = instance.root.transform
                var originalFrames: [String: ReplayRealityRendererAudit.Frame] = [:]
                for palette in palettes {
                    var component = try XCTUnwrap(instance.model.model)
                    var body = try XCTUnwrap(component.materials[0] as? PhysicallyBasedMaterial)
                    // Replace only colour. The same actual clone retains the
                    // body normal, roughness, head, skeleton and posed geometry.
                    body.baseColor = .init(tint: .white, texture: .init(palette.texture))
                    component.materials[0] = body
                    instance.model.model = component
                    XCTAssertTrue(instance.model.model?.mesh === retainedMesh)
                    XCTAssertEqual(instance.model.jointTransforms, retainedPose)
                    XCTAssertEqual(instance.root.transform, retainedRoot)
                    for view in views {
                        let variant = name + "-" + palette.name
                        let frame = try await capture(instance.root, player: player, variant: variant,
                            view: view, calibration: calibration,
                            identities: ["body": bodyHash, kitName: palette.hash,
                                         "bundledKitPNG": shippingEncodedHash,
                                         "bundledKitRGBA8_sRGB_512": shippingPixelHash,
                                         "kitFixtureManifest": Self.kitManifestSHA256])
                        if palette.name == "baseline" {
                            originalFrames[view.name] = frame
                        } else {
                            let original = try XCTUnwrap(originalFrames[view.name])
                            let difference = differentPixels(original, frame)
                            XCTAssertGreaterThan(difference, 0, "Refined kit must change actual visible pixels")
                            comparisons.append(Comparison(playerID: playerID, view: view.name,
                                first: name + "-baseline", second: variant, differentRGBPixels: difference))
                        }
                    }
                }
            }
        }
        try attachJSON(comparisons, named: "ReplayXI-BothTeams-NearLow-Kit-Comparison.json")
    }

    private static let kitManifestSHA256 = "035774ad3dcf9498c2e3321a98f02dd296a1c5317763d3c21de05b7f48974637"

    private struct KitManifest: Decodable {
        struct Texture: Decodable {
            let file: String, beforeSHA256: String, afterSHA256: String
            let size: [Int]
        }
        let schemaVersion: Int
        let sourceAssetSHA256: String
        let geometryUnchanged: Bool, normalMapsUnchanged: Bool
        let textures: [Texture]
    }

    private struct Comparison: Encodable {
        let playerID: String, view: String, first: String, second: String
        let differentRGBPixels: Int
    }

    private struct ModelReport: Encodable {
        let name: String
        let vertices: Int, triangles: Int, materials: Int, joints: Int
        let jointLocalMatricesColumnMajor: [[Float]]
    }

    private struct CaptureReport: Encodable {
        let scope = "Native RealityRenderer output of actual provider models at authored replay time, in body-local coordinates. No match-world heading, UI, headset, comfort or performance claim. Geometry bounds are RealityKit model bounds and may not describe deformed skin; raster bounds come from actual pixels."
        let playerID: String, team: String, variant: String, view: String
        let shirtNumber: Int
        let replayTime: Double
        let width = 512, height = 512
        let pixelFormat = "bgra8Unorm_srgb"
        let rendererToneMapping = true
        let calibrationMaterialInitializerToneMapping = false
        let calibration: ReplayRealityRendererAudit.Calibration
        let cameraPosition: [Float], cameraTarget: [Float], cameraMatrixColumnMajor: [Float]
        let cameraVerticalFOV: Float = 40
        let rootScale: [Float], rootMatrixColumnMajor: [Float]
        let modelBoundsMin: [Float], modelBoundsMax: [Float]
        let nonBackgroundPixels: Int, rasterBoundsLeftTopRightBottom: [Int]
        let assetSHA256: [String: String]
        let models: [ModelReport]
    }

    private func capture(_ avatar: Entity, player: PlayerTrack, variant: String,
                         view: (name: String, direction: Float),
                         calibration: ReplayRealityRendererAudit.Calibration,
                         identities: [String: String]) async throws -> ReplayRealityRendererAudit.Frame {
        let direction = view.direction
        let target = SIMD3<Float>(0, 0.9, 0)
        let position = SIMD3<Float>(2.7 * direction, 1.5, 4 * direction)
        let camera = PerspectiveCamera()
        camera.camera = PerspectiveCameraComponent(near: 0.05, far: 20, fieldOfViewInDegrees: 40)
        camera.look(at: target, from: position, relativeTo: nil)
        let key = DirectionalLight()
        key.light.intensity = 2_200
        key.look(at: target, from: [3 * direction, 4, 3 * direction], relativeTo: nil)
        let fill = DirectionalLight()
        fill.light.intensity = 500
        fill.look(at: target, from: [-3 * direction, 2, 2 * direction], relativeTo: nil)
        let frame = try await render(entities: [avatar, key, fill, camera], camera: camera, size: 512)
        var count = 0, left = frame.width, top = frame.height, right = -1, bottom = -1
        for y in 0..<frame.height {
            for x in 0..<frame.width {
                let pixel = frame.rgba(x: x, y: y, topFirst: calibration.rawRowsAreTopFirst)
                if pixel[0] > 8 || pixel[1] > 8 || pixel[2] > 8 {
                    count += 1
                    left = min(left, x); right = max(right, x)
                    top = min(top, y); bottom = max(bottom, y)
                }
            }
        }
        let bounds = avatar.visualBounds(relativeTo: nil)
        XCTAssertTrue(vector(bounds.min).allSatisfy(\.isFinite))
        XCTAssertTrue(vector(bounds.max).allSatisfy(\.isFinite))
        let models = allModels(in: avatar).map { model -> ModelReport in
            let parts = model.model?.mesh.contents.models.flatMap { Array($0.parts) } ?? []
            return ModelReport(name: model.name, vertices: parts.reduce(0) { $0 + $1.positions.count },
                triangles: parts.reduce(0) { $0 + ($1.triangleIndices?.count ?? 0) / 3 },
                materials: model.model?.materials.count ?? 0, joints: model.jointNames.count,
                jointLocalMatricesColumnMajor: model.jointTransforms.map { matrix($0.matrix) })
        }
        let report = CaptureReport(playerID: player.id, team: player.team.rawValue,
            variant: variant, view: view.name, shirtNumber: player.shirtNumber, replayTime: time,
            calibration: calibration, cameraPosition: vector(position), cameraTarget: vector(target),
            cameraMatrixColumnMajor: matrix(camera.transformMatrix(relativeTo: nil)),
            rootScale: vector(avatar.scale), rootMatrixColumnMajor: matrix(avatar.transformMatrix(relativeTo: nil)),
            modelBoundsMin: vector(bounds.min), modelBoundsMax: vector(bounds.max),
            nonBackgroundPixels: count, rasterBoundsLeftTopRightBottom: [left, top, right, bottom],
            assetSHA256: identities, models: models)
        let name = "ReplayXI-PlayerCompare-\(player.team.rawValue)-\(variant)-\(view.name)"
        try attachJSON(report, named: name + ".json")
        guard count > 500, count < frame.width * frame.height * 7 / 10,
              left > 4, top > 4, right < frame.width - 5, bottom < frame.height - 5 else {
            throw ReplayRealityRendererAudit.Failure.unsupported("\(name) is empty or clipped; PNG withheld")
        }
        let attachment = XCTAttachment(data: try ReplayRealityRendererAudit.png(frame, calibration: calibration),
                                       uniformTypeIdentifier: "public.png")
        attachment.name = name + ".png"
        attachment.lifetime = .keepAlways
        add(attachment)
        return frame
    }

    private func calibrate() async throws -> ReplayRealityRendererAudit.Calibration {
        let root = Entity()
        let space = try XCTUnwrap(CGColorSpace(name: CGColorSpace.sRGB))
        for (index, bytes) in ReplayRealityRendererAudit.swatches.enumerated() {
            let color = try XCTUnwrap(CGColor(colorSpace: space, components: bytes.map { CGFloat($0) / 255 } + [1]))
            let swatch = ModelEntity(mesh: .generateBox(size: [1.2, 0.6, 0.01]),
                materials: [UnlitMaterial(color: UIColor(cgColor: color), applyPostProcessToneMap: false)])
            swatch.position = ReplayRealityRendererAudit.swatchPosition(index)
            root.addChild(swatch)
        }
        let camera = PerspectiveCamera()
        camera.camera = PerspectiveCameraComponent(near: 0.05, far: 10, fieldOfViewInDegrees: 90)
        camera.position = [0, 0, 2]
        let probe = try ReplayRealityRendererAudit.probe(await render(entities: [root, camera], camera: camera, size: 256))
        try attachJSON(probe, named: "ReplayXI-PlayerCompare-Calibration.json")
        let matches = probe.candidates.filter { $0.maximumChannelError <= 4 }
        guard matches.count == 1, let calibration = matches.first else {
            throw ReplayRealityRendererAudit.Failure.unsupported("Player comparison requires unique row/channel/gamut calibration")
        }
        return calibration
    }

    private func render(entities: [Entity], camera: Entity, size: Int) async throws -> ReplayRealityRendererAudit.Frame {
        let renderer = try RealityRenderer()
        renderer.entities.append(contentsOf: entities)
        renderer.activeCamera = camera
        renderer.cameraSettings.isToneMappingEnabled = true
        renderer.cameraSettings.antialiasing = .none
        renderer.cameraSettings.colorBackground = .color(CGColor(gray: 0, alpha: 1))
        let texture = try ReplayRealityRendererAudit.makeTexture(size: size)
        let output = try RealityRenderer.CameraOutput(.singleProjection(colorTexture: texture))
        let completion = expectation(description: "Player comparison native GPU completion")
        let flag = ReplayPlayerCaptureCompletion()
        try renderer.updateAndRender(deltaTime: 0, cameraOutput: output, onComplete: { _ in
            flag.finish()
            completion.fulfill()
        })
        await fulfillment(of: [completion], timeout: 10)
        guard flag.isComplete else {
            throw ReplayRealityRendererAudit.Failure.unsupported("Player comparison render exceeded ten seconds")
        }
        return try withExtendedLifetime(renderer) { try ReplayRealityRendererAudit.read(texture) }
    }

    private func kitFixture() throws -> (root: URL, manifest: KitManifest) {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent(".codex-derived/ReplayXI-Players124-Kits-02")
        guard FileManager.default.fileExists(atPath: root.path) else {
            throw XCTSkip("Optional before/after kit fixture is absent; no comparison evidence claimed")
        }
        let data = try Data(contentsOf: root.appendingPathComponent("manifest.json"))
        let actual = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        guard actual == Self.kitManifestSHA256 else {
            throw ReplayRealityRendererAudit.Failure.unsupported("Present kit fixture manifest has changed")
        }
        let manifest = try JSONDecoder().decode(KitManifest.self, from: data)
        XCTAssertEqual(manifest.schemaVersion, 1)
        XCTAssertEqual(manifest.sourceAssetSHA256, ReplaySkinnedAthleteProvider.assetSHA256)
        XCTAssertTrue(manifest.geometryUnchanged)
        XCTAssertTrue(manifest.normalMapsUnchanged)
        XCTAssertEqual(manifest.textures.count, 15)
        return (root, manifest)
    }

    private func resetProviders() {
        ReplayArticulatedFarKitProvider.resetForTesting()
        ReplayArticulatedFarProvider.resetForTesting()
        ReplayFarAthleteHeadProvider.resetForTesting()
        ReplaySkinnedAthleteProvider.resetForTesting()
        ReplayAthleteHeadProvider.resetForTesting()
        ReplayFarAthletePaletteProvider.resetForTesting()
    }

    private func bundledPNGHash(_ name: String) throws -> String {
        SHA256.hash(data: try Data(contentsOf: bundledPNGURL(name))).map { String(format: "%02x", $0) }.joined()
    }

    private func bundledPNGURL(_ name: String) throws -> URL {
        try XCTUnwrap(Bundle.main.url(forResource: name, withExtension: "png", subdirectory: "Resources/Players")
            ?? Bundle.main.url(forResource: name, withExtension: "png"))
    }

    private func allModels(in root: Entity) -> [ModelEntity] {
        ((root as? ModelEntity).map { [$0] } ?? []) + root.children.flatMap { allModels(in: $0) }
    }

    private func differentPixels(_ a: ReplayRealityRendererAudit.Frame, _ b: ReplayRealityRendererAudit.Frame) -> Int {
        guard a.width == b.width, a.height == b.height else { return 0 }
        var result = 0
        for offset in stride(from: 0, to: a.bgra.count, by: 4) {
            if a.bgra[offset] != b.bgra[offset] || a.bgra[offset + 1] != b.bgra[offset + 1]
                || a.bgra[offset + 2] != b.bgra[offset + 2] { result += 1 }
        }
        return result
    }

    private func vector(_ value: SIMD3<Float>) -> [Float] { [value.x, value.y, value.z] }
    private func matrix(_ value: simd_float4x4) -> [Float] {
        var result: [Float] = []
        for column in 0..<4 { for row in 0..<4 { result.append(value[column][row]) } }
        return result
    }

    private func attachJSON<T: Encodable>(_ value: T, named name: String) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .prettyPrinted]
        let data = try encoder.encode(value)
        XCTAssertLessThan(data.count, 128 * 1024)
        let attachment = XCTAttachment(data: data, uniformTypeIdentifier: "public.json")
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
