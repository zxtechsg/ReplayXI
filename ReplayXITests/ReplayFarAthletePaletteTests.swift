import CoreGraphics
import CryptoKit
import Metal
import RealityKit
import XCTest
@testable import ReplayXI

@MainActor
final class ReplayFarAthletePaletteTests: XCTestCase {
    private let fixtureIDs = ["navy-rb", "red-lw", "navy-gk"]
    private let limbNames = ["left-leg", "right-leg", "left-arm", "right-arm"]

    override func setUp() {
        super.setUp()
        ReplayAthleteHeadProvider.resetForTesting()
        ReplayFarAthletePaletteProvider.resetForTesting()
        ReplaySkinnedAthleteProvider.resetForTesting()
        ReplayImportedAthleteProvider.resetPrewarmForTesting()
    }

    override func tearDown() {
        ReplayAthleteHeadProvider.resetForTesting()
        ReplayFarAthletePaletteProvider.resetForTesting()
        ReplaySkinnedAthleteProvider.resetForTesting()
        ReplayImportedAthleteProvider.resetPrewarmForTesting()
        super.tearDown()
    }

    private func scenario() throws -> ReplayScenario {
        try XCTUnwrap(DemoScenarios.scenario(for: .squadReplay))
    }

    private func model(named name: String, in rig: Entity) throws -> ModelEntity {
        try XCTUnwrap(rig.findEntity(named: name) as? ModelEntity)
    }

    private func models(in root: Entity) -> [ModelEntity] {
        var result: [ModelEntity] = []
        func visit(_ entity: Entity) {
            if let model = entity as? ModelEntity { result.append(model) }
            for child in entity.children { visit(child) }
        }
        visit(root)
        return result.sorted { $0.name < $1.name }
    }

