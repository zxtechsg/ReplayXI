import CryptoKit
import Foundation
import RealityKit
import XCTest
import simd
@testable import ReplayXI

/// Bounded lifecycle diagnostic, not proof that a renderer teardown is fixed.
/// Only bake() creates a renderer here; no camera, capture or GPU output exists.
/// Its private renderer identity and deferred destruction remain unobserved.
@MainActor
final class ReplayNativeRendererLifecycle142Tests: XCTestCase {
    private typealias Stage = ReplaySkinnedAthleteInstance.DiagnosticStage

    private final class WeakSkin {
        weak var value: ReplaySkinnedAthleteInstance?
        init(_ value: ReplaySkinnedAthleteInstance) { self.value = value }
    }

    private struct Receipt: Equatable {
        let samples: Int
        let touches: Int
        let sampleDigest: String
        let touchDigest: String
    }

    override func tearDown() {
        resetCaches()
        super.tearDown()
    }

    func testTwelveFreshBakesAndStageOnlySkinReleasesAcrossFiveScenes() async throws {
        let scenarios = FootballReferenceScenarios.all
        XCTAssertEqual(scenarios.count, 5)
        var baselines: [String: Receipt] = [:]
        var rows: [[String: Any]] = []

        for iteration in 0..<12 {
            let scenario = scenarios[iteration % scenarios.count]
            marker(iteration, scenario, "begin")
            resetCaches()
            // Match the header-stage test order, without any visual renderer.
            try ReplaySkinnedAthleteProvider.prewarm()
            try ReplaySkinnedAthleteProvider.prewarmLowDetail()
            let (receipt, releasedSkins) = try await exercise(scenario, iteration: iteration)
            if let expected = baselines[scenario.id] {
                XCTAssertEqual(receipt, expected, "Fresh bake changed: iteration \(iteration), \(scenario.id)")
            } else {
                baselines[scenario.id] = receipt
            }
            marker(iteration, scenario, "stage-only-scope-returned")
            resetCaches()
            // One queued main-thread turn, not a timed sleep or an assertion
            // that undocumented RealityRenderer cleanup has completed.
            await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                DispatchQueue.main.async { continuation.resume() }
            }
            await Task.yield()
            let retainedSkins = releasedSkins.filter { $0.value != nil }.count
            XCTAssertEqual(retainedSkins, 0, "Test skin instances must not extend renderer-lifecycle pressure")
            XCTAssertEqual(releasedSkins.count, 4, "Both teams at near and low detail")
            rows.append([
                "iteration": iteration, "scenario": scenario.id,
                "sampleCount": receipt.samples, "touchCount": receipt.touches,
                "sampleDigest": receipt.sampleDigest, "touchDigest": receipt.touchDigest,
                "retainedSkinInstances": retainedSkins, "visualRenderersCreated": 0,
                "physicsRendererLifetimeObserved": false
            ])
            marker(iteration, scenario, "released-and-yielded")
        }
        XCTAssertEqual(baselines.count, 5)
        let attachment = XCTAttachment(data: try JSONSerialization.data(withJSONObject: [
            "scope": "12 fresh native bakes, stage-only near/low updates, no capture renderers",
            "limit": "Passing does not identify the earlier corrupt weak reference or prove framework teardown completion",
            "iterations": rows
        ], options: [.prettyPrinted, .sortedKeys]), uniformTypeIdentifier: "public.json")
        attachment.name = "NativeRendererLifecycle142-baseline"
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    /// Returns only value receipts and weak skin references. The native bake
    /// already returns an immutable numeric recording, never a live world.
    private func exercise(_ scenario: ReplayScenario, iteration: Int) async throws -> (Receipt, [WeakSkin]) {
        let plan = try XCTUnwrap(FootballReferenceScenarios.touches(for: scenario))
        marker(iteration, scenario, "bake-start")
        let recording = try await ReplayNativeBallPhysics.bake(track: scenario.ball,
            players: scenario.players, plannedTouches: plan)
        marker(iteration, scenario, "bake-returned")
        XCTAssertEqual(recording.missedTouchCount, 0, scenario.id)
        XCTAssertEqual(recording.touches.count, plan.count, scenario.id)
        XCTAssertGreaterThan(recording.nativeStepCount, 500)
        XCTAssertTrue(recording.samples.allSatisfy {
            $0.time.isFinite && finite($0.position) && finite($0.velocity)
                && finite($0.angularVelocity) && finite($0.orientation.vector)
        })

        let receipt = try receipt(recording)
        var sentinels: [WeakSkin] = []
        for team in [FootballTeam.home, .away] {
            let contacted = recording.touches.compactMap { scenario.player(id: $0.playerID) }
                .first { $0.team == team && !$0.isGoalkeeper }
            let track = try XCTUnwrap(contacted ?? scenario.players.first { $0.team == team && !$0.isGoalkeeper })
            for detail in [ReplaySkinnedAthleteProvider.Detail.near, .lowDetail] {
                sentinels.append(try exerciseSkin(track, detail: detail, scenario: scenario, recording: recording))
            }
        }
        marker(iteration, scenario, "near-low-updates-complete")
        return (receipt, sentinels)
    }

