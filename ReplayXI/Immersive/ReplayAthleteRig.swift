import Foundation
import RealityKit
import UIKit
import simd

enum ReplayAthleteLOD: String, CaseIterable, Hashable, Sendable {
    case near
    case mid
    case far

    var supportsDistalArticulation: Bool { self != .far }
    var supportsRagdoll: Bool { self == .near }

    var budget: ReplayAthleteLODBudget {
        switch self {
        case .near:
            ReplayAthleteLODBudget(
                maximumModelEntities: 29,
                maximumVerticesPerInstance: 4_800,
                maximumTrianglesPerInstance: 6_400
            )
        case .mid:
            ReplayAthleteLODBudget(
                maximumModelEntities: 19,
                maximumVerticesPerInstance: 2_700,
                maximumTrianglesPerInstance: 3_800
            )
        case .far:
            ReplayAthleteLODBudget(
                maximumModelEntities: 7,
                maximumVerticesPerInstance: 1_800,
                maximumTrianglesPerInstance: 2_500
            )
        }
    }
}

struct ReplayAthleteLODBudget: Equatable, Sendable {
    let maximumModelEntities: Int
    let maximumVerticesPerInstance: Int
    let maximumTrianglesPerInstance: Int
}

/// Hysteretic distance selection prevents a player at an LOD boundary from
/// rebuilding every frame as the observer makes small head movements.
struct ReplayAthleteLODPolicy: Equatable, Sendable {
    var nearDistance: Float = 8
    var farDistance: Float = 23
    var hysteresis: Float = 1.5

    func level(forDistance rawDistance: Float, current: ReplayAthleteLOD? = nil) -> ReplayAthleteLOD {
        let distance = rawDistance.isFinite ? max(rawDistance, 0) : .greatestFiniteMagnitude
        let band = max(hysteresis, 0)

        switch current {
        case .near where distance <= nearDistance + band:
            return .near
        case .mid where distance > nearDistance - band && distance <= farDistance + band:
            return .mid
        case .far where distance > farDistance - band:
            return .far
        default:
            if distance <= nearDistance { return .near }
            if distance <= farDistance { return .mid }
            return .far
        }
    }
}

struct ReplayAthleteColor: Equatable, Sendable {
    let red: Float
    let green: Float
    let blue: Float
    let alpha: Float

    init(red: Float, green: Float, blue: Float, alpha: Float = 1) {
        self.red = min(max(red, 0), 1)
        self.green = min(max(green, 0), 1)
        self.blue = min(max(blue, 0), 1)
        self.alpha = min(max(alpha, 0), 1)
    }

    @MainActor
    var uiColor: UIColor {
        UIColor(
            red: CGFloat(red),
            green: CGFloat(green),
            blue: CGFloat(blue),
            alpha: CGFloat(alpha)
        )
    }
}

struct ReplayAthleteKit: Equatable, Sendable {
    let shirt: ReplayAthleteColor
    let trim: ReplayAthleteColor
    let shorts: ReplayAthleteColor
    let socks: ReplayAthleteColor
    let number: ReplayAthleteColor
    let boots: ReplayAthleteColor
    let bootAccent: ReplayAthleteColor

