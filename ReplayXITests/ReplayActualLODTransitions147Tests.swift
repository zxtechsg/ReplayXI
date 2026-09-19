import Foundation
import RealityKit
import simd
import XCTest
@testable import ReplayXI

/// Real scene admission, not forced side-by-side LODs or a headset capture.
@MainActor
final class ReplayActualLODTransitions147Tests: XCTestCase {
    private let targetIDs = ["arg-13", "arg-19"]
    private struct Context {
        let scenario: ReplayScenario
        let recording: ReplayNativeBallPhysics.Recording
    }
    private final class WeakRoot {
        weak var value: Entity?
        init(_ value: Entity) { self.value = value }
    }
    private final class WeakSkin {
        weak var value: ReplaySkinnedAthleteInstance?
        init(_ value: ReplaySkinnedAthleteInstance) { self.value = value }
    }
    private struct Snapshot: Equatable {
        let detail: String
        let playerTransform: Transform
        let rootTransform: Transform
        let joints: [Transform]
        let arms: [[SIMD3<Float>]]
        let worldArms: [[SIMD3<Float>]]
        let farArmsEnabled: [Bool]
        let skinModelEnabled: Bool
        let distance: Float

        var row: [String: Any] {
            let eye = SIMD3<Float>(0, 1.65, 0)
            let relative = worldArms.flatMap { $0 }.map { $0 - eye }
            return ["detail": detail, "activeJointCount": joints.count,
                    "armsPlayerSpace": arms.map { $0.map(Self.vector) },
                    "armsWorldSpace": worldArms.map { $0.map(Self.vector) },
                    "farArmModelsEnabledInHierarchy": farArmsEnabled,
                    "skinModelEnabledInHierarchy": skinModelEnabled,
                    "wearerDistanceMetres": distance,
                    "assumedEyePosition": Self.vector(eye),
                    "depthAlongRoomMinusZ": relative.map { -$0.z },
                    "azimuthFromRoomMinusZDegrees": relative.map { atan2($0.x, -$0.z) * 180 / .pi }]
        }

        private static func vector(_ p: SIMD3<Float>) -> [Float] { [p.x, p.y, p.z] }
    }
    private var roots: [WeakRoot] = []
    private var skins: [WeakSkin] = []

    override func setUp() {
        super.setUp()
        resetProviders()
    }

    override func tearDown() {
        // A cold cache creation prunes released scene owners. Use a tiny tree,
        // not a second match or a new public/debug production cleanup API.
        if let scenario = FootballReferenceScenarios.all.first(where: { $0.id == "final-108-rebound-v2" }) {
            let empty = Entity()
            let marks = Entity(); marks.name = "marks-root"; empty.addChild(marks)
            update(empty, scenario: scenario, time: 0, wearer: "arg-10")
            for child in Array(empty.children) { child.removeFromParent() }
        }
        XCTAssertTrue(roots.allSatisfy { $0.value == nil }, "Test-owned scene roots must be released")
        XCTAssertTrue(skins.allSatisfy { $0.value == nil }, "Expired scene caches must release skin instances")
        roots.removeAll(); skins.removeAll()
        resetProviders()
        super.tearDown()
    }

