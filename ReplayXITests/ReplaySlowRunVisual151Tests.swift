import CoreGraphics
import Foundation
import RealityKit
import simd
import UIKit
import XCTest
@testable import ReplayXI

private final class SlowRunVisualCompletion151: @unchecked Sendable {
    private let lock = NSLock()
    private var value = false
    func finish() { lock.withLock { value = true } }
    var isComplete: Bool { lock.withLock { value } }
}

/// The shipping factory default, not an alternate source attached to a test rig.
/// Stills show poses; the accompanying 120Hz samples describe their transitions.
@MainActor
final class ReplaySlowRunVisual151Tests: XCTestCase {
    private typealias Skin = ReplaySkinnedAthleteInstance
    private struct Window {
        let scenario: ReplayScenario
        let player: PlayerTrack
        let rising: Bool
        let centre: Int
        var frames: ClosedRange<Int> { (centre - 12)...(centre + 12) }
        var captures: Set<Int> { [frames.lowerBound, centre, frames.upperBound] }
    }
    private struct Snapshot {
        let frame: Int
        let weight: Float
        let joints: [Transform]
        let actor: Transform
        let ball: Transform
    }
    private struct Peak {
        let degrees: Float
        let joint: Int
        let sample: Int
    }
    private let majorJointLeaves: Set<String> = [
        "Pelvis", "Spine", "Spine1", "Spine2", "Neck", "Head",
        "L_Clavicle", "R_Clavicle", "L_UpperArm", "R_UpperArm",
        "L_Forearm", "R_Forearm", "L_Hand", "R_Hand",
        "L_Thigh", "R_Thigh", "L_Calf", "R_Calf", "L_Foot", "R_Foot", "L_Toe0", "R_Toe0"
    ]

    override func tearDown() {
        PitchSceneFactory.fullSquadSkinsForTesting = false
        if let scenario = FootballReferenceScenarios.all.first {
            let root = Entity(), marks = Entity(); marks.name = "marks-root"; root.addChild(marks)
            update(root, scenario: scenario, time: 0, selected: scenario.defaultPerspectiveID, enabled: false)
            for child in Array(root.children) { child.removeFromParent() }
        }
        ReplayArticulatedFarKitProvider.resetForTesting(); ReplayArticulatedFarProvider.resetForTesting()
        ReplayFarAthleteHeadProvider.resetForTesting(); ReplaySkinnedAthleteProvider.resetForTesting()
        ReplayAthleteHeadProvider.resetForTesting(); ReplayFarAthletePaletteProvider.resetForTesting()
        ReplayNativeBallPhysics.resetCacheForTesting()
        super.tearDown()
    }

