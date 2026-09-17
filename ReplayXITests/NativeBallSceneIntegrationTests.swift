import RealityKit
import simd
import XCTest
@testable import ReplayXI

/// These assertions exercise the actual Factory graph after native preparation.
/// They verify recording consumption and seeking, not football contact quality;
/// planned-touch completeness has its own solver/scenario regression tests.
@MainActor
final class NativeBallSceneIntegrationTests: XCTestCase {
    func testEachPreparedStudyUsesTheNativeRecordingInTableAndPlayerViews() async throws {
        ReplayNativeBallPhysics.resetCacheForTesting()
        defer { ReplayNativeBallPhysics.resetCacheForTesting() }

        for scenario in FootballReferenceScenarios.all {
            let originalTrack = scenario.ball
            let recording = try await prepare(scenario)
            let root = PitchSceneFactory.makeMatchRoot(for: scenario, nativeRecording: recording)
            defer { for child in Array(root.children) { child.removeFromParent() } }
            let attached = try XCTUnwrap(PitchSceneFactory.nativeBallRecordingForTesting(in: root))
            XCTAssertTrue(attached === recording, "\(scenario.id): use the exact prepared recording")
            XCTAssertNil(PitchSceneFactory.ballPlaybackMotionForTesting(in: root))
            XCTAssertNil(PitchSceneFactory.ballRollingMotionForTesting(in: root))

            let times: [Double] = [0, 0.137, 1.263, 2.517, scenario.duration * 0.81, scenario.duration]
            for view: ReplayViewMode in [.tacticalTable, .firstPerson, .touchline] {
                for time in times {
                    let ball = try update(root, scenario: scenario, time: time, view: view)
                    assertBall(ball, matches: recording.sample(at: time), context: "\(scenario.id), \(view), \(time)")
                }
            }
            XCTAssertEqual(scenario.ball, originalTrack, "Scene updates cannot rewrite authored/reference data")
            XCTAssertTrue(PitchSceneFactory.nativeBallRecordingForTesting(in: root) === recording)
        }
    }

    func testPOVChangesAndReverseSeeksKeepTheExactBallSampleAfterCacheEviction() async throws {
        ReplayNativeBallPhysics.resetCacheForTesting()
        defer { ReplayNativeBallPhysics.resetCacheForTesting() }
        let scenario = try XCTUnwrap(FootballReferenceScenarios.all.first { $0.id == "final-81-volley-v2" })
        let recording = try await prepare(scenario)
        let root = PitchSceneFactory.makeMatchRoot(for: scenario, nativeRecording: recording)
        defer { for child in Array(root.children) { child.removeFromParent() } }
        let checkpointTime = 2.417
        let first = try update(root, scenario: scenario, time: checkpointTime, view: .tacticalTable)
        let checkpointPosition = first.position
        let checkpointRotation = first.orientation.vector

        // A live root owns its immutable samples. Eviction only affects later
        // admissions, never an open scene or its repeatable review timeline.
        ReplayNativeBallPhysics.resetCacheForTesting()
        XCTAssertNil(ReplayNativeBallPhysics.cached(track: scenario.ball, players: scenario.players,
            plannedTouches: FootballReferenceScenarios.touches(for: scenario)))
        XCTAssertTrue(PitchSceneFactory.nativeBallRecordingForTesting(in: root) === recording)
        // The asynchronous room gate retains this recording until admission;
        // root creation must not depend on it still being in the global cache.
        let admittedRoot = PitchSceneFactory.makeMatchRoot(for: scenario, nativeRecording: recording)
        defer { for child in Array(admittedRoot.children) { child.removeFromParent() } }
        XCTAssertTrue(PitchSceneFactory.nativeBallRecordingForTesting(in: admittedRoot) === recording)
        let admittedBall = try update(admittedRoot, scenario: scenario, time: checkpointTime, view: .tacticalTable)
        XCTAssertEqual(admittedBall.position, checkpointPosition)
        XCTAssertEqual(admittedBall.orientation.vector, checkpointRotation)

        for player in scenario.players {
            _ = try update(root, scenario: scenario, time: scenario.duration, view: .firstPerson, playerID: player.id)
            _ = try update(root, scenario: scenario, time: 0.31, view: .firstPerson, playerID: player.id)
            let repeated = try update(root, scenario: scenario, time: checkpointTime,
                                      view: .firstPerson, playerID: player.id)
            XCTAssertEqual(repeated.position, checkpointPosition, "Changing to \(player.id) must not change ball physics")
            XCTAssertEqual(repeated.orientation.vector, checkpointRotation,
                           "Rewind must return the exact orientation, not advance live physics")
            assertBall(repeated, matches: recording.sample(at: checkpointTime), context: player.id)
        }
        let table = try update(root, scenario: scenario, time: checkpointTime, view: .tacticalTable)
        XCTAssertEqual(table.position, checkpointPosition)
        XCTAssertEqual(table.orientation.vector, checkpointRotation)
        XCTAssertTrue(PitchSceneFactory.nativeBallRecordingForTesting(in: root) === recording)
        XCTAssertEqual(ReplayNativeBallPhysics.cacheCountForTesting, 0,
                       "A render update cannot rebuild or reinsert a physics recording")
    }

