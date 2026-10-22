import XCTest
@testable import ReplayXI

final class PlaybackControlDeckClarityTests: XCTestCase {
    func testPlayerControlCopyAlwaysPromisesThePOVSelectionActuallyOpened() {
        XCTAssertEqual(
            PlaybackControlDeckPresentation.playerControlLabel(
                shirtNumber: 7
            ),
            "POV #7"
        )
        XCTAssertEqual(
            PlaybackControlDeckPresentation.playerControlLabel(
                shirtNumber: 23
            ),
            "POV #23"
        )
        XCTAssertEqual(
            PlaybackControlDeckPresentation.playerControlLabel(
                shirtNumber: nil
            ),
            "POV PLAYER"
        )
    }

    func testJoystickAccessibilityReportsOwnershipValidityAndAppliedMovement() {
        XCTAssertEqual(
            AnnotationJoystickAccessibility.value(
                isEnabled: false,
                appliedDelta: .zero,
                hasActiveTransaction: false,
                latestRequestWasAccepted: true,
                lastAction: nil
            ),
            "Unavailable while the other endpoint is being adjusted"
        )
        XCTAssertEqual(
            AnnotationJoystickAccessibility.value(
                isEnabled: true,
                appliedDelta: PitchPoint(x: 0.5, z: -0.25),
                hasActiveTransaction: true,
                latestRequestWasAccepted: true,
                lastAction: nil
            ),
            "Preview moved 50 centimetres right, 25 centimetres back"
        )
        XCTAssertEqual(
            AnnotationJoystickAccessibility.value(
                isEnabled: true,
                appliedDelta: .zero,
                hasActiveTransaction: true,
                latestRequestWasAccepted: false,
                lastAction: nil
            ),
            "Position unavailable; lift to cancel the adjustment"
        )
    }

    func testCollapsedOverlayBadgesExposeOnlyActiveApplicableOverlays() {
        XCTAssertEqual(
            PlaybackOverlayBadge.activeBadges(
                showsAnnotations: true,
                emphasizesBall: true,
                showsLanes: true,
                supportsLanes: true
            ),
            [.annotations, .ball, .lanes]
        )
        XCTAssertEqual(
            PlaybackOverlayBadge.activeBadges(
                showsAnnotations: false,
                emphasizesBall: true,
                showsLanes: true,
                supportsLanes: false
            ),
            [.ball],
            "A scenario without a lane overlay must not advertise a stale lane state."
        )
        XCTAssertTrue(
            PlaybackOverlayBadge.activeBadges(
                showsAnnotations: false,
                emphasizesBall: false,
                showsLanes: false,
                supportsLanes: true
            ).isEmpty
        )
    }

    func testHidingAnnotationsDismissesDrawingTools() {
        XCTAssertTrue(
            PlaybackControlDeckPresentation.shouldDismissDrawTools(
                annotationsAreVisible: false
            )
        )
        XCTAssertFalse(
            PlaybackControlDeckPresentation.shouldDismissDrawTools(
                annotationsAreVisible: true
            )
        )
    }

    func testEndpointPreviewOwnsPitchSelectionUntilTheGestureEnds() {
        XCTAssertFalse(
            PlaybackSpatialInteractionPolicy.acceptsPitchInteraction(
                hasActiveEndpointPreview: true
            )
        )
        XCTAssertTrue(
            PlaybackSpatialInteractionPolicy.acceptsPitchInteraction(
                hasActiveEndpointPreview: false
            )
        )
        XCTAssertFalse(
            PlaybackSpatialInteractionPolicy.acceptsPitchInteraction(
                hasActiveEndpointPreview: false,
                hasActiveTimelineScrub: true
            )
        )
    }

    func testHidingAnnotationsClearsEveryMarkEditingSurface() throws {
        let source = try immersiveSource()
        let transition = try sourceSlice(
            source,
            after: ".onChange(of: showsPlaybackAnnotations)",
            before: "private var matchPlaybackDeck: some View"
        )

        XCTAssertTrue(transition.contains("cancelCoachMarkGeometryPreview"))
        XCTAssertTrue(transition.contains("annotationHandleDrag.cancelCurrent(in: store)"))
        XCTAssertTrue(transition.contains("selectedAnnotationID = nil"))
        XCTAssertTrue(transition.contains("inlinePanel = nil"))
        XCTAssertTrue(transition.contains("isClearAnnotationsPending = false"))
        XCTAssertTrue(transition.contains("store.cancelDrawing()"))
    }

    func testJoystickCompletionUsesTheAuthoritativeEndTranslation() throws {
        let source = try immersiveSource()
        let gesture = try sourceSlice(
            source,
            after: "private var joystickGesture: some Gesture",
            before: "private func applyJoystickTranslation"
        )

        XCTAssertTrue(gesture.contains(".onEnded { value in"))
        XCTAssertTrue(gesture.contains("applyJoystickTranslation(value.translation)"))
    }

