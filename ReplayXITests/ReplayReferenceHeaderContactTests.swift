import CoreGraphics
import Foundation
import RealityKit
import UIKit
import XCTest
import simd
@testable import ReplayXI

private final class ReplayHeaderRenderCompletion: @unchecked Sendable {
    private let lock = NSLock()
    private var completed = false
    func finish() { lock.withLock { completed = true } }
    var isComplete: Bool { lock.withLock { completed } }
}

/// Uses every real head triangle, not an invented forehead anchor. A positive
/// gap proves that even the closest head surface cannot meet the ball sphere.
/// A passing distance alone does not establish anatomically correct forehead
/// contact; matched native images remain part of the audit.
@MainActor
final class ReplayReferenceHeaderContactTests: XCTestCase {
    func testFarHeaderEnvelopeStopsAtTheSphereWithoutLoadingMeshes() {
        ReplayFarAthleteHeadProvider.resetForTesting()
        let pivot = SIMD3<Float>(0, 1.03, 0)
        let ball = SIMD3<Float>(0, 1.921, 0.159)
        let identity = simd_quatf(real: 1, imag: .zero)
        let aim = ReplayAthleteInteractionPose.headerTorsoRotation(
            pivot: pivot, head: pivot + [0, 0.710, 0], ball: ball)
        let result = ReplayAthleteInteractionPose.farHeaderTorso(start: identity,
            aim: aim, weight: 1, pivot: pivot, neck: identity, head: identity, ball: ball)
        let centre = pivot + result.act([0, 0.710, 0])
        let local = result.inverse.act(ball - centre)
        let minimum = ReplayFarAthleteHeadProvider.localBoundsMin * ReplayFarAthleteHeadProvider.displayScale
        let maximum = ReplayFarAthleteHeadProvider.localBoundsMax * ReplayFarAthleteHeadProvider.displayScale
        let radius = (maximum.z - minimum.z) * 0.5
        let skull = SIMD3<Float>((minimum.x + maximum.x) * 0.5,
            maximum.y - radius, (minimum.z + maximum.z) * 0.5)
        let clearance = simd_distance(local, skull) - radius - ReplayNativeBallPhysics.radius
        XCTAssertGreaterThanOrEqual(clearance, 0.00199)
        XCTAssertLessThan(clearance, 0.0022)
        XCTAssertLessThanOrEqual(result.angle, 0.45001)
        XCTAssertEqual(simd_length(centre - pivot), 0.710, accuracy: 0.00001)
        XCTAssertEqual(result.vector, ReplayAthleteInteractionPose.farHeaderTorso(start: identity,
            aim: aim, weight: 1, pivot: pivot, neck: identity, head: identity, ball: ball).vector)
        XCTAssertEqual(ReplayFarAthleteHeadProvider.meshLoadCount, 0)
        XCTAssertFalse(ReplayFarAthleteHeadProvider.isPrewarmed)
    }

    func testHeaderLeanUsesRealTargetDirectionWithoutStretchingOrUnboundedRotation() {
        let pivot = SIMD3<Float>(0, 1.05, 0)
        let head = SIMD3<Float>(0, 1.76, -0.06)
        let ball = SIMD3<Float>(-0.18, 1.84, 0.18)
        let rotation = ReplayAthleteInteractionPose.headerTorsoRotation(pivot: pivot, head: head, ball: ball)
        let aimed = pivot + rotation.act(head - pivot)
        XCTAssertLessThan(simd_distance(aimed, ball), simd_distance(head, ball))
        XCTAssertLessThan(aimed.x, head.x)
        XCTAssertGreaterThan(aimed.z, head.z)
        XCTAssertEqual(simd_distance(aimed, pivot), simd_distance(head, pivot), accuracy: 0.000_001)
        XCTAssertLessThanOrEqual(rotation.angle, 0.450_001)
        XCTAssertEqual(rotation.vector,
            ReplayAthleteInteractionPose.headerTorsoRotation(pivot: pivot, head: head, ball: ball).vector)
        let invalid = ReplayAthleteInteractionPose.headerTorsoRotation(pivot: pivot, head: head, ball: [.nan, 1, 0])
        XCTAssertEqual(invalid.vector, simd_quatf(real: 1, imag: .zero).vector)
    }

