import CryptoKit
import Foundation
import RealityKit
import UIKit
import simd

enum ReplaySkinnedAthleteError: Error, Equatable {
    case missingResource(String)
    case invalidHash(String)
    case invalidSkeleton
    case invalidMaterials
    case notPrepared
}

/// Licensed single-skeleton body. Poses are written directly, never advanced
/// by animation controllers, so rewind and shared replay clocks agree.
@MainActor
enum ReplaySkinnedAthleteProvider {
    enum Detail: Hashable, Sendable { case near, lowDetail }
    static let visualRootName = "skinned-athlete-visual"
    /// Historical default-cap diagnostic. Full squad is an explicit scene
    /// preference; it does not expand the close-player rig budget.
    static let maximumConcurrentInstances = ReplayPlayerDetail.balanced.maximumSkinnedPlayers
    static let assetSHA256 = "7cfb694888f111928643e8aca7041d21925f5d55f3f5adbd353a972ca255e772"
    static let motionSHA256 = "d30a7379b81a4b0ea3fef5ebd20ad101911ab4fd521a5be1f6c00c0804f59ce4"
    static let slowRunSHA256 = "865b7d45ce021731adb8b80febb89c39d5f71a42f284af10be3a601cad33890e"
    static let contactSurfaceSHA256 = "71eb134afa27eac0c23500afbd038dd11594a2b5ad30a5a178b303305a49c3ca"
    static let lowAssetSHA256 = "cd8a496a1f89166cf819177c8b959246d130f64ea5dfbd86910488b1dbe849ac"
    static let lowContactSurfaceSHA256 = "76e9cfe574345931ca945495f41a0e2fe872a182d8db4f7e3078a8baa4acf7b1"
    static let lowSkinVertices = 1_707
    static let lowSkinTriangles = 2_129
    // Two material sections + two geometric numbers, even if the importer
    // coalesces both skin sections into one ModelEntity.
    static let materialDrawsPerInstance = 4
    static let skinVertices = 5_012
    static let skinTriangles = 8_146
    // 15 body palettes + 5 reused face palettes + 512px face normal +
    // 1024px body normal. Base-level bound; mipmaps/cache overhead are extra.
    static let decodedTextureBytes = (21 * 512 * 512 + 1_024 * 1_024) * 4

    private static var template: Entity?
    private(set) static var motion: ReplaySkinnedAthleteMotion?
    private static var contactSurface: ReplaySkinnedAthleteContactSurface?
    private static var bootMarkers: ReplaySkinnedAthleteBootMarkers?
    private static var lowTemplate: Entity?
    private static var lowContactSurface: ReplaySkinnedAthleteContactSurface?
    private static var lowBootMarkers: ReplaySkinnedAthleteBootMarkers?
    private static var kits: [[PhysicallyBasedMaterial]] = []
    static var isPrewarmed: Bool { template != nil && motion != nil && contactSurface != nil && kits.count == 15 }
    static var isLowDetailPrewarmed: Bool { isPrewarmed && lowTemplate != nil && lowContactSurface != nil }

    #if DEBUG
    private static var forcesLowDetailMakeFailure = false
    private(set) static var lowDetailCloneAttemptCount = 0
    #endif