    func testShippingSlowRunRiseAndFallMatchedNativeNearLow151() async throws {
        PitchSceneFactory.fullSquadSkinsForTesting = false
        try ReplayArmLOD147Probe.prepare()
        try ReplayStrategyPitchProvider.prewarm(); try ReplayStrategyBallProvider.prewarm()
        XCTAssertTrue(try XCTUnwrap(ReplaySkinnedAthleteProvider.motion).hasSlowRun)
        let windows = try [selectWindow(team: .home, rising: true), selectWindow(team: .away, rising: false)]
        // Retain the measured raw151 worst windows, not easier timeline extrema.
        XCTAssertEqual(windows.map { $0.scenario.id }, ["final-81-volley-v2", "city-57-underlap-cutback"])
        XCTAssertEqual(windows.map { $0.player.id }, ["arg-19", "liv-38"])
        XCTAssertEqual(windows.map(\.centre), [990, 489])
        let calibration = try await calibrate()
        var cases: [[String: Any]] = [], images: [[String: Any]] = [], pngBytes = 0
        for window in windows {
            let scenario = window.scenario
            let planned = try XCTUnwrap(FootballReferenceScenarios.touches(for: scenario))
            let recording = try await ReplayNativeBallPhysics.prewarm(track: scenario.ball,
                players: scenario.players, plannedTouches: planned)
            XCTAssertEqual(recording.missedTouchCount, 0)
            XCTAssertEqual(recording.touches.count, planned.count)
            XCTAssertFalse(recording.touches.contains { $0.playerID == window.player.id })
            try ReplayAthleteFactory.prewarm(for: scenario.players, lods: [.near, .far])
            let sourcePlayers = scenario.players, sourceBall = scenario.ball
            let ballPositions = recording.samples.map(\.position), ballVelocities = recording.samples.map(\.velocity)
            for detail in [ReplaySkinnedAthleteProvider.Detail.near, .lowDetail] {
                let result = try await capture(window, recording: recording, detail: detail, calibration: calibration)
                cases.append(result.row); images += result.images; pngBytes += result.bytes
            }
            XCTAssertEqual(scenario.players, sourcePlayers); XCTAssertEqual(scenario.ball, sourceBall)
            XCTAssertEqual(recording.samples.map(\.position), ballPositions)
            XCTAssertEqual(recording.samples.map(\.velocity), ballVelocities)
        }
        XCTAssertEqual(images.count, 24); XCTAssertLessThan(pngBytes, 48 * 1_024 * 1_024)
        let receipt: [String: Any] = ["cases": cases, "images": images, "pngBytes": pngBytes,
            "sampleRateHz": 120, "captureSize": 512,
            "calibration": ["gamut": calibration.gamut.rawValue, "topFirst": calibration.rawRowsAreTopFirst,
                            "maximumChannelError": calibration.maximumChannelError],
            "scope": "Actual factory default versus explicit fast-only; same actor routes, ball, fixed pitch, camera, lights and grid. Full-squad quality selects actual near/low instances. No forced LOD or substituted source.",
            "selection": "Frozen raw151 worst windows: largest positive 30Hz raw policy change among eligible home actors and largest negative among away actors, refined at 120Hz. Same 200ms windows; timeline attenuation does not change their selection.",
            "majorJointScope": majorJointLeaves.sorted(),
            "limits": "Authored animation diagnostic, not recovered match motion, force/contact evidence, headset comfort or device FPS. Sequential pose metrics cover the gaps between stills."]
        let attachment = XCTAttachment(data: try JSONSerialization.data(withJSONObject: receipt, options: [.sortedKeys]),
                                      uniformTypeIdentifier: "public.json")
        attachment.name = "ReplayXI-SlowRun152-ProductionVisualProof.json"; attachment.lifetime = .keepAlways; add(attachment)
    }

    private func weight(_ player: PlayerTrack, at time: Double) -> Float {
        guard let movement = ReplayAthleteMovementIntent.sample(track: player, at: time,
            presentationPose: player.presentationPose(at: time), lookTarget: nil) else { return 0 }
        return ReplaySlowRunAdmission.weight(locomotion: player.locomotion(at: time))
            * ReplaySlowRunAdmission.directionWeight(localTravelYaw: movement.localTravelYaw)
    }

    private func selectWindow(team: FootballTeam, rising: Bool) throws -> Window {
        var best: (ReplayScenario, PlayerTrack, Int, Float)?
        for scenario in FootballReferenceScenarios.all {
            let touches = try XCTUnwrap(FootballReferenceScenarios.touches(for: scenario))
            let excluded = Set(touches.map(\.playerID))
            let impact = PlayerRagdollCue.authoredDemo(for: scenario)?.playerID
            for player in scenario.players where player.team == team && !player.isGoalkeeper
                && !excluded.contains(player.id) && player.id != impact {
                let count = Int(floor(scenario.duration * 30))
                guard count > 14 else { continue }
                var previous = weight(player, at: 6.0 / 30)
                for frame in 7...(count - 6) {
                    let current = weight(player, at: Double(frame) / 30)
                    let score = (current - previous) * (rising ? 1 : -1)
                    if score > (best?.3 ?? 0) { best = (scenario, player, frame * 4 - 2, score) }
                    previous = current
                }
            }
        }
        let selected = try XCTUnwrap(best, "No actual eligible source-weight transition")
        XCTAssertGreaterThan(selected.3, 0.005)
        var centre = selected.2, maximum: Float = 0
        for frame in (selected.2 - 6)...(selected.2 + 6) {
            let score = (weight(selected.1, at: Double(frame) / 120)
                - weight(selected.1, at: Double(frame - 1) / 120)) * (rising ? 1 : -1)
            if score > maximum { maximum = score; centre = frame }
        }
        XCTAssertGreaterThan(maximum, 0)
        return Window(scenario: selected.0, player: selected.1, rising: rising, centre: centre)
    }

