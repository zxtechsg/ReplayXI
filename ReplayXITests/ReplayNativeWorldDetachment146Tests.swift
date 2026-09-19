import Foundation
import RealityKit
import XCTest
@testable import ReplayXI

/// Explicit hierarchy detachment, not a claim that the intermittent CoreRE
/// weak-reference crash is fixed or that deferred scene teardown is complete.
@MainActor
final class ReplayNativeWorldDetachment146Tests: XCTestCase {
    private typealias World = ReplayNativeBallPhysicsWorld
    private typealias Recording = ReplayNativeBallPhysics.Recording
    private enum InjectedFailure: Error, Equatable { case start }

    @MainActor
    private final class Probe {
        let sequence: Int
        let primary: Bool
        weak var world: World?
        weak var renderer: RealityRenderer?
        var finishes = 0
        var rootCounts: [Int] = []
        var attachedScenes: [Bool] = []

        init(_ world: World, sequence: Int, primary: Bool) {
            self.sequence = sequence
            self.primary = primary
            self.world = world
            renderer = world.renderer
        }

        var row: [String: Any] {
            ["sequence": sequence, "primary": primary, "finishes": finishes,
             "rendererRootCounts": rootCounts, "rootOrBallSceneAttached": attachedScenes,
             "worldRetained": world != nil, "rendererRetained": renderer != nil]
        }
    }

    @MainActor
    private final class Observation {
        var probes: [Probe] = []
        var task: Task<Recording, Error>?
        var cancellationRequests = 0
    }

    override func tearDown() {
        World.creationObserverForTesting = nil
        World.finishObserverForTesting = nil
        ReplayNativeBallPhysics.resetCacheForTesting()
        super.tearDown()
    }

    func testFinishDetachesActiveHierarchyTwiceWithoutChangingSampleOrComponents() throws {
        let observation = observe()
        let world = try World(includeGoals: false)
        world.placeBall(position: [0, 2, 0], velocity: [1, 0, 0])
        try world.start()
        for _ in 0..<4 { try world.advance(ReplayNativeBallPhysics.step) }
        let before = world.sample(at: 4 * ReplayNativeBallPhysics.step)
        XCTAssertEqual(world.renderer.entities.count, 1)
        XCTAssertNotNil(world.root.scene)
        XCTAssertNotNil(world.ball.scene)
        let childCount = world.root.children.count
        world.finish()
        world.finish()
        XCTAssertEqual(world.renderer.entities.count, 0)
        XCTAssertNil(world.root.scene)
        XCTAssertNil(world.ball.scene)
        XCTAssertEqual(world.root.children.count, childCount)
        XCTAssertTrue(world.ball.parent === world.root)
        XCTAssertNotNil(world.root.components[PhysicsSimulationComponent.self])
        XCTAssertNotNil(world.ball.components[PhysicsBodyComponent.self])
        XCTAssertNotNil(world.ball.components[CollisionComponent.self])
        let after = world.sample(at: before.time)
        XCTAssertEqual(after.position, before.position)
        XCTAssertEqual(after.orientation.vector, before.orientation.vector)
        XCTAssertEqual(after.velocity, before.velocity)
        XCTAssertEqual(after.angularVelocity, before.angularVelocity)
        XCTAssertEqual(observation.probes.count, 1)
        XCTAssertEqual(observation.probes.first?.finishes, 2)
        XCTAssertEqual(observation.probes.first?.rootCounts, [0, 0])
        XCTAssertEqual(observation.probes.first?.attachedScenes, [false, false])
    }

    func testAllFiveDetachedRecordingsExactlyMatchLegacyReleaseOrder() async throws {
        XCTAssertEqual(FootballReferenceScenarios.all.count, 5)
        let expectedCounts = [1621, 1261, 841, 1201, 1201]
        let expectedTouches = [6, 5, 6, 5, 5]
        var rows: [[String: Any]] = []
        for (index, scenario) in FootballReferenceScenarios.all.enumerated() {
            let plan = try XCTUnwrap(FootballReferenceScenarios.touches(for: scenario))
            let legacyOwnership = observe(legacy: true)
            let legacy = try await ReplayNativeBallPhysics.bake(track: scenario.ball, players: scenario.players,
                                                               plannedTouches: plan)
            assertFinished(legacyOwnership, detached: false)
            let candidateOwnership = observe()
            let candidate = try await ReplayNativeBallPhysics.bake(track: scenario.ball, players: scenario.players,
                                                                  plannedTouches: plan)
            assertFinished(candidateOwnership, detached: true)
            XCTAssertEqual(candidate.samples.count, expectedCounts[index])
            XCTAssertEqual(candidate.nativeStepCount, expectedCounts[index] - 1)
            XCTAssertEqual(candidate.touches.count, expectedTouches[index])
            XCTAssertEqual(candidate.missedTouchCount, 0)
            assertExact(candidate, legacy)
            XCTAssertEqual(candidateOwnership.probes.filter(\.primary).count, 1)
            XCTAssertEqual(candidateOwnership.probes.count, legacyOwnership.probes.count)
            XCTAssertGreaterThanOrEqual(candidateOwnership.probes.count, 1 + plan.count)
            XCTAssertLessThanOrEqual(candidateOwnership.probes.count, 1 + 3 * plan.count)
            rows.append(["scenario": scenario.id, "samples": candidate.samples.count,
                         "touches": candidate.touches.count, "missedTouches": candidate.missedTouchCount,
                         "legacy": legacyOwnership.probes.map(\.row),
                         "detached": candidateOwnership.probes.map(\.row)])
        }
        try attach(rows, name: "FiveSceneLegacyAndDetached")
    }

