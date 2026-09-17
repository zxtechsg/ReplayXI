import CryptoKit
import Foundation
import RealityKit
import XCTest
import simd
@testable import ReplayXI

/// Original Blender-MCP geometry, read from the shipping resource bundle.
@MainActor
final class ReplayArticulatedFarAdmissionTests: XCTestCase {
    static let assetSHA256 = "1a16ed08fe9c9272f5f2c2f4187ad1f747a39f52bc056ffaaacff9cee0c0a307"

    func testOriginalFourPartImportKeepsSmallSkeletonsAndPhysicalCoordinates() throws {
        let url = try XCTUnwrap(Bundle.main.url(forResource: ReplayArticulatedFarProvider.resourceName,
            withExtension: "usdz", subdirectory: "Resources/Players")
            ?? Bundle.main.url(forResource: ReplayArticulatedFarProvider.resourceName, withExtension: "usdz"))
        let data = try Data(contentsOf: url)
        XCTAssertEqual(data.count, 25_268)
        XCTAssertEqual(SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined(), Self.assetSHA256)
        let root = try Entity.load(contentsOf: url)
        let models = allModels(in: root)
        var rows: [[String: Any]] = []
        for model in models {
            let component = try XCTUnwrap(model.model)
            let contents = component.mesh.contents
            let parts = contents.models.flatMap { Array($0.parts) }
            let bounds = model.visualBounds(relativeTo: root)
            rows.append([
                "name": model.name, "parent": model.parent?.name ?? "", "joints": model.jointNames,
                "meshModels": contents.models.count, "instances": contents.instances.count,
                "parts": parts.map { ["id": $0.id, "vertices": $0.positions.count,
                    "triangles": ($0.triangleIndices?.count ?? 0) / 3,
                    "weights": $0.jointInfluences?.influences.count ?? 0] as [String: Any] },
                "boundsMin": [bounds.min.x, bounds.min.y, bounds.min.z],
                "boundsMax": [bounds.max.x, bounds.max.y, bounds.max.z]
            ])
        }
        let attachment = XCTAttachment(data: try JSONSerialization.data(withJSONObject: rows, options: [.prettyPrinted]),
                                       uniformTypeIdentifier: "public.json")
        attachment.name = "ReplayXI-Original124-NativeImport.json"
        attachment.lifetime = .keepAlways
        add(attachment)
        XCTAssertEqual(models.count, 4)
        let expected: [(String, Int, Int, Int)] = [("Torso",151,266,0),("Shorts",67,120,0),
                                                  ("Arm",167,300,3),("Leg",213,380,3)]
        for (name, vertices, triangles, jointCount) in expected {
            let model = try XCTUnwrap(models.first { $0.name == name || $0.parent?.name == name }, name)
            let component = try XCTUnwrap(model.model)
            let contents = component.mesh.contents
            let parts = contents.models.flatMap { Array($0.parts) }
            XCTAssertEqual(parts.count, 1, name)
            let part = try XCTUnwrap(parts.first)
            XCTAssertEqual(part.positions.count, vertices, name)
            XCTAssertEqual(part.normals?.count, vertices, name)
            XCTAssertEqual(part.textureCoordinates?.count, vertices, name)
            XCTAssertEqual(part.triangleIndices?.count, triangles * 3, name)
            XCTAssertEqual(component.materials.count, 1, name)
            XCTAssertTrue(component.materials.first is PhysicallyBasedMaterial)
            XCTAssertEqual(contents.instances.count, 1, name)
            XCTAssertEqual(contents.instances.first?.transform, matrix_identity_float4x4, name)
            XCTAssertEqual(model.transformMatrix(relativeTo: root), matrix_identity_float4x4, name)
            XCTAssertEqual(model.jointNames.count, jointCount, name)
            XCTAssertEqual(contents.skeletons.count, jointCount == 0 ? 0 : 1, name)
            if jointCount == 0 { XCTAssertNil(part.jointInfluences); continue }
            XCTAssertEqual(model.jointNames, ["Root", "Root/Bend", "Root/Bend/Tip"])
            let skeleton = try XCTUnwrap(contents.skeletons.first)
            XCTAssertEqual(skeleton.joints.map { $0.parentIndex ?? -1 }, [-1,0,1])
            let first: Float = name == "Leg" ? 0.39 : 0.31
            let second: Float = name == "Leg" ? 0.35 : 0.275
            XCTAssertEqual(skeleton.joints[1].restPoseTransform.translation.y, -first, accuracy: 0.000_001)
            XCTAssertEqual(skeleton.joints[2].restPoseTransform.translation.y, -second, accuracy: 0.000_001)
            let influences = try XCTUnwrap(part.jointInfluences).influences.elements
            let stride = influences.count / vertices
            XCTAssertTrue((1...4).contains(stride))
            XCTAssertEqual(influences.count, vertices * stride)
            for vertex in 0..<vertices {
                let start = vertex * stride
                let weights = influences[start..<(start + stride)]
                XCTAssertEqual(weights.reduce(Float.zero) { $0 + $1.weight }, 1, accuracy: 0.000_001)
                XCTAssertTrue(weights.allSatisfy { (0..<3).contains($0.jointIndex) && $0.weight.isFinite && $0.weight >= 0 })
            }
            let clone = model.clone(recursive: true)
            let rest = clone.jointTransforms
            var pose = rest
            pose[1].rotation = simd_quatf(angle: 0.8, axis: [1,0,0])
            model.jointTransforms = pose
            XCTAssertEqual(clone.jointTransforms, rest)
            XCTAssertEqual(model.jointTransforms, pose)
            model.jointTransforms = rest
            XCTAssertEqual(model.jointTransforms, rest)
        }
    }

    private func allModels(in root: Entity) -> [ModelEntity] {
        ((root as? ModelEntity).map { [$0] } ?? []) + root.children.flatMap { allModels(in: $0) }
    }
}