    private func capture(_ window: Window, recording: ReplayNativeBallPhysics.Recording,
                         detail: ReplaySkinnedAthleteProvider.Detail, calibration: ReplayRealityRendererAudit.Calibration)
        async throws -> (row: [String: Any], images: [[String: Any]], bytes: Int) {
        let scenario = window.scenario, player = window.player
        let detailName = detail == .near ? "near" : "low", edge = window.rising ? "rise" : "fall"
        let selected: String
        if detail == .near { selected = player.id }
        else { selected = try XCTUnwrap(scenario.players.first { $0.id != player.id }).id }
        let root = PitchSceneFactory.makeMatchRoot(for: scenario, nativeRecording: recording)
        defer { for child in Array(root.children) { child.removeFromParent() } }
        update(root, scenario: scenario, time: Double(window.frames.lowerBound) / 120, selected: selected, enabled: false)
        let timeline = PitchSceneFactory.slowRunTimelinesForTesting(in: root)[player.id]
        XCTAssertNotNil(timeline, "The actual eligible track must have a cached admission timeline")
        let skin = try XCTUnwrap(PitchSceneFactory.skinnedAthletesForTesting(in: root)[player.id])
        XCTAssertEqual(skin.detail, detail)
        let actor = try XCTUnwrap(skin.root.parent), ball = try XCTUnwrap(root.findEntity(named: "ball"))
        let playersRoot = try XCTUnwrap(root.findEntity(named: "players-root"))
        let middle = player.presentationPose(at: Double(window.centre) / 120)
        let centre = SIMD3<Float>(middle.position.x, 0, middle.position.z)
        let heading = simd_quatf(angle: middle.facingDegrees * .pi / 180, axis: [0, 1, 0])
        let camera = PerspectiveCamera(); let fov: Float = 55
        camera.camera = .init(near: 0.05, far: 80, fieldOfViewInDegrees: fov)
        camera.look(at: centre + [0, 0.95, 0], from: centre + heading.act([4.5, 1.6, 2.7]), relativeTo: nil)
        let key = DirectionalLight(); key.light.intensity = 2_200; key.look(at: centre, from: centre + [3, 4, 3], relativeTo: nil)
        let fill = DirectionalLight(); fill.light.intensity = 1_000; fill.look(at: centre, from: centre + [-3, 3, -3], relativeTo: nil)
        let grid = grid(centre); root.addChild(grid)
        let fixedCamera = camera.transform, fixedLights = [key.transform, fill.transform], fixedGrid = grid.transform
        let renderer = try RealityRenderer(); renderer.entities.append(contentsOf: [root, camera, key, fill])
        defer { renderer.activeCamera = nil; renderer.entities.removeAll() }
        configure(renderer, camera: camera)
        let texture = try ReplayRealityRendererAudit.makeTexture(size: 512)
        let output = try RealityRenderer.CameraOutput(.singleProjection(colorTexture: texture))
        var samples: [Bool: [Snapshot]] = [false: [], true: []]
        var rows: [[String: Any]] = [], images: [[String: Any]] = [], bytes = 0
        for frame in window.frames {
            let time = Double(frame) / 120
            var controlActors: [Transform] = [], controlBall = Transform()
            for enabled in [false, true] {
                update(root, scenario: scenario, time: time, selected: selected, enabled: enabled)
                XCTAssertTrue(PitchSceneFactory.skinnedAthletesForTesting(in: root)[player.id] === skin)
                XCTAssertEqual(skin.detail, detail)
                let actualActors = playersRoot.children.map(\.transform)
                if !enabled { controlActors = actualActors; controlBall = ball.transform }
                else { XCTAssertEqual(actualActors, controlActors); XCTAssertEqual(ball.transform, controlBall) }
                let expected = player.presentationPose(at: time), nativeBall = recording.pose(at: time)
                XCTAssertEqual(actor.position, [expected.position.x, 0, expected.position.z])
                XCTAssertEqual(ball.position, [nativeBall.position.x, max(nativeBall.height, 0.11), nativeBall.position.z])
                let timelineWeight = timeline?.weight(at: time) ?? 0
                let rawWeight = weight(player, at: time)
                XCTAssertEqual(skin.slowRunWeightForTesting, enabled ? timelineWeight : 0, accuracy: 0.000001)
                let snapshot = Snapshot(frame: frame, weight: skin.slowRunWeightForTesting,
                                        joints: skin.model.jointTransforms, actor: actor.transform, ball: ball.transform)
                samples[enabled, default: []].append(snapshot)
                XCTAssertGreaterThanOrEqual(skin.contactSurface.minimumY(in: skin.pose) - skin.motion.geometry.restMinY,
                                           skin.contactSurface.paddingMetres - 0.0001)
                let locomotion = player.locomotion(at: time)
                rows.append(["frame": frame, "time": time, "variant": enabled ? "shipping" : "fast-only",
                             "weight": snapshot.weight, "rawPolicyWeight": rawWeight,
                             "timelineWeight": timelineWeight, "speed": locomotion.speedMetresPerSecond,
                             "turnRate": locomotion.turnRateDegreesPerSecond, "gaitPhase": player.gaitPhase(at: time)])
                guard window.captures.contains(frame) else { continue }
                // Keep the full body in frame; do not conceal a pose problem by cropping.
                let extent = tan(fov * .pi / 360) * 0.97
                for y: Float in [0, 2.1] {
                    for x: Float in [-0.75, 0.75] {
                        for z: Float in [-0.75, 0.75] {
                            let p = camera.convert(position: actor.position + [x, y, z], from: nil)
                            XCTAssertLessThan(p.z, -0.05)
                            XCTAssertLessThan(abs(p.x), -p.z * extent); XCTAssertLessThan(abs(p.y), -p.z * extent)
                        }
                    }
                }
                let allSkins = PitchSceneFactory.skinnedAthletesForTesting(in: root)
                let joints = allSkins.mapValues { $0.model.jointTransforms }
                try await render(renderer, output: output, name: "Slow run152 \(player.id)/\(detailName)/\(frame)/\(enabled)")
                let image = try withExtendedLifetime((renderer, camera, output, root)) { try ReplayRealityRendererAudit.read(texture) }
                XCTAssertEqual(camera.transform, fixedCamera); XCTAssertEqual([key.transform, fill.transform], fixedLights)
                XCTAssertEqual(grid.transform, fixedGrid); XCTAssertEqual(root.transform, Transform())
                XCTAssertEqual(playersRoot.children.map(\.transform), actualActors); XCTAssertEqual(ball.transform, snapshot.ball)
                for (id, body) in allSkins { XCTAssertEqual(body.model.jointTransforms, joints[id]) }
                let png = try ReplayRealityRendererAudit.png(image, calibration: calibration)
                let name = "ReplayXI-SlowRun152-\(edge)-\(player.id)-\(detailName)-f\(frame)-\(enabled ? "shipping" : "fast-only").png"
                let attachment = XCTAttachment(data: png, uniformTypeIdentifier: "public.png")
                attachment.name = name; attachment.lifetime = .keepAlways; add(attachment); bytes += png.count
                images.append(["attachment": name, "scenario": scenario.id, "player": player.id,
                    "team": player.team.rawValue, "detail": detailName, "edge": edge, "time": time,
                    "weight": snapshot.weight, "rawPolicyWeight": rawWeight,
                    "timelineWeight": timelineWeight, "variant": enabled ? "shipping" : "fast-only",
                    "camera": ReplayArmLOD147Probe.vector(camera.position), "cameraFOV": fov])
            }
        }
        let enabled = try XCTUnwrap(samples[true]), control = try XCTUnwrap(samples[false])
        let maximumWeight = try XCTUnwrap(enabled.map(\.weight).max())
        let minimumWeight = try XCTUnwrap(enabled.map(\.weight).min())
        let variation = maximumWeight - minimumWeight
        XCTAssertGreaterThan(maximumWeight, 0, "Report attenuation honestly; do not require the old full-weight pulse")
        XCTAssertGreaterThan(simd_distance(enabled.first!.actor.translation, enabled.last!.actor.translation), 0.05)
        for index in 1..<enabled.count {
            XCTAssertEqual(enabled[index].frame - enabled[index - 1].frame, 1)
            XCTAssertLessThanOrEqual(abs(enabled[index].weight - enabled[index - 1].weight),
                                    Float(4.0 / 120) + 0.000001,
                                    "Production admission must respect 4/s at actual 120Hz presentation")
        }
        for active in [false, true] {
            for saved in try XCTUnwrap(samples[active]).reversed() {
                update(root, scenario: scenario, time: Double(saved.frame) / 120, selected: selected, enabled: active)
                XCTAssertEqual(skin.model.jointTransforms, saved.joints, "Exact production rewind")
                XCTAssertEqual(actor.transform, saved.actor); XCTAssertEqual(ball.transform, saved.ball)
                XCTAssertEqual(skin.slowRunWeightForTesting, saved.weight)
            }
        }
        let names = skin.motion.jointNames
        let allJoints = Array(names.indices)
        let majorJoints = names.indices.filter { majorJointLeaves.contains(String(names[$0].split(separator: "/").last!)) }
        XCTAssertEqual(majorJoints.count, majorJointLeaves.count)
        return (["scenario": scenario.id, "player": player.id, "team": player.team.rawValue,
            "detail": detailName, "edge": edge, "start": Double(window.frames.lowerBound) / 120,
            "end": Double(window.frames.upperBound) / 120, "weightRange": variation,
            "minimumWeight": minimumWeight, "maximumWeight": maximumWeight,
            "frames": rows,
            "fastPeak": pairedPeak(control, other: enabled, names: names, joints: allJoints, variant: "fast-only"),
            "shippingPeak": pairedPeak(enabled, other: control, names: names, joints: allJoints, variant: "shipping"),
            "fastMajorLimbPeak": pairedPeak(control, other: enabled, names: names, joints: majorJoints, variant: "fast-only"),
            "shippingMajorLimbPeak": pairedPeak(enabled, other: control, names: names, joints: majorJoints, variant: "shipping"),
            "exactRewind": true], images, bytes)
    }