    static func prewarm(in bundle: Bundle = .main) throws {
        guard !isPrewarmed else { return }
        let modelURL = try resource("ReplayXIRocketboxAthlete", "usdz", bundle)
        _ = try checkedData(modelURL, expected: assetSHA256)
        let motionURL = try resource("ReplayXIRocketboxMotion", "json", bundle)
        let baseMotion = try ReplaySkinnedAthleteMotion(data: checkedData(motionURL, expected: motionSHA256))
        let slowRunData = try? Data(contentsOf: resource("ReplayXIRocketboxSlowRun", "json", bundle),
                                    options: .mappedIfSafe)
        let preparedMotion = addingOptionalSlowRun(to: baseMotion, data: slowRunData)
        let contactURL = try resource("ReplayXIRocketboxContactSurface", "json", bundle)
        let preparedContactSurface = try ReplaySkinnedAthleteContactSurface(
            data: checkedData(contactURL, expected: contactSurfaceSHA256), motion: preparedMotion,
            assetSHA256: assetSHA256, motionSHA256: motionSHA256
        )
        let loaded = try Entity.load(contentsOf: modelURL)
        loaded.stopAllAnimations(recursive: true)
        let models = skinnedModels(in: loaded)
        // This source has a common skeleton. Require the verified coalesced
        // layout instead of guessing how a changed importer assigned slots.
        guard models.count == 1, let model = models.first,
              model.jointNames == preparedMotion.joints.map(\.name),
              model.jointTransforms.count == preparedMotion.joints.count
        else { throw ReplaySkinnedAthleteError.invalidSkeleton }
        guard let materials = model.model?.materials, materials.count == 2,
              let body = materials[0] as? PhysicallyBasedMaterial,
              materials[1] is PhysicallyBasedMaterial
        else { throw ReplaySkinnedAthleteError.invalidMaterials }
        let parts = model.model!.mesh.contents.models.flatMap { Array($0.parts) }
        guard parts.count == 2,
              parts.contains(where: { $0.id == "Body" && $0.materialIndex == 0 && $0.positions.count == 3_288 }),
              parts.contains(where: { $0.id == "Head" && $0.materialIndex == 1 && $0.positions.count == 1_724 })
        else { throw ReplaySkinnedAthleteError.invalidMaterials }
        try ReplayAthleteHeadProvider.prewarm(in: bundle)
        var preparedKits: [[PhysicallyBasedMaterial]] = []
        for kit in ["Home", "Away", "Keeper"] {
            for skin in 0..<5 {
                let url = try resource("ReplayXIRocketbox\(kit)Skin\(skin)", "png", bundle)
                let texture = try TextureResource.load(contentsOf: url)
                var tintedBody = body
                tintedBody.baseColor = .init(tint: .white, texture: .init(texture))
                guard let head = ReplayAthleteHeadProvider.material(at: skin) else {
                    throw ReplaySkinnedAthleteError.invalidMaterials
                }
                preparedKits.append([tintedBody, head])
            }
        }
        // Atomic publication; a missing kit must not expose a half-ready squad.
        template = loaded
        motion = preparedMotion
        contactSurface = preparedContactSurface
        bootMarkers = ReplaySkinnedAthleteBootMarkers(model: model, motion: preparedMotion)
        kits = preparedKits
    }

    /// Optional, independent admission. Existing near players remain ready if
    /// this lower-detail package or its complete contact profile is unavailable.
    /// Called on the room's cold path only, never during a scene update.
    static func prewarmLowDetail(in bundle: Bundle = .main) throws {
        guard !isLowDetailPrewarmed else { return }
        guard isPrewarmed, let motion else { throw ReplaySkinnedAthleteError.notPrepared }
        let modelURL = try resource("ReplayXIRocketboxLow", "usdz", bundle)
        _ = try checkedData(modelURL, expected: lowAssetSHA256)
        let contactURL = try resource("ReplayXIRocketboxLowContactSurface", "json", bundle)
        let contacts = try ReplaySkinnedAthleteContactSurface(
            data: checkedData(contactURL, expected: lowContactSurfaceSHA256), motion: motion,
            assetSHA256: lowAssetSHA256, motionSHA256: motionSHA256, profile: .fullLowDetail
        )
        let loaded = try Entity.load(contentsOf: modelURL)
        loaded.stopAllAnimations(recursive: true)
        let models = skinnedModels(in: loaded)
        guard models.count == 1, let model = models.first,
              model.jointNames == motion.jointNames, model.jointTransforms.count == motion.joints.count,
              var component = model.model else { throw ReplaySkinnedAthleteError.invalidSkeleton }
        let parts = component.mesh.contents.models.flatMap { Array($0.parts) }
        guard component.materials.count == 2,
              component.materials.allSatisfy({ $0 is PhysicallyBasedMaterial }),
              parts.count == 2,
              parts.contains(where: { $0.id == "Body" && $0.materialIndex == 0 && $0.positions.count == 1_296 }),
              parts.contains(where: { $0.id == "Head" && $0.materialIndex == 1 && $0.positions.count == 411 }),
              parts.reduce(0, { $0 + ($1.triangleIndices?.count ?? 0) / 3 }) == lowSkinTriangles
        else { throw ReplaySkinnedAthleteError.invalidMaterials }
        // Use the already prepared face/body palettes and normal maps; do not
        // retain the imported package's default material pair in the template.
        component.materials = kits[0]
        model.model = component
        lowTemplate = loaded
        lowContactSurface = contacts
        lowBootMarkers = ReplaySkinnedAthleteBootMarkers(model: model, motion: motion)
    }

