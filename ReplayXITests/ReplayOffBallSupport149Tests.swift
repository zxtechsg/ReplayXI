import Foundation
import RealityKit
import simd
import XCTest
@testable import ReplayXI

/// Diagnostic only: a source support event and a low boot do not prove planted
/// contact. Fixed vertices may move while the boot rolls; no slip limit is set.
@MainActor
final class ReplayOffBallSupport149Tests: XCTestCase {
    private typealias Skin = ReplaySkinnedAthleteInstance
    private typealias Stage = Skin.DiagnosticStage
    private typealias Pose = ReplaySkinnedAthleteMotion.Pose
    private let targetIDs = ["arg-13", "arg-19", "fra-26"]
    private let times = (30...96).map { Double($0) / 120 }
    private final class Stages {
        var poses: [Stage: Pose] = [:]
        var retarget: Float = 0
    }
    private struct Vertex {
        struct Influence { let joint: Int; let point: SIMD4<Float>; let weight: Float }
        let id: String
        let influences: [Influence]
    }
    private struct Patch {
        let semantic: String
        let anatomical: String
        let ankle: Int
        let vertices: [Vertex]

        // Actual imported inverse binds, not the rounded animation rest inverse.
        // The same bottom-40-mm patch is retained for every frame and rewind.
        init(_ skin: Skin, semantic: String) throws {
            self.semantic = semantic
            let ankle = try XCTUnwrap(skin.motion.semanticJointIndices[semantic + "Ankle"])
            self.ankle = ankle
            let hips = try XCTUnwrap(skin.motion.semanticJointIndices["hips"])
            anatomical = skin.motion.restPose.modelSpaceTransforms[ankle].columns.3.x
                < skin.motion.restPose.modelSpaceTransforms[hips].columns.3.x ? "left" : "right"
            let contents = try XCTUnwrap(skin.model.model).mesh.contents
            let skeleton = try XCTUnwrap(contents.skeletons.first)
            XCTAssertEqual(skeleton.joints.map(\.name), skin.motion.jointNames)
            let allowed = Set(skin.motion.joints.indices.filter { index in
                var cursor = index
                while cursor >= 0 {
                    if cursor == ankle { return true }
                    cursor = skin.motion.joints[cursor].parentIndex
                }
                return false
            })
            var result: [Vertex] = []
            for (partIndex, part) in contents.models.flatMap({ Array($0.parts) }).enumerated() {
                let weights = try XCTUnwrap(part.jointInfluences).influences.elements
                guard part.positions.count > 0, weights.count.isMultiple(of: part.positions.count) else {
                    throw CocoaError(.fileReadCorruptFile)
                }
                let width = weights.count / part.positions.count
                guard (1...8).contains(width) else { throw CocoaError(.fileReadCorruptFile) }
                for (index, position) in part.positions.elements.enumerated() {
                    let slice = weights[(index * width)..<((index + 1) * width)].filter { $0.weight > 0 }
                    guard !slice.isEmpty, slice.allSatisfy({ allowed.contains($0.jointIndex) }) else { continue }
                    let influences = slice.map { weight in
                        Vertex.Influence(joint: weight.jointIndex,
                            point: skeleton.joints[weight.jointIndex].inverseBindPoseMatrix * SIMD4(position, 1),
                            weight: weight.weight)
                    }
                    let rest = influences.reduce(SIMD4<Float>.zero) {
                        $0 + skin.motion.restPose.modelSpaceTransforms[$1.joint] * $1.point * $1.weight
                    }
                    guard rest.y <= skin.motion.geometry.restMinY + 0.04 else { continue }
                    XCTAssertEqual(rest.w, 1, accuracy: 0.00001)
                    result.append(.init(id: "part\(partIndex):v\(index)", influences: influences))
                }
            }
            XCTAssertGreaterThan(result.count, 3)
            guard !result.isEmpty else { throw CocoaError(.fileReadCorruptFile) }
            vertices = result
        }