    func testActualReboundPOVNearFarReturnAtPointThree() async throws {
        let context = try await prepare()
        let rows = try withScene(context) { root -> [[String: Any]] in
            var rows: [[String: Any]] = []
            update(root, scenario: context.scenario, time: 0.3, wearer: "arg-23")
            XCTAssertEqual(nearIDs(root), targetIDs)
            let first = try snapshots(root, context: context, time: 0.3, wearer: "arg-23")
            XCTAssertTrue(first.values.allSatisfy { $0.detail == "near" })
            let previousRoots = PitchSceneFactory.skinnedAthletesForTesting(in: root).values.map { WeakRoot($0.root) }
            rows.append(row(root, snapshots: first, time: 0.3, wearer: "arg-23", kind: "initial-near"))

            update(root, scenario: context.scenario, time: 0.3, wearer: "arg-10")
            let far = try snapshots(root, context: context, time: 0.3, wearer: "arg-10")
            XCTAssertTrue(far.values.allSatisfy { $0.detail == "far" })
            XCTAssertTrue(previousRoots.allSatisfy { $0.value?.parent == nil })
            rows.append(row(root, snapshots: far, time: 0.3, wearer: "arg-10", kind: "wearer-change-far"))

            update(root, scenario: context.scenario, time: 0.3, wearer: "arg-23")
            XCTAssertEqual(nearIDs(root), targetIDs)
            let returned = try snapshots(root, context: context, time: 0.3, wearer: "arg-23")
            XCTAssertEqual(returned, first, "Returning to the same wearer/time restores submitted poses exactly")
            rows.append(row(root, snapshots: returned, time: 0.3, wearer: "arg-23", kind: "wearer-return-near"))

            update(root, scenario: context.scenario, time: 1.2, wearer: "arg-23")
            update(root, scenario: context.scenario, time: 0.3, wearer: "arg-23")
            let rewound = try snapshots(root, context: context, time: 0.3, wearer: "arg-23")
            XCTAssertEqual(rewound, first, "Same-wearer seek restores both near arm poses exactly")
            rows.append(row(root, snapshots: rewound, time: 0.3, wearer: "arg-23", kind: "time-rewind-near"))
            update(root, scenario: context.scenario, time: 1.2, wearer: "arg-10")
            update(root, scenario: context.scenario, time: 0.3, wearer: "arg-10")
            let farRewound = try snapshots(root, context: context, time: 0.3, wearer: "arg-10")
            XCTAssertEqual(farRewound, far, "Same-wearer seek restores both submitted far arm meshes exactly")
            rows.append(row(root, snapshots: farRewound, time: 0.3, wearer: "arg-10", kind: "time-rewind-far"))
            return rows
        }
        try attach(rows, name: "FixedTimeWearerSwitch")
    }

    func testActualReboundFixedWearerAdmissionsAcrossSevenSeconds() async throws {
        let context = try await prepare()
        XCTAssertEqual(context.scenario.duration, 7)
        var rows: [[String: Any]] = []
        for wearer in ["arg-23", "arg-10"] {
            rows += try withScene(context) { root -> [[String: Any]] in
                var rows: [[String: Any]] = []
                var previousIDs: [String]?
                var previousSnapshots: [String: Snapshot] = [:]
                var eventCount = 0
                var targetEvents: [String: Int] = Dictionary(uniqueKeysWithValues: targetIDs.map { ($0, 0) })
                var counts: [String: [String: Int]] = [:]
                for frame in 0...420 {
                    let time = Double(frame) / 60
                    update(root, scenario: context.scenario, time: time, wearer: wearer)
                    let admitted = nearIDs(root)
                    let current = try snapshots(root, context: context, time: time, wearer: wearer)
                    let changed = previousIDs != nil && previousIDs != admitted
                    if changed { eventCount += 1 }
                    for id in targetIDs {
                        let state = try XCTUnwrap(current[id])
                        counts[id, default: [:]][state.detail, default: 0] += 1
                        if let previous = previousSnapshots[id], previous.detail != state.detail {
                            targetEvents[id, default: 0] += 1
                        }
                    }
                    if frame == 0 || frame == 18 || frame == 420 || changed {
                        var value = row(root, snapshots: current, time: time, wearer: wearer,
                                        kind: changed ? "admission-change" : "checkpoint")
                        if changed {
                            value["previousTime"] = Double(frame - 1) / 60
                            value["previousNearIDs"] = previousIDs
                            value["previousTargets"] = previousSnapshots.mapValues(\.row)
                        }
                        rows.append(value)
                    }
                    previousIDs = admitted
                    previousSnapshots = current
                }
                for id in targetIDs { XCTAssertEqual(counts[id]?.values.reduce(0, +), 421) }
                rows.append(["kind": "summary", "wearer": wearer, "frames": 421, "sampleRateHz": 60,
                             "admissionChanges": eventCount, "targetAdmissionChanges": targetEvents,
                             "targetDetailFrameCounts": counts])
                return rows
            }
        }
        try attach(rows, name: "FixedWearer60HzAdmissionEvents")
    }