    private func attach(_ rows: [[String: Any]], named name: String) throws {
        let data = try JSONSerialization.data(withJSONObject: ["samples": rows], options: [.sortedKeys])
        let attachment = XCTAttachment(data: data, uniformTypeIdentifier: "public.json")
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    func testFarLimbsHaveFiniteHeightUVsWithoutChangingVertexCounts() throws {
        let scenario = try scenario()
        for id in fixtureIDs {
            let rig = try ReplayAthleteFactory.make(for: XCTUnwrap(scenario.player(id: id)), lod: .far)
            for name in limbNames {
                let component = try XCTUnwrap(model(named: name, in: rig.root).model)
                for mesh in component.mesh.contents.models {
                    for part in mesh.parts {
                        guard let coordinates = part.textureCoordinates else {
                            XCTFail("\(id) \(name): far limb needs height UVs for skin/kit/boot bands")
                            continue
                        }
                        let positions = part.positions.elements
                        let uvs = coordinates.elements
                        XCTAssertEqual(uvs.count, positions.count)
                        let lowerY: Float = name.hasSuffix("leg") ? -0.82 : -0.58
                        let upperY: Float = 0.02
                        for (position, uv) in zip(positions, uvs) {
                            XCTAssertTrue(uv.x.isFinite && uv.y.isFinite)
                            XCTAssertEqual(uv.x, 0.5)
                            let relativeHeight = min(max((upperY - position.y) / (upperY - lowerY), 0), 1)
                            let expectedV = 1 - (0.5 + relativeHeight * 63) / 64
                            XCTAssertEqual(uv.y, expectedV, accuracy: 0.000001)
                            XCTAssertGreaterThanOrEqual(uv.y, 0.5 / 64)
                            XCTAssertLessThanOrEqual(uv.y, 63.5 / 64)
                        }
                    }
                }
            }
        }
    }

    func testFarLimbsAdmitBoundedSeparateColourStripsInOneMaterialSlot() throws {
        let scenario = try scenario()
        try ReplayAthleteFactory.prewarm(for: scenario.players, lods: [.far])
        for id in fixtureIDs {
            let rig = try ReplayAthleteFactory.make(for: XCTUnwrap(scenario.player(id: id)), lod: .far)
            var textures: [String: TextureResource] = [:]
            for name in limbNames {
                let component = try XCTUnwrap(model(named: name, in: rig.root).model)
                XCTAssertEqual(component.materials.count, 1)
                let material = try XCTUnwrap(component.materials.first as? SimpleMaterial)
                guard let texture = material.color.texture else {
                    XCTFail("\(id) \(name): one colour strip must distinguish exposed skin and kit")
                    continue
                }
                let resource = texture.resource
                textures[name] = resource
                XCTAssertEqual(resource.width, 1)
                XCTAssertEqual(resource.height, 64)
                XCTAssertEqual(resource.mipmapLevelCount, 7)
                XCTAssertEqual(resource.semantic, .color)
                XCTAssertTrue([MTLPixelFormat.rgba8Unorm, .rgba8Unorm_srgb, .bgra8Unorm, .bgra8Unorm_srgb]
                    .contains(resource.pixelFormat), "The audit must read a bounded uncompressed colour format")
                texture.sampler.access { sampler in
                    XCTAssertEqual(sampler.sAddressMode, .clampToEdge)
                    XCTAssertEqual(sampler.tAddressMode, .clampToEdge)
                    XCTAssertEqual(sampler.minFilter, .linear)
                    XCTAssertEqual(sampler.magFilter, .linear)
                    XCTAssertEqual(sampler.mipFilter, .linear)
                    XCTAssertTrue(sampler.normalizedCoordinates)
                }
            }
            if textures.count == 4 {
                XCTAssertEqual(try XCTUnwrap(textures["left-leg"]), try XCTUnwrap(textures["right-leg"]))
                XCTAssertEqual(try XCTUnwrap(textures["left-arm"]), try XCTUnwrap(textures["right-arm"]))
                XCTAssertNotEqual(try XCTUnwrap(textures["left-leg"]), try XCTUnwrap(textures["left-arm"]),
                                  "Separate mip chains must never average arm and leg palettes together")
            }
        }
    }

    func testFarGeometryRetainsTheSevenModel399Vertex574TriangleBaseline() throws {
        let scenario = try scenario()
        var report: [[String: Any]] = []
        for id in fixtureIDs {
            let rig = try ReplayAthleteFactory.make(for: XCTUnwrap(scenario.player(id: id)), lod: .far)
            let renderModels = models(in: rig.root)
            XCTAssertEqual(renderModels.count, 7)
            XCTAssertEqual(rig.metrics.modelEntities, 7)
            XCTAssertEqual(rig.metrics.verticesPerInstance, 399)
            XCTAssertEqual(rig.metrics.trianglesPerInstance, 574)
            XCTAssertTrue(rig.metrics.fits(ReplayAthleteLOD.far.budget))
            var vertices = 0, triangles = 0
            var geometry: [[String: Any]] = []
            for model in renderModels {
                let component = try XCTUnwrap(model.model)
                XCTAssertEqual(component.materials.count, 1)
                for mesh in component.mesh.contents.models {
                    for part in mesh.parts {
                        let positions = part.positions.elements
                        let normals = try XCTUnwrap(part.normals).elements
                        let indices = try XCTUnwrap(part.triangleIndices).elements
                        XCTAssertEqual(indices.count % 3, 0)
                        XCTAssertEqual(part.materialIndex, 0)
                        vertices += positions.count
                        triangles += indices.count / 3
                        geometry.append(["name": model.name,
                                         "positions": positions.map { [$0.x, $0.y, $0.z] },
                                         "normals": normals.map { [$0.x, $0.y, $0.z] },
                                         "indices": indices])
                    }
                }
            }
            XCTAssertEqual(vertices, 399)
            XCTAssertEqual(triangles, 574)
            let bytes = try JSONSerialization.data(withJSONObject: geometry, options: [.sortedKeys])
            let digest = SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined()
            XCTAssertEqual(digest, "3f40c68f717193de03dc4c967382060a8686857bca2db62624ecc0a01bcce13d",
                           "Native positions, normals and indices must match the captured pre-palette mesh")
            report.append(["playerID": id, "modelCount": renderModels.count, "vertices": vertices,
                           "triangles": triangles, "geometrySHA256": digest])
        }
        try attach(report, named: "ReplayXI-FarPalette96-GeometryBaseline.json")
    }

    func testNearAndMidLimbMaterialsAndUVAdmissionRemainUnchanged() throws {
        let scenario = try scenario()
        for lod in [ReplayAthleteLOD.near, .mid] {
            for id in fixtureIDs {
                let rig = try ReplayAthleteFactory.make(for: XCTUnwrap(scenario.player(id: id)), lod: lod)
                for name in ["left-thigh", "right-thigh", "left-shin", "right-shin",
                             "left-sleeve", "right-sleeve", "left-forearm", "right-forearm"] {
                    let component = try XCTUnwrap(model(named: name, in: rig.root).model)
                    XCTAssertEqual(component.materials.count, 1)
                    let material = try XCTUnwrap(component.materials.first as? SimpleMaterial)
                    XCTAssertNil(material.color.texture, "Only the integrated far limbs change")
                    for mesh in component.mesh.contents.models {
                        for part in mesh.parts { XCTAssertNil(part.textureCoordinates) }
                    }
                }
                XCTAssertTrue(rig.metrics.fits(lod.budget))
            }
        }
        XCTAssertEqual(ReplayFarAthletePaletteProvider.preparationAttemptCount, 0)
        XCTAssertEqual(ReplayFarAthletePaletteProvider.cachedPaletteCount, 0)
    }

    func testFarRigPoseAndMeshPositionsRepeatExactlyAcrossAbsoluteTimeSeeks() throws {
        let scenario = try scenario()
        let player = try XCTUnwrap(scenario.player(id: "navy-rb"))
        let rig = try ReplayAthleteFactory.make(for: player, lod: .far)
        func sample(_ time: Double) {
            let ball = scenario.ball.pose(at: time)
            let pose = ReplayAthleteMotion.locomotionPose(for: player, at: time,
                lookTargetWorldPosition: [ball.position.x, ball.height, ball.position.z], ballTrack: scenario.ball)
            ReplayAthleteMotion.apply(pose, to: rig.joints)
        }
        func points() throws -> [SIMD3<Float>] {
            try models(in: rig.root).flatMap { model in
                try XCTUnwrap(model.model).mesh.contents.models.flatMap { mesh in
                    mesh.parts.flatMap { part in
                        part.positions.elements.map { model.convert(position: $0, to: rig.root) }
                    }
                }
            }
        }
        sample(11.691666666666666)
        let first = try points()
        let firstJoints = ReplayAthleteJoint.allCases.map { rig.joints[$0].transform }
        for time in [32.0, 13.6, 0, 11.691666666666666] { sample(time) }
        XCTAssertEqual(try points(), first)
        XCTAssertEqual(ReplayAthleteJoint.allCases.map { rig.joints[$0].transform }, firstJoints)
    }

    private func configuration(_ base: ReplayAthleteConfiguration,
                               shirt: ReplayAthleteColor? = nil,
                               identity: String? = nil,
                               appearance: ReplayAthleteAppearance? = nil) -> ReplayAthleteConfiguration {
        let kit = ReplayAthleteKit(
            shirt: shirt ?? base.kit.shirt, trim: base.kit.trim, shorts: base.kit.shorts,
            socks: base.kit.socks, number: base.kit.number, boots: base.kit.boots,
            bootAccent: base.kit.bootAccent
        )
        return ReplayAthleteConfiguration(
            playerID: identity ?? base.playerID, shirtNumber: base.shirtNumber,
            goalkeeper: base.goalkeeper, kit: kit, appearance: appearance ?? base.appearance
        )
    }

    private func resource(_ material: SimpleMaterial) throws -> TextureResource {
        try XCTUnwrap(material.color.texture).resource
    }

    private func rgba(_ colour: ReplayAthleteColor) -> [UInt8] {
        [colour.red, colour.green, colour.blue, colour.alpha].map { UInt8(($0 * 255).rounded()) }
    }


    func testNativeStripsSeparateShortsSkinSocksBootsAndKeeperGloves() throws {
        let scenario = try scenario()
        let sourceSpace = try XCTUnwrap(CGColorSpace(name: CGColorSpace.sRGB))
        let nativeSpace = try XCTUnwrap(CGColorSpace(name: CGColorSpace.displayP3))
        for id in fixtureIDs {
            let player = try XCTUnwrap(scenario.player(id: id))
            let config = ReplayAthleteConfiguration(player: player)
            let rig = try ReplayAthleteFactory.make(for: player, lod: .far)
            let legMaterial = try XCTUnwrap(model(named: "left-leg", in: rig.root).model?.materials.first as? SimpleMaterial)
            let armMaterial = try XCTUnwrap(model(named: "left-arm", in: rig.root).model?.materials.first as? SimpleMaterial)
            let leg = try ReplayNativeTextureAudit.capture(resource(legMaterial))
            let arm = try ReplayNativeTextureAudit.capture(resource(armMaterial))
            for (snapshot, expectedRows) in [
                (leg, [(0, config.kit.shorts), (20, config.appearance.skin),
                       (40, config.kit.socks), (63, config.kit.boots)]),
                (arm, [(0, config.kit.shirt),
                       (32, config.goalkeeper ? config.kit.shirt : config.appearance.skin),
                       (63, config.goalkeeper ? config.kit.trim : config.appearance.skin)]),
            ] {
                XCTAssertEqual(snapshot.width, 1)
                XCTAssertEqual(snapshot.height, 64)
                XCTAssertEqual(snapshot.colourSpace, "Display P3")
                XCTAssertEqual(snapshot.origin, "top-left")
                XCTAssertEqual(snapshot.rgba8.count, 256)
                for (row, expected) in expectedRows {
                    // Production's source image is quantised sRGB; RealityKit
                    // imports it to P3. Core Graphics is the independent reference.
                    let components = rgba(expected).map { CGFloat($0) / 255 }
                    let source = try XCTUnwrap(CGColor(colorSpace: sourceSpace, components: components))
                    let converted = try XCTUnwrap(source.converted(to: nativeSpace, intent: .defaultIntent, options: nil))
                    let expectedP3 = try XCTUnwrap(converted.components)
                    for channel in 0..<4 {
                        XCTAssertEqual(Double(snapshot.rgba8[row * 4 + channel]),
                                       Double(expectedP3[channel] * 255), accuracy: 1,
                                       "\(id), row \(row): native colour must match this kit/skin band")
                    }
                }
                XCTAssertTrue(stride(from: 3, to: snapshot.rgba8.count, by: 4)
                    .allSatisfy { snapshot.rgba8[$0] == 255 })
            }
        }
    }

    func testPrewarmAndSceneSeeksDoNotGenerateMoreTextures() throws {
        let scenario = try scenario()
        try ReplayAthleteFactory.prewarm(for: scenario.players, lods: [.far])
        let palettes = ReplayFarAthletePaletteProvider.preparedPaletteCount
        let attempts = ReplayFarAthletePaletteProvider.preparationAttemptCount
        let generated = ReplayFarAthletePaletteProvider.textureCreationCount
        XCTAssertGreaterThan(palettes, 0)
        XCTAssertLessThanOrEqual(palettes, ReplayFarAthletePaletteProvider.maximumPaletteCount)
        XCTAssertEqual(attempts, palettes)
        XCTAssertEqual(generated, palettes * 2)
        let root = PitchSceneFactory.makeMatchRoot(for: scenario)
        var first: [String: TextureResource] = [:]
        for id in fixtureIDs {
            let player = try XCTUnwrap(root.findEntity(named: "player-\(id)"))
            let marker = try XCTUnwrap(player.findEntity(named: "table-marker"))
            let material = try XCTUnwrap(model(named: "left-leg", in: marker).model?.materials.first as? SimpleMaterial)
            first[id] = try resource(material)
        }
        for view in [ReplayViewMode.tacticalTable, .touchline, .firstPerson] {
            for time in [0.0, 11.691666666666666, 32, 13.6, 0] {
                PitchSceneFactory.update(root: root, scenario: scenario, time: time, viewMode: view,
                    perspectiveID: "navy-gk", marks: [], showsLaneLens: false,
                    isDrawing: false, positionalOriginTransform: nil)
            }
        }
        try ReplayAthleteFactory.prewarm(for: scenario.players, lods: [.far])
        _ = PitchSceneFactory.makeMatchRoot(for: scenario)
        XCTAssertEqual(ReplayFarAthletePaletteProvider.preparedPaletteCount, palettes)
        XCTAssertEqual(ReplayFarAthletePaletteProvider.preparationAttemptCount, attempts)
        XCTAssertEqual(ReplayFarAthletePaletteProvider.textureCreationCount, generated)
        XCTAssertEqual(ReplayFarAthletePaletteProvider.cachedTextureCount, generated)
        for id in fixtureIDs {
            let player = try XCTUnwrap(root.findEntity(named: "player-\(id)"))
            let marker = try XCTUnwrap(player.findEntity(named: "table-marker"))
            let material = try XCTUnwrap(model(named: "left-leg", in: marker).model?.materials.first as? SimpleMaterial)
            XCTAssertEqual(try resource(material), try XCTUnwrap(first[id]))
        }
        try attach([["preparedPalettes": palettes, "textureCreationCount": generated,
                     "additionalPreparationsDuring15ViewSeeksAndSecondRoot":
                        ReplayFarAthletePaletteProvider.preparationAttemptCount - attempts,
                     "additionalTexturesDuring15ViewSeeksAndSecondRoot":
                        ReplayFarAthletePaletteProvider.textureCreationCount - generated]],
                   named: "ReplayXI-FarPalette96-CacheLifecycle.json")
    }

    func testPaletteCacheBoundsSuccessfulResourcesAndSharesAppearanceIndependentColours() throws {
        let scenario = try scenario()
        let base = ReplayAthleteConfiguration(player: try XCTUnwrap(scenario.player(id: "navy-rb")))
        var first: ReplayFarAthletePaletteProvider.Materials?
        for index in 0..<36 {
            let config = configuration(base, shirt: .init(red: Float(index) / 255, green: 0.2, blue: 0.3))
            let materials = ReplayFarAthletePaletteProvider.materials(for: config)
            if index < 32 {
                XCTAssertNotNil(materials)
                if index == 0 { first = materials }
            } else {
                XCTAssertNil(materials, "The bounded cache uses flat fallback once all slots are admitted")
            }
        }
        XCTAssertEqual(ReplayFarAthletePaletteProvider.preparationAttemptCount, 32)
        XCTAssertEqual(ReplayFarAthletePaletteProvider.preparedPaletteCount, 32)
        XCTAssertEqual(ReplayFarAthletePaletteProvider.cachedPaletteCount, 32)
        XCTAssertEqual(ReplayFarAthletePaletteProvider.textureCreationCount, 64)
        XCTAssertEqual(ReplayFarAthletePaletteProvider.cachedTextureCount, 64)
        let changedShape = ReplayAthleteAppearance(skin: base.appearance.skin,
            hair: .init(red: 0.1, green: 0.2, blue: 0.3), heightScale: 1.03, widthScale: 0.98)
        let matchingQuantizedColour = configuration(base,
            shirt: .init(red: 0.1 / 255, green: 0.2, blue: 0.3),
            identity: "other-player", appearance: changedShape)
        let reused = try XCTUnwrap(ReplayFarAthletePaletteProvider.materials(for: matchingQuantizedColour))
        XCTAssertEqual(try resource(reused.leg), try resource(XCTUnwrap(first).leg))
        XCTAssertEqual(try resource(reused.arm), try resource(XCTUnwrap(first).arm))
        XCTAssertEqual(ReplayFarAthletePaletteProvider.preparationAttemptCount, 32)
        XCTAssertEqual(ReplayFarAthletePaletteProvider.textureCreationCount, 64)
    }

    func testFailedPreparationsAreMemoizedAndRetainFlatLimbFallback() throws {
        ReplayFarAthletePaletteProvider.resetForTesting(forceFailure: true)
        let scenario = try scenario()
        let player = try XCTUnwrap(scenario.player(id: "navy-rb"))
        let base = ReplayAthleteConfiguration(player: player)
        for _ in 0..<3 { XCTAssertNil(ReplayFarAthletePaletteProvider.materials(for: base)) }
        let rig = try ReplayAthleteFactory.make(for: player, lod: .far)
        XCTAssertEqual(ReplayFarAthletePaletteProvider.preparationAttemptCount, 1)
        XCTAssertEqual(ReplayFarAthletePaletteProvider.cachedPaletteCount, 1)
        XCTAssertEqual(ReplayFarAthletePaletteProvider.textureCreationCount, 0)
        XCTAssertEqual(models(in: rig.root).count, 7)
        XCTAssertEqual(rig.metrics.verticesPerInstance, 399)
        XCTAssertEqual(rig.metrics.trianglesPerInstance, 574)
        XCTAssertNotNil(rig.joints.farFloorSupport)
        for name in limbNames {
            let component = try XCTUnwrap(model(named: name, in: rig.root).model)
            XCTAssertEqual(component.materials.count, 1)
            let material = try XCTUnwrap(component.materials.first as? SimpleMaterial)
            XCTAssertNil(material.color.texture)
            let expected = name.hasSuffix("leg") ? base.kit.socks : base.kit.shirt
            // Compare the native, colour-managed value with the old flat
            // material path, not with an unconverted source UIColor.
            let baseline = SimpleMaterial(color: expected.uiColor,
                roughness: .float(name.hasSuffix("leg") ? 0.88 : 0.84), isMetallic: false)
            XCTAssertEqual(material.color.tint, baseline.color.tint)
        }
        for index in 0..<36 {
            let config = configuration(base, shirt: .init(red: Float(index) / 255, green: 0.2, blue: 0.3))
            for _ in 0..<2 { XCTAssertNil(ReplayFarAthletePaletteProvider.materials(for: config)) }
        }
        XCTAssertEqual(ReplayFarAthletePaletteProvider.preparationAttemptCount, 32)
        XCTAssertEqual(ReplayFarAthletePaletteProvider.cachedPaletteCount, 32)
        XCTAssertEqual(ReplayFarAthletePaletteProvider.preparedPaletteCount, 0)
        XCTAssertEqual(ReplayFarAthletePaletteProvider.textureCreationCount, 0)
        XCTAssertEqual(ReplayFarAthletePaletteProvider.cachedTextureCount, 0)
    }

    func testNonFiniteColoursAndUVInputsFailSafely() throws {
        let scenario = try scenario()
        let base = ReplayAthleteConfiguration(player: try XCTUnwrap(scenario.player(id: "navy-rb")))
        for shirt in [ReplayAthleteColor(red: .nan, green: 0.2, blue: 0.3),
                      ReplayAthleteColor(red: 0.1, green: .nan, blue: 0.3),
                      ReplayAthleteColor(red: 0.1, green: 0.2, blue: .nan),
                      ReplayAthleteColor(red: 0.1, green: 0.2, blue: 0.3, alpha: .nan),
                      ReplayAthleteColor(red: 0.1, green: 0.2, blue: 0.3, alpha: 0.5)] {
            XCTAssertNil(ReplayFarAthletePaletteProvider.materials(for: configuration(base, shirt: shirt)))
        }
        XCTAssertEqual(ReplayFarAthletePaletteProvider.preparationAttemptCount, 0)
        XCTAssertEqual(ReplayFarAthletePaletteProvider.cachedPaletteCount, 0)
        for limb in ReplayFarAthletePaletteProvider.Limb.allCases {
            for y in [Float.nan, .infinity, -.infinity] {
                XCTAssertEqual(ReplayFarAthletePaletteProvider.textureCoordinate(for: [0, y, 0], limb: limb),
                               SIMD2(0.5, 0.5))
            }
            for y in [Float.greatestFiniteMagnitude, -Float.greatestFiniteMagnitude, -10, 10] {
                let uv = ReplayFarAthletePaletteProvider.textureCoordinate(for: [0, y, 0], limb: limb)
                XCTAssertTrue(uv.x.isFinite && uv.y.isFinite)
                XCTAssertGreaterThanOrEqual(uv.y, 0.5 / 64)
                XCTAssertLessThanOrEqual(uv.y, 63.5 / 64)
            }
        }
    }
}
