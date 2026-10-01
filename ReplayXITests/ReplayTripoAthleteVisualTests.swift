import CoreGraphics
import Metal
import RealityKit
import UIKit
import XCTest
@testable import ReplayXI

private final class ReplayTripoCaptureCompletion: @unchecked Sendable {
    private let lock = NSLock()
    private var complete = false
    func finish() { lock.withLock { complete = true } }
    var isComplete: Bool { lock.withLock { complete } }
}

@MainActor
final class ReplayTripoAthleteVisualTests: XCTestCase {
    func testCapturesTripoNearAndLowNativePlayerViews() async throws {
        ReplayTripoAthleteProvider.resetForTesting()
        ReplaySkinnedAthleteProvider.resetForTesting()
        defer {
            ReplayTripoAthleteProvider.resetForTesting()
            ReplaySkinnedAthleteProvider.resetForTesting()
        }

        try ReplayTripoAthleteProvider.prewarm()
        XCTAssertTrue(ReplayTripoAthleteProvider.isPrewarmed)
        let scenario = try XCTUnwrap(DemoScenarios.scenario(for: .squadReplay))
        let home = try XCTUnwrap(scenario.player(id: "navy-rw"))
        let away = try XCTUnwrap(scenario.player(id: "red-lb"))
        let keeper = try XCTUnwrap(scenario.player(id: "navy-gk"))
        let homeNear = try ReplayTripoAthleteProvider.make(for: home, detail: .near)
        let awayNear = try ReplayTripoAthleteProvider.make(for: away, detail: .near)
        let keeperNear = try ReplayTripoAthleteProvider.make(for: keeper, detail: .near)
        let awayLow = try ReplayTripoAthleteProvider.make(for: away, detail: .lowDetail)
        let liveInstances = [homeNear, awayNear, keeperNear, awayLow]
        XCTAssertTrue(liveInstances.allSatisfy { $0.motion.rigProfile == .tripo52 && $0.model.jointNames.count == 52 })

        let calibration = try await calibrate()
        let idleTime = 1.25
        for (instance, player, name) in [(homeNear, home, "home"), (awayNear, away, "away"),
                                         (keeperNear, keeper, "keeper")] {
            XCTAssertTrue(update(instance, player: player, time: idleTime, speed: 0, stationary: true))
            try await capture(instance.root, label: "\(name)-near-idle-front", player: player,
                              view: .front, calibration: calibration)
        }
        // Diagnostic separates geometry/normal shading from atlas seams.
        var flat = PhysicallyBasedMaterial()
        flat.baseColor = .init(tint: .white)
        flat.roughness = .init(floatLiteral: 0.78)
        let original = try XCTUnwrap(homeNear.model.model)
        var withoutAtlas = original
        withoutAtlas.materials = [flat]
        homeNear.model.model = withoutAtlas
        try await capture(homeNear.root, label: "home-near-idle-flat-material-diagnostic", player: home,
                          view: .front, calibration: calibration)
        homeNear.model.model = original
        let savedJoints = homeNear.model.jointTransforms
        var rebuilt = original
        rebuilt.mesh = try MeshResource.generate(from: original.mesh.contents)
        homeNear.model.model = rebuilt
        homeNear.model.jointTransforms = savedJoints
        try await capture(homeNear.root, label: "home-near-rebuilt-mesh-diagnostic", player: home,
                          view: .front, calibration: calibration)
        homeNear.model.model = original
        homeNear.model.jointTransforms = homeNear.motion.restPose.translations.indices.map { index in
            Transform(scale: homeNear.motion.restPose.scales[index],
                      rotation: homeNear.motion.restPose.rotations[index],
                      translation: homeNear.motion.restPose.translations[index])
        }
        try await capture(homeNear.root, label: "home-near-rest-pose-diagnostic", player: home,
                          view: .front, calibration: calibration)
        homeNear.model.jointTransforms = savedJoints
        XCTAssertTrue(update(homeNear, player: home, time: idleTime, speed: 0, stationary: true))
        try await capture(homeNear.root, label: "home-near-idle-back-number-\(home.shirtNumber)",
                          player: home, view: .back, calibration: calibration)

        let runTime = 13.6
        XCTAssertTrue(update(homeNear, player: home, time: runTime, speed: 3.6, stationary: false))
        try await capture(homeNear.root, label: "home-near-run-side", player: home,
                          view: .side, calibration: calibration)
        try await capture(homeNear.root, label: "home-near-run-front", player: home,
                          view: .front, calibration: calibration)
        XCTAssertTrue(update(awayLow, player: away, time: runTime, speed: 3.6, stationary: false))
        try await capture(awayLow.root, label: "away-low-run-front", player: away,
                          view: .front, calibration: calibration)

        // Keep every native skinned root alive until all renderer work completes.
        withExtendedLifetime(liveInstances) {}
    }

    private enum View {
        case front, back, side
    }

