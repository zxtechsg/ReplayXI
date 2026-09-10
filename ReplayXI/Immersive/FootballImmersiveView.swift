import RealityKit
import SwiftUI

struct FootballImmersiveView: View {
    @Environment(ReplayStore.self) private var store
    @Environment(LocalPitchAnchorCoordinator.self) private var sharedSpace
    @Environment(\.dismissImmersiveSpace) private var dismissImmersiveSpace
    @Environment(\.openWindow) private var openWindow
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.accessibilityPrefersHeadAnchorAlternative)
    private var accessibilityPrefersHeadAnchorAlternative
    @AppStorage("ReplayXI.PlaybackControlDeckPreset") private var controlDeckPresetRawValue =
        PlaybackControlDeckPreset.standard.rawValue
    @State private var selectedAnnotationID: UUID?
    @State private var draggedAnnotationTarget: AnnotationSceneTarget?
    @State private var annotationStroke: PlaybackAnnotationStroke?
    @GestureState private var spatialDragIsActive = false
    @State private var showsDecisionStrip = false
    @State private var showsPlaybackAnnotations = true
    // Wearer-local HUD state. PitchSceneFactory owns the eventual ball-emphasis
    // treatment; keeping this binding at the immersive root makes that scene
    // integration explicit without coupling the control surface to the renderer.
    @State private var emphasizesBall = true
    @State private var accessibilityActivationSubscription: EventSubscription?

    private var controlDeckPreset: PlaybackControlDeckPreset {
        PlaybackControlDeckPreset(rawValue: controlDeckPresetRawValue) ?? .standard
    }

    private var controlDeckLayout: PlaybackControlDeckLayout {
        PlaybackControlDeckLayout.resolve(
            preset: controlDeckPreset,
            usesAccessibilityText: dynamicTypeSize.isAccessibilitySize
        )
    }

    private var viewHUDLayout: PlaybackViewHUDLayout {
        PlaybackViewHUDLayout.resolve(
            preset: controlDeckPreset,
            usesAccessibilityText: dynamicTypeSize.isAccessibilitySize
        )
    }

    var body: some View {
        RealityView { content, attachments in
            let root = PitchSceneFactory.makeMatchRoot(for: store.selectedScenario)
            content.add(root)
            // Normal playback follows the physical wearer independently of the
            // replayed player's moving POV. When assistive technology conflicts
            // with head-locked content, `.once` captures the initial head pose
            // and then leaves the controls stable in the room.
            let controlsAnchor = AnchorEntity(
                .head,
                trackingMode: PlaybackAttachmentPlacement.controlAnchorTrackingMode(
                    prefersHeadAnchorAlternative: accessibilityPrefersHeadAnchorAlternative
                )
            )
            controlsAnchor.name = "playback-controls-head-anchor"
            content.add(controlsAnchor)
            if accessibilityActivationSubscription == nil {
                accessibilityActivationSubscription = content.subscribe(
                    to: AccessibilityEvents.Activate.self
                ) { event in
                    handleAccessibilityActivation(of: event.entity)
                }
            }
            PitchSceneFactory.update(
                root: root,
                scenario: store.selectedScenario,
                time: store.playhead,
                viewMode: store.viewMode,
                perspectiveID: store.activePerspectiveID,
                marks: store.marks,
                selectedAnnotationID: selectedAnnotationID,
                selectedAnnotationIsEditable: selectedAnnotationIsEditable,
                decisionSnapshot: visibleDecisionSnapshot,
                showsLaneLens: store.showsLaneLens,
                isDrawing: store.isDrawing,
                draftStart: store.pendingDrawStart,
                draftEnd: annotationStroke?.previewEnd,
                draftKind: store.selectedTool,
                positionalOriginTransform: sharedSpace.pitchOriginTransform,
                triangleLockMode: store.triangleLockMode,
                isTrianglePlacementReady: store.hasLocallyAcknowledgedTrianglePlacement
                    && sharedSpace.hasUsableSharedPitchFrame
                    && store.canRevealPhysicalTriangleMarkers(
                        participantID: nil,
                        sharedSession: false
                    ),
                showsIdealBranch: store.showsIdealBranch,
                emphasizesBall: emphasizesBall
            )
            applyLocalOverlayVisibility(to: root)
            addAttachments(
                to: content,
                attachments: attachments,
                controlsAnchor: controlsAnchor
            )
        } update: { content, attachments in
            let expectedName = "match-root-\(store.selectedScenarioID)"
            var root = content.entities.first { $0.name == expectedName }

            if root == nil {
                for entity in content.entities where entity.name.hasPrefix("match-root-") {
                    content.remove(entity)
                }
                let replacement = PitchSceneFactory.makeMatchRoot(for: store.selectedScenario)
                content.add(replacement)
                root = replacement
            }

            if let root {
                PitchSceneFactory.update(
                    root: root,
                    scenario: store.selectedScenario,
                    time: store.playhead,
                    viewMode: store.viewMode,
                    perspectiveID: store.activePerspectiveID,
                    marks: store.marks,
                    selectedAnnotationID: selectedAnnotationID,
                    selectedAnnotationIsEditable: selectedAnnotationIsEditable,
                    decisionSnapshot: visibleDecisionSnapshot,
                    showsLaneLens: store.showsLaneLens,
                    isDrawing: store.isDrawing,
                    draftStart: store.pendingDrawStart,
                    draftEnd: annotationStroke?.previewEnd,
                    draftKind: store.selectedTool,
                    positionalOriginTransform: sharedSpace.pitchOriginTransform,
                    triangleLockMode: store.triangleLockMode,
                    isTrianglePlacementReady: store.hasLocallyAcknowledgedTrianglePlacement
                        && sharedSpace.hasUsableSharedPitchFrame
                        && store.canRevealPhysicalTriangleMarkers(
                            participantID: nil,
                            sharedSession: false
                        ),
                    showsIdealBranch: store.showsIdealBranch,
                    emphasizesBall: emphasizesBall
                )
                applyLocalOverlayVisibility(to: root)
            }
            // Attachments do not inherit the match-root presentation transform.
            // Re-assert their room-space placement whenever view mode or another
            // observed playback value causes RealityView to update.
            if let controlsAnchor = content.entities.first(where: {
                $0.name == "playback-controls-head-anchor"
            }) as? AnchorEntity {
                controlsAnchor.anchoring.trackingMode =
                    PlaybackAttachmentPlacement.controlAnchorTrackingMode(
                        prefersHeadAnchorAlternative: accessibilityPrefersHeadAnchorAlternative
                    )
            }
            updateAttachmentPositions(attachments)
        } attachments: {
            if store.selectedScenario.kind == .shapeLab {
                Attachment(id: "room-header") {
                    ImmersiveRoomHeader()
                        .frame(width: 650)
                }
            }

            Attachment(id: "coach-console") {
                ImmersiveControlDeck(
                    selectedAnnotationID: $selectedAnnotationID,
                    showsDecisionStrip: $showsDecisionStrip,
                    showsPlaybackAnnotations: $showsPlaybackAnnotations,
                    controlDeckPresetRawValue: $controlDeckPresetRawValue,
                    deckWidth: controlDeckLayout.contentWidth,
                    isPinchDrawing: annotationStroke != nil,
                    isPinchDrawingReady: annotationStroke?.isReadyToCommit == true,
                    exit: exitRoom
                )
                    .frame(width: controlDeckLayout.attachmentWidth)
            }

            if store.selectedScenario.kind != .shapeLab {
                Attachment(id: "playback-view-hud") {
                    PlaybackViewOverlayHUD(
                        showsPlaybackAnnotations: $showsPlaybackAnnotations,
                        emphasizesBall: $emphasizesBall
                    )
                    .frame(width: viewHUDLayout.attachmentWidth)
                }
            }

            if store.selectedScenario.kind == .perspectiveMatrix {
                Attachment(id: "perspective-matrix") {
                    PerspectiveMatrixPanel()
                        .frame(width: 520)
                }
            }

            if store.selectedScenario.kind == .shapeLab {
                Attachment(id: "position-status") {
                    PositioningPanel()
                        .frame(width: 460)
                }
            }

        }
        .gesture(spatialInteractionGesture)
        .task(id: store.selectedScenario.kind) {
            #if DEBUG
            if ProcessInfo.processInfo.arguments.contains("--replayxi-pinch-draft") {
                let start = PitchPoint(x: 11, z: 7)
                let end = PitchPoint(x: 23, z: 22)
                store.beginDrawing(.run)
                _ = store.registerPitchTap(start)
                if var preview = PlaybackAnnotationStroke(kind: .run, start: start) {
                    _ = preview.update(to: end)
                    annotationStroke = preview
                }
            }
            #endif
            if store.selectedScenario.kind == .shapeLab {
                // World tracking is needed only by the stationary Shape Focus
                // placement drill. Match review stays on the lighter render path.
                await sharedSpace.start()
                guard !Task.isCancelled else { return }
                sharedSpace.selectSharedPitchAnchor(id: store.sharedPitchAnchorID)
            } else if sharedSpace.isRunning {
                await sharedSpace.removeLocallyPlacedPitchAnchor()
                sharedSpace.stop()
            }
        }
        .task {
            let clock = ContinuousClock()
            var previous = clock.now
            while !Task.isCancelled {
                // Sample the ownership state before sleeping. If playback is
                // started during an idle poll, the next active frame begins
                // from that wake instant rather than charging paused time to
                // the transport and producing a visible jump.
                let shouldAdvance = store.isActivelyPlaying
                try? await Task.sleep(
                    for: ReplayPresentationClock.interval(shouldAdvance: shouldAdvance)
                )
                guard !Task.isCancelled else { return }
                let now = clock.now
                let duration = previous.duration(to: now)
                previous = now
                guard shouldAdvance else { continue }
                store.advance(by: ReplayPresentationClock.seconds(duration))
            }
        }
        .onDisappear {
            // System dismissal is also an exit transaction. Roll transient
            // geometry back before child controls disappear, then force the
            // dashboard-facing store into a genuinely paused state.
            // Clear immersive ownership first. If the child deck disappears
            // afterward, it must not restore a pre-scrub playing checkpoint
            // over this definitive exit pause.
            store.isImmersiveOpen = false
            store.isOpeningImmersive = false
            store.prepareForImmersiveExit()
            accessibilityActivationSubscription?.cancel()
            accessibilityActivationSubscription = nil
            cancelInterruptedSpatialInteraction()
            if store.isDrawing {
                store.cancelDrawing()
            }
            if store.triangleLockMode == .place {
                if store.localRole == .coach {
                    store.endTrianglePlacement()
                } else {
                    store.revokeTrianglePlacementConsentLocally()
                }
            }
            if store.localRole == .coach {
                // The session can reset Store to visualise before this view disappears.
                // Removal is ownership-safe and prevents an orphaned coach anchor.
                Task {
                    await sharedSpace.removeLocallyPlacedPitchAnchor()
                    sharedSpace.stop()
                }
            } else {
                sharedSpace.stop()
            }
            openWindow(id: "ReplayDashboard")
        }
        .onChange(of: store.sharedPitchAnchorID) { _, anchorID in
            sharedSpace.selectSharedPitchAnchor(id: anchorID)
        }
        .onChange(of: store.isDrawing) { _, isDrawing in
            if !isDrawing { annotationStroke = nil }
        }
        .onChange(of: store.selectedTool) { _, _ in
            annotationStroke = nil
        }
        .onChange(of: showsPlaybackAnnotations) { _, isVisible in
            guard !isVisible else { return }
            // This root owns the RealityView handle-drag state, so tear it
            // down here rather than relying on the control deck's observer.
            // SwiftUI does not guarantee observer ordering: the deck may have
            // already cleared the shared selection by the time this runs.
            if let draggedAnnotationTarget {
                _ = store.cancelCoachMarkGeometryPreview(
                    id: draggedAnnotationTarget.markID
                )
            } else if let selectedAnnotationID {
                _ = store.cancelCoachMarkGeometryPreview(id: selectedAnnotationID)
            }
            draggedAnnotationTarget = nil
            selectedAnnotationID = nil
            annotationStroke = nil
            if store.isDrawing {
                store.cancelDrawing()
            }
        }
        .onChange(of: spatialDragIsActive) { wasActive, isActive in
            guard wasActive, !isActive else { return }
            cancelInterruptedSpatialInteraction()
        }
    }

    private func addAttachments(
        to content: RealityViewContent,
        attachments: RealityViewAttachments,
        controlsAnchor: AnchorEntity
    ) {
        for id in [
            "room-header",
            "coach-console",
            "playback-view-hud",
            "perspective-matrix",
            "position-status",
        ] {
            if let entity = attachments.entity(for: id) {
                entity.name = id
                if PlaybackAttachmentPlacement.followsHead(id) {
                    controlsAnchor.addChild(entity)
                } else {
                    content.add(entity)
                }
            }
        }
        updateAttachmentPositions(attachments)
    }

    private func updateAttachmentPositions(_ attachments: RealityViewAttachments) {
        attachments.entity(for: "room-header")?.position = [0, 1.74, -1.55]
        // `coach-console` is local to the head anchor. The low, forward offset
        // preserves an unobstructed central view and keeps gaze/pinch targets in
        // a comfortable hand-reach cone as the wearer changes POV or turns.
        if let console = attachments.entity(for: "coach-console") {
            let layout = controlDeckLayout
            console.position = [0, layout.verticalOffset, layout.forwardOffset]
            console.scale = SIMD3<Float>(repeating: layout.uniformScale)
        }
        if let viewHUD = attachments.entity(for: "playback-view-hud") {
            let layout = viewHUDLayout
            viewHUD.position = [layout.horizontalOffset, layout.verticalOffset, layout.forwardOffset]
            viewHUD.scale = SIMD3<Float>(repeating: layout.uniformScale)
        }
        attachments.entity(for: "perspective-matrix")?.position = [0.92, 1.30, -1.55]
        attachments.entity(for: "position-status")?.position = [-1.00, 1.30, -1.30]
    }

    /// Annotation visibility is a wearer-local analysis preference. Keep the
    /// authored marks in ReplayStore (and therefore in the shared room) while
    /// suppressing only this headset's render and edit affordances.
    private func applyLocalOverlayVisibility(to root: Entity) {
        PlaybackLocalOverlayVisibility.apply(
            to: root,
            showsAnnotations: showsPlaybackAnnotations,
            canOverrideMarksRoot: store.selectedScenario.kind != .shapeLab
        )
    }

    private func matchRootAncestor(of entity: Entity) -> Entity? {
        var cursor: Entity? = entity
        while let current = cursor {
            if current.name.hasPrefix("match-root-") { return current }
            cursor = current.parent
        }
        return nil
    }

    private func playerIDAncestor(of entity: Entity) -> String? {
        if let decisionPlayerID = DecisionOptionSceneOverlay.playerIDAncestor(of: entity) {
            return decisionPlayerID
        }
        var cursor: Entity? = entity
        while let current = cursor {
            let labelPrefix = "player-label-"
            if current.name.hasPrefix(labelPrefix) {
                return String(current.name.dropFirst(labelPrefix.count))
            }
            let prefix = "player-"
            if current.name.hasPrefix(prefix) {
                return String(current.name.dropFirst(prefix.count))
            }
            cursor = current.parent
        }
        return nil
    }

    private func nearestPlayer(to point: PitchPoint, maximumDistance: Float) -> PlayerTrack? {
        let maximumSquaredDistance = maximumDistance * maximumDistance
        var closest: (player: PlayerTrack, squaredDistance: Float)?
        for player in store.selectedScenario.players {
            let position = player.presentationPose(at: store.playhead).position
            let xOffset = position.x - point.x
            let zOffset = position.z - point.z
            let squaredDistance = (xOffset * xOffset) + (zOffset * zOffset)
            guard squaredDistance <= maximumSquaredDistance else { continue }
            if let current = closest, squaredDistance >= current.squaredDistance {
                continue
            } else {
                closest = (player, squaredDistance)
            }
        }
        return closest?.player
    }

    /// One exclusive recognizer arbitrates pitch taps and spatial drags. The
    /// semantic tap gets precedence, preserving reliable player/mark picking;
    /// once tap recognition fails because the hand moves, the drag takes over.
    /// visionOS 26 documents entity-drag distances in the entity's spatial
    /// scale; 0.001 local units is the recommended 1 mm gate.
    private var spatialInteractionGesture: some Gesture {
        SpatialTapGesture()
            .targetedToAnyEntity()
            .onEnded(handleSpatialTap)
            .exclusively(
                before: DragGesture(
                    minimumDistance: PlaybackAnnotationStroke.entityGestureMinimumDistance,
                    coordinateSpace: .local
                )
                .targetedToAnyEntity()
                .updating($spatialDragIsActive) { _, isActive, _ in
                    isActive = true
                }
                .onChanged { value in
                    handleAnnotationDragChanged(value)
                    handleAnnotationStrokeChanged(value)
                }
                .onEnded { value in
                    handleSpatialDragEnded(value)
                }
            )
    }

    private func handleSpatialTap(
        _ value: EntityTargetValue<SpatialTapGesture.Value>
    ) {
        guard PlaybackSpatialInteractionPolicy.acceptsPitchInteraction(
            hasActiveEndpointPreview: store.hasActiveCoachMarkGeometryPreview,
            hasActiveTimelineScrub: store.hasActiveTimelineScrub
        ) else { return }

        if let annotationTarget = AnnotationSceneAffordance.targetAncestor(
            of: value.entity
        ) {
            selectedAnnotationID = annotationTarget.markID
            if let mark = store.marks.first(where: { $0.id == annotationTarget.markID }) {
                reviewSpatialAnnotation(mark)
            }
            return
        }

        if let playerID = playerIDAncestor(of: value.entity),
           let player = store.selectedScenario.player(id: playerID) {
            if store.isDrawing {
                if store.selectedTool == .playerLabel {
                    store.labelPlayer(playerID)
                } else {
                    store.registerPitchTap(player.presentationPose(at: store.playhead).position)
                }
            } else {
                openPlayerPOV(playerID)
            }
            return
        }

        guard value.entity.name == "annotation-surface",
              let matchRoot = matchRootAncestor(of: value.entity) else { return }
        let point = value.convert(value.location3D, from: .local, to: matchRoot)
        guard let pitchPoint = PlaybackAnnotationStroke.projectedPitchPoint(
            SIMD3<Float>(point.x, point.y, point.z)
        ) else { return }

        if store.isDrawing, store.selectedTool == .playerLabel {
            // The pitch owns the broad input surface. Resolving the nearest
            // authored pose lets a tap on a rendered player remain a single
            // action even when a child mesh has no collision component.
            if let player = nearestPlayer(to: pitchPoint, maximumDistance: 5.5) {
                store.labelPlayer(player.id)
            } else {
                store.registerPitchTap(pitchPoint)
            }
        } else if store.isDrawing {
            store.registerPitchTap(pitchPoint)
        } else if let player = nearestPlayer(to: pitchPoint, maximumDistance: 3.2) {
            openPlayerPOV(player.id)
        }
    }

    /// Assistive technologies deliver semantic activation through RealityKit
    /// instead of the app's SpatialTapGesture. Route those events through the
    /// same annotation and POV commands so existing interaction locks remain
    /// authoritative.
    private func handleAccessibilityActivation(of entity: Entity) {
        guard PlaybackSpatialInteractionPolicy.acceptsPitchInteraction(
            hasActiveEndpointPreview: store.hasActiveCoachMarkGeometryPreview,
            hasActiveTimelineScrub: store.hasActiveTimelineScrub
        ) else { return }

        if let annotationTarget = AnnotationSceneAffordance.targetAncestor(of: entity) {
            selectedAnnotationID = annotationTarget.markID
            if let mark = store.marks.first(where: { $0.id == annotationTarget.markID }) {
                reviewSpatialAnnotation(mark)
            }
            return
        }

        // Drawing owns player activations for spatial authoring. Never make an
        // assistive activation unexpectedly abandon or mutate an active stroke.
        guard !store.isDrawing,
              let playerID = playerIDAncestor(of: entity),
              store.selectedScenario.player(id: playerID) != nil else { return }
        openPlayerPOV(playerID)
    }

    private var selectedAnnotationIsEditable: Bool {
        guard store.localRole == .coach,
              let selectedAnnotationID,
              store.marks.contains(where: { $0.id == selectedAnnotationID }) else {
            return false
        }
        return !store.selectedScenario.coachMarks.contains {
            $0.id == selectedAnnotationID
        }
    }

    private var visibleDecisionSnapshot: ReplayDecisionSnapshot? {
        guard showsDecisionStrip else { return nil }
        return store.selectedScenario.decisionReview(
            at: store.playhead,
            playerID: store.activePerspectiveID,
            currentMarks: store.marks
        )
    }

    private func handleAnnotationDragChanged(
        _ value: EntityTargetValue<DragGesture.Value>
    ) {
        guard let target = AnnotationSceneAffordance.targetAncestor(of: value.entity),
              target.role == .start || target.role == .end,
              let matchRoot = matchRootAncestor(of: value.entity),
              let mark = store.marks.first(where: { $0.id == target.markID })
        else { return }

        guard let point = pitchPoint(
            for: value,
            fallback3D: value.location3D,
            in: matchRoot
        ) else { return }
        let geometry = mark.resolvedGeometry(
            in: store.selectedScenario,
            at: store.playhead
        )
        let start = target.role == .start ? point : geometry.start
        let end = target.role == .end ? point : geometry.end
        guard store.updateCoachMarkGeometry(
            id: target.markID,
            start: start,
            end: end,
            broadcast: false
        ) else { return }

        draggedAnnotationTarget = target
        selectedAnnotationID = target.markID
    }

    private func handleAnnotationDragEnded(
        _ value: EntityTargetValue<DragGesture.Value>
    ) {
        guard let target = draggedAnnotationTarget,
              target == AnnotationSceneAffordance.targetAncestor(of: value.entity),
              let matchRoot = matchRootAncestor(of: value.entity),
              let mark = store.marks.first(where: { $0.id == target.markID })
        else {
            if let interrupted = draggedAnnotationTarget {
                _ = store.cancelCoachMarkGeometryPreview(id: interrupted.markID)
            }
            draggedAnnotationTarget = nil
            return
        }

        guard let point = pitchPoint(
            for: value,
            fallback3D: value.location3D,
            in: matchRoot
        ) else {
            _ = store.cancelCoachMarkGeometryPreview(id: target.markID)
            draggedAnnotationTarget = nil
            return
        }
        let geometry = mark.resolvedGeometry(
            in: store.selectedScenario,
            at: store.playhead
        )
        let start = target.role == .start ? point : geometry.start
        let end = target.role == .end ? point : geometry.end
        _ = store.updateCoachMarkGeometry(
            id: target.markID,
            start: start,
            end: end,
            broadcast: true
        )
        draggedAnnotationTarget = nil
    }

    private func handleAnnotationStrokeChanged(
        _ value: EntityTargetValue<DragGesture.Value>
    ) {
        let sourcePlayerID = playerIDAncestor(of: value.entity)
        guard store.isDrawing,
              store.selectedTool.requiresTwoPitchPoints,
              value.entity.name == "annotation-surface" || sourcePlayerID != nil,
              let matchRoot = matchRootAncestor(of: value.entity) else { return }

        guard let current = pitchPoint(
            for: value,
            fallback3D: value.location3D,
            in: matchRoot
        ) else { return }

        if annotationStroke == nil {
            if store.pendingDrawStart == nil {
                let start: PitchPoint
                if let sourcePlayerID,
                   let sourcePlayer = store.selectedScenario.player(id: sourcePlayerID) {
                    // Beginning on a footballer is the natural shorthand for
                    // “this player's run.” Anchor it to the authored pose.
                    start = ReplayStore.clampedPitchPoint(
                        sourcePlayer.presentationPose(at: store.playhead).position
                    )
                } else if let projectedStart = pitchPoint(
                    for: value,
                    fallback3D: value.startLocation3D,
                    in: matchRoot
                ) {
                    start = projectedStart
                } else {
                    return
                }
                _ = store.registerPitchTap(start)
            }
            guard let start = store.pendingDrawStart else { return }
            annotationStroke = PlaybackAnnotationStroke(
                kind: store.selectedTool,
                start: start
            )
        }

        guard var annotationStroke else { return }
        _ = annotationStroke.update(to: current)
        self.annotationStroke = annotationStroke
    }

    private func handleAnnotationStrokeEnded(
        _ value: EntityTargetValue<DragGesture.Value>
    ) {
        let sourcePlayerID = playerIDAncestor(of: value.entity)
        guard var annotationStroke,
              value.entity.name == "annotation-surface" || sourcePlayerID != nil,
              let matchRoot = matchRootAncestor(of: value.entity) else {
            if self.annotationStroke != nil {
                store.resetPendingAnnotationPointAfterInterruption()
            }
            self.annotationStroke = nil
            return
        }
        guard let point = pitchPoint(
            for: value,
            fallback3D: value.location3D,
            in: matchRoot
        ) else {
            self.annotationStroke = nil
            store.resetPendingAnnotationPointAfterInterruption()
            return
        }
        let endpoint = annotationStroke.finish(at: point)
        self.annotationStroke = nil

        // A short gesture deliberately leaves the first point active so the
        // coach can finish with the established two-tap interaction.
        if let endpoint {
            _ = store.registerPitchTap(endpoint)
        }
    }

    private func handleSpatialDragEnded(
        _ value: EntityTargetValue<DragGesture.Value>
    ) {
        if draggedAnnotationTarget != nil {
            handleAnnotationDragEnded(value)
            return
        }
        if annotationStroke != nil {
            handleAnnotationStrokeEnded(value)
            return
        }
        recoverTapIntentFromShortDrag(value)
    }

    private func recoverTapIntentFromShortDrag(
        _ value: EntityTargetValue<DragGesture.Value>
    ) {
        guard PlaybackSpatialInteractionPolicy.acceptsPitchInteraction(
            hasActiveEndpointPreview: store.hasActiveCoachMarkGeometryPreview,
            hasActiveTimelineScrub: store.hasActiveTimelineScrub
        ) else { return }
        guard let matchRoot = matchRootAncestor(of: value.entity),
              let start = pitchPoint(
                for: value,
                fallback3D: value.startLocation3D,
                in: matchRoot
              ),
              let end = pitchPoint(
                for: value,
                fallback3D: value.location3D,
                in: matchRoot
              ),
              SpatialPlaybackIntentRouter.shouldRecoverTapIntent(from: start, to: end)
        else { return }

        if let annotationTarget = AnnotationSceneAffordance.targetAncestor(of: value.entity),
           let mark = store.marks.first(where: { $0.id == annotationTarget.markID }) {
            selectedAnnotationID = annotationTarget.markID
            reviewSpatialAnnotation(mark)
            return
        }

        if let playerID = playerIDAncestor(of: value.entity),
           let player = store.selectedScenario.player(id: playerID) {
            if store.isDrawing {
                if store.selectedTool == .playerLabel {
                    store.labelPlayer(playerID)
                } else {
                    _ = store.registerPitchTap(
                        player.presentationPose(at: store.playhead).position
                    )
                }
            } else {
                openPlayerPOV(playerID)
            }
            return
        }

        guard value.entity.name == "annotation-surface" else { return }
        if store.isDrawing, store.selectedTool == .playerLabel {
            if let player = nearestPlayer(to: end, maximumDistance: 5.5) {
                store.labelPlayer(player.id)
            } else {
                _ = store.registerPitchTap(end)
            }
        } else if store.isDrawing {
            _ = store.registerPitchTap(end)
        } else if let player = nearestPlayer(to: end, maximumDistance: 3.2) {
            openPlayerPOV(player.id)
        }
    }

    /// Maps the system's gaze-and-pinch spatial location onto the fixed pitch.
    /// EntityTargetValue supplies the gesture in the RealityView's local 3D
    /// coordinate space. Converting into `matchRoot` keeps player-origin and
    /// pitch-origin drags consistent; deliberately dropping only Y prevents
    /// small hand-depth changes from lifting an annotation off the grass.
    ///
    /// RealityCoordinateSpaceProjecting's ray/plane convenience APIs are
    /// explicitly unavailable on visionOS in the current SDK, so this uses the
    /// native spatial sample rather than a private or camera-dependent ray.
    private func pitchPoint(
        for value: EntityTargetValue<DragGesture.Value>,
        fallback3D: Point3D,
        in matchRoot: Entity
    ) -> PitchPoint? {
        let spatialPoint = value.convert(fallback3D, from: .local, to: matchRoot)
        return PlaybackAnnotationStroke.projectedPitchPoint(
            SIMD3<Float>(spatialPoint.x, spatialPoint.y, spatialPoint.z)
        )
    }

    private func cancelInterruptedSpatialInteraction() {
        if let target = draggedAnnotationTarget {
            _ = store.cancelCoachMarkGeometryPreview(id: target.markID)
            draggedAnnotationTarget = nil
        }
        if annotationStroke != nil {
            annotationStroke = nil
            store.resetPendingAnnotationPointAfterInterruption()
        }
    }

    private func openPlayerPOV(_ playerID: String) {
        // Follow player translation while preserving headset-controlled free look.
        store.openLocalPlayerPOV(playerID)
    }

    private func reviewSpatialAnnotation(_ mark: CoachMark) {
        // A joined player must explicitly enter device-local comfort review
        // before changing time. Otherwise the UI still claims to follow the
        // coach and the next heartbeat snaps this headset back unexpectedly.
        if store.localRole == .player {
            _ = store.beginLocalReview(at: mark.revealTime)
            return
        }

        store.setPlaying(false, broadcast: false)
        // A coach selecting a shared 3D annotation owns the room's transport,
        // matching annotation selections made from the event shelf.
        store.seek(to: mark.revealTime, broadcast: store.localRole == .coach)
    }

    private func exitRoom() {
        Task {
            store.prepareForImmersiveExit()
            if store.triangleLockMode == .place {
                if store.localRole == .coach {
                    store.endTrianglePlacement()
                    await sharedSpace.removeLocallyPlacedPitchAnchor()
                } else {
                    store.revokeTrianglePlacementConsentLocally()
                }
            }
            await dismissImmersiveSpace()
            store.isImmersiveOpen = false
        }
    }
}