    static func make(for player: PlayerTrack, detail: Detail = .near) throws -> ReplaySkinnedAthleteInstance {
        let preparedTemplate = detail == .near ? template : lowTemplate
        let preparedContacts = detail == .near ? contactSurface : lowContactSurface
        guard let template = preparedTemplate, let motion, let contactSurface = preparedContacts,
              isPrewarmed, kits.count == 15 else {
            throw ReplaySkinnedAthleteError.notPrepared
        }
        #if DEBUG
        if detail == .lowDetail {
            lowDetailCloneAttemptCount += 1
            if forcesLowDetailMakeFailure { throw ReplaySkinnedAthleteError.invalidSkeleton }
        }
        #endif
        let clone = template.clone(recursive: true)
        clone.stopAllAnimations(recursive: true)
        guard let model = skinnedModels(in: clone).first, var component = model.model else {
            throw ReplaySkinnedAthleteError.invalidSkeleton
        }
        let skin = (player.shirtNumber + (player.team == .away ? 2 : 0)) % 5
        let kit = player.isGoalkeeper ? 2 : (player.team == .home ? 0 : 1)
        component.materials = kits[kit * 5 + skin]
        model.model = component
        let configuration = ReplayAthleteConfiguration(player: player)
        let root = Entity()
        root.name = visualRootName
        root.scale = [configuration.appearance.widthScale, configuration.appearance.heightScale, 1]
        root.addChild(clone)
        let digit = try ReplayAthleteMeshLibrary.jerseyNumber(player.shirtNumber)
        let ink = UnlitMaterial(color: configuration.kit.number.uiColor, applyPostProcessToneMap: false)
        let front = ModelEntity(mesh: digit.mesh, materials: [ink])
        front.name = "skinned-chest-number"
        let back = ModelEntity(mesh: digit.mesh, materials: [ink])
        back.name = "skinned-shirt-number"
        clone.addChild(front)
        clone.addChild(back)
        return ReplaySkinnedAthleteInstance(root: root, skinRoot: clone, model: model,
                                           front: front, back: back, playerID: player.id, motion: motion,
                                           contactSurface: contactSurface, detail: detail,
                                           bootMarkers: detail == .near ? bootMarkers : lowBootMarkers)
    }

    static func skinnedModels(in entity: Entity) -> [ModelEntity] {
        var result: [ModelEntity] = []
        if let model = entity as? ModelEntity, !model.jointNames.isEmpty { result.append(model) }
        for child in entity.children { result.append(contentsOf: skinnedModels(in: child)) }
        return result
    }

    private static func resource(_ name: String, _ suffix: String, _ bundle: Bundle) throws -> URL {
        guard let url = bundle.url(forResource: name, withExtension: suffix, subdirectory: "Resources/Players")
                ?? bundle.url(forResource: name, withExtension: suffix) else {
            throw ReplaySkinnedAthleteError.missingResource(name)
        }
        return url
    }

    private static func checkedData(_ url: URL, expected: String) throws -> Data {
        let data = try Data(contentsOf: url, options: .mappedIfSafe)
        let digest = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        guard digest == expected else { throw ReplaySkinnedAthleteError.invalidHash(url.lastPathComponent) }
        return data
    }

    /// A missing or incompatible supplemental gait must not disable the verified
    /// base rig. This cold-path validation never runs during playback or a seek.
    static func addingOptionalSlowRun(to base: ReplaySkinnedAthleteMotion,
                                      data: Data?) -> ReplaySkinnedAthleteMotion {
        guard let data, data.count <= ReplaySkinnedAthleteMotion.maximumSlowRunPayloadBytes,
              SHA256.hash(data: data).map({ String(format: "%02x", $0) }).joined() == slowRunSHA256,
              let extended = try? base.addingSlowRun(data: data, baseMotionSHA256: motionSHA256)
        else { return base }
        return extended
    }

    #if DEBUG
    static func resetForTesting() {
        template = nil; motion = nil; contactSurface = nil; bootMarkers = nil; kits = []
        resetLowDetailForTesting()
    }

    static func resetLowDetailForTesting() {
        lowTemplate = nil; lowContactSurface = nil; lowBootMarkers = nil
        forcesLowDetailMakeFailure = false
        lowDetailCloneAttemptCount = 0
    }

    static func setLowDetailMakeFailureForTesting(_ enabled: Bool) {
        forcesLowDetailMakeFailure = enabled
    }
    #endif
}

