import CoreGraphics
import Foundation
import RealityKit
import XCTest

/// Public resource equality and mutation aliasing, not GPU allocation identity.
/// All resources are fresh and unnamed; no shipping asset or cache is mutated.
@MainActor
final class ReplayTextureResourceSemantics150Tests: XCTestCase {
    private struct Alias {
        let label: String
        let resource: TextureResource
    }

    private struct Comparison: Encodable {
        let lhs: String
        let rhs: String
        let sameSwiftObject: Bool
        let equalResources: Bool
    }

    private struct Readback: Encodable {
        let label: String
        let swiftObjectIdentifier: String
        let sameSwiftObjectAsSource: Bool
        let equalToSourceResource: Bool
        let matchesExpectedPixels: Bool
        let snapshot: ReplayNativeTextureAudit.Snapshot
    }

    private struct Phase: Encodable {
        let name: String
        let retainedAliasCount: Int
        let readbacks: [Readback]
    }

    private struct Receipt: Encodable {
        let runtime = ProcessInfo.processInfo.operatingSystemVersionString
        let scope = "Fresh unnamed textures; public equality and mutation aliasing only, not GPU allocation identity"
        var initialComparisons: [Comparison] = []
        var phases: [Phase] = []
    }

    func testFreshIdenticalPixelResourcesRemainDistinctWhileMaterialAliasesShareReplacementAndRestore() throws {
        var receipt = Receipt()
        defer {
            do {
                let encoder = JSONEncoder()
                encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
                let attachment = XCTAttachment(data: try encoder.encode(receipt), uniformTypeIdentifier: "public.json")
                attachment.name = "ReplayXI-TextureResourceSemantics150.json"
                attachment.lifetime = .keepAlways
                add(attachment)
            } catch {
                XCTFail("Could not attach texture semantics receipt: \(error)")
            }
        }

        let originalImage = try image(replacement: false)
        let replacementImage = try image(replacement: true)
        let options = TextureResource.CreateOptions(semantic: .color, compression: .none, mipmapsMode: .none)
        let source = try TextureResource(image: originalImage, options: options)
        let independent = try TextureResource(image: originalImage, options: options)
        XCTAssertFalse(source === independent)
        XCTAssertNotEqual(source, independent,
                          "Independent resources must not compare equal merely because their pixels match")
        let original = try ReplayNativeTextureAudit.capture(source)
        XCTAssertEqual(original.width, 4)
        XCTAssertEqual(original.height, 4)
        XCTAssertEqual(original.rgba8.count, 64)
        XCTAssertEqual(try ReplayNativeTextureAudit.capture(independent), original)

        var simple = SimpleMaterial(color: .white, roughness: .float(0.8), isMetallic: false)
        simple.color = .init(tint: .white, texture: .init(source))
        var pbr = PhysicallyBasedMaterial()
        pbr.baseColor = .init(tint: .white, texture: .init(source))
        let mesh = MeshResource.generatePlane(width: 1, depth: 1)
        let simpleModel = ModelEntity(mesh: mesh, materials: [simple])
        let pbrModel = ModelEntity(mesh: mesh, materials: [pbr])

        // Retain every extracted wrapper across all three phases, so an
        // allocator cannot recycle an earlier ObjectIdentifier in the receipt.
        var aliases = try materialAliases(prefix: "initial", simple: simple, pbr: pbr,
                                          simpleModel: simpleModel, pbrModel: pbrModel)
        XCTAssertEqual(aliases.count, 8)
        let initialResources = [Alias(label: "source", resource: source)] + aliases
            + [Alias(label: "independent-same-pixels", resource: independent)]
        for lhs in initialResources.indices {
            for rhs in initialResources.indices where rhs > lhs {
                let a = initialResources[lhs]
                let b = initialResources[rhs]
                receipt.initialComparisons.append(.init(lhs: a.label, rhs: b.label,
                    sameSwiftObject: a.resource === b.resource, equalResources: a.resource == b.resource))
            }
        }
        receipt.phases.append(try phase("original", source: source, independent: independent,
            aliases: aliases, expectedSource: original, expectedIndependent: original))

        try source.replace(withImage: replacementImage, options: options)
        let replaced = try ReplayNativeTextureAudit.capture(source)
        XCTAssertNotEqual(replaced.rgba8, original.rgba8, "The mutation must visibly change the probe pixels")
        aliases += try materialAliases(prefix: "after-replace", simple: simple, pbr: pbr,
                                       simpleModel: simpleModel, pbrModel: pbrModel)
        XCTAssertEqual(aliases.count, 16)
        receipt.phases.append(try phase("replacement", source: source, independent: independent,
            aliases: aliases, expectedSource: replaced, expectedIndependent: original))

        try source.replace(withImage: originalImage, options: options)
        aliases += try materialAliases(prefix: "after-restore", simple: simple, pbr: pbr,
                                       simpleModel: simpleModel, pbrModel: pbrModel)
        XCTAssertEqual(aliases.count, 24)
        receipt.phases.append(try phase("restored", source: source, independent: independent,
            aliases: aliases, expectedSource: original, expectedIndependent: original))
        XCTAssertEqual(receipt.phases.count, 3)
        XCTAssertEqual(receipt.initialComparisons.count, 45)
        withExtendedLifetime((source, independent, simple, pbr, simpleModel, pbrModel,
                              initialResources, aliases)) {}
    }

