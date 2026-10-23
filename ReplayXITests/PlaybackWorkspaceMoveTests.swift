import RealityKit
import XCTest
@testable import ReplayXI

@MainActor
final class PlaybackWorkspaceMoveTests: XCTestCase {
    func testCumulativeDragDoesNotAccumulateFeedbackAndCommitKeepsPlacement() {
        var move = PlaybackWorkspaceMove()
        let room = UUID()
        XCTAssertTrue(move.preview(roomID: room, cumulativeTranslation: [0.2, 0.1, -0.1], isAllowed: true))
        XCTAssertTrue(move.preview(roomID: room, cumulativeTranslation: [0.3, 0.2, -0.2], isAllowed: true))
        XCTAssertEqual(move.offset, [0.3, 0.2, -0.2])
        XCTAssertTrue(move.commit(roomID: room))
        XCTAssertFalse(move.isActive)
        XCTAssertEqual(move.offset, [0.3, 0.2, -0.2])
        XCTAssertTrue(move.preview(roomID: room, cumulativeTranslation: [0.1, 0, 0], isAllowed: true))
        XCTAssertEqual(move.offset.x, 0.4, accuracy: 0.000_001)
        move.cancel()
        XCTAssertEqual(move.offset, [0.3, 0.2, -0.2])
    }

    func testPlacementHasFiniteReachableBoundsAtEveryPreset() {
        XCTAssertEqual(PlaybackWorkspaceMove.clamped([99, 99, 99]), [1.2, 0.75, 0.4])
        XCTAssertEqual(PlaybackWorkspaceMove.clamped([-99, -99, -99]), [-1.2, -0.75, -1])
        for preset in PlaybackControlDeckPreset.allCases {
            for accessibility in [false, true] {
                let layout = PlaybackControlDeckLayout.resolve(preset: preset, usesAccessibilityText: accessibility)
                XCTAssertLessThanOrEqual(layout.forwardOffset + 0.4, -0.54 + 0.000_001)
            }
        }
    }

    func testBlockedBeginCannotJoinHalfwayThroughTheSamePinch() {
        var move = PlaybackWorkspaceMove()
        let room = UUID()
        XCTAssertFalse(move.preview(roomID: room, cumulativeTranslation: [0.2, 0, 0], isAllowed: false))
        XCTAssertFalse(move.preview(roomID: room, cumulativeTranslation: [0.4, 0, 0], isAllowed: true))
        XCTAssertEqual(move.offset, .zero)
        XCTAssertFalse(move.isActive)
        move.cancel() // End/cancel releases the rejected physical gesture.
        XCTAssertTrue(move.preview(roomID: room, cumulativeTranslation: [0.1, 0, 0], isAllowed: true))
    }

    func testNewEditOwnershipRollsBackAnActiveMoveUntilPinchEnds() {
        var move = PlaybackWorkspaceMove()
        let room = UUID()
        XCTAssertTrue(move.preview(roomID: room, cumulativeTranslation: [0.1, 0, 0], isAllowed: true))
        XCTAssertTrue(move.commit(roomID: room))
        XCTAssertTrue(move.preview(roomID: room, cumulativeTranslation: [0.5, 0, 0], isAllowed: true))
        XCTAssertFalse(move.preview(roomID: room, cumulativeTranslation: [0.6, 0, 0], isAllowed: false))
        XCTAssertEqual(move.offset, [0.1, 0, 0])
        XCTAssertFalse(move.isActive)
        XCTAssertFalse(move.preview(roomID: room, cumulativeTranslation: [0.7, 0, 0], isAllowed: true))
        move.cancel()
        XCTAssertTrue(move.preview(roomID: room, cumulativeTranslation: [0.1, 0, 0], isAllowed: true))
    }