        func positions(_ pose: Pose, modelToPitch: simd_float4x4) -> [SIMD3<Float>] {
            vertices.map { vertex in
                let model = vertex.influences.reduce(SIMD4<Float>.zero) {
                    $0 + pose.modelSpaceTransforms[$1.joint] * $1.point * $1.weight
                }
                let point = modelToPitch * model
                return [point.x, point.y, point.z]
            }
        }
    }
    private struct Foot {
        let points: [SIMD3<Float>]
        let support: Bool
        let cycle: Int
        let pitch: Float
        let roll: Float
    }
    private struct Sample {
        let time: Double
        let root: SIMD3<Float>
        let feet: [Foot]
        let joints: [Transform]
        let localChain: [Transform]
        let runWeight: Float
    }

    override func tearDown() {
        PitchSceneFactory.fullSquadSkinsForTesting = false
        // Prune expired factory roots before releasing shared asset templates.
        if let scenario = FootballReferenceScenarios.all.first(where: { $0.id == "final-108-rebound-v2" }) {
            let empty = Entity(), marks = Entity(); marks.name = "marks-root"; empty.addChild(marks)
            update(empty, scenario, wearer: "arg-10", time: 0)
            for child in Array(empty.children) { child.removeFromParent() }
        }
        ReplayArticulatedFarKitProvider.resetForTesting()
        ReplayArticulatedFarProvider.resetForTesting()
        ReplayFarAthleteHeadProvider.resetForTesting()
        ReplaySkinnedAthleteProvider.resetForTesting()
        ReplayAthleteHeadProvider.resetForTesting()
        ReplayFarAthletePaletteProvider.resetForTesting()
        ReplayNativeBallPhysics.resetCacheForTesting()
        super.tearDown()
    }