    private func update(_ root: Entity, scenario: ReplayScenario, time: Double, selected: String, enabled: Bool) {
        if enabled {
            // Deliberately omit the optional argument: exercise the shipping default.
            PitchSceneFactory.update(root: root, scenario: scenario, time: time, viewMode: .touchline,
                perspectiveID: selected, marks: [], showsLaneLens: false, isDrawing: false,
                positionalOriginTransform: nil, playerDetail: .fullSquad)
        } else {
            PitchSceneFactory.update(root: root, scenario: scenario, time: time, viewMode: .touchline,
                perspectiveID: selected, marks: [], showsLaneLens: false, isDrawing: false,
                positionalOriginTransform: nil, playerDetail: .fullSquad, allowsSlowRunSource: false)
        }
        root.transform = Transform() // Fixed diagnostic pitch, never a player recenter.
    }

    private func angle(_ samples: [Snapshot], sample: Int, joint: Int) -> Float {
        let delta = simd_normalize(samples[sample - 1].joints[joint].rotation.inverse
            * samples[sample].joints[joint].rotation)
        let result = 2 * atan2(simd_length(delta.imag), abs(delta.real)) * 180 / Float.pi
        XCTAssertTrue(result.isFinite)
        return result
    }

    /// Both values in a peak row are the same joint and exact pair of times.
    /// Independent whole-window peaks remain separate rows, including fingers.
    private func pairedPeak(_ samples: [Snapshot], other: [Snapshot], names: [String],
                            joints: [Int], variant: String) -> [String: Any] {
        XCTAssertEqual(samples.map(\.frame), other.map(\.frame))
        var peak = Peak(degrees: 0, joint: joints[0], sample: 1), weightRate: Float = 0
        for index in 1..<samples.count {
            weightRate = max(weightRate, abs(samples[index].weight - samples[index - 1].weight) * 120)
            for bone in joints {
                let degrees = angle(samples, sample: index, joint: bone)
                if degrees > peak.degrees { peak = Peak(degrees: degrees, joint: bone, sample: index) }
            }
        }
        let comparison = angle(other, sample: peak.sample, joint: peak.joint)
        return ["degreesPer120HzStep": peak.degrees, "joint": names[peak.joint], "jointIndex": peak.joint,
                "startingFrame": samples[peak.sample - 1].frame, "endingFrame": samples[peak.sample].frame,
                "startingTime": Double(samples[peak.sample - 1].frame) / 120,
                "endingTime": Double(samples[peak.sample].frame) / 120,
                "peakVariant": variant, "pairedFastDegreesPer120HzStep": variant == "fast-only" ? peak.degrees : comparison,
                "pairedShippingDegreesPer120HzStep": variant == "shipping" ? peak.degrees : comparison,
                "weightBefore": samples[peak.sample - 1].weight, "weightAfter": samples[peak.sample].weight,
                "pairedWeightBefore": other[peak.sample - 1].weight, "pairedWeightAfter": other[peak.sample].weight,
                "maximumAbsoluteWeightDerivativePerSecond": weightRate]
    }