@MainActor
final class ReplaySkinnedAthleteInstance {
    let detail: ReplaySkinnedAthleteProvider.Detail
    #if DEBUG
    /// Native same-frame A/B audit; not exposed in the shipped app.
    var disablesCutPhaseAlignmentForTesting = false
    /// Retains the independently measured cycle138 aligned, unsmoothed control.
    var disablesCutWeightSmoothingForTesting = false
    var disablesHeaderHandoffForTesting = false
    var disablesOffBallReadyArmsForTesting = false
    var disablesCervicalAimForTesting = false
    var disablesUpperBodyFlowForTesting = false
    /// Matched original-arm control; body, phase, source and contacts are shared.
    var disablesArmCutSmoothingForTesting = false
    enum DiagnosticStage: String, CaseIterable {
        case source, footballRetargetAndContact, offBall, look, impact
        case stationarySupport, headerAim, cervical, finalFloor
    }
    /// Local arrays are authoritative at every stage. Intermediate model-space
    /// matrices may be stale; a test observer must rebuild its own value copy.
    /// No observer/storage or extra hierarchy work exists in Release builds.
    var poseStageObserverForTesting: ((DiagnosticStage, ReplaySkinnedAthleteMotion.Pose) -> Void)?
    var authoredPoseObserverForTesting: ((ReplayAthleteLocomotionPose, Float, Float) -> Void)?
    private(set) var slowRunWeightForTesting: Float = 0
    private(set) var armCutWeightForTesting: Float = 0
    private(set) var armCutSuppressionForTesting: Float = 0
    #endif
    let root: Entity
    let playerID: String
    let model: ModelEntity
    let front: ModelEntity
    let back: ModelEntity
    private let skinRoot: Entity
    let motion: ReplaySkinnedAthleteMotion
    let contactSurface: ReplaySkinnedAthleteContactSurface
    let bootMarkers: ReplaySkinnedAthleteBootMarkers?
    private(set) var pose: ReplaySkinnedAthleteMotion.Pose
    private var transforms: [Transform]
    private let frontLocal: simd_float4x4
    private let backLocal: simd_float4x4
    private let neckIndex: Int
    private let headIndex: Int
    private let inverseRestChestRotation: simd_quatf
    private let restHeadRotation: simd_quatf
    private let neckCompensatedChildren: [Int]
    private let offBallLeftArm: ReplayAthleteOffBallPose.NativeArmBinding?
    private let offBallRightArm: ReplayAthleteOffBallPose.NativeArmBinding?
    private let upperBodyFlow: ReplayAthleteUpperBodyFlow.NativeBinding?
    private var footballPose: ReplaySkinnedAthleteFootballPose?
    private var impactPose: ReplaySkinnedAthleteImpactPose?
    private let turnInPlace: ReplaySkinnedAthleteTurnInPlace?

    init(root: Entity, skinRoot: Entity, model: ModelEntity, front: ModelEntity, back: ModelEntity,
         playerID: String, motion: ReplaySkinnedAthleteMotion, contactSurface: ReplaySkinnedAthleteContactSurface,
         detail: ReplaySkinnedAthleteProvider.Detail = .near,
         bootMarkers: ReplaySkinnedAthleteBootMarkers? = nil) {
        self.detail = detail
        self.root = root
        self.skinRoot = skinRoot
        self.model = model
        self.front = front
        self.back = back
        self.playerID = playerID
        self.motion = motion
        self.contactSurface = contactSurface
        self.bootMarkers = bootMarkers
        pose = motion.makePoseBuffer()
        footballPose = ReplaySkinnedAthleteFootballPose(motion: motion, bootMarkers: bootMarkers)
        impactPose = ReplaySkinnedAthleteImpactPose(motion: motion, contactSurface: contactSurface)
        turnInPlace = ReplaySkinnedAthleteTurnInPlace(motion: motion)
        offBallLeftArm = .init(side: "left", motion: motion)
        offBallRightArm = .init(side: "right", motion: motion)
        upperBodyFlow = .init(motion: motion)
        transforms = model.jointTransforms
        neckIndex = motion.semanticJointIndices["neck"]!
        headIndex = motion.semanticJointIndices["head"]!
        neckCompensatedChildren = motion.joints.indices.filter {
            motion.joints[$0].parentIndex == motion.semanticJointIndices["neck"]!
                && $0 != motion.semanticJointIndices["head"]!
        }
        let chest = motion.numberAnchors.jointIndex
        let restRotation = simd_quatf(motion.restPose.modelSpaceTransforms[chest])
        inverseRestChestRotation = restRotation.inverse
        restHeadRotation = simd_quatf(motion.restPose.modelSpaceTransforms[headIndex])
        // The Tripo shirt's weighted folds protrude past its rest-pose number
        // anchors. A small skin-local clearance avoids clipped/z-fighting
        // digits while preserving attachment to the animated chest joint.
        let numberClearance: Float = motion.rigProfile == .tripo52 ? 0.022 : 0
        let numberNormal = restRotation.inverse.act(SIMD3<Float>(0, 0, numberClearance))
        frontLocal = Transform(scale: .init(repeating: 0.115), rotation: restRotation.inverse,
                               translation: motion.numberAnchors.front + numberNormal).matrix
        backLocal = Transform(scale: .init(repeating: 0.23),
                              rotation: restRotation.inverse * simd_quatf(angle: .pi, axis: [0, 1, 0]),
                              translation: motion.numberAnchors.back - numberNormal).matrix
    }