private struct ImmersiveRoomHeader: View {
    @Environment(ReplayStore.self) private var store

    var body: some View {
        HStack(spacing: 14) {
            Text(store.selectedScenario.kind.number)
                .font(.title2.monospacedDigit().weight(.black))
                .foregroundStyle(.black)
                .frame(width: 50, height: 50)
                .background(ReplayTheme.signal, in: RoundedRectangle(cornerRadius: 13))

            VStack(alignment: .leading, spacing: 3) {
                Eyebrow(text: store.selectedScenario.kind.shortLabel)
                Text(store.selectedScenario.title)
                    .font(.title2.weight(.black))
                Text(store.activeMoment?.headline ?? store.selectedScenario.objective)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 4) {
                Text(formatTime(store.playhead))
                    .font(.title2.monospacedDigit().weight(.black))
                Text(store.activeMoment?.kicker ?? "READY")
                    .font(.caption2.monospaced().weight(.black))
                    .foregroundStyle(ReplayTheme.orange)
            }

            StatusPill(
                text: "LOCAL REPLAY",
                systemImage: "visionpro"
            )
        }
        .padding(18)
        .glassBackgroundEffect(in: .rect(cornerRadius: 24))
    }

    private func formatTime(_ time: TimeInterval) -> String {
        String(format: "00:%05.2f", max(0, time))
    }
}

private enum PlaybackReviewEvent: Identifiable {
    case cue(CueMoment)
    case mark(CoachMark)

    var id: String {
        switch self {
        case .cue(let cue): "cue-\(cue.id)"
        case .mark(let mark): "mark-\(mark.id.uuidString)"
        }
    }

    var time: TimeInterval {
        switch self {
        case .cue(let cue): cue.time
        case .mark(let mark): mark.revealTime
        }
    }
}

/// Only event-rail metadata participates in this signature. Endpoint drags
/// replace a `CoachMark` many times per second, but changing spatial geometry
/// cannot change timeline order or labels and must not trigger a sort/rebuild.
struct PlaybackReviewIndexKey: Equatable, Sendable {
    let id: UUID
    let kind: String
    let label: String
    let revealTime: TimeInterval
    let hideTime: TimeInterval?

    nonisolated init(mark: CoachMark) {
        id = mark.id
        kind = mark.kind.rawValue
        label = mark.label
        revealTime = mark.revealTime
        hideTime = mark.hideTime
    }
}

enum PlaybackAttachmentPlacement {
    static func followsHead(_ attachmentID: String) -> Bool {
        attachmentID == "coach-console" || attachmentID == "playback-view-hud"
    }

    static func controlAnchorTrackingMode(
        prefersHeadAnchorAlternative: Bool
    ) -> AnchoringComponent.TrackingMode {
        prefersHeadAnchorAlternative ? .once : .continuous
    }
}

/// Applies a wearer-local visibility gate after PitchSceneFactory has resolved
/// the authored scene state. Playback marks can be restored directly on a
/// hide/show round trip; Shape Focus retains its scene-owned marks visibility.
/// Selection, draft and input entities are only forced off because their visible
/// states are conditional and are restored by the next scene update when needed.
enum PlaybackLocalOverlayVisibility {
    static func apply(
        to root: Entity,
        showsAnnotations: Bool,
        canOverrideMarksRoot: Bool
    ) {
        // Shape Focus and the other authored exercises own their annotation
        // visibility. A wearer-local Playback preference must not leak across a
        // scenario change and disable those scene-owned teaching cues.
        guard canOverrideMarksRoot else { return }

        directChild(named: "marks-root", of: root)?.isEnabled = showsAnnotations

        guard !showsAnnotations else { return }
        directChild(named: AnnotationSceneAffordance.selectionRootName, of: root)?.isEnabled = false
        directChild(named: "annotation-draft-root", of: root)?.isEnabled = false
        directChild(named: "annotation-surface", of: root)?.isEnabled = false
    }

    private static func directChild(named name: String, of root: Entity) -> Entity? {
        root.children.first { $0.name == name }
    }
}

/// Immersive spaces cannot host SwiftUI's pop-up presentation controls. Keep
/// every secondary Playback action in one mutually exclusive, in-deck shelf
/// instead. Associated annotation IDs prevent a shelf from silently editing a
/// different mark after the selection changes.
enum PlaybackInlinePanel: Equatable, Sendable {
    case settings
    case savedReviews
    case annotationEdit
    case annotationDuration(UUID)
    case annotationGeometry(UUID)
    case annotationLabel(UUID)
    case annotationTracking(UUID)

    static func toggled(
        current: PlaybackInlinePanel?,
        candidate: PlaybackInlinePanel
    ) -> PlaybackInlinePanel? {
        current == candidate ? nil : candidate
    }

    func isValid(for selectedAnnotationID: UUID?) -> Bool {
        switch self {
        case .settings, .savedReviews, .annotationEdit:
            true
        case .annotationDuration(let id),
             .annotationGeometry(let id),
             .annotationLabel(let id),
             .annotationTracking(let id):
            selectedAnnotationID == id
        }
    }
}

/// Shared copy and sizing rules for the compact Playback surface. Keeping these
/// decisions outside the private SwiftUI view makes the two camera contexts and
/// the spatial hit-target floor independently testable.
enum PlaybackControlDeckPresentation {
    static let minimumSpatialHitTarget: CGFloat = 60

    static func playerControlLabel(
        shirtNumber: Int?
    ) -> String {
        guard let shirtNumber else { return "POV PLAYER" }
        return "POV #\(shirtNumber)"
    }

    static func shouldDismissDrawTools(annotationsAreVisible: Bool) -> Bool {
        !annotationsAreVisible
    }
}

/// A joystick owns annotation selection until its physical pinch ends. The
/// RealityView's independent tap recognizer must honor the same barrier as the
/// SwiftUI deck or a second hand can select a different mark before the first
/// transaction has cancelled, leaving the inspector at the wrong timestamp.
enum PlaybackSpatialInteractionPolicy {
    static func acceptsPitchInteraction(
        hasActiveEndpointPreview: Bool,
        hasActiveTimelineScrub: Bool = false
    ) -> Bool {
        !hasActiveEndpointPreview && !hasActiveTimelineScrub
    }
}

enum PlaybackOverlayBadge: String, CaseIterable, Hashable, Identifiable, Sendable {
    case annotations
    case ball
    case lanes

    var id: Self { self }

    var systemImage: String {
        switch self {
        case .annotations: "arrow.up.right"
        case .ball: "scope"
        case .lanes: "arrow.triangle.branch"
        }
    }

    var accessibilityName: String {
        switch self {
        case .annotations: "Annotations"
        case .ball: "Ball highlight"
        case .lanes: "Passing lanes"
        }
    }

    static func activeBadges(
        showsAnnotations: Bool,
        emphasizesBall: Bool,
        showsLanes: Bool,
        supportsLanes: Bool
    ) -> [PlaybackOverlayBadge] {
        var badges: [PlaybackOverlayBadge] = []
        if showsAnnotations { badges.append(.annotations) }
        if emphasizesBall { badges.append(.ball) }
        if supportsLanes, showsLanes { badges.append(.lanes) }
        return badges
    }
}

/// Converts a free 2D drag into predictable quarter-metre pitch steps. The
/// dead zone prevents an eye-pinch from moving a mark before the wearer means
/// to steer, while the bounded step count makes one gesture reversible.
struct AnnotationJoystickMath: Equatable, Sendable {
    struct Sample: Equatable, Sendable {
        let knobOffset: CGSize
        let steps: SIMD2<Int>

        static let zero = Sample(knobOffset: .zero, steps: .zero)
    }

    static let deadZone: CGFloat = 12
    // Four distinct thresholds must fit before either axis reaches its
    // 38-point square gate. At 12, 20, 28 and 36 points every accepted
    // quarter-metre notch has visible travel, including a diagonal request.
    static let pointsPerStep: CGFloat = 8
    static let maximumTravel: CGFloat = 38
    static let maximumSteps = 4

    static func sample(for translation: CGSize) -> Sample {
        guard translation.width.isFinite, translation.height.isFinite else {
            return .zero
        }

        let offset = CGSize(
            width: min(max(translation.width, -maximumTravel), maximumTravel),
            height: min(max(translation.height, -maximumTravel), maximumTravel)
        )

        return Sample(
            knobOffset: offset,
            steps: SIMD2<Int>(
                quantizedSteps(for: translation.width),
                quantizedSteps(for: translation.height)
            )
        )
    }

    private static func quantizedSteps(for value: CGFloat) -> Int {
        let magnitude = abs(value)
        guard magnitude > deadZone else { return 0 }
        let count = min(
            1 + Int((magnitude - deadZone) / pointsPerStep),
            maximumSteps
        )
        return value < 0 ? -count : count
    }
}

enum AnnotationJoystickGesturePolicy {
    static func shouldSubmit(
        sample: AnnotationJoystickMath.Sample,
        after requestedSteps: SIMD2<Int>
    ) -> Bool {
        sample.steps != requestedSteps
    }
}

enum AnnotationJoystickAccessibility {
    static func value(
        isEnabled: Bool,
        appliedDelta: PitchPoint,
        hasActiveTransaction: Bool,
        latestRequestWasAccepted: Bool,
        lastAction: String?
    ) -> String {
        guard isEnabled else {
            return "Unavailable while the other endpoint is being adjusted"
        }
        if let lastAction { return lastAction }
        guard latestRequestWasAccepted else {
            return "Position unavailable; lift to cancel the adjustment"
        }
        guard hasActiveTransaction, appliedDelta != .zero else {
            return "Centred; each step moves 25 centimetres"
        }
        return "Preview moved " + movementDescription(appliedDelta)
    }

    static func movementDescription(_ delta: PitchPoint) -> String {
        var parts: [String] = []
        if abs(delta.x) >= 0.000_1 {
            parts.append(axisDescription(delta.x, positive: "right", negative: "left"))
        }
        if abs(delta.z) >= 0.000_1 {
            parts.append(axisDescription(delta.z, positive: "upfield", negative: "back"))
        }
        return parts.isEmpty ? "to its starting point" : parts.joined(separator: ", ")
    }

    private static func axisDescription(
        _ value: Float,
        positive: String,
        negative: String
    ) -> String {
        let centimetres = Int((abs(value) * 100).rounded())
        return "\(centimetres) centimetres \(value >= 0 ? positive : negative)"
    }
}

/// View and overlay controls stay visible in the upper-left comfort quadrant,
/// independent of the lower transport. Expanding this surface is an in-place
/// shelf: immersive spaces never receive a Menu, sheet, popover, or alert.
private struct PlaybackViewOverlayHUD: View {
    @Environment(ReplayStore.self) private var store
    @Binding var showsPlaybackAnnotations: Bool
    @Binding var emphasizesBall: Bool
    @State private var isExpanded = false