    private func materialAliases(prefix: String, simple: SimpleMaterial, pbr: PhysicallyBasedMaterial,
                                 simpleModel: ModelEntity, pbrModel: ModelEntity) throws -> [Alias] {
        var result: [Alias] = []
        for read in 0..<2 {
            result.append(.init(label: "\(prefix)-simple-\(read)",
                                resource: try XCTUnwrap(simple.color.texture).resource))
            result.append(.init(label: "\(prefix)-pbr-\(read)",
                                resource: try XCTUnwrap(pbr.baseColor.texture).resource))
            let modelSimple = try XCTUnwrap(simpleModel.model?.materials.first as? SimpleMaterial)
            let modelPBR = try XCTUnwrap(pbrModel.model?.materials.first as? PhysicallyBasedMaterial)
            result.append(.init(label: "\(prefix)-model-simple-\(read)",
                                resource: try XCTUnwrap(modelSimple.color.texture).resource))
            result.append(.init(label: "\(prefix)-model-pbr-\(read)",
                                resource: try XCTUnwrap(modelPBR.baseColor.texture).resource))
        }
        return result
    }

    private func phase(_ name: String, source: TextureResource, independent: TextureResource,
                       aliases: [Alias], expectedSource: ReplayNativeTextureAudit.Snapshot,
                       expectedIndependent: ReplayNativeTextureAudit.Snapshot) throws -> Phase {
        var rows: [Readback] = []
        let resources = [Alias(label: "source", resource: source)] + aliases
            + [Alias(label: "independent-same-pixels", resource: independent)]
        for alias in resources {
            let isIndependent = alias.label == "independent-same-pixels"
            let expected = isIndependent ? expectedIndependent : expectedSource
            let snapshot = try ReplayNativeTextureAudit.capture(alias.resource)
            let equalsSource = alias.resource == source
            XCTAssertEqual(equalsSource, !isIndependent, "\(name), \(alias.label): public resource equality")
            XCTAssertEqual(snapshot, expected, "\(name), \(alias.label): exact mutation/restore readback")
            rows.append(.init(label: alias.label,
                swiftObjectIdentifier: String(describing: ObjectIdentifier(alias.resource)),
                sameSwiftObjectAsSource: alias.resource === source,
                equalToSourceResource: equalsSource, matchesExpectedPixels: snapshot == expected,
                snapshot: snapshot))
        }
        return .init(name: name, retainedAliasCount: aliases.count, readbacks: rows)
    }

    private func image(replacement: Bool) throws -> CGImage {
        let colours: [[UInt8]] = replacement
            ? [[0, 0, 255, 255], [0, 255, 0, 255]]
            : [[255, 0, 0, 255], [255, 255, 255, 255]]
        let pixels = (0..<16).flatMap { colours[(($0 / 4) + ($0 % 4)) % 2] }
        let space = try XCTUnwrap(CGColorSpace(name: CGColorSpace.sRGB))
        let provider = try XCTUnwrap(CGDataProvider(data: Data(pixels) as CFData))
        return try XCTUnwrap(CGImage(width: 4, height: 4, bitsPerComponent: 8, bitsPerPixel: 32,
            bytesPerRow: 16, space: space,
            bitmapInfo: CGBitmapInfo.byteOrder32Big.union(CGBitmapInfo(rawValue: CGImageAlphaInfo.last.rawValue)),
            provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent))
    }
}
