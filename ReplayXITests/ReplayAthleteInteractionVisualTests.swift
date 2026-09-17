import CoreGraphics
import Foundation
import RealityKit
import UIKit
import XCTest
@testable import ReplayXI

private final class ReplayInteractionRenderCompletion: @unchecked Sendable {
    private let lock = NSLock()
    private var completed = false
    func finish() { lock.withLock { completed = true } }
    var isComplete: Bool { lock.withLock { completed } }
}

/// Thirteen fixed-camera native frames. The ball marks the recorded contact
/// reference, not a separate claim that this still-image fixture simulates it.
@MainActor
final class ReplayAthleteInteractionVisualTests: XCTestCase {
    func testCapturesPassPhasesAcrossAllLODsAndHeaderSaveUpperBody() async throws {
        reset()
        defer { reset() }
        let player = PlayerTrack(id: "interaction-render", displayName: "Contact", role: "CM", shirtNumber: 8,
            team: .away, isGoalkeeper: false,
            keyframes: [.init(time: 0, position: .zero, facingDegrees: 0),
                        .init(time: 2, position: .zero, facingDegrees: 0)])
        try ReplaySkinnedAthleteProvider.prewarm()
        try ReplaySkinnedAthleteProvider.prewarmLowDetail()
        try ReplayFarAthleteHeadProvider.prewarm()
        try ReplayArticulatedFarProvider.prewarm()
        try ReplayArticulatedFarKitProvider.prewarm()
        try ReplayAthleteFactory.prewarm(for: [player], lods: [.far])
        try ReplayStrategyBallProvider.prewarm()
        let calibration = try await calibrate()
        var report: [[String: Any]] = []
        for detail in ["far", "near", "low"] {
            let far = detail == "far" ? try ReplayAthleteFactory.make(for: player, lod: .far) : nil
            let skin = detail != "far" ? try ReplaySkinnedAthleteProvider.make(
                for: player, detail: detail == "near" ? .near : .lowDetail) : nil
            let avatar = try XCTUnwrap(far?.root ?? skin?.root)
            let poses: [(String, ReplayAthleteInteractionCue.Kind, Double, SIMD3<Float>)] = [
                ("wind-up", .pass, 0.82, [0.137, 0.11, 0.42]),
                ("contact", .pass, 1, [0.137, 0.11, 0.42]),
                ("follow-through", .pass, 1.20, [0.137, 0.11, 0.42]),
                ("low-parry", .save, 1, [0, 0.65, 0.40])
            ] + (detail == "far" ? [
                ("header", .header, 1, [0, 1.65, 0.25])
            ] : [])
            for (label, kind, time, centre) in poses {
                let cue = ReplayAthleteInteractionCue(playerID: player.id, kind: kind,
                    contactTime: 1, startTime: 0.7, endTime: 1.4, kickingLeg: .right,
                    contactBallWorldPosition: centre, outgoingDirectionWorld: [0, 0, 1],
                    supportFootWorldPosition: [-0.137, 0, 0.035])
                let presentation = PlayerPose(position: .zero, facingDegrees: 0)
                if let far {
                    ReplayAthleteMotion.update(far, from: player, at: time,
                        lookTargetWorldPosition: centre, interaction: cue, presentationPose: presentation)
                    XCTAssertEqual(far.metrics.modelEntities, 7)
                    XCTAssertEqual(far.joints.articulatedFar?.supportPointCount, 426)
                }
                if let skin {
                    XCTAssertTrue(skin.update(at: time, track: player, locomotion: player.locomotion(at: time),
                        lookTarget: centre, ballAction: nil, interaction: cue, presentationPose: presentation))
                    XCTAssertEqual(skin.model.jointTransforms.count, 80)
                }
                XCTAssertEqual(avatar.scale, .one)
                let scene = Entity()
                scene.addChild(avatar)
                let ball = try XCTUnwrap(ReplayStrategyBallProvider.makeInstance())
                ball.position = centre
                scene.addChild(ball)
                let floor = ModelEntity(mesh: .generateBox(size: [1.6, 0.008, 1.6]),
                    materials: [SimpleMaterial(color: UIColor(red: 0.07, green: 0.12, blue: 0.09, alpha: 1),
                                               roughness: 1, isMetallic: false)])
                floor.position.y = -0.006
                scene.addChild(floor)
                let camera = PerspectiveCamera()
                camera.camera = .init(near: 0.05, far: 20, fieldOfViewInDegrees: 40)
                camera.look(at: [0, 0.9, 0], from: [2.7, 1.5, 4], relativeTo: nil)
                let key = DirectionalLight()
                key.light.intensity = 2_200
                key.look(at: [0, 0.9, 0], from: [3, 4, 3], relativeTo: nil)
                let fill = DirectionalLight()
                fill.light.intensity = 500
                fill.look(at: [0, 0.9, 0], from: [-3, 2, 2], relativeTo: nil)
                let frame = try await render([scene, camera, key, fill], camera: camera, size: 512)
                var count = 0, left = 512, top = 512, right = -1, bottom = -1
                for y in 0..<512 { for x in 0..<512 {
                    let pixel = frame.rgba(x: x, y: y, topFirst: calibration.rawRowsAreTopFirst)
                    if pixel[0] > 8 || pixel[1] > 8 || pixel[2] > 8 {
                        count += 1; left = min(left, x); right = max(right, x)
                        top = min(top, y); bottom = max(bottom, y)
                    }
                } }
                XCTAssertGreaterThan(count, 2_000)
                XCTAssertLessThan(count, 512 * 512 / 2)
                XCTAssertGreaterThan(left, 4); XCTAssertGreaterThan(top, 4)
                XCTAssertLessThan(right, 507); XCTAssertLessThan(bottom, 507)
                let name = "ReplayXI-Interaction125-\(detail)-\(label)"
                let image = XCTAttachment(data: try ReplayRealityRendererAudit.png(frame, calibration: calibration),
                                          uniformTypeIdentifier: "public.png")
                image.name = name + ".png"; image.lifetime = .keepAlways; add(image)
                report.append(["name": name, "time": time, "kind": kind.rawValue,
                               "contactBallCentreMetres": [centre.x, centre.y, centre.z],
                               "rootScale": [avatar.scale.x, avatar.scale.y, avatar.scale.z],
                               "nonBackgroundPixels": count, "bounds": [left, top, right, bottom],
                               "cameraPosition": [2.7, 1.5, 4], "cameraTarget": [0, 0.9, 0], "cameraFOV": 40,
                               "scope": "Native pose audit; fixed contact-reference ball, no moving ball or UI/headset claim"])
                avatar.removeFromParent()
            }
        }
        XCTAssertEqual(report.count, 13)
        let receipt = XCTAttachment(data: try JSONSerialization.data(withJSONObject: report, options: [.sortedKeys]),
                                    uniformTypeIdentifier: "public.json")
        receipt.name = "ReplayXI-Interaction125-Native-Frames.json"
        receipt.lifetime = .keepAlways; add(receipt)
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
        XCTAssertEqual(matches.count, 1)
        let calibration = try XCTUnwrap(matches.first)
        let data = try JSONEncoder().encode(calibration)
        let receipt = XCTAttachment(data: data, uniformTypeIdentifier: "public.json")
        receipt.name = "ReplayXI-Interaction125-Calibration.json"
        receipt.lifetime = .keepAlways; add(receipt)
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
        let completion = expectation(description: "Interaction native frame")
        let flag = ReplayInteractionRenderCompletion()
        try renderer.updateAndRender(deltaTime: 0, cameraOutput: output, onComplete: { _ in
            flag.finish(); completion.fulfill()
        })
        await fulfillment(of: [completion], timeout: 10)
        guard flag.isComplete else { throw ReplayRealityRendererAudit.Failure.unsupported("Interaction frame timed out") }
        return try withExtendedLifetime(renderer) { try ReplayRealityRendererAudit.read(texture) }
    }

    private func reset() {
        ReplayArticulatedFarKitProvider.resetForTesting()
        ReplayArticulatedFarProvider.resetForTesting()
        ReplayFarAthleteHeadProvider.resetForTesting()
        ReplaySkinnedAthleteProvider.resetForTesting()
        ReplayAthleteHeadProvider.resetForTesting()
        ReplayFarAthletePaletteProvider.resetForTesting()
        ReplayStrategyBallProvider.resetForTesting()
    }
}
