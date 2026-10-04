import SwiftUI

/// View and overlay controls stay visible in the upper-left comfort quadrant,
/// independent of the lower transport. Expanding this surface is an in-place
/// shelf: immersive spaces never receive a Menu, sheet, popover, or alert.
struct PlaybackViewOverlayHUD: View {
    @Environment(ReplayStore.self) private var store
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @AppStorage(ReplayEnvironmentMode.storageKey) private var environmentModeRawValue =
        ReplayEnvironmentMode.defaultSelection.rawValue
    @Binding var showsPlaybackAnnotations: Bool
    @Binding var emphasizesBall: Bool
    let recenterControls: () -> Void
    var surfaceControls: ReplaySurfacePlacementControls? = nil
    private let usesSpatialGlass: Bool
    @State private var isExpanded = false
    @State private var section: PlaybackViewShelf = .camera

    init(showsPlaybackAnnotations: Binding<Bool>, emphasizesBall: Binding<Bool>,
         recenterControls: @escaping () -> Void, surfaceControls: ReplaySurfacePlacementControls? = nil,
         initialSection: PlaybackViewShelf = .camera, initiallyExpanded: Bool = false,
         usesSpatialGlass: Bool = true) {
        self._showsPlaybackAnnotations = showsPlaybackAnnotations
        self._emphasizesBall = emphasizesBall
        self.recenterControls = recenterControls
        self.surfaceControls = surfaceControls
        self.usesSpatialGlass = usesSpatialGlass
        self._section = State(initialValue: initialSection)
        self._isExpanded = State(initialValue: initiallyExpanded)
    }

    var body: some View {
        if usesSpatialGlass {
            controls.glassBackgroundEffect(in: .rect(cornerRadius: 20))
        } else {
            // UIHostingController cannot snapshot spatial glass composites.
            // Window-layout audits render the identical controls without glass.
            controls
        }
    }

