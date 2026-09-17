import RealityKit

/// One room-space workspace, separate from all replay/player transforms.
/// `.once` samples the initial wearer pose; it never follows subsequent head motion.
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

    /// Only an explicit user request changes the workspace origin. No frame loop,
    /// player selection, save restore or view switch is allowed to recapture it.
    static func needsRecenter(_ anchor: AnchorEntity, revision: Int) -> Bool {
        anchor.components[Revision.self]?.value != revision
    }

    static func recenteredAnchor(from previous: AnchorEntity, revision: Int) -> AnchorEntity {
        let replacement = makeAnchor(revision: revision)
        for child in Array(previous.children) {
            replacement.addChild(child, preservingWorldTransform: false)
        }
        return replacement
    }

    static func canRecenter(isDrawing: Bool, isScrubbing: Bool, isEditingGeometry: Bool) -> Bool {
        !isDrawing && !isScrubbing && !isEditingGeometry
    }
}
