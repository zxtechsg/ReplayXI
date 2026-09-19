import RealityKit
import XCTest
import simd
@testable import ReplayXI

@MainActor
final class ReplayTacticalAttentionSeparationTests: XCTestCase {
    override func tearDown() {
        ReplayNativeBallPhysics.resetCacheForTesting()
        ReplaySkinnedAthleteProvider.resetForTesting()
        ReplayAthleteHeadProvider.resetForTesting()
        super.tearDown()
    }

    private func player(_ id: String, team: FootballTeam, position: PitchPoint) -> PlayerTrack {
        .init(id: id, displayName: id, role: "CM", shirtNumber: 8, team: team,
              isGoalkeeper: false, keyframes: [
                .init(time: 0, position: position, facingDegrees: 0),
                .init(time: 30, position: position, facingDegrees: 0)
              ])
    }

    func testBothTeamsFadeCloseNeighboursBeforeNormalizingTheScan() {
        let ball: SIMD3<Float> = [0, 0.11, 18]
        for team in FootballTeam.allCases {
            let observer = player("separation-observer", team: team, position: .zero)
            let otherTeam: FootballTeam = team == .home ? .away : .home
            let background = player("background", team: otherTeam, position: .init(x: -6, z: 6))
            func target(distance: Float, time: Double, includesBackground: Bool = true) -> SIMD3<Float> {
                let neighbour = player("nearby", team: otherTeam, position: .init(x: distance, z: 0))
                let players = includesBackground ? [observer, neighbour, background] : [observer, neighbour]
                let poses = Dictionary(uniqueKeysWithValues: players.map { ($0.id, $0.presentationPose(at: time)) })
                return ReplayAthleteTacticalAttention.target(for: observer, at: time,
                    pose: observer.presentationPose(at: time), ball: ball,
                    players: players, poses: poses, contacts: [])
            }
            for time in stride(from: 0.0, through: 12, by: 0.25) {
                // The old 20 cm hard gate discarded the dominant neighbour in
                // one sample and jumped to the background opponent instead.
                for boundary: Float in [0.20, 0.80, 1.20] {
                    XCTAssertLessThan(simd_distance(target(distance: boundary - 0.0001, time: time),
                                                    target(distance: boundary + 0.0001, time: time)), 0.01)
                }
                for distance: Float in [0, 0.10, 0.20] {
                    XCTAssertEqual(target(distance: distance, time: time, includesBackground: false), ball)
                    // sqrt(distance²) may land one Float ULP above 20 cm.
                    // Its quintic weight is effectively zero, not bitwise zero.
                    XCTAssertLessThan(simd_distance(target(distance: distance, time: time), ball), 0.000001,
                                      "Near-overlapping routes must not invent a background scan")
                }
                var previous = target(distance: 0, time: time)
                for step in 0...120 {
                    let distance = Float(step) / 100
                    let current = target(distance: distance, time: time)
                    XCTAssertLessThan(simd_distance(target(distance: distance - 0.00001, time: time),
                                                    target(distance: distance + 0.00001, time: time)), 0.02)
                    XCTAssertLessThan(simd_distance(current, previous), 0.5)
                    XCTAssertEqual(hypot(current.x, current.z), 18, accuracy: 0.00002)
                    previous = current
                }
            }
        }
    }

    func testVolleyDefenderAndForwardKeepContinuousHeadsAcrossClosePass() async throws {
        try await verifyWindow(scenarioID: "final-81-volley-v2", ids: ["arg-24", "fra-26"],
                               interval: 7.95...8.45, crossings: [8.15...8.20, 8.25...8.30])
    }

    func testUnderlapOpponentsKeepContinuousHeadsAcrossClosePass() async throws {
        try await verifyWindow(scenarioID: "city-57-underlap-cutback", ids: ["city-42", "liv-6"],
                               interval: 4.35...5.0, crossings: [4.50...4.55, 4.80...4.90])
    }

