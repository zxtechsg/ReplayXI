import Foundation
import RealityKit
import XCTest
@testable import ReplayXI

/// Offline CPU diagnostics for deciding whether a cheaper mesh is sufficient.
/// This deliberately does not change the shipping instance cap or infer FPS.
@MainActor
final class ReplaySkinnedAthleteWorkDiagnosticsTests: XCTestCase {
    private struct Input {
        let time: Double
        let locomotion: PlayerLocomotionSample
        let lookTarget: SIMD3<Float>
        let action: ReplayAthleteBallActionPose?
    }

    func testRecordsSkinPoseCostAtOneFourAndTwentyTwoInstances() throws {
        ReplaySkinnedAthleteProvider.resetForTesting()
        ReplayAthleteHeadProvider.resetForTesting()
        defer {
            ReplaySkinnedAthleteProvider.resetForTesting()
            ReplayAthleteHeadProvider.resetForTesting()
        }
        XCTAssertEqual(ReplaySkinnedAthleteProvider.maximumConcurrentInstances, 4)
        XCTAssertEqual(PitchSceneFactory.firstPersonDetailedRigLimit, 2)
        let scenario = try XCTUnwrap(DemoScenarios.scenario(for: .squadReplay))
        XCTAssertEqual(scenario.players.count, 22)
        let activeIDs = ["navy-rw", "navy-rb", "red-lw", "red-lb"]
        let activePlayers = try activeIDs.map { try XCTUnwrap(scenario.player(id: $0)) }
        let orderedPlayers = activePlayers + scenario.players.filter { !activeIDs.contains($0.id) }
        let start = DispatchTime.now().uptimeNanoseconds
        try ReplaySkinnedAthleteProvider.prewarm()
        let prewarmMilliseconds = milliseconds(since: start)
        let forwardTimes = (0..<32).map { 10.5 + Double($0) * 0.25 }
        let times = forwardTimes + forwardTimes.reversed()
        var results: [[String: Any]] = []
        for count in [1, 4, 22] {
            let players = Array(orderedPlayers.prefix(count))
            let creationStart = DispatchTime.now().uptimeNanoseconds
            let skins = try players.map { try ReplaySkinnedAthleteProvider.make(for: $0) }
            let creationMilliseconds = milliseconds(since: creationStart)
            let mesh = try XCTUnwrap(skins.first?.model.model?.mesh)
            let frames: [[Input]] = times.map { time in
                let ball = scenario.ball.pose(at: time)
                return players.map { player in
                    Input(time: time, locomotion: player.locomotion(at: time),
                          lookTarget: [ball.position.x, ball.height, ball.position.z],
                          action: ReplayAthleteMotion.ballActionPose(for: player, ballTrack: scenario.ball, at: time))
                }
            }
            // Prepare pose buffers before the timed interval. Assertions and
            // track/ball sampling are also outside it, so the measured scope is
            // exactly Instance.update, including contacts and native joint writes.
            for frame in frames.prefix(3) {
                for index in skins.indices {
                    XCTAssertTrue(update(skins[index], player: players[index], input: frame[index]))
                }
            }
            var samples: [Double] = []
            samples.reserveCapacity(frames.count)
            for frame in frames {
                var allSupported = true
                let frameStart = DispatchTime.now().uptimeNanoseconds
                for index in skins.indices {
                    allSupported = update(skins[index], player: players[index], input: frame[index]) && allSupported
                }
                samples.append(milliseconds(since: frameStart))
                XCTAssertTrue(allSupported)
            }
            for skin in skins {
                XCTAssertTrue(skin.model.model?.mesh === mesh)
                XCTAssertEqual(skin.model.jointTransforms.count, 80)
                XCTAssertTrue(skin.model.jointTransforms.allSatisfy { transform in
                    transform.translation.x.isFinite && transform.translation.y.isFinite
                        && transform.translation.z.isFinite && transform.rotation.vector.x.isFinite
                        && transform.rotation.vector.y.isFinite && transform.rotation.vector.z.isFinite
                        && transform.rotation.vector.w.isFinite
                })
            }
            let sorted = samples.sorted()
            XCTAssertEqual(sorted.count, 64)
            XCTAssertTrue(sorted.allSatisfy { $0.isFinite && $0 >= 0 })
            results.append([
                "instances": count,
                "playerIDs": players.map(\.id),
                "jointsPerInstance": 80,
                "measuredFrames": sorted.count,
                "creationMilliseconds": creationMilliseconds,
                "medianGroupUpdateMilliseconds": sorted[sorted.count / 2],
                "p95GroupUpdateMilliseconds": sorted[Int(Double(sorted.count - 1) * 0.95)],
                "maximumGroupUpdateMilliseconds": sorted.last!,
                "contactVerticesPerInstance": skins[0].contactSurface.vertexCount,
                "contactInfluencesPerInstance": skins[0].contactSurface.influenceCount
            ])
        }
        XCTAssertEqual(ReplaySkinnedAthleteProvider.maximumConcurrentInstances, 4)
        XCTAssertEqual(PitchSceneFactory.firstPersonDetailedRigLimit, 2)
        let report: [String: Any] = [
            "scope": "Debug Simulator CPU: existing skin pose, contacts and native joint writes only",
            "excludes": "track sampling, scene traversal, rendering, GPU, compositor and headset work",
            "notFPS": true,
            "shippingCapUnchanged": 4,
            "prewarmMilliseconds": prewarmMilliseconds,
            "samples": results
        ]
        let data = try JSONSerialization.data(withJSONObject: report, options: [.sortedKeys])
        let attachment = XCTAttachment(data: data, uniformTypeIdentifier: "public.json")
        attachment.name = "ReplayXI-Skin105-CPUScaling.json"
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    private func update(_ skin: ReplaySkinnedAthleteInstance, player: PlayerTrack, input: Input) -> Bool {
        skin.update(at: input.time, track: player, locomotion: input.locomotion,
                    lookTarget: input.lookTarget, ballAction: input.action)
    }

    private func milliseconds(since start: UInt64) -> Double {
        Double(DispatchTime.now().uptimeNanoseconds - start) / 1_000_000
    }
}