    func testLegacyRootRetainsAuthoredPlaybackWithoutStartingANativeBake() throws {
        ReplayNativeBallPhysics.resetCacheForTesting()
        defer { ReplayNativeBallPhysics.resetCacheForTesting() }
        let scenario = try XCTUnwrap(DemoScenarios.scenario(for: .squadReplay))
        XCTAssertFalse(FootballReferenceScenarios.contains(scenario))
        let root = PitchSceneFactory.makeMatchRoot(for: scenario)
        defer { for child in Array(root.children) { child.removeFromParent() } }
        XCTAssertNil(PitchSceneFactory.nativeBallRecordingForTesting(in: root))
        let fallback = try XCTUnwrap(PitchSceneFactory.ballPlaybackMotionForTesting(in: root))
        let rolling = try XCTUnwrap(PitchSceneFactory.ballRollingMotionForTesting(in: root))
        let time = 2.417
        let ball = try update(root, scenario: scenario, time: time, view: .tacticalTable)
        let expected = fallback.pose(at: time)
        XCTAssertEqual(ball.position, SIMD3<Float>(expected.position.x, max(expected.height, 0.11), expected.position.z))
        assertRotation(ball.orientation, equals: rolling.orientation(at: time), context: "Legacy authored playback")
        XCTAssertEqual(ReplayNativeBallPhysics.cacheCountForTesting, 0)
        XCTAssertNil(PitchSceneFactory.nativeBallRecordingForTesting(in: root))
    }

    private func prepare(_ scenario: ReplayScenario) async throws -> ReplayNativeBallPhysics.Recording {
        try await ReplayNativeBallPhysics.prewarm(track: scenario.ball, players: scenario.players,
            plannedTouches: FootballReferenceScenarios.touches(for: scenario))
    }

    private func update(_ root: Entity, scenario: ReplayScenario, time: Double, view: ReplayViewMode,
                        playerID: String? = nil) throws -> Entity {
        PitchSceneFactory.update(root: root, scenario: scenario, time: time, viewMode: view,
            perspectiveID: playerID ?? scenario.defaultPerspectiveID, marks: [],
            showsLaneLens: false, isDrawing: false, positionalOriginTransform: nil)
        return try XCTUnwrap(root.findEntity(named: "ball"))
    }

    private func assertBall(_ ball: Entity, matches sample: ReplayNativeBallPhysics.Sample,
                            context: String, file: StaticString = #filePath, line: UInt = #line) {
        // The render-only floor guard is intentional: it cannot alter x/z or
        // spin and does not feed back into the recorded native simulation.
        XCTAssertEqual(ball.position.x, sample.position.x, accuracy: 0.000_001, context, file: file, line: line)
        XCTAssertEqual(ball.position.y, max(sample.position.y, ReplayNativeBallPhysics.radius),
                       accuracy: 0.000_001, context, file: file, line: line)
        XCTAssertEqual(ball.position.z, sample.position.z, accuracy: 0.000_001, context, file: file, line: line)
        XCTAssertEqual(ball.scale, SIMD3<Float>(repeating: 1), context, file: file, line: line)
        XCTAssertTrue(ball.isEnabled, context, file: file, line: line)
        assertRotation(ball.orientation, equals: sample.orientation, context: context, file: file, line: line)
    }

    private func assertRotation(_ actual: simd_quatf, equals expected: simd_quatf,
                                context: String, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(simd_length(actual.vector), 1, accuracy: 0.000_01, context, file: file, line: line)
        XCTAssertEqual(abs(simd_dot(actual.vector, expected.vector)), 1,
                       accuracy: 0.000_01, context, file: file, line: line)
    }
}