    static func replayXI(team: FootballTeam, goalkeeper: Bool, appearanceIndex: Int) -> Self {
        let accents = [
            ReplayAthleteColor(red: 0.94, green: 0.96, blue: 0.98),
            ReplayAthleteColor(red: 0.73, green: 0.94, blue: 0.12),
            ReplayAthleteColor(red: 0.99, green: 0.31, blue: 0.17),
            ReplayAthleteColor(red: 0.14, green: 0.76, blue: 0.95),
            ReplayAthleteColor(red: 0.96, green: 0.72, blue: 0.10),
        ]
        let accent = accents[((appearanceIndex % accents.count) + accents.count) % accents.count]
        if goalkeeper {
            return Self(
                shirt: .init(red: 0.70, green: 0.94, blue: 0.12),
                trim: .init(red: 0.08, green: 0.12, blue: 0.06),
                shorts: .init(red: 0.08, green: 0.12, blue: 0.06),
                socks: .init(red: 0.70, green: 0.94, blue: 0.12),
                number: .init(red: 0.04, green: 0.07, blue: 0.03),
                boots: .init(red: 0.018, green: 0.020, blue: 0.024),
                bootAccent: accent
            )
        }
        switch team {
        case .home:
            return Self(
                shirt: .init(red: 0.91, green: 0.95, blue: 0.98),
                trim: .init(red: 0.025, green: 0.07, blue: 0.16),
                shorts: .init(red: 0.025, green: 0.07, blue: 0.16),
                socks: .init(red: 0.91, green: 0.95, blue: 0.98),
                number: .init(red: 0.025, green: 0.07, blue: 0.16),
                boots: .init(red: 0.018, green: 0.020, blue: 0.024),
                bootAccent: accent
            )
        case .away:
            return Self(
                shirt: .init(red: 0.72, green: 0.045, blue: 0.075),
                trim: .init(red: 0.94, green: 0.95, blue: 0.96),
                shorts: .init(red: 0.93, green: 0.94, blue: 0.95),
                socks: .init(red: 0.72, green: 0.045, blue: 0.075),
                number: .init(red: 0.98, green: 0.98, blue: 0.96),
                boots: .init(red: 0.018, green: 0.020, blue: 0.024),
                bootAccent: accent
            )
        }
    }
}

struct ReplayAthleteAppearance: Equatable, Sendable {
    let skin: ReplayAthleteColor
    let hair: ReplayAthleteColor
    let heightScale: Float
    let widthScale: Float

    static func replayXI(index rawIndex: Int) -> Self {
        let index = ((rawIndex % 5) + 5) % 5
        let skinTones = [
            ReplayAthleteColor(red: 0.91, green: 0.70, blue: 0.54),
            ReplayAthleteColor(red: 0.74, green: 0.49, blue: 0.32),
            ReplayAthleteColor(red: 0.52, green: 0.31, blue: 0.20),
            ReplayAthleteColor(red: 0.34, green: 0.195, blue: 0.145),
            ReplayAthleteColor(red: 0.82, green: 0.59, blue: 0.41),
        ]
        let hairTones = [
            ReplayAthleteColor(red: 0.055, green: 0.047, blue: 0.045),
            ReplayAthleteColor(red: 0.18, green: 0.10, blue: 0.055),
            ReplayAthleteColor(red: 0.34, green: 0.20, blue: 0.08),
            ReplayAthleteColor(red: 0.07, green: 0.055, blue: 0.045),
            ReplayAthleteColor(red: 0.46, green: 0.31, blue: 0.15),
        ]
        return Self(
            skin: skinTones[index],
            hair: hairTones[index],
            // A palette is not measured anatomy. Until height/width are
            // explicit physical player inputs, every team uses the same body.
            heightScale: 1,
            widthScale: 1
        )
    }
}

struct ReplayAthleteConfiguration: Equatable, Sendable {
    let playerID: String
    let shirtNumber: Int
    let goalkeeper: Bool
    let kit: ReplayAthleteKit
    let appearance: ReplayAthleteAppearance

    init(player: PlayerTrack) {
        let appearanceIndex = (player.shirtNumber + (player.team == .away ? 2 : 0)) % 5
        self.playerID = player.id
        self.shirtNumber = min(max(player.shirtNumber, 0), 99)
        self.goalkeeper = player.isGoalkeeper
        self.kit = .replayXI(
            team: player.team,
            goalkeeper: player.isGoalkeeper,
            appearanceIndex: appearanceIndex
        )
        self.appearance = .replayXI(index: appearanceIndex)
    }

    init(
        playerID: String,
        shirtNumber: Int,
        goalkeeper: Bool,
        kit: ReplayAthleteKit,
        appearance: ReplayAthleteAppearance
    ) {
        self.playerID = playerID
        self.shirtNumber = min(max(shirtNumber, 0), 99)
        self.goalkeeper = goalkeeper
        self.kit = kit
        self.appearance = appearance
    }
}

