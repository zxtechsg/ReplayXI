import Dispatch
import Foundation
import RealityKit
import XCTest
import simd
@testable import ReplayXI

/// Test-only attribution. No contact coverage, pose cache or shipping math changes.
@MainActor
final class ReplaySkinFloorStageBenchmarkTests: XCTestCase {
    private struct Input {
        let time: Double
        let locomotion: PlayerLocomotionSample
        let look: SIMD3<Float>
        let action: ReplayAthleteBallActionPose?
        let presentation: PlayerPose
    }

    private struct Frame {
        let inputs: [Input]
        let preFloor: [ReplaySkinnedAthleteMotion.Pose]
        let minima: [Float]
        let finalJoints: [[Transform]]
        let finalFront: [Transform]
        let finalBack: [Transform]
    }

    private final class Capture {
        var poses: [ReplaySkinnedAthleteMotion.Pose?]
        init(count: Int) { poses = Array(repeating: nil, count: count) }
    }

    private struct Batch: Codable {
        let pair: Int
        let order: String
        let floorNanoseconds: UInt64
        let wholeUpdateNanoseconds: UInt64
    }

    private struct Phase: Codable {
        let group: String
        let phase: String
        let nearInstances: Int
        let lowInstances: Int
        let verticesPerGroupScan: Int
        let influencesPerGroupScan: Int
        let groupUpdatesPerBatch: Int
        let batches: [Batch]
        let medianFloorNanoseconds: Double
        let medianWholeUpdateNanoseconds: Double
        let medianPairedFloorToWholeRatio: Double
    }

    private struct Report: Codable {
        let qualification: String
        let phases: [Phase]
    }

    override func setUp() {
        super.setUp()
        ReplaySkinnedAthleteProvider.resetForTesting()
        ReplayAthleteHeadProvider.resetForTesting()
    }

    override func tearDown() {
        ReplaySkinnedAthleteProvider.resetForTesting()
        ReplayAthleteHeadProvider.resetForTesting()
        super.tearDown()
    }

