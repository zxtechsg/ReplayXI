import CoreGraphics
import Foundation
import Metal
import RealityKit
import UIKit
import XCTest
@testable import ReplayXI

private final class ReplayStadiumCaptureCompletion169: @unchecked Sendable {
    private let lock = NSLock()
    private var complete = false
    func finish() { lock.withLock { complete = true } }
    var isComplete: Bool { lock.withLock { complete } }
}

/// Native offscreen evidence for the supplied and fallback stadiums. These images
/// do not validate SwiftUI, immersion transitions, passthrough or headset cost.
@MainActor
final class ReplayStadiumEnvironmentVisual169Tests: XCTestCase {
    func testCapturesLocalStadiumFromHeadHeightInsideBowl169() async throws {
        ReplayStadiumEnvironment.prewarm()
        XCTAssertTrue(ReplayStadiumEnvironment.preparationSucceeded)
        let calibration = try await calibrate()
        let sky = ReplayStadiumEnvironment.makeSkyRoot()
        let stadium = ReplayStadiumEnvironment.makeStadium()
        // Existing shipping pitch lines provide scale. No new grass surface,
        // players, physics, imported assets or scene preparation are needed.
        let markings = ModelEntity(mesh: ReplayPitchMeshLibrary.markingsAndGoals,
            materials: [UnlitMaterial(color: .white, applyPostProcessToneMap: false)])
        markings.name = "existing-pitch-markings-for-stadium-audit"
        let position = SIMD3<Float>(0, 1.7, 8)
        let target = SIMD3<Float>(0, 7, -62)
        let camera = PerspectiveCamera()
        camera.camera = .init(near: 0.05, far: 400, fieldOfViewInDegrees: 70)
        camera.look(at: target, from: position, relativeTo: nil)

        let background = try await render(entities: [sky, markings, camera], camera: camera, size: 768)
        let visible = try await render(entities: [sky, stadium, markings, camera], camera: camera, size: 768)
        var changedPixels = 0, tealTierPixels = 0, exposedClearPixels = 0
        for y in 0..<visible.height {
            for x in 0..<visible.width {
                let a = background.rgba(x: x, y: y, topFirst: calibration.rawRowsAreTopFirst)
                let b = visible.rgba(x: x, y: y, topFirst: calibration.rawRowsAreTopFirst)
                let difference = (0..<3).reduce(0) { $0 + abs(Int(a[$1]) - Int(b[$1])) }
                if difference > 12 {
                    changedPixels += 1
                    // A broad gamut-tolerant check of changed teal pixels;
                    // source geometry and exact material counts have separate tests.
                    if b[1] > 40, b[2] > 45, Float(b[1]) > Float(b[0]) * 1.6 {
                        tealTierPixels += 1
                    }
                }
                if b[0] > 200, b[1] < 20, b[2] > 200 { exposedClearPixels += 1 }
            }
        }
        let pixels = visible.width * visible.height
        XCTAssertGreaterThan(changedPixels, pixels / 30,
                             "The stadium must be visible from inside its bowl")
        XCTAssertGreaterThan(tealTierPixels, 100,
                             "Visible tier faces must produce more than isolated pixels")
        XCTAssertEqual(exposedClearPixels, 0,
                       "The inward sky and floor must cover the magenta diagnostic background")

        try attachPNG(visible, calibration: calibration, name: "ReplayXI-LocalProcedural-Stadium169-head-height.png")
        try attachPNG(background, calibration: calibration, name: "ReplayXI-LocalProcedural-Stadium169-sky-floor-control.png")
        let report: [String: Any] = [
            "source": ReplayStadiumEnvironment.sourceDescription,
            "scope": "Native offscreen render of local procedural stadium, sky and floor with existing pitch lines. No Tripo, UI, passthrough, headset or performance claim.",
            "size": [visible.width, visible.height],
            "cameraMetres": [position.x, position.y, position.z],
            "targetMetres": [target.x, target.y, target.z],
            "verticalFieldOfViewDegrees": 70,
            "environmentMaterialDraws": 6,
            "existingPitchMaterialDraws": 1,
            "environmentTriangles": ReplayStadiumEnvironment.geometry.triangleCount,
            "changedPixelsVersusSkyFloorControl": changedPixels,
            "changedTealTierPixels": tealTierPixels,
            "exposedDiagnosticBackgroundPixels": exposedClearPixels,
            "calibrationMaximumChannelError": calibration.maximumChannelError,
            "calibratedGamut": calibration.gamut.rawValue
        ]
        let attachment = XCTAttachment(data: try JSONSerialization.data(withJSONObject: report, options: [.sortedKeys]),
                                       uniformTypeIdentifier: "public.json")
        attachment.name = "ReplayXI-LocalProcedural-Stadium169-capture.json"
        attachment.lifetime = .keepAlways
        add(attachment)
        withExtendedLifetime([sky, stadium, markings, camera]) {}
    }

