import RealityKit
import UIKit

/// App-owned grab bars styled as simple white capsules, with generous hit boxes.
@MainActor
enum PlaybackWorkspaceGrabHandle {
    static let name = "playback-workspace-grab-handle"
    static let size = SIMD3<Float>(0.22, 0.065, 0.025)
    struct Target: Component { let panelID: String }
    struct Offset: Component { var value: SIMD3<Float> }
    private struct Presentation: Component, Equatable {
        let isAvailable: Bool
        let isMoving: Bool
    }

    static func make(panelID: String = "coach-console") -> Entity {
        let handle = ModelEntity(
            mesh: .generateBox(size: [0.16, 0.008, 0.006], cornerRadius: 0.003),
            materials: [UnlitMaterial(color: .white)])
        handle.name = panelID == "coach-console" ? name : name + "-" + panelID
        handle.components.set(Target(panelID: panelID))
        handle.components.set(CollisionComponent(shapes: [.generateBox(size: size)]))
        handle.components.set(InputTargetComponent())
        handle.components.set(ReplayHoverAffordance.highlight)
        update(handle, isAvailable: true, isMoving: false)
        return handle
    }

    static func ancestor(of entity: Entity) -> Entity? {
        var current: Entity? = entity
        while let candidate = current {
            if candidate.components[Target.self] != nil { return candidate }
            current = candidate.parent
        }
        return nil
    }

    static func update(_ handle: Entity, isAvailable: Bool, isMoving: Bool) {
        let presentation = Presentation(isAvailable: isAvailable, isMoving: isMoving)
        guard handle.components[Presentation.self] != presentation else { return }
        handle.components.set(presentation)
        var input = handle.components[InputTargetComponent.self] ?? InputTargetComponent()
        input.isEnabled = isAvailable
        handle.components.set(input)
        handle.components.set(OpacityComponent(opacity: isAvailable ? 1 : 0.30))
        var accessibility = AccessibilityComponent()
        accessibility.isAccessibilityElement = true
        accessibility.label = "Move panel"
        accessibility.value = isAvailable
            ? "Pinch the white bar and drag. Moving closer keeps the same panel size."
            : "Finish the current edit first."
        handle.components.set(accessibility)
    }

    static func position(for layout: PlaybackControlDeckLayout) -> SIMD3<Float> {
        [0, layout.verticalOffset - 0.20, layout.forwardOffset]
    }
}