    var body: some View {
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
                        .frame(width: 34, height: PlaybackControlDeckPresentation.minimumSpatialHitTarget)

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
                        .frame(width: 34, height: PlaybackControlDeckPresentation.minimumSpatialHitTarget)
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

                VStack(alignment: .leading, spacing: 5) {
                    Eyebrow(text: "Camera", color: ReplayTheme.signal)
                    HStack(spacing: 6) {
                        ForEach(playbackViewModes, id: \.self) { mode in
                            viewChoice(mode)
                        }
                    }
                }

                VStack(alignment: .leading, spacing: 5) {
                    Eyebrow(text: "Overlays", color: ReplayTheme.orange)
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
                            title: "Ball glow",
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
        .glassBackgroundEffect(in: .rect(cornerRadius: 20))
        .task {
            #if DEBUG
            if ProcessInfo.processInfo.arguments.contains("--replayxi-view-hud-expanded") {
                isExpanded = true
            }
            #endif
        }
    }

    private var playbackViewModes: [ReplayViewMode] {
        [.firstPerson, .tacticalTable, .touchline]
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
            .frame(width: 28, height: 28)
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
                    .font(.caption2.monospaced().weight(.black))
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
        .disabled(store.hasActiveCoachMarkGeometryPreview)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(mode.title) view")
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
        .disabled(!isEnabled || store.hasActiveCoachMarkGeometryPreview)
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

private struct AnnotationAdjustmentJoystick: View {
    let title: String
    let accessibilityTarget: String
    let color: Color
    let isEnabled: Bool
    let onPreview: (_ gestureID: UUID, _ cumulativeX: Float, _ cumulativeZ: Float) -> CoachMarkEndpointPreviewResult?
    let onCommit: (_ gestureID: UUID) -> PitchPoint?
    let onCancel: (_ gestureID: UUID) -> Bool
    let onAtomicNudge: (_ x: Float, _ z: Float) -> Bool

    @State private var sample = AnnotationJoystickMath.Sample.zero
    @State private var requestedSteps = SIMD2<Int>.zero
    @State private var transactionIsActive = false
    @State private var latestRequestWasAccepted = true
    @State private var gestureID: UUID?
    @State private var acceptedDelta = PitchPoint.zero
    @State private var lastAccessibilityAction: String?
    @GestureState private var joystickDragIsActive = false

    private let stepMetres: Float = 0.25

    private struct CompletionState {
        let transactionIsActive: Bool
        let latestRequestWasAccepted: Bool
        let gestureID: UUID?
    }

    var body: some View {
        VStack(spacing: 5) {
            Eyebrow(text: title, color: color)

            ZStack {
                RoundedRectangle(cornerRadius: 24)
                    .fill(.white.opacity(0.055))
                RoundedRectangle(cornerRadius: 24)
                    .stroke(color.opacity(0.32), lineWidth: 1.5)

                Rectangle()
                    .fill(.white.opacity(0.12))
                    .frame(width: 1, height: 74)
                Rectangle()
                    .fill(.white.opacity(0.12))
                    .frame(width: 74, height: 1)

                Image(systemName: "arrow.up")
                    .offset(y: -42)
                Image(systemName: "arrow.down")
                    .offset(y: 42)
                Image(systemName: "arrow.left")
                    .offset(x: -42)
                Image(systemName: "arrow.right")
                    .offset(x: 42)

                Circle()
                    .fill(color.gradient)
                    .frame(width: 42, height: 42)
                    .overlay(Circle().stroke(.black.opacity(0.24), lineWidth: 2))
                    .shadow(color: color.opacity(0.34), radius: 8)
                    .offset(sample.knobOffset)
            }
            .font(.caption2.weight(.black))
            .foregroundStyle(.white.opacity(0.54))
            .frame(width: 120, height: 120)
            .contentShape(RoundedRectangle(cornerRadius: 24))
            .gesture(joystickGesture)

            Text("0.25 M STEPS")
                .font(.caption2.monospaced().weight(.black))
                .foregroundStyle(.white.opacity(0.58))
                .lineLimit(1)
        }
        .padding(.horizontal, 8)
        .opacity(isEnabled ? 1 : 0.42)
        .allowsHitTesting(isEnabled)
        .disabled(!isEnabled)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Adjust \(accessibilityTarget)")
        .accessibilityValue(accessibilityValue)
        .accessibilityHint(
            isEnabled
                ? "Pinch and drag. Up moves upfield and down moves back."
                : "Finish the active endpoint adjustment first."
        )
        .accessibilityAction(named: "Move left") { atomicNudge(x: -stepMetres, z: 0) }
        .accessibilityAction(named: "Move right") { atomicNudge(x: stepMetres, z: 0) }
        .accessibilityAction(named: "Move upfield") { atomicNudge(x: 0, z: stepMetres) }
        .accessibilityAction(named: "Move back") { atomicNudge(x: 0, z: -stepMetres) }
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: atomicNudge(x: 0, z: stepMetres)
            case .decrement: atomicNudge(x: 0, z: -stepMetres)
            @unknown default: break
            }
        }
        .onDisappear {
            cancelTransactionAndReset()
        }
        .onChange(of: joystickDragIsActive) { wasActive, isActive in
            guard wasActive, !isActive, transactionIsActive else { return }
            // GestureState also resets when visionOS interrupts a pinch without
            // delivering a normal end sample (for example, tracking loss).
            cancelTransactionAndReset()
        }
    }

    private var joystickGesture: some Gesture {
        DragGesture(minimumDistance: 0)
            .updating($joystickDragIsActive) { _, isActive, _ in
                isActive = true
            }
            .onChanged { value in
                _ = applyJoystickTranslation(value.translation)
            }
            .onEnded { value in
                // `onEnded` owns the authoritative final translation. A fast
                // lift can cross a notch after the last `onChanged` delivery,
                // so submit that sample before deciding whether to commit.
                let completion = applyJoystickTranslation(value.translation)
                if completion.transactionIsActive, let gestureID = completion.gestureID {
                    if completion.latestRequestWasAccepted {
                        if let committedDelta = onCommit(gestureID) {
                            lastAccessibilityAction = "Moved "
                                + AnnotationJoystickAccessibility.movementDescription(committedDelta)
                        } else {
                            lastAccessibilityAction = "Adjustment cancelled"
                        }
                    } else {
                        _ = onCancel(gestureID)
                        lastAccessibilityAction = "Adjustment cancelled"
                    }
                }
                resetJoystick(preservingAccessibilityAction: true)
            }
    }

    @discardableResult
    private func applyJoystickTranslation(_ translation: CGSize) -> CompletionState {
        guard isEnabled else {
            return CompletionState(
                transactionIsActive: transactionIsActive,
                latestRequestWasAccepted: latestRequestWasAccepted,
                gestureID: gestureID
            )
        }

        let next = AnnotationJoystickMath.sample(for: translation)
        sample = next
        guard AnnotationJoystickGesturePolicy.shouldSubmit(
            sample: next,
            after: requestedSteps
        ) else {
            return CompletionState(
                transactionIsActive: transactionIsActive,
                latestRequestWasAccepted: latestRequestWasAccepted,
                gestureID: gestureID
            )
        }

        requestedSteps = next.steps
        lastAccessibilityAction = nil
        let resolvedGestureID = gestureID ?? UUID()
        gestureID = resolvedGestureID

        // Steps are an absolute request from the gesture origin, never an
        // increment from the last accepted sample. The store returns the exact
        // per-axis clamp and retains the immutable baseline.
        let result = onPreview(
            resolvedGestureID,
            Float(next.steps.x) * stepMetres,
            Float(-next.steps.y) * stepMetres
        )
        let requestWasAccepted = result != nil
        latestRequestWasAccepted = requestWasAccepted
        if let result {
            transactionIsActive = result.hasActiveTransaction
            acceptedDelta = result.appliedDelta
        }
        return CompletionState(
            transactionIsActive: transactionIsActive,
            latestRequestWasAccepted: requestWasAccepted,
            gestureID: resolvedGestureID
        )
    }

    @discardableResult
    private func atomicNudge(x: Float, z: Float) -> Bool {
        guard isEnabled else { return false }
        let succeeded = onAtomicNudge(x, z)
        lastAccessibilityAction = succeeded
            ? "Moved " + AnnotationJoystickAccessibility.movementDescription(PitchPoint(x: x, z: z))
            : "Movement unavailable at this boundary"
        return succeeded
    }

    private var accessibilityValue: String {
        AnnotationJoystickAccessibility.value(
            isEnabled: isEnabled,
            appliedDelta: acceptedDelta,
            hasActiveTransaction: transactionIsActive,
            latestRequestWasAccepted: latestRequestWasAccepted,
            lastAction: lastAccessibilityAction
        )
    }

    private func resetJoystick(preservingAccessibilityAction: Bool = false) {
        requestedSteps = .zero
        transactionIsActive = false
        latestRequestWasAccepted = true
        gestureID = nil
        acceptedDelta = .zero
        if !preservingAccessibilityAction {
            lastAccessibilityAction = nil
        }
        withAnimation(.spring(duration: 0.22, bounce: 0.22)) {
            sample = .zero
        }
    }

    private func cancelTransactionAndReset() {
        if transactionIsActive, let gestureID {
            _ = onCancel(gestureID)
            lastAccessibilityAction = "Adjustment cancelled"
        }
        resetJoystick(preservingAccessibilityAction: true)
    }
}

private struct ImmersiveControlDeck: View {
    @Environment(ReplayStore.self) private var store
    @State private var annotationConfirmation: String?
    @State private var showsEventStrip = false
    @State private var showsPlayerGrid = false
    @State private var eventPage = 0
    @State private var orderedReviewMarks: [CoachMark] = []
    @State private var indexedReviewEvents: [PlaybackReviewEvent] = []
    @State private var timelineTickClusters: [PlaybackEventRailLayout.TimelineTickCluster] = []
    @State private var timelineTrackWidth: CGFloat = 0
    @State private var timelineScrubState: PlaybackTimelineScrub.GestureState?
    @GestureState private var timelineScrubIsActive = false
    @State private var isClearAnnotationsPending = false
    @State private var inlinePanel: PlaybackInlinePanel?
    @State private var showsAnnotationTools = false
    @State private var showsToolsShelf = false
    @Binding var selectedAnnotationID: UUID?
    @Binding var showsDecisionStrip: Bool
    @Binding var showsPlaybackAnnotations: Bool
    @Binding var controlDeckPresetRawValue: String

    let deckWidth: CGFloat
    let isPinchDrawing: Bool
    let isPinchDrawingReady: Bool
    let exit: () -> Void

    var body: some View {
        Group {
            if store.triangleLockMode == .place {
            HStack(spacing: 12) {
                Button(action: exit) {
                    Image(systemName: "xmark")
                }
                .buttonStyle(.bordered)
                .accessibilityLabel("Exit spatial replay")

                Image(systemName: "figure.stand")
                    .foregroundStyle(ReplayTheme.orange)
                VStack(alignment: .leading, spacing: 2) {
                    Eyebrow(text: "Shape Focus • Step 3 of 3", color: ReplayTheme.orange)
                    Text("Physical stations • replay paused • movements stay slow")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                StatusPill(
                    text: store.hasLocallyAcknowledgedTrianglePlacement ? "LOCAL CONSENT" : "WAITING FOR CONSENT",
                    systemImage: store.hasLocallyAcknowledgedTrianglePlacement ? "checkmark.shield" : "hand.raised.fill",
                    color: store.hasLocallyAcknowledgedTrianglePlacement ? ReplayTheme.signal : ReplayTheme.orange
                )
            }
            .padding(18)
            .glassBackgroundEffect(in: .rect(cornerRadius: 26))
        } else if store.selectedScenario.kind == .shapeLab {
            shapeFocusStatusDeck
        } else if store.isDrawing {
            annotationDrawingShelf
        } else {
            matchPlaybackDeck
        }
        }
        .onDisappear {
            cancelInterruptedTimelineScrub()
        }
        .onChange(of: timelineScrubIsActive) { wasActive, isActive in
            guard wasActive, !isActive, timelineScrubState != nil else { return }
            // A normal lift clears the transaction in `onEnded` first. Reaching
            // this branch means tracking ended without a commit.
            cancelInterruptedTimelineScrub()
        }
        .onChange(of: showsPlaybackAnnotations) { _, isVisible in
            guard PlaybackControlDeckPresentation.shouldDismissDrawTools(
                annotationsAreVisible: isVisible
            ) else { return }
            if let selectedAnnotationID {
                _ = store.cancelCoachMarkGeometryPreview(id: selectedAnnotationID)
            }
            selectedAnnotationID = nil
            if inlinePanel != .settings && inlinePanel != .savedReviews {
                inlinePanel = nil
            }
            isClearAnnotationsPending = false
            showsAnnotationTools = false
            if store.isDrawing {
                store.cancelDrawing()
            }
        }
    }

    private var matchPlaybackDeck: some View {
        VStack(alignment: .leading, spacing: 11) {
            HStack(spacing: 8) {
                Button(action: exit) {
                    Image(systemName: "xmark")
                        .frame(
                            minWidth: PlaybackControlDeckPresentation.minimumSpatialHitTarget,
                            minHeight: PlaybackControlDeckPresentation.minimumSpatialHitTarget
                        )
                }
                .buttonStyle(.bordered)
                .accessibilityLabel("Exit spatial replay")

                Button {
                    if let previousCue { jump(to: previousCue) }
                } label: {
                    Image(systemName: "backward.end.fill")
                        .frame(
                            minWidth: PlaybackControlDeckPresentation.minimumSpatialHitTarget,
                            minHeight: PlaybackControlDeckPresentation.minimumSpatialHitTarget
                        )
                }
                .buttonStyle(.bordered)
                .disabled(previousCue == nil || timelineControlsAreDisabled)
                .accessibilityLabel("Previous cue")

                Button(action: handlePrimaryPlaybackAction) {
                    Image(systemName: primaryPlaybackSystemImage)
                        .font(.subheadline.weight(.black))
                        .frame(width: 64, height: PlaybackControlDeckPresentation.minimumSpatialHitTarget)
                }
                .buttonStyle(.borderedProminent)
                .tint(ReplayTheme.signal)
                .foregroundStyle(.black)
                .disabled(primaryPlaybackControlIsDisabled)
                .accessibilityLabel(primaryPlaybackLabel)

                Button {
                    if let nextCue { jump(to: nextCue) }
                } label: {
                    Image(systemName: "forward.end.fill")
                        .frame(
                            minWidth: PlaybackControlDeckPresentation.minimumSpatialHitTarget,
                            minHeight: PlaybackControlDeckPresentation.minimumSpatialHitTarget
                        )
                }
                .buttonStyle(.bordered)
                .disabled(nextCue == nil || timelineControlsAreDisabled)
                .accessibilityLabel("Next cue")

                timelineScrubber
                    .layoutPriority(1)

                compactPlayerControlButton
                if store.localRole == .coach {
                    annotationToolsButton
                }
                playbackToolsButton
            }

            if isClearAnnotationsPending {
                clearAnnotationsConfirmationStrip
            } else if showsPlayerGrid {
                playerPOVGrid
            } else if showsToolsShelf {
                playbackToolsShelf
            } else if showsDecisionStrip, let decisionSnapshot {
                PlaybackDecisionStrip(
                    snapshot: decisionSnapshot,
                    scenario: store.selectedScenario,
                    onSelectPlayer: openPlayerPOV,
                    onClose: { showsDecisionStrip = false }
                )
            } else if let inlinePanel {
                inlinePanelShelf(inlinePanel)
            } else if let selectedAnnotation {
                selectedAnnotationInspector(selectedAnnotation)
            } else if showsEventStrip {
                annotationEventStrip
            } else if store.localRole == .coach, showsAnnotationTools {
                coachAnnotationStrip
            }
        }
        .padding(18)
        .padding(4)
        .frame(width: deckWidth)
        .controlSize(.extraLarge)
        .background(ReplayTheme.navy.opacity(0.46), in: RoundedRectangle(cornerRadius: 26))
        .overlay {
            RoundedRectangle(cornerRadius: 26)
                .stroke(.white.opacity(0.13), lineWidth: 1)
        }
        .glassBackgroundEffect(in: .rect(cornerRadius: 26))
        .task {
            #if DEBUG
            if ProcessInfo.processInfo.arguments.contains("--replayxi-saved-reviews") {
                inlinePanel = .savedReviews
            }
            #endif
        }
        .onChange(of: store.marks.count) { oldCount, newCount in
            guard store.localRole == .coach,
                  newCount > oldCount,
                  newCount > store.selectedScenario.coachMarks.count,
                  let mark = store.marks.last else { return }
            annotationConfirmation = "\(mark.kind.title.uppercased()) SAVED · \(formatTime(mark.revealTime))"
            // Saving is the end of the spatial gesture, not an instruction to
            // open another editing workflow. Keep the compact draw shelf ready
            // for the coach's next mark; Events remains the explicit route to
            // retiming, relabelling, endpoint editing or deletion.
            selectedAnnotationID = nil
            showsDecisionStrip = false
            showsEventStrip = false
            showsPlayerGrid = false
            showsToolsShelf = false
        }
        .onChange(of: store.selectedScenarioID) { _, _ in
            selectedAnnotationID = nil
            cancelInterruptedTimelineScrub()
            showsDecisionStrip = false
            showsEventStrip = false
            showsPlayerGrid = false
            showsToolsShelf = false
            isClearAnnotationsPending = false
            inlinePanel = nil
            showsAnnotationTools = false
            eventPage = 0
            annotationConfirmation = nil
            rebuildReviewIndex()
        }
        .onChange(of: store.reviewIndexVersion) { _, _ in
            rebuildReviewIndex()
        }
        .onChange(of: selectedAnnotationID) { _, selectedID in
            // Secondary controls belong to the selection that opened them.
            // Never carry a label, duration, geometry, or tracking shelf onto
            // a new mark.
            inlinePanel = nil
            if selectedID != nil {
                showsPlayerGrid = false
                showsAnnotationTools = false
                showsToolsShelf = false
            }
            rebuildTimelineTickClusters(selectionID: selectedID)
        }
        .onChange(of: store.playhead) { _, playhead in
            guard let selectedAnnotationID,
                  let selected = store.marks.first(where: { $0.id == selectedAnnotationID }),
                  !isCoachCreated(selected),
                  !selected.isVisible(at: playhead) else { return }
            // Fixture annotations cannot be held visible for editing. Once
            // their authored time window leaves the playhead, close the stale
            // inspector so text never describes geometry that is no longer in
            // the scene.
            self.selectedAnnotationID = nil
        }
        .task {
            PlaybackEventRailLayout.prepareTimelineTickClusters(&timelineTickClusters)
            rebuildReviewIndex()
            #if DEBUG
            let arguments = ProcessInfo.processInfo.arguments
            if arguments.contains("--replayxi-large-controls") {
                controlDeckPresetRawValue = PlaybackControlDeckPreset.large.rawValue
            }
            if arguments.contains("--replayxi-tools") {
                inlinePanel = nil
                selectedAnnotationID = nil
                showsEventStrip = false
                showsDecisionStrip = false
                showsPlayerGrid = false
                showsAnnotationTools = false
                showsToolsShelf = true
            }
            if arguments.contains("--replayxi-events") {
                inlinePanel = nil
                showsEventStrip = true
                showsAnnotationTools = false
                showsToolsShelf = false
            }
            if arguments.contains("--replayxi-player-grid") {
                inlinePanel = nil
                showsPlayerGrid = true
                showsEventStrip = false
                showsDecisionStrip = false
                showsAnnotationTools = false
                showsToolsShelf = false
            }
            if arguments.contains("--replayxi-options") {
                inlinePanel = nil
                selectedAnnotationID = nil
                showsEventStrip = false
                showsDecisionStrip = true
                showsAnnotationTools = false
                showsToolsShelf = false
                store.setPlaying(false, broadcast: false)
            }
            if arguments.contains("--replayxi-select-coach-mark") {
                inlinePanel = nil
                selectedAnnotationID = store.marks.last?.id
                showsDecisionStrip = false
                showsEventStrip = true
                showsAnnotationTools = false
                showsToolsShelf = false
            }
            if arguments.contains("--replayxi-clear-confirm") {
                inlinePanel = nil
                isClearAnnotationsPending = true
                selectedAnnotationID = nil
                showsDecisionStrip = false
                showsEventStrip = false
                showsAnnotationTools = false
                showsToolsShelf = false
            }
            if arguments.contains("--replayxi-inline-settings") {
                selectedAnnotationID = nil
                showsDecisionStrip = false
                showsEventStrip = false
                showsPlayerGrid = false
                isClearAnnotationsPending = false
                inlinePanel = .settings
                showsAnnotationTools = false
                showsToolsShelf = false
            }
            #endif
        }
        .task(id: annotationConfirmation) {
            guard annotationConfirmation != nil else { return }
            try? await Task.sleep(for: .seconds(2.4))
            guard !Task.isCancelled else { return }
            annotationConfirmation = nil
        }
        .task(id: isClearAnnotationsPending) {
            guard isClearAnnotationsPending else { return }
            try? await Task.sleep(for: .seconds(6))
            guard !Task.isCancelled else { return }
            isClearAnnotationsPending = false
        }
    }

    private var playbackToolsButton: some View {
        Button {
            togglePlaybackToolsShelf()
        } label: {
            VStack(spacing: 1) {
                Image(systemName: "square.grid.2x2.fill")
                    .font(.headline.weight(.black))
                Text("TOOLS")
                    .font(.caption.monospaced().weight(.black))
                    .lineLimit(1)
            }
            .frame(width: 78, height: PlaybackControlDeckPresentation.minimumSpatialHitTarget)
        }
        .buttonStyle(.borderedProminent)
        .tint(toolsWorkflowIsPresented ? ReplayTheme.cyan : .white.opacity(0.10))
        .foregroundStyle(toolsWorkflowIsPresented ? Color.black : Color.white)
        .disabled(secondaryPlaybackControlsAreDisabled)
        .accessibilityLabel("Playback tools")
        .accessibilityValue(
            "Timeline, decision review, settings"
        )
        .accessibilityHint(
            showsToolsShelf
                ? "Closes the playback tools shelf"
                : "Opens timeline, decision review, settings, and annotation editing"
        )
        .accessibilityAddTraits(toolsWorkflowIsPresented ? .isSelected : [])
    }

    private var compactPlayerControlButton: some View {
        Button {
            let opensRoster = !showsPlayerGrid
            inlinePanel = nil
            selectedAnnotationID = nil
            showsEventStrip = false
            showsDecisionStrip = false
            showsAnnotationTools = false
            showsToolsShelf = false
            showsPlayerGrid = opensRoster
        } label: {
            VStack(spacing: 1) {
                Image(systemName: "person.crop.rectangle.stack.fill")
                    .font(.headline.weight(.bold))
                Text(activePlayerCompactLabel)
                    .font(.caption.monospaced().weight(.black))
                    .lineLimit(1)
                    .minimumScaleFactor(0.82)
            }
            .frame(width: 116, height: PlaybackControlDeckPresentation.minimumSpatialHitTarget)
        }
        .buttonStyle(.borderedProminent)
        .tint(showsPlayerGrid ? ReplayTheme.signal : .white.opacity(0.10))
        .foregroundStyle(showsPlayerGrid ? Color.black : Color.white)
        .disabled(playerControlIsDisabled)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            activePlayerAccessibilityLabel
        )
        .accessibilityHint(
            showsPlayerGrid
                ? "Closes the 22-player roster"
                : "Opens direct point-of-view targets for all 22 players"
        )
        .accessibilityAddTraits(showsPlayerGrid ? .isSelected : [])
        .accessibilityAction(named: "Previous player") {
            openAdjacentPlayerPOV(by: -1)
        }
        .accessibilityAction(named: "Next player") {
            openAdjacentPlayerPOV(by: 1)
        }
    }