    func testCapturesSuppliedStadiumInFourDirectionsAndOverview169() async throws {
        guard ReplayStadiumAssetProvider.assetSHA256.count == 64,
              ReplayStadiumAssetProvider.expectedBounds != nil else {
            throw XCTSkip("The supplied stadium hash and bounds have not been audited yet")
        }
        ReplayStadiumAssetProvider.resetForTesting()
        defer { ReplayStadiumAssetProvider.resetForTesting() }
        try ReplayStadiumAssetProvider.prewarm()
        let stadium = try XCTUnwrap(ReplayStadiumAssetProvider.makeInstance())
        let admission = try XCTUnwrap(stadium.components[ReplayStadiumAssetProvider.Admission.self])
        XCTAssertEqual(admission.assetSHA256, ReplayStadiumAssetProvider.assetSHA256)
        XCTAssertGreaterThan(admission.triangles, 0)
        XCTAssertLessThanOrEqual(admission.triangles, ReplayStadiumAssetProvider.triangleBudget)

        ReplayStadiumEnvironment.prewarm()
        let sky = ReplayStadiumEnvironment.makeSkyRoot()
        try ReplayStrategyPitchProvider.prewarm()
        let pitch = try XCTUnwrap(ReplayStrategyPitchProvider.makeInstance())
        // Match the scene's unlit white-line treatment while retaining the
        // admitted turf textures and the existing second (net) material slot.
        for model in ReplayStrategyPitchProvider.models(in: pitch)
            where model.name == "pitch-markings-and-goals" {
            if var component = model.model, !component.materials.isEmpty {
                component.materials[0] = UnlitMaterial(color: .white, applyPostProcessToneMap: false)
                model.model = component
            }
        }
        let calibration = try await calibrate()
        let views: [(name: String, position: SIMD3<Float>, target: SIMD3<Float>)] = [
            ("north", [0, 1.7, 0], [0, 3, -70]),
            ("east", [0, 1.7, 0], [70, 3, 0]),
            ("south", [0, 1.7, 0], [0, 3, 70]),
            ("west", [0, 1.7, 0], [-70, 3, 0]),
            ("overview", [105, 88, 135], [0, 4, 0])
        ]
        var rows: [[String: Any]] = []
        for view in views {
            let camera = PerspectiveCamera()
            camera.camera = .init(near: 0.05, far: 600, fieldOfViewInDegrees: 70)
            camera.look(at: view.target, from: view.position, relativeTo: nil)
            let control = try await render(entities: [sky, pitch, camera], camera: camera, size: 768)
            let frame = try await render(entities: [sky, stadium, pitch, camera], camera: camera, size: 768)
            var changed = 0, visibleChanged = 0, exposedClear = 0
            var minimumX = frame.width, minimumY = frame.height, maximumX = -1, maximumY = -1
            var channelDifferenceTotal = 0
            for y in 0..<frame.height {
                for x in 0..<frame.width {
                    let a = control.rgba(x: x, y: y, topFirst: calibration.rawRowsAreTopFirst)
                    let b = frame.rgba(x: x, y: y, topFirst: calibration.rawRowsAreTopFirst)
                    let difference = (0..<3).reduce(0) { $0 + abs(Int(a[$1]) - Int(b[$1])) }
                    channelDifferenceTotal += difference
                    if difference > 12 {
                        changed += 1
                        minimumX = min(minimumX, x); maximumX = max(maximumX, x)
                        minimumY = min(minimumY, y); maximumY = max(maximumY, y)
                        if max(b[0], max(b[1], b[2])) > 12 { visibleChanged += 1 }
                    }
                    if b[0] > 200, b[1] < 20, b[2] > 200 { exposedClear += 1 }
                }
            }
            let pixels = frame.width * frame.height
            XCTAssertGreaterThan(changed, pixels / 200,
                                 "\(view.name): the imported bowl must visibly change the pitch/sky control")
            XCTAssertGreaterThan(visibleChanged, pixels / 1_000,
                                 "\(view.name): imported geometry must show more than a black silhouette")
            XCTAssertGreaterThan(maximumX - minimumX, frame.width / 8,
                                 "\(view.name): the visible stadium must cover a broad horizontal area")
            XCTAssertGreaterThan(maximumY - minimumY, frame.height / 32,
                                 "\(view.name): the visible stadium must have appreciable height")
            XCTAssertEqual(exposedClear, 0, "\(view.name): sky/floor must cover the diagnostic background")
            try attachPNG(frame, calibration: calibration,
                          name: "ReplayXI-Supplied-Stadium169-\(view.name).png")
            try attachPNG(control, calibration: calibration,
                          name: "ReplayXI-Supplied-Stadium169-\(view.name)-pitch-sky-control.png")
            rows.append([
                "view": view.name,
                "cameraMetres": [view.position.x, view.position.y, view.position.z],
                "targetMetres": [view.target.x, view.target.y, view.target.z],
                "size": [frame.width, frame.height],
                "changedPixels": changed,
                "visibleChangedPixels": visibleChanged,
                "changedPixelBounds": [minimumX, minimumY, maximumX, maximumY],
                "meanChannelDifference": Double(channelDifferenceTotal) / Double(pixels * 3),
                "exposedDiagnosticBackgroundPixels": exposedClear
            ])
            withExtendedLifetime(camera) {}
        }
        let bounds = stadium.visualBounds(relativeTo: stadium)
        let report: [String: Any] = [
            "source": admission.source,
            "assetSHA256": admission.assetSHA256,
            "scope": "Native supplied stadium with the existing strategy pitch and local sky. No UI, passthrough, headset or performance claim.",
            "stadiumTriangles": admission.triangles,
            "stadiumMaterialDraws": admission.materialDraws,
            "stadiumBoundsMinMetres": [bounds.min.x, bounds.min.y, bounds.min.z],
            "stadiumBoundsMaxMetres": [bounds.max.x, bounds.max.y, bounds.max.z],
            "verticalFieldOfViewDegrees": 70,
            "calibrationMaximumChannelError": calibration.maximumChannelError,
            "calibratedGamut": calibration.gamut.rawValue,
            "views": rows
        ]
        let attachment = XCTAttachment(data: try JSONSerialization.data(withJSONObject: report, options: [.sortedKeys]),
                                       uniformTypeIdentifier: "public.json")
        attachment.name = "ReplayXI-Supplied-Stadium169-captures.json"
        attachment.lifetime = .keepAlways
        add(attachment)
        withExtendedLifetime([sky, stadium, pitch]) {}
    }