    private func verifyWindow(scenarioID: String, ids: [String], interval: ClosedRange<Double>,
                              crossings: [ClosedRange<Double>]) async throws {
        try ReplaySkinnedAthleteProvider.prewarm()
        try ReplaySkinnedAthleteProvider.prewarmLowDetail()
        let scenario = try XCTUnwrap(FootballReferenceScenarios.all.first { $0.id == scenarioID })
        let players = try ids.map { id in try XCTUnwrap(scenario.player(id: id)) }
        XCTAssertNotEqual(players[0].team, players[1].team)
        let touches = try XCTUnwrap(FootballReferenceScenarios.touches(for: scenario))
        let recording = try await ReplayNativeBallPhysics.bake(
            track: scenario.ball, players: scenario.players, plannedTouches: touches)
        XCTAssertEqual(recording.missedTouchCount, 0)
        // These specific windows are off-ball for both participants. The
        // regression must not invent a new contact or change an authored route.
        XCTAssertFalse(recording.touches.contains {
            ids.contains($0.playerID) && interval.overlaps(($0.time - 0.92)...($0.time + 1.02))
        })

        func separation(_ time: Double) -> Float {
            let a = players[0].presentationPose(at: time).position
            let b = players[1].presentationPose(at: time).position
            return hypot(a.x - b.x, a.z - b.z)
        }
        let boundaries = crossings.map { range -> Double in
            var low = range.lowerBound, high = range.upperBound
            let startsInside = separation(low) < 0.20
            XCTAssertNotEqual(startsInside, separation(high) < 0.20)
            for _ in 0..<28 {
                let middle = (low + high) / 2
                if (separation(middle) < 0.20) == startsInside { low = middle }
                else { high = middle }
            }
            return (low + high) / 2
        }
        var report: [[String: Any]] = []
        for detail in [ReplaySkinnedAthleteProvider.Detail.near, .lowDetail] {
            for player in players {
                let skin = try ReplaySkinnedAthleteProvider.make(for: player, detail: detail)
                let head = try XCTUnwrap(skin.motion.semanticJointIndices["head"])
                let chest = skin.motion.numberAnchors.jointIndex
                let restChest = simd_quatf(skin.motion.restPose.modelSpaceTransforms[chest])
                let restHead = simd_quatf(skin.motion.restPose.modelSpaceTransforms[head])
                func sample(_ time: Double) -> (target: SIMD3<Float>, head: simd_quatf) {
                    let poses = Dictionary(uniqueKeysWithValues: scenario.players.map {
                        ($0.id, $0.presentationPose(at: time))
                    })
                    let pose = player.presentationPose(at: time)
                    let target = ReplayAthleteTacticalAttention.target(for: player, at: time, pose: pose,
                        ball: recording.sample(at: time).position, players: scenario.players, poses: poses, contacts: [])
                    XCTAssertTrue(skin.update(at: time, track: player, locomotion: player.locomotion(at: time),
                        lookTarget: target, ballAction: nil, presentationPose: pose))
                    let chestDelta = simd_quatf(skin.pose.modelSpaceTransforms[chest]) * restChest.inverse
                    let relative = simd_normalize(chestDelta.inverse
                        * simd_quatf(skin.pose.modelSpaceTransforms[head]) * restHead.inverse)
                    let forward = relative.act([0, 0, 1])
                    let yaw = atan2(forward.x, forward.z)
                    let pitch = atan2(-forward.y, hypot(forward.x, forward.z))
                    let swing = simd_quatf(angle: yaw, axis: [0, 1, 0])
                        * simd_quatf(angle: pitch, axis: [1, 0, 0])
                    let right = (swing.inverse * relative).act([1, 0, 0])
                    XCTAssertLessThanOrEqual(abs(yaw) * 180 / .pi, 70.001)
                    XCTAssertLessThanOrEqual(abs(pitch) * 180 / .pi, 40.001)
                    XCTAssertLessThanOrEqual(abs(atan2(right.y, right.x)) * 180 / .pi, 22.001)
                    return (target, relative)
                }
                var largestBoundaryTurn: Float = 0
                for boundary in boundaries {
                    let first = sample(boundary - 0.0001)
                    let second = sample(boundary + 0.0001)
                    let turn = angularDistance(first.head, second.head)
                    largestBoundaryTurn = max(largestBoundaryTurn, turn)
                    XCTAssertLessThan(simd_distance(first.target, second.target), 0.02)
                    XCTAssertLessThan(turn, 0.2, "No head jump at the inner attention radius")
                }
                var largestFrameTurn: Float = 0
                var previous: simd_quatf?
                let times = stride(from: interval.lowerBound, through: interval.upperBound, by: 1.0 / 120).map { $0 }
                var saved: [[Transform]] = []
                var targets: [SIMD3<Float>] = []
                for time in times {
                    let current = sample(time)
                    if let previous { largestFrameTurn = max(largestFrameTurn, angularDistance(previous, current.head)) }
                    previous = current.head
                    saved.append(skin.model.jointTransforms)
                    targets.append(current.target)
                }
                XCTAssertLessThan(largestFrameTurn, 6, "Dense off-ball head poses must stay continuous")
                for index in times.indices.reversed() {
                    XCTAssertEqual(sample(times[index]).target, targets[index])
                    XCTAssertEqual(skin.model.jointTransforms, saved[index])
                }
                report.append(["player": player.id, "detail": String(describing: detail),
                               "maximumBoundaryTurnDegrees": largestBoundaryTurn,
                               "maximum120HzTurnDegrees": largestFrameTurn])
            }
        }
        let attachment = XCTAttachment(data: try JSONSerialization.data(withJSONObject: report, options: [.sortedKeys]),
                                       uniformTypeIdentifier: "public.json")
        attachment.name = "ReplayXI-InnerAttention-\(scenario.id).json"
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    private func angularDistance(_ first: simd_quatf, _ second: simd_quatf) -> Float {
        let a = simd_normalize(first).vector, b = simd_normalize(second).vector
        let chord = min(simd_length(a - b), simd_length(a + b))
        return 4 * asin(min(chord / 2, 1)) * 180 / .pi
    }
}