    private var activePlayerCompactLabel: String {
        PlaybackControlDeckPresentation.playerControlLabel(
            shirtNumber: store.activePerspective?.shirtNumber
        )
    }

    private var activePlayerAccessibilityLabel: String {
        guard let player = store.activePerspective else {
            return "Choose player point of view"
        }
        return "Player point of view, number \(player.shirtNumber), \(player.role)"
    }

    private var annotationToolsButton: some View {
        Button {
            let opensTools = !showsAnnotationTools
            inlinePanel = nil
            selectedAnnotationID = nil
            showsPlayerGrid = false
            showsEventStrip = false
            showsDecisionStrip = false
            showsToolsShelf = false
            isClearAnnotationsPending = false
            showsAnnotationTools = opensTools
            if opensTools {
                showsPlaybackAnnotations = true
            }
        } label: {
            VStack(spacing: 1) {
                Image(systemName: "pencil.and.outline")
                    .font(.headline.weight(.bold))
                Text("DRAW")
                    .font(.caption.monospaced().weight(.black))
                    .lineLimit(1)
            }
            .frame(width: 76, height: PlaybackControlDeckPresentation.minimumSpatialHitTarget)
        }
        .buttonStyle(.borderedProminent)
        .tint(showsAnnotationTools ? ReplayTheme.orange : .white.opacity(0.10))
        .foregroundStyle(showsAnnotationTools ? Color.black : Color.white)
        .disabled(store.hasActiveCoachMarkGeometryPreview)
        .accessibilityLabel("Draw annotations")
        .accessibilityHint(
            showsAnnotationTools ? "Closes drawing tools" : "Opens run, pass, press, zone, and label tools"
        )
        .accessibilityAddTraits(showsAnnotationTools ? .isSelected : [])
    }

    private var controlDeckPreset: PlaybackControlDeckPreset {
        PlaybackControlDeckPreset(rawValue: controlDeckPresetRawValue) ?? .standard
    }

    private func annotationEditButton(compact: Bool) -> some View {
        Button {
            // The drawing shelf is a top-level compact mode. Leave it before
            // opening the inline editor so Undo/Clear cannot become an
            // invisible selected control underneath that shelf.
            if store.isDrawing {
                store.cancelDrawing()
            }
            toggleInlinePanel(.annotationEdit)
        } label: {
            Group {
                if compact {
                    Image(systemName: "eraser.fill")
                        .frame(
                            minWidth: PlaybackControlDeckPresentation.minimumSpatialHitTarget,
                            minHeight: PlaybackControlDeckPresentation.minimumSpatialHitTarget
                        )
                } else {
                    Label("Edit marks", systemImage: "eraser.fill")
                        .font(.subheadline.weight(.black))
                        .lineLimit(1)
                        .minimumScaleFactor(0.78)
                        .frame(width: 124, height: PlaybackControlDeckPresentation.minimumSpatialHitTarget)
                }
            }
        }
        .buttonStyle(.bordered)
        .disabled(
            store.localRole != .coach
                || clearableCoachAnnotationCount == 0
                || store.hasActiveCoachMarkGeometryPreview
        )
        .accessibilityLabel("Edit annotations")
        .accessibilityValue("\(clearableCoachAnnotationCount) coach marks")
        .accessibilityHint("Opens undo and clear controls")
        .accessibilityAddTraits(inlinePanel == .annotationEdit ? .isSelected : [])
    }

    private var playbackToolsShelf: some View {
        inlineShelf(color: ReplayTheme.cyan) {
            HStack(spacing: 10) {
                Button {
                    showsToolsShelf = false
                } label: {
                    Image(systemName: "xmark")
                        .frame(
                            minWidth: PlaybackControlDeckPresentation.minimumSpatialHitTarget,
                            minHeight: PlaybackControlDeckPresentation.minimumSpatialHitTarget
                        )
                }
                .buttonStyle(.bordered)
                .accessibilityLabel("Close playback tools")

                VStack(alignment: .leading, spacing: 2) {
                    Eyebrow(text: "Playback", color: ReplayTheme.cyan)
                    Text("TOOLS")
                        .font(.subheadline.weight(.black))
                }
                .frame(width: 108, alignment: .leading)
                .accessibilityElement(children: .combine)

                inlineChoiceDivider

                annotationEventsButton
                decisionReviewButton
                settingsToolButton
                Button {
                    toggleInlinePanel(.savedReviews)
                } label: {
                    Label("Reviews", systemImage: "bookmark")
                        .font(.subheadline.weight(.bold))
                        .lineLimit(1)
                        .frame(width: 126, height: PlaybackControlDeckPresentation.minimumSpatialHitTarget)
                }
                .buttonStyle(.bordered)
                .disabled(secondaryPlaybackControlsAreDisabled)
                .accessibilityLabel("Saved reviews")
                .accessibilityHint("Save this moment or load an earlier review")

                if store.localRole == .coach {
                    annotationEditButton(compact: false)
                }

                Spacer(minLength: 6)
            }
        }
    }

    private var settingsToolButton: some View {
        Button {
            toggleInlinePanel(.settings)
        } label: {
            Label("Settings", systemImage: "slider.horizontal.3")
                .font(.subheadline.weight(.black))
                .lineLimit(1)
                .frame(width: 126, height: PlaybackControlDeckPresentation.minimumSpatialHitTarget)
        }
        .buttonStyle(.borderedProminent)
        .tint(.white.opacity(0.10))
        .foregroundStyle(.white)
        .disabled(secondaryPlaybackControlsAreDisabled)
        .accessibilityLabel("Playback settings")
        .accessibilityValue(
            "\(rateLabel(store.playbackRate)), \(controlDeckPreset.title) controls"
        )
        .accessibilityHint("Opens playback speed and local control size")
    }

    @ViewBuilder
    private func inlinePanelShelf(_ panel: PlaybackInlinePanel) -> some View {
        switch panel {
        case .settings:
            playbackSettingsShelf
        case .savedReviews:
            inlineShelf(color: ReplayTheme.cyan) {
                ReplayReviewLibraryView {
                    inlinePanel = nil
                    showsToolsShelf = true
                }
            }
        case .annotationEdit:
            annotationEditShelf
        case .annotationDuration(let markID):
            if selectedAnnotationID == markID,
               let mark = store.marks.first(where: { $0.id == markID }) {
                annotationDurationShelf(mark)
            } else {
                unavailableInlineShelf
            }
        case .annotationGeometry(let markID):
            if selectedAnnotationID == markID,
               let mark = store.marks.first(where: { $0.id == markID }) {
                annotationGeometryShelf(mark)
            } else {
                unavailableInlineShelf
            }
        case .annotationLabel(let markID):
            if selectedAnnotationID == markID,
               let mark = store.marks.first(where: { $0.id == markID }) {
                annotationLabelShelf(mark)
            } else {
                unavailableInlineShelf
            }
        case .annotationTracking(let markID):
            if selectedAnnotationID == markID,
               let mark = store.marks.first(where: { $0.id == markID }) {
                annotationTrackingShelf(mark)
            } else {
                unavailableInlineShelf
            }
        }
    }

    private var playbackSettingsShelf: some View {
        inlineShelf(color: ReplayTheme.cyan) {
            HStack(spacing: 12) {
                inlinePanelHeader(
                    title: "Playback",
                    detail: "SETTINGS",
                    systemImage: "slider.horizontal.3",
                    color: ReplayTheme.cyan
                )

                inlineChoiceDivider

                VStack(alignment: .leading, spacing: 4) {
                    Eyebrow(text: "Speed", color: ReplayTheme.cyan)
                    HStack(spacing: 6) {
                        ForEach(directPlaybackRates, id: \.self) { rate in
                            playbackRateChoice(rate)
                        }
                    }
                }

                inlineChoiceDivider

                VStack(alignment: .leading, spacing: 4) {
                    Eyebrow(text: "Step", color: ReplayTheme.signal)
                    HStack(spacing: 6) {
                        timelineStepChoice(seconds: -1, title: "−1s")
                        timelineStepChoice(seconds: 1, title: "+1s")
                    }
                }

                inlineChoiceDivider

                VStack(alignment: .leading, spacing: 4) {
                    Eyebrow(text: "Control size", color: ReplayTheme.orange)
                    HStack(spacing: 6) {
                        ForEach(PlaybackControlDeckPreset.allCases, id: \.self) { preset in
                            controlDeckChoice(preset)
                        }
                    }
                }
            }
        }
    }

    private func timelineStepChoice(seconds: TimeInterval, title: String) -> some View {
        Button {
            nudgeTimeline(by: seconds)
        } label: {
            Text(title)
                .font(.subheadline.monospacedDigit().weight(.black))
                .frame(width: 64, height: 48)
        }
        .buttonStyle(.borderedProminent)
        .tint(.white.opacity(0.10))
        .foregroundStyle(.white)
        .buttonRepeatBehavior(.enabled)
        .disabled(timelineControlsAreDisabled)
        .accessibilityLabel(seconds < 0 ? "Back one second" : "Forward one second")
        .accessibilityHint("Pinch and hold to keep stepping")
    }

    private func playbackRateChoice(_ rate: Double) -> some View {
        let isSelected = store.playbackRate == rate
        return Button {
            store.setPlaybackRate(rate, broadcast: store.localRole == .coach)
        } label: {
            Text(rateLabel(rate))
                .font(.subheadline.monospacedDigit().weight(.black))
                .frame(width: 56, height: 48)
        }
        .buttonStyle(.borderedProminent)
        .tint(isSelected ? ReplayTheme.cyan : .white.opacity(0.10))
        .foregroundStyle(isSelected ? Color.black : Color.white)
        .disabled(rateControlsAreDisabled)
        .accessibilityLabel("Playback speed \(rateLabel(rate))")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private func controlDeckChoice(_ preset: PlaybackControlDeckPreset) -> some View {
        let isSelected = controlDeckPreset == preset
        return Button {
            controlDeckPresetRawValue = preset.rawValue
        } label: {
            VStack(spacing: 1) {
                Image(systemName: preset.systemImage)
                    .font(.headline.weight(.bold))
                Text(preset.title.uppercased())
                    .font(.caption2.monospaced().weight(.black))
                    .lineLimit(1)
            }
            .frame(width: 72, height: 48)
        }
        .buttonStyle(.borderedProminent)
        .tint(isSelected ? ReplayTheme.orange : .white.opacity(0.10))
        .foregroundStyle(isSelected ? Color.black : Color.white)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(preset.title) control size")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private var annotationEditShelf: some View {
        inlineShelf(color: ReplayTheme.orange) {
            HStack(spacing: 12) {
                inlinePanelHeader(
                    title: "Annotations",
                    detail: "EDIT",
                    systemImage: "eraser.fill",
                    color: ReplayTheme.orange
                )

                inlineChoiceDivider

                Button(action: undoLastCoachAnnotation) {
                    Label("Undo last", systemImage: "arrow.uturn.backward")
                        .font(.subheadline.weight(.black))
                        .frame(minWidth: 150, minHeight: 52)
                }
                .buttonStyle(.borderedProminent)
                .tint(ReplayTheme.orange)
                .foregroundStyle(.black)
                .disabled(!canUndoCoachAnnotation)
                .accessibilityHint("Removes the newest coach-created annotation")

                Button(action: armClearAnnotations) {
                    Label("Clear all…", systemImage: "trash.fill")
                        .font(.subheadline.weight(.black))
                        .frame(minWidth: 150, minHeight: 52)
                }
                .buttonStyle(.bordered)
                .tint(.red)
                .disabled(clearableCoachAnnotationCount == 0)
                .accessibilityHint("Opens a confirmation before clearing coach-created annotations")

                Spacer(minLength: 8)

                StatusPill(
                    text: "\(clearableCoachAnnotationCount) COACH MARKS",
                    systemImage: "pencil.and.outline",
                    color: ReplayTheme.orange
                )
            }
        }
    }

    private func annotationDurationShelf(_ mark: CoachMark) -> some View {
        inlineShelf(color: annotationColor(for: mark.kind)) {
            HStack(spacing: 12) {
                inlinePanelHeader(
                    title: "Annotation",
                    detail: "DURATION",
                    systemImage: "timer",
                    color: annotationColor(for: mark.kind)
                )

                inlineChoiceDivider

                ForEach([3.0, 5.0, 8.0, 12.0], id: \.self) { duration in
                    annotationDurationChoice(
                        mark,
                        duration: duration,
                        title: "\(Int(duration))s"
                    )
                }

                annotationDurationChoice(mark, duration: nil, title: "TO END")

                Spacer(minLength: 8)

                StatusPill(
                    text: "NOW · \(annotationDurationLabel(mark).uppercased())",
                    systemImage: "clock.fill",
                    color: annotationColor(for: mark.kind)
                )
            }
        }
    }

    private func annotationDurationChoice(
        _ mark: CoachMark,
        duration: TimeInterval?,
        title: String
    ) -> some View {
        let isSelected = isAnnotationDuration(duration, selectedFor: mark)
        return Button {
            if store.setCoachMarkDuration(id: mark.id, duration: duration) {
                annotationConfirmation = "DURATION · \(title)"
                inlinePanel = nil
            }
        } label: {
            Text(title)
                .font(.subheadline.monospacedDigit().weight(.black))
                .lineLimit(1)
                .minimumScaleFactor(0.78)
                .frame(width: duration == nil ? 104 : 66, height: 52)
        }
        .buttonStyle(.borderedProminent)
        .tint(isSelected ? annotationColor(for: mark.kind) : .white.opacity(0.10))
        .foregroundStyle(isSelected ? Color.black : Color.white)
        .disabled(isSelected)
        .accessibilityLabel(duration == nil ? "Show until replay ends" : "Show for \(title)")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private func annotationGeometryShelf(_ mark: CoachMark) -> some View {
        inlineShelf(color: annotationColor(for: mark.kind)) {
            HStack(spacing: 12) {
                inlinePanelHeader(
                    title: "Drag to steer",
                    detail: "ADJUST",
                    systemImage: "dot.scope",
                    color: annotationColor(for: mark.kind)
                )

                inlineChoiceDivider

                AnnotationAdjustmentJoystick(
                    title: "START",
                    accessibilityTarget: "start point",
                    color: annotationColor(for: mark.kind),
                    isEnabled: annotationJoystickIsEnabled(markID: mark.id, endpoint: .start),
                    onPreview: { gestureID, x, z in
                        previewAnnotation(
                            mark,
                            endpoint: .start,
                            gestureID: gestureID,
                            x: x,
                            z: z
                        )
                    },
                    onCommit: { gestureID in
                        commitAnnotationPreview(
                            mark,
                            endpoint: .start,
                            gestureID: gestureID
                        )
                    },
                    onCancel: { gestureID in
                        store.cancelCoachMarkEndpointPreview(
                            id: mark.id,
                            gestureID: gestureID
                        )
                    },
                    onAtomicNudge: { x, z in
                        nudgeAnnotation(mark, endpoint: .start, x: x, z: z)
                    }
                )

                inlineChoiceDivider

                AnnotationAdjustmentJoystick(
                    title: annotationEndPointTitle(for: mark.kind),
                    accessibilityTarget: annotationEndPointAccessibilityTarget(for: mark.kind),
                    color: annotationColor(for: mark.kind),
                    isEnabled: annotationJoystickIsEnabled(markID: mark.id, endpoint: .end),
                    onPreview: { gestureID, x, z in
                        previewAnnotation(
                            mark,
                            endpoint: .end,
                            gestureID: gestureID,
                            x: x,
                            z: z
                        )
                    },
                    onCommit: { gestureID in
                        commitAnnotationPreview(
                            mark,
                            endpoint: .end,
                            gestureID: gestureID
                        )
                    },
                    onCancel: { gestureID in
                        store.cancelCoachMarkEndpointPreview(
                            id: mark.id,
                            gestureID: gestureID
                        )
                    },
                    onAtomicNudge: { x, z in
                        nudgeAnnotation(mark, endpoint: .end, x: x, z: z)
                    }
                )

                inlineChoiceDivider

                annotationElevationControls(mark)
            }
        }
    }

    @ViewBuilder
    private func annotationElevationControls(_ mark: CoachMark) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 7) {
                Image(systemName: "cube.transparent")
                    .foregroundStyle(annotationColor(for: mark.kind))
                VStack(alignment: .leading, spacing: 1) {
                    Eyebrow(text: "3D height", color: annotationColor(for: mark.kind))
                    Text("0–4 M ABOVE PITCH")
                        .font(.caption2.monospaced().weight(.black))
                        .foregroundStyle(.white.opacity(0.54))
                }
            }

            HStack(spacing: 8) {
                if mark.kind != .space {
                    annotationElevationStepper(
                        mark,
                        target: .start,
                        title: "START",
                        elevation: mark.resolvedStartElevation
                    )
                    annotationElevationStepper(
                        mark,
                        target: .end,
                        title: annotationEndPointTitle(for: mark.kind),
                        elevation: mark.resolvedEndElevation
                    )
                }
                annotationElevationStepper(
                    mark,
                    target: .both,
                    title: mark.kind == .space ? "ZONE" : "WHOLE",
                    elevation: (mark.resolvedStartElevation + mark.resolvedEndElevation) / 2
                )
            }
        }
        .accessibilityElement(children: .contain)
    }

    private func annotationElevationStepper(
        _ mark: CoachMark,
        target: CoachMarkElevationTarget,
        title: String,
        elevation: Float
    ) -> some View {
        VStack(spacing: 4) {
            HStack(spacing: 4) {
                Text(title)
                    .lineLimit(1)
                    .minimumScaleFactor(0.68)
                Text(annotationElevationLabel(elevation))
                    .foregroundStyle(annotationColor(for: mark.kind))
            }
            .font(.caption2.monospacedDigit().weight(.black))

            HStack(spacing: 4) {
                annotationElevationButton(
                    mark,
                    target: target,
                    delta: -CoachMarkGeometryPolicy.elevationStep,
                    systemImage: "chevron.down"
                )
                annotationElevationButton(
                    mark,
                    target: target,
                    delta: CoachMarkGeometryPolicy.elevationStep,
                    systemImage: "chevron.up"
                )
            }
        }
    }

    private func annotationElevationButton(
        _ mark: CoachMark,
        target: CoachMarkElevationTarget,
        delta: Float,
        systemImage: String
    ) -> some View {
        Button {
            nudgeAnnotationElevation(mark, target: target, delta: delta)
        } label: {
            Image(systemName: systemImage)
                .font(.headline.weight(.black))
                .frame(
                    width: PlaybackControlDeckPresentation.minimumSpatialHitTarget,
                    height: PlaybackControlDeckPresentation.minimumSpatialHitTarget
                )
        }
        .buttonStyle(.borderedProminent)
        .tint(.white.opacity(0.10))
        .foregroundStyle(.white)
        .buttonRepeatBehavior(.enabled)
        .disabled(!canNudgeAnnotationElevation(mark, target: target, delta: delta))
        .accessibilityLabel(
            "\(delta > 0 ? "Raise" : "Lower") \(annotationElevationTargetName(target, kind: mark.kind))"
        )
        .accessibilityValue(annotationElevationAccessibilityValue(mark, target: target))
        .accessibilityHint("Moves vertically by 0.25 metres")
    }

    private func canNudgeAnnotationElevation(
        _ mark: CoachMark,
        target: CoachMarkElevationTarget,
        delta: Float
    ) -> Bool {
        let elevations: [Float] = switch target {
        case .start: [mark.resolvedStartElevation]
        case .end: [mark.resolvedEndElevation]
        case .both: [mark.resolvedStartElevation, mark.resolvedEndElevation]
        }
        if delta > 0 {
            return elevations.contains { $0 < CoachMarkGeometryPolicy.maximumElevation }
        }
        return elevations.contains { $0 > 0 }
    }

    private func annotationElevationTargetName(
        _ target: CoachMarkElevationTarget,
        kind: CoachMarkKind
    ) -> String {
        switch target {
        case .start: "annotation start"
        case .end: kind == .space ? "opposite corner" : "arrow point"
        case .both: kind == .space ? "zone" : "whole annotation"
        }
    }

    private func annotationElevationAccessibilityValue(
        _ mark: CoachMark,
        target: CoachMarkElevationTarget
    ) -> String {
        switch target {
        case .start:
            return annotationElevationLabel(mark.resolvedStartElevation)
        case .end:
            return annotationElevationLabel(mark.resolvedEndElevation)
        case .both:
            return "Start \(annotationElevationLabel(mark.resolvedStartElevation)), end \(annotationElevationLabel(mark.resolvedEndElevation))"
        }
    }

