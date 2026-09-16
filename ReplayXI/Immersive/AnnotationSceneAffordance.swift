import Foundation
import RealityKit
import UIKit

/// The semantic part of an annotation target hit in the RealityKit scene.
///
/// Target names deliberately carry their role and mark identifier. A spatial
/// gesture can therefore recover intent by walking ancestors without relying
/// on fragile child ordering or attaching one-off gesture closures to meshes.
enum AnnotationSceneTargetRole: String, Equatable, Sendable {
    case body
    case start
    case end
    case attachedPlayer
}

struct AnnotationSceneTarget: Equatable, Sendable {
    let markID: UUID
    let role: AnnotationSceneTargetRole
}

/// A single reusable scene overlay for the selected coach mark.
///
/// The overlay owns a bounded number of meshes regardless of annotation count.
/// Only transforms and enabled state change during playback; materials and
/// accessibility metadata are restyled solely when the selection changes.
@MainActor
enum AnnotationSceneAffordance {
    static let selectionRootName = "annotation-selection-root"
    static let bodyTargetName = "annotation-target-body"
    static let labelTargetName = "annotation-target-label"
    static let playerAttachmentName = "annotation-player-attachment"
    static let spaceTargetSegmentCount = 12

    private static let pathRootName = "annotation-selection-path"
    private static let zoneRootName = "annotation-selection-zone"
    private static let attachedRootName = "annotation-selection-attached-player"
    private static let startHandleName = "annotation-selection-start-handle"
    private static let endHandleName = "annotation-selection-end-handle"
    private static let labelOutlineName = "annotation-selection-label-outline"
    private static let stateNamePrefix = "annotation-selection-state-"
    private static let markNamePrefix = "mark-"
    private static let startTargetPrefix = "annotation-target-start-"
    private static let endTargetPrefix = "annotation-target-end-"
    private static let attachedTargetPrefix = "annotation-target-attached-player-"
    private static let spaceBodyTargetPrefix = "annotation-space-body-target-"

    private static let pathBodyTargetShape = ShapeResource.generateBox(
        size: [0.95, 0.38, 1]
    )
    private static let labelBodyTargetShape = ShapeResource.generateBox(
        size: [3.6, 0.72, 0.46]
    )
    private static let spaceBodyTargetShape = ShapeResource.generateBox(
        size: [0.95, 0.34, 1]
    )

    private static let selectionRailMesh = MeshResource.generateBox(
        size: [0.19, 0.038, 1],
        cornerRadius: 0.075
    )
    private static let selectionCoreMesh = MeshResource.generateBox(
        size: [0.052, 0.046, 1],
        cornerRadius: 0.024
    )
    private static let handleOuterMesh = MeshResource.generateCylinder(
        height: 0.055,
        radius: 0.25
    )
    private static let handlePinMesh = MeshResource.generateSphere(radius: 0.072)
    private static let handleStemMesh = MeshResource.generateCylinder(
        height: 1,
        radius: 0.024
    )
    private static let attachmentRingMesh = MeshResource.generateCylinder(
        height: 0.025,
        radius: 0.38
    )
    private static let attachmentRingInsetMesh = MeshResource.generateCylinder(
        height: 0.031,
        radius: 0.26
    )
    private static let attachmentStemMesh = MeshResource.generateCylinder(
        height: 1,
        radius: 0.022
    )
    private static let labelOutlineMesh = MeshResource.generateBox(
        size: [1.30, 0.41, 0.018],
        cornerRadius: 0.105
    )

