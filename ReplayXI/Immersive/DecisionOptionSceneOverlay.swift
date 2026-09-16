import Foundation
import RealityKit
import simd
import UIKit

/// A bounded, pitch-space visualization of the descriptive options shown in
/// `PlaybackDecisionStrip`. Four reusable slots avoid rebuilding scene graphs
/// while a coach scrubs. The lines communicate geometry only: they do not
/// score the player or claim that a highlighted pass is tactically correct.
@MainActor
enum DecisionOptionSceneOverlay {
    static let rootName = "decision-options-root"
    static let optionNamePrefix = "decision-option-"
    static let maximumVisibleOptions = 4
    private static let hitTargetBaseName = "decision-option-hit-target"
    private static let hitTargetNamePrefix = "decision-option-hit-target-"

    private static let railMesh = MeshResource.generateBox(
        size: [0.22, 0.038, 1],
        cornerRadius: 0.085
    )
    private static let coreMesh = MeshResource.generateBox(
        size: [0.065, 0.048, 1],
        cornerRadius: 0.026
    )
    private static let arrowMesh = MeshResource.generateCone(height: 0.58, radius: 0.26)
    private static let targetOuterMesh = MeshResource.generateCylinder(height: 0.032, radius: 0.42)
    private static let targetInnerMesh = MeshResource.generateCylinder(height: 0.038, radius: 0.29)

    private static let darkInsetMaterial = UnlitMaterial(
        color: UIColor(red: 0.012, green: 0.025, blue: 0.022, alpha: 0.88),
        applyPostProcessToneMap: false
    )
    private static let cyanMaterial = UnlitMaterial(
        color: UIColor(red: 0.22, green: 0.91, blue: 0.88, alpha: 0.96),
        applyPostProcessToneMap: false
    )
    private static let orangeMaterial = UnlitMaterial(
        color: UIColor(red: 1.0, green: 0.42, blue: 0.12, alpha: 0.98),
        applyPostProcessToneMap: false
    )
    private static let dangerMaterial = UnlitMaterial(
        color: UIColor(red: 1.0, green: 0.25, blue: 0.34, alpha: 0.94),
        applyPostProcessToneMap: false
    )
    private static let signalMaterial = UnlitMaterial(
        color: UIColor(red: 0.78, green: 0.94, blue: 0.19, alpha: 0.98),
        applyPostProcessToneMap: false
    )

    static func makeRoot() -> Entity {
        let root = Entity()
        root.name = rootName
        root.isEnabled = false
        for index in 0..<maximumVisibleOptions {
            root.addChild(makeSlot(index: index))
        }
        return root
    }

    static func update(
        in matchRoot: Entity,
        snapshot: ReplayDecisionSnapshot?,
        scenario: ReplayScenario,
        viewMode: ReplayViewMode,
        isDrawing: Bool,
        presentedPlayerPoses: [String: PlayerPose]? = nil
    ) {
        guard let root = matchRoot.children.first(where: { $0.name == rootName }) else {
            return
        }
        guard let snapshot,
              snapshot.scenarioID == scenario.id,
              !isDrawing,
              let source = scenario.player(id: snapshot.playerID)
        else {
            root.isEnabled = false
            return
        }

        root.isEnabled = true
        let sourcePoint = presentedPlayerPoses?[source.id]?.position
            ?? source.presentationPose(at: snapshot.time).position
        let scale = visualScale(for: viewMode)
        let visibleOptionCount = min(
            snapshot.passingOptions.count,
            maximumVisibleOptions
        )

        // Slots have immutable insertion order and are never added or removed.
        // Enumerating that live collection avoids allocating a prefix Array on
        // every RealityView update while retaining the hard four-option bound.
        for (index, slot) in root.children.enumerated() {
            guard index < visibleOptionCount,
                  let receiver = scenario.player(
                    id: snapshot.passingOptions[index].receiverID
                  )
            else {
                slot.isEnabled = false
                continue
            }

            let option = snapshot.passingOptions[index]
            let destination = presentedPlayerPoses?[receiver.id]?.position
                ?? receiver.presentationPose(at: snapshot.time).position
            slot.isEnabled = true
            let styleChanged = restyleIfNeeded(slot, option: option)
            updateGeometry(
                slot,
                start: sourcePoint,
                end: destination,
                scale: scale,
                time: snapshot.time
            )
            if let target = slot.children.first(where: {
                $0.name.hasPrefix(hitTargetBaseName)
            }) {
                let expectedNameLength = hitTargetNamePrefix.count
                    + optionNamePrefix.count
                    + receiver.id.count
                let receiverChanged = target.name.count != expectedNameLength
                    || !target.name.hasPrefix(hitTargetNamePrefix)
                    || !target.name.hasSuffix(receiver.id)
                if receiverChanged {
                    target.name = hitTargetNamePrefix + optionNamePrefix + receiver.id
                }
                // Localized accessibility resources are rebuilt only when the
                // semantic receiver/style changes, never merely while scrubbing.
                if receiverChanged || styleChanged {
                    setAccessibility(on: target, player: receiver, option: option)
                }
            }
        }
    }

