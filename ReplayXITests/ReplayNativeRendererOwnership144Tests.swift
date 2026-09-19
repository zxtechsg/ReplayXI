import CryptoKit
import Foundation
import RealityKit
import XCTest
@testable import ReplayXI

/// Observes Swift ownership during nested native aim previews and cancellation.
/// Weak-reference release does not establish completion of CoreRE scene teardown.
@MainActor
final class ReplayNativeRendererOwnership144Tests: XCTestCase {
    private typealias Recording = ReplayNativeBallPhysics.Recording

    @MainActor
    private final class WeakWorld {
        let sequence: Int
        let role: String
        let rendererAddress: String
        weak var world: ReplayNativeBallPhysicsWorld?
        weak var renderer: RealityRenderer?
        weak var root: Entity?
        weak var ball: ModelEntity?

        init(_ world: ReplayNativeBallPhysicsWorld, sequence: Int, includesGoals: Bool) {
            self.sequence = sequence
            // Within prewarm's call tree only the primary world has goals;
            // aim-preview worlds explicitly construct with includeGoals: false.
            role = includesGoals ? "primary" : "aim-preview"
            rendererAddress = String(describing: ObjectIdentifier(world.renderer))
            self.world = world
            renderer = world.renderer
            root = world.root
            ball = world.ball
        }

        var row: [String: Any] {
            ["sequence": sequence, "role": role, "rendererAddress": rendererAddress,
             "worldRetained": world != nil, "rendererRetained": renderer != nil,
             "rootRetained": root != nil, "ballRetained": ball != nil]
        }
    }

    @MainActor
    private final class Observation {
        var probes: [WeakWorld] = []
        var task: Task<Recording, Error>?
        var cancellationRequests = 0
        var primaryAliveAtFirstPreview = false
        var sawFirstPreview = false
    }

    private struct Receipt: Equatable {
        let samples: Int
        let touches: Int
        let sampleDigest: String
        let touchDigest: String

        var row: [String: Any] {
            ["samples": samples, "touches": touches,
             "sampleDigest": sampleDigest, "touchDigest": touchDigest]
        }
    }

    private struct Run {
        let recording: Recording?
        let observation: Observation
        let beforeQueueTurn: [[String: Any]]
        let afterQueueTurn: [[String: Any]]
    }

