import CryptoKit
import Foundation
import RealityKit
import XCTest
@testable import ReplayXI

@MainActor
final class ReplayWorldPreviewTests: XCTestCase {
    func testSyntheticWorldPreviewUsesFourBatchedMeshesWithinBudget() {
        let root = ReplayWorldPreviewFactory.make()

        XCTAssertEqual(root.name, ReplayWorldPreviewFactory.rootName)
        XCTAssertEqual(root.children.count, ReplayWorldPreviewFactory.materialGroupCount)
        XCTAssertEqual(ReplayWorldPreviewFactory.splatCount, 640)
        XCTAssertEqual(ReplayWorldPreviewFactory.estimatedTriangleCount, 2_560)
        XCTAssertEqual(ReplayWorldPreviewFactory.estimatedVertexCount, 7_680)
        XCTAssertTrue(root.children.allSatisfy { $0 is ModelEntity })
        XCTAssertEqual(
            Set(root.children.map(\.name)),
            Set((0..<4).map { "world-preview-surfels-\($0)" })
        )
    }

    func testWorldScenarioIsExplicitlySyntheticAndUsesTrackBoundTeachingMarks() throws {
        let scenario = try XCTUnwrap(DemoScenarios.scenario(for: .realWorldReplay))

        XCTAssertEqual(scenario.id, "real-world-match-replay")
        XCTAssertTrue(scenario.matchContext.contains("ORIGINAL SYNTHETIC"))
        XCTAssertEqual(scenario.players.count, 22)
        XCTAssertEqual(scenario.duration, 32)
        XCTAssertEqual(scenario.coachMarks.filter(\.followsPlayerTracks).count, 3)
        XCTAssertTrue(scenario.coachMarks.contains { $0.kind == .space && !$0.followsPlayerTracks })
    }

    func testWorldPreviewIsScopedOnlyToRealWorldScenario() throws {
        let world = try XCTUnwrap(DemoScenarios.scenario(for: .realWorldReplay))
        let playback = try XCTUnwrap(DemoScenarios.scenario(for: .squadReplay))

        XCTAssertNotNil(
            PitchSceneFactory.makeMatchRoot(for: world).findEntity(
                named: ReplayWorldPreviewFactory.rootName
            )
        )
        XCTAssertNil(
            PitchSceneFactory.makeMatchRoot(for: playback).findEntity(
                named: ReplayWorldPreviewFactory.rootName
            )
        )
    }

    func testAdmissionReceiptLoadsExactAssetAndHashMismatchFailsClosed() throws {
        var fixture = try makeAdmissionBundle()
        defer { try? FileManager.default.removeItem(at: fixture.directory) }

        let admitted = ReplayWorldPreviewFactory.make(in: fixture.bundle)

        XCTAssertEqual(admitted.name, ReplayWorldPreviewFactory.admittedRootName)
        XCTAssertEqual(admitted.children.count, 1)
        XCTAssertEqual(admitted.children.first?.name, "manifest-admitted-visual-context")

        fixture.receipt["runtimeAsset"] = [
            "resourceName": fixture.assetName,
            "sha256": String(repeating: "0", count: 64),
            "byteCount": fixture.assetData.count,
        ]
        try JSONSerialization.data(
            withJSONObject: fixture.receipt,
            options: [.prettyPrinted, .sortedKeys]
        ).write(to: fixture.receiptURL, options: .atomic)

        let fallback = ReplayWorldPreviewFactory.make(in: fixture.bundle)
        XCTAssertEqual(fallback.name, ReplayWorldPreviewFactory.rootName)
        XCTAssertEqual(fallback.children.count, ReplayWorldPreviewFactory.materialGroupCount)
    }

    private func makeAdmissionBundle() throws -> AdmissionFixture {
        let sourceAsset = try XCTUnwrap(
            Bundle.main.url(
                forResource: ReplayImportedAthleteProvider.resourceName,
                withExtension: "usdz"
            )
        )
        let assetData = try Data(contentsOf: sourceAsset, options: .mappedIfSafe)
        let digest = SHA256.hash(data: assetData)
            .map { String(format: "%02x", $0) }
            .joined()

        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("ReplayXIWorldAdmission-\(UUID().uuidString)")
            .appendingPathExtension("bundle")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let info: [String: Any] = [
            "CFBundleIdentifier": "com.humansbeforemachines.replayxi.world-test.\(UUID().uuidString)",
            "CFBundleName": "Replay XI World Admission Test",
            "CFBundlePackageType": "BNDL",
            "CFBundleVersion": "1",
        ]
        try PropertyListSerialization.data(fromPropertyList: info, format: .xml, options: 0)
            .write(to: directory.appendingPathComponent("Info.plist"), options: .atomic)

        let assetName = "ReplayXIAdmittedWorld.usdz"
        try assetData.write(to: directory.appendingPathComponent(assetName), options: .atomic)
        let receipt: [String: Any] = [
            "schemaVersion": 1,
            "admissionVersion": 1,
            "manifestSHA256": String(repeating: "a", count: 64),
            "worldID": "right-wing-overlap",
            "displayName": "Real World Match Replay",
            "source": [
                "kind": "original-synthetic",
                "owner": "Replay XI test fixture",
                "rightsBasis": "Original deterministic test asset.",
                "containsRealPlayerLikenesses": false,
            ],
            "coordinates": [
                "upAxis": "Y",
                "metresPerUnit": 1,
                "pitchLengthMetres": 105,
                "pitchWidthMetres": 68,
                "origin": "pitch-centre",
                "positiveZ": "home-attacking-direction",
                "positiveX": "home-right",
            ],
            "tacticalTruth": [
                "generatedPixelsAreAuthoritative": false,
                "trackingAuthority": "Replay XI deterministic authored tracking fixture",
            ],
            "runtimeAsset": [
                "resourceName": assetName,
                "sha256": digest,
                "byteCount": assetData.count,
            ],
        ]
        let receiptURL = directory.appendingPathComponent(
            "\(ReplayWorldPreviewFactory.admissionReceiptResourceName).json"
        )
        try JSONSerialization.data(withJSONObject: receipt, options: [.prettyPrinted, .sortedKeys])
            .write(to: receiptURL, options: .atomic)
        let bundle = try XCTUnwrap(Bundle(url: directory))
        return AdmissionFixture(
            bundle: bundle,
            directory: directory,
            receiptURL: receiptURL,
            assetName: assetName,
            assetData: assetData,
            receipt: receipt
        )
    }
}

private struct AdmissionFixture {
    let bundle: Bundle
    let directory: URL
    let receiptURL: URL
    let assetName: String
    let assetData: Data
    var receipt: [String: Any]
}
