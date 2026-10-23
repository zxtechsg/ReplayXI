import CoreGraphics
import Foundation
import Metal
import RealityKit
import UIKit
import XCTest
@testable import ReplayXI

private final class ReplayRenderCompletion: @unchecked Sendable {
    private let lock = NSLock()
    private var completed = false

    func finish() { lock.withLock { completed = true } }
    var isComplete: Bool { lock.withLock { completed } }
}

/// Public RealityRenderer output only: no SwiftUI, camera passthrough or
/// physical-headset validation. The calibration must pass before PNG export.
@MainActor
final class ReplayRealityRendererAuditTests: XCTestCase {
    func testCapturesCurvedAndLiftedAnnotationWithNativeGeometry() async throws {
        let calibrationFrame = try await renderCalibration()
        let probe = try ReplayRealityRendererAudit.probe(calibrationFrame)
        let matches = probe.candidates.filter { $0.maximumChannelError <= 4 }
        XCTAssertEqual(matches.count, 1)
        let calibration = try XCTUnwrap(matches.first)
        let scenario = try XCTUnwrap(DemoScenarios.scenario(for: .squadReplay))
        let root = PitchSceneFactory.makeMatchRoot(for: scenario)
        defer { for child in Array(root.children) { child.removeFromParent() } }
        let arc = CoachMark(kind: .arc, start: .init(x: -8, z: -2), end: .init(x: 8, z: -2),
                            curve: .init(bend: 3.2, lift: 1.2), label: "Bend around defender")
        PitchSceneFactory.update(root: root, scenario: scenario, time: 0,
            viewMode: .firstPerson, perspectiveID: scenario.defaultPerspectiveID,
            marks: [arc], showsLaneLens: false, isDrawing: false, positionalOriginTransform: nil)
        let mark = try XCTUnwrap(root.findEntity(named: "mark-\(arc.id.uuidString)"))
        mark.removeFromParent()
        let scene = Entity()
        scene.addChild(mark)
        let turf = ModelEntity(mesh: .generateBox(size: [23, 0.02, 15]),
                               materials: [UnlitMaterial(color: UIColor(red: 0.08, green: 0.20, blue: 0.12, alpha: 1))])
        turf.position.y = -0.05
        scene.addChild(turf)
        let camera = PerspectiveCamera()
        camera.camera = PerspectiveCameraComponent(near: 0.05, far: 100, fieldOfViewInDegrees: 55)
        camera.look(at: [0, 0.5, 0], from: [0, 12, 18], relativeTo: nil)
        let frame = try await render(entities: [scene, camera], camera: camera, size: 512).frame
        let rgba = frame.topFirstRGBA(calibration.rawRowsAreTopFirst)
        var purplePixels = 0
        for offset in stride(from: 0, to: rgba.count, by: 4) {
            if Int(rgba[offset]) > Int(rgba[offset + 1]) + 15,
               Int(rgba[offset + 2]) > Int(rgba[offset + 1]) + 30 { purplePixels += 1 }
        }
        XCTAssertGreaterThan(purplePixels, 50, "The actual curved tube must render, not only its caption")
        try attachPNG(frame, calibration: calibration, named: "ReplayXI-EditableArc-Native.png")
    }

    func testCapturesActualBootAndBallContactsBeforeAndAfterPresentationRepair() async throws {
        try XCTSkipIf(ReplayImportedAthleteFeatureGate.isEnabled, "Captures the normal local player skin")
        let probe = try ReplayRealityRendererAudit.probe(try await renderCalibration())
        let matches = probe.candidates.filter { $0.maximumChannelError <= 4 }
        XCTAssertEqual(matches.count, 1)
        let calibration = try XCTUnwrap(matches.first)
        try ReplaySkinnedAthleteProvider.prewarm()
        try ReplayStrategyBallProvider.prewarm()
        let scenario = try XCTUnwrap(DemoScenarios.scenario(for: .squadReplay))
        struct ContactReport: Encodable {
            let player: String
            let time: Double
            let sourcePosition: [Float]
            let correctedPosition: [Float]
            let scope: String
        }
        for (playerID, time) in [("navy-rw", 13.6), ("navy-rb", 17.5), ("navy-cf", 24.0)] {
            let player = try XCTUnwrap(scenario.player(id: playerID))
            let pose = player.presentationPose(at: time)
            let match = PitchSceneFactory.makeMatchRoot(for: scenario)
            defer { for child in Array(match.children) { child.removeFromParent() } }
            PitchSceneFactory.update(root: match, scenario: scenario, time: time,
                viewMode: .tacticalTable, perspectiveID: playerID, marks: [],
                showsLaneLens: false, isDrawing: false, positionalOriginTransform: nil)
            let actor = try XCTUnwrap(match.findEntity(named: "player-\(playerID)"))
            XCTAssertTrue(try XCTUnwrap(actor.findEntity(named: ReplaySkinnedAthleteProvider.visualRootName)).isEnabled)
            let ball = try XCTUnwrap(match.findEntity(named: "ball"))
            let corrected = ball.position - SIMD3<Float>(pose.position.x, 0, pose.position.z)
            let sourcePose = scenario.ball.pose(at: time)
            let source = SIMD3<Float>(sourcePose.position.x - pose.position.x,
                                      sourcePose.height, sourcePose.position.z - pose.position.z)
            XCTAssertGreaterThan(simd_distance(source, corrected), 0.4)
            XCTAssertEqual(ball.scale, SIMD3<Float>(repeating: 1))
            actor.removeFromParent()
            ball.removeFromParent()
            actor.position = .zero
            let scene = Entity()
            scene.orientation = simd_quatf(angle: -pose.facingDegrees * .pi / 180, axis: [0, 1, 0])
            scene.addChild(actor)
            scene.addChild(ball)
            let turf = ModelEntity(mesh: .generateBox(size: [4, 0.02, 4]),
                                   materials: [UnlitMaterial(color: UIColor(red: 0.08, green: 0.20,
                                                                          blue: 0.12, alpha: 1))])
            turf.position.y = -0.012
            scene.addChild(turf)
            let key = DirectionalLight()
            key.light.intensity = 2_200
            key.look(at: [0, 0.5, 0], from: [3, 4, 3], relativeTo: nil)
            let fill = DirectionalLight()
            fill.light.intensity = 600
            fill.look(at: [0, 0.5, 0], from: [-3, 2, 2], relativeTo: nil)
            let camera = PerspectiveCamera()
            camera.camera = PerspectiveCameraComponent(near: 0.05, far: 20, fieldOfViewInDegrees: 40)
            camera.look(at: [0, 0.48, 0.10], from: [1.8, 1.0, 2.15], relativeTo: nil)
            for (name, position) in [("source-centre", source), ("corrected-contact", corrected)] {
                ball.position = position
                let capture = try await render(entities: [scene, key, fill, camera], camera: camera, size: 512)
                try attachPNG(capture.frame, calibration: calibration,
                              named: "ReplayXI-BallContact-\(playerID)-\(name).png")
            }
            try attachJSON(ContactReport(player: playerID, time: time,
                sourcePosition: [source.x, source.y, source.z],
                correctedPosition: [corrected.x, corrected.y, corrected.z],
                scope: "Actual native skin and ball, lower-body crop; no UI or headset capture"),
                named: "ReplayXI-BallContact-\(playerID).json")
        }
    }