    func testActualReboundNativeBootSupportEpisodesNearLowAndRewind149() async throws {
        try XCTSkipIf(ReplayImportedAthleteFeatureGate.isEnabled, "Default admitted assets only")
        PitchSceneFactory.fullSquadSkinsForTesting = false
        try ReplayArmLOD147Probe.prepare()
        try ReplayStrategyPitchProvider.prewarm()
        try ReplayStrategyBallProvider.prewarm()
        let context = try await ReplayArmLOD147Probe.context()
        let scenario = context.scenario, recording = context.recording
        try ReplayAthleteFactory.prewarm(for: scenario.players, lods: [.near, .far])
        let originalPlayers = scenario.players, originalBall = scenario.ball
        let positions = recording.samples.map(\.position), velocities = recording.samples.map(\.velocity)
        let orientations = recording.samples.map { $0.orientation.vector }
        XCTAssertEqual(recording.missedTouchCount, 0)
        for id in targetIDs { XCTAssertFalse(recording.touches.contains { $0.playerID == id }) }
        XCTAssertEqual(Set(try targetIDs.map { try XCTUnwrap(scenario.player(id: $0)).team }).count, 2)
        let sourceEvidence = try sourceSupportEvidence(try XCTUnwrap(ReplaySkinnedAthleteProvider.motion))
        var cases: [[String: Any]] = [], control: [Sample]?
        for wearer in ["arg-23", "arg-10"] {
            let result = try measure(scenario, recording: recording, wearer: wearer)
            cases.append(contentsOf: result.rows)
            if let prior = control {
                XCTAssertTrue(result.control.map(\.joints) == prior.map(\.joints), "FRA26 low poses must be view-origin independent")
                for (a, b) in zip(result.control, prior) {
                    XCTAssertTrue(a.localChain == b.localChain, "FRA26 model-to-actor local transforms differ at \(a.time)")
                    for (left, right) in zip(a.feet, b.feet) {
                        XCTAssertTrue(left.points == right.points, "FRA26 fixed boot points differ across POV roots at \(a.time)")
                    }
                }
            } else { control = result.control }
        }
        XCTAssertEqual(cases.count, 6)
        XCTAssertEqual(scenario.players, originalPlayers); XCTAssertEqual(scenario.ball, originalBall)
        XCTAssertEqual(recording.samples.map(\.position), positions)
        XCTAssertEqual(recording.samples.map(\.velocity), velocities)
        XCTAssertEqual(recording.samples.map { $0.orientation.vector }, orientations)
        XCTAssertFalse(PitchSceneFactory.fullSquadSkinsForTesting)
        let report: [String: Any] = ["scenario": scenario.id, "cases": cases, "sourceSupportEvidence": sourceEvidence,
            "framesPerCase": times.count, "sampleRateHz": 120, "nativeTouches": recording.touches.count,
            "motionSHA256": ReplaySkinnedAthleteProvider.motionSHA256,
            "nearAssetSHA256": ReplaySkinnedAthleteProvider.assetSHA256,
            "lowAssetSHA256": ReplaySkinnedAthleteProvider.lowAssetSHA256,
            "scope": "Actual Full squad POV factory poses. ARG13/19 near for wearer23, low for wearer10; FRA26 low in both is an away-team/view-origin control. No renderer or production correction.",
            "coordinates": "Pitch-root metres from bounded manual multiplication of the model-to-actor local transform chain plus the actor local transform. Actual hierarchy must reach that actor through skin.root; no world/relative transform conversion enters boot measurements. Old relative-API point deltas are reported separately. No camera-visible sliding is inferred.",
            "supportMeaning": "Frozen cycle138 raw-run backward-sweep phase markers, checked independently from the final pose. These are not force/contact events. The asset supplies no measured ground-contact labels.",
            "patchMeaning": "Fixed actual imported ankle/toe-chain vertices within 40 mm of the rest floor, actual inverse binds and weights. No per-frame lowest-point switching.",
            "limits": "Near-floor point motion includes rolling and toe articulation. A source support episode alone does not prove a planted boot or a defect. Partial run blends are reported, not treated as pure source support. Matched moving views are still required."]
        let attachment = XCTAttachment(data: try JSONSerialization.data(withJSONObject: report, options: [.sortedKeys]),
                                       uniformTypeIdentifier: "public.json")
        attachment.name = "ReplayXI-OffBallSupport149-NativeBootEpisodes.json"
        attachment.lifetime = .keepAlways; add(attachment)
    }