    private func annotationElevationLabel(_ elevation: Float) -> String {
        elevation.formatted(.number.precision(.fractionLength(2))) + " M"
    }

    private func annotationEndPointTitle(for kind: CoachMarkKind) -> String {
        switch kind {
        case .space: "CORNER"
        case .run, .pass, .danger: "ARROW TIP"
        case .playerLabel: "PLAYER"
        }
    }

    private func annotationJoystickIsEnabled(
        markID: UUID,
        endpoint: CoachMarkEndpoint
    ) -> Bool {
        guard !store.hasActiveTimelineScrub else { return false }
        guard let owner = store.activeCoachMarkEndpointPreviewOwner else { return true }
        return owner == CoachMarkEndpointPreviewOwner(markID: markID, endpoint: endpoint)
    }

    private func annotationEndPointAccessibilityTarget(for kind: CoachMarkKind) -> String {
        kind == .space ? "opposite corner" : "arrow point"
    }

    /// A selected coach mark can follow any shirt in either XI without opening
    /// a platform popover. The store samples both endpoint offsets at the
    /// current replay instant, so choosing a player never makes the mark jump.
    private func annotationTrackingShelf(_ mark: CoachMark) -> some View {
        let color = annotationColor(for: mark.kind)
        let isFixedToPitch = !mark.followsPlayerTracks

        return inlineShelf(color: color) {
            VStack(spacing: 8) {
                HStack(spacing: 12) {
                    inlinePanelHeader(
                        title: "Follow player",
                        detail: "START + END",
                        systemImage: "link",
                        color: color
                    )

                    inlineChoiceDivider

                    Text("Keeps both points at their current offset from the chosen player.")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.white.opacity(0.68))
                        .lineLimit(2)
                        .minimumScaleFactor(0.78)

                    Spacer(minLength: 8)

                    StatusPill(
                        text: annotationTrackingSummary(mark),
                        systemImage: isFixedToPitch ? "mappin" : "link",
                        color: color
                    )

                    Button {
                        setAnnotationTracking(mark, playerID: nil)
                    } label: {
                        Label("Pitch", systemImage: "mappin")
                            .font(.subheadline.weight(.black))
                            .lineLimit(1)
                            .frame(
                                minWidth: 108,
                                minHeight: PlaybackControlDeckPresentation.minimumSpatialHitTarget
                            )
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(isFixedToPitch ? color : .white.opacity(0.10))
                    .foregroundStyle(isFixedToPitch ? Color.black : Color.white)
                    .disabled(isFixedToPitch)
                    .accessibilityLabel("Fix annotation to pitch")
                    .accessibilityHint("Stops both annotation points following a player")
                    .accessibilityAddTraits(isFixedToPitch ? .isSelected : [])
                }

                annotationTrackingTeamRow(
                    team: .home,
                    players: store.selectedScenario.homePlayers,
                    mark: mark
                )
                annotationTrackingTeamRow(
                    team: .away,
                    players: store.selectedScenario.awayPlayers,
                    mark: mark
                )
            }
        }
    }

