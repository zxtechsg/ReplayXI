import RealityKit
import XCTest
@testable import ReplayXI

/// Measurement only. Near-turf motion is not automatically invalid sliding:
/// a boot can roll, and each reported episode follows one fixed mesh vertex.
@MainActor
final class ReplayRunContactDiagnosticsTests: XCTestCase {
    private struct Window {
        let name: String
        let playerID: String
        let start: Double
    }

    private let windows = [
        Window(name: "overlap-jog", playerID: "navy-rb", start: 6.85),
        Window(name: "overlap-run", playerID: "navy-rb", start: 11.6),
        Window(name: "recovery-run", playerID: "red-lw", start: 13.55),
        Window(name: "standing", playerID: "red-gk", start: 10),
    ]

    private struct ContactDocument: Decodable {
        struct Vertex: Decodable {
            let id: String
            let position: [Float]
            let joints: [Int]
            let weights: [Float]
        }
        let vertices: [Vertex]
    }

    private struct WeightedPoint {
        let id: String
        let side: String
        let bindings: [(joint: Int, local: SIMD4<Float>, weight: Float)]
    }

    private struct MeshFoot {
        let side: String
        let model: ModelEntity
        let points: [(id: String, local: SIMD3<Float>)]
    }

    private struct Procedural {
        let lod: ReplayAthleteLOD
        let rig: ReplayAthleteInstance
        let feet: [MeshFoot]
    }

    private struct Context {
        let stage: Entity
        let actor: Entity
        let skin: ReplaySkinnedAthleteInstance
        let weightedPoints: [WeightedPoint]
        let procedural: [Procedural]
    }

    private struct FootSample {
        let renderer: String
        let side: String
        let ids: [String]
        let positions: [SIMD3<Float>]
    }

    private struct Sample {
        let time: Double
        let root: SIMD3<Float>
        let facing: Float
        let speed: Float
        let turn: Float
        let phase: Float
        let actionInfluence: Float
        let authoredInfluence: Float
        let travelHeading: Float?
        let feet: [FootSample]

        var sourceRunEligible: Bool {
            speed >= 2.25 && abs(turn) <= 38 && actionInfluence == 0 && authoredInfluence == 0
        }
    }

    override func tearDown() {
        ReplaySkinnedAthleteProvider.resetForTesting()
        ReplayAthleteHeadProvider.resetForTesting()
        super.tearDown()
    }

    private func array(_ point: SIMD3<Float>) -> [Float] { [point.x, point.y, point.z] }
    private func xzDistance(_ a: SIMD3<Float>, _ b: SIMD3<Float>) -> Float { hypot(b.x - a.x, b.z - a.z) }

    private func makeContext(for player: PlayerTrack) throws -> Context {
        let skin = try ReplaySkinnedAthleteProvider.make(for: player)
        let url = try XCTUnwrap(Bundle.main.url(forResource: "ReplayXIRocketboxContactSurface", withExtension: "json",
                                               subdirectory: "Resources/Players")
            ?? Bundle.main.url(forResource: "ReplayXIRocketboxContactSurface", withExtension: "json"))
        let document = try JSONDecoder().decode(ContactDocument.self, from: Data(contentsOf: url))
        let left = try XCTUnwrap(skin.motion.footContacts["left"])
        let right = try XCTUnwrap(skin.motion.footContacts["right"])
        let inverses = skin.motion.restPose.modelSpaceTransforms.map(\.inverse)
        // This is a fixed rest-mesh patch, not a per-frame lowest-vertex pick.
        let points = document.vertices.filter { $0.position[1] <= skin.motion.geometry.restMinY + 0.04 }.map { vertex in
            let position = SIMD3(vertex.position[0], vertex.position[1], vertex.position[2])
            let side = simd_distance(position, left.restSoleWorld) < simd_distance(position, right.restSoleWorld)
                ? "left" : "right"
            let total = vertex.weights.reduce(0, +)
            return WeightedPoint(id: vertex.id, side: side, bindings: zip(vertex.joints, vertex.weights).map {
                (joint: $0.0, local: inverses[$0.0] * SIMD4(position, 1), weight: $0.1 / total)
            })
        }
        XCTAssertEqual(points.count, 28, "The existing verified bottom-40-mm skin patch is the measurement source")
        let stage = Entity()
        let actor = Entity()
        stage.addChild(actor)
        actor.addChild(skin.root)
        let appearance = ReplayAthleteConfiguration(player: player).appearance
        XCTAssertEqual(skin.root.scale, SIMD3(appearance.widthScale, appearance.heightScale, 1))
        let procedural = try ReplayAthleteLOD.allCases.map { lod -> Procedural in
            let rig = try ReplayAthleteFactory.make(for: player, lod: lod)
            actor.addChild(rig.root)
            XCTAssertEqual(rig.root.scale, skin.root.scale)
            let feet = try ["left", "right"].map { side -> MeshFoot in
                let suffix = lod == .far ? "leg" : "boot"
                let model = try XCTUnwrap(rig.root.findEntity(named: "\(side)-\(suffix)") as? ModelEntity)
                let component = try XCTUnwrap(model.model)
                let positions = component.mesh.contents.models.flatMap { model in
                    model.parts.flatMap { Array($0.positions.elements) }
                }
                let minimum = try XCTUnwrap(positions.map(\.y).min())
                let patch = positions.enumerated().filter { $0.element.y <= minimum + 0.04 }
                    .map { (id: "\(side):\($0.offset)", local: $0.element) }
                XCTAssertFalse(patch.isEmpty)
                return MeshFoot(side: side, model: model, points: patch)
            }
            return Procedural(lod: lod, rig: rig, feet: feet)
        }
        return Context(stage: stage, actor: actor, skin: skin, weightedPoints: points, procedural: procedural)
    }

