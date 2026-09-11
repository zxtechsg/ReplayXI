import CoreGraphics

/// Comfort presets for the room-anchored Playback console. Offsets are relative
/// to the captured workspace origin, not the wearer's current head position.
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

/// A small room-anchored surface for view and overlay choices.
/// Its negative horizontal offset keeps it in the upper-left comfort quadrant
/// without covering either the replayed player's sightline or the transport.
struct PlaybackViewHUDLayout: Equatable, Sendable {
    let attachmentWidth: CGFloat
    let horizontalOffset: Float
    let verticalOffset: Float
    let forwardOffset: Float
    let uniformScale: Float

    static func resolve(
        preset: PlaybackControlDeckPreset,
        usesAccessibilityText: Bool
    ) -> PlaybackViewHUDLayout {
        let base: PlaybackViewHUDLayout = switch preset {
        case .near:
            PlaybackViewHUDLayout(
                attachmentWidth: 500,
                horizontalOffset: -0.54,
                verticalOffset: 0.20,
                forwardOffset: -1.00,
                uniformScale: 0.96
            )
        case .standard:
            PlaybackViewHUDLayout(
                attachmentWidth: 500,
                horizontalOffset: -0.64,
                verticalOffset: 0.22,
                forwardOffset: -1.18,
                uniformScale: 1
            )
        case .large:
            PlaybackViewHUDLayout(
                attachmentWidth: 540,
                horizontalOffset: -0.62,
                verticalOffset: 0.21,
                forwardOffset: -1.10,
                uniformScale: 1.10
            )
        }

        guard usesAccessibilityText else { return base }
        return PlaybackViewHUDLayout(
            attachmentWidth: max(base.attachmentWidth, 600),
            horizontalOffset: base.horizontalOffset + 0.04,
            verticalOffset: base.verticalOffset - 0.02,
            forwardOffset: base.forwardOffset + 0.04,
            uniformScale: min(base.uniformScale * 1.08, 1.20)
        )
    }
}
