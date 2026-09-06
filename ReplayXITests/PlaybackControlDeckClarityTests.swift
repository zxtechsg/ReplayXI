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
        XCTAssertTrue(transition.contains("draggedAnnotationTarget = nil"))
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
        XCTAssertTrue(source.contains("Eyebrow(text: \"View & Overlays\""))
    }

    func testSelectedCoachMarkExposesClearRetractableTwentyTwoPlayerTracking() throws {
        let source = try immersiveSource()
        let inspector = try sourceSlice(
            source,
            after: "private func selectedAnnotationInspector(_ mark: CoachMark) -> some View",
            before: "private func annotationGeometryButton(_ mark: CoachMark) -> some View"
        )
        XCTAssertTrue(inspector.contains("annotationTrackingButton(mark)"))

        let trackingButton = try sourceSlice(
            source,
            after: "private func annotationTrackingButton(_ mark: CoachMark) -> some View",
            before: "private func annotationTrackingButtonTitle(_ mark: CoachMark) -> String"
        )
        XCTAssertTrue(trackingButton.contains("toggleInlinePanel(.annotationTracking(mark.id))"))
        XCTAssertTrue(trackingButton.contains("Annotation player tracking"))

        let trackingShelf = try sourceSlice(
            source,
            after: "private func annotationTrackingShelf(_ mark: CoachMark) -> some View",
            before: "private func annotationTrackingTeamRow("
        )
        XCTAssertTrue(trackingShelf.contains("title: \"Follow player\""))
        XCTAssertTrue(trackingShelf.contains("detail: \"START + END\""))
        XCTAssertTrue(trackingShelf.contains("Label(\"Pitch\""))
        XCTAssertTrue(trackingShelf.contains("store.selectedScenario.homePlayers"))
        XCTAssertTrue(trackingShelf.contains("store.selectedScenario.awayPlayers"))

        let trackingRow = try sourceSlice(
            source,
            after: "private func annotationTrackingTeamRow(\n",
            before: "private func annotationTrackingPlayerButton("
        )
        XCTAssertTrue(trackingRow.contains("ForEach(players.prefix(11))"))

        let trackingMutation = try sourceSlice(
            source,
            after: "private func setAnnotationTracking(_ mark: CoachMark, playerID: String?)",
            before: "private func annotationLabelShelf(_ mark: CoachMark) -> some View"
        )
        XCTAssertTrue(
            trackingMutation.contains(
                "store.setCoachMarkTracking(id: mark.id, playerID: playerID)"
            )
        )
        XCTAssertTrue(trackingMutation.contains("inlinePanel = nil"))
    }

    private func immersiveSource() throws -> String {
        let projectRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let sourceURL = projectRoot
            .appendingPathComponent("ReplayXI")
            .appendingPathComponent("Immersive")
            .appendingPathComponent("FootballImmersiveView.swift")
        return try String(contentsOf: sourceURL, encoding: .utf8)
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