    private func prepare() async throws -> Context {
        try XCTSkipIf(ReplayImportedAthleteFeatureGate.isEnabled, "Default production skin path only")
        let scenario = try XCTUnwrap(FootballReferenceScenarios.all.first { $0.id == "final-108-rebound-v2" })
        try ReplaySkinnedAthleteProvider.prewarm()
        try ReplaySkinnedAthleteProvider.prewarmLowDetail()
        try ReplayFarAthleteHeadProvider.prewarm()
        try ReplayArticulatedFarProvider.prewarm()
        try ReplayArticulatedFarKitProvider.prewarm()
        try ReplayAthleteFactory.prewarm(for: scenario.players, lods: [.near, .far])
        let recording = try await ReplayNativeBallPhysics.prewarm(track: scenario.ball, players: scenario.players,
            plannedTouches: FootballReferenceScenarios.touches(for: scenario))
        XCTAssertEqual(recording.samples.count, 841)
        XCTAssertEqual(recording.nativeStepCount, 840)
        XCTAssertEqual(recording.touches.count, 6)
        XCTAssertEqual(recording.missedTouchCount, 0)
        XCTAssertFalse(recording.touches.contains { targetIDs.contains($0.playerID) })
        return Context(scenario: scenario, recording: recording)
    }

    private func withScene<T>(_ context: Context, body: (Entity) throws -> T) throws -> T {
        let root = PitchSceneFactory.makeMatchRoot(for: context.scenario, nativeRecording: context.recording)
        roots.append(WeakRoot(root))
        defer { for child in Array(root.children) { child.removeFromParent() } }
        let attached = try XCTUnwrap(PitchSceneFactory.nativeBallRecordingForTesting(in: root))
        XCTAssertEqual(attached.samples.map(\.position), context.recording.samples.map(\.position))
        XCTAssertEqual(attached.samples.map { $0.orientation.vector }, context.recording.samples.map { $0.orientation.vector })
        XCTAssertEqual(attached.touches.map(\.time), context.recording.touches.map(\.time))
        return try body(root)
    }

    private func update(_ root: Entity, scenario: ReplayScenario, time: Double, wearer: String) {
        PitchSceneFactory.update(root: root, scenario: scenario, time: time, viewMode: .firstPerson,
            perspectiveID: wearer, marks: scenario.coachMarks, showsLaneLens: false, isDrawing: false,
            positionalOriginTransform: nil)
        for skin in PitchSceneFactory.skinnedAthletesForTesting(in: root).values {
            if !skins.contains(where: { $0.value === skin }) { skins.append(WeakSkin(skin)) }
        }
    }

    private func nearIDs(_ root: Entity) -> [String] {
        PitchSceneFactory.skinnedAthletesForTesting(in: root).keys.sorted()
    }

