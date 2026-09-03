import RealityKit
import SwiftUI
import UIKit

@MainActor
enum PitchSceneFactory {
    private static let pitchWidth: Float = 68
    private static let pitchLength: Float = 105
    static let positionalScale: Float = TriangleLockLayout.visualiseScale
    static let positionalForwardOffset: Float = TriangleLockLayout.visualiseForwardOffset
    /// Two nearby articulated subjects preserve the close decision context
    /// while leaving enough of the mixed-space draw envelope for the pitch,
    /// readable identities, the ball, and coach annotations.
    static let firstPersonDetailedRigLimit = 2

    /// Weak RealityKit references let the cache accelerate a live scene
    /// without extending that scene's lifetime after immersive-root replacement.
    private final class WeakEntityReference {
        weak var value: Entity?

        init(_ value: Entity?) {
            self.value = value
        }
    }

    private struct CachedMarkBinding {
        let mark: CoachMark
        let entity: WeakEntityReference
        let label: WeakEntityReference
        let labelTarget: WeakEntityReference
        let bodyTarget: WeakEntityReference
        let playerAttachment: WeakEntityReference
    }

    private struct PlayerSceneBuild {
        let root: Entity
        let tableMarkerBinding: ReplayAthleteJointBinding?
    }

    /// The scene focus is deliberately semantic. It changes only when a coach
    /// selects a different mark, changes that mark, or opens a different set of
    /// decision receivers—not as the replay clock advances.
    private struct DecisionPlayerFocusKey: Equatable {
        let scenarioID: String
        let sourceID: String
        let receiver0: String?
        let receiver1: String?
        let receiver2: String?
        let receiver3: String?

        init(snapshot: ReplayDecisionSnapshot) {
            scenarioID = snapshot.scenarioID
            sourceID = snapshot.playerID
            receiver0 = Self.receiverID(at: 0, in: snapshot)
            receiver1 = Self.receiverID(at: 1, in: snapshot)
            receiver2 = Self.receiverID(at: 2, in: snapshot)
            receiver3 = Self.receiverID(at: 3, in: snapshot)
        }

        private static func receiverID(
            at index: Int,
            in snapshot: ReplayDecisionSnapshot
        ) -> String? {
            guard snapshot.passingOptions.indices.contains(index) else { return nil }
            return snapshot.passingOptions[index].receiverID
        }

    }

    private enum SpatialReviewFocus: Equatable {
        case normal
        case annotation(mark: CoachMark, perspectiveID: String)
        case decision(DecisionPlayerFocusKey)

        var selectedMarkID: UUID? {
            guard case let .annotation(mark, _) = self else { return nil }
            return mark.id
        }

    }

    /// Exactly matches the current first-person caption budget without a
    /// per-frame Set or sorting buffer.
    private struct FirstPersonAnnotationLabelSelection {
        var first: UUID?
        var second: UUID?

        func contains(_ id: UUID) -> Bool {
            first == id || second == id
        }
    }

    private final class AnnotationSceneCache {
        weak var root: Entity?
        weak var marksRoot: Entity?
        var marks: [CoachMark] = []
        var bindings: [CachedMarkBinding] = []
        var bindingsByID: [UUID: CachedMarkBinding] = [:]
        var renderPriorityIndices: [Int] = []
        var playerLabelFocus: SpatialReviewFocus = .normal
        var focusedPlayerIDs: Set<String>?
        var firstPersonDetailedPlayerIDs: [String] = []
        var importedAthlete: ReplayImportedAthleteInstance?
        var importedAthleteAttemptedPlayerID: String?
        // A match root owns at most 22 far rigs and four transient near rigs.
        // Retaining the factory-created semantic bindings removes named joint
        // searches from the 30 Hz path. Entries are explicitly invalidated when
        // a near rig is detached; the root-level LRU bounds the remaining life.
        private var athleteRigBindings: [ObjectIdentifier: ReplayAthleteJointBinding] = [:]
        private(set) var athleteBindingHierarchyResolutionCount = 0
        private(set) var athleteBindingInvalidationCount = 0
        var lastAccess: UInt64 = 0

        private static let maximumAthleteRigBindings = 32

        init(root: Entity, marksRoot: Entity, lastAccess: UInt64) {
            self.root = root
            self.marksRoot = marksRoot
            self.lastAccess = lastAccess
        }

        func retainAthleteBinding(_ binding: ReplayAthleteJointBinding) {
            let key = ObjectIdentifier(binding.root)
            guard athleteRigBindings[key] == nil else { return }
            if athleteRigBindings.count >= Self.maximumAthleteRigBindings {
                pruneDetachedAthleteBindings()
            }
            guard athleteRigBindings.count < Self.maximumAthleteRigBindings else { return }
            athleteRigBindings[key] = binding
        }

        func athleteBinding(for rig: Entity) -> ReplayAthleteJointBinding? {
            let key = ObjectIdentifier(rig)
            if let cached = athleteRigBindings[key], cached.root === rig {
                return cached
            }

            guard let resolved = try? ReplayAthleteJointBinding(root: rig) else { return nil }
            athleteBindingHierarchyResolutionCount &+= 1
            retainAthleteBinding(resolved)
            return resolved
        }

        func invalidateAthleteBinding(for rig: Entity) {
            if athleteRigBindings.removeValue(forKey: ObjectIdentifier(rig)) != nil {
                athleteBindingInvalidationCount &+= 1
            }
        }

        func containsAthleteBinding(for rig: Entity) -> Bool {
            let key = ObjectIdentifier(rig)
            return athleteRigBindings[key]?.root === rig
        }

        var athleteBindingCount: Int {
            pruneDetachedAthleteBindings()
            return athleteRigBindings.count
        }

        private func pruneDetachedAthleteBindings() {
            athleteRigBindings = athleteRigBindings.filter { $0.value.root.parent != nil }
        }

        func matches(_ incoming: [CoachMark], count: Int) -> Bool {
            guard marks.count == count,
                  bindings.count == count,
                  bindingsByID.count == count,
                  marksRoot?.children.count == count
            else { return false }
            for index in 0..<count where marks[index] != incoming[index] {
                return false
            }
            return bindings.allSatisfy {
                $0.entity.value?.parent != nil
                    && $0.label.value != nil
                    && $0.labelTarget.value != nil
                    && $0.bodyTarget.value != nil
                    && ($0.mark.kind != .playerLabel || $0.playerAttachment.value != nil)
            }
        }
    }

    private static let maximumCachedAnnotationRoots = 6
    static let selectedAnnotationContextOpacity: Float = 0.13
    static let decisionAnnotationContextOpacity: Float = 0.07
    private static var annotationCacheClock: UInt64 = 0
    private static var annotationSceneCaches: [ObjectIdentifier: AnnotationSceneCache] = [:]

    struct ProceduralAthleteBindingCacheDiagnostics: Equatable {
        let cachedBindings: Int
        let hierarchyResolutions: Int
        let invalidations: Int
    }

    /// Narrow regression seam for proving that presentation updates reuse the
    /// factory's semantic bindings rather than walking joint names at 30 Hz.
    static func proceduralAthleteBindingCacheDiagnostics(
        for root: Entity
    ) -> ProceduralAthleteBindingCacheDiagnostics {
        guard let cache = annotationSceneCaches[ObjectIdentifier(root)],
              cache.root === root else {
            return ProceduralAthleteBindingCacheDiagnostics(
                cachedBindings: 0,
                hierarchyResolutions: 0,
                invalidations: 0
            )
        }
        return ProceduralAthleteBindingCacheDiagnostics(
            cachedBindings: cache.athleteBindingCount,
            hierarchyResolutions: cache.athleteBindingHierarchyResolutionCount,
            invalidations: cache.athleteBindingInvalidationCount
        )
    }

    static func hasCachedProceduralAthleteBinding(
        for rig: Entity,
        in root: Entity
    ) -> Bool {
        guard let cache = annotationSceneCaches[ObjectIdentifier(root)],
              cache.root === root else { return false }
        return cache.containsAthleteBinding(for: rig)
    }

    // All 22 rigs share immutable geometry. Kits and appearances vary through
    // lightweight materials, avoiding hundreds of duplicate mesh allocations.
    private static let rigShortsMesh = MeshResource.generateBox(
        size: [0.39, 0.21, 0.26], cornerRadius: 0.065
    )
    // Smooth shared ellipsoids replace the earlier cylinder-and-box mannequin
    // silhouette. Each ModelEntity scales the unit sphere into an anatomical
    // taper while the joint hierarchy supplies deterministic running motion.
    private static let rigBodyVolumeMesh = MeshResource.generateSphere(radius: 1)
    private static let rigSidePanelMesh = MeshResource.generateBox(
        size: [0.018, 0.25, 0.20], cornerRadius: 0.008
    )
    private static let rigCollarMesh = MeshResource.generateCylinder(height: 0.026, radius: 0.105)
    private static let rigNeckMesh = MeshResource.generateCylinder(height: 0.10, radius: 0.073)
    private static let rigHeadMesh = MeshResource.generateSphere(radius: 0.133)
    private static let rigJawMesh = MeshResource.generateSphere(radius: 0.107)
    private static let rigEarMesh = MeshResource.generateSphere(radius: 0.030)
    private static let rigNoseMesh = MeshResource.generateBox(
        size: [0.037, 0.049, 0.044], cornerRadius: 0.017
    )
    private static let rigMouthMesh = MeshResource.generateBox(
        size: [0.064, 0.010, 0.012], cornerRadius: 0.004
    )
    private static let rigBrowMesh = MeshResource.generateBox(
        size: [0.052, 0.010, 0.010], cornerRadius: 0.004
    )
    private static let rigKitPipingMesh = MeshResource.generateBox(
        size: [0.018, 0.34, 0.012], cornerRadius: 0.005
    )
    private static let rigHairMesh = MeshResource.generateSphere(radius: 0.137)
    private static let rigThighMesh = rigBodyVolumeMesh
    private static let rigKneeMesh = MeshResource.generateSphere(radius: 0.084)
    private static let rigShinMesh = rigBodyVolumeMesh
    private static let rigSockCuffMesh = MeshResource.generateCylinder(height: 0.035, radius: 0.078)
    private static let rigBootMesh = MeshResource.generateBox(
        size: [0.136, 0.086, 0.257], cornerRadius: 0.040
    )
    private static let rigBootSoleMesh = MeshResource.generateBox(
        size: [0.145, 0.023, 0.272], cornerRadius: 0.010
    )
    private static let rigBootAccentMesh = MeshResource.generateBox(
        size: [0.035, 0.016, 0.155], cornerRadius: 0.007
    )
    private static let rigSleeveMesh = rigBodyVolumeMesh
    private static let rigUpperArmMesh = rigBodyVolumeMesh
    private static let rigForearmMesh = rigBodyVolumeMesh
    private static let rigKeeperForearmMesh = rigBodyVolumeMesh
    private static let rigElbowMesh = MeshResource.generateSphere(radius: 0.068)
    private static let rigHandMesh = MeshResource.generateSphere(radius: 0.060)
    private static let rigKeeperGloveMesh = MeshResource.generateBox(
        size: [0.14, 0.15, 0.09], cornerRadius: 0.035
    )
    private static let rigBadgeMesh = MeshResource.generateCylinder(height: 0.012, radius: 0.045)
    private static let rigContactShadowMesh = MeshResource.generateCylinder(height: 0.008, radius: 0.30)
    private static let tableMarkerBaseMesh = MeshResource.generateCylinder(height: 0.055, radius: 0.34)
    private static let tableMarkerHeadMesh = MeshResource.generateSphere(radius: 0.15)
    private static let tableMarkerFacingMesh = MeshResource.generateBox(
        size: [0.13, 0.055, 0.42], cornerRadius: 0.045
    )
    private static let matchBallMesh = MeshResource.generateSphere(radius: 0.11)
    private static let matchBallPanelMesh = MeshResource.generateCylinder(height: 0.006, radius: 0.025)
    private static let matchBallShadowMesh = MeshResource.generateCylinder(height: 0.004, radius: 0.145)
    private static let tacticalBoardRimMesh = MeshResource.generateBox(
        size: [pitchWidth + 1.20, 0.52, pitchLength + 1.20],
        cornerRadius: 0.48
    )
    private static let annotationDraftSegmentMesh = MeshResource.generateBox(
        size: [0.24, 0.030, 0.070],
        cornerRadius: 0.028
    )
    private static let annotationDraftPinMesh = MeshResource.generateSphere(radius: 0.115)
    private static let annotationDraftStemMesh = MeshResource.generateCylinder(
        height: 0.42,
        radius: 0.025
    )
    private static let annotationMarkSegmentMesh = MeshResource.generateBox(
        size: [0.20, 0.06, 1],
        cornerRadius: 0.09
    )
    private static let annotationMarkArrowMesh = MeshResource.generateCone(
        height: 0.72,
        radius: 0.34
    )
    private static let selectionHaloMesh = MeshResource.generateCylinder(height: 0.025, radius: 0.47)

    private struct RagdollPhysicsPart {
        let name: String
        let shape: ShapeResource
        let mass: Float
    }

    /// Shared collision primitives are installed on only the one explicitly
    /// cued player, then removed after the impact window. Kinematic bodies let
    /// the deterministic playback pose participate in RealityKit collision
    /// queries without handing timeline ownership to a frame-driven solver.
    private static let ragdollPhysicsParts: [RagdollPhysicsPart] = [
        RagdollPhysicsPart(
            name: "hips",
            shape: ShapeResource.generateBox(size: [0.38, 0.24, 0.25]),
            mass: 12
        ),
        RagdollPhysicsPart(
            name: "spine",
            shape: ShapeResource.generateCapsule(height: 0.56, radius: 0.19)
                .offsetBy(translation: [0, 0.29, 0]),
            mass: 27
        ),
        RagdollPhysicsPart(
            name: "head-root",
            shape: ShapeResource.generateSphere(radius: 0.145),
            mass: 5
        ),
        RagdollPhysicsPart(
            name: "left-hip",
            shape: ShapeResource.generateCapsule(height: 0.39, radius: 0.094)
                .offsetBy(translation: [0, -0.195, 0]),
            mass: 7.5
        ),
        RagdollPhysicsPart(
            name: "right-hip",
            shape: ShapeResource.generateCapsule(height: 0.39, radius: 0.094)
                .offsetBy(translation: [0, -0.195, 0]),
            mass: 7.5
        ),
        RagdollPhysicsPart(
            name: "left-knee",
            shape: ShapeResource.generateCapsule(height: 0.35, radius: 0.076)
                .offsetBy(translation: [0, -0.175, 0]),
            mass: 4.3
        ),
        RagdollPhysicsPart(
            name: "right-knee",
            shape: ShapeResource.generateCapsule(height: 0.35, radius: 0.076)
                .offsetBy(translation: [0, -0.175, 0]),
            mass: 4.3
        ),
        RagdollPhysicsPart(
            name: "left-shoulder",
            shape: ShapeResource.generateCapsule(height: 0.31, radius: 0.068)
                .offsetBy(translation: [0, -0.155, 0]),
            mass: 2.6
        ),
        RagdollPhysicsPart(
            name: "right-shoulder",
            shape: ShapeResource.generateCapsule(height: 0.31, radius: 0.068)
                .offsetBy(translation: [0, -0.155, 0]),
            mass: 2.6
        ),
        RagdollPhysicsPart(
            name: "left-elbow",
            shape: ShapeResource.generateCapsule(height: 0.27, radius: 0.058)
                .offsetBy(translation: [0, -0.135, 0]),
            mass: 1.6
        ),
        RagdollPhysicsPart(
            name: "right-elbow",
            shape: ShapeResource.generateCapsule(height: 0.27, radius: 0.058)
                .offsetBy(translation: [0, -0.135, 0]),
            mass: 1.6
        ),
    ]
    private static let ragdollPhysicsMaterial = PhysicsMaterialResource.generate(
        staticFriction: 0.88,
        dynamicFriction: 0.72,
        restitution: 0.08
    )
    private static let ragdollCollisionGroup = CollisionGroup(rawValue: 1 << 20)
    /// RealityKit forwards the font's name into CoreText while tessellating 3D
    /// glyphs. UIKit's synthetic "System Font Black" name triggers a slower
    /// name-resolution path, so use a public PostScript face when available.
    private static let shirtNumberFont = UIFont(
        name: "HelveticaNeue-CondensedBlack",
        size: 0.19
    ) ?? UIFont.systemFont(ofSize: 0.19, weight: .black)
    private static var shirtNumberMeshCache: [Int: MeshResource] = [:]
    static func positionalTargetPoint(
        for target: FormationTarget,
        in scenario: ReplayScenario,
        mode: TriangleLockMode = .visualise
    ) -> PitchPoint {
        let targets = scenario.formationTargets
        let scale = TriangleLockLayout.scale(for: mode, targets: targets)
        let forwardOffset = mode == .place
            ? TriangleLockLayout.placeForwardOffset
            : TriangleLockLayout.visualiseForwardOffset
        let centre = PitchPoint(
            x: targets.isEmpty ? 0 : targets.map(\.position.x).reduce(0, +) / Float(targets.count),
            z: targets.isEmpty ? 0 : targets.map(\.position.z).reduce(0, +) / Float(targets.count)
        )
        return PitchPoint(
            x: -(target.position.x - centre.x) * scale,
            z: -forwardOffset - ((target.position.z - centre.z) * scale)
        )
    }

