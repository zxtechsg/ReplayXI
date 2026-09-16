import CoreGraphics
import Foundation
import Metal
import RealityKit
import UIKit
import XCTest
@testable import ReplayXI

private final class ReplayPaletteRenderCompletion: @unchecked Sendable {
    private let lock = NSLock()
    private var completed = false
    func finish() { lock.withLock { completed = true } }
    var isComplete: Bool { lock.withLock { completed } }
}

/// Native shader sampling, not CPU row readback or a recreated offline texture.
/// Factory UV rings and the actual attached texture/sampler remain unchanged.
@MainActor
final class ReplayNativeFarPaletteOrientationTests: XCTestCase {
    func testNativeTextureRowsReachTheExpectedTopAndBottomOfAnUnlitQuad() async throws {
        let calibration = try await calibrate()
        let bytes: [UInt8] = [255, 0, 0, 255, 255, 0, 0, 255,
                             0, 0, 255, 255, 0, 0, 255, 255]
        let provider = try XCTUnwrap(CGDataProvider(data: Data(bytes) as CFData))
        let space = try XCTUnwrap(CGColorSpace(name: CGColorSpace.sRGB))
        let image = try XCTUnwrap(CGImage(width: 1, height: 4, bitsPerComponent: 8,
            bitsPerPixel: 32, bytesPerRow: 4, space: space,
            bitmapInfo: .byteOrder32Big.union(CGBitmapInfo(rawValue: CGImageAlphaInfo.last.rawValue)),
            provider: provider, decode: nil, shouldInterpolate: true, intent: .defaultIntent))
        let resource = try await TextureResource(image: image,
            options: .init(semantic: .color, compression: .none, mipmapsMode: .none))
        let descriptor = MTLSamplerDescriptor()
        descriptor.sAddressMode = .clampToEdge
        descriptor.tAddressMode = .clampToEdge
        descriptor.minFilter = .nearest
        descriptor.magFilter = .nearest
        descriptor.normalizedCoordinates = true
        let texture = MaterialParameters.Texture(resource, sampler: .init(descriptor))
        // This independent control deliberately uses canonical bottom-origin
        // UVs. It does not call or reproduce the app's height-to-UV function.
        let quad = try makeStrip(centreX: 0, rings: [(1, SIMD2<Float>(0.5, 1)),
                                                   (0, SIMD2<Float>(0.5, 0))], texture: texture)
        let frame = try await render([quad], size: 256)
        let top = sample(frame, at: [0, 0.8], calibration: calibration)
        let bottom = sample(frame, at: [0, -0.8], calibration: calibration)
        let expectedTop = try expectedColour([255, 0, 0, 255], calibration: calibration)
        let expectedBottom = try expectedColour([0, 0, 255, 255], calibration: calibration)
        try attachPNG(frame, calibration: calibration, named: "ReplayXI-Palette110-KnownRows.png")
        XCTAssertLessThanOrEqual(channelError(top, expectedTop), 4, "Source image top row must appear at physical top")
        XCTAssertLessThanOrEqual(channelError(bottom, expectedBottom), 4, "Source image bottom row must appear at physical bottom")
    }