    func testCancellationFinishesPrimaryAndNestedPreviewsWithoutCaching() async throws {
        let scenario = try rebound()
        let plan = try XCTUnwrap(FootballReferenceScenarios.touches(for: scenario))
        ReplayNativeBallPhysics.resetCacheForTesting()
        let observation = Observation()
        observe(into: observation) { _, construction in
            guard !construction.includesGoals, observation.cancellationRequests == 0 else { return }
            XCTAssertNotNil(observation.task)
            observation.cancellationRequests += 1
            observation.task?.cancel()
        }
        observation.task = Task { @MainActor in
            try await ReplayNativeBallPhysics.prewarm(track: scenario.ball, players: scenario.players,
                                                      plannedTouches: plan)
        }
        do {
            _ = try await XCTUnwrap(observation.task).value
            XCTFail("Cancelled preparation must throw")
        } catch is CancellationError {}
        observation.task = nil
        XCTAssertEqual(observation.cancellationRequests, 1)
        XCTAssertEqual(observation.probes.filter(\.primary).count, 1)
        XCTAssertGreaterThan(observation.probes.filter { !$0.primary }.count, 0)
        assertFinished(observation, detached: true)
        XCTAssertEqual(ReplayNativeBallPhysics.cacheCountForTesting, 0)
        XCTAssertNil(ReplayNativeBallPhysics.cached(track: scenario.ball, players: scenario.players, plannedTouches: plan))
        try attach(observation.probes.map(\.row), name: "Cancelled")
    }

    func testPrimaryAndAimStartErrorsDetachEveryConstructedWorldWithoutCaching() async throws {
        let scenario = try rebound()
        let plan = try XCTUnwrap(FootballReferenceScenarios.touches(for: scenario))
        var rows: [[String: Any]] = []
        for failPrimary in [true, false] {
            ReplayNativeBallPhysics.resetCacheForTesting()
            let observation = observe { world, construction in
                if construction.includesGoals == failPrimary { world.startErrorForTesting = InjectedFailure.start }
            }
            do {
                _ = try await ReplayNativeBallPhysics.prewarm(track: scenario.ball, players: scenario.players,
                                                              plannedTouches: plan)
                XCTFail("Injected native start error must propagate")
            } catch {
                XCTAssertEqual(error as? InjectedFailure, .start)
            }
            XCTAssertEqual(observation.probes.count, failPrimary ? 1 : 2)
            XCTAssertEqual(observation.probes.filter(\.primary).count, 1)
            assertFinished(observation, detached: true)
            XCTAssertEqual(ReplayNativeBallPhysics.cacheCountForTesting, 0)
            XCTAssertNil(ReplayNativeBallPhysics.cached(track: scenario.ball, players: scenario.players, plannedTouches: plan))
            rows.append(["failedPrimaryStart": failPrimary, "worlds": observation.probes.map(\.row)])
        }
        try attach(rows, name: "StartErrors")
    }

    @discardableResult
    private func observe(legacy: Bool = false, into existingObservation: Observation? = nil,
                         onCreate: ((World, World.ConstructionForTesting) -> Void)? = nil) -> Observation {
        let observation = existingObservation ?? Observation()
        World.creationObserverForTesting = { world, construction in
            world.skipsDetachmentForTesting = legacy
            observation.probes.append(Probe(world, sequence: observation.probes.count + 1,
                                            primary: construction.includesGoals))
            onCreate?(world, construction)
        }
        World.finishObserverForTesting = { world in
            guard let probe = observation.probes.first(where: { $0.world === world }) else {
                XCTFail("Finished world must have been observed at creation")
                return
            }
            probe.finishes += 1
            probe.rootCounts.append(world.renderer.entities.count)
            probe.attachedScenes.append(world.root.scene != nil || world.ball.scene != nil)
            XCTAssertTrue(world.ball.parent === world.root)
            XCTAssertNotNil(world.root.components[PhysicsSimulationComponent.self])
            XCTAssertNotNil(world.ball.components[PhysicsBodyComponent.self])
        }
        return observation
    }

    private func assertFinished(_ observation: Observation, detached: Bool) {
        XCTAssertFalse(observation.probes.isEmpty)
        for probe in observation.probes {
            XCTAssertEqual(probe.finishes, 1, "Exactly one caller-owned finish per world")
            XCTAssertEqual(probe.rootCounts, [detached ? 0 : 1])
            XCTAssertEqual(probe.attachedScenes, [!detached])
            XCTAssertNil(probe.world)
            XCTAssertNil(probe.renderer)
        }
    }

    private func rebound() throws -> ReplayScenario {
        try XCTUnwrap(FootballReferenceScenarios.all.first { $0.id == "final-108-rebound-v2" })
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

    private func attach(_ rows: [[String: Any]], name: String) throws {
        let attachment = XCTAttachment(data: try JSONSerialization.data(withJSONObject: [
            "scope": "Explicit entity detachment before owner release; no simulation tick or component changes",
            "limit": "Does not establish completion of deferred CoreRE destruction or a fix for the intermittent crash",
            "rows": rows
        ], options: [.prettyPrinted, .sortedKeys]), uniformTypeIdentifier: "public.json")
        attachment.name = "NativeWorldDetachment146-\(name)"
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