    static func physicalTolerance(
        for target: FormationTarget,
        mode: TriangleLockMode = .place
    ) -> Float {
        _ = target
        return TriangleLockLayout.tolerance(for: mode)
    }

    static func makeMatchRoot(for scenario: ReplayScenario) -> Entity {
        let root = Entity()
        root.name = "match-root-\(scenario.id)"

        let pitch = makePitch()
        pitch.name = "pitch"
        root.addChild(pitch)

        let playersRoot = Entity()
        playersRoot.name = "players-root"
        var initialAthleteBindings: [ReplayAthleteJointBinding] = []
        initialAthleteBindings.reserveCapacity(scenario.players.count)
        for player in scenario.players {
            // Detailed rigs are fully lazy. The first presentation update knows
            // the actual view mode; constructing one here would waste a complete
            // articulated avatar when Player POV immediately hides the wearer.
            let build = makePlayer(player, includesDetailedRig: false)
            playersRoot.addChild(build.root)
            if let tableMarkerBinding = build.tableMarkerBinding {
                initialAthleteBindings.append(tableMarkerBinding)
            }
        }
        root.addChild(playersRoot)
        root.addChild(PlaybackSpatialLabels.makePlayerLabels(for: scenario))

        // One shared overlay replaces 22 dormant copies. It follows the
        // selected telemetry pose and retains authored facing independently
        // from the wearer's head-tracked free look.
        root.addChild(makeRecordedFacingIndicator())
        root.addChild(makeSelectionHalo())

        root.addChild(makeMatchBall())

        let ballShadow = ModelEntity(
            mesh: matchBallShadowMesh,
            materials: [
                UnlitMaterial(
                    color: UIColor(red: 0, green: 0.01, blue: 0.008, alpha: 0.38),
                    applyPostProcessToneMap: false
                )
            ]
        )
        ballShadow.name = "ball-shadow"
        root.addChild(ballShadow)

        let marksRoot = Entity()
        marksRoot.name = "marks-root"
        root.addChild(marksRoot)
        root.addChild(AnnotationSceneAffordance.makeSelectionRoot())
        root.addChild(makeAnnotationDraftRoot())
        root.addChild(DecisionOptionSceneOverlay.makeRoot())

        let targetsRoot = Entity()
        targetsRoot.name = "targets-root"
        for target in scenario.formationTargets {
            targetsRoot.addChild(makeFormationTarget(target, allTargets: scenario.formationTargets))
        }
        root.addChild(targetsRoot)

        root.addChild(makeTriangleBoard(for: scenario))
        root.addChild(makeTriangleShapeRoot())

        let lanesRoot = makeLaneRoot()
        lanesRoot.name = "lanes-root"
        root.addChild(lanesRoot)

        // Collision-only: a nearly transparent ModelEntity can still render as an
        // opaque slab on some RealityKit/simulator combinations.
        let surface = Entity()
        surface.name = "annotation-surface"
        surface.position.y = 0.025
        surface.components.set(InputTargetComponent(allowedInputTypes: .all))
        surface.components.set(
            CollisionComponent(
                shapes: [.generateBox(size: [pitchWidth, 0.04, pitchLength])],
                isStatic: true
            )
        )
        root.addChild(surface)

        let sceneCache = syncMarks(in: root, marks: scenario.coachMarks)
        for binding in initialAthleteBindings {
            sceneCache?.retainAthleteBinding(binding)
        }
        return root
    }

    static func update(
        root: Entity,
        scenario: ReplayScenario,
        time: TimeInterval,
        viewMode: ReplayViewMode,
        perspectiveID: String,
        marks: [CoachMark],
        selectedAnnotationID: UUID? = nil,
        selectedAnnotationIsEditable: Bool = false,
        decisionSnapshot: ReplayDecisionSnapshot? = nil,
        showsLaneLens: Bool,
        isDrawing: Bool,
        draftStart: PitchPoint? = nil,
        draftEnd: PitchPoint? = nil,
        draftKind: CoachMarkKind = .run,
        positionalOriginTransform: simd_float4x4?,
        triangleLockMode: TriangleLockMode = .visualise,
        isTrianglePlacementReady: Bool = false,
        showsIdealBranch: Bool = false,
        ragdollCue: PlayerRagdollCue? = nil
    ) {
        // A caller-supplied cue supports imported impact data in every view.
        // The bundled showcase cue stays automatic in external review views,
        // but never throws an unrequested body through the wearer's near field
        // in Player POV. A future explicit Impact mode can pass the cue back in.
        let resolvedRagdollCue: PlayerRagdollCue? = if let ragdollCue {
            ragdollCue
        } else if viewMode == .firstPerson {
            nil
        } else {
            PlayerRagdollCue.authoredDemo(for: scenario)
        }
        let effectiveTriangleMode: TriangleLockMode =
            triangleLockMode == .place && isTrianglePlacementReady ? .place : .visualise
        // Endpoint handles must be the sole acquisition targets during direct
        // geometry editing. Player capsules and floating number tags may share
        // the same pitch coordinate as a player-origin run, so suspend those
        // hit targets until the annotation inspector closes.
        let suspendsPlayerPickingForAnnotationEdit = selectedAnnotationIsEditable
            && selectedAnnotationID != nil
            && !isDrawing
        let isTriangleView = viewMode == .positional
        let showsIdealShape = isTriangleView
            && (showsIdealBranch || effectiveTriangleMode == .place)
        let featuredTriangleIDs: Set<String> = isTriangleView
            ? Set(scenario.formationTargets.map(\.playerID))
            : []
        let triangleTargetsByPlayerID = Dictionary(
            uniqueKeysWithValues: scenario.formationTargets.map { ($0.playerID, $0) }
        )
        let playerPosesByID = Dictionary(
            uniqueKeysWithValues: scenario.players.map { ($0.id, $0.pose(at: time)) }
        )
        let firstPersonVisibleIDs: [String] = if viewMode == .firstPerson {
            nearestVisiblePlayerIDs(
                players: scenario.players,
                posesByPlayerID: playerPosesByID,
                wearerID: perspectiveID,
                limit: PlaybackSpatialLabels.firstPersonVisibleLabelLimit
            )
        } else {
            []
        }
        let sceneState = annotationCache(for: root)
        var firstPersonDetailedIDList = resolvedFirstPersonDetailedPlayerIDs(
            cache: sceneState,
            candidates: firstPersonVisibleIDs,
            posesByPlayerID: playerPosesByID,
            wearerID: perspectiveID,
            limit: firstPersonDetailedRigLimit
        )
        // A distant authored impact still needs its articulated body, but POV
        // rendering must never exceed the existing neighbour budget. Promote
        // the cue subject into the last LOD slot instead of allocating a fifth
        // detailed player.
        if viewMode == .firstPerson,
           firstPersonDetailedRigLimit > 0,
           let resolvedRagdollCue,
           resolvedRagdollCue.isActive(at: time),
           resolvedRagdollCue.playerID != perspectiveID,
           scenario.player(id: resolvedRagdollCue.playerID) != nil,
           !firstPersonDetailedIDList.contains(resolvedRagdollCue.playerID) {
            if firstPersonDetailedIDList.count == firstPersonDetailedRigLimit {
                firstPersonDetailedIDList.removeLast()
            }
            firstPersonDetailedIDList.append(resolvedRagdollCue.playerID)
        }
        let firstPersonDetailedIDs = Set(firstPersonDetailedIDList)
        let preferredImportedAthleteID: String? = if viewMode == .firstPerson {
            // The selected track is the wearer's translated camera origin and
            // must stay visually hidden. Spend the one imported-rig budget on
            // the nearest visible neighbour instead.
            firstPersonDetailedIDList.first
        } else {
            perspectiveID
        }
        let importedAthleteID: String? = if let preferredImportedAthleteID,
                                           resolvedRagdollCue?.playerID == preferredImportedAthleteID,
                                           resolvedRagdollCue?.isActive(at: time) == true {
            // The imported pilot is not yet retargeted to Replay XI's fixed-step
            // ragdoll. Preserve the deterministic procedural body for impacts.
            nil
        } else {
            preferredImportedAthleteID
        }
        let primaryTriangleDefenderID = isTriangleView
            ? primaryShapeDefenderID(in: scenario, time: time)
            : nil
        let labelEnabledPlayerIDs: Set<String>? = if isTriangleView {
            effectiveTriangleMode == .place
                ? []
                : featuredTriangleIDs.union(
                    primaryTriangleDefenderID.map { Set([$0]) } ?? Set<String>()
                )
        } else {
            nil
        }
        let ballPose = scenario.ball.pose(at: time)
        let shapeSourcePosition: PitchPoint? = if isTriangleView,
                                                  let source = scenario.player(id: scenario.defaultPerspectiveID) {
            showsIdealShape
                ? triangleTargetsByPlayerID[source.id]?.position
                    ?? playerPosesByID[source.id]?.position
                    ?? source.pose(at: time).position
                : playerPosesByID[source.id]?.position ?? source.pose(at: time).position
        } else {
            nil
        }
        let presentationBallPosition = shapeSourcePosition.map {
            PitchPoint(x: $0.x + 0.55, z: $0.z + 0.25)
        } ?? ballPose.position

        if let playersRoot = directChild(named: "players-root", of: root) {
            // RealityKit child ordering is not part of our data contract. It can
            // change when a rig is detached or another child is inserted, so
            // always resolve the authored track through the stable player ID.
            let playerEntitiesByID = Dictionary(
                uniqueKeysWithValues: playersRoot.children.compactMap { entity -> (String, Entity)? in
                    let prefix = "player-"
                    guard entity.name.hasPrefix(prefix) else { return nil }
                    return (String(entity.name.dropFirst(prefix.count)), entity)
                }
            )
            reconcileImportedAthlete(
                cache: sceneState,
                admittedPlayerID: importedAthleteID,
                playerEntitiesByID: playerEntitiesByID
            )
            for player in scenario.players {
                guard let entity = playerEntitiesByID[player.id] else { continue }
                let isSelected = player.id == perspectiveID
                let pose = playerPosesByID[player.id] ?? player.pose(at: time)
                let locomotion = player.locomotion(at: time)
                // A cue is explicit and singular, so normal telemetry remains
                // the only animation source for every uncued player. Shape Lab
                // intentionally ignores impacts because it presents authored
                // formation targets rather than match contact.
                let activeRagdollCue: PlayerRagdollCue? = if let resolvedRagdollCue,
                                                             resolvedRagdollCue.playerID == player.id,
                                                             resolvedRagdollCue.isActive(at: time),
                                                             viewMode != .positional {
                    resolvedRagdollCue
                } else {
                    nil
                }
                let idealTarget = triangleTargetsByPlayerID[player.id]
                var presentationPosition = showsIdealShape && effectiveTriangleMode == .visualise
                    ? idealTarget?.position ?? pose.position
                    : pose.position
                var presentationFacingDegrees = pose.facingDegrees
                if let activeRagdollCue {
                    let impactPose = player.pose(at: activeRagdollCue.impactTime)
                    let telemetryRelease = activeRagdollCue.telemetryRelease(at: time)
                    presentationPosition = impactPose.position.interpolated(
                        to: presentationPosition,
                        fraction: telemetryRelease
                    )
                    presentationFacingDegrees = ReplayGeometry.interpolateAngle(
                        from: impactPose.facingDegrees,
                        to: pose.facingDegrees,
                        fraction: telemetryRelease
                    )
                }
                entity.position = [presentationPosition.x, 0, presentationPosition.z]
                if showsIdealShape,
                   idealTarget != nil,
                   ReplayGeometry.distance(presentationPosition, presentationBallPosition) > 0.05 {
                    let facingRadians = atan2(
                        presentationBallPosition.x - presentationPosition.x,
                        presentationBallPosition.z - presentationPosition.z
                    )
                    entity.orientation = simd_quatf(angle: -facingRadians, axis: [0, 1, 0])
                } else {
                    entity.orientation = simd_quatf(
                        angle: -presentationFacingDegrees * .pi / 180,
                        axis: [0, 1, 0]
                    )
                }
                if viewMode == .positional {
                    entity.isEnabled = effectiveTriangleMode == .visualise
                        && (
                            featuredTriangleIDs.contains(player.id)
                                || player.id == primaryTriangleDefenderID
                        )
                } else {
                    entity.isEnabled = true
                }
                let isFeatured = scenario.featuredPerspectiveIDs.contains(player.id)
                let focusScale: Float
                switch viewMode {
                case .firstPerson:
                    // Player POV renders the match at human scale. Perspective
                    // is created by moving the pitch around the viewer, not by
                    // enlarging the selected avatar on a miniature table.
                    focusScale = 1
                case .tacticalTable:
                    // The tabletop is an analysis surface, so player identity
                    // must survive at arm's length. Keep the selected player
                    // unmistakable while every off-ball runner remains a
                    // legible footballer instead of collapsing into a peg.
                    focusScale = isSelected ? 3.15 : (isFeatured ? 2.05 : 1.40)
                case .touchline:
                    focusScale = isSelected ? 1.9 : (isFeatured ? 1.4 : 1.08)
                case .positional:
                    focusScale = effectiveTriangleMode == .place
                        ? 1
                        : (featuredTriangleIDs.contains(player.id) ? 3.05 : 2.65)
                }
                entity.scale = SIMD3<Float>(repeating: focusScale)
                let isShapeVisualise = scenario.kind == .shapeLab
                    && viewMode == .positional
                    && effectiveTriangleMode == .visualise
                // A head-mounted camera must not render the selected player's
                // own head around the wearer. Keep the track/entity alive as
                // the positional anchor, but suppress its visual children.
                let hidesHeadMountedAvatar = viewMode == .firstPerson && isSelected
                if let interactionTarget = directChild(named: "interaction-target", of: entity) {
                    interactionTarget.isEnabled = entity.isEnabled
                        && !hidesHeadMountedAvatar
                        && !suspendsPlayerPickingForAnnotationEdit
                    // Keep the body itself an easy target after the miniature
                    // pitch and focus scales are applied. The floating number
                    // tag offers a second, equally direct acquisition surface.
                    let footprintScale: Float = switch viewMode {
                    case .firstPerson: 1
                    case .tacticalTable: 2.4 / focusScale
                    case .touchline: 2.1 / focusScale
                    case .positional: 1.4 / max(focusScale, 0.01)
                    }
                    interactionTarget.scale = [footprintScale, 1, footprintScale]
                }
                let isNearbyFirstPersonPlayer = viewMode == .firstPerson
                    && firstPersonDetailedIDs.contains(player.id)
                let needsDetailedRig = entity.isEnabled
                    && !hidesHeadMountedAvatar
                    && (
                        isShapeVisualise
                            || isNearbyFirstPersonPlayer
                            || isSelected
                            || activeRagdollCue != nil
                    )
                if needsDetailedRig,
                   directChild(named: "full-rig", of: entity) == nil,
                   let athlete = makeDetailedRig(for: player) {
                    athlete.root.name = "full-rig"
                    entity.addChild(athlete.root)
                    sceneState?.retainAthleteBinding(athlete.joints)
                }
                if needsDetailedRig,
                   player.id == importedAthleteID,
                   sceneState?.importedAthlete == nil,
                   sceneState?.importedAthleteAttemptedPlayerID != player.id {
                    sceneState?.importedAthleteAttemptedPlayerID = player.id
                    if let imported = ReplayImportedAthleteProvider.makeNearFieldVisualIfReady(
                        for: player,
                        slot: 0,
                        at: time,
                        locomotion: locomotion
                    ) {
                        entity.addChild(imported.root)
                        sceneState?.importedAthlete = imported
                    }
                }
                let attachedImportedAthlete = sceneState?.importedAthlete
                let importedBelongsToPlayer = attachedImportedAthlete?.playerID == player.id
                    && attachedImportedAthlete?.root.parent === entity
                let hasImportedAthlete = importedBelongsToPlayer
                    && needsDetailedRig
                    && activeRagdollCue == nil
                let importedMotionIsSupported: Bool
                if hasImportedAthlete, let imported = attachedImportedAthlete {
                    importedMotionIsSupported = imported.updateMotionPresentation(
                        at: time,
                        using: player,
                        locomotion: locomotion
                    )
                } else {
                    if importedBelongsToPlayer {
                        attachedImportedAthlete?.root.isEnabled = false
                    }
                    importedMotionIsSupported = false
                }
                let usesImportedAthlete = hasImportedAthlete && importedMotionIsSupported
                // Player POV retains only its capped visible-neighbour set;
                // the wearer's hidden avatar must never be built or cached.
                // Other views keep the default rig plus the current selection,
                // preserving the inexpensive A → B → A return path.
                let retainsDetailedRig = needsDetailedRig
                    || (
                        viewMode != .firstPerson
                            && player.id == scenario.defaultPerspectiveID
                    )
                if let fullRig = directChild(named: "full-rig", of: entity) {
                    if retainsDetailedRig {
                        fullRig.isEnabled = needsDetailedRig && !hidesHeadMountedAvatar
                        setProceduralModelVisualsEnabled(
                            !usesImportedAthlete,
                            in: fullRig
                        )
                        setRagdollPhysicsEnabled(activeRagdollCue != nil, in: fullRig)
                    } else {
                        setProceduralModelVisualsEnabled(true, in: fullRig)
                        sceneState?.invalidateAthleteBinding(for: fullRig)
                        fullRig.removeFromParent()
                    }
                }
                let usesTableMarker = entity.isEnabled
                    && !needsDetailedRig
                    && !hidesHeadMountedAvatar
                    && !usesImportedAthlete
                directChild(named: "table-marker", of: entity)?.isEnabled = usesTableMarker

                let needsFullRigUpdate = entity.isEnabled
                    && needsDetailedRig
                    && !hidesHeadMountedAvatar
                    && !usesImportedAthlete
                if needsFullRigUpdate {
                    animateRig(
                        of: entity,
                        track: player,
                        time: time,
                        locomotion: locomotion,
                        cache: sceneState
                    )
                    if let activeRagdollCue {
                        applyRagdollPose(
                            PlayerRagdollPlayback.pose(for: activeRagdollCue, at: time),
                            influence: activeRagdollCue.influence(at: time),
                            to: entity,
                            cache: sceneState
                        )
                    }
                } else if usesTableMarker {
                    animateTableMarker(
                        of: entity,
                        track: player,
                        time: time,
                        locomotion: locomotion,
                        cache: sceneState
                    )
                }
            }
        }

        if let facing = directChild(named: "recorded-facing", of: root),
           let selectedPlayer = scenario.player(id: perspectiveID) {
            let pose = playerPosesByID[selectedPlayer.id] ?? selectedPlayer.pose(at: time)
            facing.position = [pose.position.x, 0, pose.position.z]
            facing.orientation = simd_quatf(
                angle: -pose.facingDegrees * .pi / 180,
                axis: [0, 1, 0]
            )
            facing.scale = SIMD3<Float>(repeating: 1)
            facing.isEnabled = viewMode == .firstPerson
            if let halo = directChild(named: "selection-halo", of: root) {
                halo.position = [pose.position.x, 0, pose.position.z]
                let haloScale: Float
                switch viewMode {
                case .firstPerson: haloScale = 1.8
                case .tacticalTable: haloScale = 2.2
                case .touchline: haloScale = 1.45
                case .positional: haloScale = 1.65
                }
                halo.scale = SIMD3<Float>(repeating: haloScale)
                // The halo's vertical beacon would intersect the head-mounted
                // view. The recorded-facing brackets are the sole POV direction cue.
                halo.isEnabled = viewMode != .positional && viewMode != .firstPerson
            }
        } else {
            directChild(named: "recorded-facing", of: root)?.isEnabled = false
            directChild(named: "selection-halo", of: root)?.isEnabled = false
        }

        let ballScale: Float = switch viewMode {
        case .firstPerson: 1
        case .tacticalTable: 3.2
        case .touchline: 1.5
        case .positional: 1.8
        }
        let showsBall = viewMode != .positional || effectiveTriangleMode == .visualise
        if let ball = directChild(named: "ball", of: root) {
            ball.position = [
                presentationBallPosition.x,
                isTriangleView ? 0.11 : max(ballPose.height, 0.11),
                presentationBallPosition.z
            ]
            ball.orientation = simd_quatf(
                angle: Float(time) * 1.8,
                axis: simd_normalize(SIMD3<Float>(1, 0.25, 0.1))
            )
            ball.scale = SIMD3<Float>(repeating: ballScale)
            ball.isEnabled = showsBall
        }
        if let shadow = directChild(named: "ball-shadow", of: root) {
            let lift = max(ballPose.height - 0.11, 0)
            let spread = 1 + min(lift * 0.16, 0.65)
            shadow.position = [presentationBallPosition.x, 0.006, presentationBallPosition.z]
            shadow.scale = [ballScale * spread, 1, ballScale * spread * 0.74]
            shadow.isEnabled = showsBall
        }

        let annotationCache = syncMarks(in: root, marks: marks)
        let isShapeProblem = isTriangleView
            && effectiveTriangleMode == .visualise
            && !showsIdealShape
        annotationCache?.marksRoot?.isEnabled = isTriangleView ? isShapeProblem : true

        let selectedBindingCandidate = selectedAnnotationID.flatMap {
            annotationCache?.bindingsByID[$0]
        }
        let selectedMark: CoachMark? = if !isDrawing,
                                          annotationCache?.marksRoot?.isEnabled == true,
                                          let selectedBindingCandidate,
                                          selectedBindingCandidate.mark.isVisible(at: time)
                                            || selectedAnnotationIsEditable,
                                          !isShapeProblem
                                            || selectedBindingCandidate.mark.kind == .danger {
            selectedBindingCandidate.mark
        } else {
            nil
        }
        let validDecisionSnapshot: ReplayDecisionSnapshot? = if !isDrawing,
                                                                let decisionSnapshot,
                                                                decisionSnapshot.scenarioID == scenario.id,
                                                                !decisionSnapshot.passingOptions.isEmpty,
                                                                scenario.player(id: decisionSnapshot.playerID) != nil {
            decisionSnapshot
        } else {
            nil
        }
        // Direct manipulation takes priority over comparison rails. This avoids
        // two bright, interactive teaching systems competing for the same pinch.
        let spatialFocus: SpatialReviewFocus = if let selectedMark {
            .annotation(mark: selectedMark, perspectiveID: perspectiveID)
        } else if let validDecisionSnapshot {
            .decision(DecisionPlayerFocusKey(snapshot: validDecisionSnapshot))
        } else {
            .normal
        }
        let decisionFocusIsVisible: Bool
        if case .decision = spatialFocus {
            decisionFocusIsVisible = true
        } else {
            decisionFocusIsVisible = false
        }
        let renderedAnnotationIDs = PlaybackSceneRenderBudget.visibleAnnotationIDs(
            in: annotationCache?.marks ?? [],
            priorityIndices: annotationCache?.renderPriorityIndices ?? [],
            at: time,
            selectedID: spatialFocus.selectedMarkID,
            selectedIsEditable: selectedAnnotationIsEditable,
            decisionReviewIsVisible: decisionFocusIsVisible
        )
        let focusedPlayerIDs = resolvedFocusedPlayerIDs(
            cache: annotationCache,
            focus: spatialFocus,
            scenario: scenario
        )

        if let annotationCache {
            for binding in annotationCache.bindings {
                guard let entity = binding.entity.value else { continue }
                let isRevealed = binding.mark.isVisible(at: time)
                let keepsEditableSelectionVisible = selectedAnnotationIsEditable
                    && spatialFocus.selectedMarkID == binding.mark.id
                entity.isEnabled = renderedAnnotationIDs.contains(binding.mark.id) && (isShapeProblem
                    ? (isRevealed || keepsEditableSelectionVisible)
                        && binding.mark.kind == .danger
                    : isRevealed || keepsEditableSelectionVisible)

                let isSelected = spatialFocus.selectedMarkID == binding.mark.id
                let opacity: Float = switch spatialFocus {
                case .normal:
                    1
                case .annotation:
                    isSelected ? 1 : selectedAnnotationContextOpacity
                case .decision:
                    decisionAnnotationContextOpacity
                }
                setAnnotationOpacity(opacity, on: entity)

                // During a focus, unrelated annotation hit volumes must not sit
                // in front of an endpoint handle or decision lane. Their faint
                // geometry remains as formation context and returns instantly.
                let acceptsAnnotationInput: Bool
                if isDrawing || !renderedAnnotationIDs.contains(binding.mark.id) {
                    acceptsAnnotationInput = false
                } else {
                    acceptsAnnotationInput = switch spatialFocus {
                    case .normal: true
                    // Once endpoint handles are present, the selected mark's
                    // broad path/card targets would overlap those handles and
                    // steal the drag as a non-editable `.body` gesture.
                    case .annotation: isSelected && !selectedAnnotationIsEditable
                    case .decision: false
                    }
                }
                binding.bodyTarget.value?.isEnabled = acceptsAnnotationInput
                binding.labelTarget.value?.isEnabled = acceptsAnnotationInput
            }
        }

        PlaybackSpatialLabels.updatePlayerLabels(
            in: root,
            scenario: scenario,
            posesByPlayerID: playerPosesByID,
            viewMode: viewMode,
            perspectiveID: perspectiveID,
            enabledPlayerIDs: labelEnabledPlayerIDs,
            firstPersonVisiblePlayerIDs: firstPersonVisibleIDs,
            focusedPlayerIDs: focusedPlayerIDs,
            acceptsInput: !suspendsPlayerPickingForAnnotationEdit
        )
        updateMarkLabels(
            cache: annotationCache,
            posesByPlayerID: playerPosesByID,
            viewMode: viewMode,
            perspectiveID: perspectiveID,
            focus: spatialFocus,
            time: time
        )
        let selectedBinding = spatialFocus.selectedMarkID.flatMap {
            annotationCache?.bindingsByID[$0]
        }
        AnnotationSceneAffordance.updateSelection(
            in: root,
            mark: selectedMark,
            viewMode: viewMode,
            observer: annotationObserver(
                posesByPlayerID: playerPosesByID,
                viewMode: viewMode,
                perspectiveID: perspectiveID
            ),
            attachedPlayerPosition: selectedMark?.playerID.flatMap {
                playerPosesByID[$0]?.position
            },
            selectedLabel: selectedBinding?.label.value,
            isEditable: selectedAnnotationIsEditable,
            time: time,
            isDrawing: isDrawing
        )
        updateAnnotationDraft(
            in: root,
            start: isDrawing ? draftStart : nil,
            end: isDrawing ? draftEnd : nil,
            kind: draftKind,
            viewMode: viewMode,
            observerID: perspectiveID,
            posesByPlayerID: playerPosesByID,
            time: time
        )
        DecisionOptionSceneOverlay.update(
            in: root,
            snapshot: selectedMark == nil ? validDecisionSnapshot : nil,
            scenario: scenario,
            viewMode: viewMode,
            isDrawing: isDrawing
        )

        if let targets = directChild(named: "targets-root", of: root) {
            targets.isEnabled = isTriangleView
                && (showsIdealShape || effectiveTriangleMode == .place)
            for target in targets.children {
                directChild(named: "visualise-marker", of: target)?.isEnabled =
                    effectiveTriangleMode == .visualise && showsIdealShape
                directChild(named: "place-marker", of: target)?.isEnabled = effectiveTriangleMode == .place
            }
        }
        directChild(named: "triangle-board-root", of: root)?.isEnabled =
            isTriangleView && effectiveTriangleMode == .visualise
        updateTriangleShape(
            in: root,
            scenario: scenario,
            time: time,
            mode: effectiveTriangleMode,
            visible: isTriangleView,
            showsIdeal: showsIdealShape
        )
        let showsFullField = viewMode == .tacticalTable || viewMode == .firstPerson
        if let pitch = directChild(named: "pitch", of: root) {
            pitch.isEnabled = viewMode != .positional
            directChild(named: "tactical-board-rim", of: pitch)?.isEnabled =
                viewMode == .tacticalTable
            directChild(named: "field-surface", of: pitch)?.isEnabled = showsFullField
            for stripe in 0..<10 where stripe.isMultiple(of: 2) {
                directChild(named: "field-stripe-\(stripe)", of: pitch)?.isEnabled = showsFullField
            }
            updatePitchContrast(
                in: pitch,
                usesFirstPersonContrast: viewMode == .firstPerson
            )
        }
        directChild(named: "annotation-surface", of: root)?.isEnabled = isDrawing
        updateLanes(in: root, scenario: scenario, time: time, visible: showsLaneLens)
        applyPresentation(
            root: root,
            scenario: scenario,
            time: time,
            mode: viewMode,
            perspectiveID: perspectiveID,
            positionalOriginTransform: positionalOriginTransform,
            triangleLockMode: effectiveTriangleMode
        )
    }

