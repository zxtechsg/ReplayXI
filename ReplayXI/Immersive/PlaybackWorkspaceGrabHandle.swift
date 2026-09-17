import RealityKit
import UIKit

/// A separate spatial target beside the console: it cannot steal a timeline
/// or button pinch, and its bounds do not depend on an open shelf's height.
@MainActor
enum PlaybackWorkspaceGrabHandle {
    static let name = "playback-workspace-grab-handle"
    static let size = SIMD3<Float>(0.108, 0.088, 0.012)

    private struct Presentation: Component, Equatable {
        let isAvailable: Bool
        let isMoving: Bool
    }

    static func make() -> Entity {
        let handle = ModelEntity(
            mesh: .generateBox(size: size, cornerRadius: 0.005),
            materials: [UnlitMaterial(color: UIColor(white: 0.13, alpha: 1))]
        )
        handle.name = name
        handle.components.set(CollisionComponent(shapes: [.generateBox(size: size)]))
        handle.components.set(InputTargetComponent())
        handle.components.set(HoverEffectComponent())

        let text = ModelEntity(
            mesh: .generateText("Move", extrusionDepth: 0.0002,
                font: .systemFont(ofSize: 0.020, weight: .semibold)),
            materials: [UnlitMaterial(color: .white)]
        )
        let bounds = text.visualBounds(relativeTo: text)
        text.position = [-bounds.center.x, -0.022 - bounds.center.y, size.z / 2 + 0.001]
        handle.addChild(text)

        let dotMesh = MeshResource.generateSphere(radius: 0.003)
        let dotMaterial = UnlitMaterial(color: UIColor(white: 0.78, alpha: 1))
        for x in [-Float(0.011), 0, 0.011] {
            for y in [Float(0.010), 0.021] {
                let dot = ModelEntity(mesh: dotMesh, materials: [dotMaterial])
                dot.position = [x, y, size.z / 2 + 0.001]
                handle.addChild(dot)
            }
        }
        update(handle, isAvailable: true, isMoving: false)
        return handle
    }

    static func ancestor(of entity: Entity) -> Entity? {
        var current: Entity? = entity
        while let candidate = current {
            if candidate.name == name { return candidate }
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
        handle.components.set(OpacityComponent(opacity: isAvailable ? 1 : 0.35))
        if var model = handle.components[ModelComponent.self] {
            model.materials = [UnlitMaterial(color: isMoving
                ? UIColor(red: 0.08, green: 0.40, blue: 0.44, alpha: 1)
                : UIColor(white: 0.13, alpha: 1))]
            handle.components.set(model)
        }
        var accessibility = AccessibilityComponent()
        accessibility.isAccessibilityElement = true
        accessibility.label = "Move controls"
        accessibility.value = isAvailable
            ? "Pinch and drag. Controls stay fixed in the room after release."
            : "Finish or cancel the current gesture first."
        handle.components.set(accessibility)
    }

    static func position(for layout: PlaybackControlDeckLayout) -> SIMD3<Float> {
        let halfWidth = Float(layout.attachmentWidth) * 0.001 * layout.uniformScale / 2
        return [halfWidth + 0.075, layout.verticalOffset, layout.forwardOffset]
    }
}