    static func makeSelectionRoot() -> Entity {
        let root = Entity()
        root.name = selectionRootName
        root.isEnabled = false

        let state = Entity()
        state.name = stateNamePrefix + "none"
        root.addChild(state)

        let path = Entity()
        path.name = pathRootName
        let rail = ModelEntity(
            mesh: selectionRailMesh,
            materials: [selectionGlowMaterial]
        )
        rail.name = "annotation-selection-rail"
        path.addChild(rail)
        let core = ModelEntity(
            mesh: selectionCoreMesh,
            materials: [signalMaterial]
        )
        core.name = "annotation-selection-core"
        core.position.y = 0.014
        path.addChild(core)
        root.addChild(path)

        let zone = ModelEntity(
            mesh: ReplayPitchMeshLibrary.annotationSpaceRing,
            materials: [signalMaterial]
        )
        zone.name = zoneRootName
        root.addChild(zone)

        root.addChild(makeHandle(name: startHandleName, label: "START"))
        root.addChild(makeHandle(name: endHandleName, label: "END"))

        let labelOutline = ModelEntity(
            mesh: labelOutlineMesh,
            materials: [selectionGlowMaterial]
        )
        labelOutline.name = labelOutlineName
        root.addChild(labelOutline)

        let attached = makeAttachedPlayerSelectionRoot()
        attached.name = attachedRootName
        root.addChild(attached)
        return root
    }

    /// Creates a generous invisible body target around the authored geometry.
    /// The visible mark remains unchanged until selected.
    static func makeBodyTarget(for mark: CoachMark) -> Entity {
        let target = Entity()
        target.name = bodyTargetName
        target.components.set(InputTargetComponent(allowedInputTypes: .all))
        target.components.set(HoverEffectComponent())
        switch mark.kind {
        case .playerLabel:
            target.components.set(
                CollisionComponent(shapes: [labelBodyTargetShape], isStatic: false)
            )
        case .run, .pass, .danger:
            target.components.set(
                CollisionComponent(shapes: [pathBodyTargetShape], isStatic: false)
            )
        case .space:
            // A ring should be hittable around its circumference without an
            // invisible filled disc stealing taps from players inside it.
            for index in 0..<spaceTargetSegmentCount {
                let segment = Entity()
                segment.name = spaceBodyTargetPrefix + String(index)
                segment.components.set(InputTargetComponent(allowedInputTypes: .all))
                segment.components.set(
                    CollisionComponent(shapes: [spaceBodyTargetShape], isStatic: false)
                )
                segment.components.set(HoverEffectComponent())
                target.addChild(segment)
            }
        }
        configureBodyTarget(target, for: mark, labelPosition: nil)
        setAccessibility(
            on: target,
            label: "\(mark.kind.title) annotation, \(mark.label)",
            value: "Select annotation"
        )
        return target
    }

    /// Makes the floating annotation card itself a direct target in addition
    /// to the mark geometry beneath it. Coaches can therefore select whichever
    /// representation is easiest to acquire from their current viewpoint.
    @discardableResult
    static func configureLabelTarget(
        _ label: Entity,
        for mark: CoachMark,
        renderedText: String
    ) -> Entity {
        let boardWidth = PlaybackSpatialLabels.annotationBoardWidth(
            in: label, renderedCharacterCount: renderedText.count
        )
        let target = Entity()
        target.name = labelTargetName
        target.components.set(InputTargetComponent(allowedInputTypes: .all))
        target.components.set(
            CollisionComponent(
                shapes: [.generateBox(size: [boardWidth + 0.30, 0.56, 0.20])],
                isStatic: false
            )
        )
        target.components.set(HoverEffectComponent())
        setAccessibility(
            on: target,
            label: "\(mark.kind.title) annotation, \(mark.label)",
            value: "Select annotation"
        )
        label.addChild(target)
        return target
    }

    /// A restrained tether makes a player label visibly belong to the tracked
    /// shirt even while both the replay and label billboard are moving.
    static func makePlayerAttachment() -> Entity {
        let root = Entity()
        root.name = playerAttachmentName

        let outer = ModelEntity(
            mesh: attachmentRingMesh,
            materials: [softSignalMaterial]
        )
        outer.name = "annotation-attachment-ring"
        outer.position.y = 0.032
        root.addChild(outer)

        let inset = ModelEntity(
            mesh: attachmentRingInsetMesh,
            materials: [darkInsetMaterial]
        )
        inset.name = "annotation-attachment-ring-inset"
        inset.position.y = 0.036
        root.addChild(inset)

        let stem = ModelEntity(
            mesh: attachmentStemMesh,
            materials: [softSignalMaterial]
        )
        stem.name = "annotation-attachment-stem"
        root.addChild(stem)
        return root
    }