    func testRecordsFloorScanAgainstWholeNativeUpdateInAlternatingBoundedBatches() throws {
        let scenario = try prepare()
        let roster = try ["navy-rw", "navy-rb", "red-lw", "red-lb"].map {
            try XCTUnwrap(scenario.player(id: $0))
        }
        let forward = (0..<32).map { 10.5 + Double($0) * 0.25 }
        let times = forward + forward.reversed()
        let configurations: [(String, [ReplaySkinnedAthleteProvider.Detail])] = [
            ("one_near", [.near]), ("one_low", [.lowDetail]),
            ("one_near_three_low", [.near, .lowDetail, .lowDetail, .lowDetail])
        ]
        var reports: [Phase] = []
        for (name, details) in configurations {
            let players = Array(roster.prefix(details.count))
            let skins = try details.indices.map {
                try ReplaySkinnedAthleteProvider.make(for: players[$0], detail: details[$0])
            }
            // Capture and oracle work precede timing. The observer is removed
            // before warmup; retained snapshots cannot add observer/COW costs
            // to the measured whole-update loop after its first warmup update.
            let moving = try capture(skins: skins, players: players, scenario: scenario, times: times)
            let pausedSample = try XCTUnwrap(capture(skins: skins, players: players,
                                                    scenario: scenario, times: [13.6]).first)
            let phases: [(String, [Frame])] = [
                ("paused", Array(repeating: pausedSample, count: 64)),
                ("forward_reverse", moving)
            ]
            for (phase, frames) in phases {
                XCTAssertEqual(frames.count, 64)
                let requests = 128
                let expectedSum = expectedChecksum(frames: frames, requests: requests)
                let warmFloor = measureFloor(skins, frames: frames, requests: 64)
                let warmWhole = measureWhole(skins, players: players, frames: frames, requests: 64)
                XCTAssertTrue(warmFloor.checksum.isFinite)
                XCTAssertTrue(warmWhole.supported)
                var batches: [Batch] = []
                for pair in 0..<8 {
                    let floorFirst = pair.isMultiple(of: 2)
                    let floor: (nanoseconds: UInt64, checksum: Double)
                    let whole: (nanoseconds: UInt64, supported: Bool)
                    if floorFirst {
                        floor = measureFloor(skins, frames: frames, requests: requests)
                        whole = measureWhole(skins, players: players, frames: frames, requests: requests)
                    } else {
                        whole = measureWhole(skins, players: players, frames: frames, requests: requests)
                        floor = measureFloor(skins, frames: frames, requests: requests)
                    }
                    XCTAssertEqual(floor.checksum, expectedSum, "Every scan result must be consumed")
                    XCTAssertTrue(whole.supported)
                    assertFinalState(skins, frame: frames[63])
                    batches.append(Batch(pair: pair, order: floorFirst ? "floor_then_whole" : "whole_then_floor",
                                         floorNanoseconds: floor.nanoseconds,
                                         wholeUpdateNanoseconds: whole.nanoseconds))
                }
                reports.append(Phase(
                    group: name, phase: phase,
                    nearInstances: details.filter { $0 == .near }.count,
                    lowInstances: details.filter { $0 == .lowDetail }.count,
                    verticesPerGroupScan: skins.reduce(0) { $0 + $1.contactSurface.vertexCount },
                    influencesPerGroupScan: skins.reduce(0) { $0 + $1.contactSurface.influenceCount },
                    groupUpdatesPerBatch: requests, batches: batches,
                    medianFloorNanoseconds: median(batches.map { Double($0.floorNanoseconds) }),
                    medianWholeUpdateNanoseconds: median(batches.map { Double($0.wholeUpdateNanoseconds) }),
                    medianPairedFloorToWholeRatio: median(batches.map {
                        Double($0.floorNanoseconds) / max(Double($0.wholeUpdateNanoseconds), 1)
                    })
                ))
            }
        }
        let report = Report(
            qualification: "Native test-process CPU only; record compiler flags with this receipt. Eight alternating-order pairs of 128 group requests, after warmup. Floor-only scans actual captured cervical/pre-floor poses; whole Instance.update includes sampling/retargeting/contacts and native joint writes, with observers nil. Identical authored replay inputs use supplied locomotion/presentation and inferred ball-action cues, not a native-ball bake. Input preparation, capture, oracles, assertions, assets, scene traversal, rendering/GPU/compositor and headset work are excluded. Near coverage is all 339 admitted contact probes (not all 5012 mesh vertices); low coverage is all 1707 actual mesh vertices. Exact independent contact-document minima and separate public imported-low-mesh minima are checked. Ratios are isolated-stage attribution, not a promised removable cost, FPS result, or timing pass/fail threshold.",
            phases: reports
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let attachment = XCTAttachment(data: try encoder.encode(report), uniformTypeIdentifier: "public.json")
        attachment.name = "ReplayXI-SkinFloorStageBenchmark.json"
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    func testCompleteContactOraclesRetainAffineMotionAndFloorLift() throws {
        let scenario = try prepare()
        let player = try XCTUnwrap(scenario.player(id: "navy-rw"))
        for detail in [ReplaySkinnedAthleteProvider.Detail.near, .lowDetail] {
            let skin = try ReplaySkinnedAthleteProvider.make(for: player, detail: detail)
            let oracle = try ContactOracle(skin: skin)
            let native = detail == .lowDetail ? try NativeLowOracle(skin: skin) : nil
            let samples = try capture(skins: [skin], players: [player], scenario: scenario,
                                      times: [11, 12.5, 13.6, 14.15, 17.5])
            for sample in samples {
                for y: Float in [-0.35, 0, 0.8] {
                    var pose = sample.preFloor[0]
                    let transform = Transform(scale: [0.9, 1.1, 1.05],
                        rotation: simd_quatf(angle: y, axis: simd_normalize(SIMD3<Float>(0.7, 0, 0.4))),
                        translation: [0.2, y, -0.3]).matrix
                    for index in pose.modelSpaceTransforms.indices {
                        pose.modelSpaceTransforms[index] = transform * pose.modelSpaceTransforms[index]
                    }
                    let expected = oracle.minimumY(in: pose)
                    XCTAssertEqual(skin.contactSurface.minimumY(in: pose), expected)
                    if let native {
                        XCTAssertEqual(expected, native.minimumY(in: pose), accuracy: 0.000_01)
                    }
                }
                var corrected = sample.preFloor[0]
                let before = corrected
                let floor = skin.motion.geometry.restMinY + skin.contactSurface.paddingMetres
                let expectedLift = max(floor - oracle.minimumY(in: before), 0)
                XCTAssertEqual(skin.contactSurface.raiseAboveFloor(floor, in: &corrected), expectedLift)
                XCTAssertEqual(corrected.rotations.map(\.vector), before.rotations.map(\.vector))
                XCTAssertEqual(corrected.scales, before.scales)
                XCTAssertGreaterThanOrEqual(oracle.minimumY(in: corrected), floor - 0.000_001)
            }
        }
    }

    func testMalformedPoseAndNonfiniteFloorFailWithoutMutationForBothDetails() throws {
        let scenario = try prepare()
        let player = try XCTUnwrap(scenario.player(id: "navy-rw"))
        for detail in [ReplaySkinnedAthleteProvider.Detail.near, .lowDetail] {
            let skin = try ReplaySkinnedAthleteProvider.make(for: player, detail: detail)
            let captured = try XCTUnwrap(capture(skins: [skin], players: [player],
                                                 scenario: scenario, times: [13.6]).first)
            let valid = captured.preFloor[0]
            var short = valid
            short.modelSpaceTransforms.removeLast()
            var empty = valid
            empty.modelSpaceTransforms.removeAll()
            var invalids = [short, empty]
            for bad: Float in [.nan, .infinity, -.infinity] {
                var pose = valid
                for index in pose.modelSpaceTransforms.indices { pose.modelSpaceTransforms[index].columns.3.y = bad }
                invalids.append(pose)
            }
            for var pose in invalids {
                let before = bits(pose)
                XCTAssertTrue(skin.contactSurface.minimumY(in: pose).isNaN)
                XCTAssertEqual(skin.contactSurface.raiseAboveFloor(0.1, in: &pose), 0)
                XCTAssertEqual(bits(pose), before)
            }
            for floor: Float in [.nan, .infinity, -.infinity] {
                var pose = valid
                let before = bits(pose)
                XCTAssertEqual(skin.contactSurface.raiseAboveFloor(floor, in: &pose), 0)
                XCTAssertEqual(bits(pose), before)
            }
            var shortTranslations = valid
            shortTranslations.translations.removeLast()
            let before = bits(shortTranslations)
            XCTAssertEqual(skin.contactSurface.raiseAboveFloor(0.1, in: &shortTranslations), 0)
            XCTAssertEqual(bits(shortTranslations), before)
        }
    }

    private func prepare() throws -> ReplayScenario {
        try ReplaySkinnedAthleteProvider.prewarm()
        try ReplaySkinnedAthleteProvider.prewarmLowDetail()
        return try XCTUnwrap(DemoScenarios.scenario(for: .squadReplay))
    }

    private func capture(skins: [ReplaySkinnedAthleteInstance], players: [PlayerTrack],
                         scenario: ReplayScenario, times: [Double]) throws -> [Frame] {
        let capture = Capture(count: skins.count)
        let oracles = try skins.map { try ContactOracle(skin: $0) }
        let nativeOracles = try skins.map { skin -> NativeLowOracle? in
            skin.detail == .lowDetail ? try NativeLowOracle(skin: skin) : nil
        }
        for index in skins.indices {
            skins[index].poseStageObserverForTesting = { stage, pose in
                if stage == .cervical { capture.poses[index] = pose }
            }
        }
        defer { for skin in skins { skin.poseStageObserverForTesting = nil } }
        var frames: [Frame] = []
        for time in times {
            capture.poses = Array(repeating: nil, count: skins.count)
            let ball = scenario.ball.pose(at: time)
            let inputs = players.map { player in
                Input(time: time, locomotion: player.locomotion(at: time),
                      look: [ball.position.x, ball.height, ball.position.z],
                      action: ReplayAthleteMotion.ballActionPose(for: player, ballTrack: scenario.ball, at: time),
                      presentation: player.presentationPose(at: time))
            }
            var poses: [ReplaySkinnedAthleteMotion.Pose] = []
            var minima: [Float] = []
            for index in skins.indices {
                let skin = skins[index]
                XCTAssertTrue(update(skin, player: players[index], input: inputs[index]))
                let pose = try XCTUnwrap(capture.poses[index])
                var rebuilt = pose
                skin.motion.rebuildModelSpaceTransforms(in: &rebuilt)
                for (actual, expected) in zip(pose.modelSpaceTransforms, rebuilt.modelSpaceTransforms) {
                    for column in 0..<4 {
                        XCTAssertLessThanOrEqual(simd_distance(actual[column], expected[column]), 0.000_01,
                                                 "The captured pre-floor hierarchy must be current")
                    }
                }
                let minimum = skin.contactSurface.minimumY(in: pose)
                XCTAssertEqual(minimum, oracles[index].minimumY(in: pose), "Every contact vertex participates")
                if let native = nativeOracles[index] {
                    XCTAssertEqual(minimum, native.minimumY(in: pose), accuracy: 0.000_01,
                                   "Full imported low-mesh minimum, not a near proxy")
                }
                XCTAssertTrue(minimum.isFinite)
                poses.append(pose)
                minima.append(minimum)
            }
            frames.append(Frame(inputs: inputs, preFloor: poses, minima: minima,
                                finalJoints: skins.map { $0.model.jointTransforms },
                                finalFront: skins.map { $0.front.transform },
                                finalBack: skins.map { $0.back.transform }))
        }
        return frames
    }

    @inline(never)
    private func measureFloor(_ skins: [ReplaySkinnedAthleteInstance], frames: [Frame],
                              requests: Int) -> (nanoseconds: UInt64, checksum: Double) {
        var checksum = 0.0
        let started = DispatchTime.now().uptimeNanoseconds
        for request in 0..<requests {
            let frame = frames[request & 63]
            for index in skins.indices {
                checksum += Double(skins[index].contactSurface.minimumY(in: frame.preFloor[index]))
            }
        }
        return (DispatchTime.now().uptimeNanoseconds &- started, checksum)
    }

    @inline(never)
    private func measureWhole(_ skins: [ReplaySkinnedAthleteInstance], players: [PlayerTrack],
                              frames: [Frame], requests: Int) -> (nanoseconds: UInt64, supported: Bool) {
        var supported = true
        let started = DispatchTime.now().uptimeNanoseconds
        for request in 0..<requests {
            let frame = frames[request & 63]
            for index in skins.indices {
                supported = update(skins[index], player: players[index], input: frame.inputs[index]) && supported
            }
        }
        return (DispatchTime.now().uptimeNanoseconds &- started, supported)
    }

    private func update(_ skin: ReplaySkinnedAthleteInstance, player: PlayerTrack, input: Input) -> Bool {
        skin.update(at: input.time, track: player, locomotion: input.locomotion,
                    lookTarget: input.look, ballAction: input.action, presentationPose: input.presentation,
                    allowsTrackLocomotionSampling: true)
    }

    private func expectedChecksum(frames: [Frame], requests: Int) -> Double {
        var result = 0.0
        for request in 0..<requests {
            for value in frames[request & 63].minima { result += Double(value) }
        }
        return result
    }

    private func assertFinalState(_ skins: [ReplaySkinnedAthleteInstance], frame: Frame) {
        for index in skins.indices {
            XCTAssertNil(skins[index].poseStageObserverForTesting)
            XCTAssertEqual(skins[index].model.jointTransforms, frame.finalJoints[index])
            XCTAssertEqual(skins[index].front.transform, frame.finalFront[index])
            XCTAssertEqual(skins[index].back.transform, frame.finalBack[index])
        }
    }

    /// Decode every source contact vertex independently. No prepared production
    /// ranges/influences, minimum cache or reduced extremal subset is used.
    private struct ContactOracle {
        private struct Document: Decodable {
            struct Vertex: Decodable {
                let position: [Float]
                let joints: [Int]
                let weights: [Float]
            }
            let vertices: [Vertex]
            let inverseBindMatricesColumnMajor: [[Float]]?
        }
        private let document: Document
        private let inverseBinds: [simd_float4x4]

        init(skin: ReplaySkinnedAthleteInstance) throws {
            let name = skin.detail == .near ? "ReplayXIRocketboxContactSurface" : "ReplayXIRocketboxLowContactSurface"
            let url = try XCTUnwrap(Bundle.main.url(forResource: name, withExtension: "json", subdirectory: "Resources/Players")
                ?? Bundle.main.url(forResource: name, withExtension: "json"))
            document = try JSONDecoder().decode(Document.self, from: Data(contentsOf: url))
            XCTAssertEqual(document.vertices.count, skin.contactSurface.vertexCount)
            if skin.detail == .lowDetail {
                let values = try XCTUnwrap(document.inverseBindMatricesColumnMajor)
                inverseBinds = try values.map { value in
                    guard value.count == 16 else { throw CocoaError(.fileReadCorruptFile) }
                    return simd_float4x4(columns: (
                        SIMD4(value[0], value[1], value[2], value[3]),
                        SIMD4(value[4], value[5], value[6], value[7]),
                        SIMD4(value[8], value[9], value[10], value[11]),
                        SIMD4(value[12], value[13], value[14], value[15])))
                }
            } else {
                inverseBinds = skin.motion.restPose.modelSpaceTransforms.map(\.inverse)
            }
        }

        func minimumY(in pose: ReplaySkinnedAthleteMotion.Pose) -> Float {
            var minimum = Float.infinity
            for vertex in document.vertices {
                let point = SIMD4<Float>(vertex.position[0], vertex.position[1], vertex.position[2], 1)
                let total = vertex.weights.reduce(0, +)
                var height: Float = 0
                for index in vertex.joints.indices {
                    let joint = vertex.joints[index]
                    let local = inverseBinds[joint] * point
                    height += (pose.modelSpaceTransforms[joint] * local).y * (vertex.weights[index] / total)
                }
                minimum = min(minimum, height)
            }
            return minimum
        }
    }

    /// A second low-detail oracle reads the actual imported RealityKit mesh,
    /// not the contact sidecar. CPU linear-blend geometry is not GPU readback.
    private struct NativeLowOracle {
        private struct Part {
            let positions: [SIMD3<Float>]
            let influences: [MeshJointInfluence]
            let stride: Int
        }
        private let parts: [Part]
        private let inverseBinds: [simd_float4x4]

        init(skin: ReplaySkinnedAthleteInstance) throws {
            let contents = try XCTUnwrap(skin.model.model).mesh.contents
            let skeleton = try XCTUnwrap(Array(contents.skeletons).first)
            XCTAssertEqual(skeleton.joints.map(\.name), skin.motion.jointNames)
            inverseBinds = skeleton.joints.map(\.inverseBindPoseMatrix)
            parts = try contents.models.flatMap { Array($0.parts) }.map { part in
                let positions = part.positions.elements
                let influences = try XCTUnwrap(part.jointInfluences).influences.elements
                guard !positions.isEmpty, influences.count.isMultiple(of: positions.count),
                      (1...4).contains(influences.count / positions.count) else {
                    throw CocoaError(.fileReadCorruptFile)
                }
                return Part(positions: positions, influences: influences, stride: influences.count / positions.count)
            }
            XCTAssertEqual(parts.reduce(0) { $0 + $1.positions.count }, 1_707)
        }

        func minimumY(in pose: ReplaySkinnedAthleteMotion.Pose) -> Float {
            var minimum = Float.infinity
            for part in parts {
                for vertex in part.positions.indices {
                    let point = SIMD4<Float>(part.positions[vertex], 1)
                    var deformed = SIMD4<Float>.zero
                    for index in 0..<part.stride {
                        let influence = part.influences[vertex * part.stride + index]
                        guard influence.weight > 0 else { continue }
                        let matrix = pose.modelSpaceTransforms[influence.jointIndex] * inverseBinds[influence.jointIndex]
                        deformed += matrix * point * influence.weight
                    }
                    minimum = min(minimum, deformed.y)
                }
            }
            return minimum
        }
    }

    private func bits(_ pose: ReplaySkinnedAthleteMotion.Pose) -> [UInt32] {
        var result: [UInt32] = []
        for value in pose.translations + pose.scales { result += [value.x.bitPattern, value.y.bitPattern, value.z.bitPattern] }
        for rotation in pose.rotations {
            let value = rotation.vector
            result += [value.x.bitPattern, value.y.bitPattern, value.z.bitPattern, value.w.bitPattern]
        }
        for matrix in pose.modelSpaceTransforms {
            for column in 0..<4 {
                let value = matrix[column]
                result += [value.x.bitPattern, value.y.bitPattern, value.z.bitPattern, value.w.bitPattern]
            }
        }
        return result
    }

    private func median(_ values: [Double]) -> Double {
        let sorted = values.sorted()
        return (sorted[(sorted.count - 1) / 2] + sorted[sorted.count / 2]) * 0.5
    }
}
