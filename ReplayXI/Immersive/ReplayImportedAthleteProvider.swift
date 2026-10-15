import CryptoKit
import Foundation
import RealityKit
import UIKit

/// The MIT Rocketbox face is a static surface attached to our head joint. It
/// adds real facial anatomy and a normal map without replacing the football
/// pose solver or running another skeleton. All 22 players share one mesh and
/// five 512px skin palettes; only near athletes use it.
@MainActor
enum ReplayAthleteHeadProvider {
    static let resourceName = "ReplayXIAthleteHead"
    static let expectedSHA256 = "7446de58f31366aacf733060a12748b62c3dfb75a46994ba3ed32576355c1f20"
    static let metrics = ReplayAthleteMeshMetrics(vertices: 1_724, triangles: 3_128)
    static let decodedTextureBytes = 7 * 512 * 512 * 4
    private static var mesh: MeshResource?
    private static var materials: [PhysicallyBasedMaterial] = []

    static var isPrewarmed: Bool { mesh != nil && materials.count == 5 }

    static func prewarm(in bundle: Bundle = .main) throws {
        guard !isPrewarmed else { return }
        guard let url = resourceURL(named: resourceName, extension: "usdz", in: bundle) else {
            throw ReplayImportedAthleteError.resourceMissing
        }
        let data = try Data(contentsOf: url, options: .mappedIfSafe)
        let digest = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        guard digest == expectedSHA256 else {
            throw ReplayImportedAthleteError.resourceHashMismatch(actual: digest)
        }
        let loaded = try Entity.load(contentsOf: url)
        guard let component = firstModel(in: loaded),
              let sourceMaterial = component.materials.first as? PhysicallyBasedMaterial
        else { throw ReplayImportedAthleteError.resourceMissing }
        let bounds = loaded.visualBounds(relativeTo: loaded)
        guard bounds.extents.allFinite,
              (0.17...0.20).contains(bounds.extents.x),
              (0.30...0.34).contains(bounds.extents.y)
        else { throw ReplayImportedAthleteError.invalidBounds }

        var prepared: [PhysicallyBasedMaterial] = []
        for index in 0..<5 {
            guard let textureURL = resourceURL(
                named: "ReplayXIAthleteSkin\(index)", extension: "png", in: bundle
            ) else { throw ReplayImportedAthleteError.resourceMissing }
            let texture = try TextureResource.load(contentsOf: textureURL)
            var material = sourceMaterial
            material.baseColor = .init(tint: .white, texture: .init(texture))
            prepared.append(material)
        }
        let seatedHead = try ReplayAthleteHeadNeckSkirt.make(from: component.mesh)
        // Publish together so a failed texture load never exposes a half-ready
        // renderer. The procedural face remains available without a retry loop.
        materials = prepared
        mesh = seatedHead
    }

    static func make(appearance: ReplayAthleteAppearance) -> ModelEntity? {
        guard let mesh, materials.count == 5 else { return nil }
        let index = (0..<5).first { ReplayAthleteAppearance.replayXI(index: $0).skin == appearance.skin } ?? 0
        let head = ModelEntity(mesh: mesh, materials: [materials[index]])
        head.name = "head"
        // Source facial anatomy is adult scale. A small width adjustment seats
        // the authored neck inside the shirt collar without stretching height.
        head.scale.x = 1.07
        return head
    }

    /// Full-body skins reuse these five prepared face textures and normal map.
    /// No texture decoding is needed when a player enters the near-field set.
    static func material(at index: Int) -> PhysicallyBasedMaterial? {
        guard materials.indices.contains(index) else { return nil }
        return materials[index]
    }

    private static func firstModel(in entity: Entity) -> ModelComponent? {
        if let component = entity.components[ModelComponent.self] { return component }
        for child in entity.children {
            if let component = firstModel(in: child) { return component }
        }
        return nil
    }

    private static func resourceURL(named name: String, extension suffix: String, in bundle: Bundle) -> URL? {
        bundle.url(forResource: name, withExtension: suffix, subdirectory: "Resources/Players")
            ?? bundle.url(forResource: name, withExtension: suffix)
    }

    #if DEBUG
    static func resetForTesting() {
        mesh = nil
        materials = []
    }
    #endif
}

