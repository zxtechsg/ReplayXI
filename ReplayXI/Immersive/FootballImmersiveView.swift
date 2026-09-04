import RealityKit
import SwiftUI

struct FootballImmersiveView: View {
    @Environment(ReplayStore.self) private var store
    @Environment(SquadSessionCoordinator.self) private var squadSession
    @Environment(SharedSpaceAnchorCoordinator.self) private var sharedSpace
    @Environment(\.dismissImmersiveSpace) private var dismissImmersiveSpace
    @Environment(\.openWindow) private var openWindow
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @AppStorage("ReplayXI.PlaybackControlDeckPreset") private var controlDeckPresetRawValue =
        PlaybackControlDeckPreset.standard.rawValue
    @State private var selectedAnnotationID: UUID?
    @State private var draggedAnnotationTarget: AnnotationSceneTarget?
    @State private var annotationStroke: PlaybackAnnotationStroke?
    @GestureState private var spatialDragIsActive = false
    @State private var showsDecisionStrip = false

    private var controlDeckPreset: PlaybackControlDeckPreset {
        PlaybackControlDeckPreset(rawValue: controlDeckPresetRawValue) ?? .standard
    }

    private var controlDeckLayout: PlaybackControlDeckLayout {
        PlaybackControlDeckLayout.resolve(
            preset: controlDeckPreset,
            usesAccessibilityText: dynamicTypeSize.isAccessibilitySize
        )
    }

