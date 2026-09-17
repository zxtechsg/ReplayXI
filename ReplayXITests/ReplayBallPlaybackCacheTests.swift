import Dispatch
import RealityKit
import XCTest
@testable import ReplayXI

@MainActor
final class ReplayBallPlaybackCacheTests: XCTestCase {
    override func setUp() {
        super.setUp()
        ReplayBallPlaybackMotion.resetPreparationCacheForTesting()
    }

    override func tearDown() {
        ReplayBallPlaybackMotion.resetPreparationCacheForTesting()
        super.tearDown()
    }

    private func track(offset: Float = 0) -> BallTrack {
        .init(keyframes: [
            .init(time: 0, position: .init(x: offset, z: 0), height: 0.11),
            .init(time: 1, position: .init(x: offset + 4, z: 0), height: 0.11),
        ])
    }

    func testExactSourceAndPlayerInputsReuseNumericSamplesButNotRootOwnedObjects() throws {
        let scenario = try XCTUnwrap(DemoScenarios.scenario(for: .squadReplay))
        let first = ReplayBallPlaybackMotion.prepared(track: scenario.ball, players: scenario.players)
        let second = ReplayBallPlaybackMotion.prepared(track: scenario.ball, players: scenario.players)
        XCTAssertEqual(ReplayBallPlaybackMotion.preparationCacheMissesForTesting, 1)
        XCTAssertEqual(ReplayBallPlaybackMotion.preparationCacheHitsForTesting, 1)
        XCTAssertEqual(ReplayBallPlaybackMotion.cachedPathCountForTesting, 1)
        XCTAssertFalse(first === second)
        XCTAssertFalse(first.rolling === second.rolling)
        for time in [0.0, 6.2, 13.6, 14.15, 17.5, 25.4, 32, 13.6] {
            XCTAssertEqual(first.pose(at: time), second.pose(at: time))
            XCTAssertEqual(first.rolling.orientation(at: time).vector, second.rolling.orientation(at: time).vector)
        }
        _ = ReplayBallPlaybackMotion.prepared(track: scenario.ball, players: Array(scenario.players.dropLast()))
        XCTAssertEqual(ReplayBallPlaybackMotion.preparationCacheMissesForTesting, 2,
                       "Changed player data must not reuse old obstacle positions")
        _ = ReplayBallPlaybackMotion.prepared(track: track(), players: scenario.players)
        XCTAssertEqual(ReplayBallPlaybackMotion.preparationCacheMissesForTesting, 3,
                       "Changed ball data must not reuse old travel")
    }

    func testCacheHasFourEntryLRUBoundAndDoesNotAdmitMalformedInput() {
        for offset in 0..<4 {
            _ = ReplayBallPlaybackMotion.prepared(track: track(offset: Float(offset)), players: [])
        }
        _ = ReplayBallPlaybackMotion.prepared(track: track(), players: []) // keep zero most recent
        _ = ReplayBallPlaybackMotion.prepared(track: track(offset: 4), players: [])
        XCTAssertEqual(ReplayBallPlaybackMotion.cachedPathCountForTesting, 4)
        XCTAssertEqual(ReplayBallPlaybackMotion.preparationCacheMissesForTesting, 5)
        _ = ReplayBallPlaybackMotion.prepared(track: track(), players: [])
        XCTAssertEqual(ReplayBallPlaybackMotion.preparationCacheHitsForTesting, 2)
        _ = ReplayBallPlaybackMotion.prepared(track: track(offset: 1), players: [])
        XCTAssertEqual(ReplayBallPlaybackMotion.preparationCacheMissesForTesting, 6)
        _ = ReplayBallPlaybackMotion.prepared(track: .init(keyframes: []), players: [])
        XCTAssertEqual(ReplayBallPlaybackMotion.cachedPathCountForTesting, 4)
    }

    func testRootReleaseStillReleasesItsMotionAndRollingWhileNumericCacheLives() throws {
        let scenario = try XCTUnwrap(DemoScenarios.scenario(for: .squadReplay))
        weak var weakRoot: Entity?
        weak var weakMotion: ReplayBallPlaybackMotion?
        weak var weakRolling: ReplayBallRollingMotion?
        autoreleasepool {
            let root = PitchSceneFactory.makeMatchRoot(for: scenario)
            weakRoot = root
            weakMotion = PitchSceneFactory.ballPlaybackMotionForTesting(in: root)
            weakRolling = PitchSceneFactory.ballRollingMotionForTesting(in: root)
            XCTAssertNotNil(weakMotion)
            XCTAssertNotNil(weakRolling)
        }
        XCTAssertNil(weakRoot)
        XCTAssertNil(weakMotion)
        XCTAssertNil(weakRolling)
        XCTAssertEqual(ReplayBallPlaybackMotion.cachedPathCountForTesting, 1)
    }

    func testWarmSceneReuseDoesNotHideTheColdPreparationDiagnostic() throws {
        let scenario = try XCTUnwrap(DemoScenarios.scenario(for: .squadReplay))
        let coldStart = DispatchTime.now().uptimeNanoseconds
        let cold = ReplayBallPlaybackMotion.prepared(track: scenario.ball, players: scenario.players)
        let coldMilliseconds = Double(DispatchTime.now().uptimeNanoseconds - coldStart) / 1_000_000
        let warmStart = DispatchTime.now().uptimeNanoseconds
        let warm = ReplayBallPlaybackMotion.prepared(track: scenario.ball, players: scenario.players)
        let warmMilliseconds = Double(DispatchTime.now().uptimeNanoseconds - warmStart) / 1_000_000
        XCTAssertEqual(cold.pose(at: 13.6), warm.pose(at: 13.6))
        XCTAssertEqual(ReplayBallPlaybackMotion.preparationCacheMissesForTesting, 1)
        XCTAssertEqual(ReplayBallPlaybackMotion.preparationCacheHitsForTesting, 1)
        let direct = ReplayBallPlaybackMotion(track: scenario.ball, players: scenario.players)
        XCTAssertEqual(direct.pose(at: 13.6), cold.pose(at: 13.6))
        XCTAssertEqual(ReplayBallPlaybackMotion.preparationCacheHitsForTesting, 1,
                       "Direct diagnostic init must not become a cache hit")
        let data = try JSONSerialization.data(withJSONObject: [
            "coldPreparationMilliseconds": coldMilliseconds,
            "warmNumericReuseMilliseconds": warmMilliseconds,
            "preparedSamples": cold.sampleCount,
            "scope": "CPU preparation only, not frame rate; same-process one-shot samples",
        ], options: [.sortedKeys])
        let attachment = XCTAttachment(data: data, uniformTypeIdentifier: "public.json")
        attachment.name = "ReplayXI-BallPlayback-Cold-Warm-Preparation.json"
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