    func testNestedPreviewOwnershipOnCompletionCancellationAndExactRetry() async throws {
        let scenario = try XCTUnwrap(FootballReferenceScenarios.all.first { $0.id == "final-108-rebound-v2" })
        let plan = try XCTUnwrap(FootballReferenceScenarios.touches(for: scenario))
        XCTAssertEqual(plan.count, 6)
        ReplayNativeBallPhysics.resetCacheForTesting()
        defer {
            ReplayNativeBallPhysicsWorld.creationObserverForTesting = nil
            ReplayNativeBallPhysics.resetCacheForTesting()
        }

        let baseline = try await run(scenario, plan: plan, phase: "complete", cancelAtFirstPreview: false)
        let baselineRecording = try XCTUnwrap(baseline.recording)
        let baselineReceipt = try receipt(baselineRecording)
        assertCompleted(baseline, receipt: baselineReceipt, scenario: scenario, plan: plan)

        // prewarm checks its cache before making a world. Reset it so the next
        // task reaches a live nested preview instead of returning the baseline.
        ReplayNativeBallPhysics.resetCacheForTesting()
        let cancelled = try await run(scenario, plan: plan, phase: "cancel-preview", cancelAtFirstPreview: true)
        XCTAssertNil(cancelled.recording)
        XCTAssertEqual(cancelled.observation.cancellationRequests, 1)
        XCTAssertEqual(cancelled.observation.probes.filter { $0.role == "primary" }.count, 1)
        XCTAssertTrue(cancelled.observation.primaryAliveAtFirstPreview)
        XCTAssertGreaterThanOrEqual(cancelled.observation.probes.filter { $0.role == "aim-preview" }.count, 1)
        XCTAssertEqual(ReplayNativeBallPhysics.cacheCountForTesting, 0)
        XCTAssertNil(ReplayNativeBallPhysics.cached(track: scenario.ball, players: scenario.players, plannedTouches: plan))

        let retry = try await run(scenario, plan: plan, phase: "retry", cancelAtFirstPreview: false)
        let retryRecording = try XCTUnwrap(retry.recording)
        let retryReceipt = try receipt(retryRecording)
        assertCompleted(retry, receipt: retryReceipt, scenario: scenario, plan: plan)
        XCTAssertEqual(retryReceipt, baselineReceipt, "Cancellation must not alter any recorded sample or touch")

        let phases = [
            phaseRow("complete", baseline, receipt: baselineReceipt),
            phaseRow("cancel-preview", cancelled, receipt: nil),
            phaseRow("retry", retry, receipt: retryReceipt)
        ]
        let attachment = XCTAttachment(data: try JSONSerialization.data(withJSONObject: [
            "scenario": scenario.id, "phases": phases, "visualRenderersCreated": 0,
            "limit": "Weak Swift object release is observed; asynchronous CoreRE teardown completion is not observable here",
            "identity": "Sequence numbers identify creations; renderer addresses may be reused after release"
        ], options: [.prettyPrinted, .sortedKeys]), uniformTypeIdentifier: "public.json")
        attachment.name = "NativeRendererOwnership144-complete-cancel-retry"
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    private func run(_ scenario: ReplayScenario, plan: [ReplayNativeBallPhysics.PlannedTouch],
                     phase: String, cancelAtFirstPreview: Bool) async throws -> Run {
        let observation = Observation()
        // The observer owns only this receipt container, whose entity/renderer
        // refs are weak. It never captures a world or the test instance.
        ReplayNativeBallPhysicsWorld.creationObserverForTesting = { world, construction in
            XCTAssertTrue(construction.includesPitch)
            XCTAssertEqual(world.renderer.entities.count, 1)
            XCTAssertNil(world.renderer.activeCamera)
            let probe = WeakWorld(world, sequence: observation.probes.count + 1,
                                  includesGoals: construction.includesGoals)
            observation.probes.append(probe)
            print("[NativeOwnership144] phase=\(phase) created=\(probe.sequence) role=\(probe.role) renderer=\(probe.rendererAddress)")
            if !construction.includesGoals, !observation.sawFirstPreview {
                observation.sawFirstPreview = true
                observation.primaryAliveAtFirstPreview = observation.probes.contains {
                    $0.role == "primary" && $0.world != nil && $0.renderer != nil
                }
                if cancelAtFirstPreview {
                    XCTAssertNotNil(observation.task)
                    observation.cancellationRequests += 1
                    observation.task?.cancel()
                    print("[NativeOwnership144] phase=\(phase) cancellation-requested")
                }
            }
        }
        defer {
            ReplayNativeBallPhysicsWorld.creationObserverForTesting = nil
            observation.task = nil
        }
        // The main-actor task cannot run before its handle is assigned: there
        // is no suspension between task creation and storing the handle.
        observation.task = Task { @MainActor in
            try await ReplayNativeBallPhysics.prewarm(track: scenario.ball, players: scenario.players,
                                                      plannedTouches: plan)
        }
        var recording: Recording?
        do {
            recording = try await XCTUnwrap(observation.task).value
            XCTAssertFalse(cancelAtFirstPreview, "The task must throw after cancellation inside its first preview")
        } catch is CancellationError {
            XCTAssertTrue(cancelAtFirstPreview, "Normal bakes must not be cancelled")
        }
        observation.task = nil
        ReplayNativeBallPhysicsWorld.creationObserverForTesting = nil
        print("[NativeOwnership144] phase=\(phase) task-released")
        let before = observation.probes.map(\.row)
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            DispatchQueue.main.async { continuation.resume() }
        }
        await Task.yield()
        let after = observation.probes.map(\.row)
        XCTAssertEqual(observation.probes.filter { $0.world != nil }.count, 0,
                       "The completed/cancelled task must not retain native worlds")
        XCTAssertEqual(observation.probes.filter { $0.renderer != nil }.count, 0,
                       "No Swift renderer owner should survive the task and one queued main turn")
        // Root/ball lifetimes are reported, not used as an undocumented fence
        // for the renderer's deferred internal scene-removal work.
        print("[NativeOwnership144] phase=\(phase) ownership-observed")
        return Run(recording: recording, observation: observation, beforeQueueTurn: before, afterQueueTurn: after)
    }

    private func assertCompleted(_ run: Run, receipt: Receipt, scenario: ReplayScenario,
                                 plan: [ReplayNativeBallPhysics.PlannedTouch]) {
        XCTAssertEqual(receipt.samples, 841)
        XCTAssertEqual(receipt.touches, 6)
        XCTAssertEqual(run.recording?.nativeStepCount, 840)
        XCTAssertEqual(run.recording?.missedTouchCount, 0)
        XCTAssertEqual(run.observation.cancellationRequests, 0)
        XCTAssertTrue(run.observation.primaryAliveAtFirstPreview)
        XCTAssertEqual(run.observation.probes.filter { $0.role == "primary" }.count, 1)
        let previews = run.observation.probes.filter { $0.role == "aim-preview" }.count
        XCTAssertGreaterThanOrEqual(previews, 6)
        XCTAssertLessThanOrEqual(previews, 18)
        XCTAssertEqual(ReplayNativeBallPhysics.cacheCountForTesting, 1)
        XCTAssertTrue(ReplayNativeBallPhysics.cached(track: scenario.ball, players: scenario.players,
                                                    plannedTouches: plan) === run.recording)
    }

    private func phaseRow(_ phase: String, _ run: Run, receipt: Receipt?) -> [String: Any] {
        ["phase": phase, "createdWorlds": run.observation.probes.count,
         "cancellationRequests": run.observation.cancellationRequests,
         "primaryAliveAtFirstPreview": run.observation.primaryAliveAtFirstPreview,
         "beforeQueuedMainTurn": run.beforeQueueTurn, "afterQueuedMainTurn": run.afterQueueTurn,
         "recording": receipt?.row ?? [:]]
    }

    private func receipt(_ recording: Recording) throws -> Receipt {
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

    private func vector(_ value: SIMD3<Float>) -> [Double] { [Double(value.x), Double(value.y), Double(value.z)] }
    private func vector(_ value: SIMD4<Float>) -> [Double] { [Double(value.x), Double(value.y), Double(value.z), Double(value.w)] }
}