    func testCapturesWholeTouchlineReplayWithTimedAnnotationsAndBundledAssets() async throws {
        // A fixed audit camera, not a UI screenshot or headset capture. Keep
        // the actual Touchline root transform and its existing label observer.
        try XCTSkipIf(ReplayImportedAthleteFeatureGate.isEnabled,
                      "This capture covers default admission, not the legacy pilot")
        ReplayFarAthleteHeadProvider.resetForTesting()
        ReplaySkinnedAthleteProvider.resetForTesting()
        ReplayImportedAthleteProvider.resetPrewarmForTesting()
        ReplayAthleteHeadProvider.resetForTesting()
        ReplayFarAthletePaletteProvider.resetForTesting()
        ReplayStrategyBallProvider.resetForTesting()
        defer {
            ReplayFarAthleteHeadProvider.resetForTesting()
            ReplaySkinnedAthleteProvider.resetForTesting()
            ReplayImportedAthleteProvider.resetPrewarmForTesting()
            ReplayAthleteHeadProvider.resetForTesting()
            ReplayFarAthletePaletteProvider.resetForTesting()
            ReplayStrategyBallProvider.resetForTesting()
        }
        let scenario = try XCTUnwrap(DemoScenarios.scenario(for: .squadReplay))
        let time = 13.6
        try ReplayAthleteFactory.prewarm(for: scenario.players, lods: [.near, .far])
        try ReplaySkinnedAthleteProvider.prewarm()
        try ReplaySkinnedAthleteProvider.prewarmLowDetail()
        try ReplayFarAthleteHeadProvider.prewarm()
        try ReplayStrategyBallProvider.prewarm()
        try ReplayStrategyPitchProvider.prewarm()
        let match = PitchSceneFactory.makeMatchRoot(for: scenario)
        defer { for child in Array(match.children) { child.removeFromParent() } }
        PitchSceneFactory.update(root: match, scenario: scenario, time: time,
            viewMode: .touchline, perspectiveID: scenario.defaultPerspectiveID,
            marks: scenario.coachMarks, showsLaneLens: false, isDrawing: false,
            positionalOriginTransform: nil)
        XCTAssertEqual(match.scale, SIMD3<Float>(repeating: 0.085))
        XCTAssertEqual(match.position, [0, 0.02, -4.1])
        let pitch = try XCTUnwrap(match.findEntity(named: "pitch"))
        XCTAssertNotNil(pitch.components[ReplayStrategyPitchProvider.Admission.self])
        let fieldSurface = try XCTUnwrap(pitch.findEntity(named: "field-surface"))
        XCTAssertTrue(fieldSurface.isEnabledInHierarchy,
                      "The tabletop touchline view keeps the scaled pitch surface visible")
        XCTAssertTrue(try XCTUnwrap(pitch.findEntity(named: "pitch-markings-and-goals")).isEnabledInHierarchy)
        let ball = try XCTUnwrap(match.findEntity(named: "ball"))
        XCTAssertTrue(ball.isEnabledInHierarchy)
        XCTAssertTrue(try XCTUnwrap(ball.findEntity(named: ReplayStrategyBallProvider.visualRootName)).isEnabledInHierarchy)
        let ballPose = ReplayBallPlaybackMotion(track: scenario.ball, players: scenario.players).pose(at: time)
        XCTAssertEqual(ball.position.x, ballPose.position.x)
        XCTAssertEqual(ball.position.z, ballPose.position.z)

        let players = try XCTUnwrap(match.findEntity(named: "players-root"))
        XCTAssertEqual(players.children.count, 22)
        let skins = PitchSceneFactory.skinnedAthletesForTesting(in: match)
        XCTAssertEqual(skins.count, 4)
        let nearSkinCount = skins.values.filter { $0.detail == .near && $0.root.isEnabledInHierarchy }.count
        let lowSkinCount = skins.values.filter { $0.detail == .lowDetail && $0.root.isEnabledInHierarchy }.count
        XCTAssertEqual(nearSkinCount, 1)
        XCTAssertEqual(lowSkinCount, 3)
        let farRigs = players.children.compactMap { player in
            player.children.first { $0.name == "table-marker" && $0.isEnabledInHierarchy }
        }
        XCTAssertEqual(farRigs.count, 18)
        for rig in farRigs {
            let head = try XCTUnwrap(rig.findEntity(named: "head") as? ModelEntity)
            XCTAssertTrue(try XCTUnwrap(head.model).materials.first is PhysicallyBasedMaterial)
            XCTAssertTrue(head.isEnabledInHierarchy)
        }
        let labels = try XCTUnwrap(match.findEntity(named: "player-labels-root"))
        XCTAssertEqual(labels.children.filter(\.isEnabledInHierarchy).count, 22)

        let camera = PerspectiveCamera()
        // The enlarged pitch needs a wider square audit viewport. This is not
        // the headset's compositor camera or a change to user placement.
        let fieldOfView: Float = 70
        camera.camera = PerspectiveCameraComponent(near: 0.03, far: 30, fieldOfViewInDegrees: fieldOfView)
        let observer = match.convert(position: [-70, 0, 0], to: nil)
        var cameraPosition = SIMD3<Float>(observer.x, 1.6, observer.z)
        var cameraTarget = ball.position(relativeTo: nil)
        camera.look(at: cameraTarget, from: cameraPosition, relativeTo: nil)
        var cameraInverse = camera.transformMatrix(relativeTo: nil).inverse
        func vector(_ point: SIMD3<Float>) -> [Float] { [point.x, point.y, point.z] }
        func matrix(_ value: simd_float4x4) -> [Float] { (0..<4).flatMap { column in (0..<4).map { value[column][$0] } } }
        func projected(_ position: SIMD3<Float>) -> [Float] {
            let p = cameraInverse * SIMD4<Float>(position, 1)
            let extent = -p.z * tan(fieldOfView * .pi / 360)
            return [256 * (1 + p.x / extent), 256 * (1 - p.y / extent), -p.z]
        }
        struct MarkReport: Encodable {
            let id: String, kind: String, label: String
            let revealTime: Double
            let enabled: Bool, labelEnabled: Bool, arrowEnabled: Bool
            let labelRoomPosition: [Float]
            let arrowRoomPosition: [Float]?
            let arrowProjectedPixelAndDepth: [Float]?
        }
        func markReports() throws -> [MarkReport] {
            var result: [MarkReport] = []
            for mark in scenario.coachMarks {
                let entity = try XCTUnwrap(match.findEntity(named: "mark-\(mark.id.uuidString)"))
                let label = try XCTUnwrap(entity.findEntity(named: "annotation-label"))
                let arrow = entity.findEntity(named: "annotation-mark-arrow")
                XCTAssertEqual(entity.isEnabledInHierarchy, mark.isVisible(at: time))
                XCTAssertEqual(label.isEnabledInHierarchy, mark.isVisible(at: time))
                if mark.isVisible(at: time) {
                    XCTAssertTrue(try XCTUnwrap(arrow).isEnabledInHierarchy)
                    let point = projected(try XCTUnwrap(arrow).position(relativeTo: nil))
                    XCTAssertTrue(point.allSatisfy(\.isFinite))
                    XCTAssertTrue(point[0] >= 0 && point[0] < 512 && point[1] >= 0 && point[1] < 512 && point[2] > 0,
                                  "Active annotation arrow must be inside the fixed audit view")
                }
                result.append(MarkReport(id: mark.id.uuidString, kind: mark.kind.rawValue, label: mark.label,
                    revealTime: mark.revealTime, enabled: entity.isEnabledInHierarchy,
                    labelEnabled: label.isEnabledInHierarchy, arrowEnabled: arrow?.isEnabledInHierarchy ?? false,
                    labelRoomPosition: vector(label.position(relativeTo: nil)),
                    arrowRoomPosition: arrow.map { vector($0.position(relativeTo: nil)) },
                    arrowProjectedPixelAndDepth: arrow.map { projected($0.position(relativeTo: nil)) }))
            }
            return result
        }
        let marks = try markReports()
        XCTAssertEqual(marks.filter(\.enabled).count, 2)
        let key = DirectionalLight()
        key.light.intensity = 2_200
        key.look(at: cameraTarget, from: cameraTarget + SIMD3<Float>(3, 4, 3), relativeTo: nil)
        let fill = DirectionalLight()
        fill.light.intensity = 500
        fill.look(at: cameraTarget, from: cameraTarget + SIMD3<Float>(-3, 2, 2), relativeTo: nil)
        let calibrationFrame = try await renderCalibration()
        let probe = try ReplayRealityRendererAudit.probe(calibrationFrame)
        let matching = probe.candidates.filter { $0.maximumChannelError <= 4 }
        guard matching.count == 1, let calibration = matching.first else {
            throw ReplayRealityRendererAudit.Failure.unsupported("Whole-scene119 capture requires unique native calibration")
        }
        let frame = try await render(entities: [match, key, fill, camera], camera: camera, size: 512).frame
        func pixelCounts(_ image: ReplayRealityRendererAudit.Frame) -> (foreground: Int, colours: Int) {
            var foreground = 0
            var colours = Set<UInt32>()
            for y in 0..<512 {
                for x in 0..<512 {
                    let rgba = image.rgba(x: x, y: y, topFirst: calibration.rawRowsAreTopFirst)
                    if rgba[0] > 8 || rgba[1] > 8 || rgba[2] > 8 { foreground += 1 }
                    if x.isMultiple(of: 4), y.isMultiple(of: 4) {
                        colours.insert((UInt32(rgba[0] / 4) << 12) | (UInt32(rgba[1] / 4) << 6) | UInt32(rgba[2] / 4))
                    }
                }
            }
            return (foreground, colours.count)
        }
        let touchlinePixels = pixelCounts(frame)
        // Prove that the actual timed marks change rendered pixels,
        // while preserving every flag and the camera for the positive capture.
        let marksRoot = try XCTUnwrap(match.findEntity(named: "marks-root"))
        let originalMarksEnabled = marksRoot.isEnabled
        let withoutMarks: ReplayRealityRendererAudit.Frame
        do {
            defer { marksRoot.isEnabled = originalMarksEnabled }
            marksRoot.isEnabled = false
            withoutMarks = try await render(entities: [match, key, fill, camera], camera: camera, size: 512).frame
        }
        XCTAssertEqual(marksRoot.isEnabled, originalMarksEnabled)
        var marksDifferencePixels = 0
        for offset in stride(from: 0, to: frame.bgra.count, by: 4) {
            if frame.bgra[offset] != withoutMarks.bgra[offset]
                || frame.bgra[offset + 1] != withoutMarks.bgra[offset + 1]
                || frame.bgra[offset + 2] != withoutMarks.bgra[offset + 2] { marksDifferencePixels += 1 }
        }
        XCTAssertGreaterThan(marksDifferencePixels, 0, "Timed marks must visibly contribute, not merely exist in the graph")
        XCTAssertGreaterThan(touchlinePixels.foreground, marksDifferencePixels,
                             "Players/pitch context must remain beyond the annotation difference")
        XCTAssertGreaterThan(touchlinePixels.colours, 16, "An empty or single clear-colour frame is not scene evidence")
        struct SceneReport: Encodable {
            let scope = "Actual factory replay scene with default timed marks. Fixed audit camera/lights, not SwiftUI, compositor, frustum-count or headset readability evidence."
            let viewMode: String
            let pitchSurfaceEnabled: Bool
            let scenarioID: String, perspectiveID: String
            let time: Double
            let width = 512, height = 512
            let cameraRoomPosition: [Float], cameraRoomTarget: [Float], cameraMatrixColumnMajor: [Float]
            let verticalFieldOfViewDegrees: Float
            let matchRootMatrixColumnMajor: [Float]
            let ballPitchPosition: [Float], ballRoomPosition: [Float], ballProjectedPixelAndDepth: [Float]
            let hierarchyEnabledCounts: [String: Int]
            let admittedSkinDetailsByPlayer: [String: String]
            let assetHashes: [String: String]
            let marks: [MarkReport]
            let calibration: ReplayRealityRendererAudit.Calibration
            let nonBackgroundPixels: Int, sampledQuantizedColourCount: Int
            let marksVisibleDifferencePixels: Int?
        }
        func report(mode: ReplayViewMode, image: ReplayRealityRendererAudit.Frame, markDifference: Int?) throws -> SceneReport {
            let enabledModels = ReplayStrategyPitchProvider.models(in: match).filter(\.isEnabledInHierarchy)
            let currentSkins = PitchSceneFactory.skinnedAthletesForTesting(in: match)
            let currentFar = players.children.compactMap { player in
                player.children.first { $0.name == "table-marker" && $0.isEnabledInHierarchy }
            }
            let currentMarks = try markReports()
            let pixels = pixelCounts(image)
            return SceneReport(viewMode: mode.rawValue, pitchSurfaceEnabled: fieldSurface.isEnabledInHierarchy,
                scenarioID: scenario.id, perspectiveID: scenario.defaultPerspectiveID, time: time,
                cameraRoomPosition: vector(cameraPosition), cameraRoomTarget: vector(cameraTarget),
                cameraMatrixColumnMajor: matrix(camera.transformMatrix(relativeTo: nil)), verticalFieldOfViewDegrees: fieldOfView,
                matchRootMatrixColumnMajor: matrix(match.transform.matrix),
                ballPitchPosition: vector(ball.position), ballRoomPosition: vector(ball.position(relativeTo: nil)),
                ballProjectedPixelAndDepth: projected(ball.position(relativeTo: nil)),
                hierarchyEnabledCounts: ["players": players.children.filter(\.isEnabledInHierarchy).count,
                    "nearSkins": currentSkins.values.filter { $0.detail == .near && $0.root.isEnabledInHierarchy }.count,
                    "lowSkins": currentSkins.values.filter { $0.detail == .lowDetail && $0.root.isEnabledInHierarchy }.count,
                    "farStaticFaces": currentFar.count, "playerLabels": labels.children.filter(\.isEnabledInHierarchy).count,
                    "coachMarks": currentMarks.filter(\.enabled).count, "modelEntities": enabledModels.count],
                admittedSkinDetailsByPlayer: currentSkins.mapValues { String(describing: $0.detail) },
                assetHashes: ["pitch": ReplayStrategyPitchProvider.assetSHA256, "ball": ReplayStrategyBallProvider.assetSHA256,
                    "nearSkin": ReplaySkinnedAthleteProvider.assetSHA256, "lowSkin": ReplaySkinnedAthleteProvider.lowAssetSHA256,
                    "staticFarHead": ReplayFarAthleteHeadProvider.expectedSHA256],
                marks: currentMarks, calibration: calibration, nonBackgroundPixels: pixels.foreground,
                sampledQuantizedColourCount: pixels.colours, marksVisibleDifferencePixels: markDifference)
        }
        let touchlineReport = try report(mode: .touchline, image: frame, markDifference: marksDifferencePixels)
        try attachJSON(touchlineReport, named: "ReplayXI-RealityRenderer119-TouchlineScene.json")
        try attachPNG(frame, calibration: calibration, named: "ReplayXI-RealityRenderer119-TouchlineScene.png")

        // Separately capture the actual Table presentation and turf material.
        PitchSceneFactory.update(root: match, scenario: scenario, time: time,
            viewMode: .tacticalTable, perspectiveID: scenario.defaultPerspectiveID,
            marks: scenario.coachMarks, showsLaneLens: false, isDrawing: false,
            positionalOriginTransform: nil)
        XCTAssertEqual(match.scale, SIMD3<Float>(repeating: 0.040))
        XCTAssertTrue(fieldSurface.isEnabledInHierarchy)
        cameraPosition = [0, 1.6, 0]
        cameraTarget = match.position
        camera.look(at: cameraTarget, from: cameraPosition, relativeTo: nil)
        cameraInverse = camera.transformMatrix(relativeTo: nil).inverse
        let tacticalFrame = try await render(entities: [match, key, fill, camera], camera: camera, size: 512).frame
        let tacticalReport = try report(mode: .tacticalTable, image: tacticalFrame, markDifference: nil)
        XCTAssertGreaterThan(tacticalReport.nonBackgroundPixels, 5_000)
        XCTAssertGreaterThan(tacticalReport.sampledQuantizedColourCount, 16)
        XCTAssertEqual(tacticalReport.hierarchyEnabledCounts["coachMarks"], 2)
        XCTAssertEqual(tacticalReport.hierarchyEnabledCounts["players"], 22)
        XCTAssertEqual(tacticalReport.hierarchyEnabledCounts["nearSkins"], 1)
        XCTAssertEqual(tacticalReport.hierarchyEnabledCounts["lowSkins"], 3)
        XCTAssertEqual(tacticalReport.hierarchyEnabledCounts["farStaticFaces"], 18)
        try attachJSON(tacticalReport, named: "ReplayXI-RealityRenderer119-TacticalScene.json")
        try attachPNG(tacticalFrame, calibration: calibration, named: "ReplayXI-RealityRenderer119-TacticalScene.png")
    }

