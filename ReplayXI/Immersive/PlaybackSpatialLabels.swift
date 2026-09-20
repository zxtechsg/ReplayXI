import RealityKit
import UIKit
#if DEBUG
import Dispatch
#endif

/// Lightweight spatial identity used by Match Playback.
///
/// Player tags live outside the animated rig hierarchy, so jersey identity stays
/// readable at every LOD and does not inherit a player's running rotation.
@MainActor
enum PlaybackSpatialLabels {
    #if DEBUG
    /// Requested RealityKit property/component writes, not internal engine
    /// work, allocation counts, frame time or headset FPS.
    struct UpdateWork: Codable, Equatable {
        var updateCalls = 0
        var visitedPlayerLabels = 0
        var transformWrites = 0
        var stylePropertyWrites = 0
        var visibilityWrites = 0
        var inputComponentWrites = 0
    }
    private(set) static var updateWork = UpdateWork()
    static func resetUpdateWorkForTesting() { updateWork = UpdateWork() }
    /// Calls made by centeredText only. Annotation-card extent measurement
    /// remains separate; these counts are not engine work or timing estimates.
    struct TextCenteringWork: Codable, Equatable {
        var cacheHits = 0
        var cacheMisses = 0
        var nativeCenteringBoundsQueries = 0
    }
    private(set) static var textCenteringWork = TextCenteringWork()
    static func resetTextCenteringWorkForTesting() { textCenteringWork = TextCenteringWork() }
    /// Direct player-tag box generation requests only. Elapsed CPU includes
    /// clock overhead; neither field reports native allocations or frame rate.
    struct PlayerLabelCollisionWork: Codable, Equatable {
        var generationCalls = 0
        var generationNanoseconds: UInt64 = 0
    }
    private(set) static var playerLabelCollisionWork = PlayerLabelCollisionWork()
    static func resetPlayerLabelCollisionWorkForTesting() {
        // Reset observations only; the immutable shared shape stays alive.
        playerLabelCollisionWork = PlayerLabelCollisionWork()
    }
    #endif
    static let firstPersonVisibleLabelLimit = 4
    static let firstPersonVisibleAnnotationLimit = 2
    /// A focused tactical review names only the directly relevant shirts. The
    /// remaining bodies stay on the board as formation context and remain
    /// selectable through their body targets.
    static let tacticalFocusedPlayerLabelLimit = 5
    static let tacticalContextLabelScale: Float = 2.85
    static let firstPersonMaximumLabelDistance: Float = 32
    // At close range the front/back shirt number is already readable. Hiding
    // the floating plate there prevents a tag from covering the athlete's face
    // or the ball during a first-person decision freeze.
    static let firstPersonMinimumLabelDistance: Float = 2.25

    /// Every player tag has the same local hit box. Share its immutable shape;
    /// collision components and entity transforms remain independently owned.
    private static let playerLabelTargetShape: ShapeResource = {
        #if DEBUG
        let start = DispatchTime.now().uptimeNanoseconds
        #endif
        let shape = ShapeResource.generateBox(size: [1.02, 0.40, 0.10])
        #if DEBUG
        playerLabelCollisionWork.generationCalls &+= 1
        playerLabelCollisionWork.generationNanoseconds &+= DispatchTime.now().uptimeNanoseconds - start
        #endif
        return shape
    }()

    private static let playerBoardMesh = MeshResource.generateBox(
        size: [0.94, 0.30, 0.026],
        cornerRadius: 0.075
    )
    private static let playerSelectionMesh = MeshResource.generateBox(
        size: [1.02, 0.38, 0.018],
        cornerRadius: 0.095
    )
    private static let teamStripMesh = MeshResource.generateBox(
        size: [0.055, 0.245, 0.032],
        cornerRadius: 0.020
    )
    private static let annotationBoardMesh = MeshResource.generateBox(
        size: [1.18, 0.32, 0.026],
        cornerRadius: 0.080
    )
    private struct AnnotationCardMetrics: Component {
        let boardWidth: Float
    }
    /// Fixed player identities benefit from mesh reuse, but arbitrary coach
    /// text must not acquire an unbounded process-wide lifetime.
    static let maximumCachedTextMeshes = 64
    private struct CachedTextMesh {
        let mesh: MeshResource
        /// Exact offset measured on the first fresh, unparented glyph using
        /// this immutable mesh. Shares the mesh's existing bounded lifetime.
        let centeringOffset: SIMD3<Float>
        var lastAccess: UInt64
    }
    private static var textMeshClock: UInt64 = 0
    private static var textMeshes: [String: CachedTextMesh] = [:]
    static var cachedTextMeshCount: Int { textMeshes.count }