enum ReplayAthleteJoint: String, CaseIterable, Sendable {
    case bodyRoot = "body-root"
    case hips
    case spine
    case neck
    case headRoot = "head-root"
    case leftHip = "left-hip"
    case rightHip = "right-hip"
    case leftKnee = "left-knee"
    case rightKnee = "right-knee"
    case leftAnkle = "left-ankle"
    case rightAnkle = "right-ankle"
    case leftShoulder = "left-shoulder"
    case rightShoulder = "right-shoulder"
    case leftElbow = "left-elbow"
    case rightElbow = "right-elbow"
    case leftWrist = "left-wrist"
    case rightWrist = "right-wrist"

    var expectedParentName: String {
        switch self {
        case .bodyRoot: "full-rig"
        case .hips: Self.bodyRoot.rawValue
        case .spine, .leftHip, .rightHip: Self.hips.rawValue
        case .neck, .leftShoulder, .rightShoulder: Self.spine.rawValue
        case .headRoot: Self.neck.rawValue
        case .leftKnee: Self.leftHip.rawValue
        case .rightKnee: Self.rightHip.rawValue
        case .leftAnkle: Self.leftKnee.rawValue
        case .rightAnkle: Self.rightKnee.rawValue
        case .leftElbow: Self.leftShoulder.rawValue
        case .rightElbow: Self.rightShoulder.rawValue
        case .leftWrist: Self.leftElbow.rawValue
        case .rightWrist: Self.rightElbow.rawValue
        }
    }
}

enum ReplayAthleteRigError: Error {
    case missingJoint(ReplayAthleteJoint)
    case invalidParent(joint: ReplayAthleteJoint, expected: String, actual: String?)
    case geometryBudgetExceeded(lod: ReplayAthleteLOD, metrics: ReplayAthleteBuildMetrics)
}

@MainActor
struct ReplayAthleteJointBinding {
    let root: Entity
    let farFloorSupport: ReplayFarAthleteFloorSupport?
    let articulatedFar: ReplayArticulatedFarBinding?
    private let entities: [ReplayAthleteJoint: Entity]
    private let headBoundsCorners: [SIMD3<Float>]

    init(root: Entity) throws {
        var resolved: [ReplayAthleteJoint: Entity] = [:]
        for joint in ReplayAthleteJoint.allCases {
            guard let entity = root.findEntity(named: joint.rawValue) else {
                throw ReplayAthleteRigError.missingJoint(joint)
            }
            guard entity.parent?.name == joint.expectedParentName else {
                throw ReplayAthleteRigError.invalidParent(
                    joint: joint,
                    expected: joint.expectedParentName,
                    actual: entity.parent?.name
                )
            }
            resolved[joint] = entity
        }
        self.root = root
        self.entities = resolved
        let head = resolved[.headRoot]!
        let bounds = head.visualBounds(relativeTo: head)
        headBoundsCorners = (0..<8).map { corner in
            SIMD3<Float>(corner & 1 == 0 ? bounds.min.x : bounds.max.x,
                         corner & 2 == 0 ? bounds.min.y : bounds.max.y,
                         corner & 4 == 0 ? bounds.min.z : bounds.max.z)
        }
        let articulated = ReplayArticulatedFarBinding(root: root, joints: resolved)
        self.articulatedFar = articulated
        self.farFloorSupport = articulated == nil ? ReplayFarAthleteFloorSupport(
            leftHip: resolved[.leftHip]!, rightHip: resolved[.rightHip]!
        ) : nil
    }

    subscript(_ joint: ReplayAthleteJoint) -> Entity {
        // Construction validates all cases, so a missing key here would be a
        // programmer error rather than recoverable replay data.
        entities[joint]!
    }

    /// One cached head envelope follows the current neck/head pose. This reads
    /// only the joint transform; no mesh bounds are queried during playback.
    func headUpperY(relativeTo entity: Entity) -> Float? {
        let transform = entities[.headRoot]!.transformMatrix(relativeTo: entity)
        var upper = -Float.greatestFiniteMagnitude
        for corner in headBoundsCorners {
            upper = max(upper, (transform * SIMD4<Float>(corner, 1)).y)
        }
        return upper.isFinite ? upper : nil
    }
}