    private static func makePitch() -> Entity {
        let root = Entity()

        // A non-rendering bit records which material set is already applied,
        // keeping the contrast change out of the per-frame playback hot path.
        let contrastState = Entity()
        contrastState.name = "first-person-pitch-contrast-state"
        contrastState.isEnabled = false
        root.addChild(contrastState)

        // One tactical-only under-board gives the miniature pitch a readable
        // physical edge against passthrough furniture. It is disabled at human
        // scale so Player POV remains a ground plane, not a raised slab.
        let boardRim = ModelEntity(
            mesh: tacticalBoardRimMesh,
            materials: [
                SimpleMaterial(
                    color: UIColor(red: 0.012, green: 0.020, blue: 0.019, alpha: 0.96),
                    roughness: 0.92,
                    isMetallic: false
                )
            ]
        )
        boardRim.name = "tactical-board-rim"
        boardRim.position.y = -0.30
        boardRim.isEnabled = false
        root.addChild(boardRim)

        let field = ModelEntity(
            mesh: .generateBox(size: [pitchWidth, 0.05, pitchLength], cornerRadius: 0.18),
            materials: [UnlitMaterial(color: UIColor(red: 0.035, green: 0.19, blue: 0.105, alpha: 0.76))]
        )
        field.name = "field-surface"
        field.position.y = -0.035
        root.addChild(field)

        for stripe in 0..<10 where stripe.isMultiple(of: 2) {
            let stripeEntity = ModelEntity(
                mesh: .generateBox(size: [pitchWidth / 10, 0.007, pitchLength]),
                materials: [
                    UnlitMaterial(
                        color: UIColor(red: 0.048, green: 0.235, blue: 0.128, alpha: 0.48)
                    )
                ]
            )
            stripeEntity.name = "field-stripe-\(stripe)"
            stripeEntity.position = [(-pitchWidth / 2) + (pitchWidth / 20) + (Float(stripe) * pitchWidth / 10), 0.001, 0]
            root.addChild(stripeEntity)
        }

        let ivory = UIColor(red: 0.94, green: 0.93, blue: 0.82, alpha: 1)
        let markings = ModelEntity(
            mesh: ReplayPitchMeshLibrary.markingsAndGoals,
            materials: [UnlitMaterial(color: ivory, applyPostProcessToneMap: false)]
        )
        markings.name = "pitch-markings-and-goals"
        root.addChild(markings)
        return root
    }

    private static func updatePitchContrast(
        in pitch: Entity,
        usesFirstPersonContrast: Bool
    ) {
        guard let state = directChild(
            named: "first-person-pitch-contrast-state",
            of: pitch
        ), state.isEnabled != usesFirstPersonContrast else { return }
        state.isEnabled = usesFirstPersonContrast

        let stripeColor = usesFirstPersonContrast
            ? UIColor(red: 0.065, green: 0.285, blue: 0.145, alpha: 0.68)
            : UIColor(red: 0.048, green: 0.235, blue: 0.128, alpha: 0.48)
        for stripe in 0..<10 where stripe.isMultiple(of: 2) {
            if let entity = directChild(named: "field-stripe-\(stripe)", of: pitch) as? ModelEntity {
                entity.model?.materials = [
                    UnlitMaterial(color: stripeColor, applyPostProcessToneMap: false)
                ]
            }
        }

        let markingColor = usesFirstPersonContrast
            ? UIColor(red: 1, green: 0.995, blue: 0.95, alpha: 1)
            : UIColor(red: 0.94, green: 0.93, blue: 0.82, alpha: 1)
        updatePitchMarkingMaterials(in: pitch, color: markingColor)
    }

    private static func updatePitchMarkingMaterials(in parent: Entity, color: UIColor) {
        for child in parent.children {
            guard child.name != "field-surface",
                  child.name != "tactical-board-rim",
                  !child.name.hasPrefix("field-stripe-")
            else { continue }
            if let model = child as? ModelEntity {
                model.model?.materials = [
                    UnlitMaterial(color: color, applyPostProcessToneMap: false)
                ]
            }
            updatePitchMarkingMaterials(in: child, color: color)
        }
    }

    private static func addPenaltyArea(to root: Entity, atZ goalLine: Float, direction: Float, color: UIColor) {
        let edgeZ = goalLine + (direction * 16.5)
        root.addChild(segment(from: [-20.16, 0.016, goalLine], to: [-20.16, 0.016, edgeZ], width: 0.09, color: color))
        root.addChild(segment(from: [20.16, 0.016, goalLine], to: [20.16, 0.016, edgeZ], width: 0.09, color: color))
        root.addChild(segment(from: [-20.16, 0.016, edgeZ], to: [20.16, 0.016, edgeZ], width: 0.09, color: color))
    }

    private static func makeGoal(atZ z: Float) -> Entity {
        let root = Entity()
        let white = UIColor.white
        root.addChild(segment(from: [-3.66, 0, z], to: [-3.66, 2.44, z], width: 0.09, color: white))
        root.addChild(segment(from: [3.66, 0, z], to: [3.66, 2.44, z], width: 0.09, color: white))
        root.addChild(segment(from: [-3.66, 2.44, z], to: [3.66, 2.44, z], width: 0.09, color: white))
        return root
    }

    /// A small original panel treatment makes ball rotation and contact easier
    /// to read than a featureless white sphere. Geometry remains a single,
    /// bounded shared asset regardless of playback duration or squad size.
    private static func makeMatchBall() -> Entity {
        let root = Entity()
        root.name = "ball"

        let shell = ModelEntity(
            mesh: matchBallMesh,
            materials: [SimpleMaterial(color: .white, roughness: 0.74, isMetallic: false)]
        )
        shell.name = "ball-shell"
        root.addChild(shell)

        let panelMaterial = UnlitMaterial(
            color: UIColor(red: 0.035, green: 0.055, blue: 0.060, alpha: 1),
            applyPostProcessToneMap: false
        )
        let panelTransforms: [(SIMD3<Float>, simd_quatf)] = [
            ([0, 0.108, 0], simd_quatf(angle: 0, axis: [0, 1, 0])),
            ([0, -0.108, 0], simd_quatf(angle: 0, axis: [0, 1, 0])),
            ([0, 0, 0.108], simd_quatf(angle: .pi / 2, axis: [1, 0, 0])),
            ([0, 0, -0.108], simd_quatf(angle: .pi / 2, axis: [1, 0, 0])),
            ([0.108, 0, 0], simd_quatf(angle: .pi / 2, axis: [0, 0, 1])),
            ([-0.108, 0, 0], simd_quatf(angle: .pi / 2, axis: [0, 0, 1]))
        ]
        for (index, transform) in panelTransforms.enumerated() {
            let panel = ModelEntity(mesh: matchBallPanelMesh, materials: [panelMaterial])
            panel.name = "ball-panel-\(index)"
            panel.position = transform.0
            panel.orientation = transform.1
            root.addChild(panel)
        }
        return root
    }