    private static func displayFont(ofSize size: CGFloat) -> UIFont {
        // A concrete public PostScript name avoids CoreText's suboptimal
        // synthetic-system-name lookup inside RealityKit's 3D text generator.
        UIFont(name: "HelveticaNeue-CondensedBlack", size: size)
            ?? UIFont.systemFont(ofSize: size, weight: .black)
    }

    static func makePlayerLabels(for scenario: ReplayScenario) -> Entity {
        let root = Entity()
        root.name = "player-labels-root"
        for player in scenario.players {
            root.addChild(makePlayerLabel(for: player))
        }
        return root
    }

    static func updatePlayerLabels(
        in root: Entity,
        scenario: ReplayScenario,
        posesByPlayerID: [String: PlayerPose],
        viewMode: ReplayViewMode,
        perspectiveID: String,
        enabledPlayerIDs: Set<String>? = nil,
        firstPersonVisiblePlayerIDs: [String]? = nil,
        focusedPlayerIDs: Set<String>? = nil,
        acceptsInput: Bool = true
    ) {
        guard let labelsRoot = root.children.first(where: { $0.name == "player-labels-root" }) else {
            return
        }
        #if DEBUG
        updateWork.updateCalls &+= 1
        #endif

        // Only POV needs a ranked visibility set. Other views evaluate their
        // optional filters in-place, avoiding a throwaway 22-ID Set every frame.
        let fallbackFirstPersonIDs = viewMode == .firstPerson
                && firstPersonVisiblePlayerIDs == nil
            ? visiblePlayerIDs(
                scenario: scenario,
                posesByPlayerID: posesByPlayerID,
                viewMode: viewMode,
                perspectiveID: perspectiveID,
                enabledPlayerIDs: enabledPlayerIDs,
                firstPersonVisiblePlayerIDs: nil
            )
            : nil
        let observer = observerPoint(
            scenario: scenario,
            posesByPlayerID: posesByPlayerID,
            viewMode: viewMode,
            perspectiveID: perspectiveID
        )
        // Tabletop rigs are intentionally exaggerated for readability. Lift
        // the independent identity layer clear of their heads so shirt number
        // and role never disappear inside a selected player's body.
        let defaultLabelHeight: Float = 2.16

        for player in scenario.players {
            guard let label = labelsRoot.children.first(where: {
                $0.name == "player-label-\(player.id)"
            }) else { continue }
            #if DEBUG
            updateWork.visitedPlayerLabels &+= 1
            #endif
            setInputEnabled(acceptsInput, on: label)
            let passesBaseFilter: Bool = switch viewMode {
            case .firstPerson:
                if player.id == perspectiveID {
                    false
                } else if let pose = posesByPlayerID[player.id] {
                    (firstPersonVisiblePlayerIDs?.contains(player.id)
                        ?? fallbackFirstPersonIDs?.contains(player.id)
                        ?? false)
                        && ReplayGeometry.distance(observer, pose.position)
                            >= firstPersonMinimumLabelDistance
                        && ReplayGeometry.distance(observer, pose.position)
                            <= firstPersonMaximumLabelDistance
                } else {
                    false
                }
            case .tacticalTable, .touchline, .positional:
                enabledPlayerIDs?.contains(player.id) ?? true
            }
            let passesFocusFilter = viewMode != .tacticalTable
                || focusedPlayerIDs?.contains(player.id) != false
            let isVisible = passesBaseFilter && passesFocusFilter
            setVisibility(isVisible, on: label)
            guard isVisible, let pose = posesByPlayerID[player.id] else { continue }

            let dx = observer.x - pose.position.x
            let dz = observer.z - pose.position.z
            let distance = ReplayGeometry.distance(observer, pose.position)
            let resolvedScale: Float = switch viewMode {
            case .firstPerson:
                firstPersonLabelScale(forDistance: distance)
            case .tacticalTable:
                // Keep the active lens fully named. Number-only context chips
                // use 40% less linear footprint than the previous treatment,
                // materially reducing 22-player overlaps at tabletop scale.
                player.id == perspectiveID ? 4.75 : tacticalContextLabelScale
            case .touchline:
                1.70
            case .positional:
                2.30
            }
            let minimumReviewHeight = ReplayAthleteReviewLayout.minimumTagHeight(
                athleteScale: ReplayAthleteReviewLayout.focusScale(
                    viewMode: viewMode,
                    isSelected: player.id == perspectiveID,
                    isFeatured: scenario.featuredPerspectiveIDs.contains(player.id),
                    isShapeRole: scenario.formationTargets.contains { $0.playerID == player.id }
                ),
                labelScale: resolvedScale
            )
            let resolvedHeight: Float = switch viewMode {
            case .firstPerson:
                firstPersonLabelHeight(forDistance: distance)
                    + (player.team == .away ? 0.16 : 0)
                    + (player.shirtNumber.isMultiple(of: 2) ? 0 : 0.08)
            case .tacticalTable:
                max(tacticalLabelHeight(team: player.team, shirtNumber: player.shirtNumber), minimumReviewHeight)
            case .touchline, .positional:
                max(defaultLabelHeight, minimumReviewHeight)
            }
            applyLabelTransform(on: label, position: [pose.position.x, resolvedHeight, pose.position.z],
                                orientation: simd_quatf(angle: atan2(dx, dz), axis: [0, 1, 0]),
                                scale: SIMD3<Float>(repeating: resolvedScale))
            setStyleEnabled(player.id == perspectiveID,
                            on: label.children.first(where: { $0.name == "selected-outline" }))
            let usesCompactTacticalTag = (viewMode == .tacticalTable || viewMode == .touchline)
                && player.id != perspectiveID
            setStyleEnabled(!usesCompactTacticalTag,
                            on: label.children.first(where: { $0.name == "label-glyph" }))
            setStyleEnabled(usesCompactTacticalTag,
                            on: label.children.first(where: { $0.name == "compact-label-glyph" }))
            if let board = label.children.first(where: { $0.name == "label-board" }) {
                setStyleScaleX(usesCompactTacticalTag ? 0.54 : 1, on: board)
                // Context identities are a single high-contrast number draw.
                // The detailed active player retains the complete card.
                setStyleEnabled(!usesCompactTacticalTag, on: board)
            }
            if let strip = label.children.first(where: { $0.name == "team-strip" }) {
                setStylePositionX(usesCompactTacticalTag ? -0.205 : -0.405, on: strip)
                setStyleEnabled(!usesCompactTacticalTag, on: strip)
            }
        }
    }

