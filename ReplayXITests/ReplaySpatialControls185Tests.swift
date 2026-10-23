import RealityKit
import XCTest
@testable import ReplayXI

@MainActor
final class ReplaySpatialControls185Tests: XCTestCase {
    func testPanelsFollowTranslationWithoutFollowingHeadRotation() throws {
        let anchor = PlaybackAttachmentPlacement.makeAnchor(revision: 0)
        let root = PlaybackAttachmentPlacement.contentRoot(in: anchor)
        PlaybackAttachmentPlacement.followPosition(in: anchor,
            viewer: Transform(translation: [1, 1.6, 2]).matrix)
        let initialRotation = root.orientation
        PlaybackAttachmentPlacement.followPosition(in: anchor,
            viewer: Transform(rotation: .init(angle: .pi / 2, axis: [0, 1, 0]),
                              translation: [1.4, 1.6, 2.5]).matrix)
        XCTAssertEqual(root.position.x, 0.4, accuracy: 0.0001)
        XCTAssertEqual(root.position.z, 0.5, accuracy: 0.0001)
        XCTAssertEqual(root.orientation, initialRotation)
        let before = root.transform
        var invalid = matrix_identity_float4x4
        invalid.columns.3.x = .nan
        PlaybackAttachmentPlacement.followPosition(in: anchor, viewer: invalid)
        XCTAssertEqual(root.transform, before)
    }

    func testPullingBothHandsCloserDoesNotShrinkPitch() {
        var placement = ReplayWorldPlacement()
        placement.update(left: [-0.2, 1, -1], right: [0.2, 1, -1], allowed: true)
        placement.update(left: [-0.2, 1, -0.5], right: [0.2, 1, -0.5], allowed: true)
        XCTAssertEqual(placement.scale, 1, accuracy: 0.0001)
        XCTAssertEqual(placement.offset.z, 0.5, accuracy: 0.0001)
        placement.update(left: [-0.4, 1, -0.5], right: [0.4, 1, -0.5], allowed: true)
        XCTAssertEqual(placement.scale, 2, accuracy: 0.0001)
        XCTAssertEqual(placement.offset.z, 0.5, accuracy: 0.0001)
    }

    func testSeparateBarsAndRejectedDragCannotRestartUntilRelease() throws {
        let console = PlaybackWorkspaceGrabHandle.make(panelID: "coach-console")
        let view = PlaybackWorkspaceGrabHandle.make(panelID: "playback-view-hud")
        XCTAssertEqual(console.components[PlaybackWorkspaceGrabHandle.Target.self]?.panelID, "coach-console")
        XCTAssertEqual(view.components[PlaybackWorkspaceGrabHandle.Target.self]?.panelID, "playback-view-hud")
        XCTAssertNotNil(console.components[ModelComponent.self])
        XCTAssertNil(console.components[BillboardComponent.self])
        XCTAssertNotNil(console.components[CollisionComponent.self])
        var move = PlaybackWorkspaceMove()
        let room = UUID()
        move.prepare(at: [0.2, 0, 0.1])
        XCTAssertTrue(move.preview(roomID: room, cumulativeTranslation: [0, 0, 0.2], isAllowed: true))
        move.cancel(rejectCurrentGesture: true)
        move.prepare(at: .zero)
        XCTAssertFalse(move.preview(roomID: room, cumulativeTranslation: [0, 0, 0.2], isAllowed: true))
        XCTAssertEqual(move.offset, [0.2, 0, 0.1])
        move.cancel()
        move.prepare(at: .zero)
        XCTAssertTrue(move.preview(roomID: room, cumulativeTranslation: [0, 0, 0.2], isAllowed: true))
    }

    func testPitchButtonsSeparateSizeAndDistanceAndRespectActiveGesture() {
        var placement = ReplayWorldPlacement()
        placement.resize(by: 1.5)
        placement.move(by: [0, 0, 0.3])
        XCTAssertEqual(placement.scale, 1.5)
        XCTAssertEqual(placement.offset.z, 0.3)
        placement.update(left: [-0.2, 1, -1], right: [0.2, 1, -1], allowed: true)
        let active = placement
        placement.resize(by: 0.5)
        placement.move(by: [0, 0, -0.3])
        XCTAssertEqual(placement, active)
        placement.update(left: nil, right: nil, allowed: false)
        placement.resize(by: .infinity)
        placement.move(by: [.nan, 0, 0])
        XCTAssertEqual(placement.scale, 1.5)
        XCTAssertEqual(placement.offset.z, 0.3)
    }

    func testInvisibleTargetsAndVisibleModelsShareHoverWithoutExtraCollisions() throws {
        let root = Entity()
        let target = Entity()
        target.components.set(InputTargetComponent())
        target.components.set(CollisionComponent(shapes: [.generateSphere(radius: 1)]))
        let visual = ModelEntity(mesh: .generateSphere(radius: 0.5), materials: [UnlitMaterial(color: .white)])
        root.addChild(target); root.addChild(visual)
        let group = ReplayHoverAffordance.install(on: root)
        XCTAssertEqual(target.components[HoverEffectComponent.self]?.hoverEffect.groupID, group)
        XCTAssertEqual(visual.components[HoverEffectComponent.self]?.hoverEffect.groupID, group)
        XCTAssertNil(visual.components[CollisionComponent.self])
        let lateLOD = ModelEntity(mesh: .generateSphere(radius: 0.4))
        ReplayHoverAffordance.install(on: lateLOD, using: group)
        XCTAssertEqual(lateLOD.components[HoverEffectComponent.self]?.hoverEffect.groupID, group)
        XCTAssertNotEqual(ReplayHoverAffordance.install(on: Entity()), group)
    }
}