    private func snapshots(_ root: Entity, context: Context, time: Double, wearer: String) throws -> [String: Snapshot] {
        let admitted = PitchSceneFactory.skinnedAthletesForTesting(in: root)
        XCTAssertEqual(admitted.count, PitchSceneFactory.firstPersonDetailedRigLimit)
        XCTAssertTrue(admitted.values.allSatisfy { $0.detail == .near }, "POV never admits low skins")
        XCTAssertNil(admitted[wearer])
        let wearerBody = try XCTUnwrap(root.findEntity(named: "player-\(wearer)"))
        XCTAssertFalse(try XCTUnwrap(wearerBody.findEntity(named: "table-marker")).isEnabledInHierarchy)
        let wearerPose = try XCTUnwrap(context.scenario.player(id: wearer)).presentationPose(at: time)
        let ball = try XCTUnwrap(root.findEntity(named: "ball"))
        let nativePosition = context.recording.sample(at: time).position
        XCTAssertEqual(ball.position, [nativePosition.x, max(nativePosition.y, 0.11), nativePosition.z],
                       "POV preserves the native trajectory with its existing visual floor clamp")
        XCTAssertEqual(ball.orientation.vector, context.recording.orientation(at: time).vector)
        var result: [String: Snapshot] = [:]
        for id in targetIDs {
            let player = try XCTUnwrap(context.scenario.player(id: id))
            let body = try XCTUnwrap(root.findEntity(named: "player-\(id)"))
            let pose = player.presentationPose(at: time)
            XCTAssertEqual(body.position, [pose.position.x, 0, pose.position.z])
            let far = try XCTUnwrap(body.children.first { $0.name == "table-marker" })
            let models = try ["left-arm", "right-arm"].map { name in
                try XCTUnwrap(far.findEntity(named: name) as? ModelEntity)
            }
            let farEnabled = models.map(\.isEnabledInHierarchy)
            var armPoints: [[SIMD3<Float>]] = [], worldPoints: [[SIMD3<Float>]] = []
            let activeJoints: [Transform]
            if let skin = admitted[id] {
                XCTAssertTrue(skin.root.parent === body)
                XCTAssertTrue(skin.model.isEnabledInHierarchy)
                XCTAssertFalse(far.isEnabledInHierarchy)
                XCTAssertEqual(farEnabled, [false, false])
                activeJoints = skin.model.jointTransforms
                var submitted = skin.pose
                for (index, joint) in activeJoints.enumerated() {
                    submitted.translations[index] = joint.translation
                    submitted.rotations[index] = joint.rotation
                    submitted.scales[index] = joint.scale
                }
                skin.motion.rebuildModelSpaceTransforms(in: &submitted)
                for side in ["left", "right"] {
                    let points = try ["Shoulder", "Elbow", "Wrist"].map { suffix -> SIMD3<Float> in
                        let index = try XCTUnwrap(skin.motion.semanticJointIndices[side + suffix])
                        let p = submitted.modelSpaceTransforms[index].columns.3
                        return SIMD3<Float>(p.x, p.y, p.z)
                    }
                    armPoints.append(points.map { skin.model.convert(position: $0, to: body) })
                    worldPoints.append(points.map { skin.model.convert(position: $0, to: nil) })
                }
            } else {
                XCTAssertTrue(far.isEnabledInHierarchy)
                XCTAssertEqual(farEnabled, [true, true])
                XCTAssertNil(body.children.first { $0.name == "full-rig" })
                activeJoints = models.flatMap(\.jointTransforms)
                for model in models {
                    XCTAssertEqual(model.jointNames, ["Root", "Root/Bend", "Root/Bend/Tip"])
                    let joints = model.jointTransforms
                    XCTAssertEqual(joints.count, 3)
                    guard joints.count == 3 else { throw NSError(domain: "ActualLOD147", code: 1) }
                    let matrices = [joints[0].matrix, joints[0].matrix * joints[1].matrix,
                                    joints[0].matrix * joints[1].matrix * joints[2].matrix]
                    let points = matrices.map { SIMD3<Float>($0.columns.3.x, $0.columns.3.y, $0.columns.3.z) }
                    armPoints.append(points.map { model.convert(position: $0, to: body) })
                    worldPoints.append(points.map { model.convert(position: $0, to: nil) })
                }
            }
            XCTAssertTrue((armPoints + worldPoints).flatMap { $0 }.allSatisfy {
                $0.x.isFinite && $0.y.isFinite && $0.z.isFinite
            })
            result[id] = Snapshot(detail: admitted[id] == nil ? "far" : "near", playerTransform: body.transform,
                rootTransform: root.transform, joints: activeJoints, arms: armPoints, worldArms: worldPoints,
                farArmsEnabled: farEnabled, skinModelEnabled: admitted[id]?.model.isEnabledInHierarchy ?? false,
                distance: ReplayGeometry.distance(pose.position, wearerPose.position))
        }
        return result
    }

    private func row(_ root: Entity, snapshots: [String: Snapshot], time: Double, wearer: String,
                     kind: String) -> [String: Any] {
        ["kind": kind, "time": time, "wearer": wearer, "nearIDs": nearIDs(root),
         "lowSkinCount": PitchSceneFactory.skinnedAthletesForTesting(in: root).values.filter { $0.detail == .lowDetail }.count,
         "targets": snapshots.mapValues(\.row)]
    }

    private func attach(_ rows: [[String: Any]], name: String) throws {
        let attachment = XCTAttachment(data: try JSONSerialization.data(withJSONObject: [
            "scope": "Actual rebound native recording and PitchSceneFactory POV admission/poses; no forced LOD",
            "limit": "Hierarchy visibility is not pixel visibility. Eye height 1.65 m and room -Z are numeric references, not observed headset gaze, FOV or occlusion. Wearer changes move the camera origin.",
            "rows": rows
        ], options: [.prettyPrinted, .sortedKeys]), uniformTypeIdentifier: "public.json")
        attachment.name = "ActualLODTransitions147-\(name)"
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    private func resetProviders() {
        ReplayArticulatedFarKitProvider.resetForTesting()
        ReplayArticulatedFarProvider.resetForTesting()
        ReplayFarAthleteHeadProvider.resetForTesting()
        ReplaySkinnedAthleteProvider.resetForTesting()
        ReplayImportedAthleteProvider.resetPrewarmForTesting()
        ReplayAthleteHeadProvider.resetForTesting()
        ReplayFarAthletePaletteProvider.resetForTesting()
        ReplayNativeBallPhysics.resetCacheForTesting()
    }
}