    func testInvalidInputRollsBackWithoutPoisoningCommittedPlacement() {
        for invalid in [SIMD3<Float>(Float.nan, 0, 0), SIMD3<Float>(0, Float.infinity, 0), SIMD3<Float>(0, 0, -Float.infinity)] {
            var move = PlaybackWorkspaceMove()
            let room = UUID()
            XCTAssertTrue(move.preview(roomID: room, cumulativeTranslation: [0.2, 0, 0], isAllowed: true))
            XCTAssertTrue(move.commit(roomID: room))
            XCTAssertTrue(move.preview(roomID: room, cumulativeTranslation: [0.3, 0, 0], isAllowed: true))
            XCTAssertFalse(move.preview(roomID: room, cumulativeTranslation: invalid, isAllowed: true))
            XCTAssertEqual(move.offset, [0.2, 0, 0])
            XCTAssertFalse(move.commit(roomID: room))
        }
    }

    func testWrongRoomCannotPreviewCancelOrCommitTheCurrentMove() {
        var move = PlaybackWorkspaceMove()
        let room = UUID()
        XCTAssertTrue(move.preview(roomID: room, cumulativeTranslation: [0.2, 0, 0], isAllowed: true))
        let before = move
        XCTAssertFalse(move.preview(roomID: UUID(), cumulativeTranslation: .zero, isAllowed: false))
        XCTAssertFalse(move.commit(roomID: UUID()))
        XCTAssertEqual(move, before)
    }

    func testMovingWorkspaceLeavesTheRoomAnchorPitchAndPanelLayoutUntouched() {
        let anchor = PlaybackAttachmentPlacement.makeAnchor(revision: 0)
        let workspace = PlaybackAttachmentPlacement.contentRoot(in: anchor)
        XCTAssertTrue(PlaybackAttachmentPlacement.contentRoot(in: anchor) === workspace)
        let console = Entity()
        console.position = [0, -0.5, -1.2]
        workspace.addChild(console)
        let pitch = Entity()
        pitch.position = [0, -1, -3]
        let originalPitch = pitch.transform
        let originalPanel = console.transform
        let originalAnchor = anchor.transform
        var move = PlaybackWorkspaceMove()
        let room = UUID()
        XCTAssertTrue(move.preview(roomID: room, cumulativeTranslation: [0.4, 0.1, -0.2], isAllowed: true))
        workspace.position = move.offset
        let placed = console.position(relativeTo: anchor)
        XCTAssertEqual(placed.x, 0.4, accuracy: 0.000_001)
        XCTAssertEqual(placed.y, -0.4, accuracy: 0.000_001)
        XCTAssertEqual(placed.z, -1.4, accuracy: 0.000_001)
        XCTAssertEqual(console.transform, originalPanel)
        XCTAssertEqual(anchor.transform, originalAnchor)
        XCTAssertEqual(anchor.anchoring.trackingMode, .once)
        XCTAssertEqual(pitch.transform, originalPitch)
        move.cancel()
        workspace.position = move.offset
        XCTAssertEqual(workspace.position, .zero)
    }

    func testRecenterResetsMoveButRetainsTheSameWorkspaceAndPanels() {
        let original = PlaybackAttachmentPlacement.makeAnchor(revision: 0)
        let workspace = PlaybackAttachmentPlacement.contentRoot(in: original)
        let panel = Entity()
        workspace.addChild(panel)
        var move = PlaybackWorkspaceMove()
        let room = UUID()
        XCTAssertTrue(move.preview(roomID: room, cumulativeTranslation: [0.3, 0.2, 0.1], isAllowed: true))
        XCTAssertTrue(move.commit(roomID: room))
        workspace.position = move.offset
        move.reset()
        let recentered = PlaybackAttachmentPlacement.recenteredAnchor(from: original, revision: 1)
        workspace.position = move.offset
        XCTAssertTrue(PlaybackAttachmentPlacement.contentRoot(in: recentered) === workspace)
        XCTAssertTrue(panel.parent === workspace)
        XCTAssertEqual(workspace.position, .zero)
        XCTAssertEqual(recentered.anchoring.trackingMode, .once)
    }

