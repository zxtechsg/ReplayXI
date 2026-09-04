import CoreGraphics

/// Device-local comfort presets for the head-following Playback console.
/// They never enter shared state: every wearer can choose the angular size and
/// reach distance that works for them without moving another headset's UI.
enum PlaybackControlDeckPreset: String, CaseIterable, Hashable, Sendable {
    case near
    case standard
    case large

    var title: String {
        switch self {
        case .near: "Near"
        case .standard: "Standard"
        case .large: "Large"
        }
    }

    var systemImage: String {
        switch self {
        case .near: "arrow.down.right.and.arrow.up.left"
        case .standard: "rectangle.center.inset.filled"
        case .large: "arrow.up.left.and.arrow.down.right"
        }
    }
}

struct PlaybackControlDeckLayout: Equatable, Sendable {
    let attachmentWidth: CGFloat
    let uniformScale: Float
    let verticalOffset: Float
    let forwardOffset: Float

    /// Keeps the glass panel inside the attachment's transparent safety edge
    /// while allowing accessibility layouts to use the width they requested.
    var contentWidth: CGFloat {
        max(attachmentWidth - 40, 1)
    }

    static func resolve(
        preset: PlaybackControlDeckPreset,
        usesAccessibilityText: Bool
    ) -> PlaybackControlDeckLayout {
        let base: PlaybackControlDeckLayout = switch preset {
        case .near:
            PlaybackControlDeckLayout(
                attachmentWidth: 1_240,
                uniformScale: 0.98,
                verticalOffset: -0.44,
                forwardOffset: -1.00
            )
        case .standard:
            PlaybackControlDeckLayout(
                attachmentWidth: 1_240,
                uniformScale: 1,
                verticalOffset: -0.50,
                forwardOffset: -1.20
            )
        case .large:
            PlaybackControlDeckLayout(
                attachmentWidth: 1_340,
                uniformScale: 1.18,
                verticalOffset: -0.40,
                forwardOffset: -1.12
            )
        }

        guard usesAccessibilityText else { return base }
        return PlaybackControlDeckLayout(
            attachmentWidth: max(base.attachmentWidth, 1_420),
            uniformScale: base.uniformScale * 1.10,
            verticalOffset: min(base.verticalOffset + 0.04, -0.36),
            forwardOffset: min(base.forwardOffset + 0.06, -0.94)
        )
    }
}