    static func updatePlayerAttachment(
        _ root: Entity,
        anchor: PitchPoint,
        labelHeight: Float,
        viewMode: ReplayViewMode
    ) {
        root.position = [anchor.x, 0, anchor.z]
        let scale = visualScale(for: viewMode)
        root.children.first { $0.name == "annotation-attachment-ring" }?.scale = [scale, 1, scale]
        root.children.first { $0.name == "annotation-attachment-ring-inset" }?.scale = [scale, 1, scale]
        if let stem = root.children.first(where: { $0.name == "annotation-attachment-stem" }) {
            let height = max(labelHeight - 0.32, 0.25)
            stem.position = [0, height / 2, 0]
            stem.scale = [scale, height, scale]
        }
    }

    static func configureBodyTarget(
        _ target: Entity,
        for mark: CoachMark,
        labelPosition: SIMD3<Float>?
    ) {
        switch mark.kind {
        case .playerLabel:
            target.position = labelPosition ?? [mark.end.x, 2.2, mark.end.z]
            target.orientation = simd_quatf()
            target.scale = SIMD3<Float>(repeating: 1)

        case .space:
            let radius = max(ReplayGeometry.distance(mark.start, mark.end), 1.1)
            let elevation = (mark.resolvedStartElevation + mark.resolvedEndElevation) / 2
            target.position = [mark.start.x, 0.16 + elevation, mark.start.z]
            target.orientation = simd_quatf()
            target.scale = SIMD3<Float>(repeating: 1)
            let visibleArcFraction: Float = 0.74
            let arcLength = (2 * Float.pi * radius / Float(spaceTargetSegmentCount))
                * visibleArcFraction
            for (index, segment) in target.children.enumerated()
                where index < spaceTargetSegmentCount {
                let angle = (Float(index) / Float(spaceTargetSegmentCount)) * 2 * .pi
                segment.position = [sin(angle) * radius, 0, cos(angle) * radius]
                segment.orientation = simd_quatf(
                    angle: angle + (.pi / 2),
                    axis: [0, 1, 0]
                )
                segment.scale = [1, 1, arcLength]
            }

        case .run, .pass, .danger:
            let start = SIMD3<Float>(
                mark.start.x,
                0.17 + mark.resolvedStartElevation,
                mark.start.z
            )
            let end = SIMD3<Float>(
                mark.end.x,
                0.17 + mark.resolvedEndElevation,
                mark.end.z
            )
            let direction = end - start
            let length = max(simd_length(direction), 0.45)
            target.position = (start + end) / 2
            target.orientation = simd_quatf(
                from: SIMD3<Float>(0, 0, 1),
                to: simd_normalize(direction)
            )
            target.scale = [1, 1, length + 0.65]
        }
    }

