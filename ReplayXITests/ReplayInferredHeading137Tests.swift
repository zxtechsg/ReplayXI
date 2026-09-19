import CryptoKit
import XCTest
import simd
@testable import ReplayXI

/// Freeze inputs before changing inferred headings. These are authored asset
/// fingerprints, not assertions that the reconstruction equals the real match.
@MainActor
final class ReplayInferredHeading137Tests: XCTestCase {
    // Independently captured BEFORE the heading policy in the native baseline
    // run (cycle137-labels-fingerprint). Never regenerate these from new code.
    private let baseline: [String: (positions: String, headings: String)] = [
        "final-36-counter-v2": ("8adcba74cbd17e8f11cc78ca2045e83409d837b24a344e717fac1dc25cacf20d", "2e03b4e17facec65c3d7bf3fa2cf52ef125029dbfad9ed0f2ccccd0e316a5d87"),
        "final-81-volley-v2": ("9af1e9f9958c537d594375750f72f7ad4eeb390a599881a6849be53e3d78f6a7", "01db9c867aa45590a3db7d95d7ebbb579d5a3644f73e7bdc45ec50b87da90c18"),
        "final-108-rebound-v2": ("98ffa9a53a28e1984d642e75e872be784acb022ad838af666bfb186990d4cccf", "1d9e8f5933c9411a2ebe4bc8a1de4607869b5bc1931e1294e5b8029376c99597"),
        "city-45-overlap-header": ("73b62f106fa86288c3eb3a0db92717f841a2839898af0d33163db62840f64296", "b9e9d1a5570e2f1da3348d69831d5f80e197dd56d0e0873a3f48d6dd90513dab"),
        "city-57-underlap-cutback": ("2411fdb65ae641179b1b20004c1bc00c6f3effe724ecfc8137e3dbcfbafc454b", "3447f1bb3f4d62420fd667ddcbf820ad15d68196e612acf1cc884efe1633456c"),
        "final-36-counter": ("dfce492a0c6112e096cbd037a3e7c7ebb9a9640b1c7ee3f559048302db444c82", "caeb8f318dd8152f3481b1e6536d2265609a66430f72db87888680c401f9ee38"),
        "final-81-volley": ("8309bc760630e0b952e94f476d3df6a0f944df258f0d31e8d81e42bdc4f815d3", "821b58f836f2b1831dd94d6e56325c63b5779ddf3e618d3fe36b41d1a0f53a1c"),
        "final-108-rebound": ("55b6e3f11d80390c8d878f45a6ce25d65bbbb208e4e393a57067854760d2227d", "c9865b41faf2841fe8a2807182b447402f279c4dee9d97e396224072fa4d5626")
    ]

    func testAllFiveAndLegacyPositionAndProtectedHeadingFingerprints() throws {
        var rows: [[String: Any]] = []
        for scenario in FootballReferenceScenarios.all + FootballReferenceScenarios.legacy {
            let participants = Set((FootballReferenceScenarios.touches(for: scenario) ?? []).map(\.playerID))
            let explicit: Set<String> = scenario.id == "final-81-volley-v2" ? ["arg-26"] : []
            let legacy = !FootballReferenceScenarios.ids.contains(scenario.id)
            var positions = SHA256(), protectedHeadings = SHA256(), allHeadings = SHA256()
            var protectedPlayers: [String] = []
            for track in scenario.players.sorted(by: { $0.id < $1.id }) {
                let protected = legacy || track.isGoalkeeper || participants.contains(track.id) || explicit.contains(track.id)
                if protected { protectedPlayers.append(track.id) }
                feed(track.id, to: &positions)
                feed(track.id, to: &allHeadings)
                if protected { feed(track.id, to: &protectedHeadings) }
                for frame in track.keyframes {
                    feed("k:\(frame.time.bitPattern):\(frame.position.x.bitPattern):\(frame.position.z.bitPattern)", to: &positions)
                    let heading = "k:\(frame.time.bitPattern):\(frame.facingDegrees.bitPattern)"
                    feed(heading, to: &allHeadings)
                    if protected { feed(heading, to: &protectedHeadings) }
                }
                // Also protects runtime interpolation, not just10Hz waypoints.
                for index in 0...Int(ceil(scenario.duration * 120)) {
                    let time = min(Double(index) / 120, scenario.duration)
                    let pose = track.presentationPose(at: time)
                    feed("p:\(time.bitPattern):\(pose.position.x.bitPattern):\(pose.position.z.bitPattern)", to: &positions)
                    let heading = "p:\(time.bitPattern):\(pose.facingDegrees.bitPattern)"
                    feed(heading, to: &allHeadings)
                    if protected { feed(heading, to: &protectedHeadings) }
                }
            }
            let expected = try XCTUnwrap(baseline[scenario.id])
            XCTAssertEqual(hex(positions), expected.positions, "Every authored and interpolated position remains exact: \(scenario.id)")
            XCTAssertEqual(hex(protectedHeadings), expected.headings, "Contact actors/GKs/authored facing and legacy stay exact: \(scenario.id)")
            rows.append(["scenario": scenario.id, "legacy": legacy, "protectedPlayers": protectedPlayers,
                         "positionsSHA256": hex(positions), "protectedHeadingsSHA256": hex(protectedHeadings),
                         "allHeadingsSHA256": hex(allHeadings)])
        }
        XCTAssertEqual(rows.count, 8)
        let receipt = XCTAttachment(data: try JSONSerialization.data(withJSONObject: rows, options: [.sortedKeys]),
                                    uniformTypeIdentifier: "public.json")
        receipt.name = "ReplayXI-InferredHeading137-BaselineFingerprints.json"
        receipt.lifetime = .keepAlways
        add(receipt)
    }

