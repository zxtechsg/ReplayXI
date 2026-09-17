import Foundation
import simd

/// An authored presentation cue, not recovered player eye tracking. Off-ball
/// players briefly check the nearby opposing line, then return to the ball.
/// Absolute time makes forward play, reverse play and random seeks identical.
enum ReplayAthleteTacticalAttention {
    static func target(
        for player: PlayerTrack,
        at time: TimeInterval,
        pose: PlayerPose,
        ball: SIMD3<Float>,
        players: [PlayerTrack],
        poses: [String: PlayerPose],
        contacts: [ReplayAthleteInteractionCue]
    ) -> SIMD3<Float> {
        guard time.isFinite, finite(ball), pose.position.x.isFinite,
              pose.position.z.isFinite, !player.isGoalkeeper else { return ball }
        let offset = SIMD2<Float>(ball.x - pose.position.x, ball.z - pose.position.z)
        let distance = simd_length(offset)
        // Ball handling and nearby pressure take priority over an invented scan.
        let ballPriority = smooth((distance - 3.25) / 9)
        guard ballPriority > 0 else { return ball }
        let contactFreedom = freedom(at: time, contacts: contacts)
        guard contactFreedom > 0 else { return ball }

        var weightedDirection = SIMD2<Float>.zero
        var weightSum: Float = 0
        var threatPresence: Float = 0
        // Reuse the renderer's prepared poses. No Entity traversal, sorting,
        // resampling of tracks, or temporary neighbour arrays per frame.
        for other in players where other.team != player.team && !other.isGoalkeeper {
            guard let otherPose = poses[other.id] else { continue }
            let delta = SIMD2<Float>(otherPose.position.x - pose.position.x,
                                     otherPose.position.z - pose.position.z)
            let squaredDistance = simd_length_squared(delta)
            guard squaredDistance.isFinite, squaredDistance > 0.04,
                  squaredDistance < 256 else { continue }
            let proximity = 1 - smooth((sqrt(squaredDistance) - 5) / 11)
            let weight = proximity / ((squaredDistance + 4) * (squaredDistance + 4))
            weightedDirection += delta * weight
            weightSum += weight
            threatPresence = max(threatPresence, proximity)
        }
        guard weightSum > 0 else { return ball }
        let threat = weightedDirection / weightSum
        let threatDistance = simd_length(threat)
        guard threatDistance > 0.01 else { return ball }

        let ballBearing = atan2(offset.x, offset.y)
        let threatBearing = atan2(threat.x, threat.y)
        let delta = atan2(sin(threatBearing - ballBearing), cos(threatBearing - ballBearing))
        // A rear-axis crossing must not switch shoulders instantly. Fade the
        // inferred cue to zero around ±pi, like the bounded cervical solver.
        let rearFade = 1 - smooth((abs(delta) * 180 / .pi - 100) / 80)
        let closeThreat = smooth((threatDistance - 0.2) / 0.8)
        let seed = stableSeed(player.id)
        let period = 5.8 + Double(seed % 251) / 100
        let phase = Double(seed % 1021) / 1021 * 2 * Double.pi
        let clock = min(max(time, -1_000_000), 1_000_000)
        let glance = smooth(Float((cos(clock * 2 * .pi / period + phase) - 0.1) / 0.8))
        let weight = 0.85 * glance * rearFade * closeThreat * threatPresence * ballPriority * contactFreedom
        guard weight > 0 else { return ball }
        let bearing = ballBearing + min(max(delta, -.pi / 3), .pi / 3) * weight
        // Keep horizontal range unchanged: scanning must not fool the separate
        // footwork/readiness solver into thinking the ball suddenly got closer.
        return [pose.position.x + sin(bearing) * distance,
                ball.y + (1.45 - ball.y) * weight,
                pose.position.z + cos(bearing) * distance]
    }

    static func freedom(at time: TimeInterval, contacts: [ReplayAthleteInteractionCue]) -> Float {
        var result: Float = 1
        for cue in contacts {
            guard cue.startTime.isFinite, cue.endTime.isFinite,
                  cue.endTime >= cue.startTime else { continue }
            let outside = max(cue.startTime - time, time - cue.endTime, 0)
            result = min(result, smooth(Float(outside / 0.6)))
        }
        return result
    }

    private static func stableSeed(_ id: String) -> UInt32 {
        id.utf8.reduce(UInt32(2_166_136_261)) { ($0 ^ UInt32($1)) &* 16_777_619 }
    }

    private static func smooth(_ value: Float) -> Float {
        let x = min(max(value, 0), 1)
        return x * x * x * (x * (x * 6 - 15) + 10)
    }

    private static func finite(_ value: SIMD3<Float>) -> Bool {
        value.x.isFinite && value.y.isFinite && value.z.isFinite
    }
}