    /// Supplied locomotion is authoritative by default, including deliberate
    /// straight-run overrides. Only callers using the track's exact sample may
    /// opt into neighbour-track sampling for the cut-weight crossfade.
    @discardableResult
    func update(at time: TimeInterval, track: PlayerTrack, locomotion suppliedLocomotion: PlayerLocomotionSample,
                lookTarget: SIMD3<Float>?, ballAction: ReplayAthleteBallActionPose?,
                impact: PlayerRagdollPlayback.Sample? = nil,
                stationaryPose: PlayerPose? = nil,
                interaction: ReplayAthleteInteractionCue? = nil,
                presentationPose: PlayerPose? = nil,
                allowsOffBallPose: Bool = true,
                goalkeeperReadiness: ReplayGoalkeeperReadiness.Sample? = nil,
                allowsTrackLocomotionSampling: Bool = false,
                slowRunWeight suppliedSlowRunWeight: Float = 0,
                armCutAdmission: ReplayArmCutTimeline.Admission? = nil) -> Bool {
        #if DEBUG
        slowRunWeightForTesting = 0
        armCutWeightForTesting = 0
        armCutSuppressionForTesting = 0
        #endif
        let locomotion = stationaryPose == nil ? suppliedLocomotion : track.stationaryLocomotion
        // Never apply a stale or different player's collision sample. Unsupported
        // assets still fail soft to the procedural body rather than disappear.
        let validImpact = impact.map { $0.playerID == track.id && $0.time == time && impactPose != nil } ?? true
        let supported = validImpact && time.isFinite && locomotion.speedMetresPerSecond.isFinite
            && locomotion.turnRateDegreesPerSecond.isFinite && locomotion.accelerationMetresPerSecondSquared.isFinite
        root.isEnabled = supported
        guard supported else { return false }
        let gaitPhase = stationaryPose == nil
            ? track.gaitPhase(at: time)
            : locomotion.motion.locomotionPhase
        // Let the idle upper body contribute at walking speeds; the source run
        // has a deep elbow fold that looks like sprinting when moving slowly.
        let effort = locomotion.effort
        let upperBodyEffort = effort * min(max(locomotion.speedMetresPerSecond / 2.4, 0), 1)
        let movement = stationaryPose == nil
            ? ReplayAthleteMovementIntent.sample(track: track, at: time, presentationPose: presentationPose,
                                               lookTarget: lookTarget, interaction: interaction) : nil
        // Factory admission is a cold-built absolute-time envelope. Do not
        // clamp it by the live turn signal: that would restore the sudden
        // source-pose drop the envelope prevents. Direct callers stay opt-in.
        let slowWeight: Float
        if suppliedSlowRunWeight.isFinite, suppliedSlowRunWeight > 0,
           allowsTrackLocomotionSampling, allowsOffBallPose,
           motion.hasSlowRun, !track.isGoalkeeper, stationaryPose == nil,
           impact == nil, ballAction == nil, interaction == nil, movement != nil {
            slowWeight = min(suppliedSlowRunWeight, 1)
        } else { slowWeight = 0 }
        #if DEBUG
        slowRunWeightForTesting = slowWeight
        #endif
        motion.sample(time: time, locomotionEffort: upperBodyEffort,
                      gaitPhase: gaitPhase, slowRunWeight: slowWeight,
                      rebuildingModelSpace: false, into: &pose)
        #if DEBUG
        poseStageObserverForTesting?(.source, pose)
        #endif
        let interactionSample = ReplayAthleteInteractionPose.sample(
            cue: interaction, at: time, track: track, presentationPose: stationaryPose ?? presentationPose)
        // Callers already ease readiness out around a touch. Defend the actual
        // contact core here too, so a stale supplied sample cannot deform a save.
        let keeper = track.isGoalkeeper && stationaryPose == nil && impact == nil
            ? ReplayGoalkeeperReadiness.limited(goalkeeperReadiness,
                actionInfluence: max(interactionSample?.influence ?? 0, ballAction?.influence ?? 0)) : nil
        var phaseEnabled = allowsOffBallPose && stationaryPose == nil && impact == nil && ballAction == nil
        #if DEBUG
        phaseEnabled = phaseEnabled && !disablesCutPhaseAlignmentForTesting
        let cutWeightEnabled = phaseEnabled && allowsTrackLocomotionSampling && !disablesCutWeightSmoothingForTesting
        #else
        let cutWeightEnabled = phaseEnabled && allowsTrackLocomotionSampling
        #endif
        let nativeLocomotion = ReplaySkinnedAthleteCutWeight.sample(source: motion.sourceCommit,
            track: track, at: time, locomotion: locomotion, interaction: interaction, enabled: cutWeightEnabled)
        var armCut = nativeLocomotion.influence
        var permitsArmCutEnvelope = cutWeightEnabled && nativeLocomotion.admission > 0
        #if DEBUG
        permitsArmCutEnvelope = permitsArmCutEnvelope && !disablesArmCutSmoothingForTesting
        #endif
        if permitsArmCutEnvelope,
           let cap = armCutAdmission?.matchingWeight(sourceCommit: motion.sourceCommit, track: track,
                                                     at: time, locomotion: locomotion) {
            // The live min is intentional: sampled caps cannot prove that the
            // raw curve never dips between knots. No old zero can be activated.
            // These gates preserve contacts but do not promise a global 4/s
            // bound on the final arm weight across a live cap or contact fade.
            let limited = min(armCut, cap)
            if limited < armCut {
                armCut += (limited - armCut) * nativeLocomotion.admission
            }
        }
        #if DEBUG
        armCutWeightForTesting = armCut
        armCutSuppressionForTesting = nativeLocomotion.influence - armCut
        #endif
        let ballInfluence = ballAction == nil ? 0
            : ReplaySkinnedAthleteFootballPose.influence(locomotion: locomotion, ballAction: ballAction)
        let influence = max(nativeLocomotion.influence, ballInfluence,
                            interactionSample?.influence ?? 0, movement?.influence ?? 0, keeper?.influence ?? 0)
        // Header cues outlive the nonzero action sample by the existing
        // preparation/release margin. Hand the source chest back to locomotion
        // continuously instead of switching when the action becomes nil.
        var headerChestAdmission: Float?
        if interaction?.kind == .header, stationaryPose == nil, impact == nil {
            headerChestAdmission = 1 - ReplayAthleteMovementIntent.contactProtection(
                for: interaction, track: track, at: time)
        }
        #if DEBUG
        if disablesHeaderHandoffForTesting { headerChestAdmission = nil }
        #endif
        if influence > 0, footballPose != nil {
            let phaseWeight = ReplaySkinnedAthleteCutPhase.weight(source: motion.sourceCommit,
                track: track, at: time, locomotion: locomotion, interaction: interaction,
                retargetInfluence: influence, enabled: phaseEnabled, cutInfluence: nativeLocomotion.influence)
            let authored = ReplaySkinnedAthleteCutPhase.authoredPose(phase: gaitPhase, weight: phaseWeight) { phase in
                ReplayAthleteMotion.locomotionPose(
                    for: track, at: time, locomotion: locomotion, gaitPhase: phase,
                    lookTargetWorldPosition: lookTarget, ballAction: ballAction,
                    stationaryPose: stationaryPose, interaction: interaction, presentationPose: presentationPose,
                    movementIntent: movement, allowsOffBallPose: false, goalkeeperReadiness: keeper)
            }
            #if DEBUG
            authoredPoseObserverForTesting?(authored, phaseWeight, influence)
            #endif
            footballPose?.apply(authored, influence: influence,
                                armInfluence: max(armCut,
                                                  interactionSample?.influence ?? 0, movement?.readiness ?? 0,
                                                  keeper?.armInfluence ?? 0),
                                motion: motion, to: &pose, interaction: interactionSample,
                                goalkeeperReadiness: keeper, headerChestAdmission: headerChestAdmission)
        }
        #if DEBUG
        poseStageObserverForTesting?(.footballRetargetAndContact, pose)
        #endif
        let rawContactAttention = max(
            movement?.contactProtection ?? ReplayAthleteMovementIntent.contactProtection(
                for: interaction, track: track, at: time),
            interactionSample?.influence ?? 0, ballAction?.influence ?? 0)
        let contactAttention = rawContactAttention.isFinite
            ? min(max(rawContactAttention, 0), 1) : 1
        let baseLook = ReplayAthleteMotion.lookPose(for: track, at: time, locomotion: locomotion,
                                               targetWorldPosition: lookTarget,
                                               stationaryPose: stationaryPose,
                                               presentationPose: presentationPose,
                                               contactAttention: contactAttention)
        #if DEBUG
        let preservesReadyArms = !disablesOffBallReadyArmsForTesting
        #else
        let preservesReadyArms = true
        #endif
        let offBall = ReplayAthleteOffBallPose.sample(
            playerID: track.id, at: time, locomotion: locomotion, look: baseLook,
            actionInfluence: max(interactionSample?.influence ?? 0, ballAction?.influence ?? 0,
                                 keeper?.influence ?? 0),
            sourceFraction: 1 - influence,
            retargetedArmReadiness: preservesReadyArms && !track.isGoalkeeper
                ? (movement?.readiness ?? 0) * (1 - (movement?.contactProtection ?? 0)) : 0,
            enabled: allowsOffBallPose && presentationPose != nil && stationaryPose == nil
                && impact == nil && lookTarget != nil)
        applyOffBall(offBall)
        var flowEnabled = allowsOffBallPose && presentationPose != nil && stationaryPose == nil
            && impact == nil && lookTarget != nil && !track.isGoalkeeper
        #if DEBUG
        flowEnabled = flowEnabled && !disablesUpperBodyFlowForTesting
        #endif
        let flow = ReplayAthleteUpperBodyFlow.sample(gaitPhase: gaitPhase, locomotion: locomotion,
            actionInfluence: contactAttention, armReadiness: movement?.readiness ?? 0,
            enabled: flowEnabled && upperBodyFlow != nil)
        upperBodyFlow?.apply(flow, motion: motion, to: &pose)
        #if DEBUG
        poseStageObserverForTesting?(.offBall, pose)
        #endif
        let look = flow.adjusting(offBall.adjusting(baseLook))
        if let action = interactionSample {
            applyLook(ReplayAthleteLookPose(neckYawRadians: look.neckYawRadians,
                headYawRadians: look.headYawRadians,
                neckPitchRadians: look.neckPitchRadians,
                headPitchRadians: look.headPitchRadians + action.headPitch * action.influence))
        } else { applyLook(look) }
        #if DEBUG
        poseStageObserverForTesting?(.look, pose)
        #endif
        if let impact {
            impactPose?.apply(impact.pose, influence: impact.influence, motion: motion, to: &pose)
        }
        #if DEBUG
        poseStageObserverForTesting?(.impact, pose)
        #endif
        motion.rebuildModelSpaceTransforms(in: &pose)
        if let turn = ReplaySkinnedAthleteTurnInPlace.sample(track: track, at: time,
            presentationPose: presentationPose, locomotion: locomotion, interaction: interaction,
            actionInfluence: max(interactionSample?.influence ?? 0, ballAction?.influence ?? 0),
            enabled: allowsOffBallPose && stationaryPose == nil && impact == nil) {
            turnInPlace?.apply(turn, motion: motion, to: &pose)
        }
        #if DEBUG
        poseStageObserverForTesting?(.stationarySupport, pose)
        #endif
        if let action = interactionSample, action.kind == .header {
            // Source Biped axes and torso lengths differ from the generated
            // rig. Solve from the actual model-space chest/head pivots, then
            // recover the chest's true parent-local rotation. No stretching,
            // root correction or foot transform is introduced by this aim step.
            // Explicit grounded headers plant their feet in footballPose above.
            let chestIndex = motion.numberAnchors.jointIndex
            let chest = pose.modelSpaceTransforms[chestIndex]
            let head = pose.modelSpaceTransforms[headIndex]
            let pivot = SIMD3<Float>(chest.columns.3.x, chest.columns.3.y, chest.columns.3.z)
            let headPosition = SIMD3<Float>(head.columns.3.x, head.columns.3.y, head.columns.3.z)
            let ball = action.ballCentreTarget + SIMD3<Float>(0, motion.geometry.restMinY, 0)
            let aim = ReplayAthleteInteractionPose.headerTorsoRotation(pivot: pivot, head: headPosition, ball: ball)
            let parent = motion.joints[chestIndex].parentIndex
            let parentRotation = parent < 0 ? simd_quatf(real: 1, imag: .zero)
                : simd_quatf(pose.modelSpaceTransforms[parent])
            let world = simd_quatf(chest)
            let desired: simd_quatf
            if action.headerSupportLeg != nil {
                desired = contactSurface.plantedHeaderAim(aim, weight: action.influence,
                    pivot: pivot, head: head, ball: ball, pose: pose) * world
            } else {
                desired = ReplayAthleteInteractionPose.blend(world, aim * world, action.influence)
            }
            pose.rotations[chestIndex] = simd_normalize(parentRotation.inverse * desired)
            motion.rebuildModelSpaceTransforms(in: &pose)
        }
        #if DEBUG
        poseStageObserverForTesting?(.headerAim, pose)
        #endif
        let hasFiniteLookTarget = lookTarget.map { $0.x.isFinite && $0.y.isFinite && $0.z.isFinite } ?? false
        var aimFreedom: Float = hasFiniteLookTarget && stationaryPose == nil
            && impact == nil && !track.isGoalkeeper ? 1 - min(max(contactAttention, 0), 1) : 0
        #if DEBUG
        if disablesCervicalAimForTesting { aimFreedom = 0 }
        #endif
        constrainHeadRelativeToChest(look: baseLook, aimFreedom: aimFreedom)
        #if DEBUG
        poseStageObserverForTesting?(.cervical, pose)
        #endif
        contactSurface.raiseAboveFloor(motion.geometry.restMinY + contactSurface.paddingMetres, in: &pose)
        #if DEBUG
        poseStageObserverForTesting?(.finalFloor, pose)
        #endif
        for index in transforms.indices {
            transforms[index] = Transform(scale: pose.scales[index], rotation: pose.rotations[index],
                                          translation: pose.translations[index])
        }
        model.jointTransforms = transforms
        let chest = pose.modelSpaceTransforms[motion.numberAnchors.jointIndex]
        front.transform = Transform(matrix: chest * frontLocal)
        back.transform = Transform(matrix: chest * backLocal)
        skinRoot.position.y = -motion.geometry.restMinY
        return true
    }

