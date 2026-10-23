import RealityKit
import XCTest
@testable import ReplayXI

@MainActor
final class PlaybackViewerFacing180Tests: XCTestCase {
    func testCardsKeepFixedHeadingWithoutMovingOriginOrNeighbours() throws {
        let anchor = PlaybackAttachmentPlacement.makeAnchor(revision: 7)
        let workspace = PlaybackAttachmentPlacement.contentRoot(in: anchor)
        workspace.position = [0.3, 0.1, 0.2]
        let origin = anchor.transform
        let placement = workspace.transform
        for id in PlaybackAttachmentPlacement.attachmentIDs {
            let card = Entity()
            card.name = id
            card.position = [0.5, -0.4, -1.2]
            card.scale = [1.1, 1.1, 1.1]
            workspace.addChild(card)
            let transform = card.transform

            PlaybackAttachmentPlacement.faceViewer(card)

            XCTAssertNil(card.components[BillboardComponent.self])
            XCTAssertEqual(card.transform, transform)
            XCTAssertTrue(card.parent === workspace)
        }
        XCTAssertEqual(anchor.transform, origin)
        XCTAssertEqual(workspace.transform, placement)
        XCTAssertEqual(anchor.anchoring.trackingMode, .once)
        XCTAssertNil(anchor.components[BillboardComponent.self])
        XCTAssertNil(workspace.components[BillboardComponent.self])
        XCTAssertFalse(PlaybackAttachmentPlacement.needsRecenter(anchor, revision: 7))
    }

    func testMountingAnExistingCardRemovesHeadFacingBehavior() {
        let card = Entity()
        card.components.set(BillboardComponent())
        PlaybackAttachmentPlacement.faceViewer(card)
        XCTAssertNil(card.components[BillboardComponent.self])
    }

    func testMoveHandleRemainsInteractiveWithoutHeadFacingWhenAvailabilityChanges() throws {
        let handle = PlaybackWorkspaceGrabHandle.make()
        XCTAssertNil(handle.components[BillboardComponent.self])
        XCTAssertNotNil(handle.components[CollisionComponent.self])
        XCTAssertNotNil(handle.components[HoverEffectComponent.self])
        for available in [false, true] {
            PlaybackWorkspaceGrabHandle.update(handle, isAvailable: available, isMoving: false)
            XCTAssertNil(handle.components[BillboardComponent.self])
            XCTAssertEqual(try XCTUnwrap(handle.components[InputTargetComponent.self]).isEnabled, available)
        }
    }

    func testFixedHeadingCardsRetainPullPushCommitCancelAndRecenter() throws {
        let anchor = PlaybackAttachmentPlacement.makeAnchor(revision: 0)
        let workspace = PlaybackAttachmentPlacement.contentRoot(in: anchor)
        let card = Entity()
        card.name = "coach-console"
        card.position = [0, -0.5, -1.2]
        workspace.addChild(card)
        PlaybackAttachmentPlacement.faceViewer(card)
        let room = UUID()
        var move = PlaybackWorkspaceMove()
        XCTAssertTrue(move.preview(roomID: room, cumulativeTranslation: [0, 0, 0.3], isAllowed: true))
        workspace.position = move.offset
        XCTAssertEqual(card.position(relativeTo: anchor).z, -0.9, accuracy: 0.000_01)
        XCTAssertTrue(move.commit(roomID: room))
        XCTAssertTrue(move.preview(roomID: room, cumulativeTranslation: [0, 0, -0.6], isAllowed: true))
        move.cancel()
        workspace.position = move.offset
        XCTAssertEqual(card.position(relativeTo: anchor).z, -0.9, accuracy: 0.000_01)

        move.reset()
        let replacement = PlaybackAttachmentPlacement.recenteredAnchor(from: anchor, revision: 1)
        workspace.position = move.offset
        XCTAssertTrue(card.parent === PlaybackAttachmentPlacement.contentRoot(in: replacement))
        XCTAssertNil(card.components[BillboardComponent.self])
        XCTAssertEqual(card.position, [0, -0.5, -1.2])
        XCTAssertNil(replacement.components[BillboardComponent.self])
    }

    func testActualAttachmentMountUsesFacingOnlyOnIndividualCards() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        let source = try String(contentsOf: root.appendingPathComponent(
            "ReplayXI/Immersive/FootballImmersiveView.swift"), encoding: .utf8)
        let start = try XCTUnwrap(source.range(of: "private func addAttachments(")?.lowerBound)
        let end = try XCTUnwrap(source.range(of: "private func updateAttachmentPositions(",
                                             range: start..<source.endIndex)?.lowerBound)
        let mount = source[start..<end]
        XCTAssertTrue(mount.contains("PlaybackAttachmentPlacement.faceViewer(entity)"))
        XCTAssertFalse(mount.contains("faceViewer(workspace)"))
        XCTAssertFalse(mount.contains("faceViewer(controlsAnchor)"))
    }
}
