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

/// Native symbol bounds need more width than the old 34 pt mode frame at
/// regular XXXL and AX sizes. This changes labels only, not the room anchor.
struct PlaybackViewHUDSymbolLayout: Equatable, Sendable {
    let modeIconWidth: CGFloat
    let disclosureIconWidth: CGFloat
    let overlayBadgeDiameter: CGFloat

    static func resolve(usesAccessibilityText: Bool) -> PlaybackViewHUDSymbolLayout {
        PlaybackViewHUDSymbolLayout(
            modeIconWidth: usesAccessibilityText ? 64 : 40,
            disclosureIconWidth: 34,
            overlayBadgeDiameter: usesAccessibilityText ? 40 : 28
        )
    }
}

/// Secondary controls may use extra room without widening the main transport.
/// AX label budgets cover the measured largest caption/headline and speed text;
/// the rate grid also reserves horizontal room for the system button style.
struct PlaybackSecondaryControlLayout: Equatable, Sendable {
    let usesAdaptiveRates: Bool
    let presetLabelWidth: CGFloat
    let presetLabelMinimumHeight: CGFloat
    let rateLabelWidth: CGFloat
    let rateLabelMinimumHeight: CGFloat
    let rateMinimumTextScale: CGFloat

    static let rateGridSpacing: CGFloat = 8
    var rateGridMinimumCellWidth: CGFloat { rateLabelWidth + 48 }

    static func resolve(usesAccessibilityText: Bool) -> PlaybackSecondaryControlLayout {
        PlaybackSecondaryControlLayout(
            usesAdaptiveRates: usesAccessibilityText,
            presetLabelWidth: usesAccessibilityText ? 144 : 80,
            presetLabelMinimumHeight: usesAccessibilityText ? 84 : 48,
            rateLabelWidth: usesAccessibilityText ? 104 : 64,
            rateLabelMinimumHeight: usesAccessibilityText ? 64 : 60,
            rateMinimumTextScale: usesAccessibilityText ? 1 : 0.8
        )
    }
}

/// Label budgets for the compact roster and its three two-line entry buttons.
/// Normal sizes stay unchanged; AX sizes fit the measured full-size text and
/// symbols without consuming the main timeline's existing minimum width.
struct PlaybackPrimaryControlLabelLayout: Equatable, Sendable {
    let playerLabelWidth: CGFloat
    let toolsLabelWidth: CGFloat
    let drawLabelWidth: CGFloat
    let compactLabelMinimumHeight: CGFloat
    let playerMinimumTextScale: CGFloat
    let rosterLabelWidth: CGFloat
    let rosterLabelMinimumHeight: CGFloat
    let rosterRoleMinimumTextScale: CGFloat

    static func resolve(usesAccessibilityText: Bool) -> PlaybackPrimaryControlLabelLayout {
        PlaybackPrimaryControlLabelLayout(
            playerLabelWidth: usesAccessibilityText ? 168 : 116,
            toolsLabelWidth: usesAccessibilityText ? 88 : 78,
            drawLabelWidth: 76,
            compactLabelMinimumHeight: usesAccessibilityText ? 88 : 60,
            playerMinimumTextScale: usesAccessibilityText ? 1 : 0.82,
            rosterLabelWidth: 72,
            rosterLabelMinimumHeight: usesAccessibilityText ? 72 : 60,
            rosterRoleMinimumTextScale: usesAccessibilityText ? 1 : 0.75
        )
    }
}