    func testAllFiveInferredFastRunDirectionDistributionAndRuntimeTurnBound() throws {
        var rows: [[String: Any]] = []
        var allFastSamples = 0, allBeyond90 = 0
        var allYaw: Float = 0
        for scenario in FootballReferenceScenarios.all {
            let participants = Set((FootballReferenceScenarios.touches(for: scenario) ?? []).map(\.playerID))
            for team in FootballTeam.allCases {
                let players = scenario.players.filter {
                    $0.team == team && !$0.isGoalkeeper && !participants.contains($0.id)
                        && !(scenario.id == "final-81-volley-v2" && $0.id == "arg-26")
                }
                var total = 0, beyond90 = 0, beyond135 = 0
                var sumYaw: Float = 0, maxYaw: Float = 0, maxRate: Float = 0
                for track in players {
                    var previousHeading: Float?
                    var previousTime: Double?
                    var playerCount = 0, playerBeyond90 = 0
                    var playerMaxYaw: Float = 0, playerRate: Float = 0
                    for index in 0...Int(ceil(scenario.duration * 120)) {
                        let time = min(Double(index) / 120, scenario.duration)
                        let pose = track.presentationPose(at: time)
                        if let previousHeading, let previousTime, time > previousTime {
                            // Check actual interpolated orientation, including
                            // wrap boundaries, not just10Hz waypoint increments.
                            let rawStep = pose.facingDegrees - previousHeading
                            let radians = rawStep * .pi / 180
                            let turn = abs(atan2(sin(radians), cos(radians))) * 180 / .pi / Float(time - previousTime)
                            XCTAssertLessThanOrEqual(turn, 215, "\(scenario.id) \(track.id) \(time)")
                            XCTAssertLessThanOrEqual(abs(rawStep), 215 * Float(time - previousTime) + 0.0001,
                                "The unwrapped heading stream must not jump360°")
                            playerRate = max(playerRate, turn)
                            maxRate = max(maxRate, turn)
                        }
                        previousHeading = pose.facingDegrees
                        previousTime = time
                        let before = track.presentationPose(at: time - 0.08).position
                        let after = track.presentationPose(at: time + 0.08).position
                        let velocity = SIMD2<Float>((after.x - before.x) / 0.16, (after.z - before.z) / 0.16)
                        let speed = simd_length(velocity)
                        guard speed > 4.5 else { continue }
                        let direction = atan2(velocity.x, velocity.y) - pose.facingDegrees * .pi / 180
                        let yaw = abs(atan2(sin(direction), cos(direction))) * 180 / .pi
                        total += 1; playerCount += 1
                        if yaw > 90 { beyond90 += 1; playerBeyond90 += 1 }
                        if yaw > 135 { beyond135 += 1 }
                        sumYaw += yaw
                        maxYaw = max(maxYaw, yaw)
                        playerMaxYaw = max(playerMaxYaw, yaw)
                    }
                    rows.append(["scenario": scenario.id, "team": team.rawValue, "player": track.id,
                        "fastSamples": playerCount, "beyond90Samples": playerBeyond90,
                        "maxTravelYaw": playerMaxYaw, "maxRuntimeHeadingDegreesPerSecond": playerRate])
                }
                rows.append(["summary": true, "scenario": scenario.id, "team": team.rawValue,
                    "admittedPlayers": players.count, "fastSamples": total, "beyond90Samples": beyond90,
                    "beyond135Samples": beyond135, "meanTravelYaw": total > 0 ? sumYaw / Float(total) : 0,
                    "maxTravelYaw": maxYaw, "maxRuntimeHeadingDegreesPerSecond": maxRate])
                allFastSamples += total
                allBeyond90 += beyond90
                allYaw += sumYaw
                if scenario.id == "final-36-counter-v2", team == .away {
                    // Independent native baseline:145.55° maximum,51 samples
                    // beyond90°. Do not merely shift the problem to another run.
                    XCTAssertLessThan(maxYaw, 15)
                } else {
                    // Other admitted fast runs were already aligned (baseline
                    // maximum11.27°). Do not replace them with sideways sprints.
                    XCTAssertLessThan(maxYaw, 16)
                }
            }
        }
        XCTAssertEqual(allFastSamples, 5_854, "Unchanged routes imply unchanged fast-run coverage")
        XCTAssertEqual(allBeyond90, 0, "No admitted fast run may still face backwards")
        XCTAssertLessThan(allYaw / Float(allFastSamples), 1,
            "Baseline mean≈1.90° overall5; require a material aggregate improvement")
        let receipt = XCTAttachment(data: try JSONSerialization.data(withJSONObject: rows, options: [.sortedKeys]),
                                    uniformTypeIdentifier: "public.json")
        receipt.name = "ReplayXI-InferredHeading137-DirectionDistribution.json"
        receipt.lifetime = .keepAlways
        add(receipt)
    }