    private static func applyLabelTransform(on label: Entity, position: SIMD3<Float>,
                                            orientation: simd_quatf, scale: SIMD3<Float>) {
        // Inspect the entity, not a last-request cache: clones, reparented tags
        // and external edits still need their actual presentation restored.
        let current = label.transform
        let sameRotation = current.rotation.vector == orientation.vector
            || current.rotation.vector == -orientation.vector
        guard current.translation != position || current.scale != scale || !sameRotation else { return }
        // One component update instead of three. Exact comparisons (including
        // q/-q equivalence) retain even very small position or facing changes.
        label.transform = Transform(scale: scale, rotation: orientation, translation: position)
        #if DEBUG
        updateWork.transformWrites &+= 1
        #endif
    }

    private static func setVisibility(_ isEnabled: Bool, on label: Entity) {
        guard label.isEnabled != isEnabled else { return }
        label.isEnabled = isEnabled
        #if DEBUG
        updateWork.visibilityWrites &+= 1
        #endif
    }

    private static func setStyleEnabled(_ isEnabled: Bool, on entity: Entity?) {
        guard let entity, entity.isEnabled != isEnabled else { return }
        entity.isEnabled = isEnabled
        #if DEBUG
        updateWork.stylePropertyWrites &+= 1
        #endif
    }