    func testCapturesRuntimeLowPlayerWithFootballPoseAndJerseyNumbers() async throws {
        ReplaySkinnedAthleteProvider.resetForTesting()
        ReplayAthleteHeadProvider.resetForTesting()
        defer {
            ReplaySkinnedAthleteProvider.resetForTesting()
            ReplayAthleteHeadProvider.resetForTesting()
        }
        try ReplaySkinnedAthleteProvider.prewarm()
        try ReplaySkinnedAthleteProvider.prewarmLowDetail()
        let scenario = try XCTUnwrap(DemoScenarios.scenario(for: .squadReplay))
        let player = try XCTUnwrap(scenario.player(id: "navy-rw"))
        let time = 13.6
        let ball = scenario.ball.pose(at: time)
        let lookTarget = SIMD3<Float>(ball.position.x, ball.height, ball.position.z)
        let action = try XCTUnwrap(ReplayAthleteMotion.ballActionPose(for: player, ballTrack: scenario.ball, at: time))
        XCTAssertGreaterThan(action.influence, 0)
        let skin = try ReplaySkinnedAthleteProvider.make(for: player, detail: .lowDetail)
        XCTAssertEqual(skin.detail, .lowDetail)
        XCTAssertTrue(skin.update(at: time, track: player, locomotion: player.locomotion(at: time),
            lookTarget: lookTarget, ballAction: nil))
        let locomotionOnly = skin.model.jointTransforms
        XCTAssertTrue(skin.update(at: time, track: player, locomotion: player.locomotion(at: time),
            lookTarget: lookTarget, ballAction: action))
        XCTAssertNotEqual(skin.model.jointTransforms, locomotionOnly,
            "Runtime capture must include the active football retarget, not just a canned gait")
        XCTAssertTrue(skin.front.isEnabledInHierarchy)
        XCTAssertTrue(skin.back.isEnabledInHierarchy)
        XCTAssertNotNil(skin.front.model)
        XCTAssertNotNil(skin.back.model)

        let calibrationFrame = try await renderCalibration()
        let probe = try ReplayRealityRendererAudit.probe(calibrationFrame)
        let matching = probe.candidates.filter { $0.maximumChannelError <= 4 }
        guard matching.count == 1, let calibration = matching.first else {
            throw ReplayRealityRendererAudit.Failure.unsupported("Runtime low preview requires unique fixed calibration")
        }
        let views: [(String, Float)] = [("front", 1), ("back", -1)]
        for (view, direction) in views {
            let key = DirectionalLight()
            key.light.intensity = 2_200
            key.look(at: [0, 0.9, 0], from: [3 * direction, 4, 3 * direction], relativeTo: nil)
            let fill = DirectionalLight()
            fill.light.intensity = 500
            fill.look(at: [0, 0.9, 0], from: [-3 * direction, 2, 2 * direction], relativeTo: nil)
            let camera = PerspectiveCamera()
            camera.camera = PerspectiveCameraComponent(near: 0.05, far: 20, fieldOfViewInDegrees: 40)
            camera.look(at: [0, 0.9, 0], from: [2.7 * direction, 1.5, 4 * direction], relativeTo: nil)
            let frame = try await render(entities: [skin.root, key, fill, camera], camera: camera, size: 512).frame
            var count = 0
            var left = frame.width, top = frame.height, right = -1, bottom = -1
            for y in 0..<frame.height {
                let row = calibration.rawRowsAreTopFirst ? y : frame.height - 1 - y
                for x in 0..<frame.width {
                    let offset = (row * frame.width + x) * 4
                    if frame.bgra[offset] > 8 || frame.bgra[offset + 1] > 8 || frame.bgra[offset + 2] > 8 {
                        count += 1
                        left = min(left, x); right = max(right, x)
                        top = min(top, y); bottom = max(bottom, y)
                    }
                }
            }
            try attachJSON(RuntimeLowReport(assetSHA256: ReplaySkinnedAthleteProvider.lowAssetSHA256,
                playerID: player.id, shirtNumber: player.shirtNumber, time: time, view: view,
                action: action.kind.rawValue, actionInfluence: action.influence,
                calibration: calibration, nonBackgroundPixels: count, pixelBounds: [left, top, right, bottom]),
                named: "ReplayXI-RealityRenderer104-RuntimeLow-\(view).json")
            guard count > 500, count < frame.width * frame.height * 7 / 10,
                  left > 4, top > 4, right < frame.width - 5, bottom < frame.height - 5 else {
                throw ReplayRealityRendererAudit.Failure.unsupported("Runtime low player is empty or clipped; no PNG exported")
            }
            try attachPNG(frame, calibration: calibration,
                named: "ReplayXI-RealityRenderer104-RuntimeLow-\(view).png")
        }
    }