    var body: some View {
        RealityView { content, attachments in
            let root = PitchSceneFactory.makeMatchRoot(for: store.selectedScenario)
            content.add(root)
            // Keep the primary transport in a stable, reachable comfort band
            // below the wearer's sightline. A native head anchor follows the
            // physical wearer independently of the replayed player's moving
            // first-person origin, so the pitch can never leave the controls
            // behind. Continuous (rather than predicted) tracking avoids
            // anticipatory panel motion while turning the head.
            let controlsAnchor = AnchorEntity(.head, trackingMode: .continuous)
            controlsAnchor.name = "playback-controls-head-anchor"
            content.add(controlsAnchor)
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
                        participantID: squadSession.localParticipantID,
                        sharedSession: squadSession.state == .joined
                    ),
                showsIdealBranch: store.showsIdealBranch
            )
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
                            participantID: squadSession.localParticipantID,
                            sharedSession: squadSession.state == .joined
                        ),
                    showsIdealBranch: store.showsIdealBranch
                )
            }
            // Attachments do not inherit the match-root presentation transform.
            // Re-assert their room-space placement whenever view mode or another
            // observed playback value causes RealityView to update.
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
                    controlDeckPresetRawValue: $controlDeckPresetRawValue,
                    isPinchDrawing: annotationStroke != nil,
                    isPinchDrawingReady: annotationStroke?.isReadyToCommit == true,
                    exit: exitRoom
                )
                    .frame(width: controlDeckLayout.attachmentWidth)
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
                try? await Task.sleep(for: .milliseconds(33))
                let now = clock.now
                let duration = previous.duration(to: now)
                previous = now
                let seconds = Double(duration.components.seconds)
                    + (Double(duration.components.attoseconds) / 1e18)
                store.advance(by: seconds)
            }
        }
        .onDisappear {
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
            store.isImmersiveOpen = false
            store.isOpeningImmersive = false
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
        for id in ["room-header", "coach-console", "perspective-matrix", "position-status"] {
            if let entity = attachments.entity(for: id) {
                entity.name = id
                if id == "coach-console" {
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
        attachments.entity(for: "perspective-matrix")?.position = [0.92, 1.30, -1.55]
        attachments.entity(for: "position-status")?.position = [-1.00, 1.30, -1.30]
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
            let position = player.pose(at: store.playhead).position
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
                    store.registerPitchTap(player.pose(at: store.playhead).position)
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
        let start = target.role == .start ? point : mark.start
        let end = target.role == .end ? point : mark.end
        guard store.updateCoachMarkGeometry(
            id: target.markID,
            start: start,
            end: end,
            broadcast: false
        ) else { return }

        draggedAnnotationTarget = target
        selectedAnnotationID = target.markID
        store.setPlaying(false, broadcast: false)
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
        let start = target.role == .start ? point : mark.start
        let end = target.role == .end ? point : mark.end
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
                        sourcePlayer.pose(at: store.playhead).position
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
                    _ = store.registerPitchTap(player.pose(at: store.playhead).position)
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
        // Player selection is local. Sharing the POV remains an explicit coach
        // action in the transport deck, preventing an accidental squad switch.
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
            store.setPlaying(false)
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
    @Environment(SquadSessionCoordinator.self) private var squadSession

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
                text: squadSession.state.label,
                systemImage: squadSession.state == .joined ? "shareplay" : "person.crop.circle"
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

private struct ImmersiveControlDeck: View {
    @Environment(ReplayStore.self) private var store
    @Environment(SquadSessionCoordinator.self) private var squadSession
    @State private var wasPlayingBeforeScrub = false
    @State private var annotationConfirmation: String?
    @State private var showsEventStrip = false
    @State private var showsPlayerGrid = false
    @State private var eventPage = 0
    @State private var orderedReviewMarks: [CoachMark] = []
    @State private var indexedReviewEvents: [PlaybackReviewEvent] = []
    @State private var timelineTickClusters: [PlaybackEventRailLayout.TimelineTickCluster] = []
    @State private var timelineTrackWidth: CGFloat = 0
    @State private var timelineScrubState: PlaybackTimelineScrub.GestureState?
    @State private var isClearAnnotationsPending = false
    @Binding var selectedAnnotationID: UUID?
    @Binding var showsDecisionStrip: Bool
    @Binding var controlDeckPresetRawValue: String

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
    }

    private var matchPlaybackDeck: some View {
        VStack(alignment: .leading, spacing: 11) {
            HStack(spacing: 10) {
                Button(action: exit) {
                    Image(systemName: "xmark")
                        .frame(width: 32, height: 56)
                }
                .buttonStyle(.bordered)
                .accessibilityLabel("Exit spatial replay")

                Image(systemName: "play.square.stack.fill")
                    .font(.title3.weight(.black))
                    .foregroundStyle(ReplayTheme.signal)
                    .frame(width: 38, height: 56)
                    .accessibilityLabel("Match playback")

                Button {
                    if let previousCue { jump(to: previousCue) }
                } label: {
                    Image(systemName: "backward.end.fill")
                        .frame(width: 34, height: 56)
                }
                .buttonStyle(.bordered)
                .disabled(previousCue == nil || timelineControlsAreDisabled)
                .accessibilityLabel("Previous cue")

                Button {
                    nudgeTimeline(by: -1)
                } label: {
                    Text("−1s")
                        .font(.subheadline.monospacedDigit().weight(.black))
                        .frame(minWidth: 40, minHeight: 56)
                }
                .buttonStyle(.bordered)
                .buttonRepeatBehavior(.enabled)
                .disabled(timelineControlsAreDisabled)
                .accessibilityLabel("Back one second")
                .accessibilityHint("Pinch and hold to keep stepping backward")

                Button(action: handlePrimaryPlaybackAction) {
                    Label(primaryPlaybackLabel, systemImage: primaryPlaybackSystemImage)
                        .font(.subheadline.weight(.black))
                        .lineLimit(1)
                        .minimumScaleFactor(0.78)
                        .frame(width: 108, height: 56)
                }
                .buttonStyle(.borderedProminent)
                .tint(ReplayTheme.signal)
                .foregroundStyle(.black)
                .disabled(store.isDrawing)

                Button {
                    nudgeTimeline(by: 1)
                } label: {
                    Text("+1s")
                        .font(.subheadline.monospacedDigit().weight(.black))
                        .frame(minWidth: 40, minHeight: 56)
                }
                .buttonStyle(.bordered)
                .buttonRepeatBehavior(.enabled)
                .disabled(timelineControlsAreDisabled)
                .accessibilityLabel("Forward one second")
                .accessibilityHint("Pinch and hold to keep stepping forward")

                Button {
                    if let nextCue { jump(to: nextCue) }
                } label: {
                    Image(systemName: "forward.end.fill")
                        .frame(width: 34, height: 56)
                }
                .buttonStyle(.bordered)
                .disabled(nextCue == nil || timelineControlsAreDisabled)
                .accessibilityLabel("Next cue")

                timelineScrubber
                    .layoutPriority(1)
                annotationEventsButton
                decisionReviewButton
            }

            if !isReviewShelfOpen {
                HStack(spacing: 9) {
                    playbackSettingsMenu

                    Spacer()

                    Label("DRAG TIMELINE · MOVE UP FOR FINE", systemImage: "hand.point.up.left.fill")
                        .font(.caption2.monospaced().weight(.black))
                        // This sits over live passthrough rather than an opaque
                        // window. Keep it clearly legible in a bright room while
                        // retaining lower emphasis than the transport itself.
                        .foregroundStyle(.white.opacity(0.72))
                        .lineLimit(1)
                        .minimumScaleFactor(0.76)
                }

                HStack(spacing: 9) {
                    Label("POV", systemImage: "hand.tap.fill")
                        .font(.caption.monospaced().weight(.black))
                        .foregroundStyle(ReplayTheme.signal)
                        .frame(width: 58, alignment: .leading)

                    Button {
                        openAdjacentPlayerPOV(by: -1)
                    } label: {
                        Image(systemName: "chevron.left")
                            .font(.headline.weight(.black))
                            .frame(width: 34, height: 52)
                    }
                    .buttonStyle(.bordered)
                    .disabled(store.isDrawing)
                    .accessibilityLabel("Previous player")

                    Button {
                        showsPlayerGrid = true
                        showsEventStrip = false
                        showsDecisionStrip = false
                        selectedAnnotationID = nil
                    } label: {
                        if let player = store.activePerspective {
                            Label(
                                "\(player.team.compactTitle) · #\(player.shirtNumber) \(player.positionCode)",
                                systemImage: "person.crop.rectangle.stack"
                            )
                            .font(.subheadline.weight(.black))
                            .lineLimit(1)
                            .minimumScaleFactor(0.76)
                            .frame(width: 236, height: 52)
                        } else {
                            Label("Choose player", systemImage: "person.crop.rectangle.stack")
                                .lineLimit(1)
                                .minimumScaleFactor(0.76)
                                .frame(width: 236, height: 52)
                        }
                    }
                    .buttonStyle(.bordered)
                    .disabled(store.isDrawing)
                    .accessibilityLabel(
                        store.activePerspective.map {
                            "Focused player, number \($0.shirtNumber), \($0.role)"
                        } ?? "Choose focused player"
                    )
                    .accessibilityHint(
                        squadSession.state == .joined
                            ? "Opens all 22 players for a private local selection"
                            : "Opens direct point-of-view targets for all 22 players"
                    )

                    Button {
                        openAdjacentPlayerPOV(by: 1)
                    } label: {
                        Image(systemName: "chevron.right")
                            .font(.headline.weight(.black))
                            .frame(width: 34, height: 52)
                    }
                    .buttonStyle(.bordered)
                    .disabled(store.isDrawing)
                    .accessibilityLabel("Next player")

                    if squadSession.state == .joined {
                        povSharingStatusChip
                    }

                    if store.viewMode == .firstPerson {
                        povStatusChip
                    }

                    Spacer(minLength: 4)

                    if store.localRole == .coach, squadSession.state == .joined {
                        coachPOVShareControls
                    }

                    if hasRoomActions {
                        roomActionsMenu
                    }
                }
            }

            if isClearAnnotationsPending {
                clearAnnotationsConfirmationStrip
            } else if showsPlayerGrid {
                playerPOVGrid
            } else if showsDecisionStrip, let decisionSnapshot {
                PlaybackDecisionStrip(
                    snapshot: decisionSnapshot,
                    scenario: store.selectedScenario,
                    onSelectPlayer: openPlayerPOV,
                    onClose: { showsDecisionStrip = false }
                )
            } else if let selectedAnnotation {
                selectedAnnotationInspector(selectedAnnotation)
            } else if showsEventStrip {
                annotationEventStrip
            } else if store.localRole == .coach {
                coachAnnotationStrip
            }
        }
        .padding(18)
        .padding(4)
        .frame(maxWidth: 1200)
        .controlSize(.extraLarge)
        .background(ReplayTheme.navy.opacity(0.46), in: RoundedRectangle(cornerRadius: 26))
        .overlay {
            RoundedRectangle(cornerRadius: 26)
                .stroke(.white.opacity(0.13), lineWidth: 1)
        }
        .glassBackgroundEffect(in: .rect(cornerRadius: 26))
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
        }
        .onChange(of: store.selectedScenarioID) { _, _ in
            selectedAnnotationID = nil
            timelineScrubState = nil
            showsDecisionStrip = false
            showsEventStrip = false
            showsPlayerGrid = false
            isClearAnnotationsPending = false
            eventPage = 0
            annotationConfirmation = nil
            rebuildReviewIndex()
        }
        .onChange(of: reviewIndexKeys) { _, _ in
            rebuildReviewIndex()
        }
        .onChange(of: selectedAnnotationID) { _, selectedID in
            if selectedID != nil {
                showsPlayerGrid = false
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
            if arguments.contains("--replayxi-events") {
                showsEventStrip = true
            }
            if arguments.contains("--replayxi-player-grid") {
                showsPlayerGrid = true
                showsEventStrip = false
                showsDecisionStrip = false
            }
            if arguments.contains("--replayxi-options") {
                selectedAnnotationID = nil
                showsEventStrip = false
                showsDecisionStrip = true
                store.setPlaying(false, broadcast: false)
            }
            if arguments.contains("--replayxi-select-coach-mark") {
                selectedAnnotationID = store.marks.last?.id
                showsDecisionStrip = false
                showsEventStrip = true
            }
            if arguments.contains("--replayxi-clear-confirm") {
                isClearAnnotationsPending = true
                selectedAnnotationID = nil
                showsDecisionStrip = false
                showsEventStrip = false
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

    private var playbackSettingsMenu: some View {
        Menu {
            Section("Speed") {
                ForEach(directPlaybackRates, id: \.self) { rate in
                    Button {
                        store.setPlaybackRate(rate, broadcast: store.localRole == .coach)
                    } label: {
                        if store.playbackRate == rate {
                            Label(rateLabel(rate), systemImage: "checkmark")
                        } else {
                            Text(rateLabel(rate))
                        }
                    }
                    .disabled(rateControlsAreDisabled)
                }
            }

            Section("View") {
                ForEach(viewModes, id: \.self) { mode in
                    Button {
                        store.setViewMode(mode)
                    } label: {
                        if store.viewMode == mode {
                            Label(viewLabel(for: mode), systemImage: "checkmark")
                        } else {
                            Label(viewLabel(for: mode), systemImage: mode.systemImage)
                        }
                    }
                    .disabled(store.isDrawing)
                }
            }

            Section("Control deck") {
                ForEach(PlaybackControlDeckPreset.allCases, id: \.self) { preset in
                    Button {
                        controlDeckPresetRawValue = preset.rawValue
                    } label: {
                        if controlDeckPreset == preset {
                            Label(preset.title, systemImage: "checkmark")
                        } else {
                            Label(preset.title, systemImage: preset.systemImage)
                        }
                    }
                }
            }
        } label: {
            Label(
                "\(rateLabel(store.playbackRate)) · \(viewLabel(for: store.viewMode))",
                systemImage: "slider.horizontal.3"
            )
            .font(.subheadline.weight(.black))
            .lineLimit(1)
            .minimumScaleFactor(0.76)
            .frame(width: 210, height: 52)
        }
        .buttonStyle(.bordered)
        .disabled(store.isDrawing)
        .accessibilityLabel("Playback settings")
        .accessibilityValue(
            "\(rateLabel(store.playbackRate)), \(viewLabel(for: store.viewMode))"
        )
        .accessibilityHint("Changes playback speed, camera view, or local control size and reach")
    }

    private var controlDeckPreset: PlaybackControlDeckPreset {
        PlaybackControlDeckPreset(rawValue: controlDeckPresetRawValue) ?? .standard
    }

    private var hasRoomActions: Bool {
        store.localRole == .coach
            && store.selectedScenario.kind == .passingChannels
    }

    private var roomActionsMenu: some View {
        Menu {
            Button {
                store.showsLaneLens.toggle()
                squadSession.broadcastCurrentState()
            } label: {
                Label(
                    store.showsLaneLens ? "Hide passing lanes" : "Show passing lanes",
                    systemImage: store.showsLaneLens ? "eye.slash" : "arrow.triangle.branch"
                )
            }
        } label: {
            Label("Lanes", systemImage: "arrow.triangle.branch")
                .font(.subheadline.weight(.black))
                .lineLimit(1)
                .frame(width: 104, height: 52)
        }
        .buttonStyle(.bordered)
        .tint(
            store.showsLaneLens
                ? ReplayTheme.orange
                : .white.opacity(0.48)
        )
        .accessibilityLabel("Passing lane actions")
        .accessibilityHint("Shows or hides the descriptive passing lanes")
    }

    private func annotationEditMenu(compact: Bool) -> some View {
        Menu {
            Button(action: undoLastCoachAnnotation) {
                Label("Undo last", systemImage: "arrow.uturn.backward")
            }
            .disabled(!canUndoCoachAnnotation)

            Button(action: armClearAnnotations) {
                Label("Clear coach marks…", systemImage: "eraser.fill")
            }
            .disabled(clearableCoachAnnotationCount == 0)
        } label: {
            Group {
                if compact {
                    Image(systemName: "eraser.fill")
                        .frame(width: 32, height: 48)
                } else {
                    Label("Edit", systemImage: "eraser.fill")
                        .font(.subheadline.weight(.black))
                        .lineLimit(1)
                        .minimumScaleFactor(0.78)
                        .frame(width: 92, height: 48)
                }
            }
        }
        .buttonStyle(.bordered)
        .disabled(store.localRole != .coach || clearableCoachAnnotationCount == 0)
        .accessibilityLabel("Edit annotations")
        .accessibilityValue("\(clearableCoachAnnotationCount) coach marks")
        .accessibilityHint("Undo the latest mark or start a safe clear")
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
        }
    }

    private func armClearAnnotations() {
        guard store.localRole == .coach, clearableCoachAnnotationCount > 0 else { return }
        if store.isDrawing {
            store.cancelDrawing()
        }
        showsDecisionStrip = false
        showsEventStrip = false
        showsPlayerGrid = false
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
                    Eyebrow(text: "22 PLAYER POV", color: ReplayTheme.signal)
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
            .frame(width: 72, height: 50)
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

    private var playerGridInstruction: String {
        guard squadSession.state == .joined else { return "PINCH A SHIRT" }
        return store.localRole == .coach
            ? "PICK LOCAL · SHARE AFTER"
            : "PRIVATE COMFORT REVIEW"
    }

    private var playerPOVAccessibilityHint: String {
        guard squadSession.state == .joined else {
            return "Opens this player's free-look point of view"
        }
        if store.localRole == .coach {
            return "Selects this point of view locally. Use Take Squad afterward to share it."
        }
        return "Pauses coach follow and opens this player's private free-look point of view."
    }

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

            annotationEditMenu(compact: true)
        }
        .padding(16)
        .frame(width: 1080)
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

            // Events already has a persistent primary-row button. Keeping a
            // duplicate here forced its title into a vertical stack under
            // spatial-size compression and obscured the actual drawing tools.
            annotationEditMenu(compact: true)
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

    private var povSharingStatusChip: some View {
        StatusPill(
            text: povSharingStatusText,
            systemImage: povSharingStatusSystemImage,
            color: povSharingStatusColor
        )
        .accessibilityLabel("Point-of-view scope")
        .accessibilityValue(povSharingStatusAccessibilityValue)
    }

    private var coachPOVShareControls: some View {
        HStack(spacing: 7) {
            if store.coachLockEnabled {
                Button {
                    store.releaseSquad()
                } label: {
                    Label("END SQUAD", systemImage: "person.3.sequence.fill")
                        .font(.subheadline.weight(.black))
                        .lineLimit(1)
                        .minimumScaleFactor(0.74)
                        .frame(width: 128, height: 52)
                }
                .buttonStyle(.bordered)
                .tint(ReplayTheme.orange)
                .accessibilityLabel("End squad point-of-view share")
                .accessibilityHint("Returns every participant to their assigned perspective")
            }

            if !isCurrentCoachPOVShared {
                Button {
                    store.broadcastPerspective(store.localPerspectiveID)
                } label: {
                    Label(coachPOVShareButtonLabel, systemImage: "dot.radiowaves.left.and.right")
                        .font(.subheadline.weight(.black))
                        .lineLimit(1)
                        .minimumScaleFactor(0.74)
                        .frame(width: 142, height: 52)
                }
                .buttonStyle(.borderedProminent)
                .tint(ReplayTheme.cyan)
                .foregroundStyle(.black)
                .accessibilityLabel("Take squad to selected player point of view")
                .accessibilityHint(
                    "Pauses playback and explicitly changes every participant's perspective"
                )
            }
        }
    }

    private func annotationToolButton(_ kind: CoachMarkKind, label: String) -> some View {
        let isSelected = store.isDrawing && store.selectedTool == kind
        return Button {
            annotationConfirmation = nil
            selectedAnnotationID = nil
            showsPlayerGrid = false
            showsDecisionStrip = false
            showsEventStrip = false
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

    private var reviewIndexKeys: [PlaybackReviewIndexKey] {
        store.marks.map(PlaybackReviewIndexKey.init)
    }

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

    /// Opening a review shelf temporarily removes secondary rate, view, and
    /// roster rows. The pitch and 3D handles stay visible; closing the shelf
    /// restores the full transport without losing replay state.
    private var isReviewShelfOpen: Bool {
        showsDecisionStrip
            || showsEventStrip
            || showsPlayerGrid
            || selectedAnnotation != nil
            || isClearAnnotationsPending
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
        .frame(minWidth: 230, maxWidth: .infinity, minHeight: 58, maxHeight: 58)
        .disabled(timelineControlsAreDisabled)
    }

    private var annotationEventsButton: some View {
        let isOpen = showsEventStrip || selectedAnnotation != nil
        return Button {
            let opensEvents = !showsEventStrip
            selectedAnnotationID = nil
            showsPlayerGrid = false
            showsDecisionStrip = false
            showsEventStrip.toggle()
            if opensEvents {
                eventPage = PlaybackEventRailLayout.page(
                    nearestTo: store.playhead,
                    events: reviewEvents,
                    time: { $0.time }
                )
            }
        } label: {
            VStack(spacing: 1) {
                Image(systemName: "list.bullet.rectangle.fill")
                    .font(.headline.weight(.bold))
                Text("EVENTS")
                    .font(.caption2.monospaced().weight(.black))
                    .minimumScaleFactor(0.75)
            }
            .frame(width: 54, height: 56)
        }
        .buttonStyle(.borderedProminent)
        .tint(isOpen ? ReplayTheme.cyan : .white.opacity(0.10))
        .foregroundStyle(isOpen ? Color.black : Color.white)
        .disabled(store.isDrawing || reviewEvents.isEmpty)
        .accessibilityLabel("Review events")
        .accessibilityValue("\(reviewEvents.count) events")
        .accessibilityHint(isOpen ? "Closes the event strip" : "Shows cues and annotations")
    }

    private var decisionReviewButton: some View {
        Button {
            selectedAnnotationID = nil
            showsPlayerGrid = false
            showsEventStrip = false
            showsDecisionStrip.toggle()
            if showsDecisionStrip {
                if isJoinedPlayer {
                    // Decision review is a local comfort pause for a follower.
                    // Leaving follow and pausing must be one state transition or
                    // the next coach heartbeat immediately overwrites this view.
                    _ = store.beginLocalReview(at: store.playhead)
                } else {
                    store.setPlaying(false, broadcast: false)
                }
            }
        } label: {
            VStack(spacing: 1) {
                Image(systemName: "eye.fill")
                    .font(.headline.weight(.bold))
                Text("OPTIONS")
                    .font(.caption2.monospaced().weight(.black))
                    .minimumScaleFactor(0.75)
            }
            .frame(width: 58, height: 56)
        }
        .buttonStyle(.borderedProminent)
        .tint(showsDecisionStrip ? ReplayTheme.cyan : .white.opacity(0.10))
        .foregroundStyle(showsDecisionStrip ? Color.black : Color.white)
        // Keep an already-open control closable even if imported/replaced data
        // temporarily has no decision snapshot for the current player.
        .disabled(store.isDrawing || (decisionSnapshot == nil && !showsDecisionStrip))
        .accessibilityLabel("Decision options")
        .accessibilityHint(
            showsDecisionStrip
                ? "Closes descriptive passing options"
                : "Pauses and shows the selected player's descriptive passing lanes"
        )
    }

    private var annotationEventStrip: some View {
        HStack(spacing: PlaybackEventRailLayout.horizontalSpacing) {
            Button {
                showsEventStrip = false
            } label: {
                Image(systemName: "xmark")
                    .frame(width: 32, height: 56)
            }
            .buttonStyle(.bordered)
            .frame(width: PlaybackEventRailLayout.closeWidth, height: 56)
            .fixedSize()
            .accessibilityLabel("Close events")

            VStack(alignment: .leading, spacing: 2) {
                Eyebrow(text: "Events", color: ReplayTheme.cyan)
                Text(visibleEventRangeLabel)
                    .font(.caption2.monospacedDigit().weight(.black))
                    .foregroundStyle(.white.opacity(0.58))
            }
            .frame(width: PlaybackEventRailLayout.headingWidth, alignment: .leading)
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Events, \(visibleEventRangeLabel)")

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
                } label: {
                    Label("DRAW", systemImage: "pencil.and.outline")
                        .font(.subheadline.weight(.black))
                        .lineLimit(1)
                        .frame(width: 100, height: 56)
                }
                .buttonStyle(.borderedProminent)
                .tint(ReplayTheme.orange)
                .foregroundStyle(.black)
                .frame(width: PlaybackEventRailLayout.drawWidth, height: 56)
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
                .frame(width: 30, height: 56)
        }
        .buttonStyle(.bordered)
        .frame(width: PlaybackEventRailLayout.pageButtonWidth, height: 56)
        .fixedSize()
        .disabled(!isAvailable)
        .accessibilityLabel(movesBackward ? "Previous events" : "Next events")
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
        .frame(width: PlaybackEventRailLayout.chipWidth, height: 56)
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
                        .frame(width: 28, height: 48)
                }
                .buttonStyle(.bordered)
                .accessibilityLabel("Back to events")

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

                if store.localRole == .coach, isCoachCreated(mark) {
                    if mark.kind != .playerLabel {
                        annotationGeometryMenu(mark)
                    }

                    Menu {
                        ForEach([3.0, 5.0, 8.0, 12.0], id: \.self) { duration in
                            Button("\(Int(duration)) seconds") {
                                _ = store.setCoachMarkDuration(id: mark.id, duration: duration)
                            }
                        }
                        Button("Until replay ends") {
                            _ = store.setCoachMarkDuration(id: mark.id, duration: nil)
                        }
                    } label: {
                        Label(annotationDurationLabel(mark), systemImage: "timer")
                            .frame(minHeight: 48)
                    }
                    .buttonStyle(.bordered)
                    .accessibilityLabel("Annotation duration")
                    .accessibilityValue(annotationDurationLabel(mark))

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
                            .frame(width: 92, height: 48)
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
                        .frame(width: 28, height: 48)
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
                            .frame(minWidth: 170, minHeight: 48)
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

    private func annotationGeometryMenu(_ mark: CoachMark) -> some View {
        Menu {
            Section("Start point · 0.5 metre") {
                Button("Left") {
                    nudgeAnnotation(mark, endpoint: .start, x: -0.5, z: 0)
                }
                Button("Right") {
                    nudgeAnnotation(mark, endpoint: .start, x: 0.5, z: 0)
                }
                Button("Upfield") {
                    nudgeAnnotation(mark, endpoint: .start, x: 0, z: 0.5)
                }
                Button("Back") {
                    nudgeAnnotation(mark, endpoint: .start, x: 0, z: -0.5)
                }
            }

            Section("Arrow point · 0.5 metre") {
                Button("Left") {
                    nudgeAnnotation(mark, endpoint: .end, x: -0.5, z: 0)
                }
                Button("Right") {
                    nudgeAnnotation(mark, endpoint: .end, x: 0.5, z: 0)
                }
                Button("Upfield") {
                    nudgeAnnotation(mark, endpoint: .end, x: 0, z: 0.5)
                }
                Button("Back") {
                    nudgeAnnotation(mark, endpoint: .end, x: 0, z: -0.5)
                }
            }
        } label: {
            Label("Adjust", systemImage: "arrow.up.and.down.and.arrow.left.and.right")
                .font(.subheadline.weight(.black))
                .lineLimit(1)
                .minimumScaleFactor(0.78)
                .frame(minWidth: 112, minHeight: 48)
        }
        .buttonStyle(.bordered)
        .tint(annotationColor(for: mark.kind))
        .accessibilityLabel("Adjust annotation endpoints")
        .accessibilityHint(
            "Pinch and drag either glowing pitch handle, or choose a precise half-metre move"
        )
        .accessibilityAction(named: "Move start left") {
            nudgeAnnotation(mark, endpoint: .start, x: -0.5, z: 0)
        }
        .accessibilityAction(named: "Move start right") {
            nudgeAnnotation(mark, endpoint: .start, x: 0.5, z: 0)
        }
        .accessibilityAction(named: "Move start upfield") {
            nudgeAnnotation(mark, endpoint: .start, x: 0, z: 0.5)
        }
        .accessibilityAction(named: "Move start back") {
            nudgeAnnotation(mark, endpoint: .start, x: 0, z: -0.5)
        }
        .accessibilityAction(named: "Move arrow point left") {
            nudgeAnnotation(mark, endpoint: .end, x: -0.5, z: 0)
        }
        .accessibilityAction(named: "Move arrow point right") {
            nudgeAnnotation(mark, endpoint: .end, x: 0.5, z: 0)
        }
        .accessibilityAction(named: "Move arrow point upfield") {
            nudgeAnnotation(mark, endpoint: .end, x: 0, z: 0.5)
        }
        .accessibilityAction(named: "Move arrow point back") {
            nudgeAnnotation(mark, endpoint: .end, x: 0, z: -0.5)
        }
    }

    private func nudgeAnnotation(
        _ mark: CoachMark,
        endpoint: CoachMarkEndpoint,
        x: Float,
        z: Float
    ) {
        store.setPlaying(false, broadcast: false)
        guard store.nudgeCoachMarkEndpoint(
            id: mark.id,
            endpoint: endpoint,
            by: PitchPoint(x: x, z: z)
        ) else { return }
        switch endpoint {
        case .start:
            annotationConfirmation = "START MOVED · 0.5 M"
        case .end:
            annotationConfirmation = "ARROW POINT MOVED · 0.5 M"
        }
    }

    @ViewBuilder
    private func annotationIdentity(_ mark: CoachMark) -> some View {
        if store.localRole == .coach,
           isCoachCreated(mark),
           mark.kind != .playerLabel {
            Menu {
                ForEach(mark.kind.suggestedLabels, id: \.self) { label in
                    Button {
                        if store.updateCoachMarkLabel(id: mark.id, label: label) {
                            annotationConfirmation = "LABEL · \(label.uppercased())"
                        }
                    } label: {
                        if label == mark.label {
                            Label(label, systemImage: "checkmark")
                        } else {
                            Text(label)
                        }
                    }
                    .disabled(label == mark.label)
                }
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
                .frame(minHeight: 48)
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
            .accessibilityHint("Opens tactical label presets")
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
        store.isDrawing || (isJoinedPlayer && !store.isLocallyPaused)
    }

    private var rateControlsAreDisabled: Bool {
        store.isDrawing || isJoinedPlayer
    }

    private var primaryPlaybackLabel: String {
        if isJoinedPlayer {
            return store.isLocallyPaused ? "Rejoin" : "Hold"
        }
        return store.isActivelyPlaying ? "Pause" : "Play"
    }

    private var primaryPlaybackSystemImage: String {
        if isJoinedPlayer {
            return store.isLocallyPaused ? "arrow.clockwise" : "pause.fill"
        }
        return store.isActivelyPlaying ? "pause.fill" : "play.fill"
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

    private var isCurrentCoachPOVShared: Bool {
        store.coachLockEnabled
            && store.coachFocusPerspectiveID == store.localPerspectiveID
            && !store.isCoachLocalReview
    }

    private var coachPOVShareButtonLabel: String {
        guard !isCurrentCoachPOVShared else { return "END SHARE" }
        guard let player = store.selectedScenario.player(id: store.localPerspectiveID) else {
            return "SHARE POV"
        }
        let side = player.team == .home ? "HOME" : "OPP"
        return "SHARE · \(side) #\(player.shirtNumber)"
    }

    private var sharedCoachPlayer: PlayerTrack? {
        guard let playerID = store.coachFocusPerspectiveID else { return nil }
        return store.selectedScenario.player(id: playerID)
    }

    private var sharedCoachPlayerCompactLabel: String? {
        guard let player = sharedCoachPlayer else { return nil }
        let side = player.team == .home ? "HOME" : "OPP"
        return "\(side) #\(player.shirtNumber) \(player.positionCode)"
    }

    private var povSharingStatusText: String {
        if store.localRole == .coach {
            if store.isCoachLocalReview {
                return sharedCoachPlayerCompactLabel.map { "LOCAL · SQUAD \($0)" } ?? "LOCAL ONLY"
            }
            return store.coachLockEnabled
                ? sharedCoachPlayerCompactLabel.map { "SQUAD · \($0)" } ?? "SHARED WITH SQUAD"
                : "LOCAL ONLY"
        }
        if store.followsCoach, store.coachLockEnabled {
            return "FOLLOWING COACH"
        }
        return store.isLocallyPaused ? "LOCAL REVIEW" : "OWN POV"
    }

    private var povSharingStatusSystemImage: String {
        if store.localRole == .coach, store.coachLockEnabled, !store.isCoachLocalReview {
            return "dot.radiowaves.left.and.right"
        }
        if store.localRole == .player, store.followsCoach, store.coachLockEnabled {
            return "person.3.fill"
        }
        return "person.crop.circle"
    }

    private var povSharingStatusColor: Color {
        if store.localRole == .coach, store.coachLockEnabled, !store.isCoachLocalReview {
            return ReplayTheme.orange
        }
        if store.localRole == .player, store.followsCoach, store.coachLockEnabled {
            return ReplayTheme.orange
        }
        return ReplayTheme.cyan
    }

    private var povSharingStatusAccessibilityValue: String {
        if store.localRole == .coach, store.isCoachLocalReview, let sharedCoachPlayer {
            return "Private local review. The squad remains on \(sharedCoachPlayer.team.shortTitle), number \(sharedCoachPlayer.shirtNumber), \(sharedCoachPlayer.role)."
        }
        if store.localRole == .coach, store.coachLockEnabled, let sharedCoachPlayer {
            return "\(sharedCoachPlayer.team.shortTitle), number \(sharedCoachPlayer.shirtNumber), \(sharedCoachPlayer.role), is shared with the squad."
        }
        if store.localRole == .coach {
            return "The selected point of view is local only."
        }
        if store.followsCoach, store.coachLockEnabled {
            return "Following the coach's shared point of view."
        }
        return "Private local review."
    }

    private func handlePrimaryPlaybackAction() {
        if isJoinedPlayer {
            squadSession.setFollowingCoach(store.isLocallyPaused)
        } else {
            store.togglePlayback()
        }
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
        store.selectAdjacentPerspective(by: offset)
        openPlayerPOV(store.localPerspectiveID)
    }

    private func openPlayerPOV(_ playerID: String) {
        showsPlayerGrid = false
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

    private func viewLabel(for mode: ReplayViewMode) -> String {
        switch mode {
        case .firstPerson: "Player POV"
        case .tacticalTable: "Tactical"
        case .touchline: "Touchline"
        case .positional: "Shape"
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
            wasPlayingBeforeScrub = store.isActivelyPlaying
            store.setPlaying(false, broadcast: false)
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
        store.seek(to: gestureState.time, broadcast: false)
    }

    private func finishTimelineScrub(
        _ value: DragGesture.Value,
        railWidth: CGFloat,
        railLeadingInset: CGFloat
    ) {
        guard !timelineControlsAreDisabled else {
            resetTimelineScrubState()
            return
        }
        updateTimelineScrub(
            value,
            railWidth: railWidth,
            railLeadingInset: railLeadingInset
        )
        let committedTime = timelineScrubState?.time ?? store.playhead
        store.seek(to: committedTime, broadcast: false)
        if wasPlayingBeforeScrub {
            store.setPlaying(true, broadcast: false)
        }
        if store.localRole == .coach {
            squadSession.broadcastCurrentState()
        }
        resetTimelineScrubState()
    }

    private func resetTimelineScrubState() {
        timelineScrubState = nil
        wasPlayingBeforeScrub = false
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

    private var isJoinedPlayer: Bool {
        store.localRole == .player && squadSession.state == .joined
    }

    private var viewModes: [ReplayViewMode] {
        store.selectedScenario.kind == .shapeLab
            ? [.positional, .tacticalTable, .firstPerson]
            : [.firstPerson, .tacticalTable, .touchline]
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
            let pose = player.pose(at: time)
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
                let otherPose = other.pose(at: time)
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
    @Environment(SharedSpaceAnchorCoordinator.self) private var sharedSpace
    @Environment(SquadSessionCoordinator.self) private var squadSession
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

        if store.localRole == .player && squadSession.state == .joined {
            HStack(spacing: 8) {
                Label(
                    store.isLocallyPaused ? "Local comparison paused from coach" : "Following coach",
                    systemImage: store.isLocallyPaused ? "pause.circle" : "person.badge.key.fill"
                )
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
                Spacer()
                if store.isLocallyPaused {
                    Button("Resume coach") {
                        squadSession.setFollowingCoach(true)
                    }
                    .buttonStyle(.bordered)
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

            Text("Shape Focus uses a shared origin across an approximately 5 m × 3 m clear area. Vision Pro does not detect feet, people, furniture, or every obstacle for this drill.")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Label("All wearers are stationary", systemImage: "figure.stand")
            Label("The entire marked area is clear", systemImage: "square.dashed")
            switch squadSession.state {
            case .joined:
                Label("A nearby SharePlay session is connected", systemImage: "shareplay")
            case .offline:
                Label("Solo mode creates a local-only station preview", systemImage: "visionpro")
            case .preparing, .waiting:
                Label("SharePlay is connecting — placement stays locked", systemImage: "hourglass")
            case .unavailable:
                Label("SharePlay is unavailable — return to solo mode before placement", systemImage: "exclamationmark.triangle.fill")
            }
        }
        .font(.caption.weight(.semibold))

        Toggle(isOn: $hasConfirmedClearArea) {
            Text("I checked the full area and briefed every wearer. No running.")
                .font(.caption.weight(.black))
        }
        .toggleStyle(.switch)

        HStack(spacing: 8) {
            StatusPill(
                text: placementModeLabel,
                systemImage: placementModeSystemImage,
                color: placementModeColor
            )

            if squadSession.state == .joined {
                StatusPill(
                    text: sharedSpace.isAnchorSharingAvailable ? "ANCHOR READY" : "WAITING FOR ANCHOR",
                    systemImage: sharedSpace.isAnchorSharingAvailable ? "checkmark.circle" : "location",
                    color: sharedSpace.isAnchorSharingAvailable ? ReplayTheme.signal : ReplayTheme.orange
                )
            }
        }

        if squadSession.state == .offline {
            Button {
                Task { await squadSession.startSharePlay() }
            } label: {
                Label("Start nearby SharePlay", systemImage: "shareplay")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(ReplayTheme.signal)
            .foregroundStyle(.black)
        } else if squadSession.physicalPlacementRoute == nil {
            Label("Wait until SharePlay reaches LIVE ROOM. No local anchor will be created while it is starting or waiting.", systemImage: "lock.shield.fill")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(ReplayTheme.orange)
                .fixedSize(horizontal: false, vertical: true)
        }

        HStack(spacing: 8) {
            Button("Back to ideal") {
                showsPlacementPreflight = false
                hasConfirmedClearArea = false
                placementError = nil
            }
            .buttonStyle(.bordered)

            Button(placementButtonTitle) {
                placeSharedStations()
            }
            .buttonStyle(.borderedProminent)
            .tint(ReplayTheme.orange)
            .disabled(!canPlaceSharedStations)
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
            isSharedPhysicalSession ? "Verify your assigned role" : "Choose the role you will rehearse",
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
                participantID: squadSession.localParticipantID,
                sharedSession: isSharedPhysicalSession
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
                    participantID: squadSession.localParticipantID,
                    sharedSession: isSharedPhysicalSession
                )
        )

        Label("Consent is local to this headset and can be withdrawn at any time.", systemImage: "visionpro")
            .font(.caption2)
            .foregroundStyle(.secondary)
    }

    @ViewBuilder
    private var placeContent: some View {
        Label(
            isSharedPhysicalSession && store.localRole == .coach
                ? "Shared station overview"
                : "Your role station",
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

        Text("The coach does not receive live body or foot positions. \(SharedSpaceAnchorCoordinator.trackingDisclosure)")
            .font(.caption2)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }

    @ViewBuilder
    private var stationSelector: some View {
        if isSharedPhysicalSession {
            if store.localRole == .coach {
                Label("Coach overview — stay at the origin and direct each assigned wearer.", systemImage: "person.badge.key.fill")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            } else if let assignedTarget {
                HStack(spacing: 10) {
                    Image(systemName: "lock.shield.fill")
                        .foregroundStyle(ReplayTheme.signal)
                    VStack(alignment: .leading, spacing: 2) {
                        Eyebrow(text: "Identity-bound station", color: ReplayTheme.signal)
                        Text(assignedRoleLabel(for: assignedTarget))
                            .font(.caption.weight(.black))
                    }
                    Spacer(minLength: 0)
                }
                .padding(10)
                .background(ReplayTheme.signal.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
                .accessibilityLabel("Assigned \(assignedTarget.label) station")
            } else {
                Label("No unique station is assigned to this headset. Stay still; markers remain hidden until the coach assignment arrives.", systemImage: "person.crop.circle.badge.exclamationmark")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(ReplayTheme.orange)
                    .fixedSize(horizontal: false, vertical: true)
            }
        } else {
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

    private var canPlaceSharedStations: Bool {
        guard store.localRole == .coach,
              hasConfirmedClearArea,
              sharedSpace.isRunning,
              !sharedSpace.isPlacingPitchAnchor,
              let route = squadSession.physicalPlacementRoute else { return false }
        switch route {
        case .localPreview: return true
        case .sharedSquad: return sharedSpace.isAnchorSharingAvailable
        }
    }

    private var placementButtonTitle: String {
        if sharedSpace.isPlacingPitchAnchor { return "Anchoring…" }
        return switch squadSession.physicalPlacementRoute {
        case .localPreview: "Place local station preview"
        case .sharedSquad: "Anchor 3 shared stations"
        case nil: "Placement locked while connecting"
        }
    }

    private func placeSharedStations() {
        guard canPlaceSharedStations,
              let requestedRoute = squadSession.physicalPlacementRoute else { return }
        Task {
            do {
                let anchorID: UUID
                switch requestedRoute {
                case .sharedSquad:
                    anchorID = try await sharedSpace.placeSharedPitchAnchorAtCurrentHeadset()
                case .localPreview:
                    anchorID = try await sharedSpace.placeLocalPitchAnchorAtCurrentHeadset()
                }

                guard squadSession.physicalPlacementRoute == requestedRoute else {
                    await sharedSpace.removeLocallyPlacedPitchAnchor()
                    placementError = "Connection state changed during placement. No station was activated; try again in a stable mode."
                    return
                }

                switch requestedRoute {
                case .sharedSquad:
                    store.activateTrianglePlacement(anchorID: anchorID)
                case .localPreview:
                    store.activateLocalTrianglePreview(anchorID: anchorID)
                }
                sharedSpace.selectSharedPitchAnchor(id: anchorID)
                placementError = nil
                showsPlacementPreflight = false
            } catch {
                placementError = error.localizedDescription
            }
        }
    }

    private var placementModeLabel: String {
        switch squadSession.state {
        case .offline: "LOCAL PREVIEW MODE"
        case .joined: "SHARED SQUAD MODE"
        case .preparing, .waiting: "CONNECTING — PLACEMENT LOCKED"
        case .unavailable: "PLACEMENT UNAVAILABLE"
        }
    }

    private var placementModeSystemImage: String {
        switch squadSession.state {
        case .offline: "visionpro"
        case .joined: "shareplay"
        case .preparing, .waiting: "hourglass"
        case .unavailable: "exclamationmark.triangle.fill"
        }
    }

    private var placementModeColor: Color {
        switch squadSession.state {
        case .offline: ReplayTheme.cyan
        case .joined: ReplayTheme.signal
        case .preparing, .waiting, .unavailable: ReplayTheme.orange
        }
    }

    private var placementStatus: String {
        guard sharedSpace.hasUsableSharedPitchFrame else { return "POSITIONING PAUSED" }
        guard let distanceToAssignedTarget else { return "WAITING FOR ORIGIN" }
        if isInsideAssignedTarget { return "IN ZONE" }
        return "\(distanceToAssignedTarget.formatted(.number.precision(.fractionLength(2))))m AWAY"
    }

    private var assignedTarget: FormationTarget? {
        store.physicalTriangleTarget(
            participantID: squadSession.localParticipantID,
            sharedSession: isSharedPhysicalSession
        )
    }

    private var isSharedPhysicalSession: Bool {
        squadSession.state == .joined && !store.isLocalTrianglePreview
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
            return "Positioning paused — stay still while the shared origin localizes."
        }
        let station = PitchSceneFactory.positionalTargetPoint(
            for: target,
            in: store.selectedScenario,
            mode: .place
        )
        let displacement = SharedSpaceAnchorCoordinator.wearerRelativeDisplacement(
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
