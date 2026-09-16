import Foundation
import RealityKit
import XCTest
import simd
@testable import ReplayXI

@MainActor
final class ReplayLowDetailAthleteRuntimeTests: XCTestCase {
    override func tearDown() {
        ReplaySkinnedAthleteProvider.resetForTesting()
        ReplayAthleteHeadProvider.resetForTesting()
        super.tearDown()
    }

    private func prepare(low: Bool = true) throws -> ReplayScenario {
        ReplaySkinnedAthleteProvider.resetForTesting()
        ReplayAthleteHeadProvider.resetForTesting()
        try ReplaySkinnedAthleteProvider.prewarm()
        if low { try ReplaySkinnedAthleteProvider.prewarmLowDetail() }
        return try XCTUnwrap(DemoScenarios.scenario(for: .squadReplay))
    }

    func testLowAdmissionIsExplicitAndDoesNotReplaceNearDefault() throws {
        let scenario = try prepare(low: false)
        let player = try XCTUnwrap(scenario.player(id: "navy-rw"))
        XCTAssertTrue(ReplaySkinnedAthleteProvider.isPrewarmed)
        XCTAssertFalse(ReplaySkinnedAthleteProvider.isLowDetailPrewarmed)
        XCTAssertThrowsError(try ReplaySkinnedAthleteProvider.make(for: player, detail: .lowDetail)) {
            XCTAssertEqual($0 as? ReplaySkinnedAthleteError, .notPrepared)
        }
        XCTAssertEqual(try ReplaySkinnedAthleteProvider.make(for: player).detail, .near)
        try ReplaySkinnedAthleteProvider.prewarmLowDetail()
        try ReplaySkinnedAthleteProvider.prewarmLowDetail() // Idempotent cold path.
        XCTAssertTrue(ReplaySkinnedAthleteProvider.isLowDetailPrewarmed)
        XCTAssertEqual(try ReplaySkinnedAthleteProvider.make(for: player).detail, .near)
        ReplaySkinnedAthleteProvider.resetLowDetailForTesting()
        XCTAssertTrue(ReplaySkinnedAthleteProvider.isPrewarmed)
        XCTAssertFalse(ReplaySkinnedAthleteProvider.isLowDetailPrewarmed)
    }

    func testLowClonesShareMeshButKeepIndependentJointsAndNumbers() throws {
        let scenario = try prepare()
        let player = try XCTUnwrap(scenario.player(id: "navy-rw"))
        let first = try ReplaySkinnedAthleteProvider.make(for: player, detail: .lowDetail)
        let second = try ReplaySkinnedAthleteProvider.make(for: player, detail: .lowDetail)
        let near = try ReplaySkinnedAthleteProvider.make(for: player)
        XCTAssertEqual(first.detail, .lowDetail)
        XCTAssertTrue(first.model.model?.mesh === second.model.model?.mesh)
        XCTAssertFalse(first.model.model?.mesh === near.model.model?.mesh)
        XCTAssertFalse(first.model === second.model)
        XCTAssertFalse(first.front === second.front)
        XCTAssertEqual(first.model.jointNames, near.model.jointNames)
        XCTAssertEqual(first.model.jointTransforms.count, 80)
        XCTAssertEqual(first.model.model?.materials.count, 2)
        let parts = try XCTUnwrap(first.model.model).mesh.contents.models.flatMap { Array($0.parts) }
        XCTAssertEqual(parts.reduce(0) { $0 + $1.positions.count }, 1_707)
        XCTAssertEqual(parts.reduce(0) { $0 + ($1.triangleIndices?.count ?? 0) / 3 }, 2_129)
        XCTAssertEqual(first.contactSurface.vertexCount, 1_707)
        XCTAssertEqual(first.contactSurface.influenceCount, 2_823)
        XCTAssertTrue(update(first, player: player, scenario: scenario, time: 13.6))
        XCTAssertNotEqual(first.model.jointTransforms, second.model.jointTransforms)
        XCTAssertEqual(first.front.name, "skinned-chest-number")
        XCTAssertEqual(first.back.name, "skinned-shirt-number")
        XCTAssertEqual(ReplaySkinnedAthleteProvider.maximumConcurrentInstances, 4)
        XCTAssertEqual(PitchSceneFactory.firstPersonDetailedRigLimit, 2)
    }

