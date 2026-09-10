import Foundation

/// Local presentation cadence for both the dashboard preview and immersive
/// playback. This clock controls how smoothly the headset samples the local timeline.
enum ReplayPresentationClock {
    /// Roughly 60 Hz. This halves the match-time transform step compared with
    /// the former 33 ms loop, including while reviewing at 4×.
    static let activeInterval: Duration = .nanoseconds(16_666_667)

    /// A paused scene does not need to wake at presentation cadence. Fifty
    /// milliseconds keeps play/resume response perceptually immediate while
    /// avoiding an otherwise permanent 30 Hz polling loop.
    static let idleInterval: Duration = .milliseconds(50)

    static func interval(shouldAdvance: Bool) -> Duration {
        shouldAdvance ? activeInterval : idleInterval
    }

    static func seconds(_ duration: Duration) -> TimeInterval {
        Double(duration.components.seconds)
            + (Double(duration.components.attoseconds) / 1e18)
    }
}