    private static func makePlayer(
        _ player: PlayerTrack,
        includesDetailedRig: Bool = true,
        includesTableMarker: Bool = true
    ) -> PlayerSceneBuild {
        let root = Entity()
        root.name = "player-\(player.id)"
        var tableMarkerBinding: ReplayAthleteJointBinding?

        // A single invisible capsule makes the complete player selectable,
        // independent of LOD or which articulated limb the user looks at.
        let interactionTarget = Entity()
        interactionTarget.name = "interaction-target"
        interactionTarget.position.y = 0.95
        interactionTarget.components.set(InputTargetComponent(allowedInputTypes: .all))
        interactionTarget.components.set(
            CollisionComponent(
                shapes: [.generateCapsule(height: 1.78, radius: 0.34)],
                isStatic: false
            )
        )
        interactionTarget.components.set(HoverEffectComponent())
        var playerAccessibility = AccessibilityComponent()
        playerAccessibility.isAccessibilityElement = true
        playerAccessibility.label = LocalizedStringResource(
            stringLiteral: "Number \(player.shirtNumber), \(player.displayName)"
        )
        playerAccessibility.value = LocalizedStringResource(
            stringLiteral: "\(player.team.shortTitle), \(player.role)"
        )
        playerAccessibility.systemActions = [.activate]
        interactionTarget.components.set(playerAccessibility)
        root.addChild(interactionTarget)

        // Fictional, high-contrast kits keep team and body orientation legible
        // at tabletop scale. The design is original to Replay XI.
        let homeShirt = UIColor(red: 0.91, green: 0.95, blue: 0.98, alpha: 1)
        let homeTrim = UIColor(red: 0.025, green: 0.07, blue: 0.16, alpha: 1)
        let awayShirt = UIColor(red: 0.72, green: 0.045, blue: 0.075, alpha: 1)
        let awayTrim = UIColor(red: 0.075, green: 0.08, blue: 0.095, alpha: 1)
        let keeper = UIColor(red: 0.70, green: 0.94, blue: 0.12, alpha: 1)
        let shirtColor = player.isGoalkeeper ? keeper : (player.team == .home ? homeShirt : awayShirt)
        let trimColor = player.isGoalkeeper
            ? UIColor(red: 0.08, green: 0.12, blue: 0.06, alpha: 1)
            : (player.team == .home ? homeTrim : awayTrim)
        let appearanceIndex = (player.shirtNumber + (player.team == .away ? 2 : 0)) % 5
        let skinTones = [
            UIColor(red: 0.91, green: 0.70, blue: 0.54, alpha: 1),
            UIColor(red: 0.74, green: 0.49, blue: 0.32, alpha: 1),
            UIColor(red: 0.52, green: 0.31, blue: 0.20, alpha: 1),
            UIColor(red: 0.34, green: 0.195, blue: 0.145, alpha: 1),
            UIColor(red: 0.82, green: 0.59, blue: 0.41, alpha: 1)
        ]
        let hairTones = [
            UIColor(red: 0.055, green: 0.047, blue: 0.045, alpha: 1),
            UIColor(red: 0.18, green: 0.10, blue: 0.055, alpha: 1),
            UIColor(red: 0.34, green: 0.20, blue: 0.08, alpha: 1),
            UIColor(red: 0.07, green: 0.055, blue: 0.045, alpha: 1),
            UIColor(red: 0.46, green: 0.31, blue: 0.15, alpha: 1)
        ]
        let skin = skinTones[appearanceIndex]
        let hair = hairTones[appearanceIndex]
        let bootAccents = [
            UIColor(red: 0.92, green: 0.94, blue: 0.95, alpha: 1),
            UIColor(red: 0.74, green: 0.96, blue: 0.14, alpha: 1),
            UIColor(red: 0.98, green: 0.30, blue: 0.18, alpha: 1),
            UIColor(red: 0.16, green: 0.75, blue: 0.94, alpha: 1),
            UIColor(red: 0.94, green: 0.73, blue: 0.12, alpha: 1)
        ]

        let shirtMaterial = SimpleMaterial(color: shirtColor, roughness: 0.82, isMetallic: false)
        let trimMaterial = SimpleMaterial(color: trimColor, roughness: 0.76, isMetallic: false)
        let skinMaterial = SimpleMaterial(color: skin, roughness: 0.72, isMetallic: false)
        let hairMaterial = SimpleMaterial(color: hair, roughness: 0.94, isMetallic: false)
        let eyeWhiteMaterial = SimpleMaterial(
            color: UIColor(red: 0.91, green: 0.89, blue: 0.84, alpha: 1),
            roughness: 0.70,
            isMetallic: false
        )
        let eyeDarkMaterial = SimpleMaterial(
            color: UIColor(red: 0.045, green: 0.038, blue: 0.032, alpha: 1),
            roughness: 0.78,
            isMetallic: false
        )
        let mouthMaterial = SimpleMaterial(
            color: UIColor(red: 0.32, green: 0.10, blue: 0.095, alpha: 1),
            roughness: 0.82,
            isMetallic: false
        )
        let sockColor = player.isGoalkeeper
            ? keeper
            : (player.team == .home ? UIColor.white : awayShirt)
        let sockMaterial = SimpleMaterial(
            color: sockColor,
            roughness: 0.86,
            isMetallic: false
        )
        let bootMaterial = SimpleMaterial(
            color: UIColor(red: 0.018, green: 0.020, blue: 0.024, alpha: 1),
            roughness: 0.48,
            isMetallic: false
        )
        let bootAccentMaterial = SimpleMaterial(
            color: bootAccents[appearanceIndex],
            roughness: 0.62,
            isMetallic: false
        )

        if includesDetailedRig {
            let fullRig = Entity()
            fullRig.name = "full-rig"
            let heightScales: [Float] = [0.98, 1.015, 0.965, 1.035, 0.995]
            let widthScales: [Float] = [0.98, 1.02, 0.97, 1.035, 1]
            fullRig.scale = [widthScales[appearanceIndex], heightScales[appearanceIndex], 1]
            root.addChild(fullRig)

        let contactShadow = ModelEntity(
            mesh: rigContactShadowMesh,
            materials: [
                UnlitMaterial(
                    color: UIColor(red: 0, green: 0.015, blue: 0.01, alpha: 0.22),
                    applyPostProcessToneMap: false
                )
            ]
        )
        contactShadow.name = "contact-shadow"
        contactShadow.position.y = 0.006
        contactShadow.scale = [1, 1, 0.62]
        fullRig.addChild(contactShadow)

        let bodyRoot = Entity()
        bodyRoot.name = "body-root"
        fullRig.addChild(bodyRoot)

        let hips = Entity()
        hips.name = "hips"
        hips.position = [0, 0.90, 0]
        bodyRoot.addChild(hips)

        let shorts = ModelEntity(
            mesh: rigShortsMesh,
            materials: [trimMaterial]
        )
        shorts.name = "shorts"
        shorts.position.y = 0.025
        hips.addChild(shorts)

        let spine = Entity()
        spine.name = "spine"
        spine.position = [0, 0.14, 0]
        hips.addChild(spine)

        let waist = ModelEntity(mesh: rigBodyVolumeMesh, materials: [shirtMaterial])
        waist.name = "jersey-waist"
        waist.position.y = 0.055
        waist.scale = [0.190, 0.070, 0.124]
        spine.addChild(waist)

        let torso = ModelEntity(
            mesh: rigBodyVolumeMesh,
            materials: [shirtMaterial]
        )
        torso.position.y = 0.29
        torso.scale = [0.218, 0.265, 0.136]
        torso.name = "torso"
        spine.addChild(torso)

        let chest = ModelEntity(mesh: rigBodyVolumeMesh, materials: [shirtMaterial])
        chest.name = "chest"
        chest.position.y = 0.43
        chest.scale = [0.235, 0.142, 0.139]
        spine.addChild(chest)

        for x in [Float(-0.222), Float(0.222)] {
            // Keep the shaping panel in the jersey fabric. A high-contrast
            // material here read as two rigid bars at close POV distance.
            let sidePanel = ModelEntity(mesh: rigSidePanelMesh, materials: [shirtMaterial])
            sidePanel.name = x < 0 ? "left-kit-panel" : "right-kit-panel"
            sidePanel.position = [x, 0.25, 0]
            spine.addChild(sidePanel)
        }

        // Fine piping is intentionally geometric instead of texture-backed so
        // the fictional kit retains a crisp front direction at both close POV
        // and enlarged tactical-table scales.
        for x in [Float(-0.198), Float(0.198)] {
            let piping = ModelEntity(mesh: rigKitPipingMesh, materials: [trimMaterial])
            piping.name = x < 0 ? "left-kit-piping" : "right-kit-piping"
            piping.position = [x, 0.30, 0.137]
            spine.addChild(piping)
        }

        let collar = ModelEntity(
            mesh: rigCollarMesh,
            materials: [trimMaterial]
        )
        collar.name = "collar"
        collar.position = [0, 0.57, 0]
        spine.addChild(collar)

        let neck = ModelEntity(mesh: rigNeckMesh, materials: [skinMaterial])
        neck.name = "neck"
        neck.position = [0, 0.62, 0]
        spine.addChild(neck)

        let headRoot = Entity()
        headRoot.name = "head-root"
        headRoot.position = [0, 0.735, 0]
        spine.addChild(headRoot)

        let head = ModelEntity(
            mesh: rigHeadMesh,
            materials: [skinMaterial]
        )
        head.name = "head"
        head.scale = [0.91, 1.08, 0.94]
        headRoot.addChild(head)

        let jaw = ModelEntity(mesh: rigJawMesh, materials: [skinMaterial])
        jaw.name = "jaw"
        jaw.position = [0, -0.075, 0.012]
        jaw.scale = [0.91, 0.74, 0.86]
        headRoot.addChild(jaw)

        for x in [Float(-0.139), Float(0.139)] {
            let ear = ModelEntity(mesh: rigEarMesh, materials: [skinMaterial])
            ear.name = x < 0 ? "left-ear" : "right-ear"
            ear.position = [x, 0.005, 0]
            ear.scale = [0.58, 1, 0.45]
            headRoot.addChild(ear)
        }

        let nose = ModelEntity(mesh: rigNoseMesh, materials: [skinMaterial])
        nose.name = "nose"
        nose.position = [0, 0.005, 0.145]
        headRoot.addChild(nose)

        let hairCap = ModelEntity(
            mesh: rigHairMesh,
            materials: [hairMaterial]
        )
        hairCap.name = "hair"
        let hairHeights: [Float] = [0.40, 0.52, 0.34, 0.46, 0.58]
        hairCap.position = [0, 0.112, -0.008]
        hairCap.scale = [0.97, hairHeights[appearanceIndex], 0.98]
        headRoot.addChild(hairCap)

        // A restrained eye/brow/mouth treatment gives the procedural head a
        // readable gaze without attempting photorealism or using a likeness.
        for (side, x) in [("left", Float(-0.052)), ("right", Float(0.052))] {
            let eye = ModelEntity(mesh: rigBodyVolumeMesh, materials: [eyeWhiteMaterial])
            eye.name = "\(side)-eye"
            eye.position = [x, 0.025, 0.120]
            eye.scale = [0.022, 0.013, 0.009]
            headRoot.addChild(eye)

            let iris = ModelEntity(mesh: rigBodyVolumeMesh, materials: [eyeDarkMaterial])
            iris.name = "\(side)-iris"
            iris.position = [x, 0.025, 0.128]
            iris.scale = [0.008, 0.008, 0.004]
            headRoot.addChild(iris)

            let brow = ModelEntity(mesh: rigBrowMesh, materials: [hairMaterial])
            brow.name = "\(side)-brow"
            brow.position = [x, 0.057, 0.122]
            brow.orientation = simd_quatf(
                angle: side == "left" ? -0.08 : 0.08,
                axis: [0, 0, 1]
            )
            headRoot.addChild(brow)
        }

        let mouth = ModelEntity(mesh: rigMouthMesh, materials: [mouthMaterial])
        mouth.name = "mouth"
        mouth.position = [0, -0.057, 0.124]
        headRoot.addChild(mouth)

        for (side, x) in [("left", Float(-0.14)), ("right", Float(0.14))] {
            let hip = Entity()
            hip.name = "\(side)-hip"
            hip.position = [x, -0.07, 0]
            hips.addChild(hip)

            let shortLeg = ModelEntity(mesh: rigBodyVolumeMesh, materials: [trimMaterial])
            shortLeg.name = "\(side)-short-leg"
            shortLeg.position.y = -0.075
            shortLeg.scale = [0.108, 0.105, 0.118]
            hip.addChild(shortLeg)

            let thigh = ModelEntity(
                mesh: rigThighMesh,
                materials: [skinMaterial]
            )
            thigh.name = "\(side)-thigh"
            thigh.position.y = -0.225
            thigh.scale = [0.098, 0.190, 0.106]
            hip.addChild(thigh)

            let knee = Entity()
            knee.name = "\(side)-knee"
            knee.position.y = -0.39
            hip.addChild(knee)

            let kneeCap = ModelEntity(mesh: rigKneeMesh, materials: [skinMaterial])
            kneeCap.name = "\(side)-knee-cap"
            kneeCap.scale = [0.92, 1, 0.88]
            knee.addChild(kneeCap)

            let sockCuff = ModelEntity(mesh: rigSockCuffMesh, materials: [trimMaterial])
            sockCuff.name = "\(side)-sock-cuff"
            sockCuff.position.y = -0.035
            knee.addChild(sockCuff)

            let shin = ModelEntity(
                mesh: rigShinMesh,
                materials: [sockMaterial]
            )
            shin.name = "\(side)-shin"
            shin.position.y = -0.18
            shin.scale = [0.078, 0.190, 0.083]
            knee.addChild(shin)

            let calf = ModelEntity(mesh: rigBodyVolumeMesh, materials: [sockMaterial])
            calf.name = "\(side)-calf"
            calf.position = [0, -0.195, -0.020]
            calf.scale = [0.083, 0.115, 0.090]
            knee.addChild(calf)

            let ankle = Entity()
            ankle.name = "\(side)-ankle"
            ankle.position.y = -0.35
            knee.addChild(ankle)

            let boot = ModelEntity(
                mesh: rigBootMesh,
                materials: [bootMaterial]
            )
            boot.name = "\(side)-boot-upper"
            boot.position = [0, -0.035, 0.075]
            ankle.addChild(boot)

            let sole = ModelEntity(mesh: rigBootSoleMesh, materials: [bootMaterial])
            sole.name = "\(side)-boot-sole"
            sole.position = [0, -0.088, 0.075]
            ankle.addChild(sole)

            let bootAccent = ModelEntity(mesh: rigBootAccentMesh, materials: [bootAccentMaterial])
            bootAccent.name = "\(side)-boot-accent"
            bootAccent.position = [0, 0.014, 0.09]
            ankle.addChild(bootAccent)
        }

        for (side, x) in [("left", Float(-0.238)), ("right", Float(0.238))] {
            let shoulder = Entity()
            shoulder.name = "\(side)-shoulder"
            shoulder.position = [x, 0.49, 0]
            spine.addChild(shoulder)

            let deltoid = ModelEntity(mesh: rigBodyVolumeMesh, materials: [shirtMaterial])
            deltoid.name = "\(side)-deltoid"
            deltoid.position = [0, -0.030, 0]
            deltoid.scale = [0.092, 0.098, 0.101]
            shoulder.addChild(deltoid)

            let sleeve = ModelEntity(
                mesh: rigSleeveMesh,
                materials: [shirtMaterial]
            )
            sleeve.name = "\(side)-sleeve"
            sleeve.position.y = -0.085
            sleeve.scale = [0.086, 0.105, 0.094]
            shoulder.addChild(sleeve)

            let sleeveCuff = ModelEntity(mesh: rigSockCuffMesh, materials: [trimMaterial])
            sleeveCuff.name = "\(side)-sleeve-cuff"
            sleeveCuff.position.y = -0.175
            shoulder.addChild(sleeveCuff)

            let upperArm = ModelEntity(
                mesh: rigUpperArmMesh,
                materials: [player.isGoalkeeper ? shirtMaterial : skinMaterial]
            )
            upperArm.name = "\(side)-upper-arm"
            upperArm.position.y = -0.235
            upperArm.scale = [0.064, 0.110, 0.069]
            shoulder.addChild(upperArm)

            let elbow = Entity()
            elbow.name = "\(side)-elbow"
            elbow.position.y = -0.31
            shoulder.addChild(elbow)

            let elbowCap = ModelEntity(
                mesh: rigElbowMesh,
                materials: [player.isGoalkeeper ? shirtMaterial : skinMaterial]
            )
            elbowCap.name = "\(side)-elbow-cap"
            elbowCap.scale = [0.9, 1, 0.9]
            elbow.addChild(elbowCap)

            let forearm = ModelEntity(
                mesh: player.isGoalkeeper ? rigKeeperForearmMesh : rigForearmMesh,
                materials: [player.isGoalkeeper ? shirtMaterial : skinMaterial]
            )
            forearm.name = "\(side)-forearm"
            forearm.position.y = -0.135
            forearm.scale = player.isGoalkeeper
                ? [0.078, 0.150, 0.082]
                : [0.056, 0.146, 0.061]
            elbow.addChild(forearm)

            let wrist = Entity()
            wrist.name = "\(side)-wrist"
            wrist.position.y = -0.27
            elbow.addChild(wrist)

            let hand = ModelEntity(
                mesh: player.isGoalkeeper ? rigKeeperGloveMesh : rigHandMesh,
                materials: [player.isGoalkeeper ? trimMaterial : skinMaterial]
            )
            hand.name = "\(side)-hand"
            hand.position.y = player.isGoalkeeper ? -0.055 : -0.045
            if !player.isGoalkeeper {
                hand.scale = [0.82, 1.18, 0.72]
            }
            wrist.addChild(hand)
        }

        let badge = ModelEntity(mesh: rigBadgeMesh, materials: [bootAccentMaterial])
        badge.name = "kit-badge"
        badge.position = [-0.14, 0.40, 0.148]
        badge.orientation = simd_quatf(angle: .pi / 2, axis: [1, 0, 0])
        spine.addChild(badge)

        let numberColor = player.team == .home ? homeTrim : UIColor.white
        spine.addChild(
            makeShirtNumber(
                player.shirtNumber,
                color: numberColor
            )
        )
        spine.addChild(
            makeChestNumber(
                player.shirtNumber,
                color: numberColor
            )
        )

        }

        if includesTableMarker {
            let tableMarker: Entity
            if let athlete = try? ReplayAthleteFactory.make(for: player, lod: .far) {
                tableMarker = athlete.root
                tableMarkerBinding = athlete.joints
                tableMarker.name = "table-marker"
            } else {
                // Fail visually soft if a future procedural/asset revision
                // violates its geometry contract; playback and player picking
                // remain usable through the original economical silhouette.
                tableMarker = makeTableMarker(
                    shirtColor: shirtColor,
                    trimColor: trimColor,
                    limbColor: sockColor,
                    skinColor: skin,
                    facingColor: player.team == .home
                        ? UIColor(red: 0.22, green: 0.91, blue: 0.88, alpha: 1)
                        : UIColor(red: 1.0, green: 0.25, blue: 0.34, alpha: 1)
                )
            }
            tableMarker.isEnabled = false
            root.addChild(tableMarker)
        }

        return PlayerSceneBuild(
            root: root,
            tableMarkerBinding: tableMarkerBinding
        )
    }