    private func grid(_ centre: SIMD3<Float>) -> Entity {
        let result = Entity(); result.position = [round(centre.x * 10) / 10, 0.0015, round(centre.z * 10) / 10]
        let mesh = MeshResource.generateBox(size: [4.8, 0.001, 0.004])
        let ink = UnlitMaterial(color: UIColor(white: 0.36, alpha: 1), applyPostProcessToneMap: false)
        for index in -24...24 {
            for axis in 0..<2 {
                let line = ModelEntity(mesh: mesh, materials: [ink])
                if axis == 0 { line.position.z = Float(index) * 0.1 }
                else { line.position.x = Float(index) * 0.1; line.orientation = simd_quatf(angle: .pi / 2, axis: [0, 1, 0]) }
                if index.isMultiple(of: 5) { line.scale.z = 2 }; result.addChild(line)
            }
        }
        return result
    }

    private func configure(_ renderer: RealityRenderer, camera: Entity) {
        renderer.activeCamera = camera; renderer.cameraSettings.isToneMappingEnabled = true
        renderer.cameraSettings.antialiasing = .none
        renderer.cameraSettings.colorBackground = .color(CGColor(gray: 0, alpha: 1))
    }

    private func render(_ renderer: RealityRenderer, output: RealityRenderer.CameraOutput, name: String) async throws {
        let completed = expectation(description: name), flag = SlowRunVisualCompletion151()
        try renderer.updateAndRender(deltaTime: 0, cameraOutput: output, onComplete: { _ in flag.finish(); completed.fulfill() })
        await fulfillment(of: [completed], timeout: 10)
        guard flag.isComplete else { throw ReplayRealityRendererAudit.Failure.unsupported("Slow run152 frame timed out") }
    }

