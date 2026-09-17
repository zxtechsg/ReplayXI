import Foundation

/// Review navigation over the exact immutable recording admitted to the scene.
/// It never substitutes authored beat times or starts native preparation.
@MainActor
enum PlaybackBallActionNavigation {
    enum Direction: Equatable { case previous, next }

    struct Source {
        let scenarioID: String
        let recording: ReplayNativeBallPhysics.Recording
    }

    struct Destination: Equatable {
        let scenarioID: String
        let playerID: String
        let time: TimeInterval
        let kind: ReplayNativeBallPhysics.TouchKind

        var title: String {
            switch kind {
            case .receive: "Receive"
            case .pass: "Pass"
            case .shot: "Shot"
            case .header: "Header"
            case .save: "Save"
            case .dribbleTouch: "Touch"
            }
        }

        func summary(in scenario: ReplayScenario) -> String {
            guard let player = scenario.player(id: playerID) else { return title }
            let seconds = time.formatted(.number.precision(.fractionLength(2)))
            return "\(title) · #\(player.shirtNumber) \(player.displayName) · \(seconds)s"
        }
    }

    static func destination(_ direction: Direction, source: Source?, scenario: ReplayScenario,
                            at time: TimeInterval) -> Destination? {
        guard FootballReferenceScenarios.contains(scenario), let source,
              source.scenarioID == scenario.id,
              source.recording.missedTouchCount == 0, source.recording.nativeStepCount > 0,
              scenario.duration.isFinite, scenario.duration > 0, time.isFinite,
              time >= 0, time <= scenario.duration else { return nil }
        // Solver timestamps are exact seek destinations. This tiny tolerance
        // avoids selecting the current contact again without skipping nearby
        // contacts, unlike the legacy cue buttons' 0.2-second window.
        let epsilon = 0.000_001
        var nearest: ReplayNativeBallPhysics.Touch?
        for touch in source.recording.touches.prefix(512) {
            guard touch.kind != .dribbleTouch, touch.time.isFinite,
                  touch.time >= 0, touch.time <= scenario.duration,
                  scenario.player(id: touch.playerID) != nil else { continue }
            switch direction {
            case .previous:
                guard touch.time < time - epsilon else { continue }
                if let nearest, touch.time <= nearest.time { continue }
            case .next:
                guard touch.time > time + epsilon else { continue }
                if let nearest, touch.time >= nearest.time { continue }
            }
            nearest = touch
        }
        return nearest.map { Destination(scenarioID: scenario.id, playerID: $0.playerID,
                                        time: $0.time, kind: $0.kind) }
    }

    @discardableResult
    static func jump(_ direction: Direction, source: Source?, in store: ReplayStore) -> Destination? {
        guard store.canChangePlaybackView,
              let target = destination(direction, source: source,
                  scenario: store.selectedScenario, at: store.playhead) else { return nil }
        store.setPlaying(false, broadcast: false)
        store.seek(to: target.time, broadcast: store.localRole == .coach)
        store.statusMessage = target.summary(in: store.selectedScenario)
        return target
    }
}