    /// Lets the shared spatial tap path resolve an option line exactly like a
    /// directly selected player body, without encoding names into mesh order.
    static func playerIDAncestor(of entity: Entity) -> String? {
        var cursor: Entity? = entity
        while let current = cursor {
            if let range = current.name.range(of: optionNamePrefix, options: .backwards) {
                let candidate = String(current.name[range.upperBound...])
                if !candidate.isEmpty { return candidate }
            }
            cursor = current.parent
        }
        return nil
    }

    private static func makeSlot(index: Int) -> Entity {
        let slot = Entity()
        slot.name = "decision-slot-\(index)"

        let hitTarget = Entity()
        hitTarget.name = hitTargetBaseName
        hitTarget.components.set(InputTargetComponent(allowedInputTypes: .all))
        hitTarget.components.set(
            CollisionComponent(
                shapes: [.generateBox(size: [0.90, 0.46, 1])],
                isStatic: false
            )
        )
        hitTarget.components.set(HoverEffectComponent())
        slot.addChild(hitTarget)

        let state = Entity()
        state.name = "decision-style-none"
        slot.addChild(state)

        let rail = ModelEntity(mesh: railMesh, materials: [cyanMaterial])
        rail.name = "decision-option-rail"
        slot.addChild(rail)

        let core = ModelEntity(mesh: coreMesh, materials: [cyanMaterial])
        core.name = "decision-option-core"
        slot.addChild(core)

        let arrow = ModelEntity(mesh: arrowMesh, materials: [cyanMaterial])
        arrow.name = "decision-option-arrow"
        slot.addChild(arrow)

        let targetOuter = ModelEntity(mesh: targetOuterMesh, materials: [cyanMaterial])
        targetOuter.name = "decision-option-target-outer"
        slot.addChild(targetOuter)

        let targetInner = ModelEntity(mesh: targetInnerMesh, materials: [darkInsetMaterial])
        targetInner.name = "decision-option-target-inner"
        slot.addChild(targetInner)
        return slot
    }