/// The licensed head ends in a sloped open neck: the rear edge is 59 mm above
/// the front. Seated rigidly at the existing gaze pivot, that rear edge clears
/// the shirt. Extend only the open boundary into the hidden collar interior.
/// Source assets, skull vertices, UVs, indices, joint placement and draws stay
/// unchanged. This derived mesh is built once per admitted near/far asset.
@MainActor
enum ReplayAthleteHeadNeckSkirt {
    static let seatedBoundaryY: Float = -0.23
    static let seatedRadiusX: Float = 0.014
    static let seatedRadiusZ: Float = 0.0112

    private struct PositionKey: Hashable {
        let x: Int, y: Int, z: Int
        init(_ point: SIMD3<Float>) {
            x = Int((point.x * 1_000_000).rounded())
            y = Int((point.y * 1_000_000).rounded())
            z = Int((point.z * 1_000_000).rounded())
        }
    }

    static func make(from source: MeshResource) throws -> MeshResource {
        let parts = source.contents.models.flatMap { Array($0.parts) }
        guard parts.count == 1, let part = parts.first,
              let sourceNormals = part.normals, let uvs = part.textureCoordinates,
              let indices = part.triangleIndices,
              sourceNormals.count == part.positions.count,
              uvs.count == part.positions.count,
              indices.count.isMultiple(of: 3)
        else { throw ReplayImportedAthleteError.invalidBounds }
        var points = part.positions.elements
        var normals = sourceNormals.elements
        var canonical: [PositionKey: Int] = [:]
        var pointIDs: [Int] = []
        pointIDs.reserveCapacity(points.count)
        for point in points {
            let key = PositionKey(point)
            let id = canonical[key] ?? canonical.count
            canonical[key] = id
            pointIDs.append(id)
        }
        var edges: [UInt64: Int] = [:]
        let triangles = indices.elements
        for offset in stride(from: 0, to: triangles.count, by: 3) {
            for side in 0..<3 {
                let a = pointIDs[Int(triangles[offset + side])]
                let b = pointIDs[Int(triangles[offset + (side + 1) % 3])]
                let key = UInt64(min(a, b)) << 32 | UInt64(max(a, b))
                edges[key, default: 0] += 1
            }
        }
        var boundaryIDs: Set<Int> = []
        for (edge, count) in edges where count == 1 {
            boundaryIDs.insert(Int(edge >> 32))
            boundaryIDs.insert(Int(edge & 0xffff_ffff))
        }
        let lowerBoundary = points.indices.filter {
            points[$0].y < -0.08 && boundaryIDs.contains(pointIDs[$0])
        }
        let lowerIDs = Set(lowerBoundary.map { pointIDs[$0] })
        guard lowerIDs.count == 22 else { throw ReplayImportedAthleteError.invalidBounds }
        for index in lowerBoundary {
            let angle = atan2(points[index].z, points[index].x)
            points[index] = [seatedRadiusX * cos(angle), seatedBoundaryY,
                             seatedRadiusZ * sin(angle)]
        }
        // Recompute only the moved ring's normals. Coincident UV seam vertices
        // share one physical normal; facial shading retains source normals.
        var ringNormals: [Int: SIMD3<Float>] = [:]
        for offset in stride(from: 0, to: triangles.count, by: 3) {
            let a = Int(triangles[offset]), b = Int(triangles[offset + 1]), c = Int(triangles[offset + 2])
            let normal = simd_cross(points[b] - points[a], points[c] - points[a])
            for index in [a, b, c] where lowerIDs.contains(pointIDs[index]) {
                ringNormals[pointIDs[index], default: .zero] += normal
            }
        }
        for index in lowerBoundary {
            if let normal = ringNormals[pointIDs[index]], simd_length_squared(normal) > 0.000_000_01 {
                normals[index] = simd_normalize(normal)
            }
        }
        var descriptor = MeshDescriptor(name: "replayxi-seated-head-neck")
        descriptor.positions = MeshBuffers.Positions(points)
        descriptor.normals = MeshBuffers.Normals(normals)
        descriptor.textureCoordinates = MeshBuffers.TextureCoordinates(uvs.elements)
        descriptor.primitives = .triangles(triangles)
        return try MeshResource.generate(from: [descriptor])
    }
}