    func testActualFarArmAndLegUVsPlaceKitAndSkinAtTheirAnatomicalHeights() async throws {
        let calibration = try await calibrate()
        ReplayFarAthletePaletteProvider.resetForTesting()
        defer { ReplayFarAthletePaletteProvider.resetForTesting() }
        let scenario = try XCTUnwrap(DemoScenarios.scenario(for: .squadReplay))
        var entities: [Entity] = []
        var samples: [PendingSample] = []
        var ringReports: [RingReport] = []
        for (playerIndex, id) in ["navy-rb", "red-lw"].enumerated() {
            let player = try XCTUnwrap(scenario.player(id: id))
            let config = ReplayAthleteConfiguration(player: player)
            let rig = try ReplayAthleteFactory.make(for: player, lod: .far)
            for (limbIndex, name) in ["left-arm", "left-leg"].enumerated() {
                let model = try XCTUnwrap(rig.root.findEntity(named: name) as? ModelEntity)
                let component = try XCTUnwrap(model.model)
                let material = try XCTUnwrap(component.materials.first as? SimpleMaterial)
                let texture = try XCTUnwrap(material.color.texture)
                XCTAssertEqual(texture.uvIndex, 0)
                var coordinatesByHeight: [Float: SIMD2<Float>] = [:]
                for mesh in component.mesh.contents.models {
                    for part in mesh.parts {
                        let positions = part.positions.elements
                        let uvs = try XCTUnwrap(part.textureCoordinates).elements
                        XCTAssertEqual(positions.count, uvs.count)
                        for (position, uv) in zip(positions, uvs) {
                            if let previous = coordinatesByHeight[position.y] {
                                XCTAssertEqual(previous, uv, "A ring must have one height coordinate")
                            }
                            coordinatesByHeight[position.y] = uv
                        }
                    }
                }
                let rings = coordinatesByHeight.map { ($0.key, $0.value) }.sorted { $0.0 > $1.0 }
                XCTAssertGreaterThanOrEqual(rings.count, 5)
                let highest = try XCTUnwrap(rings.first).0
                let lowest = try XCTUnwrap(rings.last).0
                let x = -1.2 + Float(playerIndex * 2 + limbIndex) * 0.8
                entities.append(try makeStrip(centreX: x, rings: rings, texture: texture))
                ringReports.append(RingReport(playerID: id, limb: name,
                    sourceYAndUV: rings.map { [$0.0, $0.1.x, $0.1.y] }))
                let bands: [(String, Float, ReplayAthleteColor)] = name == "left-arm"
                    ? [("upper-arm shirt", -0.05, config.kit.shirt),
                       ("lower-arm skin", -0.45, config.appearance.skin)]
                    : [("upper-leg skin", -0.24, config.appearance.skin),
                       ("lower-leg socks", -0.58, config.kit.socks)]
                for (band, sourceY, colour) in bands {
                    let y = displayY(sourceY, highest: highest, lowest: lowest)
                    samples.append(PendingSample(playerID: id, limb: name, band: band,
                        sourceY: sourceY, point: [x, y], expected: try expectedColour(rgba(colour), calibration: calibration)))
                }
            }
        }
        let frame = try await render(entities, size: 512)
        let results = samples.map { pending in
            SampleResult(playerID: pending.playerID, limb: pending.limb, band: pending.band,
                sourceY: pending.sourceY, expected: pending.expected,
                actual: sample(frame, at: pending.point, calibration: calibration))
        }
        try attachJSON(Report(calibration: calibration, rings: ringReports, samples: results),
            named: "ReplayXI-Palette110-NativeSampling.json")
        try attachPNG(frame, calibration: calibration, named: "ReplayXI-Palette110-ActualFactoryUVs.png")
        for result in results {
            XCTAssertLessThanOrEqual(channelError(result.actual, result.expected), 4,
                "\(result.playerID) \(result.band) at local y=\(result.sourceY): expected \(result.expected), got \(result.actual)")
        }
    }

    private struct PendingSample {
        let playerID: String, limb: String, band: String
        let sourceY: Float
        let point: SIMD2<Float>
        let expected: [UInt8]
    }

    private struct SampleResult: Encodable {
        let playerID: String, limb: String, band: String
        let sourceY: Float
        let expected: [UInt8], actual: [UInt8]
    }

    private struct RingReport: Encodable {
        let playerID: String, limb: String
        let sourceYAndUV: [[Float]]
    }

    private struct Report: Encodable {
        let scope = "Actual far mesh UV rings and material resources on unlit strips; no pose, lighting, PNG-origin workaround or fitted colour transform."
        let calibration: ReplayRealityRendererAudit.Calibration
        let rings: [RingReport]
        let samples: [SampleResult]
    }

    private func displayY(_ source: Float, highest: Float, lowest: Float) -> Float {
        1.35 - (highest - source) / (highest - lowest) * 2.7
    }

    private func makeStrip(centreX: Float, rings: [(Float, SIMD2<Float>)],
                           texture: MaterialParameters.Texture) throws -> ModelEntity {
        let highest = try XCTUnwrap(rings.first).0
        let lowest = try XCTUnwrap(rings.last).0
        XCTAssertGreaterThan(highest, lowest)
        var positions: [SIMD3<Float>] = []
        var coordinates: [SIMD2<Float>] = []
        var indices: [UInt32] = []
        for (sourceY, uv) in rings {
            let y = displayY(sourceY, highest: highest, lowest: lowest)
            positions.append(contentsOf: [[centreX - 0.28, y, 0], [centreX + 0.28, y, 0]])
            coordinates.append(contentsOf: [uv, uv])
        }
        for ring in 0..<(rings.count - 1) {
            let start = UInt32(ring * 2)
            indices.append(contentsOf: [start, start + 2, start + 1, start + 1, start + 2, start + 3])
        }
        var descriptor = MeshDescriptor(name: "native-palette-audit-strip")
        descriptor.positions = MeshBuffers.Positions(positions)
        descriptor.normals = MeshBuffers.Normals([SIMD3<Float>](repeating: [0, 0, 1], count: positions.count))
        descriptor.textureCoordinates = MeshBuffers.TextureCoordinates(coordinates)
        descriptor.primitives = .triangles(indices)
        var material = UnlitMaterial(color: .white, applyPostProcessToneMap: false)
        material.color = .init(tint: .white, texture: texture)
        return ModelEntity(mesh: try MeshResource.generate(from: [descriptor]), materials: [material])
    }