    func testCapturesCanonicalLowSkinRunAndPassWithCalibratedNativeRenderer() async throws {
        // The fixture verifies pinned identities and only skips a genuinely
        // absent optional candidate. It does not change runtime admission.
        let run = try ReplayLowDetailAthleteFixture.loadAndPose(named: "run")
        let pass = try ReplayLowDetailAthleteFixture.loadAndPose(named: "pass-contact")
        let posed = [("run", run), ("pass-contact", pass)]
        let calibrationFrame = try await renderCalibration()
        let probe = try ReplayRealityRendererAudit.probe(calibrationFrame)
        let matching = probe.candidates.filter { $0.maximumChannelError <= 4 }
        guard matching.count == 1, let calibration = matching.first else {
            throw ReplayRealityRendererAudit.Failure.unsupported("Low candidate preview requires unique fixed calibration")
        }
        var previousPixels: [UInt8]?
        for (poseName, loaded) in posed {
            XCTAssertEqual(loaded.model.jointTransforms.count, 80)
            let key = DirectionalLight()
            key.light.intensity = 2_200
            key.look(at: [0, 0.9, 0], from: [3, 4, 3], relativeTo: nil)
            let fill = DirectionalLight()
            fill.light.intensity = 500
            fill.look(at: [0, 0.9, 0], from: [-3, 2, 2], relativeTo: nil)
            let camera = PerspectiveCamera()
            camera.camera = PerspectiveCameraComponent(near: 0.05, far: 20, fieldOfViewInDegrees: 40)
            camera.look(at: [0, 0.9, 0], from: [2.7, 1.5, 4], relativeTo: nil)
            let frame = try await render(entities: [loaded.root, key, fill, camera], camera: camera, size: 512).frame
            var count = 0
            var left = frame.width, top = frame.height, right = -1, bottom = -1
            for y in 0..<frame.height {
                let row = calibration.rawRowsAreTopFirst ? y : frame.height - 1 - y
                for x in 0..<frame.width {
                    let offset = (row * frame.width + x) * 4
                    if frame.bgra[offset] > 8 || frame.bgra[offset + 1] > 8 || frame.bgra[offset + 2] > 8 {
                        count += 1
                        left = min(left, x); right = max(right, x)
                        top = min(top, y); bottom = max(bottom, y)
                    }
                }
            }
            try attachJSON(LowCandidateReport(assetSHA256: ReplayLowDetailAthleteFixture.assetHash,
                pose: poseName, calibration: calibration,
                jointCount: loaded.model.jointTransforms.count, rootGroundOffset: loaded.root.position.y,
                nonBackgroundPixels: count, pixelBounds: [left, top, right, bottom]),
                named: "ReplayXI-RealityRenderer104-Low109-\(poseName).json")
            guard count > 500, count < frame.width * frame.height * 7 / 10,
                  left > 4, top > 4, right < frame.width - 5, bottom < frame.height - 5 else {
                throw ReplayRealityRendererAudit.Failure.unsupported("Low candidate is empty or clipped; no PNG exported")
            }
            if let previousPixels {
                XCTAssertFalse(frame.bgra == previousPixels, "Distinct source poses must not render as one unchanged bind pose")
            }
            previousPixels = frame.bgra
            try attachPNG(frame, calibration: calibration,
                named: "ReplayXI-RealityRenderer104-Low109-\(poseName).png")
        }
    }