    private func exerciseSkin(_ track: PlayerTrack, detail: ReplaySkinnedAthleteProvider.Detail,
                              scenario: ReplayScenario, recording: ReplayNativeBallPhysics.Recording) throws -> WeakSkin {
        let skin = try ReplaySkinnedAthleteProvider.make(for: track, detail: detail)
        let sentinel = WeakSkin(skin)
        var observed: Set<Stage> = []
        skin.poseStageObserverForTesting = { stage, pose in
            observed.insert(stage)
            XCTAssertTrue(pose.translations.allSatisfy { self.finite($0) })
            XCTAssertTrue(pose.rotations.allSatisfy { self.finite($0.vector) })
        }
        defer { skin.poseStageObserverForTesting = nil }
        let cues = try recording.touches.filter { $0.playerID == track.id }.map { touch in
            ReplayAthleteInteractionCue(playerID: track.id,
                kind: try XCTUnwrap(ReplayAthleteInteractionCue.Kind(rawValue: touch.kind.rawValue)),
                contactTime: touch.time, startTime: touch.time - 0.32, endTime: touch.time + 0.42,
                kickingLeg: touch.kickingLeg, contactBallWorldPosition: touch.position,
                outgoingDirectionWorld: touch.outgoingVelocity, headerSupportLeg: touch.headerSupportLeg)
        }
        let frameStep: Double = 1.0 / 120.0
        var sampleTimes: [Double] = [0.0, scenario.duration * 0.25, scenario.duration * 0.5,
                                     scenario.duration * 0.75, scenario.duration]
        for cue in cues {
            sampleTimes.append(cue.startTime - frameStep)
            sampleTimes.append(cue.startTime + frameStep)
            sampleTimes.append(cue.contactTime)
            sampleTimes.append(cue.endTime - frameStep)
            sampleTimes.append(cue.endTime + frameStep)
        }
        let boundedTimes: [Double] = sampleTimes.map { min(max($0, 0.0), scenario.duration) }
        let times: [Double] = boundedTimes.sorted()
        var saved: [[Transform]] = []
        func update(_ time: Double) {
            observed.removeAll(keepingCapacity: true)
            let pose = track.presentationPose(at: time)
            let cue = cues.filter { ReplayAthleteMovementIntent.includesPreparation($0, at: time) }
                .min { abs($0.contactTime - time) < abs($1.contactTime - time) }
            XCTAssertTrue(skin.update(at: time, track: track, locomotion: track.locomotion(at: time),
                lookTarget: recording.sample(at: time).position, ballAction: nil, interaction: cue,
                presentationPose: pose, allowsTrackLocomotionSampling: true))
            XCTAssertEqual(observed, Set(Stage.allCases))
        }
        for time in times {
            update(time)
            saved.append(skin.model.jointTransforms)
        }
        for index in times.indices.reversed() {
            update(times[index])
            XCTAssertEqual(skin.model.jointTransforms, saved[index], "Exact stage-only rewind: \(track.id), \(detail)")
        }
        return sentinel
    }

    private func receipt(_ recording: ReplayNativeBallPhysics.Recording) throws -> Receipt {
        let samples = recording.samples.map { sample in
            [sample.time] + vector(sample.position) + vector(sample.orientation.vector)
                + vector(sample.velocity) + vector(sample.angularVelocity)
        }
        let touches: [[String: Any]] = recording.touches.map { touch in
            ["time": touch.time, "player": touch.playerID, "kind": touch.kind.rawValue,
             "leg": touch.kickingLeg.rawValue, "support": touch.headerSupportLeg?.rawValue ?? "none",
             "position": vector(touch.position), "velocity": vector(touch.outgoingVelocity)]
        }
        func digest(_ object: Any) throws -> String {
            let data = try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
            return SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        }
        return Receipt(samples: samples.count, touches: touches.count,
            sampleDigest: try digest(samples), touchDigest: try digest(touches))
    }

    private func resetCaches() {
        ReplayNativeBallPhysics.resetCacheForTesting()
        ReplaySkinnedAthleteProvider.resetForTesting()
        ReplayAthleteHeadProvider.resetForTesting()
    }

    private func marker(_ iteration: Int, _ scenario: ReplayScenario, _ stage: String) {
        print("[NativeLifecycle142] iteration=\(iteration) scenario=\(scenario.id) stage=\(stage)")
    }

    private func vector(_ value: SIMD3<Float>) -> [Double] { [Double(value.x), Double(value.y), Double(value.z)] }
    private func vector(_ value: SIMD4<Float>) -> [Double] { [Double(value.x), Double(value.y), Double(value.z), Double(value.w)] }
    private func finite(_ value: SIMD3<Float>) -> Bool { value.x.isFinite && value.y.isFinite && value.z.isFinite }
    private func finite(_ value: SIMD4<Float>) -> Bool { value.x.isFinite && value.y.isFinite && value.z.isFinite && value.w.isFinite }
}