    private func calibrate() async throws -> ReplayRealityRendererAudit.Calibration {
        let root = Entity(); defer { for child in Array(root.children) { child.removeFromParent() } }
        let space = try XCTUnwrap(CGColorSpace(name: CGColorSpace.sRGB))
        for (index, bytes) in ReplayRealityRendererAudit.swatches.enumerated() {
            let colour = try XCTUnwrap(CGColor(colorSpace: space, components: bytes.map { CGFloat($0) / 255 } + [1]))
            let tile = ModelEntity(mesh: .generateBox(size: [1.2, 0.6, 0.01]),
                materials: [UnlitMaterial(color: UIColor(cgColor: colour), applyPostProcessToneMap: false)])
            tile.position = ReplayRealityRendererAudit.swatchPosition(index); root.addChild(tile)
        }
        let camera = PerspectiveCamera(); camera.camera = .init(near: 0.05, far: 10, fieldOfViewInDegrees: 90); camera.position = [0, 0, 2]
        let renderer = try RealityRenderer(); renderer.entities.append(contentsOf: [root, camera])
        defer { renderer.activeCamera = nil; renderer.entities.removeAll() }; configure(renderer, camera: camera)
        let texture = try ReplayRealityRendererAudit.makeTexture(size: 256)
        let output = try RealityRenderer.CameraOutput(.singleProjection(colorTexture: texture))
        try await render(renderer, output: output, name: "Slow run152 calibration")
        let result = try withExtendedLifetime((renderer, camera, output, root)) {
            try ReplayRealityRendererAudit.probe(ReplayRealityRendererAudit.read(texture))
        }
        let matches = result.candidates.filter { $0.maximumChannelError <= 4 }
        XCTAssertEqual(matches.count, 1); return try XCTUnwrap(matches.first)
    }
}