    private static func updateGeometry(
        _ slot: Entity,
        start: PitchPoint,
        end: PitchPoint,
        scale: Float,
        time: TimeInterval
    ) {
        let dx = end.x - start.x
        let dz = end.z - start.z
        let length = max(hypot(dx, dz), 0.001)
        let orientation = simd_quatf(angle: atan2(dx, dz), axis: [0, 1, 0])
        let midpoint = SIMD3<Float>((start.x + end.x) / 2, 0.13, (start.z + end.z) / 2)

        if let rail = slot.children.first(where: { $0.name == "decision-option-rail" }) {
            rail.position = midpoint
            rail.orientation = orientation
            rail.scale = [scale, scale, length]
        }
        if let core = slot.children.first(where: { $0.name == "decision-option-core" }) {
            core.position = midpoint + SIMD3<Float>(0, 0.014, 0)
            core.orientation = orientation
            core.scale = [scale, scale, length]
        }

        let direction = SIMD3<Float>(dx, 0, dz)
        if let arrow = slot.children.first(where: { $0.name == "decision-option-arrow" }) {
            arrow.position = [end.x, 0.17, end.z]
            arrow.scale = SIMD3<Float>(repeating: scale)
            arrow.isEnabled = length > 0.05
            if arrow.isEnabled {
                arrow.orientation = simd_quatf(
                    from: SIMD3<Float>(0, 1, 0),
                    to: simd_normalize(direction)
                )
            }
        }

        let pulse = 1 + (sin(Float(time) * 4.2) * 0.055)
        if let target = slot.children.first(where: {
            $0.name == "decision-option-target-outer"
        }) {
            target.position = [end.x, 0.075, end.z]
            target.scale = [scale * pulse, 1, scale * pulse]
        }
        if let target = slot.children.first(where: {
            $0.name == "decision-option-target-inner"
        }) {
            target.position = [end.x, 0.080, end.z]
            target.scale = [scale * pulse, 1, scale * pulse]
        }

        // Transform one cached unit collision box with the lane. This keeps
        // scrubbing allocation-free while retaining a forgiving pinch target.
        if let hitTarget = slot.children.first(where: {
            $0.name.hasPrefix(hitTargetBaseName)
        }) {
            hitTarget.position = midpoint
            hitTarget.orientation = orientation
            hitTarget.scale = [scale, scale, length + 0.60]
        }
    }

    private static func restyleIfNeeded(
        _ slot: Entity,
        option: ReplayPassingLaneOption
    ) -> Bool {
        let styleKey = styleStateName(for: option)
        guard let state = slot.children.first(where: { $0.name.hasPrefix("decision-style-") }),
              state.name != styleKey else { return false }
        state.name = styleKey
        let material = material(for: option)
        for child in slot.children {
            switch child.name {
            case "decision-option-rail",
                 "decision-option-core",
                 "decision-option-arrow",
                 "decision-option-target-outer":
                (child as? ModelEntity)?.model?.materials = [material]
            default:
                continue
            }
        }
        return true
    }

    private static func styleStateName(for option: ReplayPassingLaneOption) -> String {
        if option.isCoachSuggestion { return "decision-style-coach" }
        if option.isReplayedDestination { return "decision-style-played" }
        return switch option.availability {
        case .blocked: "decision-style-blocked"
        case .tight: "decision-style-tight"
        case .clear: "decision-style-clear"
        }
    }

    private static func material(for option: ReplayPassingLaneOption) -> UnlitMaterial {
        if option.isCoachSuggestion { return orangeMaterial }
        if option.isReplayedDestination { return signalMaterial }
        return switch option.availability {
        case .blocked: dangerMaterial
        case .tight: orangeMaterial
        case .clear: cyanMaterial
        }
    }

    private static func visualScale(for mode: ReplayViewMode) -> Float {
        switch mode {
        case .firstPerson: 1
        case .tacticalTable: 3.6
        case .touchline: 1.7
        case .positional: 2.5
        }
    }

    private static func setAccessibility(
        on slot: Entity,
        player: PlayerTrack,
        option: ReplayPassingLaneOption
    ) {
        var accessibility = slot.components[AccessibilityComponent.self] ?? AccessibilityComponent()
        accessibility.isAccessibilityElement = true
        accessibility.label = LocalizedStringResource(
            stringLiteral: "Passing option to number \(player.shirtNumber), \(player.role)"
        )
        let role = option.isCoachSuggestion
            ? "Coach authored"
            : (option.isReplayedDestination ? "Replayed destination" : "Descriptive alternative")
        accessibility.value = LocalizedStringResource(
            stringLiteral: "\(role), \(option.availability.rawValue) lane"
        )
        accessibility.systemActions = [.activate]
        slot.components.set(accessibility)
    }
}