    private static func setStyleScaleX(_ value: Float, on entity: Entity) {
        guard entity.scale.x != value else { return }
        entity.scale.x = value
        #if DEBUG
        updateWork.stylePropertyWrites &+= 1
        #endif
    }

    private static func setStylePositionX(_ value: Float, on entity: Entity) {
        guard entity.position.x != value else { return }
        entity.position.x = value
        #if DEBUG
        updateWork.stylePropertyWrites &+= 1
        #endif
    }

    /// Keep identity visible while an editable annotation owns spatial input.
    /// Removing only InputTargetComponent prevents a player tag at an endpoint
    /// from stealing the pinch, while avoiding visual hierarchy churn.
    private static func setInputEnabled(_ isEnabled: Bool, on label: Entity) {
        if isEnabled {
            if label.components[InputTargetComponent.self] == nil {
                label.components.set(InputTargetComponent(allowedInputTypes: .all))
                #if DEBUG
                updateWork.inputComponentWrites &+= 1
                #endif
            }
        } else if label.components[InputTargetComponent.self] != nil {
            label.components.remove(InputTargetComponent.self)
            #if DEBUG
            updateWork.inputComponentWrites &+= 1
            #endif
        }
    }

    static func makeAnnotationTag(text: String, color: UIColor) -> Entity {
        let root = Entity()
        root.name = "annotation-label"
        let glyph = centeredText(
            text.uppercased(),
            fontSize: 0.145,
            color: .white,
            cacheKey: "annotation:\(text.uppercased())"
        )
        // Character counts cannot predict wide glyphs or uppercase expansion.
        // Measure once when the card is built, then share its exact width with
        // selection and hit geometry. Normal labels retain their font size.
        let textBounds = glyph.visualBounds(relativeTo: glyph)
        let horizontalTextPadding: Float = 0.24
        let boardWidth = min(max(
            estimatedAnnotationBoardWidth(characterCount: text.count),
            textBounds.extents.x + horizontalTextPadding
        ), 3.20)
        let textScale = min(
            1,
            (boardWidth - horizontalTextPadding) / max(textBounds.extents.x, 0.000_001),
            0.24 / max(textBounds.extents.y, 0.000_001)
        )
        glyph.scale = SIMD3<Float>(repeating: textScale)
        glyph.position.x *= textScale
        glyph.position.y *= textScale
        root.components.set(AnnotationCardMetrics(boardWidth: boardWidth))

        let board = ModelEntity(
            mesh: annotationBoardMesh,
            materials: [
                UnlitMaterial(
                    color: UIColor(red: 0.015, green: 0.022, blue: 0.020, alpha: 0.92),
                    applyPostProcessToneMap: false
                )
            ]
        )
        board.name = "annotation-tag-board"
        board.scale.x = boardWidth / 1.18
        root.addChild(board)

        let accent = ModelEntity(
            mesh: teamStripMesh,
            materials: [UnlitMaterial(color: color, applyPostProcessToneMap: false)]
        )
        accent.name = "annotation-tag-accent"
        accent.position = [-(boardWidth / 2) + 0.065, 0, 0.025]
        root.addChild(accent)

        glyph.name = "annotation-tag-glyph"
        glyph.position.z = 0.025
        root.addChild(glyph)
        return root
    }

    /// Constant-time metadata lookup; no text measurement during scene updates.
    static func annotationBoardWidth(in label: Entity, renderedCharacterCount: Int) -> Float {
        label.components[AnnotationCardMetrics.self]?.boardWidth
            ?? estimatedAnnotationBoardWidth(characterCount: renderedCharacterCount)
    }

    private static func estimatedAnnotationBoardWidth(characterCount: Int) -> Float {
        min(max(Float(characterCount) * 0.088, 1.18), 3.20)
    }