    func testReplayLightingBrightensNativePlayerOnExistingPitch169() async throws {
        ReplayTripoAthleteProvider.resetForTesting()
        defer { ReplayTripoAthleteProvider.resetForTesting() }
        try ReplayTripoAthleteProvider.prewarm()
        let scenario = try XCTUnwrap(DemoScenarios.scenario(for: .squadReplay))
        let player = try XCTUnwrap(scenario.player(id: "navy-rw"))
        let athlete = try ReplayTripoAthleteProvider.make(for: player, detail: .near)
        let time = 1.25
        let locomotion = PlayerLocomotionSample(
            motion: PlayerMotionState(speedMetresPerSecond: 0, distanceTravelled: 0,
                                     locomotionPhase: player.gaitPhase(at: time)),
            speedMetresPerSecond: 0, accelerationMetresPerSecondSquared: 0,
            turnRateDegreesPerSecond: 0,
            state: PlayerLocomotionSample.classify(speedMetresPerSecond: 0, turnRateDegreesPerSecond: 0))
        XCTAssertTrue(athlete.update(at: time, track: player, locomotion: locomotion,
            lookTarget: nil, ballAction: nil, stationaryPose: player.presentationPose(at: time),
            allowsOffBallPose: false))
        try ReplayStrategyPitchProvider.prewarm()
        let pitch = try XCTUnwrap(ReplayStrategyPitchProvider.makeInstance())
        for model in ReplayStrategyPitchProvider.models(in: pitch)
            where model.name == "pitch-markings-and-goals" {
            if var component = model.model, !component.materials.isEmpty {
                component.materials[0] = UnlitMaterial(color: .white, applyPostProcessToneMap: false)
                model.model = component
            }
        }
        let sky = ReplayStadiumEnvironment.makeSkyRoot()
        let lights = ReplayStadiumEnvironment.makeReplayLighting()
        let camera = PerspectiveCamera()
        camera.camera = .init(near: 0.05, far: 600, fieldOfViewInDegrees: 36)
        camera.look(at: [0, 0.91, 0], from: [0, 1.25, 4.4], relativeTo: nil)
        let calibration = try await calibrate()
        let before = try await render(entities: [sky, pitch, athlete.root, camera], camera: camera, size: 512)
        let after = try await render(entities: [sky, pitch, athlete.root, lights, camera], camera: camera, size: 512)
        // A broad head/torso ROI avoids exact skin, kit or renderer colour values.
        // The shipping pitch and backdrop use unlit materials; only the player's
        // lit surface should account for an appreciable brightness increase here.
        let minimumX = after.width * 3 / 10, maximumX = after.width * 7 / 10
        let minimumY = after.height / 10, maximumY = after.height * 3 / 4
        var brighterPlayerPixels = 0, beforeTotal = 0, afterTotal = 0
        for y in minimumY..<maximumY {
            for x in minimumX..<maximumX {
                let a = before.rgba(x: x, y: y, topFirst: calibration.rawRowsAreTopFirst)
                let b = after.rgba(x: x, y: y, topFirst: calibration.rawRowsAreTopFirst)
                let oldBrightness = Int(a[0]) + Int(a[1]) + Int(a[2])
                let newBrightness = Int(b[0]) + Int(b[1]) + Int(b[2])
                beforeTotal += oldBrightness
                afterTotal += newBrightness
                if newBrightness - oldBrightness > 15 { brighterPlayerPixels += 1 }
            }
        }
        let roiPixels = (maximumX - minimumX) * (maximumY - minimumY)
        XCTAssertGreaterThan(brighterPlayerPixels, roiPixels / 100,
                             "Fixed stadium lights must visibly brighten the native player")
        XCTAssertGreaterThan(afterTotal, beforeTotal)
        try attachPNG(before, calibration: calibration, name: "ReplayXI-Stadium169-player-pitch-before-lighting.png")
        try attachPNG(after, calibration: calibration, name: "ReplayXI-Stadium169-player-pitch-with-lighting.png")
        let report: [String: Any] = [
            "scope": "Native existing pitch and Tripo player with no room light versus fixed shadow-free stadium key/fill. No headset performance claim.",
            "keyIntensity": 2_200, "fillIntensity": 500, "shadowLights": 0,
            "playerROI": [minimumX, minimumY, maximumX, maximumY],
            "brighterPlayerPixels": brighterPlayerPixels,
            "beforeMeanChannelValue": Double(beforeTotal) / Double(roiPixels * 3),
            "afterMeanChannelValue": Double(afterTotal) / Double(roiPixels * 3),
            "calibrationMaximumChannelError": calibration.maximumChannelError,
            "calibratedGamut": calibration.gamut.rawValue
        ]
        let attachment = XCTAttachment(data: try JSONSerialization.data(withJSONObject: report, options: [.sortedKeys]),
                                       uniformTypeIdentifier: "public.json")
        attachment.name = "ReplayXI-Stadium169-player-pitch-lighting.json"
        attachment.lifetime = .keepAlways
        add(attachment)
        withExtendedLifetime(athlete) {}
        withExtendedLifetime([sky, pitch, lights, camera]) {}
    }