    static func updateSelection(
        in root: Entity,
        mark: CoachMark?,
        viewMode: ReplayViewMode,
        observer: PitchPoint,
        attachedPlayerPosition: PitchPoint?,
        selectedLabel: Entity?,
        isEditable: Bool,
        time: TimeInterval,
        isDrawing: Bool
    ) {
        guard let selection = root.children.first(where: { $0.name == selectionRootName }) else {
            return
        }
        guard let mark,
              (mark.isVisible(at: time) || isEditable),
              !isDrawing
        else {
            selection.isEnabled = false
            return
        }

        selection.isEnabled = true
        restyleIfNeeded(selection, for: mark)
        let scale = visualScale(for: viewMode)
        let lift = selectionLift(for: viewMode)
        let pulse = 1 + (sin(Float(time) * 4.4) * 0.035)

        let path = selection.children.first { $0.name == pathRootName }
        let zone = selection.children.first { $0.name == zoneRootName }
        let startHandle = selection.children.first { isStartHandleName($0.name) }
        let endHandle = selection.children.first { isEndHandleName($0.name) }
        let attached = selection.children.first { isAttachedTargetName($0.name) }
        if let outline = selection.children.first(where: { $0.name == labelOutlineName }) {
            configureLabelOutline(outline, for: mark, matching: selectedLabel)
        }

        switch mark.kind {
        case .run, .pass, .danger:
            path?.isEnabled = true
            zone?.isEnabled = false
            startHandle?.isEnabled = isEditable
            endHandle?.isEnabled = isEditable
            attached?.isEnabled = false
            if let path {
                setSegmentTransform(
                    path,
                    from: mark.start,
                    to: mark.end,
                    startElevation: mark.resolvedStartElevation,
                    endElevation: mark.resolvedEndElevation,
                    y: lift,
                    crossScale: scale * pulse
                )
            }
            if isEditable {
                configureHandle(
                    startHandle,
                    at: mark.start,
                    observer: observer,
                    scale: scale * pulse,
                    lift: lift,
                    elevation: mark.resolvedStartElevation,
                    viewMode: viewMode
                )
                configureHandle(
                    endHandle,
                    at: mark.end,
                    observer: observer,
                    scale: scale * pulse,
                    lift: lift,
                    elevation: mark.resolvedEndElevation,
                    viewMode: viewMode
                )
            }

        case .space:
            path?.isEnabled = false
            zone?.isEnabled = true
            startHandle?.isEnabled = isEditable
            endHandle?.isEnabled = isEditable
            attached?.isEnabled = false
            let radius = max(ReplayGeometry.distance(mark.start, mark.end), 1.1)
            configureZone(
                zone,
                centre: mark.start,
                radius: radius,
                scale: scale * pulse,
                lift: lift,
                elevation: (mark.resolvedStartElevation + mark.resolvedEndElevation) / 2
            )
            if isEditable {
                configureHandle(
                    startHandle,
                    at: mark.start,
                    observer: observer,
                    scale: scale * pulse,
                    lift: lift,
                    elevation: mark.resolvedStartElevation,
                    viewMode: viewMode
                )
                configureHandle(
                    endHandle,
                    at: mark.end,
                    observer: observer,
                    scale: scale * pulse,
                    lift: lift,
                    elevation: mark.resolvedEndElevation,
                    viewMode: viewMode
                )
            }

        case .playerLabel:
            path?.isEnabled = false
            zone?.isEnabled = false
            startHandle?.isEnabled = false
            endHandle?.isEnabled = false
            attached?.isEnabled = true
            let anchor = attachedPlayerPosition ?? mark.end
            configureAttachedPlayerSelection(
                attached,
                at: anchor,
                observer: observer,
                scale: scale * pulse,
                lift: lift
            )
        }
    }

    /// Resolves the selected mark and semantic target by walking ancestors.
    /// This works for both a mark-owned body target and the shared edit handles.
    static func targetAncestor(of entity: Entity) -> AnnotationSceneTarget? {
        var cursor: Entity? = entity
        var inheritedRole: AnnotationSceneTargetRole?
        while let current = cursor {
            if current.name == bodyTargetName {
                inheritedRole = .body
            }
            if let target = parseDirectTargetName(current.name) {
                return target
            }
            if current.name.hasPrefix(markNamePrefix),
               let id = UUID(uuidString: String(current.name.dropFirst(markNamePrefix.count))) {
                return AnnotationSceneTarget(markID: id, role: inheritedRole ?? .body)
            }
            cursor = current.parent
        }
        return nil
    }

    static func visualScale(for viewMode: ReplayViewMode) -> Float {
        switch viewMode {
        case .firstPerson: 1
        case .tacticalTable: 4.10
        case .touchline: 1.65
        case .positional: 2.45
        }
    }

    /// Floats the edit overlay above boots, shirt-number chips, and the base
    /// annotation. The pitch contact remains explicit through a cached stem.
    static func selectionLift(for viewMode: ReplayViewMode) -> Float {
        switch viewMode {
        case .firstPerson: 0.15
        case .tacticalTable: 0.48
        case .touchline: 0.24
        case .positional: 0.34
        }
    }