    func testActualVolleyHeaderMeetsNativeHeadSurfaceAcrossAllLODs() async throws {
        try await checkHeader(scenarioIndex: 1)
    }

    func testActualCityHeaderMeetsNativeHeadSurfaceAcrossAllLODs() async throws {
        try await checkHeader(scenarioIndex: 3)
    }

    private func checkHeader(scenarioIndex: Int) async throws {
        reset()
        defer { reset() }
        let scenario = FootballReferenceScenarios.all[scenarioIndex]
        let plan = try XCTUnwrap(FootballReferenceScenarios.touches(for: scenario))
        let recording = try await ReplayNativeBallPhysics.bake(track: scenario.ball,
            players: scenario.players, plannedTouches: plan)
        let headers = recording.touches.filter { $0.kind == .header }
        XCTAssertEqual(headers.count, 1)
        let touch = try XCTUnwrap(headers.first)
        let player = try XCTUnwrap(scenario.player(id: touch.playerID))
        let presented = player.presentationPose(at: touch.time)
        let cue = ReplayAthleteInteractionCue(playerID: player.id, kind: .header,
            contactTime: touch.time, startTime: touch.time - 0.32, endTime: touch.time + 0.42,
            kickingLeg: touch.kickingLeg, contactBallWorldPosition: touch.position,
            outgoingDirectionWorld: touch.outgoingVelocity)
        try ReplaySkinnedAthleteProvider.prewarm()
        try ReplaySkinnedAthleteProvider.prewarmLowDetail()
        try ReplayFarAthleteHeadProvider.prewarm()
        try ReplayArticulatedFarProvider.prewarm()
        try ReplayArticulatedFarKitProvider.prewarm()
        try ReplayAthleteFactory.prewarm(for: [player], lods: [.far])
        try ReplayStrategyBallProvider.prewarm()
        let calibration = try await calibrate()
        var rows: [[String: Any]] = []
        for detail in ["far", "near", "low"] {
            let actor = Entity()
            actor.position = [presented.position.x, 0, presented.position.z]
            actor.orientation = simd_quatf(angle: presented.facingDegrees * .pi / 180, axis: [0, 1, 0])
            let triangles: [(SIMD3<Float>, SIMD3<Float>, SIMD3<Float>)]
            if detail == "far" {
                let rig = try ReplayAthleteFactory.make(for: player, lod: .far)
                actor.addChild(rig.root)
                ReplayAthleteMotion.update(rig, from: player, at: touch.time,
                    lookTargetWorldPosition: touch.position, interaction: cue, presentationPose: presented)
                let head = try XCTUnwrap(rig.joints[.headRoot].findEntity(named: "head") as? ModelEntity)
                XCTAssertTrue(head.jointTransforms.isEmpty)
                triangles = try headTriangles(head, materialIndex: 0, motion: nil)
            } else {
                let skin = try ReplaySkinnedAthleteProvider.make(for: player,
                    detail: detail == "near" ? .near : .lowDetail)
                actor.addChild(skin.root)
                XCTAssertTrue(skin.update(at: touch.time, track: player, locomotion: player.locomotion(at: touch.time),
                    lookTarget: touch.position, ballAction: nil, interaction: cue, presentationPose: presented))
                // The admitted source's second material is the full head/neck
                // surface. Deform its native triangles using read-back joints.
                triangles = try headTriangles(skin.model, materialIndex: 1, motion: skin.motion)
            }
            XCTAssertGreaterThan(triangles.count, 100)
            let points = triangles.map { nearestPoint(touch.position, $0.0, $0.1, $0.2) }
            let closest = try XCTUnwrap(points.min {
                simd_distance_squared($0, touch.position) < simd_distance_squared($1, touch.position)
            })
            let centreDistance = simd_distance(closest, touch.position)
            let gap = centreDistance - ReplayNativeBallPhysics.radius
            XCTAssertLessThanOrEqual(abs(gap), 0.03,
                "\(detail): actual admitted header sphere must meet the visible head, not act remotely")
            let ballLocal = actor.convert(position: touch.position, from: nil)
            let headLocal = actor.convert(position: closest, from: nil)

            let scene = Entity()
            scene.addChild(actor)
            let ball = try XCTUnwrap(ReplayStrategyBallProvider.makeInstance())
            ball.position = touch.position
            scene.addChild(ball)
            let floor = ModelEntity(mesh: .generateBox(size: [1.6, 0.008, 1.6]),
                materials: [SimpleMaterial(color: UIColor(red: 0.07, green: 0.12, blue: 0.09, alpha: 1),
                                           roughness: 1, isMetallic: false)])
            floor.position = actor.position + [0, -0.006, 0]
            scene.addChild(floor)
            // Translate the entire true world-space fixture for a shared camera;
            // actor facing, head pose and relative ball placement stay untouched.
            scene.position = -actor.position
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
            let image = XCTAttachment(data: try ReplayRealityRendererAudit.png(frame, calibration: calibration),
                                      uniformTypeIdentifier: "public.png")
            image.name = "ReplayXI-ActualHeader-\(scenario.id)-\(detail).png"
            image.lifetime = .keepAlways; add(image)
            rows.append(["detail": detail, "headTriangles": triangles.count,
                         "nearestHeadPointWorld": vector(closest), "nearestHeadPointActorLocal": vector(headLocal),
                         "headSurfaceToSphereGapMetres": gap, "headSurfaceToBallCentreMetres": centreDistance,
                         "ballCentreWorld": vector(touch.position), "ballCentreActorLocal": vector(ballLocal),
                         "nonBackgroundPixels": count, "imageBounds": [left, top, right, bottom]])
        }
        let report: [String: Any] = [
            "scenario": scenario.id, "playerID": player.id, "time": touch.time,
            "playerRoot": [presented.position.x, 0, presented.position.z],
            "facingDegrees": presented.facingDegrees, "ballRadius": ReplayNativeBallPhysics.radius,
            "outgoingVelocity": vector(touch.outgoingVelocity), "samples": rows,
            "admittedContacts": recording.touches.count, "plannedContacts": plan.count,
            "missedContacts": recording.missedTouchCount,
            "cameraPosition": [2.7, 1.5, 4], "cameraTarget": [0, 0.9, 0], "cameraFOV": 40,
            "scope": "Actual native header, real full-head triangles; no invented forehead anchor, root adjustment, UI or headset claim"
        ]
        let attachment = XCTAttachment(data: try JSONSerialization.data(withJSONObject: report, options: [.sortedKeys]),
                                       uniformTypeIdentifier: "public.json")
        attachment.name = "ReplayXI-ActualHeader-\(scenario.id)-HeadSurface.json"
        attachment.lifetime = .keepAlways; add(attachment)
    }

