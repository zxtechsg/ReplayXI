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
    static let maximumConcurrentInstances = 4
    static let assetSHA256 = "7cfb694888f111928643e8aca7041d21925f5d55f3f5adbd353a972ca255e772"
    static let motionSHA256 = "d30a7379b81a4b0ea3fef5ebd20ad101911ab4fd521a5be1f6c00c0804f59ce4"
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
        let preparedMotion = try ReplaySkinnedAthleteMotion(data: checkedData(motionURL, expected: motionSHA256))
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
    private var footballPose: ReplaySkinnedAthleteFootballPose?
    private var impactPose: ReplaySkinnedAthleteImpactPose?

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
        offBallLeftArm = .init(side: "left", motion: motion)
        offBallRightArm = .init(side: "right", motion: motion)
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
        frontLocal = Transform(scale: .init(repeating: 0.115), rotation: restRotation.inverse,
                               translation: motion.numberAnchors.front).matrix
        backLocal = Transform(scale: .init(repeating: 0.23),
                              rotation: restRotation.inverse * simd_quatf(angle: .pi, axis: [0, 1, 0]),
                              translation: motion.numberAnchors.back).matrix
    }

    @discardableResult
    func update(at time: TimeInterval, track: PlayerTrack, locomotion suppliedLocomotion: PlayerLocomotionSample,
                lookTarget: SIMD3<Float>?, ballAction: ReplayAthleteBallActionPose?,
                impact: PlayerRagdollPlayback.Sample? = nil,
                stationaryPose: PlayerPose? = nil,
                interaction: ReplayAthleteInteractionCue? = nil,
                presentationPose: PlayerPose? = nil,
                allowsOffBallPose: Bool = true) -> Bool {
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
        motion.sample(time: time, locomotionEffort: upperBodyEffort,
                      gaitPhase: gaitPhase, rebuildingModelSpace: false, into: &pose)
        let interactionSample = ReplayAthleteInteractionPose.sample(
            cue: interaction, at: time, track: track, presentationPose: stationaryPose ?? presentationPose)
        let movement = stationaryPose == nil
            ? ReplayAthleteMovementIntent.sample(track: track, at: time, presentationPose: presentationPose,
                                               lookTarget: lookTarget, interaction: interaction) : nil
        let influence = max(ReplaySkinnedAthleteFootballPose.influence(locomotion: locomotion, ballAction: ballAction),
                            interactionSample?.influence ?? 0, movement?.influence ?? 0)
        if influence > 0, footballPose != nil {
            let authored = ReplayAthleteMotion.locomotionPose(
                for: track, at: time, locomotion: locomotion, gaitPhase: gaitPhase,
                lookTargetWorldPosition: lookTarget, ballAction: ballAction,
                stationaryPose: stationaryPose, interaction: interaction, presentationPose: presentationPose,
                movementIntent: movement, allowsOffBallPose: false
            )
            footballPose?.apply(authored, influence: influence,
                                armInfluence: max(ReplaySkinnedAthleteFootballPose.influence(locomotion: locomotion, ballAction: nil),
                                                  interactionSample?.influence ?? 0, movement?.readiness ?? 0),
                                motion: motion, to: &pose, interaction: interactionSample)
        }
        let baseLook = ReplayAthleteMotion.lookPose(for: track, at: time, locomotion: locomotion,
                                               targetWorldPosition: lookTarget,
                                               stationaryPose: stationaryPose,
                                               presentationPose: presentationPose)
        let offBall = ReplayAthleteOffBallPose.sample(
            playerID: track.id, at: time, locomotion: locomotion, look: baseLook,
            actionInfluence: max(interactionSample?.influence ?? 0, ballAction?.influence ?? 0),
            sourceFraction: 1 - influence,
            enabled: allowsOffBallPose && presentationPose != nil && stationaryPose == nil
                && impact == nil && lookTarget != nil)
        applyOffBall(offBall)
        let look = offBall.adjusting(baseLook)
        if let action = interactionSample {
            applyLook(ReplayAthleteLookPose(neckYawRadians: look.neckYawRadians,
                headYawRadians: look.headYawRadians,
                neckPitchRadians: look.neckPitchRadians,
                headPitchRadians: look.headPitchRadians + action.headPitch * action.influence))
        } else { applyLook(look) }
        if let impact {
            impactPose?.apply(impact.pose, influence: impact.influence, motion: motion, to: &pose)
        }
        motion.rebuildModelSpaceTransforms(in: &pose)
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
                    pivot: pivot, head: head, ball: ball) * world
            } else {
                desired = ReplayAthleteInteractionPose.blend(world, aim * world, action.influence)
            }
            pose.rotations[chestIndex] = simd_normalize(parentRotation.inverse * desired)
            motion.rebuildModelSpaceTransforms(in: &pose)
        }
        constrainHeadRelativeToChest()
        contactSurface.raiseAboveFloor(motion.geometry.restMinY + contactSurface.paddingMetres, in: &pose)
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

    private func constrainHeadRelativeToChest() {
        let chestIndex = motion.numberAnchors.jointIndex
        let chestDelta = simd_quatf(pose.modelSpaceTransforms[chestIndex]) * inverseRestChestRotation
        let relative = simd_normalize(chestDelta.inverse
            * simd_quatf(pose.modelSpaceTransforms[headIndex]) * restHeadRotation.inverse)
        let limited = ReplayCervicalConstraint.limited(relative)
        guard simd_length_squared(limited.vector - relative.vector) > 0.000_000_000_1 else { return }
        let parent = motion.joints[headIndex].parentIndex
        let parentRotation = parent < 0 ? simd_quatf(real: 1, imag: .zero)
            : simd_quatf(pose.modelSpaceTransforms[parent])
        pose.rotations[headIndex] = simd_normalize(parentRotation.inverse * chestDelta * limited * restHeadRotation)
        // Only a bounded cervical correction needs this extra fixed-joint
        // rebuild. Roots, arms, legs, translations and bone lengths are intact.
        motion.rebuildModelSpaceTransforms(in: &pose)
    }

    private func applyLook(_ look: ReplayAthleteLookPose) {
        let neck = motion.joints[neckIndex]
        let delta = simd_quatf(angle: look.neckYawRadians, axis: neck.localUpAxis)
            * simd_quatf(angle: look.neckPitchRadians, axis: neck.localRightAxis)
        pose.rotations[neckIndex] = simd_normalize(pose.rotations[neckIndex] * delta)
        // Biped's clavicles are parented to Neck. Keep their complete local
        // transforms fixed in chest space; looking aside must not drag the arms.
        for index in neckCompensatedChildren {
            pose.translations[index] = delta.inverse.act(pose.translations[index])
            pose.rotations[index] = simd_normalize(delta.inverse * pose.rotations[index])
        }
        let head = motion.joints[headIndex]
        pose.rotations[headIndex] = simd_normalize(pose.rotations[headIndex]
            * simd_quatf(angle: look.headYawRadians, axis: head.localUpAxis)
            * simd_quatf(angle: look.headPitchRadians, axis: head.localRightAxis))
    }
}