/// Runtime admission policy for Replay XI's higher-fidelity imported-player
/// pilot. The current CC0 candidate remains available for explicit profiling,
/// but it is opt-in even for development builds: simulator QA exposed an
/// unacceptable shoulder/kit silhouette at the closest Playback distance.
/// The improved procedural rig is the safe default until a replacement clears
/// both the visual and physical-device gates in `PLAYER_ASSET_SELECTION.md`.
enum ReplayImportedAthleteFeatureGate {
    static let environmentKey = "REPLAYXI_IMPORTED_PLAYER_PILOT"
    static let userDefaultsKey = "ReplayXI.ImportedPlayerPilotEnabled"

    static var isEnabled: Bool {
        #if DEBUG
        readDiagnostics.record()
        #endif
        return resolvedValue(
            environmentValue: ProcessInfo.processInfo.environment[environmentKey],
            userDefaultsValue: UserDefaults.standard.object(forKey: userDefaultsKey) as? Bool,
            debugDefault: false
        )
    }

    #if DEBUG
    private static let readDiagnostics = ReplayImportedPilotReadDiagnostics()
    static var readCountForTesting: Int { readDiagnostics.count }
    static func resetReadCountForTesting() { readDiagnostics.reset() }
    #endif

    /// Kept pure so precedence and accepted spellings remain unit-testable.
    /// An environment override wins over the persisted developer setting.
    static func resolvedValue(
        environmentValue: String?,
        userDefaultsValue: Bool?,
        debugDefault: Bool
    ) -> Bool {
        if let environmentValue {
            switch environmentValue.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
            case "1", "true", "yes", "on": return true
            case "0", "false", "no", "off": return false
            default: break
            }
        }
        return userDefaultsValue ?? debugDefault
    }
}

#if DEBUG
/// This counter never stores the setting itself. Lock every access so counting
/// remains safe even if a diagnostic reads the gate outside the scene actor.
private final class ReplayImportedPilotReadDiagnostics: @unchecked Sendable {
    private let lock = NSLock()
    private var value = 0

    var count: Int { lock.withLock { value } }
    func record() { lock.withLock { value += 1 } }
    func reset() { lock.withLock { value = 0 } }
}
#endif

struct ReplayImportedAthleteAssetFacts: Equatable, Sendable {
    let sha256: String
    let bytes: Int
    let modelEntities: Int
    let animationTracks: Int
    let sourceHeight: Float
    let decodedTextureBytes: Int
}

enum ReplayImportedAthleteError: Error, Equatable {
    case featureDisabled
    case resourceMissing
    case resourceHashMismatch(actual: String)
    case invalidBounds
    case missingKitShell(String)
    case missingAnimation
    case invalidSlot(Int)
    case notPrewarmed
}

/// One cloned skinned athlete whose clip controllers stay paused and are
/// explicitly seeked from match time. This makes forward play, reverse play,
/// arbitrary timeline scrubbing, and shared-session resynchronisation land on
/// the same animation pose instead of depending on rendered frame count.
@MainActor
final class ReplayImportedAthleteInstance {
    let root: Entity
    let playerID: String
    let animationControllers: [AnimationPlaybackController]

    private(set) var normalizedClipPhase: Float = 0

    init(
        root: Entity,
        playerID: String,
        animationControllers: [AnimationPlaybackController]
    ) {
        self.root = root
        self.playerID = playerID
        self.animationControllers = animationControllers
    }

    /// Uses Replay XI's integrated telemetry-cadence clock, so animation pose is
    /// independent of playback rate and update cadence. The current pilot
    /// contains only a forward run, so unsupported football states expose the
    /// procedural rig instead of freezing a sprint frame in place.
    @discardableResult
    func updateMotionPresentation(
        at playhead: TimeInterval,
        using track: PlayerTrack,
        locomotion suppliedLocomotion: PlayerLocomotionSample? = nil
    ) -> Bool {
        let locomotion = suppliedLocomotion ?? track.locomotion(at: playhead)
        let isSupported = locomotion.state.supportsImportedRunClip
        root.isEnabled = isSupported
        guard isSupported else { return false }

        let phaseRadians = track.gaitPhase(at: playhead)
        let turns = Double(phaseRadians) / (Double.pi * 2)
        let phase = Float(turns - floor(turns))
        seek(toNormalizedClipPhase: phase)
        return true
    }

    func seek(to playhead: TimeInterval, using track: PlayerTrack) {
        updateMotionPresentation(at: playhead, using: track)
    }