    private func headTriangles(_ model: ModelEntity, materialIndex: Int,
                               motion: ReplaySkinnedAthleteMotion?) throws
        -> [(SIMD3<Float>, SIMD3<Float>, SIMD3<Float>)] {
        let contents = try XCTUnwrap(model.model).mesh.contents
        let parts = contents.models.flatMap { Array($0.parts) }.filter { $0.materialIndex == materialIndex }
        XCTAssertEqual(parts.count, 1)
        let part = try XCTUnwrap(parts.first)
        var vertices: [SIMD3<Float>] = []
        if let motion {
            let skeleton = try XCTUnwrap(contents.skeletons.first)
            let native = model.jointTransforms
            XCTAssertEqual(native.count, motion.joints.count)
            var matrices = Array(repeating: matrix_identity_float4x4, count: native.count)
            for index in native.indices {
                let parent = motion.joints[index].parentIndex
                matrices[index] = (parent < 0 ? matrix_identity_float4x4 : matrices[parent]) * native[index].matrix
            }
            let influences = try XCTUnwrap(part.jointInfluences).influences.elements
            let count = part.positions.count
            let weightStride = influences.count / max(count, 1)
            XCTAssertTrue((1...8).contains(weightStride))
            XCTAssertEqual(influences.count, count * weightStride)
            for (index, position) in part.positions.elements.enumerated() {
                var point = SIMD4<Float>.zero
                for influence in influences[(index * weightStride)..<((index + 1) * weightStride)] {
                    point += (matrices[influence.jointIndex]
                        * skeleton.joints[influence.jointIndex].inverseBindPoseMatrix
                        * SIMD4(position, 1)) * influence.weight
                }
                XCTAssertEqual(point.w, 1, accuracy: 0.000_01)
                vertices.append(model.convert(position: [point.x, point.y, point.z], to: nil))
            }
        } else {
            XCTAssertNil(part.jointInfluences)
            vertices = part.positions.elements.map { model.convert(position: $0, to: nil) }
        }
        let indices = try XCTUnwrap(part.triangleIndices).elements
        XCTAssertEqual(indices.count % 3, 0)
        var result: [(SIMD3<Float>, SIMD3<Float>, SIMD3<Float>)] = []
        for offset in stride(from: 0, to: indices.count, by: 3) {
            let a = Int(indices[offset])
            let b = Int(indices[offset + 1])
            let c = Int(indices[offset + 2])
            result.append((vertices[a], vertices[b], vertices[c]))
        }
        return result
    }