    func testEveryLowVertexStaysAboveFloorThroughFootballImpactsAndRewind() throws {
        let scenario = try prepare()
        let player = try XCTUnwrap(scenario.player(id: "navy-rw"))
        let skin = try ReplaySkinnedAthleteProvider.make(for: player, detail: .lowDetail)
        let cue = PlayerRagdollCue(playerID: player.id, impactTime: 12.5)
        let times = Array(stride(from: 0.0, through: 30.0, by: 0.125))
        for time in times + times.reversed() {
            XCTAssertTrue(update(skin, player: player, scenario: scenario, time: time,
                                 impact: PlayerRagdollPlayback.sample(for: cue, at: time)))
            XCTAssertGreaterThanOrEqual(skin.contactSurface.minimumY(in: skin.pose)
                - skin.motion.geometry.restMinY, skin.contactSurface.paddingMetres - 0.000_1)
            XCTAssertTrue(skin.model.jointTransforms.allSatisfy {
                $0.translation.x.isFinite && $0.translation.y.isFinite && $0.translation.z.isFinite
                    && abs(simd_length($0.rotation.vector) - 1) < 0.000_1
            })
        }
        XCTAssertTrue(update(skin, player: player, scenario: scenario, time: 13.6))
        let expected = skin.model.jointTransforms
        let front = skin.front.transform, back = skin.back.transform
        for time in [29.0, 0, 18, 13.6] { XCTAssertTrue(update(skin, player: player, scenario: scenario, time: time)) }
        XCTAssertEqual(skin.model.jointTransforms, expected)
        XCTAssertEqual(skin.front.transform, front)
        XCTAssertEqual(skin.back.transform, back)
    }

