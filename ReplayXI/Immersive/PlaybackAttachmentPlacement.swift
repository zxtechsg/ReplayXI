import RealityKit

/// Translation follows the wearer; orientation is captured only on recenter.
/// Headset location is the body-position proxy. We never consume eye gaze.
enum PlaybackAttachmentPlacement {
    static let anchorName = "playback-controls-room-anchor"
    static let contentRootName = "playback-controls-movable-workspace"
    static let attachmentIDs = [
        "room-header", "coach-console", "playback-view-hud",
        "perspective-matrix", "position-status",
    ]

    struct Revision: Component {
        var value: Int
    }

    struct FollowOrigin: Component {
        let position: SIMD3<Float>
    }

    static func makeAnchor(revision: Int) -> AnchorEntity {
        let anchor = AnchorEntity(.head, trackingMode: .once)
        anchor.name = anchorName
        anchor.components.set(Revision(value: revision))
        return anchor
    }

    static func contentRoot(in anchor: AnchorEntity) -> Entity {
        if let existing = anchor.children.first(where: { $0.name == contentRootName }) {
            return existing
        }
        let root = Entity()
        root.name = contentRootName
        anchor.addChild(root)
        return root
    }

    /// Keep the captured orientation: turning the head must not turn panels.
    static func faceViewer(_ surface: Entity) {
        surface.components.remove(BillboardComponent.self)
    }

    static func followPosition(in anchor: AnchorEntity, viewer: simd_float4x4) {
        guard let horizontal = ReplayReviewPlacement.horizontalViewer(viewer) else { return }
        let worldPosition = SIMD3<Float>(viewer.columns.3.x, viewer.columns.3.y, viewer.columns.3.z)
        let position = anchor.convert(position: worldPosition, from: nil)
        let root = contentRoot(in: anchor)
        if anchor.components[FollowOrigin.self] == nil {
            anchor.components.set(FollowOrigin(position: position))
            let heading = Transform(matrix: horizontal).rotation
            root.orientation = anchor.orientation(relativeTo: nil).inverse * heading
        }
        guard let origin = anchor.components[FollowOrigin.self] else { return }
        let delta = position - origin.position
        if simd_distance_squared(root.position, delta) > 0.000_001 { root.position = delta }
    }

    /// A user recenter or teleport changes the revision once. Ordinary head
    /// motion and replay ticks never recapture this room-fixed anchor.
    static func needsRecenter(_ anchor: AnchorEntity, revision: Int) -> Bool {
        anchor.components[Revision.self]?.value != revision
    }

    static func recenteredAnchor(from previous: AnchorEntity, revision: Int) -> AnchorEntity {
        let replacement = makeAnchor(revision: revision)
        for child in Array(previous.children) {
            if child.name == contentRootName {
                child.position = .zero
                child.orientation = simd_quatf(angle: 0, axis: [0, 1, 0])
            }
            replacement.addChild(child, preservingWorldTransform: false)
        }
        return replacement
    }

    static func canRecenter(isDrawing: Bool, isScrubbing: Bool, isEditingGeometry: Bool) -> Bool {
        !isDrawing && !isScrubbing && !isEditingGeometry
    }
}