    private func calibrate() async throws -> ReplayRealityRendererAudit.Calibration {
        let root = Entity()
        let space = try XCTUnwrap(CGColorSpace(name: CGColorSpace.sRGB))
        for (index, bytes) in ReplayRealityRendererAudit.swatches.enumerated() {
            let components = bytes.map { CGFloat($0) / 255 } + [1]
            let color = try XCTUnwrap(CGColor(colorSpace: space, components: components))
            let swatch = ModelEntity(mesh: .generateBox(size: [1.2, 0.6, 0.01]),
                materials: [UnlitMaterial(color: UIColor(cgColor: color), applyPostProcessToneMap: false)])
            swatch.position = ReplayRealityRendererAudit.swatchPosition(index)
            root.addChild(swatch)
        }
        let camera = PerspectiveCamera()
        camera.camera = .init(near: 0.05, far: 10, fieldOfViewInDegrees: 90)
        camera.position = [0, 0, 2]
        let frame = try await render(entities: [root, camera], camera: camera, size: 256)
        let matches = try ReplayRealityRendererAudit.probe(frame).candidates.filter { $0.maximumChannelError <= 4 }
        guard matches.count == 1, let calibration = matches.first else {
            throw ReplayRealityRendererAudit.Failure.unsupported(
                "Stadium captures require unique row/channel/gamut calibration")
        }
        return calibration
    }