    private func sample(_ context: Context, player: PlayerTrack, scenario: ReplayScenario, time: Double) -> Sample {
        let presentation = player.presentationPose(at: time)
        let root = SIMD3<Float>(presentation.position.x, 0, presentation.position.z)
        context.actor.position = root
        context.actor.orientation = simd_quatf(angle: presentation.facingDegrees * .pi / 180, axis: [0, 1, 0])
        // Match-scale, non-selected first-person neighbours use focus scale 1.
        // Appearance remains inside each real renderer root, not approximated.
        context.actor.scale = .one
        let locomotion = player.locomotion(at: time)
        let phase = player.gaitPhase(at: time)
        let ball = scenario.ball.pose(at: time)
        let target = SIMD3<Float>(ball.position.x, ball.height, ball.position.z)
        let action = ReplayAthleteMotion.ballActionPose(for: player, ballTrack: scenario.ball, at: time)
        XCTAssertTrue(context.skin.update(at: time, track: player, locomotion: locomotion,
                                          lookTarget: target, ballAction: action))
        let authored = ReplayAthleteMotion.locomotionPose(for: player, at: time, locomotion: locomotion,
                                                        gaitPhase: phase, lookTargetWorldPosition: target,
                                                        ballAction: action)
        var feet: [FootSample] = []
        for side in ["left", "right"] {
            let points = context.weightedPoints.filter { $0.side == side }
            let world = points.map { point -> SIMD3<Float> in
                let skinned = point.bindings.reduce(SIMD4<Float>.zero) { result, binding in
                    result + (context.skin.pose.modelSpaceTransforms[binding.joint] * binding.local) * binding.weight
                }
                return context.skin.model.convert(position: SIMD3(skinned.x, skinned.y, skinned.z), to: context.stage)
            }
            feet.append(FootSample(renderer: "skin", side: side, ids: points.map(\.id), positions: world))
        }
        for item in context.procedural {
            ReplayAthleteMotion.apply(authored, to: item.rig.joints)
            for foot in item.feet {
                feet.append(FootSample(renderer: item.lod.rawValue, side: foot.side, ids: foot.points.map(\.id),
                                       positions: foot.points.map { foot.model.convert(position: $0.local, to: context.stage) }))
            }
        }
        for foot in feet {
            XCTAssertTrue(foot.positions.allSatisfy { $0.x.isFinite && $0.y.isFinite && $0.z.isFinite })
        }
        let before = player.presentationPose(at: time - 0.01).position
        let after = player.presentationPose(at: time + 0.01).position
        let delta = SIMD2(after.x - before.x, after.z - before.z)
        let heading: Float? = simd_length(delta) > 0.000001 ? atan2(delta.x, delta.y) * 180 / .pi : nil
        return Sample(time: time, root: root, facing: presentation.facingDegrees,
                      speed: locomotion.speedMetresPerSecond, turn: locomotion.turnRateDegreesPerSecond, phase: phase,
                      actionInfluence: action?.influence ?? 0,
                      authoredInfluence: ReplaySkinnedAthleteFootballPose.influence(locomotion: locomotion, ballAction: action),
                      travelHeading: heading, feet: feet)
    }