    func seek(toNormalizedClipPhase rawPhase: Float) {
        let finitePhase = rawPhase.isFinite ? rawPhase : 0
        let phase = finitePhase - floor(finitePhase)
        normalizedClipPhase = phase

        for controller in animationControllers where controller.isValid {
            let duration = controller.duration
            guard duration.isFinite, duration > 0 else { continue }
            // Avoid the exact terminal sample, which some USD importers treat
            // as completion rather than the first frame of the next cycle.
            let lastSeekableTime = max(duration - min(duration / 1_000, 1.0 / 600), 0)
            controller.time = min(Double(phase) * duration, lastSeekableTime)
            controller.pause()
        }
    }
}

/// Hash-locked, fail-soft runtime provider for the repaired CC0 near athlete.
///
/// The imported fixture has eight USD mesh prims, but RealityKit coalesces that
/// source hierarchy into three `ModelEntity` subclasses. The five named kit
/// prims survive as empty marker entities below one skinned body model whose
/// material slots are body + jersey/shorts/socks/boots/trim. It also has three
/// legacy skeleton copies and about 20.5 MiB of decoded textures. It is
/// therefore restricted to one selected/nearest player. The procedural
/// near/far athletes remain the required fallback and the only supported
/// 22-player path.
@MainActor
enum ReplayImportedAthleteProvider {
    static let resourceName = "ReplayXIPlayerKitPilot"
    static let resourceSubdirectory = "Resources/Players"
    static let expectedSHA256 = "afeec6489a68c2ac121dad713021c7a5a6ff65ae3f031d3758ccdabfa4574cc1"
    static let expectedBytes = 4_833_314
    static let decodedTextureBytes = 21_495_808
    static let maximumConcurrentNearFieldInstances = 1
    static let visualRootName = "imported-athlete-visual"

    static let requiredKitShellNames = [
        "ReplayXI_Jersey",
        "ReplayXI_Shorts",
        "ReplayXI_Socks",
        "ReplayXI_Boots",
        "ReplayXI_Trim",
    ]
    /// Hash-locked mapping for RealityKit's coalesced six-material body mesh.
    /// Slot zero is the original skin/base-body material and is never replaced.
    private static let kitMaterialSlots = [
        "ReplayXI_Jersey": 1,
        "ReplayXI_Shorts": 2,
        "ReplayXI_Socks": 3,
        "ReplayXI_Boots": 4,
        "ReplayXI_Trim": 5,
    ]
    private static let expectedCoalescedBodyMaterialCount = 6
    private static let nominalHeight: Float = 1.78

    private struct KitShellBinding {
        let renderEntity: Entity
        let materialSlot: Int
    }

    private static var template: Entity?
    private static var cachedAssetURL: URL?
    private(set) static var assetFacts: ReplayImportedAthleteAssetFacts?

    #if DEBUG
    /// Keeps test processes deterministic when several suites exercise both the
    /// fail-soft procedural path and the explicitly prewarmed imported pilot.
    /// Production builds never expose or call this reset; app prewarm remains a
    /// one-way launch optimization.
    static func resetPrewarmForTesting() {
        template = nil
        cachedAssetURL = nil
        assetFacts = nil
    }
    #endif

    /// The asset lookup accepts both folder-preserving and flattened Xcode
    /// resource layouts. No filesystem or asset parsing occurs after prewarm.
    static func resourceURL(in bundle: Bundle = .main) -> URL? {
        bundle.url(
            forResource: resourceName,
            withExtension: "usdz",
            subdirectory: resourceSubdirectory
        ) ?? bundle.url(forResource: resourceName, withExtension: "usdz")
    }

    @discardableResult
    static func prewarm(in bundle: Bundle = .main) throws -> ReplayImportedAthleteAssetFacts {
        try prewarm(
            in: bundle,
            featureEnabled: ReplayImportedAthleteFeatureGate.isEnabled
        )
    }

    @discardableResult
    static func prewarm(
        in bundle: Bundle,
        featureEnabled: Bool
    ) throws -> ReplayImportedAthleteAssetFacts {
        guard featureEnabled else { throw ReplayImportedAthleteError.featureDisabled }
        guard let url = resourceURL(in: bundle) else {
            throw ReplayImportedAthleteError.resourceMissing
        }
        return try prewarm(contentsOf: url, featureEnabled: true)
    }