    private func annotationTrackingTeamRow(
        team: FootballTeam,
        players: [PlayerTrack],
        mark: CoachMark
    ) -> some View {
        HStack(spacing: 6) {
            Text(team == .home ? "HOME" : "OPPOSITION")
                .font(.caption2.monospaced().weight(.black))
                .foregroundStyle(teamAccent(team))
                .frame(width: 92, alignment: .leading)
                .accessibilityLabel(team.shortTitle)

            ForEach(players.prefix(11)) { player in
                annotationTrackingPlayerButton(player, mark: mark)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func annotationTrackingPlayerButton(
        _ player: PlayerTrack,
        mark: CoachMark
    ) -> some View {
        let isSelected = annotationTrackingPlayerID(mark) == player.id
        let accent = teamAccent(player.team)

        return Button {
            setAnnotationTracking(mark, playerID: player.id)
        } label: {
            VStack(spacing: 0) {
                Text("#\(player.shirtNumber)")
                    .font(.subheadline.monospacedDigit().weight(.black))
                Text(player.positionCode)
                    .font(.caption2.monospaced().weight(.black))
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
            }
            .foregroundStyle(isSelected ? Color.black : Color.white)
            .frame(
                maxWidth: .infinity,
                minHeight: PlaybackControlDeckPresentation.minimumSpatialHitTarget
            )
            .contentShape(RoundedRectangle(cornerRadius: 13))
            .background(
                isSelected ? accent : accent.opacity(0.14),
                in: RoundedRectangle(cornerRadius: 13)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 13)
                    .stroke(
                        isSelected ? accent : accent.opacity(0.42),
                        lineWidth: isSelected ? 2 : 1
                    )
            }
        }
        .buttonStyle(.plain)
        .hoverEffect(.highlight)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            "Follow \(player.team.shortTitle) number \(player.shirtNumber), \(player.role)"
        )
        .accessibilityHint("Keeps both annotation points at their current offsets from this player")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private func annotationTrackingPlayerID(_ mark: CoachMark) -> String? {
        guard let startID = mark.startTrackAnchor?.playerID,
              let endID = mark.endTrackAnchor?.playerID,
              startID == endID else { return nil }
        return startID
    }

    private func annotationTrackingSummary(_ mark: CoachMark) -> String {
        guard mark.followsPlayerTracks else { return "PITCH FIXED" }
        if let playerID = annotationTrackingPlayerID(mark),
           let player = store.selectedScenario.player(id: playerID) {
            return "FOLLOWS #\(player.shirtNumber)"
        }
        return mark.anchoredPlayerIDs.count > 1 ? "MIXED TRACKS" : "PARTIAL TRACK"
    }

    private func setAnnotationTracking(_ mark: CoachMark, playerID: String?) {
        guard store.setCoachMarkTracking(id: mark.id, playerID: playerID) else { return }
        if let playerID,
           let player = store.selectedScenario.player(id: playerID) {
            annotationConfirmation = "FOLLOWS #\(player.shirtNumber) · \(formatTime(store.playhead))"
        } else {
            annotationConfirmation = "FIXED TO PITCH · \(formatTime(store.playhead))"
        }
        inlinePanel = nil
    }

    private func annotationLabelShelf(_ mark: CoachMark) -> some View {
        inlineShelf(color: annotationColor(for: mark.kind)) {
            HStack(spacing: 10) {
                inlinePanelHeader(
                    title: mark.kind.title,
                    detail: "LABEL",
                    systemImage: "tag.fill",
                    color: annotationColor(for: mark.kind)
                )

                inlineChoiceDivider

                LazyVGrid(
                    columns: [
                        GridItem(
                            .adaptive(minimum: 118, maximum: 156),
                            spacing: 8,
                            alignment: .leading
                        ),
                    ],
                    alignment: .leading,
                    spacing: 8
                ) {
                    ForEach(mark.kind.suggestedLabels, id: \.self) { label in
                        let isSelected = label == mark.label
                        Button {
                            if store.updateCoachMarkLabel(id: mark.id, label: label) {
                                annotationConfirmation = "LABEL · \(label.uppercased())"
                                inlinePanel = nil
                            }
                        } label: {
                            Text(label.uppercased())
                                .font(.caption.monospaced().weight(.black))
                                .lineLimit(1)
                                .minimumScaleFactor(0.62)
                                .frame(maxWidth: .infinity, minHeight: 50)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(isSelected ? annotationColor(for: mark.kind) : .white.opacity(0.10))
                        .foregroundStyle(isSelected ? Color.black : Color.white)
                        .disabled(isSelected)
                        .accessibilityLabel(label)
                        .accessibilityAddTraits(isSelected ? .isSelected : [])
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .layoutPriority(1)
            }
        }
    }

    private var unavailableInlineShelf: some View {
        inlineShelf(color: .secondary) {
            HStack(spacing: 12) {
                inlinePanelHeader(
                    title: "Selection changed",
                    detail: "CONTROLS CLOSED",
                    systemImage: "exclamationmark.arrow.triangle.2.circlepath",
                    color: .secondary
                )
                Text("Choose an annotation again to edit it.")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()
            }
        }
    }

    private func inlinePanelHeader(
        title: String,
        detail: String,
        systemImage: String,
        color: Color
    ) -> some View {
        HStack(spacing: 10) {
            Button {
                inlinePanel = nil
            } label: {
                Image(systemName: "xmark")
                    .frame(width: 30, height: 48)
            }
            .buttonStyle(.bordered)
            .accessibilityLabel("Close \(detail.lowercased()) controls")

            Image(systemName: systemImage)
                .font(.headline.weight(.black))
                .foregroundStyle(color)
                .frame(width: 28, height: 48)

            VStack(alignment: .leading, spacing: 1) {
                Eyebrow(text: detail, color: color)
                Text(title)
                    .font(.subheadline.weight(.black))
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
            }
        }
        .frame(minWidth: 176, alignment: .leading)
    }

    private var inlineChoiceDivider: some View {
        Rectangle()
            .fill(.white.opacity(0.13))
            .frame(width: 1, height: 48)
            .accessibilityHidden(true)
    }

    private func togglePlaybackToolsShelf() {
        guard !secondaryPlaybackControlsAreDisabled else { return }
        let opensTools = !showsToolsShelf
        showsToolsShelf = false
        guard opensTools else { return }

        inlinePanel = nil
        selectedAnnotationID = nil
        showsPlayerGrid = false
        showsDecisionStrip = false
        showsEventStrip = false
        showsAnnotationTools = false
        isClearAnnotationsPending = false
        showsToolsShelf = true
    }

    private func inlineShelf<Content: View>(
        color: Color,
        @ViewBuilder content: () -> Content
    ) -> some View {
        content()
            .padding(10)
            .frame(maxWidth: .infinity, minHeight: 72)
            .background(color.opacity(0.07), in: RoundedRectangle(cornerRadius: 17))
            .overlay {
                RoundedRectangle(cornerRadius: 17)
                    .stroke(color.opacity(0.28), lineWidth: 1)
            }
    }

    private func toggleInlinePanel(_ candidate: PlaybackInlinePanel) {
        let nextPanel = PlaybackInlinePanel.toggled(
            current: inlinePanel,
            candidate: candidate
        )
        inlinePanel = nextPanel
        guard nextPanel != nil else { return }
        showsToolsShelf = false
        showsAnnotationTools = false
        showsPlayerGrid = false
        showsDecisionStrip = false
        showsEventStrip = false
        isClearAnnotationsPending = false
    }

    private func isAnnotationDuration(
        _ duration: TimeInterval?,
        selectedFor mark: CoachMark
    ) -> Bool {
        guard let duration else { return mark.hideTime == nil }
        guard let hideTime = mark.hideTime else { return false }
        return abs((hideTime - mark.revealTime) - duration) < 0.05
    }

    private var clearAnnotationsConfirmationStrip: some View {
        HStack(spacing: 12) {
            Image(systemName: "exclamationmark.eraser.fill")
                .font(.title3.weight(.black))
                .foregroundStyle(.red)
                .frame(width: 48, height: 48)

            VStack(alignment: .leading, spacing: 2) {
                Eyebrow(text: "Clear \(clearableCoachAnnotationCount) coach marks?", color: .red)
                Text("Match overlays stay.")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 8)

            Button("Cancel") {
                isClearAnnotationsPending = false
            }
            .buttonStyle(.bordered)
            .frame(minWidth: 96, minHeight: 52)

            Button(role: .destructive) {
                store.clearMarks()
                selectedAnnotationID = nil
                showsDecisionStrip = false
                showsEventStrip = false
                isClearAnnotationsPending = false
                annotationConfirmation = "MARKS CLEARED"
            } label: {
                Label("Clear", systemImage: "trash.fill")
                    .font(.subheadline.weight(.black))
                    .lineLimit(1)
                    .frame(minWidth: 104, minHeight: 52)
            }
            .buttonStyle(.borderedProminent)
            .tint(.red)
            .disabled(clearableCoachAnnotationCount == 0)
            .accessibilityHint("Removes coach-created marks but keeps match overlays")
        }
        .padding(12)
        .background(.red.opacity(0.08), in: RoundedRectangle(cornerRadius: 17))
        .overlay {
            RoundedRectangle(cornerRadius: 17)
                .stroke(.red.opacity(0.30), lineWidth: 1)
        }
    }

    private func undoLastCoachAnnotation() {
        let previousCount = clearableCoachAnnotationCount
        store.undoMark()
        if clearableCoachAnnotationCount < previousCount {
            if let selectedAnnotationID,
               !store.marks.contains(where: { $0.id == selectedAnnotationID }) {
                self.selectedAnnotationID = nil
            }
            annotationConfirmation = "LAST MARK UNDONE"
            if clearableCoachAnnotationCount == 0 {
                inlinePanel = nil
            }
        }
    }

    private func armClearAnnotations() {
        guard store.localRole == .coach, clearableCoachAnnotationCount > 0 else { return }
        if store.isDrawing {
            store.cancelDrawing()
        }
        inlinePanel = nil
        showsDecisionStrip = false
        showsEventStrip = false
        showsPlayerGrid = false
        showsAnnotationTools = false
        isClearAnnotationsPending = true
    }

    private var clearableCoachAnnotationCount: Int {
        store.marks.lazy.filter(isCoachCreated).count
    }

    /// A deliberately temporary roster replaces the platform menu's long,
    /// serial list. Both complete XIs stay visible at once, every shirt is a
    /// single direct pinch target, and choosing one immediately returns to the
    /// compact transport. Tapping a player on the pitch remains an equivalent
    /// direct shortcut.
    private var playerPOVGrid: some View {
        VStack(spacing: 8) {
            HStack(spacing: 11) {
                Button {
                    showsPlayerGrid = false
                } label: {
                    Image(systemName: "xmark")
                        .frame(width: 28, height: 48)
                }
                .buttonStyle(.bordered)
                .accessibilityLabel("Close player roster")

                Image(systemName: "person.crop.rectangle.stack.fill")
                    .font(.headline.weight(.black))
                    .foregroundStyle(ReplayTheme.signal)
                    .frame(width: 38, height: 48)

                VStack(alignment: .leading, spacing: 1) {
                    Eyebrow(text: playerGridTitle, color: ReplayTheme.signal)
                    Text(playerGridInstruction)
                        .font(.caption2.monospaced().weight(.black))
                        .foregroundStyle(.white.opacity(0.68))
                        .lineLimit(1)
                        .minimumScaleFactor(0.72)
                }

                Spacer(minLength: 8)

                if let player = store.activePerspective {
                    StatusPill(
                        text: "#\(player.shirtNumber) · \(player.positionCode)",
                        systemImage: "viewfinder",
                        color: ReplayTheme.signal
                    )
                }
            }

            perspectiveTeamRow(
                team: .home,
                players: store.selectedScenario.homePlayers
            )
            perspectiveTeamRow(
                team: .away,
                players: store.selectedScenario.awayPlayers
            )

            if store.viewMode == .firstPerson {
                povStatusChip
            }
        }
        .padding(10)
        .background(ReplayTheme.signal.opacity(0.055), in: RoundedRectangle(cornerRadius: 17))
        .overlay {
            RoundedRectangle(cornerRadius: 17)
                .stroke(ReplayTheme.signal.opacity(0.22), lineWidth: 1)
        }
    }

    private func perspectiveTeamRow(
        team: FootballTeam,
        players: [PlayerTrack]
    ) -> some View {
        HStack(spacing: 6) {
            VStack(alignment: .leading, spacing: 1) {
                Text(team == .home ? "HOME" : "AWAY")
                    .font(.caption2.monospaced().weight(.black))
                    .foregroundStyle(teamAccent(team))
                Text("XI")
                    .font(.title3.monospacedDigit().weight(.black))
                    .foregroundStyle(.white)
            }
            .frame(width: 72, alignment: .leading)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(team.shortTitle)

            ForEach(players.prefix(11)) { player in
                perspectivePlayerButton(player)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func perspectivePlayerButton(_ player: PlayerTrack) -> some View {
        let isSelected = player.id == store.activePerspectiveID
        let accent = teamAccent(player.team)
        return Button {
            openPlayerPOV(player.id)
        } label: {
            VStack(spacing: 0) {
                Text("#\(player.shirtNumber)")
                    .font(.subheadline.monospacedDigit().weight(.black))
                Text(player.positionCode)
                    .font(.caption2.monospaced().weight(.black))
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
            }
            .foregroundStyle(isSelected ? Color.black : Color.white)
            .frame(
                width: 72,
                height: PlaybackControlDeckPresentation.minimumSpatialHitTarget
            )
            .contentShape(RoundedRectangle(cornerRadius: 13))
            .background(
                isSelected ? ReplayTheme.signal : accent.opacity(0.14),
                in: RoundedRectangle(cornerRadius: 13)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 13)
                    .stroke(
                        isSelected ? ReplayTheme.signal : accent.opacity(0.42),
                        lineWidth: isSelected ? 2 : 1
                    )
            }
        }
        .buttonStyle(.plain)
        .hoverEffect(.highlight)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            "\(player.team.shortTitle), number \(player.shirtNumber), \(player.role)"
        )
        .accessibilityHint(playerPOVAccessibilityHint)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private var playerGridInstruction: String { "PINCH A SHIRT" }

    private var playerGridTitle: String {
        "22 PLAYER POV"
    }

    private var playerPOVAccessibilityHint: String { "Opens this player's free-look point of view" }

    private func teamAccent(_ team: FootballTeam) -> Color {
        team == .home ? ReplayTheme.cyan : ReplayTheme.orange
    }

    /// Once a tool is active, transport and view controls only compete with
    /// the instruction the coach is placing. A single-row shelf keeps the
    /// pitch unobstructed for either one pinch-drag or the two-tap fallback.
    private var annotationDrawingShelf: some View {
        HStack(spacing: 10) {
            Button {
                store.cancelDrawing()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .frame(width: 28, height: 48)
            }
            .buttonStyle(.bordered)
            .tint(ReplayTheme.orange)
            .accessibilityLabel("Cancel annotation")

            Label(annotationInstruction, systemImage: annotationInstructionSystemImage)
                .font(.subheadline.monospaced().weight(.black))
                .lineLimit(1)
                .minimumScaleFactor(0.72)
                .foregroundStyle(ReplayTheme.orange)
                .frame(width: 190, alignment: .leading)

            annotationToolButton(.run, label: "Run")
            annotationToolButton(.pass, label: "Pass")
            annotationToolButton(.danger, label: "Press")
            annotationToolButton(.space, label: "Zone")
            annotationToolButton(.playerLabel, label: "Label")

            Spacer(minLength: 6)

            Text(formatTime(store.playhead))
                .font(.subheadline.monospacedDigit().weight(.black))
                .foregroundStyle(.secondary)

            annotationEditButton(compact: true)
        }
        .padding(16)
        .frame(width: deckWidth)
        .controlSize(.extraLarge)
        .background(ReplayTheme.orange.opacity(0.10), in: RoundedRectangle(cornerRadius: 24))
        .overlay {
            RoundedRectangle(cornerRadius: 24)
                .stroke(ReplayTheme.orange.opacity(0.34), lineWidth: 1.5)
        }
        .glassBackgroundEffect(in: .rect(cornerRadius: 24))
    }

    private var coachAnnotationStrip: some View {
        HStack(spacing: 9) {
            Label(annotationInstruction, systemImage: annotationInstructionSystemImage)
                .font(.caption.monospaced().weight(.black))
                .lineLimit(1)
                .minimumScaleFactor(0.72)
                .foregroundStyle(annotationInstructionColor)
                .frame(width: 180, alignment: .leading)
                .accessibilityLabel(annotationInstruction)

            annotationToolButton(.run, label: "Run")
            annotationToolButton(.pass, label: "Pass")
            annotationToolButton(.danger, label: "Press")
            annotationToolButton(.space, label: "Zone")
            annotationToolButton(.playerLabel, label: "Label")

            Spacer(minLength: 6)

            // Timeline remains available from the retractable Tools shelf.
            // Keep this strip focused on choosing or editing a spatial mark.
            annotationEditButton(compact: true)
        }
        .padding(12)
        .background(ReplayTheme.orange.opacity(store.isDrawing ? 0.13 : 0.06), in: RoundedRectangle(cornerRadius: 17))
        .overlay {
            RoundedRectangle(cornerRadius: 17)
                .stroke(ReplayTheme.orange.opacity(store.isDrawing ? 0.38 : 0.16), lineWidth: 1)
        }
    }

    private var povStatusChip: some View {
        HStack(spacing: 7) {
            Image(systemName: "viewfinder")
            Text("FREE LOOK")
            Circle()
                .fill(ReplayTheme.signal)
                .frame(width: 7, height: 7)
            Text("FACING")
        }
        .font(.caption2.monospaced().weight(.black))
        .foregroundStyle(.white.opacity(0.74))
        .padding(.horizontal, 12)
        .frame(minHeight: 48)
        .background(.white.opacity(0.08), in: Capsule())
        .overlay(Capsule().stroke(ReplayTheme.signal.opacity(0.24), lineWidth: 1))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Free-look player point of view")
        .accessibilityHint(
            "Your position follows the player. Your headset controls where you look. Green brackets show the player's recorded facing direction."
        )
    }

    private func annotationToolButton(_ kind: CoachMarkKind, label: String) -> some View {
        let isSelected = store.isDrawing && store.selectedTool == kind
        return Button {
            annotationConfirmation = nil
            inlinePanel = nil
            selectedAnnotationID = nil
            showsPlayerGrid = false
            showsDecisionStrip = false
            showsEventStrip = false
            showsToolsShelf = false
            showsPlaybackAnnotations = true
            store.beginDrawing(kind)
        } label: {
            VStack(spacing: 1) {
                Image(systemName: kind.systemImage)
                    .font(.headline.weight(.bold))
                Text(label.uppercased())
                    .font(.caption2.monospaced().weight(.black))
                    .lineLimit(1)
            }
            .frame(width: 70, height: 48)
        }
        .buttonStyle(.borderedProminent)
        .tint(isSelected ? ReplayTheme.orange : .white.opacity(0.10))
        .foregroundStyle(isSelected ? Color.black : Color.white)
        .accessibilityLabel("\(label) annotation")
        .accessibilityHint(
            kind == .playerLabel
                ? "Select, then pinch a player"
                : "Select, then pinch and drag on the pitch; two taps also work"
        )
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private var orderedMarks: [CoachMark] { orderedReviewMarks }

    private var reviewEvents: [PlaybackReviewEvent] { indexedReviewEvents }

    private func rebuildReviewIndex() {
        let marks = store.marks.sorted {
            $0.revealTime == $1.revealTime
                ? $0.id.uuidString < $1.id.uuidString
                : $0.revealTime < $1.revealTime
        }
        let cueEvents = store.selectedScenario.moments.map(PlaybackReviewEvent.cue)
        let markEvents = marks.map(PlaybackReviewEvent.mark)
        var events = cueEvents
        events.append(contentsOf: markEvents)
        events.sort {
            $0.time == $1.time ? $0.id < $1.id : $0.time < $1.time
        }
        orderedReviewMarks = marks
        indexedReviewEvents = events
        // Deleting the only event on the last page must not leave an empty
        // shelf. Paging remains local presentation state, never squad state.
        eventPage = PlaybackEventRailLayout.clampedPage(
            eventPage,
            eventCount: events.count
        )
        rebuildTimelineTickClusters(events: events)
    }

    private func rebuildTimelineTickClusters(
        events: [PlaybackReviewEvent]? = nil,
        selectionID: UUID? = nil
    ) {
        let events = events ?? indexedReviewEvents
        let selectedID = selectionID ?? selectedAnnotationID
        PlaybackEventRailLayout.clusterTimelineTicks(
            events,
            duration: store.selectedScenario.duration,
            railWidth: timelineTrackWidth,
            leadingInset: 9,
            into: &timelineTickClusters,
            time: { $0.time },
            kind: { event in
                if case .cue = event { return .cue }
                return .annotation
            },
            isSelected: { event in
                guard case .mark(let mark) = event else { return false }
                return mark.id == selectedID
            }
        )
    }

    private func updateTimelineTrackWidth(_ width: CGFloat) {
        guard width.isFinite, width > 0,
              abs(width - timelineTrackWidth) >= 0.5 else { return }
        timelineTrackWidth = width
        rebuildTimelineTickClusters()
    }

    private var eventPageCount: Int {
        PlaybackEventRailLayout.pageCount(eventCount: reviewEvents.count)
    }

    private var clampedEventPage: Int {
        PlaybackEventRailLayout.clampedPage(eventPage, eventCount: reviewEvents.count)
    }

    private var visibleReviewEvents: [PlaybackReviewEvent] {
        let range = PlaybackEventRailLayout.visibleRange(
            eventCount: reviewEvents.count,
            page: eventPage
        )
        return Array(reviewEvents[range])
    }

    private var visibleEventRangeLabel: String {
        PlaybackEventRailLayout.rangeLabel(eventCount: reviewEvents.count, page: eventPage)
    }

    private var selectedAnnotation: CoachMark? {
        guard let selectedAnnotationID else { return nil }
        return store.marks.first { $0.id == selectedAnnotationID }
    }

    private var timelineScrubber: some View {
        GeometryReader { proxy in
            let duration = max(store.selectedScenario.duration, 0.1)
            let trackInset: CGFloat = 9
            let trackWidth = max(proxy.size.width - trackInset * 2, 1)
            let progress = CGFloat(min(max(store.playhead / duration, 0), 1))
            let playheadX = trackInset + trackWidth * progress

            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: 13)
                    .fill(.white.opacity(timelineScrubState == nil ? 0.035 : 0.085))

                ForEach(orderedMarks) { mark in
                    let startProgress = CGFloat(min(max(mark.revealTime / duration, 0), 1))
                    let resolvedEnd = mark.hideTime ?? store.selectedScenario.duration
                    let endProgress = CGFloat(min(max(resolvedEnd / duration, 0), 1))
                    let startX = trackInset + trackWidth * startProgress
                    let endX = trackInset + trackWidth * max(endProgress, startProgress)
                    let isSelected = mark.id == selectedAnnotationID
                    Capsule()
                        .fill(annotationColor(for: mark.kind).opacity(isSelected ? 0.78 : 0.38))
                        .frame(width: max(endX - startX, isSelected ? 8 : 4), height: isSelected ? 4 : 3)
                        .position(x: (startX + endX) / 2, y: 8)
                }

                Capsule()
                    .fill(.white.opacity(0.13))
                    .frame(width: trackWidth, height: 7)
                    .position(x: proxy.size.width / 2, y: 22)

                Capsule()
                    .fill(ReplayTheme.signal.opacity(0.86))
                    .frame(width: max(playheadX - trackInset, 1), height: 7)
                    .position(x: trackInset + max(playheadX - trackInset, 1) / 2, y: 22)

                ForEach(timelineTickClusters, id: \.binIndex) { cluster in
                    let isAtPlayhead = store.playhead >= cluster.earliestTime - 0.16
                        && store.playhead <= cluster.latestTime + 0.16
                    let isSelected = cluster.containsSelection
                    let isAnnotation = cluster.dominantKind == .annotation
                    Capsule()
                        .fill(
                            isSelected
                                ? ReplayTheme.signal
                                : (isAnnotation ? ReplayTheme.orange : .white.opacity(0.56))
                        )
                        .frame(
                            width: isSelected
                                ? 8
                                : (isAtPlayhead ? 7 : (cluster.eventCount > 1 ? 5 : 3)),
                            height: isSelected ? 22 : (isAtPlayhead ? 19 : 14)
                        )
                        .position(x: cluster.x, y: 22)
                        .accessibilityHidden(true)
                }

                Circle()
                    .fill(ReplayTheme.signal)
                    .frame(width: 19, height: 19)
                    .overlay(Circle().stroke(.black.opacity(0.28), lineWidth: 2))
                    .shadow(color: ReplayTheme.signal.opacity(0.34), radius: 6)
                    .position(x: playheadX, y: 22)

                HStack(spacing: 6) {
                    Text(formatTime(store.playhead))
                        .foregroundStyle(ReplayTheme.signal)
                    if let timelineScrubState {
                        Text(timelineScrubState.precision.rawValue)
                            .foregroundStyle(.white.opacity(0.72))
                    }
                    Spacer(minLength: 4)
                    Text(formatTime(store.selectedScenario.duration))
                }
                .font(.caption2.monospacedDigit().weight(.black))
                .lineLimit(1)
                .minimumScaleFactor(0.78)
                .padding(.horizontal, trackInset)
                .offset(y: 36)
            }
            .contentShape(RoundedRectangle(cornerRadius: 13))
            .gesture(
                DragGesture(minimumDistance: 0)
                    .updating($timelineScrubIsActive) { _, isActive, _ in
                        isActive = true
                    }
                    .onChanged { value in
                        updateTimelineScrub(
                            value,
                            railWidth: trackWidth,
                            railLeadingInset: trackInset
                        )
                    }
                    .onEnded { value in
                        finishTimelineScrub(
                            value,
                            railWidth: trackWidth,
                            railLeadingInset: trackInset
                        )
                    }
            )
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Match timeline")
            .accessibilityValue(
                "\(formatTime(store.playhead)) of \(formatTime(store.selectedScenario.duration))"
            )
            .accessibilityHint("Pinch anywhere to jump, drag sideways, and lift for frame control.")
            .accessibilityAdjustableAction { direction in
                switch direction {
                case .increment:
                    adjustTimelineForAccessibility(direction: 1)
                case .decrement:
                    adjustTimelineForAccessibility(direction: -1)
                @unknown default:
                    break
                }
            }
            .onAppear {
                updateTimelineTrackWidth(trackWidth)
            }
            .onChange(of: trackWidth) { _, width in
                updateTimelineTrackWidth(width)
            }
        }
        .frame(
            minWidth: 230,
            maxWidth: .infinity,
            minHeight: PlaybackControlDeckPresentation.minimumSpatialHitTarget,
            maxHeight: PlaybackControlDeckPresentation.minimumSpatialHitTarget
        )
        .disabled(timelineControlsAreDisabled)
    }

    private var annotationEventsButton: some View {
        Button {
            inlinePanel = nil
            selectedAnnotationID = nil
            showsPlayerGrid = false
            showsDecisionStrip = false
            showsAnnotationTools = false
            showsToolsShelf = false
            showsEventStrip = true
            eventPage = PlaybackEventRailLayout.page(
                nearestTo: store.playhead,
                events: reviewEvents,
                time: { $0.time }
            )
        } label: {
            Label("Timeline", systemImage: "list.bullet.rectangle.fill")
                .font(.subheadline.weight(.black))
                .lineLimit(1)
                .frame(width: 126, height: PlaybackControlDeckPresentation.minimumSpatialHitTarget)
        }
        .buttonStyle(.borderedProminent)
        .tint(.white.opacity(0.10))
        .foregroundStyle(.white)
        .disabled(secondaryPlaybackControlsAreDisabled || reviewEvents.isEmpty)
        .accessibilityLabel("Match timeline")
        .accessibilityValue("\(reviewEvents.count) events")
        .accessibilityHint("Shows timestamped cues and annotations")
    }

    private var decisionReviewButton: some View {
        Button {
            inlinePanel = nil
            selectedAnnotationID = nil
            showsPlayerGrid = false
            showsEventStrip = false
            showsAnnotationTools = false
            showsToolsShelf = false
            showsDecisionStrip = true
            store.setPlaying(false, broadcast: false)
        } label: {
            Label("Decisions", systemImage: "eye.fill")
                .font(.subheadline.weight(.black))
                .lineLimit(1)
                .frame(width: 132, height: PlaybackControlDeckPresentation.minimumSpatialHitTarget)
        }
        .buttonStyle(.borderedProminent)
        .tint(.white.opacity(0.10))
        .foregroundStyle(.white)
        .disabled(secondaryPlaybackControlsAreDisabled || decisionSnapshot == nil)
        .accessibilityLabel("Decision options")
        .accessibilityHint("Pauses and shows the selected player's descriptive passing lanes")
    }

    private var annotationEventStrip: some View {
        HStack(spacing: PlaybackEventRailLayout.horizontalSpacing) {
            Button {
                showsEventStrip = false
            } label: {
                Image(systemName: "xmark")
                    .frame(
                        minWidth: PlaybackControlDeckPresentation.minimumSpatialHitTarget,
                        minHeight: PlaybackControlDeckPresentation.minimumSpatialHitTarget
                    )
            }
            .buttonStyle(.bordered)
            .fixedSize()
            .accessibilityLabel("Close timeline")

            VStack(alignment: .leading, spacing: 2) {
                Eyebrow(text: "Timeline", color: ReplayTheme.cyan)
                Text(visibleEventRangeLabel)
                    .font(.caption2.monospacedDigit().weight(.black))
                    .foregroundStyle(.white.opacity(0.58))
            }
            .frame(width: PlaybackEventRailLayout.headingWidth, alignment: .leading)
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Timeline, \(visibleEventRangeLabel)")

            eventPageButton(direction: -1)

            HStack(spacing: PlaybackEventRailLayout.chipSpacing) {
                ForEach(visibleReviewEvents) { event in
                    reviewEventButton(event)
                }
            }
            .frame(maxWidth: .infinity, minHeight: 56, alignment: .leading)
            .layoutPriority(1)

            eventPageButton(direction: 1)

            if store.localRole == .coach {
                Button {
                    showsEventStrip = false
                    showsAnnotationTools = true
                    showsToolsShelf = false
                    showsPlaybackAnnotations = true
                } label: {
                    Label("DRAW", systemImage: "pencil.and.outline")
                        .font(.subheadline.weight(.black))
                        .lineLimit(1)
                        .frame(
                            width: 100,
                            height: PlaybackControlDeckPresentation.minimumSpatialHitTarget
                        )
                }
                .buttonStyle(.borderedProminent)
                .tint(ReplayTheme.orange)
                .foregroundStyle(.black)
                .frame(
                    minWidth: PlaybackEventRailLayout.drawWidth,
                    minHeight: PlaybackControlDeckPresentation.minimumSpatialHitTarget
                )
                .fixedSize()
                .accessibilityLabel("Draw annotation")
                .accessibilityHint("Returns to the annotation tools")
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity)
        .background(ReplayTheme.cyan.opacity(0.07), in: RoundedRectangle(cornerRadius: 17))
        .overlay {
            RoundedRectangle(cornerRadius: 17)
                .stroke(ReplayTheme.cyan.opacity(0.24), lineWidth: 1)
        }
    }

    private func eventPageButton(direction: Int) -> some View {
        let movesBackward = direction < 0
        let destination = clampedEventPage + direction
        let isAvailable = destination >= 0 && destination < eventPageCount

        return Button {
            guard isAvailable else { return }
            withAnimation(.easeOut(duration: 0.18)) {
                eventPage = destination
            }
        } label: {
            Image(systemName: movesBackward ? "chevron.left" : "chevron.right")
                .font(.headline.weight(.black))
                .frame(
                    minWidth: PlaybackControlDeckPresentation.minimumSpatialHitTarget,
                    minHeight: PlaybackControlDeckPresentation.minimumSpatialHitTarget
                )
        }
        .buttonStyle(.bordered)
        .fixedSize()
        .disabled(!isAvailable || store.hasActiveCoachMarkGeometryPreview)
        .accessibilityLabel(movesBackward ? "Previous timeline page" : "Next timeline page")
        .accessibilityValue(visibleEventRangeLabel)
        .accessibilityHint(
            isAvailable
                ? "Shows the adjacent group of match cues and annotations"
                : "No more events in this direction"
        )
    }

    @ViewBuilder
    private func reviewEventButton(_ event: PlaybackReviewEvent) -> some View {
        switch event {
        case .cue(let cue):
            Button {
                selectedAnnotationID = nil
                jump(to: cue)
            } label: {
                eventChipLabel(
                    time: cue.time,
                    title: cue.kicker,
                    systemImage: "flag.fill"
                )
            }
            .buttonStyle(.plain)
            .background(.white.opacity(0.10), in: RoundedRectangle(cornerRadius: 15))
            .overlay {
                RoundedRectangle(cornerRadius: 15)
                    .stroke(.white.opacity(0.11), lineWidth: 1)
            }
            .hoverEffect(.highlight)
            .disabled(timelineControlsAreDisabled)
            .accessibilityLabel("Cue at \(formatTime(cue.time)), \(cue.headline)")

        case .mark(let mark):
            Button {
                showsPlaybackAnnotations = true
                selectedAnnotationID = mark.id
                showsDecisionStrip = false
                jump(to: mark)
            } label: {
                eventChipLabel(
                    time: mark.revealTime,
                    title: mark.kind.title,
                    systemImage: mark.kind.systemImage
                )
            }
            .buttonStyle(.plain)
            .background(
                annotationColor(for: mark.kind).opacity(0.24),
                in: RoundedRectangle(cornerRadius: 15)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 15)
                    .stroke(annotationColor(for: mark.kind).opacity(0.34), lineWidth: 1)
            }
            .hoverEffect(.highlight)
            .disabled(timelineControlsAreDisabled)
            .accessibilityLabel("\(mark.kind.title) annotation at \(formatTime(mark.revealTime))")
            .accessibilityHint(mark.label)
        }
    }

    private func eventChipLabel(
        time: TimeInterval,
        title: String,
        systemImage: String
    ) -> some View {
        HStack(spacing: 9) {
            Image(systemName: systemImage)
                .font(.headline.weight(.black))
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 1) {
                Text(formatTime(time))
                    .font(.caption2.monospacedDigit().weight(.black))
                    .foregroundStyle(.white.opacity(0.62))
                Text(title.uppercased())
                    .font(.caption.weight(.black))
                    .lineLimit(1)
                    .minimumScaleFactor(0.78)
                    .foregroundStyle(.white)
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 13)
        .frame(
            width: PlaybackEventRailLayout.chipWidth,
            height: PlaybackControlDeckPresentation.minimumSpatialHitTarget
        )
        .contentShape(RoundedRectangle(cornerRadius: 15))
    }

    private func selectedAnnotationInspector(_ mark: CoachMark) -> some View {
        VStack(spacing: 8) {
            HStack(spacing: 11) {
                Button {
                    if let index = reviewEvents.firstIndex(where: {
                        $0.id == "mark-\(mark.id.uuidString)"
                    }) {
                        eventPage = PlaybackEventRailLayout.page(
                            containing: index,
                            eventCount: reviewEvents.count
                        )
                    }
                    selectedAnnotationID = nil
                    showsEventStrip = true
                } label: {
                    Image(systemName: "chevron.left")
                        .frame(
                            minWidth: PlaybackControlDeckPresentation.minimumSpatialHitTarget,
                            minHeight: PlaybackControlDeckPresentation.minimumSpatialHitTarget
                        )
                }
                .buttonStyle(.bordered)
                .accessibilityLabel("Back to timeline")

                Image(systemName: mark.kind.systemImage)
                    .font(.headline.weight(.black))
                    .foregroundStyle(.black)
                    .frame(width: 48, height: 48)
                    .background(annotationColor(for: mark.kind), in: RoundedRectangle(cornerRadius: 13))

                annotationIdentity(mark)

                Spacer(minLength: 8)

                if let playerID = mark.playerID,
                   let player = store.selectedScenario.player(id: playerID) {
                    StatusPill(
                        text: "#\(player.shirtNumber) · \(player.positionCode)",
                        systemImage: "person.fill",
                        color: annotationColor(for: mark.kind)
                    )
                }

                if mark.hasSpatialElevation {
                    StatusPill(
                        text: "3D · \(annotationElevationLabel(mark.resolvedStartElevation)) → \(annotationElevationLabel(mark.resolvedEndElevation))",
                        systemImage: "cube.transparent",
                        color: annotationColor(for: mark.kind)
                    )
                }

                if store.localRole == .coach, isCoachCreated(mark) {
                    if mark.kind != .playerLabel {
                        annotationGeometryButton(mark)
                        annotationTrackingButton(mark)
                    }

                    Button {
                        toggleInlinePanel(.annotationDuration(mark.id))
                    } label: {
                        Label(annotationDurationLabel(mark), systemImage: "timer")
                            .frame(
                                minHeight: PlaybackControlDeckPresentation.minimumSpatialHitTarget
                            )
                    }
                    .buttonStyle(.bordered)
                    .accessibilityLabel("Annotation duration")
                    .accessibilityValue(annotationDurationLabel(mark))
                    .accessibilityHint("Opens duration choices in the control deck")
                    .accessibilityAddTraits(
                        inlinePanel == .annotationDuration(mark.id) ? .isSelected : []
                    )

                    Button(role: .destructive) {
                        if store.removeCoachMark(id: mark.id) {
                            selectedAnnotationID = nil
                            showsEventStrip = true
                            annotationConfirmation = "MARK DELETED"
                        }
                    } label: {
                        Label("Erase", systemImage: "eraser.fill")
                            .font(.subheadline.weight(.black))
                            .lineLimit(1)
                            .minimumScaleFactor(0.80)
                            .frame(
                                width: 92,
                                height: PlaybackControlDeckPresentation.minimumSpatialHitTarget
                            )
                    }
                    .buttonStyle(.bordered)
                    .accessibilityLabel("Delete annotation")
                    .accessibilityHint("Deletes this coach-created annotation")
                } else {
                    StatusPill(text: "MATCH", systemImage: "lock.fill", color: .secondary)
                }

                Button {
                    selectedAnnotationID = nil
                    showsEventStrip = false
                } label: {
                    Image(systemName: "xmark")
                        .frame(
                            minWidth: PlaybackControlDeckPresentation.minimumSpatialHitTarget,
                            minHeight: PlaybackControlDeckPresentation.minimumSpatialHitTarget
                        )
                }
                .buttonStyle(.bordered)
                .accessibilityLabel("Close annotation")
            }

            if store.localRole == .coach, isCoachCreated(mark) {
                HStack(spacing: 10) {
                    Label("MARK · \(formatTime(mark.revealTime))", systemImage: "clock.fill")
                        .font(.caption.monospacedDigit().weight(.black))
                        .foregroundStyle(ReplayTheme.cyan)

                    Spacer(minLength: 8)

                    Label("SCRUB ABOVE", systemImage: "hand.draw.fill")
                        .font(.caption2.monospaced().weight(.black))
                        .foregroundStyle(.white.opacity(0.62))

                    Button {
                        store.setPlaying(false, broadcast: false)
                        if store.retimeCoachMark(id: mark.id, to: store.playhead) {
                            annotationConfirmation = "MARK MOVED · \(formatTime(store.playhead))"
                        }
                    } label: {
                        Label("MOVE · \(formatTime(store.playhead))", systemImage: "arrow.right.to.line")
                            .font(.subheadline.monospacedDigit().weight(.black))
                            .lineLimit(1)
                            .minimumScaleFactor(0.78)
                            .frame(
                                minWidth: 170,
                                minHeight: PlaybackControlDeckPresentation.minimumSpatialHitTarget
                            )
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(ReplayTheme.cyan)
                    .foregroundStyle(.black)
                    .disabled(!canMoveAnnotation(mark, to: store.playhead))
                    .accessibilityLabel("Move annotation to current playhead")
                    .accessibilityValue(formatTime(store.playhead))
                    .accessibilityHint(
                        canMoveAnnotation(mark, to: store.playhead)
                            ? "Commits the annotation at the time selected on the main timeline"
                            : "Choose a different time or shorten the annotation duration"
                    )
                }
                .padding(.horizontal, 8)
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity)
        .background(annotationColor(for: mark.kind).opacity(0.08), in: RoundedRectangle(cornerRadius: 17))
        .overlay {
            RoundedRectangle(cornerRadius: 17)
                .stroke(annotationColor(for: mark.kind).opacity(0.28), lineWidth: 1)
        }
    }

    private func annotationGeometryButton(_ mark: CoachMark) -> some View {
        Button {
            toggleInlinePanel(.annotationGeometry(mark.id))
        } label: {
            Label("Adjust", systemImage: "arrow.up.and.down.and.arrow.left.and.right")
                .font(.subheadline.weight(.black))
                .lineLimit(1)
                .minimumScaleFactor(0.78)
                .frame(
                    minWidth: 112,
                    minHeight: PlaybackControlDeckPresentation.minimumSpatialHitTarget
                )
        }
        .buttonStyle(.bordered)
        .tint(annotationColor(for: mark.kind))
        .accessibilityLabel("Adjust annotation endpoints")
        .accessibilityHint(
            "Steer either endpoint on the pitch, then raise an endpoint or the complete stroke in quarter-metre steps"
        )
        .accessibilityAddTraits(
            inlinePanel == .annotationGeometry(mark.id) ? .isSelected : []
        )
        .accessibilityAction(named: "Move start left") {
            nudgeAnnotation(mark, endpoint: .start, x: -0.25, z: 0)
        }
        .accessibilityAction(named: "Move start right") {
            nudgeAnnotation(mark, endpoint: .start, x: 0.25, z: 0)
        }
        .accessibilityAction(named: "Move start upfield") {
            nudgeAnnotation(mark, endpoint: .start, x: 0, z: 0.25)
        }
        .accessibilityAction(named: "Move start back") {
            nudgeAnnotation(mark, endpoint: .start, x: 0, z: -0.25)
        }
        .accessibilityAction(named: "Move arrow point left") {
            nudgeAnnotation(mark, endpoint: .end, x: -0.25, z: 0)
        }
        .accessibilityAction(named: "Move arrow point right") {
            nudgeAnnotation(mark, endpoint: .end, x: 0.25, z: 0)
        }
        .accessibilityAction(named: "Move arrow point upfield") {
            nudgeAnnotation(mark, endpoint: .end, x: 0, z: 0.25)
        }
        .accessibilityAction(named: "Move arrow point back") {
            nudgeAnnotation(mark, endpoint: .end, x: 0, z: -0.25)
        }
    }

    private func annotationTrackingButton(_ mark: CoachMark) -> some View {
        Button {
            toggleInlinePanel(.annotationTracking(mark.id))
        } label: {
            Label(annotationTrackingButtonTitle(mark), systemImage: "link")
                .font(.subheadline.weight(.black))
                .lineLimit(1)
                .minimumScaleFactor(0.78)
                .frame(
                    minWidth: 116,
                    minHeight: PlaybackControlDeckPresentation.minimumSpatialHitTarget
                )
        }
        .buttonStyle(.bordered)
        .tint(annotationColor(for: mark.kind))
        .accessibilityLabel("Annotation player tracking")
        .accessibilityValue(annotationTrackingAccessibilityValue(mark))
        .accessibilityHint("Opens both teams. Choose a shirt to follow or fix the mark to the pitch")
        .accessibilityAddTraits(
            inlinePanel == .annotationTracking(mark.id) ? .isSelected : []
        )
    }

    private func annotationTrackingButtonTitle(_ mark: CoachMark) -> String {
        guard let playerID = annotationTrackingPlayerID(mark),
              let player = store.selectedScenario.player(id: playerID) else {
            return mark.followsPlayerTracks ? "Tracks" : "Follow"
        }
        return "Follow #\(player.shirtNumber)"
    }

    private func annotationTrackingAccessibilityValue(_ mark: CoachMark) -> String {
        guard mark.followsPlayerTracks else { return "Fixed to pitch" }
        if let playerID = annotationTrackingPlayerID(mark),
           let player = store.selectedScenario.player(id: playerID) {
            return "Both points follow \(player.team.shortTitle) number \(player.shirtNumber)"
        }
        return "Annotation points currently use different player tracks"
    }

    @discardableResult
    private func nudgeAnnotation(
        _ mark: CoachMark,
        endpoint: CoachMarkEndpoint,
        x: Float,
        z: Float
    ) -> Bool {
        guard store.nudgeCoachMarkEndpoint(
            id: mark.id,
            endpoint: endpoint,
            by: PitchPoint(x: x, z: z)
        ) else { return false }
        let distance = hypot(x, z)
        let distanceLabel = distance.formatted(
            .number.precision(.fractionLength(distance < 1 ? 2 : 1))
        )
        switch endpoint {
        case .start:
            annotationConfirmation = "START MOVED · \(distanceLabel) M"
        case .end:
            annotationConfirmation = "ARROW POINT MOVED · \(distanceLabel) M"
        }
        return true
    }

    private func nudgeAnnotationElevation(
        _ mark: CoachMark,
        target: CoachMarkElevationTarget,
        delta: Float
    ) {
        guard store.nudgeCoachMarkElevation(
            id: mark.id,
            target: target,
            by: delta
        ) else { return }
        let updated = store.marks.first { $0.id == mark.id } ?? mark
        let targetName = annotationElevationTargetName(target, kind: mark.kind).uppercased()
        annotationConfirmation = switch target {
        case .start:
            "\(targetName) · \(annotationElevationLabel(updated.resolvedStartElevation))"
        case .end:
            "\(targetName) · \(annotationElevationLabel(updated.resolvedEndElevation))"
        case .both:
            "\(targetName) · \(annotationElevationLabel((updated.resolvedStartElevation + updated.resolvedEndElevation) / 2))"
        }
    }

    private func previewAnnotation(
        _ mark: CoachMark,
        endpoint: CoachMarkEndpoint,
        gestureID: UUID,
        x: Float,
        z: Float
    ) -> CoachMarkEndpointPreviewResult? {
        store.previewCoachMarkEndpoint(
            id: mark.id,
            endpoint: endpoint,
            gestureID: gestureID,
            cumulativeDelta: PitchPoint(x: x, z: z)
        )
    }

    private func commitAnnotationPreview(
        _ mark: CoachMark,
        endpoint: CoachMarkEndpoint,
        gestureID: UUID
    ) -> PitchPoint? {
        guard let appliedDelta = store.commitCoachMarkEndpointPreview(
            id: mark.id,
            gestureID: gestureID
        ) else { return nil }
        let distance = hypot(appliedDelta.x, appliedDelta.z)
        let distanceLabel = distance.formatted(
            .number.precision(.fractionLength(distance < 1 ? 2 : 1))
        )
        switch endpoint {
        case .start:
            annotationConfirmation = "START MOVED · \(distanceLabel) M"
        case .end:
            annotationConfirmation = "ARROW POINT MOVED · \(distanceLabel) M"
        }
        return appliedDelta
    }

    @ViewBuilder
    private func annotationIdentity(_ mark: CoachMark) -> some View {
        if store.localRole == .coach,
           isCoachCreated(mark),
           mark.kind != .playerLabel {
            Button {
                toggleInlinePanel(.annotationLabel(mark.id))
            } label: {
                HStack(spacing: 8) {
                    VStack(alignment: .leading, spacing: 2) {
                        Eyebrow(
                            text: mark.kind.title,
                            color: annotationColor(for: mark.kind)
                        )
                        Text(mark.label)
                            .font(.headline.weight(.black))
                            .lineLimit(1)
                            .minimumScaleFactor(0.72)
                    }

                    Image(systemName: "chevron.up.chevron.down")
                        .font(.caption2.weight(.black))
                        .foregroundStyle(annotationColor(for: mark.kind))
                        .frame(width: 24, height: 24)
                        .background(
                            annotationColor(for: mark.kind).opacity(0.14),
                            in: RoundedRectangle(cornerRadius: 8)
                        )
                }
                .padding(.horizontal, 9)
                .frame(minHeight: PlaybackControlDeckPresentation.minimumSpatialHitTarget)
                .contentShape(RoundedRectangle(cornerRadius: 12))
                .background(.white.opacity(0.045), in: RoundedRectangle(cornerRadius: 12))
                .overlay {
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(annotationColor(for: mark.kind).opacity(0.34), lineWidth: 1)
                }
            }
            .buttonStyle(.plain)
            .layoutPriority(1)
            .accessibilityLabel("Annotation label")
            .accessibilityValue(mark.label)
            .accessibilityHint("Opens tactical label choices in the control deck")
            .accessibilityAddTraits(
                inlinePanel == .annotationLabel(mark.id) ? .isSelected : []
            )
        } else {
            VStack(alignment: .leading, spacing: 2) {
                Eyebrow(
                    text: mark.kind.title,
                    color: annotationColor(for: mark.kind)
                )
                Text(mark.label)
                    .font(.headline.weight(.black))
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
            }
        }
    }

    private func isCoachCreated(_ mark: CoachMark) -> Bool {
        !store.selectedScenario.coachMarks.contains { $0.id == mark.id }
    }

    private var decisionSnapshot: ReplayDecisionSnapshot? {
        store.selectedScenario.decisionReview(
            at: store.playhead,
            playerID: store.activePerspectiveID,
            currentMarks: store.marks
        )
    }

    private func annotationDurationLabel(_ mark: CoachMark) -> String {
        guard let hideTime = mark.hideTime else { return "To end" }
        let duration = max(hideTime - mark.revealTime, 0)
        return duration == duration.rounded()
            ? "\(Int(duration))s"
            : "\(duration.formatted(.number.precision(.fractionLength(1))))s"
    }

    private func canMoveAnnotation(
        _ mark: CoachMark,
        to time: TimeInterval
    ) -> Bool {
        guard time.isFinite,
              store.selectedScenario.duration.isFinite,
              (0...store.selectedScenario.duration).contains(time),
              abs(mark.revealTime - time) >= 0.05 else { return false }
        guard let hideTime = mark.hideTime else { return true }
        let visibleDuration = max(hideTime - mark.revealTime, 0)
        return time + visibleDuration <= store.selectedScenario.duration
    }

    private var directPlaybackRates: [Double] { [0.5, 1, 2, 4] }

    private var previousCue: CueMoment? {
        store.selectedScenario.moments.last { $0.time < store.playhead - 0.2 }
    }

    private var nextCue: CueMoment? {
        store.selectedScenario.moments.first { $0.time > store.playhead + 0.2 }
    }

    private var timelineControlsAreDisabled: Bool {
        store.isDrawing || store.hasActiveCoachMarkGeometryPreview
    }

    private var rateControlsAreDisabled: Bool {
        store.isDrawing || store.hasActiveCoachMarkGeometryPreview
    }

    private var primaryPlaybackControlIsDisabled: Bool {
        store.isDrawing || store.hasActiveCoachMarkGeometryPreview
    }

    private var playerControlIsDisabled: Bool {
        store.isDrawing || store.hasActiveCoachMarkGeometryPreview
    }

    private var secondaryPlaybackControlsAreDisabled: Bool {
        store.isDrawing || store.hasActiveCoachMarkGeometryPreview
    }

    private var toolsWorkflowIsPresented: Bool {
        showsToolsShelf
            || showsEventStrip
            || showsDecisionStrip
            || inlinePanel != nil
            || selectedAnnotation != nil
            || isClearAnnotationsPending
    }

    private var primaryPlaybackLabel: String {
        store.isActivelyPlaying ? "Pause" : "Play"
    }

    private var primaryPlaybackSystemImage: String {
        store.isActivelyPlaying ? "pause.fill" : "play.fill"
    }

    private var annotationInstruction: String {
        guard store.isDrawing else { return annotationConfirmation ?? "CHOOSE MARK" }
        if store.selectedTool == .playerLabel {
            return "PINCH PLAYER"
        }
        if isPinchDrawing {
            return isPinchDrawingReady ? "RELEASE TO SAVE" : "DRAG FARTHER"
        }
        return store.pendingDrawStart == nil
            ? "PINCH + DRAG"
            : "PINCH END · OR TAP"
    }

    private var annotationInstructionSystemImage: String {
        guard store.isDrawing else {
            return annotationConfirmation == nil ? "pencil.and.outline" : "checkmark.circle.fill"
        }
        if store.selectedTool == .playerLabel { return "person.crop.circle.badge.plus" }
        if isPinchDrawing {
            return isPinchDrawingReady ? "checkmark.circle.fill" : "arrow.up.right"
        }
        return store.pendingDrawStart == nil ? "hand.draw.fill" : "2.circle.fill"
    }

    private var annotationInstructionColor: Color {
        if store.isDrawing { return ReplayTheme.orange }
        if annotationConfirmation != nil { return ReplayTheme.signal }
        return .secondary
    }

    private var canUndoCoachAnnotation: Bool {
        store.marks.contains(where: isCoachCreated)
    }

    private func handlePrimaryPlaybackAction() {
        guard !primaryPlaybackControlIsDisabled else { return }
        store.togglePlayback()
    }

    private func jump(to cue: CueMoment) {
        store.setPlaying(false, broadcast: false)
        store.seek(to: cue.time, broadcast: store.localRole == .coach)
    }

    private func jump(to mark: CoachMark) {
        store.setPlaying(false, broadcast: false)
        store.seek(to: mark.revealTime, broadcast: store.localRole == .coach)
    }

    private func nudgeTimeline(by delta: TimeInterval) {
        store.setPlaying(false, broadcast: false)
        store.skip(by: delta, broadcast: store.localRole == .coach)
    }

    private func openAdjacentPlayerPOV(by offset: Int) {
        guard !playerControlIsDisabled else { return }
        guard let playerID = PlaybackPerspectiveNavigation.adjacentPlayerID(
            in: store.selectedScenario.players,
            activeID: store.activePerspectiveID,
            localFallbackID: store.localPerspectiveID,
            offset: offset
        ) else { return }
        openPlayerPOV(playerID)
    }

    private func openPlayerPOV(_ playerID: String) {
        guard !playerControlIsDisabled else { return }
        inlinePanel = nil
        showsPlayerGrid = false
        showsToolsShelf = false
        store.openLocalPlayerPOV(playerID)
    }

    private func annotationColor(for kind: CoachMarkKind) -> Color {
        switch kind {
        case .run: ReplayTheme.orange
        case .pass: ReplayTheme.cyan
        case .danger: .red
        case .space, .playerLabel: ReplayTheme.signal
        }
    }

    private func updateTimelineScrub(
        _ value: DragGesture.Value,
        railWidth: CGFloat,
        railLeadingInset: CGFloat
    ) {
        guard !timelineControlsAreDisabled else { return }

        var gestureState: PlaybackTimelineScrub.GestureState
        if let timelineScrubState {
            gestureState = timelineScrubState
        } else {
            gestureState = PlaybackTimelineScrub.begin(
                atRailLocation: value.startLocation.x - railLeadingInset,
                duration: store.selectedScenario.duration,
                railWidth: railWidth
            )
            guard store.beginTimelineScrub() else { return }
        }

        gestureState = PlaybackTimelineScrub.update(
            gestureState,
            duration: store.selectedScenario.duration,
            railWidth: railWidth,
            horizontalTranslation: value.translation.width,
            verticalTranslation: value.translation.height
        )
        timelineScrubState = gestureState
        // Preview stays device-local; only the final sample is published.
        guard store.previewTimelineScrub(to: gestureState.time) else {
            cancelInterruptedTimelineScrub()
            return
        }
    }

    private func finishTimelineScrub(
        _ value: DragGesture.Value,
        railWidth: CGFloat,
        railLeadingInset: CGFloat
    ) {
        guard !timelineControlsAreDisabled else {
            cancelInterruptedTimelineScrub()
            return
        }
        updateTimelineScrub(
            value,
            railWidth: railWidth,
            railLeadingInset: railLeadingInset
        )
        let committedTime = timelineScrubState?.time ?? store.playhead
        guard store.commitTimelineScrub(to: committedTime) else {
            resetTimelineScrubState()
            return
        }
        if store.localRole == .coach {
            store.flushReviewAutosave()
        }
        resetTimelineScrubState()
    }

    private func resetTimelineScrubState() {
        timelineScrubState = nil
    }

    private func cancelInterruptedTimelineScrub() {
        defer { resetTimelineScrubState() }
        store.cancelTimelineScrub()
    }

    private func adjustTimelineForAccessibility(direction: Int) {
        guard !timelineControlsAreDisabled else { return }
        store.setPlaying(false, broadcast: false)
        let adjustedTime = PlaybackTimelineScrub.adjustedTime(
            store.playhead,
            direction: direction,
            duration: store.selectedScenario.duration
        )
        store.seek(to: adjustedTime, broadcast: store.localRole == .coach)
    }

    private var shapeFocusStatusDeck: some View {
        HStack(spacing: 12) {
            Button(action: exit) {
                Image(systemName: "xmark")
            }
            .buttonStyle(.bordered)
            .accessibilityLabel("Exit Shape Focus")

            Image(systemName: store.shapeFocusStage == .ideal ? "arrow.triangle.branch" : "exclamationmark.triangle.fill")
                .foregroundStyle(store.shapeFocusStage == .ideal ? ReplayTheme.signal : ReplayTheme.orange)

            VStack(alignment: .leading, spacing: 2) {
                Eyebrow(
                    text: "Shape Focus • Step \(store.shapeFocusStage == .ideal ? 2 : 1) of 3",
                    color: store.shapeFocusStage == .ideal ? ReplayTheme.signal : ReplayTheme.orange
                )
                Text(store.shapeFocusStage == .ideal ? "Ideal shape • two passing lanes" : "Problem shape • one cover shadow")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Label("Use the Shape Focus panel", systemImage: "arrow.up.left")
                .font(.caption.weight(.bold))
                .foregroundStyle(.secondary)
        }
        .padding(14)
        .frame(maxWidth: 700)
        .glassBackgroundEffect(in: .rect(cornerRadius: 22))
    }

    private func formatTime(_ value: TimeInterval) -> String {
        let safeValue = value.isFinite ? max(value, 0) : 0
        let minutes = Int(safeValue) / 60
        let seconds = safeValue - Double(minutes * 60)
        return String(format: "%d:%04.1f", minutes, seconds)
    }

    private func rateLabel(_ rate: Double) -> String {
        rate == rate.rounded()
            ? "\(Int(rate))×"
            : "\(rate.formatted(.number.precision(.fractionLength(2))))×"
    }
}

private struct PerspectiveMatrixPanel: View {
    @Environment(ReplayStore.self) private var store

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Eyebrow(text: "Same instant", color: ReplayTheme.cyan)
                    Text("Four Minds")
                        .font(.title2.weight(.black))
                }
                Spacer()
                Text(String(format: "%05.2f", store.playhead))
                    .font(.headline.monospacedDigit().weight(.black))
            }

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 9) {
                ForEach(store.selectedScenario.featuredPerspectiveIDs.prefix(4), id: \.self) { id in
                    if let player = store.selectedScenario.player(id: id) {
                        PerspectiveCard(
                            player: player,
                            scenario: store.selectedScenario,
                            time: store.playhead,
                            selected: store.activePerspectiveID == id
                        ) {
                            // Card inspection follows the same private/local
                            // contract as pinching a player on the pitch. Only
                            // the explicit Take Squad action may replace the
                            // room's published perspective.
                            store.openLocalPlayerPOV(id)
                        }
                    }
                }
            }

            Text("Select a card to enter that player's live, head-tracked scene. The other cards are synchronized previews—not extra virtual cameras.")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(18)
        .glassBackgroundEffect(in: .rect(cornerRadius: 24))
    }
}

private struct PerspectiveCard: View {
    let player: PlayerTrack
    let scenario: ReplayScenario
    let time: TimeInterval
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("#\(player.shirtNumber)")
                        .font(.title3.monospacedDigit().weight(.black))
                    Spacer()
                    Image(systemName: selected ? "viewfinder.circle.fill" : "viewfinder")
                        .foregroundStyle(selected ? ReplayTheme.signal : .secondary)
                }
                Text(player.role)
                    .font(.caption.weight(.bold))
                    .lineLimit(1)
                Text("VISIBILITY MAP")
                    .font(.caption2.monospaced().weight(.black))
                    .foregroundStyle(.secondary)
                PerspectiveMiniMap(
                    scenario: scenario,
                    player: player,
                    time: time
                )
                .frame(height: 64)
                Text(insight)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
            .background(selected ? ReplayTheme.signal.opacity(0.10) : Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 14))
            .overlay { RoundedRectangle(cornerRadius: 14).stroke(selected ? ReplayTheme.signal.opacity(0.46) : Color.white.opacity(0.08), lineWidth: 1) }
        }
        .buttonStyle(.plain)
    }

    private var insight: String {
        switch player.shirtNumber {
        case 7: "Defender squared. Pass window is brief."
        case 2: "Outside channel opening beyond the press."
        case 8: "Arrive beneath the cover shadow."
        case 3: "Runner moves behind the outside shoulder."
        default: "A different picture of the same second."
        }
    }
}

private struct PerspectiveMiniMap: View {
    let scenario: ReplayScenario
    let player: PlayerTrack
    let time: TimeInterval