    func testJoystickDisablesWhileTimelineScrubOwnsInput() throws {
        let source = try immersiveSource()
        let policy = try sourceSlice(
            source,
            after: "private func annotationJoystickIsEnabled(",
            before: "private func annotationEndPointAccessibilityTarget"
        )

        XCTAssertTrue(policy.contains("!store.hasActiveTimelineScrub"))
    }

    func testSpatialControlTargetFloorIsAtLeastSixtyPoints() {
        XCTAssertGreaterThanOrEqual(
            PlaybackControlDeckPresentation.minimumSpatialHitTarget,
            60
        )
    }

    func testCollapsedDeckAndToolsShelfKeepOneClearCommandHierarchy() throws {
        let source = try immersiveSource()
        let baseRow = try sourceSlice(
            source,
            after: "private var matchPlaybackDeck: some View",
            before: "if isClearAnnotationsPending"
        )
        XCTAssertTrue(baseRow.contains("compactPlayerControlButton"))
        XCTAssertTrue(baseRow.contains("compactSpeedControlButton"))
        XCTAssertTrue(baseRow.contains("annotationToolsButton"))
        XCTAssertTrue(baseRow.contains("playbackToolsButton"))
        XCTAssertFalse(baseRow.contains("annotationEventsButton"))
        XCTAssertFalse(baseRow.contains("decisionReviewButton"))
        XCTAssertFalse(baseRow.contains("settingsToolButton"))

        let toolsShelf = try sourceSlice(
            source,
            after: "private var playbackToolsShelf: some View",
            before: "private var settingsToolButton: some View"
        )
        XCTAssertTrue(toolsShelf.contains("annotationEventsButton"))
        XCTAssertTrue(toolsShelf.contains("decisionReviewButton"))
        XCTAssertTrue(toolsShelf.contains("settingsToolButton"))
        XCTAssertTrue(toolsShelf.contains("annotationEditButton(compact: false)"))

        XCTAssertFalse(source.contains("Text(\"EVENTS\")"))
        XCTAssertFalse(source.contains("Text(\"MARK\")"))
        XCTAssertFalse(source.contains("Text(\"MORE\")"))
        let hud = try sourceSlice(source,
            after: "private var controls: some View",
            before: "private var environmentChoices: some View")
        XCTAssertTrue(hud.contains("Image(systemName: store.viewMode.systemImage)"))
        XCTAssertTrue(hud.contains("Text(\"POV\")"))
        XCTAssertFalse(hud.contains("Eyebrow(text: \"View & Overlays\""))
        XCTAssertTrue(hud.contains(".help("))
        XCTAssertTrue(hud.contains(".accessibilityLabel(\"View and overlays\")"))
    }

    func testSpeedShelfRetractsAndRemainsIndependentOfSelectedAnnotation() {
        XCTAssertEqual(PlaybackInlinePanel.toggled(current: nil, candidate: .playbackSpeed), .playbackSpeed)
        XCTAssertNil(PlaybackInlinePanel.toggled(current: .playbackSpeed, candidate: .playbackSpeed))
        XCTAssertEqual(PlaybackInlinePanel.toggled(current: .settings, candidate: .playbackSpeed), .playbackSpeed)
        XCTAssertTrue(PlaybackInlinePanel.playbackSpeed.isValid(for: nil))
        XCTAssertTrue(PlaybackInlinePanel.playbackSpeed.isValid(for: UUID()))
        XCTAssertFalse(PlaybackInlinePanel.playbackSpeed.isToolsPanel)
        XCTAssertTrue(PlaybackInlinePanel.settings.isToolsPanel)
        XCTAssertTrue(PlaybackInlinePanel.savedReviews.isToolsPanel)
        XCTAssertEqual(ReplayStore.availablePlaybackRates, [0.25, 0.5, 0.75, 1, 1.5, 2, 4])
    }

    func testAnnotationHistoryStaysReachableAfterEraseClearAndUndoingTheLastMark() throws {
        let source = try immersiveSource()
        let button = try sourceSlice(source,
            after: "private func annotationEditButton(compact: Bool) -> some View",
            before: "private var playbackToolsShelf: some View")
        XCTAssertTrue(button.contains("clearableCoachAnnotationCount == 0 && !store.hasAnnotationEditHistory"))
        XCTAssertTrue(button.contains("store.hasActiveTimelineScrub"))
        let shelf = try sourceSlice(source,
            after: "private var annotationEditShelf: some View",
            before: "private func annotationDurationShelf")
        XCTAssertTrue(shelf.contains("store.annotationUndoTitle"))
        XCTAssertTrue(shelf.contains("store.annotationRedoTitle"))
        XCTAssertTrue(shelf.contains("store.canUndoAnnotationEdit"))
        XCTAssertTrue(shelf.contains("store.canRedoAnnotationEdit"))
        XCTAssertFalse(source.contains("Removes the newest coach-created annotation"))
        let confirmation = try sourceSlice(source,
            after: "private var clearAnnotationsConfirmationStrip: some View",
            before: "private func applyAnnotationHistory")
        XCTAssertTrue(confirmation.contains("inlinePanel = .annotationEdit"))
        XCTAssertTrue(confirmation.contains("Undo can restore your marks"))
    }