    private func episodes(in samples: [Sample], window: String) -> [[String: Any]] {
        guard let first = samples.first else { return [] }
        var output: [[String: Any]] = []
        for footIndex in first.feet.indices {
            let foot = first.feet[footIndex]
            for vertex in foot.ids.indices {
                for band: Float in [0.010, 0.020, 0.040] {
                    var start: Int?
                    func finish(_ end: Int) {
                        guard let begin = start, end > begin else { return }
                        let initial = samples[begin].feet[footIndex].positions[vertex]
                        let final = samples[end].feet[footIndex].positions[vertex]
                        var footTravel: Float = 0
                        var rootTravel: Float = 0
                        for index in (begin + 1)...end {
                            footTravel += xzDistance(samples[index - 1].feet[footIndex].positions[vertex],
                                                     samples[index].feet[footIndex].positions[vertex])
                            rootTravel += xzDistance(samples[index - 1].root, samples[index].root)
                        }
                        output.append([
                            "window": window, "renderer": foot.renderer, "side": foot.side, "vertex": foot.ids[vertex],
                            "bandMetres": band, "start": samples[begin].time, "end": samples[end].time,
                            "duration": samples[end].time - samples[begin].time, "pairedIntervals": end - begin,
                            "footTravelXZ": footTravel, "footNetXZ": xzDistance(initial, final),
                            "rootTravelXZ": rootTravel, "rootNetXZ": xzDistance(samples[begin].root, samples[end].root),
                            "footRootTravelRatio": rootTravel > 0.000001 ? footTravel / rootTravel as Any : NSNull(),
                            "minimumClearance": samples[begin...end].map { $0.feet[footIndex].positions[vertex].y }.min()!,
                            "maximumClearance": samples[begin...end].map { $0.feet[footIndex].positions[vertex].y }.max()!,
                            "allSourceRunEligible": samples[begin...end].allSatisfy(\.sourceRunEligible),
                            "startFoot": array(initial), "endFoot": array(final),
                        ])
                    }
                    for index in samples.indices {
                        // Each paired interval uses the same vertex and both
                        // endpoints in the band; no switching to a new low point.
                        if abs(samples[index].feet[footIndex].positions[vertex].y) <= band {
                            if start == nil { start = index }
                        } else if start != nil {
                            finish(index - 1)
                            start = nil
                        }
                    }
                    if start != nil { finish(samples.count - 1) }
                }
            }
        }
        return output
    }

    func testExportFixedSoleVertexMotionDuringFourBoundedDemoWindows() throws {
        try ReplaySkinnedAthleteProvider.prewarm()
        let scenario = try XCTUnwrap(DemoScenarios.scenario(for: .squadReplay))
        var reports: [[String: Any]] = []
        var contactEpisodes: [[String: Any]] = []
        for window in windows {
            let player = try XCTUnwrap(scenario.player(id: window.playerID))
            let context = try makeContext(for: player)
            let samples = (0...96).map { sample(context, player: player, scenario: scenario,
                                               time: window.start + Double($0) / 120) }
            for row in samples {
                reports.append([
                    "window": window.name, "playerID": player.id, "time": row.time,
                    "root": array(row.root), "facing": row.facing, "speed": row.speed,
                    "turnRate": row.turn, "gaitPhase": row.phase,
                    "travelHeading": row.travelHeading.map { $0 as Any } ?? NSNull(),
                    "actionInfluence": row.actionInfluence, "authoredInfluence": row.authoredInfluence,
                    "sourceRunEligible": row.sourceRunEligible, "appearanceScale": array(context.skin.root.scale),
                    "feet": row.feet.map { ["renderer": $0.renderer, "side": $0.side,
                                             "ids": $0.ids, "positions": $0.positions.map(array)] as [String: Any] },
                ])
            }
            contactEpisodes.append(contentsOf: episodes(in: samples, window: window.name))
        }
        XCTAssertEqual(reports.count, 388)
        let data = try JSONSerialization.data(withJSONObject: ["report": reports, "episodes": contactEpisodes],
                                              options: [.sortedKeys])
        let attachment = XCTAttachment(data: data, uniformTypeIdentifier: "public.json")
        attachment.name = "ReplayXI-RunContact86-Native.json"
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    func testSoleSamplesRepeatOnReverseSeekAndNearMidBootsKeepTheSamePose() throws {
        try ReplaySkinnedAthleteProvider.prewarm()
        let scenario = try XCTUnwrap(DemoScenarios.scenario(for: .squadReplay))
        for window in windows {
            let player = try XCTUnwrap(scenario.player(id: window.playerID))
            let context = try makeContext(for: player)
            let times = [window.start, window.start + 0.233333333333, window.start + 0.8]
            let forward = times.map { sample(context, player: player, scenario: scenario, time: $0) }
            for index in times.indices.reversed() {
                let repeated = sample(context, player: player, scenario: scenario, time: times[index])
                XCTAssertEqual(repeated.root, forward[index].root)
                XCTAssertEqual(repeated.phase, forward[index].phase)
                for (actual, expected) in zip(repeated.feet, forward[index].feet) {
                    XCTAssertEqual(actual.ids, expected.ids)
                    XCTAssertEqual(actual.positions, expected.positions, "Fixed native contacts must not depend on seek history")
                }
                for side in ["left", "right"] {
                    let near = try XCTUnwrap(repeated.feet.first { $0.renderer == "near" && $0.side == side })
                    let mid = try XCTUnwrap(repeated.feet.first { $0.renderer == "mid" && $0.side == side })
                    XCTAssertEqual(near.ids, mid.ids)
                    XCTAssertEqual(near.positions, mid.positions, "These LODs use the same articulated boot mesh and pose")
                }
            }
        }
    }
}