    private static func makePlayerLabel(for player: PlayerTrack) -> Entity {
        let root = Entity()
        root.name = "player-label-\(player.id)"
        // The visible identity tag is also a generous direct target. This is
        // much easier to acquire than a centimetre-scale tabletop body and
        // still resolves to the same authored player track.
        root.components.set(InputTargetComponent(allowedInputTypes: .all))
        root.components.set(
            CollisionComponent(
                shapes: [playerLabelTargetShape],
                isStatic: false
            )
        )
        root.components.set(HoverEffectComponent())

        var accessibility = AccessibilityComponent()
        // The player's body capsule is the canonical accessible element and
        // exists at every visible LOD. Keep metadata on the floating tag for
        // inspection, but do not announce the same player twice when this
        // optional label is also visible.
        accessibility.isAccessibilityElement = false
        accessibility.label = LocalizedStringResource(
            stringLiteral: "Number \(player.shirtNumber), \(player.displayName)"
        )
        accessibility.value = LocalizedStringResource(stringLiteral: player.role)
        root.components.set(accessibility)

        let selection = ModelEntity(
            mesh: playerSelectionMesh,
            materials: [
                UnlitMaterial(
                    color: UIColor(red: 0.78, green: 0.94, blue: 0.19, alpha: 0.92),
                    applyPostProcessToneMap: false
                )
            ]
        )
        selection.name = "selected-outline"
        selection.position.z = -0.020
        selection.isEnabled = false
        root.addChild(selection)

        let board = ModelEntity(
            mesh: playerBoardMesh,
            materials: [
                UnlitMaterial(
                    color: UIColor(red: 0.012, green: 0.020, blue: 0.018, alpha: 0.90),
                    applyPostProcessToneMap: false
                )
            ]
        )
        board.name = "label-board"
        root.addChild(board)

        let teamColor = player.team == .home
            ? UIColor(red: 0.22, green: 0.91, blue: 0.88, alpha: 1)
            : UIColor(red: 1.0, green: 0.25, blue: 0.34, alpha: 1)
        let strip = ModelEntity(
            mesh: teamStripMesh,
            materials: [UnlitMaterial(color: teamColor, applyPostProcessToneMap: false)]
        )
        strip.name = "team-strip"
        strip.position = [-0.405, 0, 0.025]
        root.addChild(strip)

        let label = "#\(player.shirtNumber)  \(player.positionCode)"
        let glyph = centeredText(
            label,
            fontSize: 0.16,
            color: .white,
            cacheKey: "player:\(label)"
        )
        glyph.name = "label-glyph"
        glyph.position.z = 0.025
        root.addChild(glyph)

        let compactGlyph = centeredText(
            "#\(player.shirtNumber)",
            fontSize: 0.18,
            color: .white,
            cacheKey: "player-compact:#\(player.shirtNumber)"
        )
        compactGlyph.name = "compact-label-glyph"
        compactGlyph.position.z = 0.026
        compactGlyph.isEnabled = false
        root.addChild(compactGlyph)
        return root
    }

    private static func centeredText(
        _ text: String,
        fontSize: CGFloat,
        color: UIColor,
        cacheKey: String
    ) -> ModelEntity {
        let mesh: MeshResource
        let cachedOffset: SIMD3<Float>?
        textMeshClock &+= 1
        if var cached = textMeshes[cacheKey] {
            cached.lastAccess = textMeshClock
            textMeshes[cacheKey] = cached
            mesh = cached.mesh
            cachedOffset = cached.centeringOffset
            #if DEBUG
            textCenteringWork.cacheHits &+= 1
            #endif
        } else {
            let generated = MeshResource.generateText(
                text,
                extrusionDepth: 0.006,
                font: displayFont(ofSize: fontSize),
                containerFrame: .zero,
                alignment: .left,
                lineBreakMode: .byClipping
            )
            mesh = generated
            cachedOffset = nil
            #if DEBUG
            textCenteringWork.cacheMisses &+= 1
            #endif
        }

        let entity = ModelEntity(
            mesh: mesh,
            materials: [UnlitMaterial(color: color, applyPostProcessToneMap: false)]
        )
        if let cachedOffset {
            entity.position = cachedOffset
        } else {
            let bounds = entity.visualBounds(relativeTo: entity)
            let offset = SIMD3<Float>(-bounds.center.x, -bounds.center.y, 0)
            #if DEBUG
            textCenteringWork.nativeCenteringBoundsQueries &+= 1
            #endif
            textMeshes[cacheKey] = CachedTextMesh(mesh: mesh, centeringOffset: offset, lastAccess: textMeshClock)
            if textMeshes.count > maximumCachedTextMeshes,
               let leastRecentlyUsedKey = textMeshes.min(by: {
                   $0.value.lastAccess < $1.value.lastAccess
               })?.key,
               leastRecentlyUsedKey != cacheKey {
                textMeshes.removeValue(forKey: leastRecentlyUsedKey)
            }
            entity.position = offset
        }
        return entity
    }