    private static func makeDetailedRig(for player: PlayerTrack) -> ReplayAthleteInstance? {
        try? ReplayAthleteFactory.make(for: player, lod: .near)
    }

    private static func makeShirtNumber(_ number: Int, color: UIColor) -> Entity {
        let root = Entity()
        root.name = "shirt-number"
        root.position = [0, 0.29, -0.147]
        root.orientation = simd_quatf(angle: .pi, axis: [0, 1, 0])

        let textMesh: MeshResource
        if let cached = shirtNumberMeshCache[number] {
            textMesh = cached
        } else {
            let generated = MeshResource.generateText(
                String(number),
                extrusionDepth: 0.006,
                font: shirtNumberFont,
                containerFrame: .zero,
                alignment: .left,
                lineBreakMode: .byClipping
            )
            shirtNumberMeshCache[number] = generated
            textMesh = generated
        }
        let numberEntity = ModelEntity(
            mesh: textMesh,
            materials: [UnlitMaterial(color: color, applyPostProcessToneMap: false)]
        )
        numberEntity.name = "shirt-number-glyph"
        let bounds = numberEntity.visualBounds(relativeTo: numberEntity)
        numberEntity.position = [-bounds.center.x, -bounds.center.y, 0]
        root.addChild(numberEntity)
        return root
    }

    /// The floating identity card remains the primary tabletop label, while a
    /// small front number preserves football-kit identity in close Player POV
    /// views where the player is approaching rather than running away.
    private static func makeChestNumber(_ number: Int, color: UIColor) -> Entity {
        let root = makeShirtNumber(number, color: color)
        root.name = "chest-number"
        root.position = [0, 0.32, 0.149]
        root.orientation = simd_quatf(angle: 0, axis: [0, 1, 0])
        root.scale = SIMD3<Float>(repeating: 0.62)
        root.children.first?.name = "chest-number-glyph"
        return root
    }

    private static func makeTableMarker(
        shirtColor: UIColor,
        trimColor: UIColor,
        limbColor: UIColor,
        skinColor: UIColor,
        facingColor: UIColor
    ) -> Entity {
        let root = Entity()
        root.name = "table-marker"

        // Background players retain a recognisable football silhouette instead
        // of dropping to a pawn. Nine unlit draws keep all 22 players readable
        // while reserving the detailed articulated rig for tactical focus.
        let base = ModelEntity(
            mesh: tableMarkerBaseMesh,
            materials: [
                UnlitMaterial(
                    color: UIColor(red: 0, green: 0.015, blue: 0.01, alpha: 0.20),
                    applyPostProcessToneMap: false
                )
            ]
        )
        base.name = "table-marker-base"
        base.position.y = 0.028
        base.scale = [1, 1, 0.62]
        root.addChild(base)

        let facing = ModelEntity(
            mesh: tableMarkerFacingMesh,
            materials: [UnlitMaterial(color: facingColor, applyPostProcessToneMap: false)]
        )
        facing.name = "table-marker-facing"
        facing.position = [0, 0.060, 0.28]
        root.addChild(facing)

        let shorts = ModelEntity(
            mesh: rigShortsMesh,
            materials: [UnlitMaterial(color: trimColor, applyPostProcessToneMap: false)]
        )
        shorts.name = "table-marker-shorts"
        shorts.position.y = 0.91
        root.addChild(shorts)

        let body = ModelEntity(
            mesh: rigBodyVolumeMesh,
            materials: [UnlitMaterial(color: shirtColor, applyPostProcessToneMap: false)]
        )
        body.name = "table-marker-body"
        body.position.y = 1.28
        body.scale = [0.246, 0.27, 0.145]
        root.addChild(body)

        for (side, x) in [("left", Float(-0.14)), ("right", Float(0.14))] {
            let leg = Entity()
            leg.name = "table-marker-\(side)-leg"
            leg.position = [x, 0.87, 0]
            root.addChild(leg)

            let legVolume = ModelEntity(
                mesh: rigShinMesh,
                materials: [UnlitMaterial(color: limbColor, applyPostProcessToneMap: false)]
            )
            legVolume.name = "table-marker-\(side)-leg-volume"
            legVolume.position.y = -0.41
            legVolume.scale = [0.085, 0.38, 0.089]
            leg.addChild(legVolume)
        }

        for (side, x) in [("left", Float(-0.29)), ("right", Float(0.29))] {
            let arm = Entity()
            arm.name = "table-marker-\(side)-arm"
            arm.position = [x, 1.46, 0]
            root.addChild(arm)

            let armVolume = ModelEntity(
                mesh: rigForearmMesh,
                materials: [UnlitMaterial(color: shirtColor, applyPostProcessToneMap: false)]
            )
            armVolume.name = "table-marker-\(side)-arm-volume"
            armVolume.position.y = -0.25
            armVolume.scale = [0.072, 0.245, 0.078]
            arm.addChild(armVolume)
        }

        let head = ModelEntity(
            mesh: tableMarkerHeadMesh,
            materials: [UnlitMaterial(color: skinColor, applyPostProcessToneMap: false)]
        )
        head.name = "table-marker-head"
        head.position.y = 1.72
        head.scale = [0.92, 1.08, 0.95]
        root.addChild(head)

        return root
    }

    private static func makeSelectionHalo() -> Entity {
        let root = Entity()
        root.name = "selection-halo"

        let halo = ModelEntity(
            mesh: selectionHaloMesh,
            materials: [UnlitMaterial(color: UIColor(red: 0.78, green: 0.94, blue: 0.19, alpha: 0.52))]
        )
        halo.position.y = 0.02
        root.addChild(halo)

        let beacon = ModelEntity(
            mesh: .generateCylinder(height: 2.45, radius: 0.028),
            materials: [UnlitMaterial(color: UIColor(red: 0.78, green: 0.94, blue: 0.19, alpha: 0.34))]
        )
        beacon.position.y = 1.23
        root.addChild(beacon)

        let cap = ModelEntity(
            mesh: .generateSphere(radius: 0.105),
            materials: [UnlitMaterial(color: UIColor(red: 0.78, green: 0.94, blue: 0.19, alpha: 0.92))]
        )
        cap.position.y = 2.48
        root.addChild(cap)

        root.isEnabled = false
        return root
    }

    private static func makeRecordedFacingIndicator() -> Entity {
        let root = Entity()
        root.name = "recorded-facing"
        let signal = UIColor(red: 0.78, green: 0.94, blue: 0.19, alpha: 0.76)
        let axis = UIColor(red: 0.78, green: 0.94, blue: 0.19, alpha: 0.22)
        let depth: Float = 4.4
        let halfWidth: Float = 0.50
        let centreY: Float = 1.56
        let halfHeight: Float = 0.27
        let bracket: Float = 0.17
        let left = -halfWidth
        let right = halfWidth
        let low = centreY - halfHeight
        let high = centreY + halfHeight

        // A quiet ground axis communicates authored direction without putting
        // the wearer inside the previous full-screen wireframe cage.
        root.addChild(segment(from: [0, 0.035, 0.45], to: [0, 0.035, depth - 0.45], width: 0.022, color: axis))

        // Four corner brackets leave the actual football picture unobstructed.
        root.addChild(segment(from: [left, high - bracket, depth], to: [left, high, depth], width: 0.035, color: signal))
        root.addChild(segment(from: [left, high, depth], to: [left + bracket, high, depth], width: 0.035, color: signal))
        root.addChild(segment(from: [right - bracket, high, depth], to: [right, high, depth], width: 0.035, color: signal))
        root.addChild(segment(from: [right, high - bracket, depth], to: [right, high, depth], width: 0.035, color: signal))
        root.addChild(segment(from: [left, low, depth], to: [left, low + bracket, depth], width: 0.035, color: signal))
        root.addChild(segment(from: [left, low, depth], to: [left + bracket, low, depth], width: 0.035, color: signal))
        root.addChild(segment(from: [right - bracket, low, depth], to: [right, low, depth], width: 0.035, color: signal))
        root.addChild(segment(from: [right, low, depth], to: [right, low + bracket, depth], width: 0.035, color: signal))
        root.isEnabled = false
        return root
    }

    private static func makeFormationTarget(
        _ target: FormationTarget,
        allTargets: [FormationTarget]
    ) -> Entity {
        let root = Entity()
        root.name = "target-\(target.id)"
        root.position = [target.position.x, 0.025, target.position.z]

        let visualise = makeStationMarker(
            name: "visualise-marker",
            physicalRadius: TriangleLockLayout.visualiseRingRadius,
            physicalBeaconHeight: 0.16,
            scale: TriangleLockLayout.visualiseScale
        )
        root.addChild(visualise)

        let place = makeStationMarker(
            name: "place-marker",
            physicalRadius: TriangleLockLayout.placeTolerance,
            physicalBeaconHeight: 0.82,
            scale: TriangleLockLayout.placeScale(for: allTargets)
        )
        place.isEnabled = false
        root.addChild(place)
        return root
    }

    private static func makeStationMarker(
        name: String,
        physicalRadius: Float,
        physicalBeaconHeight: Float,
        scale: Float
    ) -> Entity {
        let root = Entity()
        root.name = name
        let signal = UIColor(red: 0.78, green: 0.94, blue: 0.19, alpha: 0.36)
        let centreColor = UIColor(red: 0.22, green: 0.91, blue: 0.88, alpha: 0.92)
        let radius = physicalRadius / scale

        let outer = ModelEntity(
            mesh: .generateCylinder(height: 0.018 / scale, radius: radius),
            materials: [UnlitMaterial(color: signal)]
        )
        root.addChild(outer)

        let inner = ModelEntity(
            mesh: .generateCylinder(height: 0.021 / scale, radius: radius * 0.70),
            materials: [UnlitMaterial(color: UIColor.black.withAlphaComponent(0.72))]
        )
        inner.position.y = 0.002 / scale
        root.addChild(inner)

        let centre = ModelEntity(
            mesh: .generateCylinder(height: 0.026 / scale, radius: 0.035 / scale),
            materials: [UnlitMaterial(color: centreColor)]
        )
        centre.position.y = 0.004 / scale
        root.addChild(centre)

        let beacon = ModelEntity(
            mesh: .generateCylinder(
                height: physicalBeaconHeight / scale,
                radius: 0.012 / scale
            ),
            materials: [UnlitMaterial(color: centreColor.withAlphaComponent(0.62))]
        )
        beacon.position.y = physicalBeaconHeight / (2 * scale)
        root.addChild(beacon)
        return root
    }

    private static func makeTriangleShapeRoot() -> Entity {
        let root = Entity()
        root.name = "triangle-shape-root"

        for index in 0..<3 {
            let edge = ModelEntity(
                mesh: .generateBox(size: [1, 1, 1], cornerRadius: 0.32),
                materials: [UnlitMaterial(color: UIColor.white.withAlphaComponent(0.75))]
            )
            edge.name = "triangle-edge-\(index)"
            root.addChild(edge)

            let node = ModelEntity(
                mesh: .generateCylinder(height: 1, radius: 0.5),
                materials: [UnlitMaterial(color: UIColor.white.withAlphaComponent(0.82))]
            )
            node.name = "triangle-node-\(index)"
            root.addChild(node)
        }
        root.isEnabled = false
        return root
    }

    private static func makeTriangleBoard(for scenario: ReplayScenario) -> Entity {
        let root = Entity()
        root.name = "triangle-board-root"
        guard !scenario.formationTargets.isEmpty else {
            root.isEnabled = false
            return root
        }

        let centre = PitchPoint(
            x: scenario.formationTargets.map(\.position.x).reduce(0, +)
                / Float(scenario.formationTargets.count),
            z: scenario.formationTargets.map(\.position.z).reduce(0, +)
                / Float(scenario.formationTargets.count)
        )
        let width: Float = 27
        let depth: Float = 18
        let board = ModelEntity(
            mesh: .generateBox(size: [width, 0.14, depth], cornerRadius: 0.55),
            materials: [UnlitMaterial(color: UIColor(red: 0.025, green: 0.115, blue: 0.075, alpha: 0.96))]
        )
        board.position = [centre.x, -0.10, centre.z]
        root.addChild(board)

        for index in 0..<3 where index.isMultiple(of: 2) {
            let stripe = ModelEntity(
                mesh: .generateBox(size: [width / 3, 0.018, depth], cornerRadius: 0.12),
                materials: [UnlitMaterial(color: UIColor(red: 0.055, green: 0.20, blue: 0.12, alpha: 0.72))]
            )
            stripe.position = [
                centre.x - (width / 3) + (Float(index) * width / 3),
                -0.022,
                centre.z
            ]
            root.addChild(stripe)
        }

        let borderColor = UIColor.white.withAlphaComponent(0.40)
        root.addChild(segment(
            from: [centre.x - width / 2, 0.01, centre.z - depth / 2],
            to: [centre.x + width / 2, 0.01, centre.z - depth / 2],
            width: 0.10,
            color: borderColor
        ))
        root.addChild(segment(
            from: [centre.x + width / 2, 0.01, centre.z - depth / 2],
            to: [centre.x + width / 2, 0.01, centre.z + depth / 2],
            width: 0.10,
            color: borderColor
        ))
        root.addChild(segment(
            from: [centre.x + width / 2, 0.01, centre.z + depth / 2],
            to: [centre.x - width / 2, 0.01, centre.z + depth / 2],
            width: 0.10,
            color: borderColor
        ))
        root.addChild(segment(
            from: [centre.x - width / 2, 0.01, centre.z + depth / 2],
            to: [centre.x - width / 2, 0.01, centre.z - depth / 2],
            width: 0.10,
            color: borderColor
        ))
        root.isEnabled = false
        return root
    }

    private static func updateTriangleShape(
        in root: Entity,
        scenario: ReplayScenario,
        time: TimeInterval,
        mode: TriangleLockMode,
        visible: Bool,
        showsIdeal: Bool
    ) {
        guard let shapeRoot = directChild(named: "triangle-shape-root", of: root) else { return }
        shapeRoot.isEnabled = visible && scenario.formationTargets.count >= 3
        guard shapeRoot.isEnabled else { return }

        let targets = Array(scenario.formationTargets.prefix(3))
        let points: [PitchPoint] = targets.map { target in
            if showsIdeal { return target.position }
            return scenario.player(id: target.playerID)?.pose(at: time).position ?? target.position
        }
        let scale = TriangleLockLayout.scale(for: mode, targets: scenario.formationTargets)
        let color = showsIdeal
            ? UIColor(red: 0.78, green: 0.94, blue: 0.19, alpha: 0.88)
            : UIColor(red: 1.0, green: 0.42, blue: 0.12, alpha: 0.68)
        let edgePhysicalWidth: Float = mode == .place ? 0.025 : 0.007
        let nodePhysicalRadius: Float = mode == .place ? 0.070 : 0.024

        for index in 0..<3 {
            let start = points[index]
            let end = points[(index + 1) % 3]
            if let edge = directChild(named: "triangle-edge-\(index)", of: shapeRoot) as? ModelEntity {
                let dx = end.x - start.x
                let dz = end.z - start.z
                let length = max(hypot(dx, dz), 0.001)
                edge.position = [(start.x + end.x) / 2, 0.030 / scale, (start.z + end.z) / 2]
                edge.scale = [edgePhysicalWidth / scale, edgePhysicalWidth / scale, length]
                edge.orientation = simd_quatf(angle: atan2(dx, dz), axis: [0, 1, 0])
                edge.model?.materials = [UnlitMaterial(color: color)]
            }

            if let node = directChild(named: "triangle-node-\(index)", of: shapeRoot) as? ModelEntity {
                node.position = [start.x, 0.020 / scale, start.z]
                node.scale = [
                    (nodePhysicalRadius * 2) / scale,
                    0.018 / scale,
                    (nodePhysicalRadius * 2) / scale
                ]
                node.model?.materials = [UnlitMaterial(color: color)]
            }
        }
    }

