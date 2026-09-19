import Foundation
import XCTest
@testable import ReplayXI

@MainActor
final class ReplayNativePreparationCancellation145Tests: XCTestCase {
    private typealias Recording = ReplayNativeBallPhysics.Recording

    @MainActor
    private final class Observation {
        var task: Task<Recording, Error>?
        var resumedSteps: [Int] = []
        var finishedSteps: [Int] = []
        var primaryWorlds = 0
        var previewWorlds = 0
        var cancellationRequests = 0
    }

    func testCancellationAtYieldStopsBeforeAnyMoreNativeWorkAndRetryIsExact() async throws {
        let scenario = try XCTUnwrap(FootballReferenceScenarios.all.first { $0.id == "final-108-rebound-v2" })
        let plan = try XCTUnwrap(FootballReferenceScenarios.touches(for: scenario))
        ReplayNativeBallPhysics.resetCacheForTesting()
        defer {
            ReplayNativeBallPhysics.preparationObserverForTesting = nil
            ReplayNativeBallPhysicsWorld.creationObserverForTesting = nil
            ReplayNativeBallPhysics.resetCacheForTesting()
        }
        let baseline = try await ReplayNativeBallPhysics.prewarm(track: scenario.ball, players: scenario.players,
                                                                plannedTouches: plan)
        ReplayNativeBallPhysics.resetCacheForTesting()
        let observation = Observation()
        ReplayNativeBallPhysics.preparationObserverForTesting = { checkpoint in
            switch checkpoint {
            case .resumedAfterYield(let steps):
                observation.resumedSteps.append(steps)
                // Deterministically reproduce a view/task being cancelled
                // while the bake gives the main actor a turn for user input.
                if observation.cancellationRequests == 0 {
                    XCTAssertNotNil(observation.task)
                    observation.cancellationRequests += 1
                    observation.task?.cancel()
                }
            case .finished(let steps):
                observation.finishedSteps.append(steps)
            }
        }
        ReplayNativeBallPhysicsWorld.creationObserverForTesting = { _, construction in
            if construction.includesGoals { observation.primaryWorlds += 1 }
            else { observation.previewWorlds += 1 }
        }
        observation.task = Task { @MainActor in
            try await ReplayNativeBallPhysics.prewarm(track: scenario.ball, players: scenario.players,
                                                      plannedTouches: plan)
        }
        do {
            _ = try await XCTUnwrap(observation.task).value
            XCTFail("Cancellation at the yield must discard the unfinished preparation")
        } catch is CancellationError {
            // Expected. A cancelled preparation must not become a cached result.
        }
        observation.task = nil
        ReplayNativeBallPhysics.preparationObserverForTesting = nil
        ReplayNativeBallPhysicsWorld.creationObserverForTesting = nil
        XCTAssertEqual(observation.cancellationRequests, 1)
        XCTAssertEqual(observation.resumedSteps, [0])
        XCTAssertEqual(observation.finishedSteps, [0], "No obsolete 120 Hz steps may run after the cancelled yield")
        XCTAssertEqual(observation.primaryWorlds, 1)
        XCTAssertEqual(observation.previewWorlds, 0, "A cancelled preparation must not create aim-preview renderers")
        XCTAssertEqual(ReplayNativeBallPhysics.cacheCountForTesting, 0)
        XCTAssertNil(ReplayNativeBallPhysics.cached(track: scenario.ball, players: scenario.players, plannedTouches: plan))

        let retry = try await ReplayNativeBallPhysics.prewarm(track: scenario.ball, players: scenario.players,
                                                             plannedTouches: plan)
        XCTAssertEqual(retry.nativeStepCount, 840)
        XCTAssertEqual(retry.samples.count, 841)
        XCTAssertEqual(retry.touches.count, 6)
        XCTAssertEqual(retry.missedTouchCount, 0)
        assertExact(retry, baseline)
        XCTAssertEqual(ReplayNativeBallPhysics.cacheCountForTesting, 1)
        XCTAssertTrue(ReplayNativeBallPhysics.cached(track: scenario.ball, players: scenario.players,
                                                    plannedTouches: plan) === retry)

        let report: [String: Any] = [
            "scenario": scenario.id, "cancellationRequests": observation.cancellationRequests,
            "resumedNativeSteps": observation.resumedSteps, "finishedNativeSteps": observation.finishedSteps,
            "primaryWorlds": observation.primaryWorlds, "previewWorldsAfterCancellation": observation.previewWorlds,
            "retryNativeSteps": retry.nativeStepCount, "retrySamples": retry.samples.count,
            "retryTouches": retry.touches.count, "retryMissedTouches": retry.missedTouchCount
        ]
        let attachment = XCTAttachment(data: try JSONSerialization.data(withJSONObject: report,
            options: [.prettyPrinted, .sortedKeys]), uniformTypeIdentifier: "public.json")
        attachment.name = "NativePreparationCancellation145-after-yield"
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    private func assertExact(_ actual: Recording, _ expected: Recording) {
        XCTAssertEqual(actual.samples.map(\.time), expected.samples.map(\.time))
        XCTAssertEqual(actual.samples.map(\.position), expected.samples.map(\.position))
        XCTAssertEqual(actual.samples.map { $0.orientation.vector }, expected.samples.map { $0.orientation.vector })
        XCTAssertEqual(actual.samples.map(\.velocity), expected.samples.map(\.velocity))
        XCTAssertEqual(actual.samples.map(\.angularVelocity), expected.samples.map(\.angularVelocity))
        XCTAssertEqual(actual.touches.map(\.time), expected.touches.map(\.time))
        XCTAssertEqual(actual.touches.map(\.playerID), expected.touches.map(\.playerID))
        XCTAssertEqual(actual.touches.map(\.position), expected.touches.map(\.position))
        XCTAssertEqual(actual.touches.map(\.outgoingVelocity), expected.touches.map(\.outgoingVelocity))
        XCTAssertEqual(actual.touches.map(\.kind), expected.touches.map(\.kind))
        XCTAssertEqual(actual.touches.map(\.kickingLeg), expected.touches.map(\.kickingLeg))
        XCTAssertEqual(actual.touches.map(\.headerSupportLeg), expected.touches.map(\.headerSupportLeg))
        XCTAssertEqual(actual.missedTouchCount, expected.missedTouchCount)
    }
}