    private func measure(_ scenario: ReplayScenario, recording: ReplayNativeBallPhysics.Recording,
                         wearer: String) throws -> (rows: [[String: Any]], control: [Sample]) {
        let root = PitchSceneFactory.makeMatchRoot(for: scenario, nativeRecording: recording)
        defer { for child in Array(root.children) { child.removeFromParent() } }
        update(root, scenario, wearer: wearer, time: times[0])
        let skins = PitchSceneFactory.skinnedAthletesForTesting(in: root)
        XCTAssertEqual(skins.count, 21); XCTAssertNil(skins[wearer])
        let players = try XCTUnwrap(root.findEntity(named: "players-root"))
        XCTAssertEqual(players.transform, Transform())
        var patches: [String: [Patch]] = [:], stages: [String: Stages] = [:]
        var samples: [String: [Sample]] = [:], frameRows: [String: [[String: Any]]] = [:]
        var hierarchyNames: [String: [String]] = [:]
        for id in targetIDs {
            let skin = try XCTUnwrap(skins[id])
            XCTAssertEqual(skin.detail, id != "fra-26" && wearer == "arg-23" ? .near : .lowDetail)
            patches[id] = try ["left", "right"].map { try Patch(skin, semantic: $0) }
            let observed = Stages(); stages[id] = observed
            skin.poseStageObserverForTesting = { stage, pose in observed.poses[stage] = pose }
            skin.authoredPoseObserverForTesting = { _, _, influence in observed.retarget = influence }
        }
        defer {
            for id in targetIDs {
                skins[id]?.poseStageObserverForTesting = nil
                skins[id]?.authoredPoseObserverForTesting = nil
            }
        }
        for time in times {
            for stage in stages.values { stage.poses.removeAll(keepingCapacity: true); stage.retarget = 0 }
            update(root, scenario, wearer: wearer, time: time)
            let ball = try XCTUnwrap(root.findEntity(named: "ball")), expectedBall = recording.pose(at: time)
            XCTAssertEqual(ball.position, [expectedBall.position.x, max(expectedBall.height, 0.11), expectedBall.position.z])
            for id in targetIDs {
                let track = try XCTUnwrap(scenario.player(id: id)), skin = try XCTUnwrap(skins[id])
                XCTAssertTrue(PitchSceneFactory.skinnedAthletesForTesting(in: root)[id] === skin)
                let actor = try XCTUnwrap(players.children.first { $0.name == "player-\(id)" })
                XCTAssertTrue(actor.parent === players)
                let pose = track.presentationPose(at: time), locomotion = track.locomotion(at: time)
                XCTAssertEqual(actor.position, [pose.position.x, 0, pose.position.z])
                XCTAssertEqual(actor.scale, SIMD3<Float>(repeating: 1))
                let phase = track.gaitPhase(at: time), observed = try XCTUnwrap(stages[id])
                let runLinear = min(max((locomotion.effort * min(locomotion.speedMetresPerSecond / 2.4, 1) - 0.02) / 0.20, 0), 1)
                let runWeight = runLinear * runLinear * (3 - 2 * runLinear)
                let chain = try modelToPitch(skin, actor: actor)
                let transform = chain.matrix
                if let names = hierarchyNames[id] { XCTAssertEqual(chain.names, names) }
                else { hierarchyNames[id] = chain.names }
                // Comparison only. This API may internally cancel world-space
                // transforms; its output is not used by the fixed-point guard.
                let relativeAPI = actor.transform.matrix * skin.model.transformMatrix(relativeTo: actor)
                var rebuilt: [Stage: Pose] = [:]
                for stage in [Stage.source, .footballRetargetAndContact, .stationarySupport, .finalFloor] {
                    var value = try XCTUnwrap(observed.poses[stage])
                    skin.motion.rebuildModelSpaceTransforms(in: &value); rebuilt[stage] = value
                }
                let final = ReplayArmLOD147Probe.submitted(skin)
                XCTAssertEqual(final.translations, try XCTUnwrap(rebuilt[.finalFloor]).translations)
                XCTAssertEqual(final.rotations.map(\.vector), try XCTUnwrap(rebuilt[.finalFloor]).rotations.map(\.vector))
                XCTAssertGreaterThanOrEqual(skin.contactSurface.minimumY(in: final) - skin.motion.geometry.restMinY,
                                          skin.contactSurface.paddingMetres - 0.0001)
                var feet: [Foot] = [], footRows: [[String: Any]] = []
                var maximumRelativeAPIDelta: Float = 0
                for patch in try XCTUnwrap(patches[id]) {
                    let points = patch.positions(final, modelToPitch: transform)
                    let apiPoints = patch.positions(final, modelToPitch: relativeAPI)
                    maximumRelativeAPIDelta = max(maximumRelativeAPIDelta,
                        zip(points, apiPoints).map { simd_distance($0.0, $0.1) }.max() ?? 0)
                    let marker = sourceMarker(phase, semantic: patch.semantic)
                    let ankle = transform * final.modelSpaceTransforms[patch.ankle]
                    let forward4 = ankle * SIMD4(skin.motion.joints[patch.ankle].localForwardAxis, 0)
                    let right4 = ankle * SIMD4(skin.motion.joints[patch.ankle].localRightAxis, 0)
                    let forward = simd_normalize(SIMD3(forward4.x, forward4.y, forward4.z))
                    let right = simd_normalize(SIMD3(right4.x, right4.y, right4.z))
                    let pitch = asin(min(max(forward.y, -1), 1)) * 180 / .pi
                    let roll = asin(min(max(right.y, -1), 1)) * 180 / .pi
                    var stageRows: [String: Any] = [:]
                    for stage in [Stage.source, .footballRetargetAndContact, .stationarySupport, .finalFloor] {
                        let values = patch.positions(try XCTUnwrap(rebuilt[stage]), modelToPitch: transform)
                        stageRows[stage.rawValue] = ["centroid": vector(centroid(values)), "minimumY": values.map(\.y).min()!]
                    }
                    feet.append(.init(points: points, support: marker.active, cycle: marker.cycle, pitch: pitch, roll: roll))
                    footRows.append(["semantic": patch.semantic, "anatomical": patch.anatomical,
                        "sourceSupport": marker.active, "sourceCycle": marker.cycle,
                        "sourceMarkerPhase": marker.phase, "stages": stageRows,
                        "anklePitchDegrees": pitch, "ankleRollDegrees": roll,
                        "patchMinY": points.map(\.y).min()!, "patchMaxY": points.map(\.y).max()!])
                }
                samples[id, default: []].append(.init(time: time, root: actor.position, feet: feet,
                    joints: skin.model.jointTransforms, localChain: chain.transforms, runWeight: runWeight))
                frameRows[id, default: []].append(["time": time, "phase": phase,
                    "root": vector(actor.position), "speed": locomotion.speedMetresPerSecond,
                    "sourceRunWeight": runWeight, "actualRetargetInfluence": observed.retarget,
                    "relativeAPIvsLocalMaximumPointDeltaMetres": maximumRelativeAPIDelta, "feet": footRows])
            }
        }
        for (index, time) in times.enumerated().reversed() {
            update(root, scenario, wearer: wearer, time: time)
            for id in targetIDs {
                let skin = try XCTUnwrap(skins[id]), saved = try XCTUnwrap(samples[id])[index]
                XCTAssertTrue(skin.model.jointTransforms == saved.joints, "Exact reverse \(wearer)/\(id)/\(time)")
                let final = ReplayArmLOD147Probe.submitted(skin)
                let actor = try XCTUnwrap(players.children.first { $0.name == "player-\(id)" })
                let chain = try modelToPitch(skin, actor: actor)
                XCTAssertTrue(chain.transforms == saved.localChain, "Exact local chain reverse \(wearer)/\(id)/\(time)")
                for (foot, patch) in try XCTUnwrap(patches[id]).enumerated() {
                    XCTAssertTrue(patch.positions(final, modelToPitch: chain.matrix)
                        == saved.feet[foot].points, "Exact boot reverse \(wearer)/\(id)/\(time)")
                }
            }
        }
        let rows = try targetIDs.map { id -> [String: Any] in
            let skin = try XCTUnwrap(skins[id]), saved = try XCTUnwrap(samples[id]), patches = try XCTUnwrap(patches[id])
            let episodes = supportEpisodes(saved, patches: patches)
            if id != "fra-26" { XCTAssertFalse(episodes.isEmpty, "Target window must contain a source marker") }
            return ["player": id, "team": try XCTUnwrap(scenario.player(id: id)).team.rawValue,
                "wearer": wearer, "detail": skin.detail == .near ? "near" : "lowDetail",
                "modelToActorLocalChain": try XCTUnwrap(hierarchyNames[id]),
                "patches": patches.map { ["semantic": $0.semantic, "anatomical": $0.anatomical,
                                          "vertices": $0.vertices.map(\.id)] },
                "frames": try XCTUnwrap(frameRows[id]), "episodes": episodes,
                "exactRewind": true, "contactActor": false]
        }
        return (rows, try XCTUnwrap(samples["fra-26"]))
    }