struct ReplayAthleteBuildMetrics: Equatable, Sendable {
    var modelEntities: Int = 0
    var verticesPerInstance: Int = 0
    var trianglesPerInstance: Int = 0

    func fits(_ budget: ReplayAthleteLODBudget) -> Bool {
        modelEntities <= budget.maximumModelEntities
            && verticesPerInstance <= budget.maximumVerticesPerInstance
            && trianglesPerInstance <= budget.maximumTrianglesPerInstance
    }
}

@MainActor
struct ReplayAthleteInstance {
    let root: Entity
    let joints: ReplayAthleteJointBinding
    let configuration: ReplayAthleteConfiguration
    let lod: ReplayAthleteLOD
    let metrics: ReplayAthleteBuildMetrics
}

/// Production integration point for Replay XI's rights-safe player visuals.
/// The returned root is deliberately named `full-rig`, and every joint name
/// matches the existing deterministic gait and ragdoll contracts.
@MainActor
enum ReplayAthleteFactory {
    private static let contactShadowMesh = MeshResource.generateCylinder(height: 0.006, radius: 0.29)
    private static let eyeMesh = MeshResource.generateSphere(radius: 0.010)

    static func make(for player: PlayerTrack, lod: ReplayAthleteLOD) throws -> ReplayAthleteInstance {
        try make(configuration: ReplayAthleteConfiguration(player: player), lod: lod)
    }

    /// Call before `openImmersiveSpace`; the finite cache is bounded to the
    /// requested LOD parts and 0...99 geometric shirt numbers.
    static func prewarm(
        for players: [PlayerTrack],
        lods: Set<ReplayAthleteLOD> = Set(ReplayAthleteLOD.allCases)
    ) throws {
        try ReplayAthleteMeshLibrary.prewarm(
            lods: lods,
            shirtNumbers: Set(players.map { min(max($0.shirtNumber, 0), 99) })
        )
        if lods.contains(.far) {
            ReplayFarAthletePaletteProvider.prewarm(for: players)
        }
        if lods.contains(.near) {
            // Fail softly if a bundled head or texture cannot load. Geometry
            // and material decoding occurs before the immersive frame loop.
            try? ReplayAthleteHeadProvider.prewarm()
        }
    }