    /// Retains detailed-player membership until a challenger is materially
    /// nearer. This prevents two crossing tracks around the rank boundary from
    /// repeatedly constructing and destroying 29-part rigs.
    private static func resolvedFirstPersonDetailedPlayerIDs(
        cache: AnnotationSceneCache?,
        candidates: [String],
        posesByPlayerID: [String: PlayerPose],
        wearerID: String,
        limit: Int
    ) -> [String] {
        guard limit > 0,
              let wearerPose = posesByPlayerID[wearerID]
        else {
            cache?.firstPersonDetailedPlayerIDs.removeAll(keepingCapacity: true)
            return []
        }

        func distance(for id: String) -> Float {
            guard let pose = posesByPlayerID[id] else { return .greatestFiniteMagnitude }
            return ReplayGeometry.distance(wearerPose.position, pose.position)
        }

        var selected = cache?.firstPersonDetailedPlayerIDs.filter {
            $0 != wearerID && candidates.contains($0) && posesByPlayerID[$0] != nil
        } ?? []
        if selected.count > limit {
            selected.sort { distance(for: $0) < distance(for: $1) }
            selected.removeLast(selected.count - limit)
        }
        for candidate in candidates where selected.count < limit && !selected.contains(candidate) {
            selected.append(candidate)
        }

        let switchMargin: Float = 1.25
        for candidate in candidates where !selected.contains(candidate) && !selected.isEmpty {
            guard let worstIndex = selected.indices.max(by: {
                distance(for: selected[$0]) < distance(for: selected[$1])
            }) else { continue }
            if distance(for: candidate) + switchMargin < distance(for: selected[worstIndex]) {
                selected[worstIndex] = candidate
            }
        }
        cache?.firstPersonDetailedPlayerIDs = selected
        return selected
    }

    /// Returns a stable, hard-bounded set of articulated neighbours for the
    /// head-mounted view. Distance is measured from the wearer's authored
    /// telemetry position; player ID breaks exact ties so seeks and peers choose
    /// the same tracks independently of RealityKit child ordering.
    private static func nearestVisiblePlayerIDs(
        players: [PlayerTrack],
        posesByPlayerID: [String: PlayerPose],
        wearerID: String,
        limit: Int
    ) -> [String] {
        guard limit > 0, let wearerPose = posesByPlayerID[wearerID] else { return [] }
        var nearest: [(id: String, distance: Float)] = []
        nearest.reserveCapacity(limit)
        for player in players {
            guard player.id != wearerID,
                  let pose = posesByPlayerID[player.id]
            else { continue }
            let candidate = (
                id: player.id,
                distance: ReplayGeometry.distance(wearerPose.position, pose.position)
            )
            let insertionIndex = nearest.firstIndex { current in
                candidate.distance < current.distance
                    || (candidate.distance == current.distance && candidate.id < current.id)
            } ?? nearest.endIndex
            guard insertionIndex < limit else { continue }
            nearest.insert(candidate, at: insertionIndex)
            if nearest.count > limit {
                nearest.removeLast()
            }
        }
        return nearest.map(\.id)
    }

    /// Shape Focus teaches one pressure relationship at a time. The authored
    /// danger mark is the cover-shadow axis, so the closest opponent to its
    /// midpoint is the single defender that should remain in the tabletop view.
    private static func primaryShapeDefenderID(
        in scenario: ReplayScenario,
        time: TimeInterval
    ) -> String? {
        guard scenario.kind == .shapeLab else { return nil }

        let referencePoint: PitchPoint
        if let danger = scenario.coachMarks.first(where: { $0.kind == .danger }) {
            referencePoint = danger.start.interpolated(to: danger.end, fraction: 0.5)
        } else if !scenario.formationTargets.isEmpty {
            referencePoint = PitchPoint(
                x: scenario.formationTargets.map(\.position.x).reduce(0, +)
                    / Float(scenario.formationTargets.count),
                z: scenario.formationTargets.map(\.position.z).reduce(0, +)
                    / Float(scenario.formationTargets.count)
            )
        } else {
            return nil
        }

        return scenario.awayPlayers.min {
            ReplayGeometry.distance($0.pose(at: time).position, referencePoint)
                < ReplayGeometry.distance($1.pose(at: time).position, referencePoint)
        }?.id
    }

    private static func makeLaneRoot() -> Entity {
        let root = Entity()
        for index in 0..<3 {
            let lane = ModelEntity(
                mesh: .generateBox(size: [0.17, 0.035, 1], cornerRadius: 0.08),
                materials: [UnlitMaterial(color: UIColor.white.withAlphaComponent(0.55))]
            )
            lane.name = "candidate-lane-\(index)"
            root.addChild(lane)
        }
        return root
    }

    private static func updateLanes(in root: Entity, scenario: ReplayScenario, time: TimeInterval, visible: Bool) {
        guard let lanesRoot = directChild(named: "lanes-root", of: root) else { return }
        lanesRoot.isEnabled = visible
        guard visible,
              let source = scenario.homePlayers.first(where: { $0.shirtNumber == 7 })
        else { return }

        let targetNumbers = [2, 8, 6]
        let start = source.pose(at: time).position
        let defenders = scenario.awayPlayers.map { $0.pose(at: time).position }

        for (index, shirtNumber) in targetNumbers.enumerated() {
            guard let lane = directChild(named: "candidate-lane-\(index)", of: lanesRoot) as? ModelEntity,
                  let target = scenario.homePlayers.first(where: { $0.shirtNumber == shirtNumber })
            else { continue }
            let end = target.pose(at: time).position
            let clearance = ReplayGeometry.laneClearance(from: start, to: end, defenders: defenders)
            let color: UIColor
            if shirtNumber == 6 {
                color = UIColor.white.withAlphaComponent(0.48)
            } else if clearance > 1.75 {
                color = UIColor(red: 0.22, green: 0.91, blue: 0.88, alpha: 0.78)
            } else {
                color = UIColor(red: 1.0, green: 0.25, blue: 0.34, alpha: 0.72)
            }
            lane.model?.materials = [UnlitMaterial(color: color)]
            setSegmentTransform(lane, from: start, to: end, y: 0.09)
        }
    }

    /// Marks are immutable values, so ordered full-value equality is a safe
    /// revision check. The 30 Hz steady state performs no UUID-string, Set, or
    /// Dictionary construction and reuses direct weak bindings for visibility
    /// and label updates. A rare revision rebuild is bounded to the shared
    /// collaboration limit and deliberately handles same-ID content edits.
    @discardableResult
    private static func syncMarks(
        in root: Entity,
        marks: [CoachMark]
    ) -> AnnotationSceneCache? {
        guard let cache = annotationCache(for: root),
              let marksRoot = cache.marksRoot
        else { return nil }
        let renderedCount = min(marks.count, ReplayStore.maximumSharedCoachMarks)
        guard !cache.matches(marks, count: renderedCount) else { return cache }
        let needsRenderPriorityRebuild = cache.renderPriorityIndices.count != renderedCount
            || cache.marks.count != renderedCount
            || (0..<renderedCount).contains(where: { index in
                cache.marks[index].id != marks[index].id
                    || cache.marks[index].revealTime != marks[index].revealTime
                    || cache.marks[index].hideTime != marks[index].hideTime
            })

        // Resolve revisions per stable mark ID. Dragging mutates only
        // transforms, relabelling replaces one tree, append creates one tree,
        // and undo removes one tree. This prevents a single edit near the
        // collaboration cap from rebuilding all 128 RealityKit hierarchies.
        if cache.bindingsByID.count == cache.bindings.count {
            var refreshedMarks: [CoachMark] = []
            var refreshedBindings: [CachedMarkBinding] = []
            var refreshedByID: [UUID: CachedMarkBinding] = [:]
            refreshedMarks.reserveCapacity(renderedCount)
            refreshedBindings.reserveCapacity(renderedCount)
            refreshedByID.reserveCapacity(renderedCount)

            for index in 0..<renderedCount {
                let incoming = marks[index]
                let refreshed: CachedMarkBinding
                if let existing = cache.bindingsByID[incoming.id],
                   let entity = existing.entity.value {
                    let canRetainTree = existing.mark.kind == incoming.kind
                        && existing.mark.label == incoming.label
                        && updateMarkGeometry(
                            in: entity,
                            from: existing.mark,
                            to: incoming,
                            bodyTarget: existing.bodyTarget.value
                        )
                    if canRetainTree {
                        refreshed = CachedMarkBinding(
                            mark: incoming,
                            entity: existing.entity,
                            label: existing.label,
                            labelTarget: existing.labelTarget,
                            bodyTarget: existing.bodyTarget,
                            playerAttachment: existing.playerAttachment
                        )
                    } else {
                        let replacement = makeMark(incoming)
                        entity.removeFromParent()
                        marksRoot.addChild(replacement)
                        refreshed = makeCachedMarkBinding(
                            mark: incoming,
                            entity: replacement
                        )
                    }
                } else {
                    let replacement = makeMark(incoming)
                    marksRoot.addChild(replacement)
                    refreshed = makeCachedMarkBinding(
                        mark: incoming,
                        entity: replacement
                    )
                }
                refreshedMarks.append(incoming)
                refreshedBindings.append(refreshed)
                refreshedByID[incoming.id] = refreshed
            }

            if refreshedByID.count == renderedCount {
                for previous in cache.bindings
                    where refreshedByID[previous.mark.id] == nil {
                    previous.entity.value?.removeFromParent()
                }
                cache.marks = refreshedMarks
                cache.bindings = refreshedBindings
                cache.bindingsByID = refreshedByID
                if needsRenderPriorityRebuild {
                    cache.renderPriorityIndices = PlaybackSceneRenderBudget.priorityIndices(
                        for: refreshedMarks
                    )
                }
                return cache
            }
        }

        // ChildCollection is a live view. Snapshot it before detaching or the
        // iterator can skip siblings, leaving stale entities that force another
        // rebuild and keep old visibility state alive.
        for child in Array(marksRoot.children) {
            child.removeFromParent()
        }

        var renderedMarks: [CoachMark] = []
        var bindings: [CachedMarkBinding] = []
        var bindingsByID: [UUID: CachedMarkBinding] = [:]
        renderedMarks.reserveCapacity(renderedCount)
        bindings.reserveCapacity(renderedCount)
        bindingsByID.reserveCapacity(renderedCount)
        for index in 0..<renderedCount {
            let mark = marks[index]
            let entity = makeMark(mark)
            marksRoot.addChild(entity)
            renderedMarks.append(mark)
            let binding = makeCachedMarkBinding(mark: mark, entity: entity)
            bindings.append(binding)
            bindingsByID[mark.id] = binding
        }
        cache.marks = renderedMarks
        cache.bindings = bindings
        cache.bindingsByID = bindingsByID
        cache.renderPriorityIndices = PlaybackSceneRenderBudget.priorityIndices(
            for: renderedMarks
        )
        return cache
    }

    private static func makeCachedMarkBinding(
        mark: CoachMark,
        entity: Entity
    ) -> CachedMarkBinding {
        let label = directChild(named: "annotation-label", of: entity)
        return CachedMarkBinding(
            mark: mark,
            entity: WeakEntityReference(entity),
            label: WeakEntityReference(label),
            labelTarget: WeakEntityReference(
                label.flatMap {
                    directChild(named: AnnotationSceneAffordance.labelTargetName, of: $0)
                }
            ),
            bodyTarget: WeakEntityReference(
                directChild(named: AnnotationSceneAffordance.bodyTargetName, of: entity)
            ),
            playerAttachment: WeakEntityReference(
                directChild(named: AnnotationSceneAffordance.playerAttachmentName, of: entity)
            )
        )
    }

    private static func annotationCache(for root: Entity) -> AnnotationSceneCache? {
        annotationCacheClock &+= 1
        let key = ObjectIdentifier(root)
        if let cached = annotationSceneCaches[key],
           cached.root === root,
           cached.marksRoot != nil {
            cached.lastAccess = annotationCacheClock
            return cached
        }

        guard let marksRoot = directChild(named: "marks-root", of: root) else { return nil }

        let cache = AnnotationSceneCache(
            root: root,
            marksRoot: marksRoot,
            lastAccess: annotationCacheClock
        )
        annotationSceneCaches[key] = cache

        // Root creation/replacement is cold-path work. Remove released scenes,
        // then bound even unusually long editor sessions to a tiny LRU set.
        annotationSceneCaches = annotationSceneCaches.filter { $0.value.root != nil }
        while annotationSceneCaches.count > maximumCachedAnnotationRoots,
              let victim = annotationSceneCaches.min(by: {
                  $0.value.lastAccess < $1.value.lastAccess
              })?.key,
              victim != key {
            annotationSceneCaches.removeValue(forKey: victim)
        }
        return cache
    }

    /// Recomputes tactical label membership only on a semantic focus change.
    /// Scrubbing and animation frames reuse the cached Set, while mark edits
    /// naturally invalidate it because `CoachMark` is a value in the key.
    private static func resolvedFocusedPlayerIDs(
        cache: AnnotationSceneCache?,
        focus: SpatialReviewFocus,
        scenario: ReplayScenario
    ) -> Set<String>? {
        guard let cache else { return nil }
        guard cache.playerLabelFocus != focus else {
            return cache.focusedPlayerIDs
        }
        cache.playerLabelFocus = focus

        switch focus {
        case .normal:
            cache.focusedPlayerIDs = nil

        case let .decision(key):
            var ids: Set<String> = [key.sourceID]
            ids.reserveCapacity(PlaybackSpatialLabels.tacticalFocusedPlayerLabelLimit)
            for receiver in [
                key.receiver0,
                key.receiver1,
                key.receiver2,
                key.receiver3,
            ] {
                guard ids.count < PlaybackSpatialLabels.tacticalFocusedPlayerLabelLimit,
                      let receiver,
                      scenario.player(id: receiver) != nil
                else { continue }
                ids.insert(receiver)
            }
            cache.focusedPlayerIDs = ids

        case let .annotation(mark, perspectiveID):
            var ids: Set<String> = [perspectiveID]
            ids.reserveCapacity(PlaybackSpatialLabels.tacticalFocusedPlayerLabelLimit)
            if let attachedID = mark.playerID,
               scenario.player(id: attachedID) != nil {
                ids.insert(attachedID)
            }

            // Freeze membership to the mark's own timestamp. Player tags do
            // not flicker in and out as a coach drags the scrubber underneath
            // an open annotation inspector.
            let sampleTime = min(max(mark.revealTime, 0), scenario.duration)
            var ranked: [(id: String, score: Float)] = []
            ranked.reserveCapacity(scenario.players.count)
            for player in scenario.players where !ids.contains(player.id) {
                let point = player.pose(at: sampleTime).position
                ranked.append((
                    id: player.id,
                    score: annotationFocusDistance(point: point, mark: mark)
                ))
            }
            ranked.sort {
                $0.score == $1.score ? $0.id < $1.id : $0.score < $1.score
            }
            for candidate in ranked {
                guard ids.count < PlaybackSpatialLabels.tacticalFocusedPlayerLabelLimit else {
                    break
                }
                ids.insert(candidate.id)
            }
            cache.focusedPlayerIDs = ids
        }
        return cache.focusedPlayerIDs
    }

    private static func annotationFocusDistance(
        point: PitchPoint,
        mark: CoachMark
    ) -> Float {
        switch mark.kind {
        case .space, .playerLabel:
            return ReplayGeometry.distance(point, mark.start)
        case .run, .pass, .danger:
            let vx = mark.end.x - mark.start.x
            let vz = mark.end.z - mark.start.z
            let lengthSquared = (vx * vx) + (vz * vz)
            guard lengthSquared > 0.000_1 else {
                return ReplayGeometry.distance(point, mark.start)
            }
            let projection = min(max(
                (((point.x - mark.start.x) * vx) + ((point.z - mark.start.z) * vz))
                    / lengthSquared,
                0
            ), 1)
            let closest = PitchPoint(
                x: mark.start.x + (vx * projection),
                z: mark.start.z + (vz * projection)
            )
            return ReplayGeometry.distance(point, closest)
        }
    }

    private static func setAnnotationOpacity(_ opacity: Float, on entity: Entity) {
        if entity.components[OpacityComponent.self]?.opacity != opacity {
            entity.components.set(OpacityComponent(opacity: opacity))
        }
    }