    private func render(entities: [Entity], camera: Entity, size: Int) async throws -> ReplayRealityRendererAudit.Frame {
        let renderer = try RealityRenderer()
        renderer.entities.append(contentsOf: entities)
        renderer.activeCamera = camera
        renderer.cameraSettings.isToneMappingEnabled = true
        renderer.cameraSettings.antialiasing = .none
        renderer.cameraSettings.colorBackground = .color(CGColor(red: 1, green: 0, blue: 1, alpha: 1))
        defer { renderer.activeCamera = nil; renderer.entities.removeAll() }
        let texture = try ReplayRealityRendererAudit.makeTexture(size: size)
        let output = try RealityRenderer.CameraOutput(.singleProjection(colorTexture: texture))
        let completion = expectation(description: "Local stadium native GPU completion")
        let flag = ReplayStadiumCaptureCompletion169()
        try renderer.updateAndRender(deltaTime: 0, cameraOutput: output, onComplete: { _ in
            flag.finish()
            completion.fulfill()
        })
        await fulfillment(of: [completion], timeout: 10)
        guard flag.isComplete else {
            throw ReplayRealityRendererAudit.Failure.unsupported("Stadium render exceeded ten seconds")
        }
        return try withExtendedLifetime(renderer) { try ReplayRealityRendererAudit.read(texture) }
    }

    private func attachPNG(_ frame: ReplayRealityRendererAudit.Frame,
                           calibration: ReplayRealityRendererAudit.Calibration, name: String) throws {
        let attachment = XCTAttachment(data: try ReplayRealityRendererAudit.png(frame, calibration: calibration),
                                       uniformTypeIdentifier: "public.png")
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
