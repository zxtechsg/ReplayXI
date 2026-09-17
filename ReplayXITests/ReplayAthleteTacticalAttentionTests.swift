import XCTest
import simd
@testable import ReplayXI

final class ReplayAthleteTacticalAttentionTests: XCTestCase {
    private func player(_ id: String = "marker-4", team: FootballTeam = .away,
                        position: PitchPoint = .zero, keeper: Bool = false) -> PlayerTrack {
        .init(id: id, displayName: id, role: "Defender", shirtNumber: 4,
              team: team, isGoalkeeper: keeper,
              keyframes: [.init(time: 0, position: position, facingDegrees: 0),
                          .init(time: 30, position: position, facingDegrees: 0)])
    }

    private func target(_ track: PlayerTrack, at time: Double, ball: SIMD3<Float> = [0, 0.11, 18],
                        threat: PitchPoint = .init(x: 7, z: 5),
                        contacts: [ReplayAthleteInteractionCue] = []) -> SIMD3<Float> {
        let opponent = player("opponent", team: track.team == .home ? .away : .home, position: threat)
        return ReplayAthleteTacticalAttention.target(
            for: track, at: time, pose: track.presentationPose(at: time), ball: ball,
            players: [track, opponent], poses: [opponent.id: opponent.presentationPose(at: time)],
            contacts: contacts)
    }

    private var contact: ReplayAthleteInteractionCue {
        .init(playerID: "marker-4", kind: .pass, contactTime: 5,
              startTime: 4.68, endTime: 5.42, kickingLeg: .right,
              contactBallWorldPosition: [0, 0.11, 18], outgoingDirectionWorld: [0, 0, 8])
    }

    func testBothTeamsCheckOpponentsWithoutChangingBallRange() {
        for team in FootballTeam.allCases {
            let track = player(team: team)
            var largestChange: Float = 0
            for tick in 0...600 {
                let actual = target(track, at: Double(tick) / 60)
                largestChange = max(largestChange, abs(actual.x))
                XCTAssertEqual(hypot(actual.x, actual.z), 18, accuracy: 0.00001)
                XCTAssertTrue((0.109...1.451).contains(actual.y))
            }
            XCTAssertGreaterThan(largestChange, 5, "Both squads need visible off-ball scanning")
        }
    }

    func testNearBallAndGoalkeepersRetainExactBallAttention() {
        for tick in 0...100 {
            let time = Double(tick) / 10
            XCTAssertEqual(target(player(), at: time, ball: [0, 0.11, 3]), [0, 0.11, 3])
            XCTAssertEqual(target(player(keeper: true), at: time), [0, 0.11, 18])
        }
    }

    func testNoOpponentOrOnlyDistantOpponentDoesNotInventTarget() {
        let track = player()
        XCTAssertEqual(target(track, at: 5, threat: .init(x: 100, z: 100)), [0, 0.11, 18])
        XCTAssertEqual(ReplayAthleteTacticalAttention.target(
            for: track, at: 5, pose: track.presentationPose(at: 5), ball: [0, 0.11, 18],
            players: [track], poses: [:], contacts: []), [0, 0.11, 18])
    }

    func testEveryContactWindowKeepsExactOriginalGazeWithSmoothMargins() {
        for tick in 0...100 {
            let time = contact.startTime + (contact.endTime - contact.startTime) * Double(tick) / 100
            XCTAssertEqual(target(player(), at: time, contacts: [contact]), [0, 0.11, 18])
        }
        for edge in [contact.startTime, contact.endTime] {
            let before = ReplayAthleteTacticalAttention.freedom(at: edge - 0.0001, contacts: [contact])
            let after = ReplayAthleteTacticalAttention.freedom(at: edge + 0.0001, contacts: [contact])
            XCTAssertLessThan(abs(after - before), 0.00001)
        }
        XCTAssertEqual(ReplayAthleteTacticalAttention.freedom(at: 4, contacts: [contact]), 1)
        XCTAssertEqual(ReplayAthleteTacticalAttention.freedom(at: 6.1, contacts: [contact]), 1)
    }

    func testRandomAndReverseSeeksMatchForwardPlayExactly() {
        let track = player()
        let times = [0.0, 0.1, 1.2, 4.5, 4.68, 5, 5.42, 6, 9, 14, 28]
        let samples = times.map { target(track, at: $0, contacts: [contact]) }
        for index in times.indices.reversed() {
            XCTAssertEqual(target(track, at: times[index], contacts: [contact]), samples[index])
        }
        for index in [3, 0, 7, 4, 1, 6, 2, 5, 3, 0] {
            XCTAssertEqual(target(track, at: times[index], contacts: [contact]), samples[index])
        }
    }

    func testPlayersDoNotShareTheSameScanClock() {
        let first = player("marker-4"), second = player("marker-5")
        let largestDifference = (0...600).map {
            simd_distance(target(first, at: Double($0) / 60), target(second, at: Double($0) / 60))
        }.max() ?? 0
        XCTAssertGreaterThan(largestDifference, 2)
    }

    func testRearThreatDoesNotFlipBetweenShoulders() {
        let track = player()
        for tick in 0...100 {
            let time = Double(tick) / 10
            let before = target(track, at: time, threat: .init(x: -0.001, z: -7))
            let after = target(track, at: time, threat: .init(x: 0.001, z: -7))
            XCTAssertLessThan(simd_distance(before, after), 0.0001)
        }
    }

    func testAttentionIsSmoothAtFrameRateAndNeighbourRadius() {
        let track = player()
        var previous = target(track, at: 0, contacts: [contact])
        for tick in 1...2400 {
            let actual = target(track, at: Double(tick) / 120, contacts: [contact])
            XCTAssertLessThan(simd_distance(actual, previous), 0.4, "No one-frame attention jump")
            previous = actual
        }
        // An entering opponent has zero weight at the boundary. With no other
        // opponent, direction is still meaningful; a separate density fade is
        // needed so this case cannot introduce a full-strength scan instantly.
        for tick in 0...100 {
            let time = Double(tick) / 10
            let before = target(track, at: time, threat: .init(x: 16.001, z: 0))
            let after = target(track, at: time, threat: .init(x: 15.999, z: 0))
            XCTAssertLessThan(simd_distance(before, after), 0.01)
        }
    }

    func testInvalidTimeDoesNotContaminateRenderer() {
        for time in [Double.nan, .infinity, -.infinity] {
            XCTAssertEqual(target(player(), at: time), [0, 0.11, 18])
        }
    }
}