    var body: some View {
        Canvas { context, size in
            let pose = player.presentationPose(at: time)
            let centre = CGPoint(x: size.width / 2, y: size.height * 0.68)
            let scale: CGFloat = 2.35

            var horizon = Path()
            horizon.move(to: CGPoint(x: 5, y: size.height * 0.84))
            horizon.addLine(to: CGPoint(x: size.width - 5, y: size.height * 0.84))
            context.stroke(horizon, with: .color(.white.opacity(0.18)), lineWidth: 1)

            let angle = CGFloat((pose.facingDegrees - 90) * .pi / 180)
            let coneLength: CGFloat = 47
            var cone = Path()
            cone.move(to: centre)
            cone.addLine(to: CGPoint(
                x: centre.x + cos(angle - 0.42) * coneLength,
                y: centre.y + sin(angle - 0.42) * coneLength
            ))
            cone.addLine(to: CGPoint(
                x: centre.x + cos(angle + 0.42) * coneLength,
                y: centre.y + sin(angle + 0.42) * coneLength
            ))
            cone.closeSubpath()
            context.fill(cone, with: .color(ReplayTheme.signal.opacity(0.13)))

            for other in scenario.players where other.id != player.id {
                let otherPose = other.presentationPose(at: time)
                let dx = CGFloat(otherPose.position.x - pose.position.x)
                let dz = CGFloat(otherPose.position.z - pose.position.z)
                guard hypot(dx, dz) < 22 else { continue }
                let point = CGPoint(
                    x: centre.x + (dx * scale),
                    y: centre.y - (dz * scale)
                )
                guard point.x > 3, point.x < size.width - 3,
                      point.y > 3, point.y < size.height - 3 else { continue }
                let color = other.team == player.team ? ReplayTheme.cyan : ReplayTheme.danger
                context.fill(
                    Path(ellipseIn: CGRect(x: point.x - 3, y: point.y - 3, width: 6, height: 6)),
                    with: .color(color)
                )
            }

            context.fill(
                Path(ellipseIn: CGRect(x: centre.x - 5, y: centre.y - 5, width: 10, height: 10)),
                with: .color(ReplayTheme.signal)
            )
        }
        .background(Color.black.opacity(0.26), in: RoundedRectangle(cornerRadius: 9))
        .overlay { RoundedRectangle(cornerRadius: 9).stroke(Color.white.opacity(0.08), lineWidth: 1) }
        .accessibilityHidden(true)
    }
}

private enum ShapeFocusStep: Int, CaseIterable, Identifiable {
    case problem = 1
    case ideal = 2
    case physical = 3