    private static func makeMark(_ mark: CoachMark) -> Entity {
        let root = Entity()
        root.name = "mark-\(mark.id.uuidString)"
        let color: UIColor
        switch mark.kind {
        case .run: color = UIColor(red: 1.0, green: 0.42, blue: 0.12, alpha: 0.92)
        case .pass: color = UIColor(red: 0.22, green: 0.91, blue: 0.88, alpha: 0.92)
        case .danger: color = UIColor(red: 1.0, green: 0.25, blue: 0.34, alpha: 0.9)
        case .space: color = UIColor(red: 0.78, green: 0.94, blue: 0.19, alpha: 0.78)
        case .playerLabel: color = UIColor(red: 0.78, green: 0.94, blue: 0.19, alpha: 0.92)
        }

        let tagText = compactAnnotationText(for: mark)
        let label = PlaybackSpatialLabels.makeAnnotationTag(text: tagText, color: color)
        AnnotationSceneAffordance.configureLabelTarget(
            label,
            for: mark,
            renderedText: tagText
        )
        root.addChild(label)
        root.addChild(AnnotationSceneAffordance.makeBodyTarget(for: mark))

        if mark.kind == .playerLabel {
            root.addChild(AnnotationSceneAffordance.makePlayerAttachment())
            return root
        }

        if mark.kind == .space {
            let radius = max(ReplayGeometry.distance(mark.start, mark.end), 1.1)
            let ring = ModelEntity(
                mesh: ReplayPitchMeshLibrary.annotationSpaceRing,
                materials: [
                    UnlitMaterial(color: color, applyPostProcessToneMap: false)
                ]
            )
            ring.name = "annotation-mark-space"
            ring.position = [mark.start.x, 0.072, mark.start.z]
            ring.scale = [radius, 1, radius]
            root.addChild(ring)
            return root
        }

        let pieces = mark.kind == .danger ? 7 : 1
        for index in 0..<pieces {
            let startFraction = Float(index) / Float(pieces)
            let endFraction = min(startFraction + (mark.kind == .danger ? 0.075 : 1), 1)
            let start = mark.start.interpolated(to: mark.end, fraction: startFraction)
            let end = mark.start.interpolated(to: mark.end, fraction: endFraction)
            let line = ModelEntity(
                mesh: annotationMarkSegmentMesh,
                materials: [UnlitMaterial(color: color)]
            )
            line.name = "annotation-mark-segment-\(index)"
            setSegmentTransform(line, from: start, to: end, y: 0.10)
            root.addChild(line)
        }

        let direction = SIMD3<Float>(mark.end.x - mark.start.x, 0, mark.end.z - mark.start.z)
        let arrow = ModelEntity(
            mesh: annotationMarkArrowMesh,
            materials: [UnlitMaterial(color: color)]
        )
        arrow.name = "annotation-mark-arrow"
        arrow.position = [mark.end.x, 0.12, mark.end.z]
        arrow.isEnabled = simd_length(direction) > 0.05
        if arrow.isEnabled {
            arrow.orientation = simd_quatf(from: SIMD3<Float>(0, 1, 0), to: simd_normalize(direction))
        }
        root.addChild(arrow)
        return root
    }

    /// Updates a structurally compatible mark without allocating new meshes or
    /// replacing its label. Returns false when the existing tree is incomplete,
    /// allowing the cold-path rebuild to repair it safely.
    private static func updateMarkGeometry(
        in entity: Entity,
        from previous: CoachMark,
        to incoming: CoachMark,
        bodyTarget: Entity?
    ) -> Bool {
        guard let bodyTarget else { return false }
        AnnotationSceneAffordance.configureBodyTarget(
            bodyTarget,
            for: incoming,
            labelPosition: nil
        )

        switch incoming.kind {
        case .playerLabel:
            return directChild(
                named: AnnotationSceneAffordance.playerAttachmentName,
                of: entity
            ) != nil

        case .space:
            guard let disc = directChild(named: "annotation-mark-space", of: entity) else {
                return false
            }
            let newRadius = max(ReplayGeometry.distance(incoming.start, incoming.end), 1.1)
            disc.position = [incoming.start.x, 0.072, incoming.start.z]
            disc.scale = [newRadius, 1, newRadius]
            return true

        case .run, .pass, .danger:
            let pieces = incoming.kind == .danger ? 7 : 1
            for index in 0..<pieces {
                guard let line = directChild(
                    named: "annotation-mark-segment-\(index)",
                    of: entity
                ) else { return false }
                let startFraction = Float(index) / Float(pieces)
                let endFraction = min(
                    startFraction + (incoming.kind == .danger ? 0.075 : 1),
                    1
                )
                setSegmentTransform(
                    line,
                    from: incoming.start.interpolated(
                        to: incoming.end,
                        fraction: startFraction
                    ),
                    to: incoming.start.interpolated(
                        to: incoming.end,
                        fraction: endFraction
                    ),
                    y: 0.10
                )
            }

            guard let arrow = directChild(named: "annotation-mark-arrow", of: entity) else {
                return false
            }
            let direction = SIMD3<Float>(
                incoming.end.x - incoming.start.x,
                0,
                incoming.end.z - incoming.start.z
            )
            arrow.position = [incoming.end.x, 0.12, incoming.end.z]
            arrow.isEnabled = simd_length(direction) > 0.05
            if arrow.isEnabled {
                arrow.orientation = simd_quatf(
                    from: SIMD3<Float>(0, 1, 0),
                    to: simd_normalize(direction)
                )
            }
            return true
        }
    }

    private static func makeAnnotationDraftRoot() -> Entity {
        let root = Entity()
        root.name = "annotation-draft-root"
        root.isEnabled = false

        let visual = Entity()
        visual.name = "annotation-draft-visual"

        // Four short segments keep the chosen start point precise without the
        // previous filled cylinder reading as a large orange obstruction.
        let ring = Entity()
        ring.name = "annotation-draft-ring"
        let segmentMaterial = UnlitMaterial(
            color: UIColor(red: 1, green: 0.42, blue: 0.12, alpha: 0.86),
            applyPostProcessToneMap: false
        )
        let segments: [(SIMD3<Float>, Float)] = [
            ([0, 0.055, 0.38], 0),
            ([0, 0.055, -0.38], 0),
            ([0.38, 0.055, 0], .pi / 2),
            ([-0.38, 0.055, 0], .pi / 2)
        ]
        for (index, segment) in segments.enumerated() {
            let reticleSegment = ModelEntity(
                mesh: annotationDraftSegmentMesh,
                materials: [segmentMaterial]
            )
            reticleSegment.name = "annotation-draft-segment-\(index)"
            reticleSegment.position = segment.0
            reticleSegment.orientation = simd_quatf(
                angle: segment.1,
                axis: [0, 1, 0]
            )
            ring.addChild(reticleSegment)
        }
        visual.addChild(ring)

        let pin = ModelEntity(
            mesh: annotationDraftPinMesh,
            materials: [
                UnlitMaterial(
                    color: UIColor(red: 1, green: 0.42, blue: 0.12, alpha: 0.98),
                    applyPostProcessToneMap: false
                )
            ]
        )
        pin.name = "annotation-draft-pin"
        pin.position.y = 0.18
        visual.addChild(pin)

        let stem = ModelEntity(
            mesh: annotationDraftStemMesh,
            materials: [
                UnlitMaterial(
                    color: UIColor(red: 1, green: 0.42, blue: 0.12, alpha: 0.84),
                    applyPostProcessToneMap: false
                )
            ]
        )
        stem.name = "annotation-draft-stem"
        stem.position.y = 0.24
        visual.addChild(stem)

        root.addChild(visual)

        // Native gaze/pinch dragging previews the complete instruction before
        // release. These three reusable entities cover directional marks and
        // zones without allocating geometry during the gesture.
        let stroke = Entity()
        stroke.name = "annotation-draft-stroke"
        stroke.isEnabled = false

        let path = ModelEntity(
            mesh: annotationMarkSegmentMesh,
            materials: [segmentMaterial]
        )
        path.name = "annotation-draft-stroke-path"
        stroke.addChild(path)

        let arrow = ModelEntity(
            mesh: annotationMarkArrowMesh,
            materials: [segmentMaterial]
        )
        arrow.name = "annotation-draft-stroke-arrow"
        stroke.addChild(arrow)

        let zone = ModelEntity(
            mesh: ReplayPitchMeshLibrary.annotationSpaceRing,
            materials: [segmentMaterial]
        )
        zone.name = "annotation-draft-stroke-zone"
        stroke.addChild(zone)
        root.addChild(stroke)

        let labels = Entity()
        labels.name = "annotation-label"
        for candidateKind in [CoachMarkKind.run, .pass, .danger, .space] {
            let label = PlaybackSpatialLabels.makeAnnotationTag(
                text: "\(candidateKind.title.uppercased()) · START",
                color: draftColor(for: candidateKind)
            )
            label.name = "annotation-draft-label-\(candidateKind.rawValue)"
            label.isEnabled = false
            labels.addChild(label)
        }
        root.addChild(labels)
        return root
    }

    private static func updateAnnotationDraft(
        in root: Entity,
        start: PitchPoint?,
        end: PitchPoint?,
        kind: CoachMarkKind,
        viewMode: ReplayViewMode,
        observerID: String,
        posesByPlayerID: [String: PlayerPose],
        time: TimeInterval
    ) {
        guard let draft = directChild(named: "annotation-draft-root", of: root) else { return }
        guard let start, kind.requiresTwoPitchPoints else {
            draft.isEnabled = false
            return
        }

        draft.isEnabled = true
        draft.position = [start.x, 0, start.z]
        let pulse = 1 + (sin(Float(time) * 5.2) * 0.08)
        let visualScale: Float = switch viewMode {
        case .firstPerson: 1
        case .tacticalTable: 3.77
        case .touchline: 1.7
        case .positional: 2.5
        }
        if let visual = directChild(named: "annotation-draft-visual", of: draft) {
            visual.scale = SIMD3<Float>(repeating: visualScale * pulse)
        }

        configureAnnotationDraftStroke(
            in: draft,
            start: start,
            end: end,
            kind: kind
        )

        guard let label = directChild(named: "annotation-label", of: draft) else { return }
        var hasActiveLabel = false
        var needsVisualRestyle = true
        for candidate in [CoachMarkKind.run, .pass, .danger, .space] {
            guard let candidateLabel = directChild(
                named: "annotation-draft-label-\(candidate.rawValue)",
                of: label
            ) else { continue }
            if candidate == kind, candidateLabel.isEnabled {
                needsVisualRestyle = false
            }
            candidateLabel.isEnabled = candidate == kind
            hasActiveLabel = hasActiveLabel || candidate == kind
        }
        label.isEnabled = hasActiveLabel
        if needsVisualRestyle {
            let color = draftColor(for: kind)
            for index in 0..<4 {
                if let segment = draft.findEntity(
                    named: "annotation-draft-segment-\(index)"
                ) as? ModelEntity {
                    segment.model?.materials = [
                        UnlitMaterial(color: color, applyPostProcessToneMap: false)
                    ]
                }
            }
            for name in ["annotation-draft-pin", "annotation-draft-stem"] {
                if let element = draft.findEntity(named: name) as? ModelEntity {
                    element.model?.materials = [
                        UnlitMaterial(color: color, applyPostProcessToneMap: false)
                    ]
                }
            }
            for name in [
                "annotation-draft-stroke-path",
                "annotation-draft-stroke-arrow",
                "annotation-draft-stroke-zone",
            ] {
                if let element = draft.findEntity(named: name) as? ModelEntity {
                    element.model?.materials = [
                        UnlitMaterial(color: color, applyPostProcessToneMap: false)
                    ]
                }
            }
        }
        let observer: PitchPoint = switch viewMode {
        case .firstPerson: posesByPlayerID[observerID]?.position ?? .zero
        case .tacticalTable: PitchPoint(x: 0, z: 100)
        case .touchline: PitchPoint(x: -70, z: 0)
        case .positional: .zero
        }
        let labelScale: Float = switch viewMode {
        case .firstPerson: 0.48
        case .tacticalTable: 4.10
        case .touchline: 1.55
        case .positional: 2.35
        }
        let labelHeight: Float = switch viewMode {
        case .firstPerson: 1.10
        case .tacticalTable: 1.65
        case .touchline: 1.35
        case .positional: 1.55
        }
        label.position = [0, labelHeight, 0]
        label.orientation = simd_quatf(
            angle: atan2(observer.x - start.x, observer.z - start.z),
            axis: [0, 1, 0]
        )
        label.scale = SIMD3<Float>(repeating: labelScale)
    }

    private static func configureAnnotationDraftStroke(
        in draft: Entity,
        start: PitchPoint,
        end: PitchPoint?,
        kind: CoachMarkKind
    ) {
        guard let stroke = directChild(named: "annotation-draft-stroke", of: draft),
              let end,
              end.x.isFinite,
              end.z.isFinite else {
            directChild(named: "annotation-draft-stroke", of: draft)?.isEnabled = false
            return
        }
        let localEnd = PitchPoint(x: end.x - start.x, z: end.z - start.z)
        let distance = ReplayGeometry.distance(.zero, localEnd)
        guard distance > 0.05 else {
            stroke.isEnabled = false
            return
        }

        stroke.isEnabled = true
        let path = directChild(named: "annotation-draft-stroke-path", of: stroke)
        let arrow = directChild(named: "annotation-draft-stroke-arrow", of: stroke)
        let zone = directChild(named: "annotation-draft-stroke-zone", of: stroke)

        if kind == .space {
            path?.isEnabled = false
            arrow?.isEnabled = false
            zone?.isEnabled = true
            zone?.position = [0, 0.078, 0]
            zone?.orientation = simd_quatf()
            zone?.scale = [max(distance, 0.05), 1, max(distance, 0.05)]
            return
        }

        zone?.isEnabled = false
        path?.isEnabled = true
        arrow?.isEnabled = true
        if let path {
            setSegmentTransform(
                path,
                from: .zero,
                to: localEnd,
                y: 0.11
            )
        }
        let direction = SIMD3<Float>(localEnd.x, 0, localEnd.z)
        arrow?.position = [localEnd.x, 0.13, localEnd.z]
        arrow?.orientation = simd_quatf(
            from: SIMD3<Float>(0, 1, 0),
            to: simd_normalize(direction)
        )
    }

    private static func draftColor(for kind: CoachMarkKind) -> UIColor {
        switch kind {
        case .run: UIColor(red: 1.0, green: 0.42, blue: 0.12, alpha: 1)
        case .pass: UIColor(red: 0.22, green: 0.91, blue: 0.88, alpha: 1)
        case .danger: UIColor(red: 1.0, green: 0.25, blue: 0.34, alpha: 1)
        case .space, .playerLabel: UIColor(red: 0.78, green: 0.94, blue: 0.19, alpha: 1)
        }
    }

    private static func compactAnnotationText(for mark: CoachMark) -> String {
        let prefix: String = switch mark.kind {
        case .run: "RUN · "
        case .pass: "PASS · "
        default: ""
        }
        let complete = prefix + mark.label
        guard complete.count > 22 else { return complete }
        return String(complete.prefix(21)) + "…"
    }

    private static func updateMarkLabels(
        cache: AnnotationSceneCache?,
        posesByPlayerID: [String: PlayerPose],
        viewMode: ReplayViewMode,
        perspectiveID: String,
        focus: SpatialReviewFocus,
        time: TimeInterval
    ) {
        guard let cache else { return }
        let observer = annotationObserver(
            posesByPlayerID: posesByPlayerID,
            viewMode: viewMode,
            perspectiveID: perspectiveID
        )
        let scale: Float = switch viewMode {
        case .firstPerson: 0.48
        case .tacticalTable: 4.50
        case .touchline: 1.70
        case .positional: 2.60
        }
        let visibleFirstPersonLabels = viewMode == .firstPerson
            ? firstPersonAnnotationLabelIDs(
                in: cache,
                selectedAnnotationID: focus.selectedMarkID,
                at: time
            )
            : nil

        for binding in cache.bindings {
            let mark = binding.mark
            guard let label = binding.label.value else { continue }
            guard mark.isVisible(at: time) || focus.selectedMarkID == mark.id else {
                label.isEnabled = false
                continue
            }
            label.isEnabled = switch focus {
            case .normal:
                visibleFirstPersonLabels?.contains(mark.id) ?? true
            case .annotation:
                focus.selectedMarkID == mark.id
            case .decision:
                false
            }
            guard label.isEnabled else { continue }
            let anchor: PitchPoint
            if mark.kind == .playerLabel {
                anchor = mark.playerID.flatMap { posesByPlayerID[$0]?.position } ?? mark.end
            } else {
                let pathAnchor = mark.start.interpolated(to: mark.end, fraction: 0.70)
                let dx = mark.end.x - mark.start.x
                let dz = mark.end.z - mark.start.z
                let length = hypot(dx, dz)
                if length > 0.001 {
                    let side: Float = switch mark.kind {
                    case .run, .danger: 1
                    case .pass, .space: -1
                    case .playerLabel: 0
                    }
                    let offset: Float = 0.65 * side
                    anchor = PitchPoint(
                        x: pathAnchor.x - ((dz / length) * offset),
                        z: pathAnchor.z + ((dx / length) * offset)
                    )
                } else {
                    anchor = pathAnchor
                }
            }
            let playerLabelHeight: Float = switch viewMode {
            case .firstPerson: 2.45
            case .tacticalTable: 9.40
            case .touchline: 4.20
            case .positional: 6.40
            }
            label.position = [
                anchor.x,
                mark.kind == .playerLabel ? playerLabelHeight : 0.78,
                anchor.z
            ]
            label.orientation = simd_quatf(
                angle: atan2(observer.x - anchor.x, observer.z - anchor.z),
                axis: [0, 1, 0]
            )
            let resolvedScale = viewMode == .firstPerson
                ? PlaybackSpatialLabels.firstPersonAnnotationScale(
                    forDistance: ReplayGeometry.distance(observer, anchor)
                )
                : scale
            label.scale = SIMD3<Float>(repeating: resolvedScale)
            if mark.kind == .playerLabel {
                if let attachment = binding.playerAttachment.value {
                    AnnotationSceneAffordance.updatePlayerAttachment(
                        attachment,
                        anchor: anchor,
                        labelHeight: playerLabelHeight,
                        viewMode: viewMode
                    )
                }
                if let target = binding.bodyTarget.value {
                    AnnotationSceneAffordance.configureBodyTarget(
                        target,
                        for: mark,
                        labelPosition: label.position
                    )
                    target.orientation = label.orientation
                    target.scale = label.scale
                }
            }
        }
    }