    private func update(_ instance: ReplaySkinnedAthleteInstance, player: PlayerTrack,
                        time: Double, speed: Float, stationary: Bool) -> Bool {
        let state = PlayerLocomotionSample.classify(speedMetresPerSecond: speed, turnRateDegreesPerSecond: 0)
        let sample = PlayerLocomotionSample(
            motion: PlayerMotionState(speedMetresPerSecond: speed, distanceTravelled: 0,
                                     locomotionPhase: player.gaitPhase(at: time)),
            speedMetresPerSecond: speed, accelerationMetresPerSecondSquared: 0,
            turnRateDegreesPerSecond: 0, state: state)
        return instance.update(at: time, track: player, locomotion: sample,
            lookTarget: nil, ballAction: nil,
            stationaryPose: stationary ? player.presentationPose(at: time) : nil,
            allowsOffBallPose: false)
    }

    private func capture(_ avatar: Entity, label: String, player: PlayerTrack, view: View,
                         calibration: ReplayRealityRendererAudit.Calibration) async throws {
        let target = SIMD3<Float>(0, 0.91, 0)
        let position: SIMD3<Float>
        let keyPosition: SIMD3<Float>
        let fillPosition: SIMD3<Float>
        switch view {
        case .front:
            position = [0, 1.25, 4.4]
            keyPosition = [-3, 4, 3]
            fillPosition = [3, 2, 2]
        case .back:
            position = [0, 1.25, -4.4]
            keyPosition = [3, 4, -3]
            fillPosition = [-3, 2, -2]
        case .side:
            position = [4.4, 1.25, 0]
            keyPosition = [3, 4, 3]
            fillPosition = [2, 2, -3]
        }
        let camera = PerspectiveCamera()
        camera.camera = PerspectiveCameraComponent(near: 0.05, far: 20, fieldOfViewInDegrees: 36)
        camera.look(at: target, from: position, relativeTo: nil)
        let key = DirectionalLight()
        key.light.intensity = 2_200
        key.shadow = nil
        key.look(at: target, from: keyPosition, relativeTo: nil)
        let fill = DirectionalLight()
        fill.light.intensity = 500
        fill.shadow = nil
        fill.look(at: target, from: fillPosition, relativeTo: nil)
        let frame = try await render(entities: [avatar, key, fill, camera], camera: camera, size: 512)

        var count = 0, left = frame.width, top = frame.height, right = -1, bottom = -1
        for y in 0..<frame.height {
            for x in 0..<frame.width {
                let pixel = frame.rgba(x: x, y: y, topFirst: calibration.rawRowsAreTopFirst)
                if pixel[0] > 8 || pixel[1] > 8 || pixel[2] > 8 {
                    count += 1
                    left = min(left, x); right = max(right, x)
                    top = min(top, y); bottom = max(bottom, y)
                }
            }
        }
        XCTAssertGreaterThan(count, 500, "\(label) is empty")
        XCTAssertLessThan(count, frame.width * frame.height * 7 / 10, "\(label) fills the frame")
        XCTAssertGreaterThan(left, 4, "\(label) clipped left")
        XCTAssertGreaterThan(top, 4, "\(label) clipped top")
        XCTAssertLessThan(right, frame.width - 5, "\(label) clipped right")
        XCTAssertLessThan(bottom, frame.height - 5, "\(label) clipped bottom")
        let attachment = XCTAttachment(data: try ReplayRealityRendererAudit.png(frame, calibration: calibration),
                                       uniformTypeIdentifier: "public.png")
        attachment.name = "ReplayXI-Tripo-\(player.team.rawValue)-\(label).png"
        attachment.lifetime = .keepAlways
        add(attachment)
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
        camera.camera = PerspectiveCameraComponent(near: 0.05, far: 10, fieldOfViewInDegrees: 90)
        camera.position = [0, 0, 2]
        let probe = try ReplayRealityRendererAudit.probe(
            await render(entities: [root, camera], camera: camera, size: 256))
        let matches = probe.candidates.filter { $0.maximumChannelError <= 4 }
        guard matches.count == 1, let calibration = matches.first else {
            throw ReplayRealityRendererAudit.Failure.unsupported(
                "Tripo captures require unique row/channel/gamut calibration")
        }
        return calibration
    }

    private func render(entities: [Entity], camera: Entity, size: Int) async throws
        -> ReplayRealityRendererAudit.Frame {
        let renderer = try RealityRenderer()
        renderer.entities.append(contentsOf: entities)
        renderer.activeCamera = camera
        renderer.cameraSettings.isToneMappingEnabled = true
        renderer.cameraSettings.antialiasing = .none
        renderer.cameraSettings.colorBackground = .color(CGColor(gray: 0, alpha: 1))
        let texture = try ReplayRealityRendererAudit.makeTexture(size: size)
        let output = try RealityRenderer.CameraOutput(.singleProjection(colorTexture: texture))
        let completion = expectation(description: "Tripo native GPU completion")
        let flag = ReplayTripoCaptureCompletion()
        try renderer.updateAndRender(deltaTime: 0, cameraOutput: output, onComplete: { _ in
            flag.finish()
            completion.fulfill()
        })
        await fulfillment(of: [completion], timeout: 10)
        guard flag.isComplete else {
            throw ReplayRealityRendererAudit.Failure.unsupported("Tripo render exceeded ten seconds")
        }
        return try withExtendedLifetime(renderer) { try ReplayRealityRendererAudit.read(texture) }
    }
}