    static func make(
        configuration: ReplayAthleteConfiguration,
        lod: ReplayAthleteLOD
    ) throws -> ReplayAthleteInstance {
        var metrics = ReplayAthleteBuildMetrics()
        let root = Entity()
        root.name = "full-rig"
        root.scale = [
            configuration.appearance.widthScale,
            configuration.appearance.heightScale,
            1,
        ]

        let kit = configuration.kit
        let shirtMaterial = material(kit.shirt, roughness: 0.84)
        let trimMaterial = material(kit.trim, roughness: 0.79)
        let shortsMaterial = material(kit.shorts, roughness: 0.86)
        let socksMaterial = material(kit.socks, roughness: 0.88)
        let skinMaterial = material(configuration.appearance.skin, roughness: 0.76)
        let hairMaterial = material(configuration.appearance.hair, roughness: 0.96)
        let bootMaterial = material(kit.boots, roughness: 0.50)
        let bootAccentMaterial = material(kit.bootAccent, roughness: 0.66)
        let farPalette = lod == .far
            ? ReplayFarAthletePaletteProvider.materials(for: configuration)
            : nil
        let farKit = lod == .far && ReplayArticulatedFarProvider.isPrewarmed
            ? ReplayArticulatedFarKitProvider.materials(for: configuration) : nil
        let numberMaterial = UnlitMaterial(
            color: kit.number.uiColor,
            applyPostProcessToneMap: false
        )

        @discardableResult
        func addCustomModel(
            _ part: ReplayAthleteMeshLibrary.Part,
            named name: String,
            to parent: Entity,
            material: any Material,
            position: SIMD3<Float> = .zero,
            orientation: simd_quatf = simd_quatf(real: 1, imag: .zero),
            scale: SIMD3<Float> = .one
        ) throws -> ModelEntity {
            let authoredPart: ReplayArticulatedFarProvider.Part?
            switch part {
            case .torso: authoredPart = .torso
            case .shorts: authoredPart = .shorts
            case .wholeLeg: authoredPart = .leg
            case .wholeArm: authoredPart = .arm
            default: authoredPart = nil
            }
            if lod == .far, let authoredPart,
               let model = ReplayArticulatedFarProvider.make(authoredPart, material: material) {
                model.name = name
                // This imported skin uses an actual unit identity, so its
                // local matrix and weighted floor support share one basis.
                let rotation = orientation.vector == .zero
                    ? simd_quatf(real: 1, imag: .zero) : orientation
                model.transform = Transform(scale: scale, rotation: rotation, translation: position)
                parent.addChild(model)
                metrics.modelEntities += 1
                metrics.verticesPerInstance += authoredPart.metrics.vertices
                metrics.trianglesPerInstance += authoredPart.metrics.triangles
                return model
            }
            let asset = try ReplayAthleteMeshLibrary.mesh(for: part, lod: lod)
            let model = ModelEntity(mesh: asset.mesh, materials: [material])
            model.name = name
            model.position = position
            model.orientation = orientation
            model.scale = scale
            parent.addChild(model)
            metrics.modelEntities += 1
            metrics.verticesPerInstance += asset.metrics.vertices
            metrics.trianglesPerInstance += asset.metrics.triangles
            return model
        }

        func addPrimitiveModel(
            mesh: MeshResource,
            named name: String,
            to parent: Entity,
            material: any Material,
            position: SIMD3<Float> = .zero,
            scale: SIMD3<Float> = .one,
            estimatedMetrics: ReplayAthleteMeshMetrics
        ) {
            let model = ModelEntity(mesh: mesh, materials: [material])
            model.name = name
            model.position = position
            model.scale = scale
            parent.addChild(model)
            metrics.modelEntities += 1
            metrics.verticesPerInstance += estimatedMetrics.vertices
            metrics.trianglesPerInstance += estimatedMetrics.triangles
        }

        if lod != .far {
            addPrimitiveModel(
                mesh: contactShadowMesh,
                named: "contact-shadow",
                to: root,
                material: UnlitMaterial(
                    color: UIColor(red: 0, green: 0.012, blue: 0.008, alpha: 0.20),
                    applyPostProcessToneMap: false
                ),
                position: [0, 0.004, 0],
                scale: [1, 1, 0.62],
                estimatedMetrics: .init(vertices: 50, triangles: 48)
            )
        }

        let bodyRoot = Entity()
        bodyRoot.name = ReplayAthleteJoint.bodyRoot.rawValue
        root.addChild(bodyRoot)

        let hips = Entity()
        hips.name = ReplayAthleteJoint.hips.rawValue
        hips.position = [0, 0.90, 0]
        bodyRoot.addChild(hips)
        try addCustomModel(.shorts, named: "shorts", to: hips,
                           material: farKit.map { $0.shorts as any Material } ?? shortsMaterial)

        let spine = Entity()
        spine.name = ReplayAthleteJoint.spine.rawValue
        spine.position = [0, 0.14, 0]
        hips.addChild(spine)
        try addCustomModel(.torso, named: "torso", to: spine,
                           material: farKit.map { $0.torso as any Material } ?? shirtMaterial)

        if lod == .near {
            for (side, x, angle) in [
                ("left", Float(-0.178), Float(-0.045)),
                ("right", Float(0.178), Float(0.045)),
            ] {
                let stripe = try addCustomModel(
                    .jerseyStripe,
                    named: "\(side)-kit-stripe",
                    to: spine,
                    material: trimMaterial,
                    position: [x, 0.275, 0.143]
                )
                stripe.orientation = simd_quatf(angle: angle, axis: [0, 0, 1])
            }
        }

        // Give the neck its own pivot instead of leaving a static cylinder on
        // the torso while the head rotates independently.  The two-joint chain
        // lets the motion solver distribute a footballer's gaze naturally and
        // keeps the head/neck silhouette connected through wide scans.
        let texturedHead: ModelEntity?
        switch lod {
        case .near:
            texturedHead = ReplayAthleteHeadProvider.make(appearance: configuration.appearance)
        case .far:
            texturedHead = ReplayFarAthleteHeadProvider.make(appearance: configuration.appearance)
        case .mid:
            texturedHead = nil
        }
        let neck = Entity()
        neck.name = ReplayAthleteJoint.neck.rawValue
        neck.position = [0, 0.585, 0]
        spine.addChild(neck)
        if lod != .far && texturedHead == nil {
            let neckShell = try addCustomModel(
                .neck,
                named: "neck-shell",
                to: neck,
                material: skinMaterial
            )
            neckShell.scale = [1, 1, 0.96]
        }

        let headRoot = Entity()
        headRoot.name = ReplayAthleteJoint.headRoot.rawValue
        // Keep the lower head/neck inside the 1.615 m torso collar. The old
        // far fallback centre left a 25 mm vertical air gap (1.640 vs 1.615 m);
        // lowering only that head removes the open seam without a squad draw.
        // Authored heads retain their signed 125 mm placement contract.
        let headSeat: Float = texturedHead == nil ? (lod == .far ? 0.140 : 0.170) : 0.125
        headRoot.position = [0, headSeat, 0]
        neck.addChild(headRoot)
        if let texturedHead {
            headRoot.addChild(texturedHead)
            metrics.modelEntities += 1
            let headMetrics = lod == .far ? ReplayFarAthleteHeadProvider.metrics : ReplayAthleteHeadProvider.metrics
            metrics.verticesPerInstance += headMetrics.vertices
            metrics.trianglesPerInstance += headMetrics.triangles
        } else {
            try addCustomModel(.head, named: "head", to: headRoot, material: skinMaterial)
            if lod != .far {
                try addCustomModel(.hair, named: "hair", to: headRoot, material: hairMaterial)
            }
        }
        if lod == .near && texturedHead == nil {
            for (side, x) in [("left", Float(-0.048)), ("right", Float(0.048))] {
                addPrimitiveModel(
                    mesh: eyeMesh,
                    named: "\(side)-eye",
                    to: headRoot,
                    material: hairMaterial,
                    position: [x, 0.020, 0.119],
                    estimatedMetrics: .init(vertices: 48, triangles: 80)
                )
            }
            try addCustomModel(
                .nose,
                named: "nose",
                to: headRoot,
                material: skinMaterial,
                position: [0, -0.004, 0.124]
            )
        }

        for (side, x) in [("left", Float(-0.137)), ("right", Float(0.137))] {
            let hip = Entity()
            hip.name = "\(side)-hip"
            hip.position = [x, -0.070, 0]
            hips.addChild(hip)

            let knee = Entity()
            knee.name = "\(side)-knee"
            knee.position.y = -0.390
            hip.addChild(knee)

            let ankle = Entity()
            ankle.name = "\(side)-ankle"
            ankle.position.y = -0.350
            knee.addChild(ankle)

            if lod == .far {
                try addCustomModel(.wholeLeg, named: "\(side)-leg", to: hip,
                                   material: farPalette?.leg ?? socksMaterial)
            } else {
                try addCustomModel(.thigh, named: "\(side)-thigh", to: hip, material: skinMaterial)
                try addCustomModel(.shin, named: "\(side)-shin", to: knee, material: socksMaterial)
            }
            if lod != .far {
                try addCustomModel(.boot, named: "\(side)-boot", to: ankle, material: bootMaterial)
            }

            if lod == .near {
                let accent = try addCustomModel(
                    .jerseyStripe,
                    named: "\(side)-boot-accent",
                    to: ankle,
                    material: bootAccentMaterial,
                    position: [0, -0.004, 0.105],
                    scale: [1.25, 0.20, 1]
                )
                accent.orientation = simd_quatf(angle: .pi / 2, axis: [1, 0, 0])
            }
        }

        for (side, x, roll) in [
            // Sit the rotation centres just inside the shirt shell. The old
            // surface-level pivots could reveal daylight between the torso and
            // a forward-driving sleeve even though both meshes were closed.
            ("left", Float(-0.218), Float(-0.025)),
            ("right", Float(0.218), Float(0.025)),
        ] {
            let shoulder = Entity()
            shoulder.name = "\(side)-shoulder"
            shoulder.position = [x, 0.470, 0]
            shoulder.orientation = simd_quatf(angle: roll, axis: [0, 0, 1])
            spine.addChild(shoulder)

            let elbow = Entity()
            elbow.name = "\(side)-elbow"
            elbow.position.y = -0.310
            shoulder.addChild(elbow)

            let wrist = Entity()
            wrist.name = "\(side)-wrist"
            wrist.position.y = -0.275
            elbow.addChild(wrist)

            if lod == .far {
                try addCustomModel(.wholeArm, named: "\(side)-arm", to: shoulder,
                                   material: farPalette?.arm ?? shirtMaterial)
            } else {
                try addCustomModel(.sleeve, named: "\(side)-sleeve", to: shoulder, material: shirtMaterial)
                try addCustomModel(
                    .upperArm,
                    named: "\(side)-upper-arm",
                    to: shoulder,
                    material: configuration.goalkeeper ? shirtMaterial : skinMaterial
                )
                try addCustomModel(
                    .forearm,
                    named: "\(side)-forearm",
                    to: elbow,
                    material: configuration.goalkeeper ? shirtMaterial : skinMaterial,
                    scale: configuration.goalkeeper ? [1.10, 1, 1.10] : .one
                )
                if lod == .near {
                    try addCustomModel(
                        .hand,
                        named: "\(side)-hand",
                        to: wrist,
                        material: configuration.goalkeeper ? trimMaterial : skinMaterial,
                        scale: configuration.goalkeeper ? [1.35, 1.25, 1.20] : .one
                    )
                }
            }
        }

        let numberAsset = lod == .far
            ? nil
            : try ReplayAthleteMeshLibrary.jerseyNumber(configuration.shirtNumber)
        func addNumber(
            named name: String,
            position: SIMD3<Float>,
            yaw: Float,
            scale: Float
        ) {
            guard let numberAsset else { return }
            let number = ModelEntity(mesh: numberAsset.mesh, materials: [numberMaterial])
            number.name = name
            number.position = position
            number.orientation = simd_quatf(angle: yaw, axis: [0, 1, 0])
            number.scale = SIMD3<Float>(repeating: scale)
            spine.addChild(number)
            metrics.modelEntities += 1
            metrics.verticesPerInstance += numberAsset.metrics.vertices
            metrics.trianglesPerInstance += numberAsset.metrics.triangles
        }

        // At far distance a 25 cm physical digit is below useful angular size;
        // the tactical identity tag remains the accessible number. Omitting
        // that unreadable draw keeps a complete 22-player far squad at 154
        // athlete draws before pitch, tag and annotation content.
        if lod != .far {
            addNumber(
                named: "shirt-number",
                position: [0, 0.295, -0.149],
                yaw: .pi,
                scale: 0.29
            )
        }
        if lod == .near {
            addNumber(
                named: "chest-number",
                position: [0.075, 0.318, 0.149],
                yaw: 0,
                scale: 0.115
            )
        }

        guard metrics.fits(lod.budget) else {
            throw ReplayAthleteRigError.geometryBudgetExceeded(lod: lod, metrics: metrics)
        }
        let binding = try ReplayAthleteJointBinding(root: root)
        return ReplayAthleteInstance(
            root: root,
            joints: binding,
            configuration: configuration,
            lod: lod,
            metrics: metrics
        )
    }

    private static func material(_ color: ReplayAthleteColor, roughness: Float) -> SimpleMaterial {
        SimpleMaterial(
            color: color.uiColor,
            roughness: .float(roughness),
            isMetallic: false
        )
    }
}