    private static func visiblePlayerIDs(
        scenario: ReplayScenario,
        posesByPlayerID: [String: PlayerPose],
        viewMode: ReplayViewMode,
        perspectiveID: String,
        enabledPlayerIDs: Set<String>?,
        firstPersonVisiblePlayerIDs: [String]?
    ) -> Set<String> {
        if viewMode == .firstPerson, let wearerPose = posesByPlayerID[perspectiveID] {
            return Set(
                scenario.players
                    .filter {
                        $0.id != perspectiveID
                            && (firstPersonVisiblePlayerIDs?.contains($0.id) ?? true)
                    }
                    .compactMap { player -> (String, Float)? in
                        guard let pose = posesByPlayerID[player.id] else { return nil }
                        let distance = ReplayGeometry.distance(wearerPose.position, pose.position)
                        guard distance >= firstPersonMinimumLabelDistance,
                              distance <= firstPersonMaximumLabelDistance
                        else { return nil }
                        return (player.id, distance)
                    }
                    .sorted { lhs, rhs in
                        lhs.1 == rhs.1 ? lhs.0 < rhs.0 : lhs.1 < rhs.1
                    }
                    .prefix(firstPersonVisibleLabelLimit)
                    .map(\.0)
            )
        }
        if let enabledPlayerIDs { return enabledPlayerIDs }
        return Set(scenario.players.map(\.id))
    }

    /// Near tags stay compact enough not to dominate the upper field of view;
    /// distant tags grow modestly to preserve legibility without exceeding the
    /// previous label footprint.
    static func firstPersonLabelScale(forDistance distance: Float) -> Float {
        min(max(0.34 + (max(distance, 0) * 0.009), 0.34), 0.62)
    }

    /// Coach captions should read as compact callouts, not pitch-sized signs.
    /// Scaling gently with range keeps their angular footprint useful while a
    /// nearby card stays below roughly half the size of the original treatment.
    static func firstPersonAnnotationScale(forDistance distance: Float) -> Float {
        min(max(0.31 + (max(distance, 0) * 0.009), 0.34), 0.58)
    }

    static func firstPersonLabelHeight(forDistance distance: Float) -> Float {
        2.20 + min(max(distance, 0) * 0.005, 0.16)
    }

    /// A fixed team-and-shirt lane keeps compressed tactical formations
    /// readable without frame-to-frame collision solving (and its jitter).
    /// Labels remain directly above their player in X/Z, so acquisition stays
    /// obvious while opposing tags no longer occupy the same vertical band.
    static func tacticalLabelHeight(team: FootballTeam, shirtNumber: Int) -> Float {
        let teamBand: Float = team == .home ? 6.20 : 7.85
        let shirtBand: Float = shirtNumber.isMultiple(of: 2) ? 0 : 0.72
        return teamBand + shirtBand
    }

    private static func observerPoint(
        scenario: ReplayScenario,
        posesByPlayerID: [String: PlayerPose],
        viewMode: ReplayViewMode,
        perspectiveID: String
    ) -> PitchPoint {
        switch viewMode {
        case .firstPerson:
            return posesByPlayerID[perspectiveID]?.position ?? .zero
        case .tacticalTable:
            return PitchPoint(x: 0, z: 100)
        case .touchline:
            return PitchPoint(x: -70, z: 0)
        case .positional:
            return .zero
        }
    }

}