    private var controls: some View {
        VStack(alignment: .leading, spacing: 9) {
            Button {
                withAnimation(.easeOut(duration: 0.18)) {
                    isExpanded.toggle()
                }
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: store.viewMode.systemImage)
                        .font(.headline.weight(.black))
                        .foregroundStyle(ReplayTheme.signal)
                        .frame(width: symbolLayout.modeIconWidth,
                            height: PlaybackControlDeckPresentation.minimumSpatialHitTarget)

                    VStack(alignment: .leading, spacing: 1) {
                        Eyebrow(text: "View & Overlays", color: ReplayTheme.signal)
                        Text(store.viewMode.title)
                            .font(.subheadline.weight(.black))
                            .lineLimit(1)
                    }

                    HStack(spacing: 5) {
                        ForEach(activeOverlayBadges) { badge in
                            compactOverlayBadge(badge)
                        }
                    }
                    .accessibilityHidden(true)

                    Spacer(minLength: 4)

                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.caption.weight(.black))
                        .foregroundStyle(.white.opacity(0.62))
                        .frame(width: symbolLayout.disclosureIconWidth,
                            height: PlaybackControlDeckPresentation.minimumSpatialHitTarget)
                }
                .frame(minHeight: PlaybackControlDeckPresentation.minimumSpatialHitTarget)
                .contentShape(RoundedRectangle(cornerRadius: 14))
            }
            .buttonStyle(.plain)
            .hoverEffect(.highlight)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("View and overlays")
            .accessibilityValue(overlayAccessibilityValue)
            .accessibilityHint(isExpanded ? "Collapses controls" : "Expands controls")
            .accessibilityAddTraits(isExpanded ? .isSelected : [])

            if isExpanded {
                Rectangle()
                    .fill(.white.opacity(0.13))
                    .frame(height: 1)
                    .accessibilityHidden(true)

                PlaybackViewShelfPicker(selection: $section)

                if section == .camera {
                    ViewThatFits(in: .horizontal) {
                        HStack(spacing: 6) {
                            ForEach(playbackViewModes, id: \.self) { mode in
                                viewChoice(mode)
                            }
                        }
                        VStack(spacing: 6) {
                            ForEach(playbackViewModes, id: \.self) { mode in
                                viewChoice(mode)
                            }
                        }
                    }
                }

                if section == .space {
                    Button(action: recenterControls) {
                        Label("Recenter controls", systemImage: "viewfinder")
                            .font(.subheadline.weight(.semibold))
                            .frame(maxWidth: .infinity, minHeight: 60)
                    }
                    .buttonStyle(.bordered)
                    .disabled(!PlaybackAttachmentPlacement.canRecenter(
                        isDrawing: store.isDrawing,
                        isScrubbing: store.hasActiveTimelineScrub,
                        isEditingGeometry: store.hasActiveCoachMarkGeometryPreview
                    ))
                    .accessibilityHint("Places the workspace in front of you, then leaves it fixed in the room")
                    environmentChoices
                    if store.viewMode == .tacticalTable,
                       ReplayEnvironmentMode.effective(environmentModeRawValue, isPhysicalPractice: false) == .room,
                       let surfaceControls { surfaceControls }
                }

                if section == .overlays {
                    HStack(spacing: 6) {
                        overlayChoice(
                            title: "Marks",
                            systemImage: "arrow.up.right",
                            isVisible: showsPlaybackAnnotations,
                            color: ReplayTheme.orange
                        ) {
                            showsPlaybackAnnotations.toggle()
                        }

                        overlayChoice(
                            title: "Ball",
                            systemImage: "scope",
                            isVisible: emphasizesBall,
                            color: ReplayTheme.signal,
                            accessibilityName: "Ball highlight",
                            onValue: "On",
                            offValue: "Off"
                        ) {
                            emphasizesBall.toggle()
                        }

                        if store.selectedScenario.kind == .passingChannels {
                            overlayChoice(
                                title: "Lanes",
                                systemImage: "arrow.triangle.branch",
                                isVisible: store.showsLaneLens,
                                color: ReplayTheme.cyan,
                                isEnabled: canControlOverlays
                            ) {
                                store.showsLaneLens.toggle()
                                if store.localRole == .coach {
                                    store.flushReviewAutosave()
                                }
                            }
                        }
                    }
                }
            }
        }
        .padding(11)
        .controlSize(.large)
        .background(ReplayTheme.navy.opacity(0.50), in: RoundedRectangle(cornerRadius: 20))
        .overlay {
            RoundedRectangle(cornerRadius: 20)
                .stroke(.white.opacity(0.14), lineWidth: 1)
        }
        .task {
            #if DEBUG
            if ProcessInfo.processInfo.arguments.contains("--replayxi-view-hud-expanded") {
                isExpanded = true
            }
            #endif
        }
    }

    private var environmentChoices: some View {
        VStack(alignment: .leading, spacing: 5) {
            Eyebrow(text: "Surroundings", color: ReplayTheme.cyan)
            HStack(spacing: 6) {
                ForEach(ReplayEnvironmentMode.allCases) { mode in
                    Button {
                        store.setPlaying(false, broadcast: false)
                        environmentModeRawValue = mode.rawValue
                    } label: {
                        Label(mode.title, systemImage: mode.systemImage)
                            .font(.subheadline.weight(.semibold))
                            .frame(maxWidth: .infinity, minHeight: 60)
                            .foregroundStyle(environmentModeRawValue == mode.rawValue ? .black : .white)
                            .background(environmentModeRawValue == mode.rawValue
                                ? ReplayTheme.signal : .white.opacity(0.10), in: Capsule())
                    }
                    .buttonStyle(.plain)
                    .disabled(!store.canChangePlaybackView)
                    .accessibilityAddTraits(environmentModeRawValue == mode.rawValue ? .isSelected : [])
                    .accessibilityHint(mode == .room
                        ? "Shows your real surroundings" : "Hides passthrough. Stay seated or planted")
                }
            }
        }
    }

    private var playbackViewModes: [ReplayViewMode] {
        [.firstPerson, .tacticalTable, .touchline]
    }

    private var symbolLayout: PlaybackViewHUDSymbolLayout {
        PlaybackViewHUDSymbolLayout.resolve(usesAccessibilityText: dynamicTypeSize.isAccessibilitySize)
    }

    private var canControlOverlays: Bool { true }

    private var activeOverlayBadges: [PlaybackOverlayBadge] {
        PlaybackOverlayBadge.activeBadges(
            showsAnnotations: showsPlaybackAnnotations,
            emphasizesBall: emphasizesBall,
            showsLanes: store.showsLaneLens,
            supportsLanes: store.selectedScenario.kind == .passingChannels
        )
    }

    private var overlayAccessibilityValue: String {
        var values = [
            store.viewMode.title,
            "annotations \(showsPlaybackAnnotations ? "shown" : "hidden")",
            "ball highlight \(emphasizesBall ? "on" : "off")",
        ]
        if store.selectedScenario.kind == .passingChannels {
            values.append("passing lanes \(store.showsLaneLens ? "shown" : "hidden")")
        }
        return values.joined(separator: ", ")
    }

    private func compactOverlayBadge(_ badge: PlaybackOverlayBadge) -> some View {
        Image(systemName: badge.systemImage)
            .font(.caption.weight(.black))
            .foregroundStyle(compactOverlayBadgeColor(badge))
            .frame(width: symbolLayout.overlayBadgeDiameter, height: symbolLayout.overlayBadgeDiameter)
            .background(.white.opacity(0.08), in: Circle())
    }

    private func compactOverlayBadgeColor(_ badge: PlaybackOverlayBadge) -> Color {
        switch badge {
        case .annotations: ReplayTheme.orange
        case .ball: ReplayTheme.signal
        case .lanes: ReplayTheme.cyan
        }
    }

    private func viewChoice(_ mode: ReplayViewMode) -> some View {
        let isSelected = store.viewMode == mode
        return Button {
            store.setViewMode(mode)
        } label: {
            VStack(spacing: 2) {
                Image(systemName: mode.systemImage)
                    .font(.headline.weight(.bold))
                Text(shortViewTitle(mode))
                    .font(.subheadline.weight(.bold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
            }
            .frame(
                maxWidth: .infinity,
                minHeight: PlaybackControlDeckPresentation.minimumSpatialHitTarget
            )
        }
        .buttonStyle(.borderedProminent)
        .tint(isSelected ? ReplayTheme.signal : .white.opacity(0.10))
        .foregroundStyle(isSelected ? Color.black : Color.white)
        .disabled(!store.canChangePlaybackView)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(mode.title) view")
        .accessibilityHint(store.canChangePlaybackView
            ? PlaybackControlDeckPresentation.cameraActionHint(mode, currentMode: store.viewMode)
            : "Finish or cancel the current gesture first")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private func overlayChoice(
        title: String,
        systemImage: String,
        isVisible: Bool,
        color: Color,
        isEnabled: Bool = true,
        accessibilityName: String? = nil,
        onValue: String = "Shown",
        offValue: String = "Hidden",
        action: @escaping () -> Void
    ) -> some View {
        let resolvedAccessibilityName = accessibilityName ?? title
        return Button(action: action) {
            Label(title, systemImage: isVisible ? systemImage : "eye.slash")
                .font(.caption.weight(.black))
                .lineLimit(1)
                .frame(
                    maxWidth: .infinity,
                    minHeight: PlaybackControlDeckPresentation.minimumSpatialHitTarget
                )
        }
        .buttonStyle(.borderedProminent)
        .tint(isVisible ? color : .white.opacity(0.10))
        .foregroundStyle(isVisible ? Color.black : Color.white)
        .disabled(!isEnabled || store.hasActiveCoachMarkGeometryPreview || store.hasActiveTimelineScrub)
        .accessibilityLabel(resolvedAccessibilityName)
        .accessibilityValue(isVisible ? onValue : offValue)
        .accessibilityHint("Turns \(resolvedAccessibilityName.lowercased()) \(isVisible ? "off" : "on")")
        .accessibilityAddTraits(isVisible ? .isSelected : [])
    }

    private func shortViewTitle(_ mode: ReplayViewMode) -> String {
        switch mode {
        case .firstPerson: "POV"
        case .tacticalTable: "Tactical"
        case .touchline: "Touchline"
        case .positional: "Position"
        }
    }
}
