import Metal
import RealityKit
import UIKit
import XCTest
@testable import ReplayXI

/// Exports native static far meshes, not a recreated Blender rig. The raw
/// comparison restores only the authored body Y in a test-owned scene.
@MainActor
final class ReplayFarAthleteVisualAuditTests: XCTestCase {
    private struct Mesh: Encodable {
        let name: String
        let positions: [[Float]]
        let indices: [UInt32]
        let tint: [Float]
        let tintColourSpace = "Linear Rec.709"
        let uvs: [[Float]]?
        let texture: ReplayNativeTextureAudit.Snapshot?
    }

    private struct Sample: Encodable {
        let name: String
        let playerID: String
        let time: Double
        let minimumY: Float
        let meshes: [Mesh]
    }

    func testExportsNativeFarMeshesBeforeAndAfterTheVerticalOnlyCorrection() throws {
        try exportNativeFarMeshes(disablePalette: false,
            attachmentName: "ReplayXI-Far94-NativeMeshComparison.json")
    }

    func testExportsFlatLimbBaselineWithIdenticalColourHandlingAndPose() throws {
        try exportNativeFarMeshes(disablePalette: true,
            attachmentName: "ReplayXI-Far96-FlatMaterialBaseline.json")
    }

    private func exportNativeFarMeshes(disablePalette: Bool, attachmentName: String) throws {
        ReplaySkinnedAthleteProvider.resetForTesting()
        ReplayImportedAthleteProvider.resetPrewarmForTesting()
        ReplayFarAthletePaletteProvider.resetForTesting(forceFailure: disablePalette)
        defer {
            ReplaySkinnedAthleteProvider.resetForTesting()
            ReplayImportedAthleteProvider.resetPrewarmForTesting()
            ReplayAthleteHeadProvider.resetForTesting()
            ReplayFarAthletePaletteProvider.resetForTesting()
        }
        let scenario = try XCTUnwrap(DemoScenarios.scenario(for: .squadReplay))
        let root = PitchSceneFactory.makeMatchRoot(for: scenario)
        var samples: [Sample] = []
        for (id, time) in [("navy-rb", 11.691666666666666), ("red-lw", 14.083333333333334)] {
            PitchSceneFactory.update(root: root, scenario: scenario, time: time,
                viewMode: .firstPerson, perspectiveID: "navy-gk", marks: [],
                showsLaneLens: false, isDrawing: false, positionalOriginTransform: nil)
            let player = try XCTUnwrap(scenario.player(id: id))
            let entity = try XCTUnwrap(root.findEntity(named: "player-\(id)"))
            let marker = try XCTUnwrap(entity.children.first { $0.name == "table-marker" })
            XCTAssertTrue(marker.isEnabledInHierarchy)
            let body = try XCTUnwrap(marker.findEntity(named: "body-root"))
            let correctedPosition = body.position
            let corrected = try sample(name: "\(id)-corrected", player: player, time: time,
                marker: marker, relativeTo: entity)
            let ball = scenario.ball.pose(at: time)
            let authored = ReplayAthleteMotion.locomotionPose(for: player, at: time,
                lookTargetWorldPosition: [ball.position.x, ball.height, ball.position.z],
                ballTrack: scenario.ball)
            body.position.y = authored.bodyPosition.y
            let raw = try sample(name: "\(id)-uncorrected", player: player, time: time,
                marker: marker, relativeTo: entity)
            body.position = correctedPosition

            XCTAssertLessThan(raw.minimumY, -0.05, "The comparison must reproduce the measured floor error")
            XCTAssertGreaterThanOrEqual(corrected.minimumY, -0.001)
            XCTAssertEqual(raw.meshes.count, corrected.meshes.count)
            XCTAssertEqual(corrected.meshes.filter { $0.texture != nil }.count, disablePalette ? 0 : 4)
            let expectedLift = (correctedPosition.y - authored.bodyPosition.y) * marker.scale.y
            XCTAssertGreaterThan(expectedLift, 0)
            for (before, after) in zip(raw.meshes, corrected.meshes) {
                XCTAssertEqual(before.name, after.name)
                XCTAssertEqual(before.indices, after.indices)
                XCTAssertEqual(before.tint, after.tint)
                XCTAssertEqual(before.uvs, after.uvs)
                XCTAssertEqual(before.texture, after.texture)
                XCTAssertEqual(before.positions.count, after.positions.count)
                for (p, q) in zip(before.positions, after.positions) {
                    XCTAssertEqual(p[0], q[0])
                    XCTAssertEqual(p[2], q[2])
                    XCTAssertEqual(q[1] - p[1], expectedLift, accuracy: 0.000002)
                }
            }
            samples.append(contentsOf: [raw, corrected])
        }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(["samples": samples])
        XCTAssertLessThan(data.count, 2 * 1024 * 1024)
        let attachment = XCTAttachment(data: data, uniformTypeIdentifier: "public.json")
        attachment.name = attachmentName
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    private func sample(name: String, player: PlayerTrack, time: Double,
                        marker: Entity, relativeTo frame: Entity) throws -> Sample {
        var meshes: [Mesh] = []
        func visit(_ entity: Entity) throws {
            guard entity.isEnabled else { return }
            if let model = entity as? ModelEntity, let component = model.model {
                for mesh in component.mesh.contents.models {
                    for part in mesh.parts {
                        let indices = try XCTUnwrap(part.triangleIndices).elements
                        XCTAssertEqual(indices.count % 3, 0)
                        let points = part.positions.elements.map { model.convert(position: $0, to: frame) }
                        XCTAssertTrue(points.allSatisfy { $0.x.isFinite && $0.y.isFinite && $0.z.isFinite })
                        XCTAssertTrue(indices.allSatisfy { Int($0) < points.count })
                        XCTAssertTrue(component.materials.indices.contains(part.materialIndex))
                        let material = component.materials[part.materialIndex]
                        let tint = try rgba(material)
                        let texture = try colourTexture(material)
                        let uvs = part.textureCoordinates?.elements.map { [$0.x, $0.y] }
                        if texture != nil {
                            XCTAssertEqual(uvs?.count, points.count)
                            XCTAssertTrue(uvs?.allSatisfy { $0.allSatisfy { $0.isFinite && (0...1).contains($0) } } == true)
                        }
                        meshes.append(Mesh(name: "\(model.name)-\(meshes.count)",
                            positions: points.map { [$0.x, $0.y, $0.z] }, indices: indices,
                            tint: tint, uvs: uvs, texture: texture))
                    }
                }
            }
            for child in entity.children { try visit(child) }
        }
        try visit(marker)
        XCTAssertFalse(meshes.isEmpty)
        let minimum = try XCTUnwrap(meshes.flatMap(\.positions).map { $0[1] }.min())
        return Sample(name: name, playerID: player.id, time: time, minimumY: minimum, meshes: meshes)
    }

    private func rgba(_ material: any Material) throws -> [Float] {
        let colour: UIColor
        if let simple = material as? SimpleMaterial {
            colour = simple.color.tint
        } else if let unlit = material as? UnlitMaterial {
            colour = unlit.color.tint
        } else {
            XCTFail("This static-mesh audit does not approximate custom materials")
            throw NSError(domain: "ReplayXI.MeshAudit", code: 1)
        }
        return try ReplayNativeTextureAudit.linearSRGBTint(colour.cgColor)
    }

    private func colourTexture(_ material: any Material) throws -> ReplayNativeTextureAudit.Snapshot? {
        let texture: MaterialParameters.Texture?
        if let simple = material as? SimpleMaterial { texture = simple.color.texture }
        else if let unlit = material as? UnlitMaterial { texture = unlit.color.texture }
        else { throw NSError(domain: "ReplayXI.MeshAudit", code: 2) }
        guard let texture else { return nil }
        XCTAssertEqual(texture.uvIndex, 0)
        texture.sampler.access { sampler in
            XCTAssertEqual(sampler.sAddressMode, .clampToEdge)
            XCTAssertEqual(sampler.tAddressMode, .clampToEdge)
            XCTAssertEqual(sampler.minFilter, .linear)
            XCTAssertEqual(sampler.magFilter, .linear)
            XCTAssertEqual(sampler.mipFilter, .linear)
        }
        return try ReplayNativeTextureAudit.capture(texture.resource)
    }
}