    private static func makeHandle(name: String, label: String) -> Entity {
        let root = Entity()
        root.name = name
        root.components.set(InputTargetComponent(allowedInputTypes: .all))
        root.components.set(
            CollisionComponent(
                shapes: [.generateCapsule(height: 0.42, radius: 0.34)],
                isStatic: false
            )
        )
        root.components.set(HoverEffectComponent())

        let outer = ModelEntity(mesh: handleOuterMesh, materials: [selectionGlowMaterial])
        outer.name = "annotation-handle-outer"
        outer.position.y = 0.055
        root.addChild(outer)

        let pin = ModelEntity(mesh: handlePinMesh, materials: [signalMaterial])
        pin.name = "annotation-handle-pin"
        pin.position.y = 0.15
        root.addChild(pin)

        let stem = ModelEntity(mesh: handleStemMesh, materials: [selectionGlowMaterial])
        stem.name = "annotation-handle-stem"
        root.addChild(stem)

        let tag = PlaybackSpatialLabels.makeAnnotationTag(text: label, color: .white)
        tag.name = "annotation-handle-label"
        tag.position = [label == "START" ? -0.25 : 0.25, 0.82, 0]
        tag.scale = SIMD3<Float>(repeating: 0.64)
        tag.children.first { $0.name == "annotation-tag-board" }?.isEnabled = false
        tag.children.first { $0.name == "annotation-tag-accent" }?.isEnabled = false
        root.addChild(tag)
        return root
    }

    private static func makeAttachedPlayerSelectionRoot() -> Entity {
        let root = Entity()
        root.components.set(InputTargetComponent(allowedInputTypes: .all))
        root.components.set(
            CollisionComponent(
                shapes: [.generateCapsule(height: 0.48, radius: 0.48)],
                isStatic: false
            )
        )
        root.components.set(HoverEffectComponent())

        let outer = ModelEntity(mesh: attachmentRingMesh, materials: [selectionGlowMaterial])
        outer.name = "annotation-selection-attached-ring"
        outer.position.y = 0.048
        root.addChild(outer)

        let pin = ModelEntity(mesh: handlePinMesh, materials: [signalMaterial])
        pin.name = "annotation-selection-attached-pin"
        pin.position.y = 0.16
        root.addChild(pin)

        let tag = PlaybackSpatialLabels.makeAnnotationTag(text: "ATTACHED", color: .white)
        tag.name = "annotation-selection-attached-label"
        tag.position.y = 0.82
        tag.scale = SIMD3<Float>(repeating: 0.64)
        tag.children.first { $0.name == "annotation-tag-board" }?.isEnabled = false
        tag.children.first { $0.name == "annotation-tag-accent" }?.isEnabled = false
        root.addChild(tag)
        return root
    }

    private static func configureHandle(
        _ handle: Entity?,
        at point: PitchPoint,
        observer: PitchPoint,
        scale: Float,
        lift: Float,
        elevation: Float,
        viewMode: ReplayViewMode
    ) {
        guard let handle else { return }
        let spatialLift = lift + elevation
        handle.position = [point.x, spatialLift, point.z]
        handle.scale = SIMD3<Float>(repeating: scale)
        if let stem = handle.children.first(where: { $0.name == "annotation-handle-stem" }) {
            let stemHeight = max(spatialLift, 0.04)
            stem.position = [0, -stemHeight / (2 * scale), 0]
            stem.scale = [1, stemHeight / scale, 1]
        }
        if let label = handle.children.first(where: { $0.name == "annotation-handle-label" }) {
            let labelHeight = handleLabelHeight(for: viewMode)
            label.position.y = labelHeight
            label.orientation = simd_quatf(
                angle: atan2(observer.x - point.x, observer.z - point.z),
                axis: [0, 1, 0]
            )
            if let guide = handle.children.first(where: {
                $0.name == "annotation-handle-label-guide"
            }) {
                let guideStart: Float = 0.24
                let guideEnd = max(labelHeight - 0.14, guideStart + 0.04)
                guide.position = [label.position.x, (guideStart + guideEnd) / 2, 0]
                guide.scale = [0.55, guideEnd - guideStart, 0.55]
            }
        }
    }