    func testHeadingWrapIsContinuousAtRuntimeAndGenerationIsDeterministic() {
        let frames: [MotionKeyframe] = (0...30).map { index in
            let time = Double(index) / 10
            return .init(time: time, position: .init(x: Float(sin(time * 2)) * 0.2, z: Float(-5 * time)),
                         facingDegrees: 179)
        }
        let route = PlayerTrack(id: "seam", displayName: "Seam", role: "CB", shirtNumber: 4,
            team: .away, isGoalkeeper: false, keyframes: frames)
        let ball = BallTrack(keyframes: [.init(time: 0, position: .init(x: 10, z: -15), height: 0.11),
                                        .init(time: 3, position: .init(x: -10, z: -15), height: 0.11)])
        let result = ReplayInferredRunningHeading.applying(to: frames, route: route, ball: ball)
        XCTAssertEqual(result, ReplayInferredRunningHeading.applying(to: frames, route: route, ball: ball))
        XCTAssertEqual(result.map(\.position), frames.map(\.position))
        XCTAssertEqual(result.map(\.time), frames.map(\.time))
        let player = PlayerTrack(id: route.id, displayName: route.displayName, role: route.role,
            shirtNumber: route.shirtNumber, team: route.team, isGoalkeeper: false, keyframes: result)
        var previous: Float?
        var saved: [PlayerPose] = []
        for index in 0...360 {
            let pose = player.presentationPose(at: Double(index) / 120)
            XCTAssertTrue((160...200).contains(pose.facingDegrees), "No long way around the180° seam")
            if let previous { XCTAssertLessThanOrEqual(abs(pose.facingDegrees - previous) * 120, 215) }
            previous = pose.facingDegrees
            saved.append(pose)
        }
        for index in saved.indices.reversed() {
            XCTAssertEqual(player.presentationPose(at: Double(index) / 120), saved[index])
        }
    }

    private func feed(_ value: String, to hash: inout SHA256) {
        hash.update(data: Data((value + "\n").utf8))
    }

    private func hex(_ hash: SHA256) -> String {
        hash.finalize().map { String(format: "%02x", $0) }.joined()
    }
}