    private func nearestPoint(_ point: SIMD3<Float>, _ a: SIMD3<Float>,
                              _ b: SIMD3<Float>, _ c: SIMD3<Float>) -> SIMD3<Float> {
        let ab = b - a, ac = c - a
        let normal = simd_cross(ab, ac)
        let squaredNormal = simd_length_squared(normal)
        if squaredNormal > 0.000_000_000_1 {
            let projected = point - normal * (simd_dot(point - a, normal) / squaredNormal)
            let relative = projected - a
            let aa = simd_dot(ab, ab), bb = simd_dot(ab, ac), cc = simd_dot(ac, ac)
            let denominator = aa * cc - bb * bb
            if abs(denominator) > 0.000_000_000_1 {
                let u = (cc * simd_dot(relative, ab) - bb * simd_dot(relative, ac)) / denominator
                let v = (aa * simd_dot(relative, ac) - bb * simd_dot(relative, ab)) / denominator
                if u >= 0, v >= 0, u + v <= 1 { return projected }
            }
        }
        func edge(_ start: SIMD3<Float>, _ end: SIMD3<Float>) -> SIMD3<Float> {
            let delta = end - start
            let length = simd_length_squared(delta)
            let t = length > 0.000_000_000_1
                ? min(max(simd_dot(point - start, delta) / length, 0), 1) : 0
            return start + delta * t
        }
        return [edge(a, b), edge(b, c), edge(c, a)].min {
            simd_distance_squared(point, $0) < simd_distance_squared(point, $1)
        }!
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
        let attachment = XCTAttachment(data: try JSONEncoder().encode(calibration), uniformTypeIdentifier: "public.json")
        attachment.name = "ReplayXI-ActualHeader125-Calibration.json"
        attachment.lifetime = .keepAlways; add(attachment)
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
        let completion = expectation(description: "Actual header native frame")
        let flag = ReplayHeaderRenderCompletion()
        try renderer.updateAndRender(deltaTime: 0, cameraOutput: output, onComplete: { _ in
            flag.finish(); completion.fulfill()
        })
        await fulfillment(of: [completion], timeout: 10)
        guard flag.isComplete else { throw ReplayRealityRendererAudit.Failure.unsupported("Header frame timed out") }
        return try withExtendedLifetime(renderer) { try ReplayRealityRendererAudit.read(texture) }
    }

    private func vector(_ point: SIMD3<Float>) -> [Float] { [point.x, point.y, point.z] }

    private func reset() {
        ReplayNativeBallPhysics.resetCacheForTesting()
        ReplayArticulatedFarKitProvider.resetForTesting()
        ReplayArticulatedFarProvider.resetForTesting()
        ReplayFarAthleteHeadProvider.resetForTesting()
        ReplaySkinnedAthleteProvider.resetForTesting()
        ReplayAthleteHeadProvider.resetForTesting()
        ReplayFarAthletePaletteProvider.resetForTesting()
        ReplayStrategyBallProvider.resetForTesting()
    }
}
