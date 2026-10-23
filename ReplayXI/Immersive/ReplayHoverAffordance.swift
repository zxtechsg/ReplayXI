import RealityKit
import UIKit

/// Connect invisible hit targets to their visible meshes. The compositor
/// handles gaze; no eye-position polling or per-frame material swaps.
enum ReplayHoverAffordance {
    struct Group: Component {
        let id: HoverEffectComponent.GroupID
    }

    static var highlight: HoverEffectComponent {
        HoverEffectComponent(.highlight(.init(color: .white, strength: 1.5)))
    }

    @discardableResult
    static func install(on root: Entity, using existing: HoverEffectComponent.GroupID? = nil)
        -> HoverEffectComponent.GroupID {
        let group = existing ?? root.components[Group.self]?.id ?? .init()
        root.components.set(Group(id: group))
        var effect = highlight
        effect.hoverEffect.groupID = group
        func visit(_ entity: Entity) {
            if entity.components[ModelComponent.self] != nil
                || entity.components[InputTargetComponent.self] != nil {
                entity.components.set(effect)
            }
            for child in entity.children { visit(child) }
        }
        visit(root)
        return group
    }
}
