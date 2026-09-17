import Foundation
import simd

/// Bounded inverse launch planning against the same native sphere/pitch
/// solver. Only the proposed initial impulse changes. The actual match world
/// is never moved or steered by these isolated previews.
@MainActor
enum ReplayNativeBallPhysicsAim {
    static let maximumIterations = 3

    static func initialVelocity(from start: SIMD3<Float>, to target: SIMD3<Float>,
                                duration: TimeInterval) -> SIMD3<Float> {
        let elapsed = Float(max(0.18, min(3, duration)))
        let airborne = target.y > 0.25 || start.y > 0.35
        let integral = (1 - exp(-0.055 * elapsed)) / 0.055
        let horizontalGain = airborne ? 1 / integral : (1 + 0.10 * elapsed) / elapsed
        let vertical: Float = airborne
            ? (target.y - start.y + 9.81 * (elapsed - integral) / 0.055) / integral : 0.025
        return [horizontalGain * (target.x - start.x), vertical, horizontalGain * (target.z - start.z)]
    }

    static func velocity(from start: SIMD3<Float>, to target: SIMD3<Float>,
                         duration: TimeInterval, spinScale: Float) throws -> SIMD3<Float> {
        let duration = max(0.18, min(3, duration))
        let elapsed = Float(duration)
        let horizontal = SIMD2<Float>(target.x - start.x, target.z - start.z)
        let distance = simd_length(horizontal)
        let direction = distance > 0.0001 ? horizontal / distance : SIMD2<Float>(0, 1)
        let airborne = target.y > 0.25 || start.y > 0.35
        let damping: Float = 0.055
        let dragIntegral = (1 - exp(-damping * elapsed)) / damping
        var speed = distance / (airborne ? dragIntegral : elapsed) * (airborne ? 1 : (1 + 0.10 * elapsed))
        var vertical = airborne
            ? (target.y - start.y + 9.81 * (elapsed - dragIntegral) / damping) / dragIntegral
            : 0.025
        for iteration in 0..<maximumIterations {
            speed = min(max(speed, 0), 28)
            vertical = min(max(vertical, -11), 11)
            let world = try ReplayNativeBallPhysicsWorld(includeGoals: false)
            world.placeBall(position: [0, max(start.y, ReplayNativeBallPhysics.radius), 0])
            try world.start()
            world.applyContactVelocity([speed, vertical, 0], spinScale: spinScale)
            let count = Int(ceil(duration / ReplayNativeBallPhysics.step))
            for stepIndex in 0..<count {
                let time = Double(stepIndex) * ReplayNativeBallPhysics.step
                try world.advance(min(ReplayNativeBallPhysics.step, duration - time))
            }
            let result = world.sample(at: duration)
            guard result.position.x.isFinite, result.position.y.isFinite else {
                throw ReplayNativeBallPhysics.Failure.nonFiniteSimulation
            }
            let horizontalError = distance - result.position.x
            let verticalError = target.y - result.position.y
            if abs(horizontalError) < 0.025 && (!airborne || abs(verticalError) < 0.035) { break }
            // Native rollout, rather than guessed friction, measures each
            // correction. Do not return an untested extra final adjustment.
            guard iteration + 1 < maximumIterations else { break }
            speed += horizontalError / elapsed * 1.20
            if airborne { vertical += verticalError / dragIntegral }
        }
        var velocity = SIMD3<Float>(direction.x * speed, vertical, direction.y * speed)
        if simd_length(velocity) > 28 { velocity = simd_normalize(velocity) * 28 }
        return velocity
    }
}