    private static func handleLabelHeight(for viewMode: ReplayViewMode) -> Float {
        switch viewMode {
        case .firstPerson: 0.82
        case .tacticalTable: 2.12
        case .touchline: 1.18
        case .positional: 1.55
        }
    }

    private static func configureAttachedPlayerSelection(
        _ attached: Entity?,
        at point: PitchPoint,
        observer: PitchPoint,
        scale: Float,
        lift: Float
    ) {
        guard let attached else { return }
        attached.position = [point.x, lift, point.z]
        attached.scale = SIMD3<Float>(repeating: scale)
        if let label = attached.children.first(where: {
            $0.name == "annotation-selection-attached-label"
        }) {
            label.orientation = simd_quatf(
                angle: atan2(observer.x - point.x, observer.z - point.z),
                axis: [0, 1, 0]
            )
        }
    }

    private static func configureZone(
        _ zone: Entity?,
        centre: PitchPoint,
        radius: Float,
        scale: Float,
        lift: Float,
        elevation: Float
    ) {
        guard let zone else { return }
        zone.position = [centre.x, lift + elevation, centre.z]
        zone.scale = [radius * scale, scale, radius * scale]
    }

    private static func configureLabelOutline(
        _ outline: Entity,
        for mark: CoachMark,
        matching label: Entity?
    ) {
        guard let label else {
            outline.isEnabled = false
            return
        }
        outline.isEnabled = true
        // Both boards scale strongly in tabletop mode. A fixed centre offset
        // made their depth slabs overlap (and shimmer) once scaled. Separate
        // their scaled half-depths plus a small physical air gap instead.
        let scaledDepthSeparation = (0.022 * abs(label.scale.z)) + 0.008
        outline.position = label.position + label.orientation.act(
            SIMD3<Float>(0, 0, -scaledDepthSeparation)
        )
        outline.orientation = label.orientation
        let prefixCount: Int = switch mark.kind {
        case .run: 6
        case .pass: 7
        case .danger, .space, .playerLabel: 0
        }
        let renderedCharacterCount = min(mark.label.count + prefixCount, 22)
        let boardWidth = PlaybackSpatialLabels.annotationBoardWidth(
            in: label, renderedCharacterCount: renderedCharacterCount
        )
        outline.scale = [
            label.scale.x * ((boardWidth + 0.14) / 1.30),
            label.scale.y,
            label.scale.z
        ]
    }

    private static func setSegmentTransform(
        _ entity: Entity,
        from start: PitchPoint,
        to end: PitchPoint,
        startElevation: Float,
        endElevation: Float,
        y: Float,
        crossScale: Float
    ) {
        let startPosition = SIMD3<Float>(start.x, y + startElevation, start.z)
        let endPosition = SIMD3<Float>(end.x, y + endElevation, end.z)
        let direction = endPosition - startPosition
        let length = max(simd_length(direction), 0.001)
        entity.position = (startPosition + endPosition) / 2
        entity.scale = [crossScale, crossScale, length]
        entity.orientation = simd_quatf(
            from: SIMD3<Float>(0, 0, 1),
            to: simd_normalize(direction)
        )
    }

    private static func restyleIfNeeded(_ selection: Entity, for mark: CoachMark) {
        let key = "\(mark.id.uuidString)-\(mark.kind.rawValue)"
        guard let state = selection.children.first(where: {
            $0.name.hasPrefix(stateNamePrefix)
        }), state.name != stateNamePrefix + key else { return }
        state.name = stateNamePrefix + key

        let color = color(for: mark.kind)
        let coreMaterial = UnlitMaterial(color: color, applyPostProcessToneMap: false)
        let glowMaterial = UnlitMaterial(
            color: color.withAlphaComponent(0.28),
            applyPostProcessToneMap: false
        )
        for child in selection.children {
            restyle(child, core: coreMaterial, glow: glowMaterial)
        }

        if let start = selection.children.first(where: { isStartHandleName($0.name) }) {
            start.name = startTargetPrefix + mark.id.uuidString
            setAccessibility(on: start, label: "Start of \(mark.kind.title) annotation", value: "Edit start point")
        }
        if let end = selection.children.first(where: { isEndHandleName($0.name) }) {
            end.name = endTargetPrefix + mark.id.uuidString
            setAccessibility(on: end, label: "End of \(mark.kind.title) annotation", value: "Edit end point")
        }
        if let attached = selection.children.first(where: { isAttachedTargetName($0.name) }) {
            attached.name = attachedTargetPrefix + mark.id.uuidString
            setAccessibility(on: attached, label: "Player attached annotation", value: "Tracked player target")
        }
    }