    private func modelToPitch(_ skin: Skin, actor: Entity) throws
        -> (matrix: simd_float4x4, names: [String], transforms: [Transform]) {
        XCTAssertTrue(skin.root.parent === actor, "The measured skin must belong to this actual factory actor")
        var cursor: Entity? = skin.model
        var matrix = matrix_identity_float4x4
        var names: [String] = [], transforms: [Transform] = []
        var visited = Set<ObjectIdentifier>(), foundSkinRoot = false
        while let entity = cursor, entity !== actor {
            guard names.count < 16, visited.insert(ObjectIdentifier(entity)).inserted else {
                XCTFail("Model-to-actor chain exceeded its bound or repeated an entity")
                throw CocoaError(.fileReadCorruptFile)
            }
            let local = entity.transform
            matrix = local.matrix * matrix
            names.append(entity.name); transforms.append(local)
            if entity === skin.root { foundSkinRoot = true }
            cursor = entity.parent
        }
        guard cursor === actor, foundSkinRoot else {
            XCTFail("Actual model hierarchy did not reach actor through skin.root: \(names)")
            throw CocoaError(.fileReadCorruptFile)
        }
        let actorTransform = actor.transform
        names.append(actor.name); transforms.append(actorTransform)
        return (actorTransform.matrix * matrix, names, transforms)
    }