    /// Keeps first-person teaching text sparse without hiding the 3D lines.
    /// The selected annotation always wins, followed by the latest visible
    /// marks. A fixed-size insertion keeps this update O(n) and allocation-light.
    private static func firstPersonAnnotationLabelIDs(
        in cache: AnnotationSceneCache,
        selectedAnnotationID: UUID?,
        at time: TimeInterval
    ) -> FirstPersonAnnotationLabelSelection {
        let limit = PlaybackSpatialLabels.firstPersonVisibleAnnotationLimit
        guard limit > 0 else { return FirstPersonAnnotationLabelSelection() }

        var selectedVisibleID: UUID?
        if let selectedAnnotationID,
           let selected = cache.bindingsByID[selectedAnnotationID]?.mark,
           selected.isVisible(at: time) {
            selectedVisibleID = selectedAnnotationID
        }

        var latestFirst: (id: UUID, time: TimeInterval)?
        var latestSecond: (id: UUID, time: TimeInterval)?
        for binding in cache.bindings {
            let mark = binding.mark
            guard mark.id != selectedVisibleID, mark.isVisible(at: time) else { continue }
            let candidate = (id: mark.id, time: mark.revealTime)
            if latestFirst == nil || candidate.time > latestFirst!.time {
                latestSecond = latestFirst
                latestFirst = candidate
            } else if latestSecond == nil || candidate.time > latestSecond!.time {
                latestSecond = candidate
            }
        }

        if let selectedVisibleID {
            return FirstPersonAnnotationLabelSelection(
                first: selectedVisibleID,
                second: limit > 1 ? latestFirst?.id : nil
            )
        }
        return FirstPersonAnnotationLabelSelection(
            first: latestFirst?.id,
            second: limit > 1 ? latestSecond?.id : nil
        )
    }

    private static func annotationObserver(
        posesByPlayerID: [String: PlayerPose],
        viewMode: ReplayViewMode,
        perspectiveID: String
    ) -> PitchPoint {
        switch viewMode {
        case .firstPerson: posesByPlayerID[perspectiveID]?.position ?? .zero
        case .tacticalTable: PitchPoint(x: 0, z: 100)
        case .touchline: PitchPoint(x: -70, z: 0)
        case .positional: .zero
        }
    }

    private static func segment(from start: SIMD3<Float>, to end: SIMD3<Float>, width: Float, color: UIColor) -> ModelEntity {
        let entity = ModelEntity(
            mesh: .generateBox(size: [width, width, 1], cornerRadius: width * 0.42),
            materials: [UnlitMaterial(color: color)]
        )
        let startPoint = PitchPoint(x: start.x, z: start.z)
        let endPoint = PitchPoint(x: end.x, z: end.z)
        setSegmentTransform(entity, from: startPoint, to: endPoint, y: (start.y + end.y) / 2)
        if abs(end.y - start.y) > abs(end.z - start.z) + abs(end.x - start.x) {
            let length = simd_length(end - start)
            entity.position = (start + end) / 2
            entity.scale = [1, 1, max(length, 0.001)]
            entity.orientation = simd_quatf(from: SIMD3<Float>(0, 0, 1), to: simd_normalize(end - start))
        }
        return entity
    }

    private static func setSegmentTransform(_ entity: Entity, from start: PitchPoint, to end: PitchPoint, y: Float) {
        let dx = end.x - start.x
        let dz = end.z - start.z
        let length = max(hypot(dx, dz), 0.001)
        entity.position = [(start.x + end.x) / 2, y, (start.z + end.z) / 2]
        entity.scale = [1, 1, length]
        entity.orientation = simd_quatf(angle: atan2(dx, dz), axis: [0, 1, 0])
    }

    /// The economical squad LOD remains a genuinely animated football body.
    /// It shares the telemetry-derived gait clock with the articulated rig,
    /// but moves its existing nine render pieces instead of adding more draws.
    private static func animateTableMarker(
        of entity: Entity,
        track: PlayerTrack,
        time: TimeInterval,
        locomotion: PlayerLocomotionSample,
        cache: AnnotationSceneCache?
    ) {
        guard let marker = directChild(named: "table-marker", of: entity),
              marker.isEnabled else { return }

        // The production far LOD retains the exact articulated joint graph,
        // just with seven combined visual parts. It can therefore reuse the
        // same seek-stable gait as the near athlete instead of a second,
        // visibly different background animation.
        if directChild(named: "body-root", of: marker) != nil {
            animateAthleteRig(
                marker,
                track: track,
                time: time,
                locomotion: locomotion,
                cache: cache
            )
            return
        }

        // Compatibility fallback for a future mesh-generation failure.
        guard let shorts = directChild(named: "table-marker-shorts", of: marker),
              let body = directChild(named: "table-marker-body", of: marker),
              let head = directChild(named: "table-marker-head", of: marker),
              let leftLeg = directChild(named: "table-marker-left-leg", of: marker),
              let rightLeg = directChild(named: "table-marker-right-leg", of: marker),
              let leftArm = directChild(named: "table-marker-left-arm", of: marker),
              let rightArm = directChild(named: "table-marker-right-arm", of: marker)
        else { return }

        let motion = locomotion.motion
        let effort = locomotion.effort
        let cycle = sin(motion.locomotionPhase)
        let doubleCycle = sin(motion.locomotionPhase * 2)
        let movingScale: Float = effort > 0.015 ? 1 : 0
        let swing = cycle * (0.10 + (effort * 0.50)) * movingScale
        let bob = abs(doubleCycle) * 0.024 * effort
        let sideSway = cycle * 0.014 * effort

        shorts.position.y = 0.91 + bob
        shorts.position.x = sideSway
        body.position.y = 1.28 + bob
        body.position.x = sideSway * 0.72
        head.position.y = 1.72 + bob
        head.position.x = sideSway * 0.45
        leftLeg.position.y = 0.87 + bob
        rightLeg.position.y = 0.87 + bob
        leftArm.position.y = 1.46 + bob
        rightArm.position.y = 1.46 + bob

        leftLeg.orientation = simd_quatf(angle: swing * 0.78, axis: [1, 0, 0])
        rightLeg.orientation = simd_quatf(angle: -swing * 0.78, axis: [1, 0, 0])
        leftArm.orientation = simd_quatf(angle: -swing * 0.82, axis: [1, 0, 0])
        rightArm.orientation = simd_quatf(angle: swing * 0.82, axis: [1, 0, 0])
        body.orientation = simd_quatf(
            angle: -0.055 * effort,
            axis: [1, 0, 0]
        ) * simd_quatf(angle: doubleCycle * 0.020 * effort, axis: [0, 0, 1])
        head.orientation = simd_quatf(angle: 0.035 * effort, axis: [1, 0, 0])
            * simd_quatf(angle: -doubleCycle * 0.012 * effort, axis: [0, 0, 1])
    }

    private static func animateRig(
        of entity: Entity,
        track: PlayerTrack,
        time: TimeInterval,
        locomotion: PlayerLocomotionSample,
        cache: AnnotationSceneCache?
    ) {
        guard let fullRig = directChild(named: "full-rig", of: entity),
              fullRig.isEnabled else { return }
        animateAthleteRig(
            fullRig,
            track: track,
            time: time,
            locomotion: locomotion,
            cache: cache
        )
    }

    /// Keeps one high-fidelity pilot attached to the currently admitted track.
    /// The scene cache owns its paused animation controllers; retaining only
    /// the RealityKit root would make deterministic timeline seeks impossible.
    private static func reconcileImportedAthlete(
        cache: AnnotationSceneCache?,
        admittedPlayerID: String?,
        playerEntitiesByID: [String: Entity]
    ) {
        guard let cache else { return }
        if let current = cache.importedAthlete,
           current.playerID == admittedPlayerID,
           current.root.parent != nil {
            return
        }
        if cache.importedAthlete == nil,
           cache.importedAthleteAttemptedPlayerID == admittedPlayerID {
            // A failed fail-soft admission must not retry an asset clone every
            // presentation frame. Changing the focused player re-arms it.
            return
        }

        if let previous = cache.importedAthlete {
            previous.root.removeFromParent()
            if let player = playerEntitiesByID[previous.playerID],
               let fullRig = directChild(named: "full-rig", of: player) {
                setProceduralModelVisualsEnabled(true, in: fullRig)
            }
        }
        cache.importedAthlete = nil
        cache.importedAthleteAttemptedPlayerID = nil
    }

    /// Hide only rendered procedural pieces while the imported skin is active.
    /// Joint entities stay alive as stable interaction and future ragdoll
    /// proxies; when the pilot is detached every procedural model is restored.
    private static func setProceduralModelVisualsEnabled(
        _ isEnabled: Bool,
        in entity: Entity
    ) {
        if let model = entity as? ModelEntity {
            model.isEnabled = isEnabled
        }
        for child in entity.children {
            setProceduralModelVisualsEnabled(isEnabled, in: child)
        }
    }

    private static func animateAthleteRig(
        _ fullRig: Entity,
        track: PlayerTrack,
        time: TimeInterval,
        locomotion: PlayerLocomotionSample,
        cache: AnnotationSceneCache?
    ) {
        guard let binding = athleteBinding(for: fullRig, cache: cache) else { return }
        let pose = ReplayAthleteMotion.locomotionPose(
            for: track,
            at: time,
            locomotion: locomotion
        )
        ReplayAthleteMotion.apply(pose, to: binding)
    }

    private static func athleteBinding(
        for rig: Entity,
        cache: AnnotationSceneCache?
    ) -> ReplayAthleteJointBinding? {
        if let cache {
            return cache.athleteBinding(for: rig)
        }
        // A malformed externally-constructed root can omit the normal scene
        // cache. Preserve fail-soft rendering without making that exceptional
        // path part of the supported 30 Hz match pipeline.
        return try? ReplayAthleteJointBinding(root: rig)
    }

    /// Adds physical query bodies only for the focused impact subject. They
    /// remain kinematic because the deterministic playback solver owns every
    /// transform; a dynamic frame clock would make rewind and shared seek
    /// disagree across headsets. Transition-only setup keeps normal XI
    /// telemetry free of per-player physics cost.
    private static func setRagdollPhysicsEnabled(_ isEnabled: Bool, in fullRig: Entity) {
        let markerName = "ragdoll-physics-active"
        let existingMarker = directChild(named: markerName, of: fullRig)

        if isEnabled {
            guard existingMarker == nil else { return }
            let filter = CollisionFilter(group: ragdollCollisionGroup, mask: .default)
            for part in ragdollPhysicsParts {
                guard let entity = fullRig.findEntity(named: part.name) else { continue }
                entity.components.set(
                    CollisionComponent(
                        shapes: [part.shape],
                        mode: .default,
                        filter: filter
                    )
                )
                var body = PhysicsBodyComponent(
                    shapes: [part.shape],
                    mass: part.mass,
                    material: ragdollPhysicsMaterial,
                    mode: .kinematic
                )
                body.isAffectedByGravity = false
                body.linearDamping = 0.72
                body.angularDamping = 0.84
                entity.components.set(body)
                entity.components.set(PhysicsMotionComponent())
            }
            let marker = Entity()
            marker.name = markerName
            fullRig.addChild(marker)
        } else {
            guard let existingMarker else { return }
            for part in ragdollPhysicsParts {
                guard let entity = fullRig.findEntity(named: part.name) else { continue }
                entity.components.remove(PhysicsMotionComponent.self)
                entity.components.remove(PhysicsBodyComponent.self)
                entity.components.remove(CollisionComponent.self)
            }
            existingMarker.removeFromParent()
        }
    }

    /// Blends the fixed-step rigid-body result over the telemetry gait. At zero
    /// influence the authored locomotion hierarchy is untouched; at one the
    /// torso centre, constrained joints and turf contact are entirely driven by
    /// the ragdoll solve.
    private static func applyRagdollPose(
        _ pose: PlayerRagdollPose,
        influence: Float,
        to player: Entity,
        cache: AnnotationSceneCache?
    ) {
        guard influence > 0,
              let fullRig = directChild(named: "full-rig", of: player),
              let binding = athleteBinding(for: fullRig, cache: cache)
        else { return }
        ReplayAthleteMotion.apply(ragdoll: pose, influence: influence, to: binding)
    }

    /// A centered, fixed-time telemetry sample avoids instantaneous effort
    /// jumps at authored keyframes. It is independent of render cadence and
    /// playback direction, so seeking to an instant always yields one pose.
    static func gaitEffort(for track: PlayerTrack, at time: TimeInterval) -> Float {
        track.locomotion(at: time).effort
    }

    /// Normalized signed turn rate sampled symmetrically around playback time.
    /// It adds a subtle pelvis bank and anticipatory head turn while remaining
    /// stable under reverse playback and arbitrary seeks.
    static func turningResponse(for track: PlayerTrack, at time: TimeInterval) -> Float {
        track.locomotion(at: time).turnResponse
    }

    private static func directChild(named name: String, of entity: Entity) -> Entity? {
        entity.children.first { $0.name == name }
    }

    private static func applyPresentation(
        root: Entity,
        scenario: ReplayScenario,
        time: TimeInterval,
        mode: ReplayViewMode,
        perspectiveID: String,
        positionalOriginTransform: simd_float4x4?,
        triangleLockMode: TriangleLockMode
    ) {
        switch mode {
        case .firstPerson:
            // Follow only the selected player's translation. The pitch keeps a
            // constant room-space orientation, so authored yaw/pitch can never
            // steer the headset view: the wearer remains free to look anywhere.
            // Moving the world by the inverse player offset places the viewer at
            // the player's head-height body origin throughout the run.
            let pitchRotation = simd_quatf(angle: .pi, axis: [0, 1, 0])
            let playerPose = scenario.player(id: perspectiveID)?.pose(at: time)
            let playerOffset = SIMD3<Float>(
                playerPose?.position.x ?? 0,
                0,
                playerPose?.position.z ?? 0
            )
            let rotatedPlayerOffset = pitchRotation.act(playerOffset)
            root.scale = SIMD3<Float>(repeating: 1)
            root.orientation = pitchRotation
            root.position = -rotatedPlayerOffset

        case .tacticalTable:
            // A large, gently raked coaching board keeps player targets and
            // annotations visible above the transport instead of presenting a
            // tiny, nearly edge-on table in the distance.
            root.scale = SIMD3<Float>(repeating: 0.0255)
            root.orientation = simd_quatf(angle: 0.22, axis: [1, 0, 0])
            root.position = [0, 0.92, -3.15]

        case .touchline:
            root.scale = SIMD3<Float>(repeating: 0.060)
            root.orientation = simd_quatf(angle: .pi / 2, axis: [0, 1, 0])
            root.position = [0, 0.02, -4.1]

        case .positional:
            let targetPoints = scenario.formationTargets.map(\.position)
            let centre: PitchPoint
            if targetPoints.isEmpty {
                centre = .zero
            } else {
                centre = PitchPoint(
                    x: targetPoints.map(\.x).reduce(0, +) / Float(targetPoints.count),
                    z: targetPoints.map(\.z).reduce(0, +) / Float(targetPoints.count)
                )
            }
            let resolvedTriangleMode: TriangleLockMode =
                triangleLockMode == .place && positionalOriginTransform != nil
                ? .place
                : .visualise
            let scale = TriangleLockLayout.scale(
                for: resolvedTriangleMode,
                targets: scenario.formationTargets
            )
            root.scale = SIMD3<Float>(repeating: scale)
            let layoutRotation = simd_quatf(angle: .pi, axis: [0, 1, 0])
            root.orientation = layoutRotation
            let rotatedCentre = root.orientation.act(SIMD3<Float>(centre.x, 0, centre.z) * scale)
            if resolvedTriangleMode == .place, let positionalOriginTransform {
                let pitchOrigin = Transform(matrix: positionalOriginTransform)
                root.orientation = pitchOrigin.rotation * layoutRotation
                let forwardOffset = pitchOrigin.rotation.act(
                    SIMD3<Float>(0, 0, -TriangleLockLayout.placeForwardOffset)
                )
                let anchoredCentre = root.orientation.act(SIMD3<Float>(centre.x, 0, centre.z) * scale)
                root.position = pitchOrigin.translation + forwardOffset + SIMD3<Float>(0, 0.015, 0) - anchoredCentre
            } else {
                root.position = SIMD3<Float>(
                    TriangleLockLayout.visualiseHorizontalOffset,
                    TriangleLockLayout.visualiseHeight,
                    -TriangleLockLayout.visualiseForwardOffset
                ) - rotatedCentre
            }
        }
    }
}
