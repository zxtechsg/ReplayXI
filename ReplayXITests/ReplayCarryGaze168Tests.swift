import XCTest
@testable import ReplayXI

final class ReplayCarryGaze168Tests: XCTestCase {
    private func runner(id: String, team: FootballTeam = .home,
                        isGoalkeeper: Bool = false) -> PlayerTrack {
        let bearing: Float = 30 * .pi / 180
        let velocity = SIMD2<Float>(sin(bearing), cos(bearing)) * 2
        return PlayerTrack(id: id, displayName: "Carry gaze", role: "RW",
            shirtNumber: 7, team: team, isGoalkeeper: isGoalkeeper,
            keyframes: [
                .init(time: 0, position: .init(x: -velocity.x * 5, z: -velocity.y * 5), facingDegrees: 0),
                .init(time: 10, position: .init(x: velocity.x * 5, z: velocity.y * 5), facingDegrees: 0)
            ])
    }

    private func look(_ player: PlayerTrack, distance: Float, height: Float = 0.11,
                      bearing: Float = 48, time: Double = 5,
                      contactAttention: Float = 0) -> ReplayAthleteLookPose {
        let radians = bearing * .pi / 180
        return ReplayAthleteMotion.lookPose(for: player, at: time,
            targetWorldPosition: [sin(radians) * distance, height, cos(radians) * distance],
            contactAttention: contactAttention)
    }

    func testBallCrossingPlayerPositionKeepsTravelYawContinuous() {
        for team in [FootballTeam.home, .away] {
            for number in 0..<12 {
                let player = runner(id: "carry-gaze-seam-\(team.rawValue)-\(number)", team: team)
                for time: Double in [0.11, 0.8, 1.55, 3.7, 5, 7.4, 9.89] {
                    let position = player.presentationPose(at: time).position
                    let before = ReplayAthleteMotion.lookPose(for: player, at: time,
                        targetWorldPosition: [position.x, 0.11, position.z + 0.0009])
                    let after = ReplayAthleteMotion.lookPose(for: player, at: time,
                        targetWorldPosition: [position.x, 0.11, position.z + 0.0011])
                    let noTarget = ReplayAthleteMotion.lookPose(for: player, at: time)
                    XCTAssertLessThan(abs(after.combinedYawRadians - before.combinedYawRadians), 0.005,
                                      "\(player.id) at \(time)")
                    XCTAssertEqual(before.combinedYawRadians, noTarget.combinedYawRadians,
                                   accuracy: 0.0001)
                }
            }
        }
    }

    func testGazeJoinsAcrossNearBallDistanceBands() {
        let player = runner(id: "carry-gaze-bands-home")
        for boundary: Float in [0.001, 0.015, 0.24, 0.82, 1.68, 1.8, 3.15, 4.0, 4.85] {
            let before = look(player, distance: max(0, boundary - 0.0005))
            let after = look(player, distance: boundary + 0.0005)
            XCTAssertLessThan(abs(after.combinedYawRadians - before.combinedYawRadians), 0.01,
                              "yaw discontinuity at \(boundary) m")
            XCTAssertLessThan(abs(after.combinedPitchRadians - before.combinedPitchRadians), 0.01,
                              "pitch discontinuity at \(boundary) m")
        }
    }

    func testGroundBallCarryKeepsHeadUpWhileElevatedAndFarGazeRemain() {
        let player = runner(id: "carry-gaze-pitch-home")
        let neutral = ReplayAthleteMotion.lookPose(for: player, at: 5)
        let nearGround = look(player, distance: 0.6)
        let nearElevated = look(player, distance: 0.6, height: 1.45)
        let farGround = look(player, distance: 8)
        let groundDegrees = (nearGround.combinedPitchRadians - neutral.combinedPitchRadians) * 180 / .pi
        XCTAssertGreaterThan(groundDegrees, 7)
        XCTAssertLessThanOrEqual(groundDegrees, 12)
        let elevatedExpected = atan2(Float(0.25), Float(0.6)) * 0.52
        XCTAssertEqual(nearElevated.combinedPitchRadians - neutral.combinedPitchRadians,
                       elevatedExpected, accuracy: 0.001)
        let farExpected = atan2(Float(1.59), Float(8)) * 0.72
        XCTAssertEqual(farGround.combinedPitchRadians - neutral.combinedPitchRadians,
                       farExpected, accuracy: 0.001)
    }

    func testContactProtectionRestoresFullNearBallPitchAndKeeperKeepsOriginalGaze() {
        let player = runner(id: "carry-gaze-contact-home")
        let normal = look(player, distance: 0.6)
        let half = look(player, distance: 0.6, contactAttention: 0.5)
        let contact = look(player, distance: 0.6, contactAttention: 1)
        XCTAssertLessThan(normal.combinedPitchRadians, half.combinedPitchRadians)
        XCTAssertLessThan(half.combinedPitchRadians, contact.combinedPitchRadians)
        XCTAssertGreaterThan(contact.combinedPitchRadians * 180 / .pi, 20)
        XCTAssertEqual(normal.combinedYawRadians, contact.combinedYawRadians)

        let keeper = runner(id: "carry-gaze-keeper-home", isGoalkeeper: true)
        XCTAssertEqual(look(keeper, distance: 0.6),
                       look(keeper, distance: 0.6, contactAttention: 1))
    }

    func testGazeIsExactOnRepeatedAndReverseSeeksForBothTeams() {
        for (id, team) in [("carry-gaze-home", FootballTeam.home), ("carry-gaze-away", .away)] {
            let player = runner(id: id, team: team)
            let times: [Double] = [0.3, 2.1, 5, 7.6, 9.8]
            let distances: [Float] = [0.0009, 0.0011, 0.6, 1.8, 8]
            let expected = zip(times, distances).map { look(player, distance: $0.1, time: $0.0) }
            for index in times.indices.reversed() {
                XCTAssertEqual(look(player, distance: distances[index], time: times[index]), expected[index])
            }
        }
    }
}