    private func rgba(_ colour: ReplayAthleteColor) -> [UInt8] {
        [colour.red, colour.green, colour.blue, colour.alpha].map { UInt8((min(max($0, 0), 1) * 255).rounded()) }
    }

    private func expectedColour(_ bytes: [UInt8], calibration: ReplayRealityRendererAudit.Calibration) throws -> [UInt8] {
        let sourceSpace = try XCTUnwrap(CGColorSpace(name: CGColorSpace.sRGB))
        let destination = try XCTUnwrap(calibration.gamut.colourSpace)
        let source = try XCTUnwrap(CGColor(colorSpace: sourceSpace, components: bytes.map { CGFloat($0) / 255 }))
        let converted = try XCTUnwrap(source.converted(to: destination, intent: .defaultIntent, options: nil))
        return try XCTUnwrap(converted.components).map { UInt8((min(max($0, 0), 1) * 255).rounded()) }
    }

    private func sample(_ frame: ReplayRealityRendererAudit.Frame, at point: SIMD2<Float>,
                        calibration: ReplayRealityRendererAudit.Calibration) -> [UInt8] {
        let x = Int((0.5 + point.x / 4) * Float(frame.width))
        let y = Int((0.5 - point.y / 4) * Float(frame.height))
        return frame.rgba(x: x, y: y, topFirst: calibration.rawRowsAreTopFirst)
    }

    private func channelError(_ actual: [UInt8], _ expected: [UInt8]) -> Int {
        zip(actual, expected).map { abs(Int($0) - Int($1)) }.max() ?? 255
    }

    private func calibrate() async throws -> ReplayRealityRendererAudit.Calibration {
        let root = Entity()
        let space = try XCTUnwrap(CGColorSpace(name: CGColorSpace.sRGB))
        for (index, bytes) in ReplayRealityRendererAudit.swatches.enumerated() {
            let colour = try XCTUnwrap(CGColor(colorSpace: space, components: bytes.map { CGFloat($0) / 255 } + [1]))
            let swatch = ModelEntity(mesh: .generateBox(size: [1.2, 0.6, 0.01]),
                materials: [UnlitMaterial(color: UIColor(cgColor: colour), applyPostProcessToneMap: false)])
            swatch.position = ReplayRealityRendererAudit.swatchPosition(index)
            root.addChild(swatch)
        }
        let frame = try await render([root], size: 256)
        let probe = try ReplayRealityRendererAudit.probe(frame)
        let matches = probe.candidates.filter { $0.maximumChannelError <= 4 }
        guard matches.count == 1, let calibration = matches.first else {
            throw ReplayRealityRendererAudit.Failure.unsupported("Native palette audit requires unique fixed colour/row calibration")
        }
        return calibration
    }

    private func render(_ entities: [Entity], size: Int) async throws -> ReplayRealityRendererAudit.Frame {
        let camera = PerspectiveCamera()
        camera.camera = PerspectiveCameraComponent(near: 0.05, far: 10, fieldOfViewInDegrees: 90)
        camera.position = [0, 0, 2]
        let renderer = try RealityRenderer()
        renderer.entities.append(contentsOf: entities + [camera])
        renderer.activeCamera = camera
        renderer.cameraSettings.isToneMappingEnabled = true
        renderer.cameraSettings.antialiasing = .none
        renderer.cameraSettings.colorBackground = .color(CGColor(gray: 0, alpha: 1))
        let texture = try ReplayRealityRendererAudit.makeTexture(size: size)
        let output = try RealityRenderer.CameraOutput(.singleProjection(colorTexture: texture))
        let done = expectation(description: "Native palette shader completion")
        let flag = ReplayPaletteRenderCompletion()
        try renderer.updateAndRender(deltaTime: 0, cameraOutput: output, onComplete: { _ in
            flag.finish()
            done.fulfill()
        })
        await fulfillment(of: [done], timeout: 10)
        guard flag.isComplete else { throw ReplayRealityRendererAudit.Failure.unsupported("Native palette render timed out") }
        return try withExtendedLifetime(renderer) { try ReplayRealityRendererAudit.read(texture) }
    }

    private func attachJSON<T: Encodable>(_ value: T, named name: String) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .prettyPrinted]
        let data = try encoder.encode(value)
        XCTAssertLessThan(data.count, 32 * 1024)
        let attachment = XCTAttachment(data: data, uniformTypeIdentifier: "public.json")
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    private func attachPNG(_ frame: ReplayRealityRendererAudit.Frame,
                           calibration: ReplayRealityRendererAudit.Calibration, named name: String) throws {
        let data = try ReplayRealityRendererAudit.png(frame, calibration: calibration)
        let attachment = XCTAttachment(data: data, uniformTypeIdentifier: "public.png")
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