    func testMissingOrChangedLowAssetCannotInvalidateNearPlayers() throws {
        let scenario = try prepare(low: false)
        let player = try XCTUnwrap(scenario.player(id: "navy-rw"))
        let near = try ReplaySkinnedAthleteProvider.make(for: player)
        XCTAssertThrowsError(try ReplaySkinnedAthleteProvider.prewarmLowDetail(in: Bundle(for: Self.self)))
        XCTAssertTrue(ReplaySkinnedAthleteProvider.isPrewarmed)
        XCTAssertFalse(ReplaySkinnedAthleteProvider.isLowDetailPrewarmed)
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("ReplayXI-LowHash-\(UUID().uuidString).bundle", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let plist = try PropertyListSerialization.data(fromPropertyList: ["CFBundleIdentifier": "replayxi.low-hash-test"],
                                                       format: .xml, options: 0)
        try plist.write(to: directory.appendingPathComponent("Info.plist"))
        let name = "ReplayXIRocketboxLow"
        let source = try XCTUnwrap(Bundle.main.url(forResource: name, withExtension: "usdz", subdirectory: "Resources/Players")
            ?? Bundle.main.url(forResource: name, withExtension: "usdz"))
        var changed = try Data(contentsOf: source)
        changed.append(0)
        try changed.write(to: directory.appendingPathComponent(name + ".usdz"))
        let contactName = "ReplayXIRocketboxLowContactSurface"
        let contactSource = try XCTUnwrap(Bundle.main.url(forResource: contactName, withExtension: "json", subdirectory: "Resources/Players")
            ?? Bundle.main.url(forResource: contactName, withExtension: "json"))
        var changedContact = try Data(contentsOf: contactSource)
        changedContact.append(32) // Still valid JSON; changed identity must fail before decoding.
        try changedContact.write(to: directory.appendingPathComponent(contactName + ".json"))
        // Bundle caches its resource index: publish the complete fixture before
        // its first lookup. Replacing bytes below does not add a new resource.
        let fixtureBundle = try XCTUnwrap(Bundle(url: directory))
        XCTAssertThrowsError(try ReplaySkinnedAthleteProvider.prewarmLowDetail(in: fixtureBundle)) {
            XCTAssertEqual($0 as? ReplaySkinnedAthleteError, .invalidHash(name + ".usdz"))
        }
        try Data(contentsOf: source).write(to: directory.appendingPathComponent(name + ".usdz"))
        XCTAssertThrowsError(try ReplaySkinnedAthleteProvider.prewarmLowDetail(in: fixtureBundle)) {
            XCTAssertEqual($0 as? ReplaySkinnedAthleteError, .invalidHash(contactName + ".json"))
        }
        XCTAssertTrue(ReplaySkinnedAthleteProvider.isPrewarmed)
        XCTAssertFalse(ReplaySkinnedAthleteProvider.isLowDetailPrewarmed)
        XCTAssertTrue(update(near, player: player, scenario: scenario, time: 13.6))
        try ReplaySkinnedAthleteProvider.prewarmLowDetail()
        XCTAssertTrue(ReplaySkinnedAthleteProvider.isLowDetailPrewarmed)
    }

    /// Simulator CPU diagnostic, not a frame-rate or headset/GPU assertion.
    func testRecordsMixedNearAndLowPoseCPUWithinExistingFourPlayerCap() throws {
        let scenario = try prepare()
        let players = try ["navy-rw", "navy-rb", "red-lw", "red-lb"].map { try XCTUnwrap(scenario.player(id: $0)) }
        let times = (0..<32).map { 10.5 + Double($0) * 0.25 }
        let inputs = (times + times.reversed()).map { time in
            let ball = scenario.ball.pose(at: time)
            return players.map { player in (time, player.locomotion(at: time),
                SIMD3<Float>(ball.position.x, ball.height, ball.position.z),
                ReplayAthleteMotion.ballActionPose(for: player, ballTrack: scenario.ball, at: time)) }
        }
        var reports: [[String: Any]] = []
        for nearCount in [4, 1, 2] {
            let skins = try players.enumerated().map {
                try ReplaySkinnedAthleteProvider.make(for: $0.element, detail: $0.offset < nearCount ? .near : .lowDetail)
            }
            var durations: [Double] = []
            for (frameIndex, frame) in (Array(inputs.prefix(3)) + inputs).enumerated() {
                var supported = true
                let start = DispatchTime.now().uptimeNanoseconds
                for index in skins.indices {
                    let input = frame[index]
                    supported = skins[index].update(at: input.0, track: players[index], locomotion: input.1,
                        lookTarget: input.2, ballAction: input.3) && supported
                }
                let duration = Double(DispatchTime.now().uptimeNanoseconds - start) / 1_000_000
                if frameIndex >= 3 { durations.append(duration) }
                XCTAssertTrue(supported)
            }
            let sorted = durations.sorted()
            XCTAssertEqual(sorted.count, 64)
            XCTAssertTrue(sorted.allSatisfy { $0.isFinite && $0 >= 0 })
            reports.append(["near": nearCount, "low": 4 - nearCount, "frames": sorted.count,
                "medianMilliseconds": (sorted[31] + sorted[32]) / 2,
                "p95NearestRankMilliseconds": sorted[Int(ceil(0.95 * Double(sorted.count))) - 1],
                "maximumMilliseconds": sorted[63],
                "contactInfluences": skins.reduce(0) { $0 + $1.contactSurface.influenceCount }])
        }
        let data = try JSONSerialization.data(withJSONObject: [
            "scope": "Instance.update only: pose, full contacts and native joint writes; prewarm/track sampling/assertions excluded",
            "notFPS": true, "notGPUOrHeadset": true, "skinCapUnchanged": 4, "samples": reports
        ], options: [.sortedKeys])
        let attachment = XCTAttachment(data: data, uniformTypeIdentifier: "public.json")
        attachment.name = "ReplayXI-Low113-MixedPoseCPU.json"
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    private func update(_ skin: ReplaySkinnedAthleteInstance, player: PlayerTrack, scenario: ReplayScenario,
                        time: Double, impact: PlayerRagdollPlayback.Sample? = nil) -> Bool {
        let ball = scenario.ball.pose(at: time)
        return skin.update(at: time, track: player, locomotion: player.locomotion(at: time),
            lookTarget: [ball.position.x, ball.height, ball.position.z],
            ballAction: ReplayAthleteMotion.ballActionPose(for: player, ballTrack: scenario.ball, at: time), impact: impact)
    }
}