    /// Diagnostic only. It records the documented tone-map combinations without
    /// fitting a transfer curve, relaxing calibration, or exporting an image.
    func testRecordsNativeToneMapAndMidGreyCalibrationCombinations() async throws {
        let space = try XCTUnwrap(CGColorSpace(name: CGColorSpace.sRGB))
        let grey = try XCTUnwrap(CGColor(colorSpace: space,
            components: [128.0 / 255, 128.0 / 255, 128.0 / 255, 1]))
        var clearSamples: [ClearSample] = []
        var swatchSamples: [ToneMapSample] = []
        for cameraToneMapping in [false, true] {
            let camera = makeCalibrationCamera()
            let clear = try await render(entities: [camera], camera: camera, size: 64,
                toneMapping: cameraToneMapping, background: grey)
            let centre = clear.frame.rgba(x: 32, y: 32, topFirst: true)
            XCTAssertEqual(centre[3], 255)
            XCTAssertTrue(centre.prefix(3).contains { $0 > 0 }, "Known grey clear must not be empty")
            clearSamples.append(ClearSample(settings: clear.settings,
                source: ColourDescription(grey), expectedRGBA: [128, 128, 128, 255],
                centreRGBA: centre, cornerRGBA: clear.frame.rgba(x: 0, y: 0, topFirst: true)))

            for materialToneMapping in [false, true] {
                let scene = try makeCalibrationScene(materialToneMapping: materialToneMapping)
                let capture = try await render(entities: scene.entities, camera: scene.camera,
                    size: 256, toneMapping: cameraToneMapping)
                let probe = try ReplayRealityRendererAudit.probe(capture.frame)
                XCTAssertEqual(capture.settings.requestedToneMapping, cameraToneMapping)
                XCTAssertEqual(capture.settings.actualToneMapping, cameraToneMapping)
                // The initializer's colour compensation is not documented as
                // the generic program descriptor's getter. Keep both values
                // in the receipt; validate the supported path using pixels.
                XCTAssertTrue(probe.rawTopFirstSamples.allSatisfy { $0[3] == 255 })
                XCTAssertGreaterThanOrEqual(Set(probe.rawTopFirstSamples.map { Data($0) }).count, 4,
                    "A single clear colour is not a rendered calibration scene")
                if cameraToneMapping && !materialToneMapping {
                    XCTAssertEqual(probe.candidates.filter { $0.maximumChannelError <= 4 }.count, 1,
                        "Normal renderer tone mapping plus unlit colour compensation must calibrate uniquely")
                }
                swatchSamples.append(ToneMapSample(settings: capture.settings,
                    materialToneMapping: materialToneMapping, materials: scene.materials, probe: probe))
            }
        }
        let report = ToneMapComparison(clearSamples: clearSamples, swatchSamples: swatchSamples)
        try attachJSON(report, named: "ReplayXI-RealityRenderer104-ToneMapComparison.json")
    }