    private func supportEpisodes(_ samples: [Sample], patches: [Patch]) -> [[String: Any]] {
        var rows: [[String: Any]] = []
        for (foot, patch) in patches.enumerated() {
            var first: Int?
            func finish(_ end: Int) {
                guard let start = first, end > start else { return }
                let indices = Array(start...end)
                var summaries: [[String: Any]] = []
                for band: Float in [0.01, 0.02, 0.04] {
                    var runs: [(String, Int, Int, Float, Float)] = []
                    for vertex in patch.vertices.indices {
                        var begin: Int?
                        func flush(_ last: Int) {
                            guard let begin, last > begin else { return }
                            let path = ((begin + 1)...last).reduce(Float(0)) { total, index in
                                total + xz(samples[index - 1].feet[foot].points[vertex], samples[index].feet[foot].points[vertex])
                            }
                            runs.append((patch.vertices[vertex].id, begin, last, path,
                                xz(samples[begin].feet[foot].points[vertex], samples[last].feet[foot].points[vertex])))
                        }
                        for index in indices {
                            if abs(samples[index].feet[foot].points[vertex].y) <= band {
                                if begin == nil { begin = index }
                            } else { flush(index - 1); begin = nil }
                        }
                        flush(end)
                    }
                    let ordered = runs.sorted { $0.3 > $1.3 }
                    let paths = runs.map { $0.3 }.sorted()
                    summaries.append(["bandMetres": band, "fixedVertexSubepisodes": runs.count,
                        "pathMinMedianMaxXZ": paths.isEmpty ? [] : [paths.first!, paths[paths.count / 2], paths.last!],
                        "subepisodesAtLeast100ms": runs.filter { samples[$0.2].time - samples[$0.1].time >= 0.1 }.count,
                        "largestThree": ordered.prefix(3).map { item in
                            ["vertex": item.0, "start": samples[item.1].time, "end": samples[item.2].time,
                             "pathXZ": item.3, "netXZ": item.4,
                             "startPoint": vector(samples[item.1].feet[foot].points[patch.vertices.firstIndex { $0.id == item.0 }!]),
                             "endPoint": vector(samples[item.2].feet[foot].points[patch.vertices.firstIndex { $0.id == item.0 }!]),
                             "rootPathXZ": ((item.1 + 1)...item.2).reduce(Float(0)) {
                                 $0 + xz(samples[$1 - 1].root, samples[$1].root)
                             }] as [String: Any]
                        }])
                }
                rows.append(["semantic": patch.semantic, "anatomical": patch.anatomical,
                    "cycle": samples[start].feet[foot].cycle, "start": samples[start].time, "end": samples[end].time,
                    "sampledDuration": samples[end].time - samples[start].time, "frames": indices.count,
                    "clippedByWindow": start == 0 || end == samples.count - 1,
                    "sourceRunWeightMin": indices.map { samples[$0].runWeight }.min()!,
                    "patchCentroidPathXZ": ((start + 1)...end).reduce(Float(0)) {
                        $0 + xz(centroid(samples[$1 - 1].feet[foot].points), centroid(samples[$1].feet[foot].points))
                    },
                    "patchMinimumY": indices.flatMap { samples[$0].feet[foot].points.map(\.y) }.min()!,
                    "pitchRangeDegrees": [indices.map { samples[$0].feet[foot].pitch }.min()!, indices.map { samples[$0].feet[foot].pitch }.max()!],
                    "rollRangeDegrees": [indices.map { samples[$0].feet[foot].roll }.min()!, indices.map { samples[$0].feet[foot].roll }.max()!],
                    "fixedVertexNearFloorSubepisodes": summaries])
            }
            for index in samples.indices {
                let current = samples[index].feet[foot]
                if current.support {
                    if let start = first, samples[start].feet[foot].cycle != current.cycle { finish(index - 1); first = nil }
                    if first == nil { first = index }
                } else { finish(index - 1); first = nil }
            }
            finish(samples.count - 1)
        }
        return rows
    }