    func testGrabTargetIsVisibleAccessibleAndSeparateFromTheConsoleAtEverySize() throws {
        let handle = PlaybackWorkspaceGrabHandle.make()
        XCTAssertNotNil(handle.components[CollisionComponent.self])
        XCTAssertTrue(try XCTUnwrap(handle.components[InputTargetComponent.self]).isEnabled)
        XCTAssertTrue(try XCTUnwrap(handle.components[AccessibilityComponent.self]).isAccessibilityElement)
        XCTAssertNotNil(handle.components[ModelComponent.self])
        XCTAssertTrue(handle.children.isEmpty)
        let child = Entity()
        handle.addChild(child)
        XCTAssertTrue(PlaybackWorkspaceGrabHandle.ancestor(of: child) === handle)
        for preset in PlaybackControlDeckPreset.allCases {
            for accessibility in [false, true] {
                let layout = PlaybackControlDeckLayout.resolve(preset: preset, usesAccessibilityText: accessibility)
                let position = PlaybackWorkspaceGrabHandle.position(for: layout)
                XCTAssertEqual(position.x, 0)
                XCTAssertLessThan(position.y, layout.verticalOffset)
                XCTAssertEqual(position.z, layout.forwardOffset)
            }
        }
        PlaybackWorkspaceGrabHandle.update(handle, isAvailable: false, isMoving: false)
        XCTAssertFalse(try XCTUnwrap(handle.components[InputTargetComponent.self]).isEnabled)
        XCTAssertEqual(try XCTUnwrap(handle.components[OpacityComponent.self]).opacity, 0.30)
        PlaybackWorkspaceGrabHandle.update(handle, isAvailable: true, isMoving: true)
        XCTAssertTrue(try XCTUnwrap(handle.components[InputTargetComponent.self]).isEnabled)
    }

    func testSpatialMoveRoutesBeforeAnnotationAndLocksOnlyAttachmentInput() throws {
        let source = try immersiveSource()
        let gesture = try slice(source, after: "private var spatialInteractionGesture:",
                                before: "private func handleSpatialTap(")
        let route = try XCTUnwrap(gesture.range(of: "if handleWorkspaceDragChanged(value) { return }")?.lowerBound)
        let annotation = try XCTUnwrap(gesture.range(of: "handleAnnotationDragChanged(value)")?.lowerBound)
        XCTAssertLessThan(route, annotation)
        XCTAssertTrue(gesture.contains("guard !workspaceMove.isActive else { return }"))
        let attachments = try slice(source, after: "} attachments: {", before: ".gesture(spatialInteractionGesture)")
        XCTAssertEqual(attachments.components(separatedBy: ".disabled(workspaceMove.isActive)").count - 1, 5)
        XCTAssertEqual(attachments.components(separatedBy: ".allowsHitTesting(!workspaceMove.isActive)").count - 1, 5)
        let move = try slice(source, after: "private var canMoveWorkspace:", before: "private func matchRootAncestor(")
        XCTAssertTrue(move.contains("isDrawing: store.isDrawing || annotationStroke != nil"))
        XCTAssertTrue(move.contains("isScrubbing: store.hasActiveTimelineScrub"))
        XCTAssertTrue(move.contains("isEditingGeometry: store.hasActiveCoachMarkGeometryPreview"))
        XCTAssertTrue(move.contains("value.convert(value.translation3D, from: .local, to: workspace)"))
        XCTAssertFalse(move.contains("store.seek"))
        XCTAssertFalse(move.contains("store.setViewMode"))
        XCTAssertTrue(source.contains(".onChange(of: canMoveWorkspace)"))
        XCTAssertTrue(source.contains("cancelWorkspaceMove(rejectCurrentGesture: true)"))
    }

    private func immersiveSource() throws -> String {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        return try String(contentsOf: root.appendingPathComponent(
            "ReplayXI/Immersive/FootballImmersiveView.swift"), encoding: .utf8)
    }

    private func slice(_ source: String, after start: String, before end: String) throws -> String {
        let lower = try XCTUnwrap(source.range(of: start)?.upperBound)
        let upper = try XCTUnwrap(source.range(of: end, range: lower..<source.endIndex)?.lowerBound)
        return String(source[lower..<upper])
    }
}
