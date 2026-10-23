import CoreGraphics

/// Comfort presets for the position-following console. Distance and physical
/// size are independent: pulling a panel closer must never shrink it.
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

    func resized(by factor: Double) -> Self {
        let safe = Self.clampedSize(factor)
        return Self(attachmentWidth: attachmentWidth, uniformScale: uniformScale * Float(safe),
                    verticalOffset: verticalOffset, forwardOffset: forwardOffset)
    }

    static func clampedSize(_ factor: Double) -> Double {
        factor.isFinite ? min(max(factor, 0.8), 1.5) : 1
    }

    static func resolve(
        preset: PlaybackControlDeckPreset,
        usesAccessibilityText: Bool
    ) -> PlaybackControlDeckLayout {
        let base: PlaybackControlDeckLayout = switch preset {
        case .near:
            PlaybackControlDeckLayout(
                attachmentWidth: 1_400,
                uniformScale: 1.15,
                verticalOffset: -0.44,
                forwardOffset: -1.00
            )
        case .standard:
            PlaybackControlDeckLayout(
                attachmentWidth: 1_400,
                uniformScale: 1.15,
                verticalOffset: -0.50,
                forwardOffset: -1.20
            )
        case .large:
            PlaybackControlDeckLayout(
                attachmentWidth: 1_500,
                uniformScale: 1.30,
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

/// A separate, position-following surface for view and overlay choices.
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
                attachmentWidth: 700,
                horizontalOffset: -0.68,
                verticalOffset: 0.30,
                forwardOffset: -1.00,
                uniformScale: 1.10
            )
        case .standard:
            PlaybackViewHUDLayout(
                attachmentWidth: 700,
                horizontalOffset: -0.76,
                verticalOffset: 0.32,
                forwardOffset: -1.18,
                uniformScale: 1.15
            )
        case .large:
            PlaybackViewHUDLayout(
                attachmentWidth: 760,
                horizontalOffset: -0.80,
                verticalOffset: 0.32,
                forwardOffset: -1.10,
                uniformScale: 1.20
            )
        }

        guard usesAccessibilityText else { return base }
        return PlaybackViewHUDLayout(
            attachmentWidth: max(base.attachmentWidth + 40, 780),
            horizontalOffset: base.horizontalOffset + 0.04,
            verticalOffset: base.verticalOffset - 0.02,
            forwardOffset: base.forwardOffset + 0.04,
            uniformScale: base.uniformScale * 1.08
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

/// Label budgets for the compact roster and transport entry controls. Normal
/// sizes stay unchanged; AX budgets respect each label's permitted text scale
/// without consuming the main timeline's existing minimum width.
struct PlaybackPrimaryControlLabelLayout: Equatable, Sendable {
    let speedLabelWidth: CGFloat
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
            speedLabelWidth: usesAccessibilityText ? 80 : 74,
            playerLabelWidth: usesAccessibilityText ? 168 : 116,
            toolsLabelWidth: usesAccessibilityText ? 88 : 78,
            drawLabelWidth: 140,
            compactLabelMinimumHeight: usesAccessibilityText ? 96 : 80,
            playerMinimumTextScale: usesAccessibilityText ? 1 : 0.82,
            rosterLabelWidth: 72,
            rosterLabelMinimumHeight: usesAccessibilityText ? 72 : 60,
            rosterRoleMinimumTextScale: usesAccessibilityText ? 1 : 0.75
        )
    }
}

/// Tools are a secondary shelf: keep the normal row, but give AX labels their
/// measured full-size width and let the choices wrap below a separate header.
struct PlaybackToolsShelfLayout: Equatable, Sendable {
    enum Tool: CaseIterable, Equatable, Sendable {
        case timeline, decisions, settings, reviews, edit
    }

    let usesAdaptiveGrid: Bool
    let headingWidth: CGFloat
    let labelMinimumHeight: CGFloat
    let fixedLabelHeight: CGFloat?
    let editMinimumTextScale: CGFloat

    static let labelSpacingAllowance: CGFloat = 12
    static let gridSpacing: CGFloat = 10
    // Style padding is an allocation reserve, not a rendered measurement.
    var gridMinimumCellWidth: CGFloat { 208 + 48 }

    func labelWidth(for tool: Tool) -> CGFloat {
        if usesAdaptiveGrid { return 208 }
        return switch tool {
        case .timeline, .settings, .reviews: 126
        case .decisions: 132
        case .edit: 124
        }
    }

    static func resolve(usesAccessibilityText: Bool) -> PlaybackToolsShelfLayout {
        PlaybackToolsShelfLayout(
            usesAdaptiveGrid: usesAccessibilityText,
            headingWidth: usesAccessibilityText ? 148 : 108,
            labelMinimumHeight: 60,
            fixedLabelHeight: usesAccessibilityText ? nil : 60,
            editMinimumTextScale: usesAccessibilityText ? 1 : 0.78
        )
    }
}