    private func applyOffBall(_ sample: ReplayAthleteOffBallPose.Sample) {
        guard !sample.isIdentity else { return }
        let chest = motion.numberAnchors.jointIndex
        // Compose only the short parent chain; no extra full-skeleton rebuild
        // or temporary arrays. The chest's descendants follow without stretch.
        var parent = motion.joints[chest].parentIndex
        var parentRotation = simd_quatf(real: 1, imag: .zero)
        while parent >= 0 {
            parentRotation = pose.rotations[parent] * parentRotation
            parent = motion.joints[parent].parentIndex
        }
        pose.rotations[chest] = simd_normalize(parentRotation.inverse * sample.chestRotation
            * parentRotation * pose.rotations[chest])
        let torso = ReplayAthleteOffBallPose.modelRotation(chest, motion: motion, pose: pose)
            * inverseRestChestRotation
        offBallLeftArm?.apply(sample, torso: torso, motion: motion, to: &pose)
        offBallRightArm?.apply(sample, torso: torso, motion: motion, to: &pose)
    }

    private func constrainHeadRelativeToChest(look: ReplayAthleteLookPose, aimFreedom: Float) {
        let chestIndex = motion.numberAnchors.jointIndex
        let chestDelta = simd_quatf(pose.modelSpaceTransforms[chestIndex]) * inverseRestChestRotation
        let headWorld = simd_quatf(pose.modelSpaceTransforms[headIndex])
        let relative = simd_normalize(chestDelta.inverse
            * headWorld * restHeadRotation.inverse)
        let candidate: simd_quatf
        if aimFreedom > 0 {
            let aimed = ReplayCervicalConstraint.aimedModelRotation(
                simd_normalize(headWorld * restHeadRotation.inverse),
                look: look, weight: 0.65 * aimFreedom)
            candidate = simd_normalize(chestDelta.inverse * aimed)
        } else { candidate = relative }
        let limited = ReplayCervicalConstraint.limited(candidate)
        guard simd_length_squared(limited.vector - relative.vector) > 0.000_000_000_1 else { return }
        let parent = motion.joints[headIndex].parentIndex
        var parentRotation = parent < 0 ? simd_quatf(real: 1, imag: .zero)
            : simd_quatf(pose.modelSpaceTransforms[parent])
        if aimFreedom > 0, parent == neckIndex {
            // Share stabilization/limiting across both cervical joints. A
            // head-only correction bends the skull against a frozen neck.
            let desired = chestDelta * limited * restHeadRotation
            var correction = simd_normalize(desired * headWorld.inverse)
            if correction.real < 0 { correction = simd_quatf(vector: -correction.vector) }
            let shared = simd_slerp(simd_quatf(real: 1, imag: .zero), correction, 0.45 * aimFreedom)
            let neckParent = motion.joints[neckIndex].parentIndex
            let neckParentRotation = neckParent < 0 ? simd_quatf(real: 1, imag: .zero)
                : simd_quatf(pose.modelSpaceTransforms[neckParent])
            let oldLocal = pose.rotations[neckIndex]
            parentRotation = simd_normalize(shared * parentRotation)
            pose.rotations[neckIndex] = simd_normalize(neckParentRotation.inverse * parentRotation)
            let delta = simd_normalize(oldLocal.inverse * pose.rotations[neckIndex])
            compensateNeckChildren(for: delta)
        }
        pose.rotations[headIndex] = simd_normalize(parentRotation.inverse * chestDelta * limited * restHeadRotation)
        if aimFreedom > 0, parent == neckIndex {
            motion.rebuildCervicalModelSpaceTransforms(in: &pose)
        } else {
            // Contact cores retain the previous head-only path exactly.
            motion.rebuildHeadModelSpaceTransforms(in: &pose)
        }
    }

    private func applyLook(_ look: ReplayAthleteLookPose) {
        let neck = motion.joints[neckIndex]
        let delta = simd_quatf(angle: look.neckYawRadians, axis: neck.localUpAxis)
            * simd_quatf(angle: look.neckPitchRadians, axis: neck.localRightAxis)
        pose.rotations[neckIndex] = simd_normalize(pose.rotations[neckIndex] * delta)
        // Biped's clavicles are parented to Neck. Keep their complete local
        // transforms fixed in chest space; looking aside must not drag the arms.
        compensateNeckChildren(for: delta)
        let head = motion.joints[headIndex]
        pose.rotations[headIndex] = simd_normalize(pose.rotations[headIndex]
            * simd_quatf(angle: look.headYawRadians, axis: head.localUpAxis)
            * simd_quatf(angle: look.headPitchRadians, axis: head.localRightAxis))
    }

    private func compensateNeckChildren(for delta: simd_quatf) {
        for index in neckCompensatedChildren {
            pose.translations[index] = delta.inverse.act(pose.translations[index])
            pose.rotations[index] = simd_normalize(delta.inverse * pose.rotations[index])
        }
    }
}