    private static func restyle(
        _ entity: Entity,
        core: UnlitMaterial,
        glow: UnlitMaterial
    ) {
        if let model = entity as? ModelEntity {
            if entity.name.contains("rail")
                || entity.name.contains("outer")
                || entity.name.contains("ring")
                || entity.name.contains("outline") {
                model.model?.materials = [glow]
            } else if entity.name.contains("core") || entity.name.contains("pin") || entity.name.contains("zone-segment") {
                model.model?.materials = [core]
            }
        }
        for child in entity.children {
            restyle(child, core: core, glow: glow)
        }
    }

    private static func parseDirectTargetName(_ name: String) -> AnnotationSceneTarget? {
        let candidates: [(String, AnnotationSceneTargetRole)] = [
            (startTargetPrefix, .start),
            (endTargetPrefix, .end),
            (attachedTargetPrefix, .attachedPlayer)
        ]
        for (prefix, role) in candidates where name.hasPrefix(prefix) {
            guard let id = UUID(uuidString: String(name.dropFirst(prefix.count))) else {
                return nil
            }
            return AnnotationSceneTarget(markID: id, role: role)
        }
        return nil
    }

    private static func isStartHandleName(_ name: String) -> Bool {
        name == startHandleName || name.hasPrefix(startTargetPrefix)
    }

    private static func isEndHandleName(_ name: String) -> Bool {
        name == endHandleName || name.hasPrefix(endTargetPrefix)
    }

    private static func isAttachedTargetName(_ name: String) -> Bool {
        name == attachedRootName || name.hasPrefix(attachedTargetPrefix)
    }

    private static func setAccessibility(on entity: Entity, label: String, value: String) {
        var accessibility = AccessibilityComponent()
        accessibility.isAccessibilityElement = true
        accessibility.label = LocalizedStringResource(stringLiteral: label)
        accessibility.value = LocalizedStringResource(stringLiteral: value)
        accessibility.systemActions = [.activate]
        entity.components.set(accessibility)
    }

    private static func color(for kind: CoachMarkKind) -> UIColor {
        switch kind {
        case .run: UIColor(red: 1.0, green: 0.42, blue: 0.12, alpha: 0.98)
        case .pass: UIColor(red: 0.22, green: 0.91, blue: 0.88, alpha: 0.98)
        case .danger: UIColor(red: 1.0, green: 0.25, blue: 0.34, alpha: 0.98)
        case .space, .playerLabel: UIColor(red: 0.78, green: 0.94, blue: 0.19, alpha: 0.98)
        }
    }

    private static let signalMaterial = UnlitMaterial(
        color: UIColor(red: 0.78, green: 0.94, blue: 0.19, alpha: 0.98),
        applyPostProcessToneMap: false
    )
    private static let selectionGlowMaterial = UnlitMaterial(
        color: UIColor.white.withAlphaComponent(0.24),
        applyPostProcessToneMap: false
    )
    private static let softSignalMaterial = UnlitMaterial(
        color: UIColor(red: 0.78, green: 0.94, blue: 0.19, alpha: 0.48),
        applyPostProcessToneMap: false
    )
    private static let darkInsetMaterial = UnlitMaterial(
        color: UIColor(red: 0.012, green: 0.020, blue: 0.018, alpha: 0.86),
        applyPostProcessToneMap: false
    )
}
