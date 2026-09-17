import CoreGraphics
import Foundation
import RealityKit
import UIKit
import XCTest
@testable import ReplayXI

private final class ReferenceStudyRenderCompletion: @unchecked Sendable {
    private let lock = NSLock()
    private var completed = false
    func finish() { lock.withLock { completed = true } }
    var isComplete: Bool { lock.withLock { completed } }
}

/// Five match captures, one actual Factory scene at each study's
/// final native shooting contact. The calibration swatch is not a match frame.
/// Only the table root's room placement is normalised for the fixed metre-space
/// audit camera. Player, pitch, ball, animation, labels and physics stay native.
@MainActor
final class FootballReferenceStudyVisualTests: XCTestCase {
    func testFiveStudiesAtTheirFinalNativeShootingContact() async throws {
        resetOptionalProviders()
        defer {
            // Optional imported/skinned visuals change which Factory branch
            // later tests exercise. Restore their cold fallback baseline even
            // when admission, physics, calibration or rendering throws.
            resetOptionalProviders()
            XCTAssertFalse(ReplaySkinnedAthleteProvider.isPrewarmed)
            XCTAssertFalse(ReplaySkinnedAthleteProvider.isLowDetailPrewarmed)
            XCTAssertFalse(ReplayArticulatedFarProvider.isPrewarmed)
            XCTAssertFalse(ReplayArticulatedFarKitProvider.isPrewarmed)
            XCTAssertFalse(ReplayFarAthleteHeadProvider.isPrewarmed)
            XCTAssertFalse(ReplayAthleteHeadProvider.isPrewarmed)
            XCTAssertFalse(ReplayStrategyBallProvider.isPrewarmed)
            XCTAssertEqual(ReplayNativeBallPhysics.cacheCountForTesting, 0)
        }
        try ReplaySkinnedAthleteProvider.prewarm()
        try ReplaySkinnedAthleteProvider.prewarmLowDetail()
        try ReplayFarAthleteHeadProvider.prewarm()
        try ReplayArticulatedFarProvider.prewarm()
        try ReplayArticulatedFarKitProvider.prewarm()
        try ReplayStrategyPitchProvider.prewarm()
        try ReplayStrategyBallProvider.prewarm()
        let calibration = try await calibrate()
        var receipts: [[String: Any]] = []

        for scenario in FootballReferenceScenarios.all {
            let plan = try XCTUnwrap(FootballReferenceScenarios.touches(for: scenario))
            let recording = try await ReplayNativeBallPhysics.bake(track: scenario.ball,
                players: scenario.players, plannedTouches: plan)
            XCTAssertEqual(recording.missedTouchCount, 0, scenario.id)
            XCTAssertEqual(recording.touches.count, plan.count, scenario.id)
            let contact = try XCTUnwrap(recording.touches.last { $0.kind == .shot || $0.kind == .header })
            XCTAssertTrue(recording.samples.contains {
                $0.time > contact.time && $0.position.z > 52.61
                    && abs($0.position.x) < 3.55 && $0.position.y < 2.30
            }, "The captured shooting contact must belong to a completed goal: \(scenario.id)")
            try ReplayAthleteFactory.prewarm(for: scenario.players)
            let root = PitchSceneFactory.makeMatchRoot(for: scenario, nativeRecording: recording)
            defer { for child in Array(root.children) { child.removeFromParent() } }
            XCTAssertTrue(PitchSceneFactory.nativeBallRecordingForTesting(in: root) === recording)
            PitchSceneFactory.update(root: root, scenario: scenario, time: contact.time,
                viewMode: .tacticalTable, perspectiveID: contact.playerID, marks: [],
                showsLaneLens: false, isDrawing: false, positionalOriginTransform: nil,
                emphasizesBall: true)

            let pitch = try XCTUnwrap(root.findEntity(named: "pitch"))
            XCTAssertNotNil(pitch.components[ReplayStrategyPitchProvider.Admission.self])
            XCTAssertNotNil(pitch.findEntity(named: "field-surface"))
            XCTAssertNotNil(pitch.findEntity(named: "pitch-markings-and-goals"))
            let ball = try XCTUnwrap(root.findEntity(named: "ball"))
            XCTAssertNotNil(ball.findEntity(named: ReplayStrategyBallProvider.visualRootName))
            let players = try XCTUnwrap(root.findEntity(named: "players-root"))
            XCTAssertEqual(players.children.count, 22)
            let shooter = try XCTUnwrap(players.findEntity(named: "player-\(contact.playerID)"))
            XCTAssertTrue(shooter.isEnabledInHierarchy)
            XCTAssertTrue(models(in: shooter).contains { $0.jointNames.count == 80 && $0.isEnabledInHierarchy },
                          "The selected shooter must use the actual admitted skinned body")
            let ballSample = recording.sample(at: contact.time)
            XCTAssertEqual(ball.position, [ballSample.position.x, max(ballSample.position.y, 0.11), ballSample.position.z])
            XCTAssertEqual(ball.scale, .one)

            // Keep the app's actual table presentation and all entity-local
            // poses, but place the whole table at metre scale for a repeatable
            // external camera. This is not a headset/UI screenshot.
            root.transform = Transform()
            let target = SIMD3<Float>(contact.position.x * 0.35, 1, 43)
            let cameraPosition = target + SIMD3<Float>(14, 27, 33)
            let camera = PerspectiveCamera()
            camera.camera = .init(near: 0.05, far: 180, fieldOfViewInDegrees: 48)
            camera.look(at: target, from: cameraPosition, relativeTo: nil)
            let key = DirectionalLight()
            key.light.intensity = 2_200
            key.look(at: target, from: target + [20, 40, 30], relativeTo: nil)
            let fill = DirectionalLight()
            fill.light.intensity = 500
            fill.look(at: target, from: target + [-25, 25, 20], relativeTo: nil)
            let frame = try await render([root, key, fill, camera], camera: camera, size: 512)
            var nonBackgroundPixels = 0
            for y in 0..<frame.height { for x in 0..<frame.width {
                let pixel = frame.rgba(x: x, y: y, topFirst: calibration.rawRowsAreTopFirst)
                if pixel[0] > 8 || pixel[1] > 8 || pixel[2] > 8 { nonBackgroundPixels += 1 }
            } }
            XCTAssertGreaterThan(nonBackgroundPixels, 512 * 512 / 4,
                                 "The attacking third must occupy a useful part of the capture")
            let name = "ReplayXI-Reference127-\(scenario.id)-final-contact"
            let image = XCTAttachment(data: try ReplayRealityRendererAudit.png(frame, calibration: calibration),
                                      uniformTypeIdentifier: "public.png")
            image.name = name + ".png"
            image.lifetime = .keepAlways
            add(image)
            receipts.append([
                "name": name, "scenario": scenario.id, "shotPlayer": contact.playerID,
                "nativeContactTime": contact.time, "plannedTouches": plan.count,
                "nativeTouches": recording.touches.count, "missedTouches": recording.missedTouchCount,
                "nativeSamples": recording.samples.count,
                "contactBallCentre": vector(contact.position), "displayedBallCentre": vector(ball.position),
                "cameraPosition": vector(cameraPosition), "cameraTarget": vector(target), "cameraVerticalFOV": 48,
                "frameSize": [512, 512], "nonBackgroundPixels": nonBackgroundPixels,
                "pitchAssetSHA256": ReplayStrategyPitchProvider.assetSHA256,
                "ballAssetSHA256": ReplayStrategyBallProvider.assetSHA256,
                "nearPlayerAssetSHA256": ReplaySkinnedAthleteProvider.assetSHA256,
                "scope": "Actual Factory table scene, fixed metre-space attacking-third camera; no UI, headset, motion-video or performance claim. Broadcast-inspired authored reconstruction, not recovered tracking."
            ])
        }
        XCTAssertEqual(receipts.count, 5)
        let receipt = XCTAttachment(data: try JSONSerialization.data(withJSONObject: receipts,
            options: [.prettyPrinted, .sortedKeys]), uniformTypeIdentifier: "public.json")
        receipt.name = "ReplayXI-Reference127-Five-Study-Frames.json"
        receipt.lifetime = .keepAlways
        add(receipt)
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
        camera.camera = .init(near: 0.05, far: 10, fieldOfViewInDegrees: 90)
        camera.position = [0, 0, 2]
        let probe = try ReplayRealityRendererAudit.probe(await render([root, camera], camera: camera, size: 256))
        let matches = probe.candidates.filter { $0.maximumChannelError <= 4 }
        XCTAssertEqual(matches.count, 1, "Colour, channels and row direction need one unambiguous calibration")
        let calibration = try XCTUnwrap(matches.first)
        let receipt = XCTAttachment(data: try JSONEncoder().encode(calibration), uniformTypeIdentifier: "public.json")
        receipt.name = "ReplayXI-Reference125-Calibration.json"
        receipt.lifetime = .keepAlways
        add(receipt)
        return calibration
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
        let completion = expectation(description: "Reference study native GPU frame")
        let flag = ReferenceStudyRenderCompletion()
        try renderer.updateAndRender(deltaTime: 0, cameraOutput: output, onComplete: { _ in
            flag.finish()
            completion.fulfill()
        })
        await fulfillment(of: [completion], timeout: 10)
        guard flag.isComplete else { throw ReplayRealityRendererAudit.Failure.unsupported("Reference study frame timed out") }
        return try withExtendedLifetime(renderer) { try ReplayRealityRendererAudit.read(texture) }
    }

    private func vector(_ point: SIMD3<Float>) -> [Float] { [point.x, point.y, point.z] }

    private func resetOptionalProviders() {
        ReplayArticulatedFarKitProvider.resetForTesting()
        ReplayArticulatedFarProvider.resetForTesting()
        ReplayFarAthleteHeadProvider.resetForTesting()
        ReplaySkinnedAthleteProvider.resetForTesting()
        ReplayAthleteHeadProvider.resetForTesting()
        ReplayFarAthletePaletteProvider.resetForTesting()
        ReplayStrategyBallProvider.resetForTesting()
        ReplayNativeBallPhysics.resetCacheForTesting()
    }

    private func models(in root: Entity) -> [ModelEntity] {
        ((root as? ModelEntity).map { [$0] } ?? []) + root.children.flatMap { models(in: $0) }
    }
}