    /// URL entry point supports deterministic bundle and tamper tests without
    /// weakening the production hash admission check.
    @discardableResult
    static func prewarm(
        contentsOf assetURL: URL,
        featureEnabled: Bool
    ) throws -> ReplayImportedAthleteAssetFacts {
        guard featureEnabled else { throw ReplayImportedAthleteError.featureDisabled }
        if cachedAssetURL == assetURL, let assetFacts, template != nil {
            return assetFacts
        }

        let data = try Data(contentsOf: assetURL, options: .mappedIfSafe)
        let digest = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        guard digest == expectedSHA256, data.count == expectedBytes else {
            throw ReplayImportedAthleteError.resourceHashMismatch(actual: digest)
        }

        let loaded = try Entity.load(contentsOf: assetURL)
        var bodyRenderEntity: Entity?
        for shellName in requiredKitShellNames {
            guard let binding = kitShellBinding(named: shellName, in: loaded) else {
                throw ReplayImportedAthleteError.missingKitShell(shellName)
            }
            if let bodyRenderEntity {
                // All five marker prims must resolve to the same coalesced body
                // model. The exact asset hash and this topology check jointly
                // protect the hard-coded semantic material-slot mapping.
                guard bodyRenderEntity === binding.renderEntity else {
                    throw ReplayImportedAthleteError.missingKitShell(shellName)
                }
            } else {
                bodyRenderEntity = binding.renderEntity
            }
        }
        guard loaded.availableAnimations.isEmpty == false else {
            throw ReplayImportedAthleteError.missingAnimation
        }

        let bounds = loaded.visualBounds(relativeTo: nil)
        let height = bounds.extents.y
        guard bounds.min.allFinite,
              bounds.max.allFinite,
              height.isFinite,
              height > 1.4,
              height < 2.6
        else {
            throw ReplayImportedAthleteError.invalidBounds
        }

        loaded.name = "imported-athlete-template"
        loaded.stopAllAnimations(recursive: true)
        let facts = ReplayImportedAthleteAssetFacts(
            sha256: digest,
            bytes: data.count,
            modelEntities: recursiveModelCount(in: loaded),
            animationTracks: loaded.availableAnimations.count,
            sourceHeight: height,
            decodedTextureBytes: decodedTextureBytes
        )
        template = loaded
        cachedAssetURL = assetURL
        assetFacts = facts
        return facts
    }

    /// Never performs file I/O. A missing/failed prewarm simply returns nil so
    /// `ReplayAthleteFactory` remains the visual and interaction fallback.
    static func makeNearFieldVisualIfReady(
        for player: PlayerTrack,
        slot: Int = 0,
        at playhead: TimeInterval = 0,
        locomotion: PlayerLocomotionSample? = nil
    ) -> ReplayImportedAthleteInstance? {
        try? makeNearFieldVisual(
            for: player,
            slot: slot,
            at: playhead,
            locomotion: locomotion
        )
    }

    static func makeNearFieldVisual(
        for player: PlayerTrack,
        slot: Int = 0,
        at playhead: TimeInterval = 0,
        locomotion: PlayerLocomotionSample? = nil
    ) throws -> ReplayImportedAthleteInstance {
        guard (0..<maximumConcurrentNearFieldInstances).contains(slot) else {
            throw ReplayImportedAthleteError.invalidSlot(slot)
        }
        guard let template else { throw ReplayImportedAthleteError.notPrewarmed }

        let configuration = ReplayAthleteConfiguration(player: player)
        let skinnedClone = template.clone(recursive: true)
        skinnedClone.name = "imported-athlete-skinned-clone"
        skinnedClone.stopAllAnimations(recursive: true)
        applyKit(configuration.kit, to: skinnedClone)

        let sourceBounds = skinnedClone.visualBounds(relativeTo: skinnedClone)
        let sourceHeight = sourceBounds.extents.y
        guard sourceHeight.isFinite, sourceHeight > 0.01 else {
            throw ReplayImportedAthleteError.invalidBounds
        }
        let normalizationScale = nominalHeight / sourceHeight
        skinnedClone.scale = SIMD3<Float>(repeating: normalizationScale)
        skinnedClone.position = [
            -sourceBounds.center.x * normalizationScale,
            -sourceBounds.min.y * normalizationScale,
            -sourceBounds.center.z * normalizationScale,
        ]

        let root = Entity()
        root.name = visualRootName
        root.scale = [
            configuration.appearance.widthScale,
            configuration.appearance.heightScale,
            1,
        ]
        root.addChild(skinnedClone)
        try addJerseyNumbers(configuration: configuration, to: root)

        // RealityKit exposes two playable resources at the imported root even
        // though the USD audit finds three animation sources. Start every
        // resource RealityKit exposes and keep it paused; the controllers are
        // driven only by deterministic telemetry seeks.
        let controllers = skinnedClone.availableAnimations.map {
            skinnedClone.playAnimation($0, transitionDuration: 0, startsPaused: true)
        }
        guard controllers.isEmpty == false else {
            throw ReplayImportedAthleteError.missingAnimation
        }
        let instance = ReplayImportedAthleteInstance(
            root: root,
            playerID: player.id,
            animationControllers: controllers
        )
        instance.updateMotionPresentation(
            at: playhead,
            using: player,
            locomotion: locomotion
        )
        return instance
    }

