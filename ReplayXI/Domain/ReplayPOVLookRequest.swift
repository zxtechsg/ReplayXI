import Foundation
import simd

/// A deliberate, one-shot virtual heading change. Not eye-gaze tracking.
struct ReplayPOVLookRequest: Equatable {
    let id = UUID()
    let scenarioID: String
    let playerID: String
    let target: SIMD3<Float>

    static func heading(from position: PitchPoint, to target: SIMD3<Float>) -> Float? {
        guard target.x.isFinite, target.y.isFinite, target.z.isFinite else { return nil }
        let delta = SIMD2<Float>(target.x - position.x, target.z - position.z)
        guard simd_length_squared(delta) > 0.0001 else { return nil }
        return atan2(delta.x, delta.y) * 180 / .pi
    }
}

/// Only teleport-like navigation resets the controls, never playhead/head motion.
struct PlaybackControlArrival: Equatable {
    let scenarioID: String
    let view: ReplayViewMode
    let playerID: String
    let lookID: UUID?

    init(scenarioID: String, view: ReplayViewMode, playerID: String, lookID: UUID?) {
        self.scenarioID = scenarioID
        self.view = view
        self.playerID = view == .firstPerson ? playerID : ""
        self.lookID = lookID
    }
}
