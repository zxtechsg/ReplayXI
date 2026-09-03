import CoreGraphics
import Foundation

/// Deterministic translation-to-time mapping for the immersive replay rail.
///
/// Horizontal movement scrubs the whole replay. Moving the pinch vertically
/// away from the rail lowers the gain, which lets a coach land on a frame
/// without needing a second, tiny control. This type deliberately owns no UI or
/// store state so gesture previews and commits always use identical math.
enum PlaybackTimelineScrub {
    enum Precision: String, Equatable, Sendable {
        case coarse = "COARSE"
        case fine = "FINE"
        case frame = "FRAME"
    }

    struct GestureState: Equatable, Sendable {
        let time: TimeInterval
        let precision: Precision
        fileprivate let previousHorizontalTranslation: Double
    }

    static let accessibilityStep: TimeInterval = 1

    static func begin(
        at time: TimeInterval,
        duration: TimeInterval
    ) -> GestureState {
        let safeDuration = duration.isFinite ? max(duration, 0) : 0
        let safeTime = time.isFinite ? min(max(time, 0), safeDuration) : 0
        return GestureState(
            time: safeTime,
            precision: .coarse,
            previousHorizontalTranslation: 0
        )
    }

    /// Integrates only the horizontal distance since the previous gesture
    /// sample. Changing vertical precision therefore never changes time by
    /// itself; the new gain applies only to horizontal movement that follows.
    static func update(
        _ state: GestureState,
        duration: TimeInterval,
        railWidth: CGFloat,
        horizontalTranslation: CGFloat,
        verticalTranslation: CGFloat
    ) -> GestureState {
        let safeDuration = duration.isFinite ? max(duration, 0) : 0
        let safeTime = state.time.isFinite
            ? min(max(state.time, 0), safeDuration)
            : 0
        guard railWidth.isFinite, railWidth > 0,
              horizontalTranslation.isFinite,
              verticalTranslation.isFinite else {
            return GestureState(
                time: safeTime,
                precision: state.precision,
                previousHorizontalTranslation: state.previousHorizontalTranslation
            )
        }

        let precision = precision(forVerticalTravel: abs(verticalTranslation))
        let gain = gain(forVerticalTravel: abs(verticalTranslation))
        let currentHorizontalTranslation = Double(horizontalTranslation)
        let incrementalHorizontalTranslation = currentHorizontalTranslation
            - state.previousHorizontalTranslation
        let translatedSeconds = incrementalHorizontalTranslation / Double(railWidth)
            * safeDuration
            * gain
        return GestureState(
            time: min(max(safeTime + translatedSeconds, 0), safeDuration),
            precision: precision,
            previousHorizontalTranslation: currentHorizontalTranslation
        )
    }

    static func precision(forVerticalTravel travel: CGFloat) -> Precision {
        guard travel.isFinite else { return .coarse }
        if travel >= 96 { return .frame }
        if travel >= 42 { return .fine }
        return .coarse
    }

    /// A continuous gain curve prevents the playhead from snapping backward
    /// when the gesture crosses the labels' coarse/fine/frame thresholds.
    static func gain(forVerticalTravel travel: CGFloat) -> Double {
        guard travel.isFinite else { return 1 }
        let safeTravel = max(travel, 0)
        if safeTravel <= 42 {
            return smoothInterpolate(from: 1, to: 0.25, progress: Double(safeTravel / 42))
        }
        if safeTravel <= 96 {
            return smoothInterpolate(
                from: 0.25,
                to: 0.08,
                progress: Double((safeTravel - 42) / 54)
            )
        }
        return 0.08
    }

    private static func smoothInterpolate(
        from start: Double,
        to end: Double,
        progress: Double
    ) -> Double {
        let clampedProgress = min(max(progress, 0), 1)
        let easedProgress = clampedProgress * clampedProgress * (3 - 2 * clampedProgress)
        return start + (end - start) * easedProgress
    }

    static func adjustedTime(
        _ time: TimeInterval,
        direction: Int,
        duration: TimeInterval
    ) -> TimeInterval {
        let safeDuration = duration.isFinite ? max(duration, 0) : 0
        let safeTime = time.isFinite ? min(max(time, 0), safeDuration) : 0
        let directionSign = direction == 0 ? 0 : (direction > 0 ? 1.0 : -1.0)
        return min(
            max(safeTime + directionSign * accessibilityStep, 0),
            safeDuration
        )
    }
}
