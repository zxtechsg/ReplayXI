import CryptoKit
import Foundation
import simd
import XCTest
@testable import ReplayXI

/// Candidate-only evidence. Missing derived fixtures skip; a present but
/// altered/malformed fixture fails. No bundled model or scene admission changes.
final class ReplayLowDetailContactSurfaceTests: XCTestCase {
    private let assetHash = "cd8a496a1f89166cf819177c8b959246d130f64ea5dfbd86910488b1dbe849ac"
    private let profileHash = "76e9cfe574345931ca945495f41a0e2fe872a182d8db4f7e3078a8baa4acf7b1"
    private let fixtureHash = "9cd03e16888fe635bc1e4d417d48895da33dd98b7be7dbf744e262f1177dd5fd"

    private struct Fixture: Decodable {
        struct Pose: Decodable {
            let name: String
            let groundOffset: Float
            let translations: [[Float]]
            let rotations: [[Float]]
            let scales: [[Float]]
            let expectedPositionsWithRootOffset: [String: [[Float]]]
        }
        let poses: [Pose]
    }

    private var repository: URL {
        URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
    }

    private func derivedData(_ path: String, hash: String, maximumBytes: Int) throws -> Data {
        let url = repository.appendingPathComponent(".codex-derived").appendingPathComponent(path)
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw XCTSkip("Optional low-detail candidate fixture is absent: \(url.lastPathComponent)")
        }
        let size = try XCTUnwrap(url.resourceValues(forKeys: [.fileSizeKey]).fileSize)
        XCTAssertLessThanOrEqual(size, maximumBytes)
        guard size <= maximumBytes else { throw CocoaError(.fileReadTooLarge) }
        let data = try Data(contentsOf: url)
        let actual = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        XCTAssertEqual(actual, hash, "Do not silently admit a modified external fixture")
        guard actual == hash else { throw CocoaError(.fileReadCorruptFile) }
        return data
    }

    private func prepare() throws -> (ReplaySkinnedAthleteMotion, Data, ReplaySkinnedAthleteContactSurface) {
        let motionURL = try XCTUnwrap(Bundle.main.url(forResource: "ReplayXIRocketboxMotion", withExtension: "json",
            subdirectory: "Resources/Players") ?? Bundle.main.url(forResource: "ReplayXIRocketboxMotion", withExtension: "json"))
        let motion = try ReplaySkinnedAthleteMotion(data: Data(contentsOf: motionURL))
        let data = try derivedData("ReplayXI-Low102-FullContact-02/ReplayXILow102FullContactCandidate.json",
            hash: profileHash, maximumBytes: 512 * 1_024)
        return (motion, data, try decode(data, motion: motion))
    }

    private func decode(_ data: Data, motion: ReplaySkinnedAthleteMotion) throws -> ReplaySkinnedAthleteContactSurface {
        try ReplaySkinnedAthleteContactSurface(data: data, motion: motion,
            assetSHA256: assetHash, motionSHA256: ReplaySkinnedAthleteProvider.motionSHA256,
            profile: .fullLowDetail)
    }

    func testFullCandidateHasEveryVertexWithoutRelaxingNearBudget() throws {
        let (motion, data, surface) = try prepare()
        XCTAssertEqual(surface.vertexCount, 1_707)
        XCTAssertEqual(surface.influenceCount, 2_823)
        XCTAssertEqual(surface.paddingMetres, 0.006)
        XCTAssertEqual(ReplaySkinnedAthleteContactSurface.maximumVertices, 512)
        XCTAssertEqual(ReplaySkinnedAthleteContactSurface.maximumPayloadBytes, 256 * 1_024)
        XCTAssertThrowsError(try ReplaySkinnedAthleteContactSurface(data: data, motion: motion,
            assetSHA256: assetHash, motionSHA256: ReplaySkinnedAthleteProvider.motionSHA256))
    }

    func testCompleteContactMinimaMatchCanonicalWeightedPoseReferences() throws {
        let (motion, _, surface) = try prepare()
        let data = try derivedData("ReplayXI-Low102-Canonical-03/native-admission-fixture.json",
            hash: fixtureHash, maximumBytes: 2 * 1_024 * 1_024)
        let fixture = try JSONDecoder().decode(Fixture.self, from: data)
        XCTAssertEqual(fixture.poses.count, 4)
        var errors: [String: Float] = [:]
        for sample in fixture.poses {
            XCTAssertEqual(sample.translations.count, 80)
            XCTAssertEqual(sample.rotations.count, 80)
            XCTAssertEqual(sample.scales.count, 80)
            var pose = motion.makePoseBuffer()
            for index in motion.joints.indices {
                let t = sample.translations[index], r = sample.rotations[index], s = sample.scales[index]
                pose.translations[index] = [t[0], t[1], t[2]]
                pose.rotations[index] = simd_quatf(ix: r[0], iy: r[1], iz: r[2], r: r[3])
                pose.scales[index] = [s[0], s[1], s[2]]
            }
            motion.rebuildModelSpaceTransforms(in: &pose)
            let expected = try XCTUnwrap(sample.expectedPositionsWithRootOffset.values
                .flatMap { $0 }.map { $0[1] - sample.groundOffset }.min())
            let measured = surface.minimumY(in: pose)
            errors[sample.name] = abs(measured - expected)
            XCTAssertEqual(measured, expected, accuracy: 0.000_008, sample.name)
            let floor = motion.geometry.restMinY + surface.paddingMetres
            let lift = surface.raiseAboveFloor(floor, in: &pose)
            XCTAssertGreaterThanOrEqual(lift, 0)
            XCTAssertGreaterThanOrEqual(surface.minimumY(in: pose), floor - 0.000_001)
            let repeated = surface.raiseAboveFloor(floor, in: &pose)
            XCTAssertLessThanOrEqual(repeated, 0.000_001)
        }
        let attachment = XCTAttachment(data: try JSONEncoder().encode(errors), uniformTypeIdentifier: "public.json")
        attachment.name = "ReplayXI-LowContact112-CanonicalMinimumErrors.json"
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    func testLowProfileRejectsMissingOrMismatchedCanonicalMetadata() throws {
        let (motion, data, _) = try prepare()
        let original = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        for (key, value): (String, Any) in [
            ("schemaVersion", 1), ("sourceVertexCount", 1_706), ("profileKind", "sparse"),
            ("jointNames", Array(motion.jointNames.reversed())), ("rootLiftBakedIntoPoints", true),
            ("rootBaseLift", 0), ("inverseBindMatricesColumnMajor", []),
            ("assetSHA256", String(repeating: "0", count: 64))
        ] {
            var document = original
            document[key] = value
            XCTAssertThrowsError(try decode(JSONSerialization.data(withJSONObject: document), motion: motion), key)
        }
        for key in ["inverseBindMatricesColumnMajor", "jointNames", "rootBaseLift", "profileKind"] {
            var document = original
            document.removeValue(forKey: key)
            XCTAssertThrowsError(try decode(JSONSerialization.data(withJSONObject: document), motion: motion), key)
        }
        var document = original
        var vertices = try XCTUnwrap(document["vertices"] as? [[String: Any]])
        vertices.removeLast()
        document["vertices"] = vertices
        XCTAssertThrowsError(try decode(JSONSerialization.data(withJSONObject: document), motion: motion))
    }

    func testLowProfileRejectsAnotherBindBasisAndOversizedData() throws {
        let (motion, data, _) = try prepare()
        let original = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let originalMatrices = try XCTUnwrap(original["inverseBindMatricesColumnMajor"] as? [[Double]])
        for amount in [0.001, 0.1, 5] {
            var document = original
            var matrices = originalMatrices
            matrices[0][12] += amount
            document["inverseBindMatricesColumnMajor"] = matrices
            XCTAssertThrowsError(try decode(JSONSerialization.data(withJSONObject: document), motion: motion))
        }
        var document = original
        var matrices = originalMatrices
        matrices[0][3] = 0.000_01
        document["inverseBindMatricesColumnMajor"] = matrices
        XCTAssertThrowsError(try decode(JSONSerialization.data(withJSONObject: document), motion: motion))
        XCTAssertThrowsError(try decode(Data(repeating: 32, count: 512 * 1_024 + 1), motion: motion))
    }
}