    func testCalibratesNativeRowsChannelsAndGamutBeforeCapturingFarAvatar() async throws {
        let calibrationFrame = try await renderCalibration()
        let probe = try ReplayRealityRendererAudit.probe(calibrationFrame)
        try attachJSON(probe, named: "ReplayXI-RealityRenderer104-Calibration.json")
        let matching = probe.candidates.filter { $0.maximumChannelError <= 4 }
        guard matching.count == 1, let calibration = matching.first else {
            throw ReplayRealityRendererAudit.Failure.unsupported(
                "Native swatches do not uniquely establish output rows/channels/gamut; no PNG exported"
            )
        }
        try attachPNG(calibrationFrame, calibration: calibration,
            named: "ReplayXI-RealityRenderer104-CalibratedSwatches.png")

        ReplaySkinnedAthleteProvider.resetForTesting()
        ReplayImportedAthleteProvider.resetPrewarmForTesting()
        ReplayFarAthletePaletteProvider.resetForTesting()
        defer {
            ReplaySkinnedAthleteProvider.resetForTesting()
            ReplayImportedAthleteProvider.resetPrewarmForTesting()
            ReplayAthleteHeadProvider.resetForTesting()
            ReplayFarAthletePaletteProvider.resetForTesting()
        }
        let scenario = try XCTUnwrap(DemoScenarios.scenario(for: .squadReplay))
        let time = 11.691666666666666
        let match = PitchSceneFactory.makeMatchRoot(for: scenario)
        PitchSceneFactory.update(root: match, scenario: scenario, time: time,
            viewMode: .firstPerson, perspectiveID: "navy-gk", marks: [],
            showsLaneLens: false, isDrawing: false, positionalOriginTransform: nil)
        let player = try XCTUnwrap(match.findEntity(named: "player-navy-rb"))
        let marker = try XCTUnwrap(player.children.first { $0.name == "table-marker" })
        XCTAssertTrue(marker.isEnabledInHierarchy)
        let leg = try XCTUnwrap(marker.findEntity(named: "left-leg") as? ModelEntity)
        let material = try XCTUnwrap(leg.model?.materials.first as? SimpleMaterial)
        XCTAssertNotNil(material.color.texture, "Audit must use the actual prepared far palette")

        let avatar = Entity()
        avatar.orientation = player.orientation
        avatar.addChild(marker.clone(recursive: true))
        let key = DirectionalLight()
        key.light.intensity = 2_200
        key.look(at: [0, 0.9, 0], from: [3, 4, 3], relativeTo: nil)
        let fill = DirectionalLight()
        fill.light.intensity = 500
        fill.look(at: [0, 0.9, 0], from: [-3, 2, 2], relativeTo: nil)
        let camera = PerspectiveCamera()
        camera.camera = PerspectiveCameraComponent(near: 0.05, far: 20, fieldOfViewInDegrees: 40)
        camera.look(at: [0, 0.9, 0], from: [2.7, 1.5, 4], relativeTo: nil)
        let frame = try await render(entities: [avatar, key, fill, camera], camera: camera, size: 512).frame
        var count = 0
        var left = frame.width, top = frame.height, right = -1, bottom = -1
        for y in 0..<frame.height {
            let rawRow = calibration.rawRowsAreTopFirst ? y : frame.height - 1 - y
            for x in 0..<frame.width {
                let offset = (rawRow * frame.width + x) * 4
                if frame.bgra[offset] > 8 || frame.bgra[offset + 1] > 8 || frame.bgra[offset + 2] > 8 {
                    count += 1
                    left = min(left, x); right = max(right, x)
                    top = min(top, y); bottom = max(bottom, y)
                }
            }
        }
        let report = AvatarReport(time: time, colourSpace: calibration.gamut.rawValue,
            rawRowsAreTopFirst: calibration.rawRowsAreTopFirst, nonBackgroundPixels: count,
            pixelBounds: [left, top, right, bottom])
        try attachJSON(report, named: "ReplayXI-RealityRenderer104-FarAvatar.json")
        guard count > 500, count < frame.width * frame.height * 7 / 10,
              left > 4, top > 4, right < frame.width - 5, bottom < frame.height - 5 else {
            throw ReplayRealityRendererAudit.Failure.unsupported(
                "Far avatar is empty, clipped or indistinguishable from its background; no avatar PNG exported"
            )
        }
        try attachPNG(frame, calibration: calibration,
            named: "ReplayXI-RealityRenderer104-NativeFarNavyRB.png")
    }