    private static func applyKit(_ kit: ReplayAthleteKit, to root: Entity) {
        let materials: [(String, any Material)] = [
            ("ReplayXI_Jersey", SimpleMaterial(color: kit.shirt.uiColor, roughness: 0.78, isMetallic: false)),
            ("ReplayXI_Shorts", SimpleMaterial(color: kit.shorts.uiColor, roughness: 0.82, isMetallic: false)),
            ("ReplayXI_Socks", SimpleMaterial(color: kit.socks.uiColor, roughness: 0.86, isMetallic: false)),
            ("ReplayXI_Boots", SimpleMaterial(color: kit.boots.uiColor, roughness: 0.48, isMetallic: false)),
            ("ReplayXI_Trim", SimpleMaterial(color: kit.trim.uiColor, roughness: 0.70, isMetallic: false)),
        ]
        for (name, material) in materials {
            guard let binding = kitShellBinding(named: name, in: root),
                  var component = binding.renderEntity.components[ModelComponent.self],
                  component.materials.indices.contains(binding.materialSlot)
            else { continue }
            component.materials[binding.materialSlot] = material
            binding.renderEntity.components.set(component)
        }
    }

    /// Resolves the render component owned by the nearest ancestor of a kit
    /// marker. This is intentionally exposed to the focused runtime contract
    /// tests because the named marker itself is an empty imported entity.
    static func modelComponent(
        inKitShellNamed shellName: String,
        of root: Entity
    ) -> ModelComponent? {
        guard let binding = kitShellBinding(named: shellName, in: root) else { return nil }
        return binding.renderEntity.components[ModelComponent.self]
    }

    static func materialSlot(inKitShellNamed shellName: String) -> Int? {
        kitMaterialSlots[shellName]
    }

    private static func kitShellBinding(named shellName: String, in root: Entity) -> KitShellBinding? {
        guard let materialSlot = kitMaterialSlots[shellName],
              let marker = root.findEntity(named: shellName)
        else { return nil }

        var candidate = marker.parent
        while let entity = candidate {
            if let component = entity.components[ModelComponent.self] {
                guard component.materials.count == expectedCoalescedBodyMaterialCount,
                      component.materials.indices.contains(materialSlot)
                else { return nil }
                return KitShellBinding(renderEntity: entity, materialSlot: materialSlot)
            }
            candidate = entity.parent
        }
        return nil
    }

    private static func addJerseyNumbers(
        configuration: ReplayAthleteConfiguration,
        to root: Entity
    ) throws {
        let numberAsset = try ReplayAthleteMeshLibrary.jerseyNumber(configuration.shirtNumber)
        let material = UnlitMaterial(
            color: configuration.kit.number.uiColor,
            applyPostProcessToneMap: false
        )

        let back = ModelEntity(mesh: numberAsset.mesh, materials: [material])
        back.name = "imported-shirt-number"
        back.position = [0, 1.32, -0.164]
        back.orientation = simd_quatf(angle: .pi, axis: [0, 1, 0])
        back.scale = SIMD3<Float>(repeating: 0.29)
        root.addChild(back)

        let chest = ModelEntity(mesh: numberAsset.mesh, materials: [material])
        chest.name = "imported-chest-number"
        chest.position = [0.075, 1.34, 0.164]
        chest.scale = SIMD3<Float>(repeating: 0.115)
        root.addChild(chest)
    }

    private static func recursiveModelCount(in entity: Entity) -> Int {
        (entity is ModelEntity ? 1 : 0)
            + entity.children.reduce(0) { $0 + recursiveModelCount(in: $1) }
    }
}

private extension SIMD3 where Scalar == Float {
    var allFinite: Bool { x.isFinite && y.isFinite && z.isFinite }
}