    func testAnnotationDurationChoicesUseTheSameBoundsAsTheStore() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        let choice = try String(contentsOf: root.appendingPathComponent(
            "ReplayXI/Immersive/AnnotationTimingEditor.swift"), encoding: .utf8)
        XCTAssertTrue(choice.contains("CoachMarkTimingPolicy.windowFits"))
        XCTAssertTrue(choice.contains(".disabled(!canEdit || !isDirty || draft.validationMessage(duration: duration) != nil)"))
        XCTAssertTrue(choice.contains("store.setCoachMarkWindow"))
        let timeline = try String(contentsOf: root.appendingPathComponent(
            "ReplayXI/Immersive/SpatialAnnotationTimeline.swift"), encoding: .utf8)
        XCTAssertTrue(timeline.contains("SpatialAnnotationTimelineMath.movedStart(mark: edit.mark"))
        XCTAssertTrue(timeline.contains("store.retimeCoachMark(id: edit.mark.id, to: start)"))
        let projectRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
        let movePolicy = try String(contentsOf: projectRoot.appendingPathComponent(
            "ReplayXI/Immersive/PlaybackAnnotationMovePolicy.swift"), encoding: .utf8)
        XCTAssertTrue(movePolicy.contains("CoachMarkTimingPolicy.windowFits"))
    }

    func testSelectedCoachMarkExposesRetractableEndpointLinksWithFreezeGate() throws {
        let source = try immersiveSource()
        let inspector = try sourceSlice(
            source,
            after: "private func selectedAnnotationInspector(_ mark: CoachMark) -> some View",
            before: "private func nudgeAnnotation("
        )
        XCTAssertTrue(inspector.contains("SpatialAnnotationEditor(mark: mark"))

        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        let editor = try String(contentsOf: root.appendingPathComponent(
            "ReplayXI/Immersive/SpatialAnnotationEditor.swift"), encoding: .utf8)
        let header = try sourceSlice(editor, after: "private var header: some View",
            before: "private func endpointButton(")
        XCTAssertTrue(header.contains("endpointButton(.start)"))
        XCTAssertTrue(header.contains("endpointButton(.end)"))
        XCTAssertTrue(header.contains("if editable, mark.kind.requiresTwoPitchPoints"))

        let endpoint = try sourceSlice(editor, after: "private func endpointButton(",
            before: "private func playerLinks(")
        XCTAssertTrue(endpoint.contains("linking = linking == endpoint ? nil : endpoint"))
        XCTAssertTrue(endpoint.contains(".accessibilityLabel(\"Link "))
        XCTAssertTrue(endpoint.contains(".frame(minWidth: 44, minHeight: 44)"))

        let links = try sourceSlice(editor, after: "private func playerLinks(",
            before: "private func action(")
        XCTAssertTrue(links.contains("if mark.hasKeyframes"))
        XCTAssertTrue(links.contains("Button(\"Freeze here\")"))
        XCTAssertTrue(links.contains("store.freezeCoachMarkKeyframes(id: mark.id)"))
        XCTAssertTrue(links.contains("Freeze the current pose before linking"))
        XCTAssertTrue(links.contains("ForEach(store.selectedScenario.players) { player in"))
        XCTAssertTrue(links.contains("store.setCoachMarkEndpointTracking(id: mark.id, endpoint: endpoint,"))
        XCTAssertTrue(links.contains("playerID: player.id"))
        XCTAssertTrue(links.contains("playerID: nil"), "Pitch-fixed must remain available.")
        XCTAssertTrue(links.contains("linking = nil"), "Choosing a player or pitch must retract the picker.")
    }

    private func immersiveSource() throws -> String {
        let projectRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let sourceURL = projectRoot
            .appendingPathComponent("ReplayXI")
            .appendingPathComponent("Immersive")
            .appendingPathComponent("FootballImmersiveView.swift")
        let hudURL = projectRoot.appendingPathComponent("ReplayXI/Immersive/PlaybackViewOverlayHUD.swift")
        return try String(contentsOf: sourceURL, encoding: .utf8)
            + String(contentsOf: hudURL, encoding: .utf8)
    }

    private func sourceSlice(
        _ source: String,
        after startMarker: String,
        before endMarker: String
    ) throws -> String {
        let start = try XCTUnwrap(source.range(of: startMarker)?.upperBound)
        let end = try XCTUnwrap(source.range(of: endMarker, range: start..<source.endIndex)?.lowerBound)
        return String(source[start..<end])
    }
}