    private struct AvatarReport: Encodable {
        let renderer = "RealityRenderer, native offscreen test"
        let playerID = "navy-rb"
        let time: Double
        let width = 512
        let height = 512
        let pixelFormat = "bgra8Unorm_srgb"
        let rendererToneMapping = true
        let calibrationMaterialInitializerToneMapping = false
        let colourSpace: String
        let pngOrigin = "top-left"
        let rawRowsAreTopFirst: Bool
        let nonBackgroundPixels: Int
        let pixelBounds: [Int]
        let scope = "Actual far marker pose/materials; fixed audit lights/camera. Not UI or headset evidence."
    }

    private struct LowCandidateReport: Encodable {
        let scope = "Pinned optional Low109 fixture with direct canonical joint writes; fixed audit lights/camera. This fixture bypasses runtime admission; not headset evidence."
        let assetSHA256: String
        let width = 512, height = 512
        let pixelFormat = "bgra8Unorm_srgb"
        let pngOrigin = "top-left"
        let rendererToneMapping = true
        let calibrationMaterialInitializerToneMapping = false
        let pose: String
        let calibration: ReplayRealityRendererAudit.Calibration
        let jointCount: Int
        let rootGroundOffset: Float
        let nonBackgroundPixels: Int
        let pixelBounds: [Int]
    }

    private struct RuntimeLowReport: Encodable {
        let scope = "Actual bundled low provider, prepared skin/kit, current football retarget/look and front/back numbers in local body coordinates. Fixed audit lights/camera; not full scene, performance or headset evidence."
        let width = 512, height = 512
        let pixelFormat = "bgra8Unorm_srgb"
        let pngOrigin = "top-left"
        let rendererToneMapping = true
        let calibrationMaterialInitializerToneMapping = false
        let assetSHA256: String
        let playerID: String
        let shirtNumber: Int
        let time: Double
        let view: String
        let action: String
        let actionInfluence: Float
        let calibration: ReplayRealityRendererAudit.Calibration
        let nonBackgroundPixels: Int
        let pixelBounds: [Int]
    }

    private struct ColourDescription: Encodable {
        let colourSpace: String
        let components: [Double]

        init(_ colour: CGColor) {
            colourSpace = colour.colorSpace?.name.map { $0 as String } ?? "unnamed"
            components = colour.components?.map(Double.init) ?? []
        }
    }

    private struct MaterialDescription: Encodable {
        let sourceSRGB: [UInt8]
        let storedTint: ColourDescription
        let programDescriptorToneMapping: Bool
    }

    private struct RenderSettings: Encodable {
        let defaultToneMapping: Bool
        let defaultAntialiasing: String
        let defaultImageBasedLightResourcePresent: Bool
        let defaultImageBasedLightIntensityExponent: Float
        let requestedToneMapping: Bool
        let actualToneMapping: Bool
        let actualAntialiasing: String
    }

