import Foundation

/// Continuous source-clip weight for a track already admitted by the caller.
/// Actor/contact/impact eligibility remains with the caller. Travel yaw is
/// supplied separately; PlayerMotionState has scalars, not a heading.
enum ReplaySlowRunAdmission {
    static func weight(locomotion: PlayerLocomotionSample) -> Float {
        let motion = locomotion.motion
        let speed = locomotion.speedMetresPerSecond
        guard speed.isFinite, speed >= 0,
              motion.speedMetresPerSecond.isFinite, motion.speedMetresPerSecond >= 0,
              motion.distanceTravelled.isFinite, motion.locomotionPhase.isFinite,
              locomotion.accelerationMetresPerSecondSquared.isFinite,
              locomotion.turnRateDegreesPerSecond.isFinite else { return 0 }
        let turn = abs(locomotion.turnRateDegreesPerSecond)
        guard speed > 1, speed < 2.9, turn < 38 else { return 0 }

        let speedWeight: Float
        if speed < 1.9 {
            speedWeight = quintic((speed - 1) / (1.9 - 1))
        } else if speed > 2.2 {
            speedWeight = 1 - quintic((speed - 2.2) / (2.9 - 2.2))
        } else {
            speedWeight = 1
        }
        let turnWeight: Float = turn <= 20 ? 1 : 1 - quintic((turn - 20) / (38 - 20))
        // Do not gate on walk/jog classification: its discrete threshold lies
        // inside the speed ramp and would reintroduce a source-weight jump.
        return min(max(speedWeight * turnWeight, 0), 1)
    }

    static func directionWeight(localTravelYaw: Float) -> Float {
        guard localTravelYaw.isFinite else { return 0 }
        let yaw = abs(localTravelYaw)
        guard yaw < 0.72 else { return 0 }
        guard yaw > 0.22 else { return 1 }
        return 1 - quintic((yaw - 0.22) / (0.72 - 0.22))
    }

    private static func quintic(_ fraction: Float) -> Float {
        // Evaluate the polynomial in Double to avoid Float cancellation near
        // its flat endpoints; the public weight and animation remain Float.
        let t = Double(min(max(fraction, 0), 1))
        return Float(min(max(t * t * t * (t * (t * 6 - 15) + 10), 0), 1))
    }
}
