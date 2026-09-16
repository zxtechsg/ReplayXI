import CryptoKit
import Foundation
import simd
import XCTest
@testable import ReplayXI

@MainActor
final class ReplaySkinnedAthleteContactSurfaceTests: XCTestCase {
    private func resource(_ name: String) throws -> Data {
        let url = try XCTUnwrap(Bundle.main.url(forResource: name, withExtension: "json", subdirectory: "Resources/Players")
            ?? Bundle.main.url(forResource: name, withExtension: "json"))
        return try Data(contentsOf: url)
    }

    private func prepare() throws -> (ReplaySkinnedAthleteMotion, Data, ReplaySkinnedAthleteContactSurface) {
        let motion = try ReplaySkinnedAthleteMotion(data: resource("ReplayXIRocketboxMotion"))
        let data = try resource("ReplayXIRocketboxContactSurface")
        return (motion, data, try decode(data, motion: motion))
    }

    private func decode(_ data: Data, motion: ReplaySkinnedAthleteMotion) throws -> ReplaySkinnedAthleteContactSurface {
        try ReplaySkinnedAthleteContactSurface(data: data, motion: motion,
                                               assetSHA256: ReplaySkinnedAthleteProvider.assetSHA256,
                                               motionSHA256: ReplaySkinnedAthleteProvider.motionSHA256)
    }

    func testBundledContactSurfaceMatchesSkinAndBoundedBudget() throws {
        let (motion, data, surface) = try prepare()
        let hash = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        XCTAssertEqual(hash, ReplaySkinnedAthleteProvider.contactSurfaceSHA256)
        XCTAssertEqual(surface.vertexCount, 339)
        XCTAssertEqual(surface.influenceCount, 603)
        XCTAssertLessThanOrEqual(surface.vertexCount, ReplaySkinnedAthleteContactSurface.maximumVertices)
        XCTAssertEqual(surface.paddingMetres, 0.006, accuracy: 0.000001)
        XCTAssertEqual(surface.minimumY(in: motion.restPose), motion.geometry.restMinY, accuracy: 0.00001)
    }

    func testWeightedContactsMatchRigidBodyRotationAndTranslation() throws {
        let (motion, data, surface) = try prepare()
        let document = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let vertices = try XCTUnwrap(document["vertices"] as? [[String: Any]])
        for angle: Float in [0, 0.7, 1.48, -.pi / 2, .pi] {
            var transform = simd_float4x4(simd_quatf(angle: angle, axis: simd_normalize(SIMD3<Float>(0.7, 0, 0.4))))
            transform.columns.3 = SIMD4<Float>(0.4, 0.37, -0.8, 1)
            var pose = motion.makePoseBuffer()
            for index in motion.joints.indices {
                pose.modelSpaceTransforms[index] = transform * motion.restPose.modelSpaceTransforms[index]
            }
            let expected = try vertices.map { vertex -> Float in
                let values = try XCTUnwrap(vertex["position"] as? [NSNumber])
                return (transform * SIMD4<Float>(values[0].floatValue, values[1].floatValue, values[2].floatValue, 1)).y
            }.min()
            XCTAssertEqual(surface.minimumY(in: pose), try XCTUnwrap(expected), accuracy: 0.00001)
        }
    }

    func testContactHeightTracksAnimatedRootTranslationExactly() throws {
        let (motion, _, surface) = try prepare()
        var pose = motion.makePoseBuffer()
        for time in stride(from: 0.0, through: 1.2, by: 0.03) {
            motion.sample(clip: .run, at: time, into: &pose)
            let before = surface.minimumY(in: pose)
            pose.translations[0].y += 0.23
            motion.rebuildModelSpaceTransforms(in: &pose)
            XCTAssertEqual(surface.minimumY(in: pose), before + 0.23, accuracy: 0.00001)
        }
        pose.modelSpaceTransforms.removeLast()
        XCTAssertTrue(surface.minimumY(in: pose).isNaN, "Wrong-sized skeletons must not be indexed")
        pose = motion.makePoseBuffer()
        for index in motion.joints.indices { pose.modelSpaceTransforms[index].columns.3.y = .nan }
        XCTAssertTrue(surface.minimumY(in: pose).isNaN, "A malformed pose must not report positive-infinite clearance")
    }

    func testWrongAssetIdentityAndOversizedContactDataAreRejected() throws {
        let (motion, data, _) = try prepare()
        let original = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        for (key, value): (String, Any) in [
            ("schemaVersion", 2), ("assetSHA256", String(repeating: "0", count: 64)),
            ("motionSHA256", String(repeating: "0", count: 64)), ("sourceVertexCount", 5_011),
            ("jointCount", 79), ("paddingMetres", 0), ("paddingMetres", 0.1), ("vertices", [])
        ] {
            var document = original
            document[key] = value
            XCTAssertThrowsError(try decode(JSONSerialization.data(withJSONObject: document), motion: motion), key)
        }
        XCTAssertThrowsError(try decode(Data(repeating: 32, count: ReplaySkinnedAthleteContactSurface.maximumPayloadBytes + 1),
                                         motion: motion))
    }

    func testMalformedContactPositionsAndWeightsAreRejected() throws {
        let (motion, data, _) = try prepare()
        let original = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let originalVertices = try XCTUnwrap(original["vertices"] as? [[String: Any]])
        let invalid: [(String, Any)] = [
            ("id", ""), ("id", originalVertices[1]["id"]!),
            ("position", [0, 9, 0]), ("position", [0, 0]),
            ("joints", []), ("joints", [-1]), ("joints", [80]), ("joints", [0, 0]),
            ("weights", []), ("weights", [-1]), ("weights", [0.3]), ("weights", [1.1])
        ]
        for (key, value) in invalid {
            var document = original
            var vertices = originalVertices
            vertices[0][key] = value
            document["vertices"] = vertices
            XCTAssertThrowsError(try decode(JSONSerialization.data(withJSONObject: document), motion: motion), key)
        }
        var excessive = original
        excessive["vertices"] = Array(repeating: originalVertices[0], count: ReplaySkinnedAthleteContactSurface.maximumVertices + 1)
        XCTAssertThrowsError(try decode(JSONSerialization.data(withJSONObject: excessive), motion: motion))
    }
}