    private struct Capture {
        let frame: ReplayRealityRendererAudit.Frame
        let settings: RenderSettings
    }

    private struct ClearSample: Encodable {
        let settings: RenderSettings
        let source: ColourDescription
        let expectedRGBA: [UInt8]
        let centreRGBA: [UInt8]
        let cornerRGBA: [UInt8]
    }

    private struct ToneMapSample: Encodable {
        let settings: RenderSettings
        let materialToneMapping: Bool
        let materials: [MaterialDescription]
        let probe: ReplayRealityRendererAudit.CalibrationProbe
    }

    private struct ToneMapComparison: Encodable {
        let scope = "Six bounded offscreen calibration renders; no PNG, avatar, UI or headset claim."
        let colourExpectation = "Original CoreGraphics sRGB and Display P3 conversions; maximum error remains four bytes."
        let materialFlagScope = "Requested initializer colour compensation and generic program descriptor are logged separately; they are not assumed to be a setter/getter pair."
        let exposureAPI = "No RealityRenderer exposure control is declared in the current local XROS Swift interface. No exposure adjustment was applied."
        let shaderDiagnostics = "Concurrent simulator pipeline log errors are not a proven cause of a colour mismatch."
        let clearSamples: [ClearSample]
        let swatchSamples: [ToneMapSample]
    }

    private struct CalibrationScene {
        let entities: [Entity]
        let camera: PerspectiveCamera
        let materials: [MaterialDescription]
    }

    private func makeCalibrationScene(materialToneMapping: Bool) throws -> CalibrationScene {
        let root = Entity()
        let space = try XCTUnwrap(CGColorSpace(name: CGColorSpace.sRGB))
        var descriptions: [MaterialDescription] = []
        for (index, bytes) in ReplayRealityRendererAudit.swatches.enumerated() {
            let components = bytes.map { CGFloat($0) / 255 } + [1]
            let colour = try XCTUnwrap(CGColor(colorSpace: space, components: components))
            let material = UnlitMaterial(color: UIColor(cgColor: colour),
                applyPostProcessToneMap: materialToneMapping)
            descriptions.append(MaterialDescription(sourceSRGB: bytes,
                storedTint: ColourDescription(material.color.tint.cgColor),
                programDescriptorToneMapping: material.program.descriptor.applyPostProcessToneMap))
            let swatch = ModelEntity(
                mesh: .generateBox(size: [1.2, 0.6, 0.01]),
                materials: [material]
            )
            swatch.position = ReplayRealityRendererAudit.swatchPosition(index)
            root.addChild(swatch)
        }
        let camera = makeCalibrationCamera()
        return CalibrationScene(entities: [root, camera], camera: camera, materials: descriptions)
    }

    private func makeCalibrationCamera() -> PerspectiveCamera {
        let camera = PerspectiveCamera()
        camera.camera = PerspectiveCameraComponent(near: 0.05, far: 10, fieldOfViewInDegrees: 90)
        camera.position = [0, 0, 2]
        return camera
    }

    private func renderCalibration() async throws -> ReplayRealityRendererAudit.Frame {
        let scene = try makeCalibrationScene(materialToneMapping: false)
        return try await render(entities: scene.entities, camera: scene.camera, size: 256).frame
    }

    private func render(entities: [Entity], camera: Entity, size: Int,
                        toneMapping: Bool = true, background: CGColor? = nil) async throws -> Capture {
        let renderer = try RealityRenderer()
        let defaultToneMapping = renderer.cameraSettings.isToneMappingEnabled
        let defaultAntialiasing = String(describing: renderer.cameraSettings.antialiasing)
        let defaultLightPresent = renderer.lighting.resource != nil
        let defaultLightIntensity = renderer.lighting.intensityExponent
        renderer.entities.append(contentsOf: entities)
        renderer.activeCamera = camera
        renderer.cameraSettings.isToneMappingEnabled = toneMapping
        renderer.cameraSettings.antialiasing = .none
        renderer.cameraSettings.colorBackground = .color(background ?? CGColor(gray: 0, alpha: 1))
        let settings = RenderSettings(defaultToneMapping: defaultToneMapping,
            defaultAntialiasing: defaultAntialiasing,
            defaultImageBasedLightResourcePresent: defaultLightPresent,
            defaultImageBasedLightIntensityExponent: defaultLightIntensity,
            requestedToneMapping: toneMapping, actualToneMapping: renderer.cameraSettings.isToneMappingEnabled,
            actualAntialiasing: String(describing: renderer.cameraSettings.antialiasing))
        let texture = try ReplayRealityRendererAudit.makeTexture(size: size)
        let output = try RealityRenderer.CameraOutput(.singleProjection(colorTexture: texture))
        let completion = expectation(description: "RealityRenderer GPU completion")
        let flag = ReplayRenderCompletion()
        // Apple's completion callback runs after its MTLCommandBuffer, so CPU
        // readback occurs only after the awaited callback, never a semaphore.
        try renderer.updateAndRender(deltaTime: 0, cameraOutput: output, onComplete: { _ in
            flag.finish()
            completion.fulfill()
        })
        await fulfillment(of: [completion], timeout: 10)
        guard flag.isComplete else {
            throw ReplayRealityRendererAudit.Failure.unsupported("Native render exceeded its ten-second deadline")
        }
        return try withExtendedLifetime(renderer) {
            Capture(frame: try ReplayRealityRendererAudit.read(texture), settings: settings)
        }
    }

    private func attachJSON<T: Encodable>(_ value: T, named name: String) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .prettyPrinted]
        let data = try encoder.encode(value)
        XCTAssertLessThan(data.count, 32 * 1024)
        let attachment = XCTAttachment(data: data, uniformTypeIdentifier: "public.json")
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    private func attachPNG(_ frame: ReplayRealityRendererAudit.Frame,
                           calibration: ReplayRealityRendererAudit.Calibration, named name: String) throws {
        let data = try ReplayRealityRendererAudit.png(frame, calibration: calibration)
        let attachment = XCTAttachment(data: data, uniformTypeIdentifier: "public.png")
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
