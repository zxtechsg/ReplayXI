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
    let resetWorldPlacement: () -> Void
    let resizePitch: (Float) -> Void
    let movePitch: (Float) -> Void
    var surfaceControls: ReplaySurfacePlacementControls? = nil
    let canPlacePitch: Bool
    private let usesSpatialGlass: Bool
    @State private var isExpanded = false
    @State private var section: PlaybackViewShelf = .camera

    init(showsPlaybackAnnotations: Binding<Bool>, emphasizesBall: Binding<Bool>,
         recenterControls: @escaping () -> Void, resetWorldPlacement: @escaping () -> Void = {},
         resizePitch: @escaping (Float) -> Void = { _ in },
         movePitch: @escaping (Float) -> Void = { _ in },
         surfaceControls: ReplaySurfacePlacementControls? = nil,
         canPlacePitch: Bool = true,
         initialSection: PlaybackViewShelf = .camera, initiallyExpanded: Bool = true,
         usesSpatialGlass: Bool = true) {
        self._showsPlaybackAnnotations = showsPlaybackAnnotations
        self._emphasizesBall = emphasizesBall
        self.recenterControls = recenterControls
        self.resetWorldPlacement = resetWorldPlacement
        self.resizePitch = resizePitch
        self.movePitch = movePitch
        self.surfaceControls = surfaceControls
        self.canPlacePitch = canPlacePitch
        self.usesSpatialGlass = usesSpatialGlass
        self._section = State(initialValue: initialSection)
        self._isExpanded = State(initialValue: initiallyExpanded)
    }

    var body: some View {
        if usesSpatialGlass {
            controls
                .fixedSize(horizontal: !isExpanded, vertical: false)
                .glassBackgroundEffect(in: .rect(cornerRadius: 20))
        } else {
            // UIHostingController cannot snapshot spatial glass composites.
            // Window-layout audits render the identical controls without glass.
            controls.fixedSize(horizontal: !isExpanded, vertical: false)
        }
    }

    private var controls: some View {
        VStack(alignment: .leading, spacing: 9) {
            Button {
                withAnimation(.easeOut(duration: 0.18)) {
                    isExpanded.toggle()
                }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: store.viewMode.systemImage)
                        .font(.headline.weight(.black))
                        .foregroundStyle(ReplayTheme.signal)
                        .frame(width: symbolLayout.modeIconWidth,
                            height: PlaybackControlDeckPresentation.minimumSpatialHitTarget)
                    Text("View · \(store.viewMode.title)")
                        .font(.headline.weight(.semibold))

                    HStack(spacing: 5) {
                        ForEach(activeOverlayBadges) { badge in
                            compactOverlayBadge(badge)
                        }
                    }
                    .accessibilityHidden(true)

                    Spacer(minLength: 0)

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
            .help("\(store.viewMode.title) view · \(isExpanded ? "collapse" : "open") view, overlays and room controls")
            .spatialHelp(isExpanded ? "Collapse view controls" : "Open view controls")

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
                    if store.viewMode == .tacticalTable || store.viewMode == .touchline {
                        Button(action: resetWorldPlacement) {
                            Label("Bring pitch here", systemImage: "sportscourt")
                                .font(.title3.weight(.semibold))
                                .frame(maxWidth: .infinity, minHeight: 56)
                        }
                        .buttonStyle(.bordered)
                        .disabled(!canPlacePitch || surfaceControls?.hasPlacement == true)
                        .help(pitchPlacementHelp)
                        .spatialHelp("Place pitch in front of you")
                        .accessibilityLabel("Bring pitch here")
                        .accessibilityHint(pitchPlacementHelp)
                        HStack(spacing: 10) {
                            pitchButton("Smaller", "minus.magnifyingglass") { resizePitch(1 / 1.15) }
                            pitchButton("Bigger", "plus.magnifyingglass") { resizePitch(1.15) }
                        }
                        HStack(spacing: 10) {
                            pitchButton("Closer", "arrow.down") { movePitch(0.3) }
                            pitchButton("Farther", "arrow.up") { movePitch(-0.3) }
                        }
                        Text("Pinch both hands. Spread to enlarge; move together to bring the pitch closer or farther.")
                            .font(.callout).foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                if section == .space {
                    HStack(spacing: 6) {
                        Button(action: recenterControls) {
                            Label("Recenter UI", systemImage: "viewfinder")
                                .font(.title3.weight(.semibold))
                                .frame(maxWidth: .infinity, minHeight: 60)
                        }
                        .buttonStyle(.bordered)
                        .disabled(!PlaybackAttachmentPlacement.canRecenter(
                            isDrawing: store.isDrawing,
                            isScrubbing: store.hasActiveTimelineScrub,
                            isEditingGeometry: store.hasActiveCoachMarkGeometryPreview
                        ))
                        .spatialHelp("Recenter controls in front of you")
                        .accessibilityLabel("Recenter controls")
                        .accessibilityHint("Follows your position without turning with your head")
                        if store.viewMode == .tacticalTable || store.viewMode == .touchline {
                            Button(action: resetWorldPlacement) {
                                Label("Bring pitch here", systemImage: "sportscourt")
                                    .font(.title3.weight(.semibold))
                                    .frame(maxWidth: .infinity, minHeight: 60)
                            }
                            .buttonStyle(.bordered)
                            .disabled(!canPlacePitch || surfaceControls?.hasPlacement == true)
                            .help(pitchPlacementHelp)
                            .accessibilityLabel("Bring pitch here")
                            .accessibilityHint(pitchPlacementHelp)
                        }
                    }
                    environmentChoices
                    if store.viewMode == .tacticalTable,
                       ReplayEnvironmentMode.effective(environmentModeRawValue, isPhysicalPractice: false) == .room,
                       let surfaceControls { surfaceControls }
                }

                if section == .overlays {
                    HStack(spacing: 6) { overlayChoices }
                }
            }
        }
        .padding(11)
        .controlSize(.large)
        .task {
            #if DEBUG
            if ReplayLaunchConfiguration.current.automationArguments.contains("--replayxi-view-hud-expanded") {
                isExpanded = true
            }
            #endif
        }
    }

    private func pitchButton(_ title: String, _ icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: icon).font(.headline)
                .frame(maxWidth: .infinity, minHeight: 80)
        }.buttonStyle(.bordered)
            .disabled(!canPlacePitch || surfaceControls?.hasPlacement == true)
            .spatialHelp(title == "Closer" || title == "Farther"
                ? "Move pitch without changing its size" : "Change pitch size without moving it")
    }

    @ViewBuilder
    private var overlayChoices: some View {
        overlayChoice(title: "Marks", systemImage: "arrow.up.right",
            isVisible: showsPlaybackAnnotations, color: ReplayTheme.orange) {
            showsPlaybackAnnotations.toggle()
        }
        overlayChoice(title: "Ball", systemImage: "scope",
            isVisible: emphasizesBall, color: ReplayTheme.signal,
            accessibilityName: "Ball highlight", onValue: "On", offValue: "Off") {
            emphasizesBall.toggle()
        }
        if store.selectedScenario.kind == .passingChannels {
            overlayChoice(title: "Lanes", systemImage: "arrow.triangle.branch",
                isVisible: store.showsLaneLens, color: ReplayTheme.cyan) {
                store.showsLaneLens.toggle()
                if store.localRole == .coach { store.flushReviewAutosave() }
            }
        }
    }

    private var environmentChoices: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 6) {
                ForEach(ReplayEnvironmentMode.allCases) { mode in
                    Button {
                        store.setPlaying(false, broadcast: false)
                        environmentModeRawValue = mode.rawValue
                    } label: {
                        Label(mode.title, systemImage: mode.systemImage)
                            .font(.title3.weight(.semibold))
                            .frame(maxWidth: .infinity, minHeight: 60)
                            .foregroundStyle(environmentModeRawValue == mode.rawValue ? .black : .white)
                            .background(environmentModeRawValue == mode.rawValue
                                ? ReplayTheme.signal : .white.opacity(0.10), in: Capsule())
                    }
                    .buttonStyle(.plain)
                    .disabled(!store.canChangePlaybackView)
                    .help(mode == .room ? "Room: shows your real surroundings" :
                        "Stadium: hides passthrough. Stay seated or planted")
                    .accessibilityLabel("\(mode.title) surroundings")
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

    private var pitchPlacementHelp: String {
        if surfaceControls?.hasPlacement == true {
            return "Surface pitch fixed. Reset its surface placement to use the two-hand gesture."
        }
        return "Bring pitch here. Places a level pitch in front of you and keeps it fixed in the room. Pinch both hands: move together to place; spread or close to resize."
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
            Label(mode.title, systemImage: mode.systemImage)
                .font(.title3.weight(.bold))
                .frame(
                    maxWidth: .infinity,
                    minHeight: PlaybackControlDeckPresentation.minimumSpatialHitTarget
                )
        }
        .buttonStyle(.borderedProminent)
        .tint(isSelected ? ReplayTheme.signal : .white.opacity(0.10))
        .foregroundStyle(isSelected ? Color.black : Color.white)
        .disabled(!store.canChangePlaybackView)
        .help("\(mode.title) view. \(PlaybackControlDeckPresentation.cameraActionHint(mode, currentMode: store.viewMode))")
        .spatialHelp("\(mode.title) view")
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
            Label(title, systemImage: systemImage)
                .font(.title3.weight(.bold))
                .frame(
                    maxWidth: .infinity,
                    minHeight: PlaybackControlDeckPresentation.minimumSpatialHitTarget
                )
        }
        .buttonStyle(.borderedProminent)
        .tint(isVisible ? color : .white.opacity(0.10))
        .foregroundStyle(isVisible ? Color.black : Color.white)
        .disabled(!isEnabled || store.hasActiveCoachMarkGeometryPreview || store.hasActiveTimelineScrub)
        .help("\(resolvedAccessibilityName): \(isVisible ? onValue : offValue). Select to turn \(isVisible ? "off" : "on")")
        .spatialHelp("\(resolvedAccessibilityName) · \(isVisible ? onValue : offValue)")
        .accessibilityLabel(resolvedAccessibilityName)
        .accessibilityValue(isVisible ? onValue : offValue)
        .accessibilityHint("Turns \(resolvedAccessibilityName.lowercased()) \(isVisible ? "off" : "on")")
        .accessibilityAddTraits(isVisible ? .isSelected : [])
    }
}