    private func sourceSupportEvidence(_ motion: ReplaySkinnedAthleteMotion) throws -> [String: Any] {
        var rows: [[String: Any]] = []
        for semantic in ["right", "left"] {
            let phase: Float = 2.7 + (semantic == "left" ? .pi : 0)
            let foot = try XCTUnwrap(motion.footContacts[semantic])
            func point(_ phase: Float) -> SIMD3<Float> {
                var pose = motion.makePoseBuffer()
                motion.sample(time: 0, locomotionEffort: 1, gaitPhase: phase, into: &pose)
                let p = pose.modelSpaceTransforms[foot.footJointIndex] * SIMD4(foot.solePoint, 1)
                return [p.x, p.y - motion.geometry.restMinY, p.z]
            }
            let p = point(phase), derivative = (point(phase + 0.001) - point(phase - 0.001)) / 0.002
            XCTAssertLessThan(p.y, 0.035); XCTAssertLessThan(derivative.z, -0.3)
            rows.append(["semantic": semantic, "phase": phase, "sole": vector(p), "derivativePerRadian": vector(derivative)])
        }
        return ["markerPhaseLower": 2.30, "markerPhaseUpper": 3.40, "leftSemanticPhaseOffset": Double.pi,
            "provenance": "Independent raw-run phase curve and mid-support assertions in ReplayCutRunPhase138Tests; unchanged marker, never derived from final height or procedural stance.",
            "sourceCommit": motion.sourceCommit, "midSupportChecks": rows]
    }

    private func sourceMarker(_ phase: Float, semantic: String) -> (active: Bool, cycle: Int, phase: Float) {
        let shifted = phase - (semantic == "left" ? .pi : 0), cycle = floor(shifted / (2 * .pi))
        let wrapped = shifted - cycle * 2 * .pi
        return (wrapped >= 2.30 && wrapped <= 3.40, Int(cycle), wrapped)
    }
    private func update(_ root: Entity, _ scenario: ReplayScenario, wearer: String, time: Double) {
        PitchSceneFactory.update(root: root, scenario: scenario, time: time, viewMode: .firstPerson,
            perspectiveID: wearer, marks: scenario.coachMarks, showsLaneLens: false, isDrawing: false,
            positionalOriginTransform: nil, playerDetail: .fullSquad)
    }
    private func vector(_ p: SIMD3<Float>) -> [Float] { [p.x, p.y, p.z] }
    private func centroid(_ points: [SIMD3<Float>]) -> SIMD3<Float> { points.reduce(.zero, +) / Float(points.count) }
    private func xz(_ a: SIMD3<Float>, _ b: SIMD3<Float>) -> Float { hypot(a.x - b.x, a.z - b.z) }
}