    var id: Int { rawValue }

    var title: String {
        switch self {
        case .problem: "Problem"
        case .ideal: "Ideal"
        case .physical: "Physical"
        }
    }

    var systemImage: String {
        switch self {
        case .problem: "exclamationmark.triangle.fill"
        case .ideal: "arrow.triangle.branch"
        case .physical: "figure.stand"
        }
    }
}

private struct PositioningPanel: View {
    @Environment(ReplayStore.self) private var store
    @Environment(LocalPitchAnchorCoordinator.self) private var sharedSpace
    @State private var placementError: String?
    @State private var showsPlacementPreflight = false
    @State private var hasConfirmedClearArea = false

    private var stage: ShapeFocusStep {
        if store.triangleLockMode == .place || showsPlacementPreflight { return .physical }
        return store.shapeFocusStage == .ideal ? .ideal : .problem
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    Eyebrow(text: "Shape Focus • Step \(stage.rawValue) of 3", color: stageColor)
                    Text(stageTitle)
                        .font(.title3.weight(.black))
                }
                Spacer()
                Image(systemName: stage.systemImage)
                    .font(.title3.weight(.black))
                    .foregroundStyle(stageColor)
            }

            shapeProgress
            Divider()

            if store.triangleLockMode == .visualise {
                if showsPlacementPreflight {
                    placementPreflight
                } else {
                    shapeReviewContent
                }
            } else if !store.hasLocallyAcknowledgedTrianglePlacement {
                playerAcknowledgement
            } else {
                placeContent
            }
        }
        .padding(18)
        .glassBackgroundEffect(in: .rect(cornerRadius: 24))
        .onChange(of: store.triangleLockMode) { _, mode in
            if mode == .visualise {
                showsPlacementPreflight = false
                hasConfirmedClearArea = false
                placementError = nil
            }
        }
    }

    private var shapeProgress: some View {
        HStack(spacing: 7) {
            ForEach(ShapeFocusStep.allCases) { item in
                Button {
                    selectStage(item)
                } label: {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 5) {
                            Text("\(item.rawValue)")
                                .font(.caption2.monospacedDigit().weight(.black))
                                .foregroundStyle(item == stage ? .black : .secondary)
                                .frame(width: 20, height: 20)
                                .background(item == stage ? color(for: item) : Color.white.opacity(0.08), in: Circle())
                            Image(systemName: item.systemImage)
                                .font(.caption2.weight(.bold))
                                .foregroundStyle(item == stage ? color(for: item) : .secondary)
                        }
                        Text(item.title)
                            .font(.caption2.weight(.black))
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(9)
                    .background(item == stage ? color(for: item).opacity(0.09) : Color.white.opacity(0.025), in: RoundedRectangle(cornerRadius: 11))
                    .overlay {
                        RoundedRectangle(cornerRadius: 11)
                            .stroke(item == stage ? color(for: item).opacity(0.38) : Color.white.opacity(0.07), lineWidth: 1)
                    }
                }
                .buttonStyle(.plain)
                .disabled(!stageIsEnabled(item))
                .opacity(stageIsEnabled(item) ? 1 : 0.48)
                .accessibilityLabel("Shape Focus step \(item.rawValue), \(item.title)")
            }
        }
    }

    @ViewBuilder
    private var shapeReviewContent: some View {
        VStack(alignment: .leading, spacing: 7) {
            Label(
                store.shapeFocusStage == .ideal ? "Two passing lanes stay open" : "One cover shadow blocks both options",
                systemImage: store.shapeFocusStage == .ideal ? "checkmark.circle.fill" : "nosign"
            )
            .font(.headline.weight(.black))
            .foregroundStyle(store.shapeFocusStage == .ideal ? ReplayTheme.signal : ReplayTheme.orange)

            Text(
                store.shapeFocusStage == .ideal
                    ? "#8 stays inside and beneath the play, #7 holds the wide return, and #2 goes outside and beyond."
                    : "#8 starts on the ball. #7 and #2 sit on one passing angle, so the cover shadow removes both forward options."
            )
            .font(.caption.weight(.semibold))
            .foregroundStyle(.white.opacity(0.88))
            .fixedSize(horizontal: false, vertical: true)
        }
        .padding(12)
        .background(stageColor.opacity(0.08), in: RoundedRectangle(cornerRadius: 14))
        .overlay {
            RoundedRectangle(cornerRadius: 14)
                .stroke(stageColor.opacity(0.25), lineWidth: 1)
        }

        VStack(alignment: .leading, spacing: 7) {
            Eyebrow(text: "Correction to teach")
            ForEach(store.selectedScenario.formationTargets) { target in
                roleRow(target)
            }
        }

        Divider()

        if store.shapeFocusStage == .problem {
            Button {
                showIdeal()
            } label: {
                Label("Reveal ideal — open two lanes", systemImage: "arrow.right")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(ReplayTheme.signal)
            .foregroundStyle(.black)
        } else {
            HStack(spacing: 8) {
                Button {
                    showProblem()
                } label: {
                    Label("Compare problem", systemImage: "arrow.uturn.backward")
                }
                .buttonStyle(.bordered)

                if store.localRole == .coach {
                    Button {
                        beginPhysicalPreflight()
                    } label: {
                        Label("Continue to physical", systemImage: "arrow.right")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(ReplayTheme.signal)
                    .foregroundStyle(.black)
                } else {
                    Label("Coach role required for physical setup", systemImage: "person.badge.key")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
            }
        }

        Label("Tabletop markers only. Stay where you are during steps 1 and 2.", systemImage: "figure.stand")
            .font(.caption2.weight(.semibold))
            .foregroundStyle(.secondary)
    }

    @ViewBuilder
    private var placementPreflight: some View {
        VStack(alignment: .leading, spacing: 9) {
            Label("Before any physical marker appears", systemImage: "checkmark.shield.fill")
                .font(.headline.weight(.black))
                .foregroundStyle(ReplayTheme.orange)

            Text("Shape Focus uses a local origin across an approximately 5 m × 3 m clear area. Vision Pro does not detect feet, people, furniture, or every obstacle for this drill.")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Label("Stay stationary", systemImage: "figure.stand")
            Label("The entire marked area is clear", systemImage: "square.dashed")
            Label("Station markers are local to this headset", systemImage: "visionpro")
        }
        .font(.caption.weight(.semibold))

        Toggle(isOn: $hasConfirmedClearArea) {
            Text("I checked the full area. I will stay stationary. No running.")
                .font(.caption.weight(.black))
        }
        .toggleStyle(.switch)

        HStack(spacing: 8) {
            StatusPill(
                text: placementModeLabel,
                systemImage: placementModeSystemImage,
                color: placementModeColor
            )

        }

        HStack(spacing: 8) {
            Button("Back to ideal") {
                showsPlacementPreflight = false
                hasConfirmedClearArea = false
                placementError = nil
            }
            .buttonStyle(.bordered)

            Button(placementButtonTitle) {
                placeLocalStations()
            }
            .buttonStyle(.borderedProminent)
            .tint(ReplayTheme.orange)
            .disabled(!canPlaceLocalStations)
        }

        if let placementError {
            Label(placementError, systemImage: "exclamationmark.circle.fill")
                .font(.caption2)
                .foregroundStyle(ReplayTheme.danger)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    @ViewBuilder
    private var playerAcknowledgement: some View {
        Label(
            "Choose the role you will rehearse",
            systemImage: "person.crop.circle.badge.checkmark"
        )
            .font(.headline.weight(.black))
        stationSelector

        Text("Stay still and look around. Your station remains hidden until this headset confirms that the area is clear.")
            .font(.caption)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)

        StatusPill(
            text: sharedSpace.hasUsableSharedPitchFrame ? "ORIGIN READY" : "LOCALIZING ORIGIN",
            systemImage: sharedSpace.hasUsableSharedPitchFrame ? "checkmark.circle" : "location",
            color: sharedSpace.hasUsableSharedPitchFrame ? ReplayTheme.signal : ReplayTheme.orange
        )

        Button {
            store.acknowledgeTrianglePlacementLocally(
                participantID: nil,
                sharedSession: false
            )
        } label: {
            Label("I’m stationary — reveal my station", systemImage: "eye.fill")
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderedProminent)
        .tint(ReplayTheme.signal)
        .foregroundStyle(.black)
        .disabled(
            !sharedSpace.hasUsableSharedPitchFrame
                || !store.canRevealPhysicalTriangleMarkers(
                    participantID: nil,
                    sharedSession: false
                )
        )

        Label("Consent is local to this headset and can be withdrawn at any time.", systemImage: "visionpro")
            .font(.caption2)
            .foregroundStyle(.secondary)
    }

    @ViewBuilder
    private var placeContent: some View {
        Label(
            "Your role station",
            systemImage: "scope"
        )
            .font(.headline.weight(.black))
        stationSelector

        if let assignedTarget {
            VStack(alignment: .leading, spacing: 9) {
                HStack {
                    VStack(alignment: .leading, spacing: 3) {
                        Eyebrow(text: store.localRole == .coach ? "Previewing" : "Assigned role", color: ReplayTheme.signal)
                        Text(assignedRoleLabel(for: assignedTarget))
                            .font(.headline.weight(.black))
                    }
                    Spacer()
                    StatusPill(
                        text: placementStatus,
                        systemImage: isInsideAssignedTarget ? "checkmark" : "location.fill",
                        color: isInsideAssignedTarget ? ReplayTheme.signal : ReplayTheme.orange
                    )
                }

                if let correction = correctionText(for: assignedTarget) {
                    Text(correction)
                        .font(.caption.monospacedDigit().weight(.semibold))
                        .foregroundStyle(isInsideAssignedTarget ? ReplayTheme.signal : .white)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(12)
            .background((isInsideAssignedTarget ? ReplayTheme.signal : ReplayTheme.orange).opacity(0.08), in: RoundedRectangle(cornerRadius: 14))
        }

        Label("Look up first. If clear, take one slow step, then stop and read the correction again. Never run or chase a marker.", systemImage: "exclamationmark.triangle.fill")
            .font(.caption2.weight(.semibold))
            .foregroundStyle(ReplayTheme.orange)
            .fixedSize(horizontal: false, vertical: true)

        Divider()

        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text(sharedSpace.status.label)
                    .font(.caption.monospaced().weight(.black))
                    .foregroundStyle(sharedSpace.hasUsableSharedPitchFrame ? ReplayTheme.signal : ReplayTheme.orange)
                Text("Only this headset’s wearer is measured.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if store.localRole == .coach {
                Button("End drill") {
                    store.endTrianglePlacement()
                    Task { await sharedSpace.removeLocallyPlacedPitchAnchor() }
                }
                .buttonStyle(.bordered)
            } else {
                Button("Hide my station") {
                    store.revokeTrianglePlacementConsentLocally()
                }
                .buttonStyle(.bordered)
            }
        }

        Text(LocalPitchAnchorCoordinator.trackingDisclosure)
            .font(.caption2)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }

    @ViewBuilder
    private var stationSelector: some View {
            HStack(spacing: 6) {
                ForEach(store.selectedScenario.formationTargets) { target in
                    let isSelected = target.playerID == assignedTarget?.playerID
                    Button {
                        store.setLocalPerspective(target.playerID, entersLocalReview: false)
                    } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            if let player = store.selectedScenario.player(id: target.playerID) {
                                Text("#\(player.shirtNumber)")
                                    .font(.caption.monospacedDigit().weight(.black))
                                Text(shortRole(player.role))
                                    .font(.caption2.weight(.semibold))
                                    .lineLimit(1)
                            } else {
                                Text(target.label)
                                    .font(.caption2.weight(.semibold))
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .buttonStyle(.bordered)
                    .tint(isSelected ? ReplayTheme.signal : .white.opacity(0.45))
                    .accessibilityLabel("Choose \(target.label) station")
                }
            }
    }

    @ViewBuilder
    private func roleRow(_ target: FormationTarget) -> some View {
        if let player = store.selectedScenario.player(id: target.playerID) {
            HStack(spacing: 8) {
                Text("#\(player.shirtNumber)")
                    .font(.caption2.monospacedDigit().weight(.black))
                    .foregroundStyle(.black)
                    .frame(width: 30, height: 24)
                    .background(ReplayTheme.signal, in: RoundedRectangle(cornerRadius: 6))
                VStack(alignment: .leading, spacing: 1) {
                    Text(player.role)
                        .font(.caption.weight(.black))
                    Text(target.label)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }
        }
    }

    private func stageIsEnabled(_ item: ShapeFocusStep) -> Bool {
        if item == .physical { return store.localRole == .coach }
        return store.triangleLockMode != .place
    }

    private func color(for item: ShapeFocusStep) -> Color {
        switch item {
        case .problem: ReplayTheme.orange
        case .ideal: ReplayTheme.signal
        case .physical: ReplayTheme.cyan
        }
    }

    private var stageColor: Color {
        color(for: stage)
    }

    private var stageTitle: String {
        switch stage {
        case .problem: "Diagnose the blocked shape"
        case .ideal: "See the corrected triangle"
        case .physical: "Rehearse the spacing"
        }
    }

    private func selectStage(_ item: ShapeFocusStep) {
        switch item {
        case .problem: showProblem()
        case .ideal: showIdeal()
        case .physical: beginPhysicalPreflight()
        }
    }

    private func showProblem() {
        guard store.triangleLockMode == .visualise else { return }
        showsPlacementPreflight = false
        hasConfirmedClearArea = false
        placementError = nil
        store.setShapeFocusStage(.problem)
    }

    private func showIdeal() {
        guard store.triangleLockMode == .visualise else { return }
        showsPlacementPreflight = false
        hasConfirmedClearArea = false
        placementError = nil
        store.setShapeFocusStage(.ideal)
    }

    private func beginPhysicalPreflight() {
        guard store.localRole == .coach, store.triangleLockMode == .visualise else { return }
        showIdeal()
        showsPlacementPreflight = true
    }

    private var canPlaceLocalStations: Bool {
        hasConfirmedClearArea && sharedSpace.isRunning && !sharedSpace.isPlacingPitchAnchor
    }

    private var placementButtonTitle: String {
        sharedSpace.isPlacingPitchAnchor ? "Anchoring…" : "Place local stations"
    }

    private func placeLocalStations() {
        guard canPlaceLocalStations else { return }
        Task {
            do {
                let anchorID = try await sharedSpace.placeLocalPitchAnchorAtCurrentHeadset()
                guard store.isImmersiveOpen, showsPlacementPreflight,
                      hasConfirmedClearArea, store.triangleLockMode == .visualise else {
                    await sharedSpace.removeLocallyPlacedPitchAnchor()
                    return
                }
                store.activateLocalTrianglePreview(anchorID: anchorID)
                sharedSpace.selectSharedPitchAnchor(id: anchorID)
                placementError = nil
                showsPlacementPreflight = false
            } catch {
                placementError = error.localizedDescription
            }
        }
    }

    private var placementModeLabel: String { "LOCAL POSITIONING" }

    private var placementModeSystemImage: String { "visionpro" }

    private var placementModeColor: Color { ReplayTheme.cyan }

    private var placementStatus: String {
        guard sharedSpace.hasUsableSharedPitchFrame else { return "POSITIONING PAUSED" }
        guard let distanceToAssignedTarget else { return "WAITING FOR ORIGIN" }
        if isInsideAssignedTarget { return "IN ZONE" }
        return "\(distanceToAssignedTarget.formatted(.number.precision(.fractionLength(2))))m AWAY"
    }

    private var assignedTarget: FormationTarget? {
        store.physicalTriangleTarget(
            participantID: nil,
            sharedSession: false
        )
    }



    private var distanceToAssignedTarget: Float? {
        guard store.triangleLockMode == .place,
              store.hasLocallyAcknowledgedTrianglePlacement,
              sharedSpace.hasUsableSharedPitchFrame,
              let target = assignedTarget,
              let pose = sharedSpace.horizontalHeadsetPose else { return nil }
        let station = PitchSceneFactory.positionalTargetPoint(
            for: target,
            in: store.selectedScenario,
            mode: .place
        )
        return hypot(station.x - pose.x, station.z - pose.z)
    }

    private var isInsideAssignedTarget: Bool {
        guard let distanceToAssignedTarget else { return false }
        return distanceToAssignedTarget <= TriangleLockLayout.placeTolerance
    }

    private func assignedRoleLabel(for target: FormationTarget) -> String {
        guard let player = store.selectedScenario.player(id: target.playerID) else {
            return target.label
        }
        return "#\(player.shirtNumber) \(player.role) • \(target.label)"
    }

    private func shortRole(_ role: String) -> String {
        role.replacingOccurrences(of: "Right ", with: "R ")
            .replacingOccurrences(of: "Centre ", with: "C ")
    }

    private func correctionText(for target: FormationTarget) -> String? {
        guard sharedSpace.hasUsableSharedPitchFrame,
              let pose = sharedSpace.horizontalHeadsetPose else {
            return "Positioning paused — stay still while the local origin localizes."
        }
        let station = PitchSceneFactory.positionalTargetPoint(
            for: target,
            in: store.selectedScenario,
            mode: .place
        )
        let displacement = LocalPitchAnchorCoordinator.wearerRelativeDisplacement(
            from: pose,
            targetX: station.x,
            targetZ: station.z
        )
        if displacement.distanceMetres <= TriangleLockLayout.placeTolerance {
            return "In zone. Stop here and look across both passing lanes."
        }

        var offsets: [String] = []
        if abs(displacement.rightMetres) > 0.05 {
            offsets.append(
                "\(abs(displacement.rightMetres).formatted(.number.precision(.fractionLength(2))))m \(displacement.rightMetres > 0 ? "right" : "left")"
            )
        }
        if abs(displacement.forwardMetres) > 0.05 {
            offsets.append(
                "\(abs(displacement.forwardMetres).formatted(.number.precision(.fractionLength(2))))m \(displacement.forwardMetres > 0 ? "forward" : "back")"
            )
        }
        return "Relative to where you face: " + offsets.joined(separator: " • ") + ". Take one slow step, then stop."
    }
}
