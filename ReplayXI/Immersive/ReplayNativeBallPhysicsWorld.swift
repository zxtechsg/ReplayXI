import Foundation
import RealityKit
import simd

/// An offscreen, native RealityKit physics world. No visual mesh or texture is
/// needed. The renderer's documented update(_:) method ticks the actual solver.
/// This object lives only during a bake; retained recordings contain numbers.
@MainActor
final class ReplayNativeBallPhysicsWorld {
    let renderer: RealityRenderer
    let root = Entity()
    let ball = ModelEntity()
    let pitch = ModelEntity()
    private struct PlayerBodies {
        let torso: ModelEntity
        let head: ModelEntity
        let leftBoot: ModelEntity
        let rightBoot: ModelEntity
        let leftShin: ModelEntity
        let rightShin: ModelEntity
    }
    private var bodies: [PlayerBodies] = []
    private var intents: [ReplayNativeBallPhysics.Intent] = []
    private var completedTouches: [ReplayNativeBallPhysics.Touch] = []
    private var isPlacingPlayers = false
    private static let ballGroup = CollisionGroup(rawValue: 1 << 22)
    private static let obstacleGroup = CollisionGroup(rawValue: 1 << 23)
    // A world-space cap includes authored root travel. The head must share
    // the torso's budget; 8 m/s is only the separate limb-proxy world cap.
    private static let maximumBodyProxyWorldSpeed: Float = 12
    private let playerMaterial: PhysicsMaterialResource
    private let legacyBootShape: ShapeResource
    private let interactionBootShape: ShapeResource
    private let shinShape: ShapeResource

    init(gravity: SIMD3<Float> = [0, -9.81, 0], includePitch: Bool = true, includeGoals: Bool = true) throws {
        renderer = try RealityRenderer()
        root.name = "native-ball-physics-world"
        var simulation = PhysicsSimulationComponent()
        simulation.gravity = gravity
        simulation.solverIterations = .init(positionIterations: 12, velocityIterations: 4)
        root.components.set(simulation)
        let ballShape = ShapeResource.generateSphere(radius: ReplayNativeBallPhysics.radius)
        let ballMaterial = PhysicsMaterialResource.generate(staticFriction: 0.55, dynamicFriction: 0.42,
                                                           restitution: 0.46)
        playerMaterial = .generate(staticFriction: 0.7, dynamicFriction: 0.5, restitution: 0.22)
        // RealityKit capsule height includes both spherical caps. These equal
        // the joint-chain centreline length plus two radii, not just the line.
        legacyBootShape = .generateCapsule(height: 0.321, radius: 0.070)
        interactionBootShape = .generateCapsule(height: 0.276, radius: 0.070)
        shinShape = .generateCapsule(height: 0.500, radius: 0.075)
        ball.name = "native-physics-match-ball"
        ball.components.set(CollisionComponent(shapes: [ballShape], mode: .default,
                                             filter: .init(group: Self.ballGroup, mask: Self.obstacleGroup)))
        var body = PhysicsBodyComponent(shapes: [ballShape], mass: ReplayNativeBallPhysics.mass,
                                       material: ballMaterial, mode: .dynamic)
        body.isContinuousCollisionDetectionEnabled = true
        body.linearDamping = 0.055
        body.angularDamping = 0.16
        ball.components.set(body)
        ball.components.set(PhysicsMotionComponent())
        root.addChild(ball)
        if includePitch {
            let shape = ShapeResource.generateBox(size: [220, 0.2, 220])
            pitch.name = "native-physics-pitch"
            pitch.position = [0, -0.1, 0]
            pitch.components.set(CollisionComponent(shapes: [shape], mode: .default,
                                                   filter: .init(group: Self.obstacleGroup, mask: Self.ballGroup)))
            pitch.components.set(PhysicsBodyComponent(shapes: [shape], mass: 1,
                                                      material: .generate(staticFriction: 0.65, dynamicFriction: 0.50,
                                                                          restitution: 0.42), mode: .static))
            root.addChild(pitch)
            if includeGoals {
                ReplayNativeBallPhysicsGoals.install(in: root, ballGroup: Self.ballGroup,
                                                      obstacleGroup: Self.obstacleGroup)
            }
        }
        renderer.entities.append(root)
    }

    func placeBall(position: SIMD3<Float>, velocity: SIMD3<Float> = .zero,
                   angularVelocity: SIMD3<Float> = .zero) {
        ball.position = position
        ball.components.set(PhysicsMotionComponent(linearVelocity: velocity, angularVelocity: angularVelocity))
    }

    func start() throws { try renderer.update(0) }

    func configureIntents(_ intents: [ReplayNativeBallPhysics.Intent]) {
        self.intents = intents
        completedTouches.reserveCapacity(intents.count)
    }

    func addPlayers(_ players: [PlayerTrack], ball track: BallTrack, at time: TimeInterval) {
        bodies.reserveCapacity(players.count)
        let torsoShape = ShapeResource.generateCapsule(height: 1.16, radius: 0.23)
        let headShape = ShapeResource.generateSphere(radius: 0.11)
        for player in players {
            // Torso starts above the boots: the sphere can travel through a
            // genuine open stance, but not through the hips/chest. A separate
            // narrow head avoids a shoulder-width cap above the real skull.
            let torso = proxy(shape: torsoShape,
                              name: "native-player-\(player.id)-body")
            let head = proxy(shape: headShape, name: "native-player-\(player.id)-head")
            let left = proxy(shape: legacyBootShape,
                             name: "native-player-\(player.id)-left-boot")
            let right = proxy(shape: legacyBootShape,
                              name: "native-player-\(player.id)-right-boot")
            let leftShin = proxy(shape: shinShape,
                                 name: "native-player-\(player.id)-left-shin")
            let rightShin = proxy(shape: shinShape,
                                  name: "native-player-\(player.id)-right-shin")
            bodies.append(PlayerBodies(torso: torso, head: head, leftBoot: left, rightBoot: right,
                                       leftShin: leftShin, rightShin: rightShin))
        }
        isPlacingPlayers = true
        movePlayers(players, ball: track, time: time, delta: ReplayNativeBallPhysics.step)
        isPlacingPlayers = false
    }

    private func proxy(shape: ShapeResource, name: String) -> ModelEntity {
        let entity = ModelEntity()
        entity.name = name
        entity.components.set(CollisionComponent(shapes: [shape], mode: .default,
                                                filter: .init(group: Self.obstacleGroup, mask: Self.ballGroup)))
        entity.components.set(PhysicsBodyComponent(shapes: [shape], mass: 70,
                                                   material: playerMaterial, mode: .kinematic))
        entity.components.set(PhysicsMotionComponent())
        root.addChild(entity)
        return entity
    }

    func movePlayers(_ players: [PlayerTrack], ball track: BallTrack,
                     time: TimeInterval, delta: TimeInterval) {
        guard delta > 0 else { return }
        for (index, player) in players.enumerated() where index < bodies.count {
            let body = bodies[index]
            let current = player.presentationPose(at: time)
            let next = player.presentationPose(at: time + delta)
            let p = SIMD3<Float>(current.position.x, 1.04, current.position.z)
            let n = SIMD3<Float>(next.position.x, 1.04, next.position.z)
            move(body.torso, from: p, to: n, delta: delta,
                 maximumSpeed: Self.maximumBodyProxyWorldSpeed, reset: isPlacingPlayers)
            let horizontalDelta = SIMD2<Float>(current.position.x - ball.position.x,
                                                current.position.z - ball.position.z)
            let cue = interaction(for: player, at: time)
            let headNearby = simd_length_squared(horizontalDelta) < 3.0 * 3.0
                && (ball.position.y > 0.8 || cue?.kind == .header || cue?.kind == .save)
            let headStart = headNearby ? headCentre(player: player, at: time, pose: current, cue: cue)
                : SIMD3<Float>(current.position.x, 1.74, current.position.z)
            let headEnd = headNearby ? headCentre(player: player, at: time + delta, pose: next, cue: cue)
                : SIMD3<Float>(next.position.x, 1.74, next.position.z)
            move(body.head, from: headStart, to: headEnd, delta: delta,
                 maximumSpeed: Self.maximumBodyProxyWorldSpeed, reset: isPlacingPlayers)
            let needsLegs = simd_length_squared(horizontalDelta) < 3.0 * 3.0 && ball.position.y < 1.3
            let resetFeet = isPlacingPlayers || !body.leftBoot.isEnabled
            body.leftBoot.isEnabled = needsLegs
            body.rightBoot.isEnabled = needsLegs
            body.leftShin.isEnabled = needsLegs
            body.rightShin.isEnabled = needsLegs
            guard needsLegs else { continue }
            // Boot collision geometry follows the same articulated chain used
            // by the visible rig, including its kick preparation/follow-through.
            let explicitBoot = cue.map { $0.kind != .header && $0.kind != .save } ?? false
            setBootShape(body.leftBoot, explicit: explicitBoot)
            setBootShape(body.rightBoot, explicit: explicitBoot)
            let contact = ReplayBallPlayerContact(player: player, ball: track, time: time,
                                                  interaction: cue, presentationPose: current)
            let following = ReplayBallPlayerContact(player: player, ball: track, time: time + delta,
                                                    interaction: cue, presentationPose: next)
            moveBoot(body.leftBoot, from: contact.leftBoot, to: following.leftBoot, delta: delta, reset: resetFeet)
            moveBoot(body.rightBoot, from: contact.rightBoot, to: following.rightBoot, delta: delta, reset: resetFeet)
            moveBoot(body.leftShin, from: contact.leftShin, to: following.leftShin, delta: delta, reset: resetFeet)
            moveBoot(body.rightShin, from: contact.rightShin, to: following.rightShin, delta: delta, reset: resetFeet)
        }
    }

    private func headCentre(player: PlayerTrack, at time: TimeInterval, pose: PlayerPose,
                            cue: ReplayAthleteInteractionCue?) -> SIMD3<Float> {
        let articulated = ReplayAthleteMotion.locomotionPose(for: player, at: time,
            lookTargetWorldPosition: ball.position, interaction: cue, presentationPose: pose)
        let heading = simd_quatf(angle: pose.facingDegrees * .pi / 180, axis: [0, 1, 0])
        let body = SIMD3<Float>(pose.position.x, 0, pose.position.z) + heading.act(articulated.bodyPosition)
        let bodyRotation = heading * articulated.bodyOrientation
        let hips = body + bodyRotation.act(articulated.hipsPosition)
        let hipRotation = bodyRotation * articulated.hipsOrientation
        let spine = hips + hipRotation.act([0, 0.14, 0])
        let torsoRotation = hipRotation * articulated.spineOrientation
        // Same fixed pivots as the textured procedural rig. The skull sphere
        // is only an envelope; imported head skins are verified separately.
        return spine + torsoRotation.act([0, 0.585, 0])
            + (torsoRotation * articulated.neckOrientation).act([0, 0.125, 0])
    }

    private func setBootShape(_ boot: ModelEntity, explicit: Bool) {
        let shape = explicit ? interactionBootShape : legacyBootShape
        guard boot.components[CollisionComponent.self]?.shapes.first != shape else { return }
        boot.components.set(CollisionComponent(shapes: [shape], mode: .default,
                                               filter: .init(group: Self.obstacleGroup, mask: Self.ballGroup)))
    }

    #if DEBUG
    func nearestColliderNames(to point: SIMD3<Float>) -> [String] {
        root.children.filter { $0 !== ball && $0 !== pitch && $0.isEnabled }
            .sorted { simd_distance_squared($0.position, point) < simd_distance_squared($1.position, point) }
            .prefix(3).map(\.name)
    }
    #endif

    private func interaction(for player: PlayerTrack, at time: TimeInterval) -> ReplayAthleteInteractionCue? {
        guard let intent = intents.first(where: {
            $0.player.id == player.id && time >= $0.time - 0.32 && time <= $0.time + 0.42
        }), let kind = ReplayAthleteInteractionCue.Kind(rawValue: intent.kind.rawValue) else { return nil }
        let completed = completedTouches.first { $0.playerID == player.id && abs($0.time - intent.time) <= 0.13 }
        if time > intent.time + 0.13, completed == nil { return nil }
        let centre: SIMD3<Float>
        let outgoing: SIMD3<Float>
        if let completed {
            centre = completed.position
            outgoing = completed.outgoingVelocity
        } else {
            let remaining = Float(max(0, intent.time - 0.20 - time))
            let velocity = ball.components[PhysicsMotionComponent.self]?.linearVelocity ?? .zero
            var predicted = ball.position + velocity * remaining
            predicted.y = max(ReplayNativeBallPhysics.radius,
                              predicted.y - 4.905 * remaining * remaining)
            centre = predicted
            outgoing = intent.target - centre
        }
        let actualContact = completed?.time ?? max(intent.time - 0.12, time)
        return ReplayAthleteInteractionCue(playerID: player.id, kind: kind, contactTime: actualContact,
                                           startTime: actualContact - 0.32, endTime: actualContact + 0.42,
                                           kickingLeg: intent.kickingLeg, contactBallWorldPosition: centre,
                                           outgoingDirectionWorld: outgoing)
    }

    private func move(_ entity: ModelEntity, from start: SIMD3<Float>, to end: SIMD3<Float>, delta: TimeInterval,
                      maximumSpeed: Float, reset: Bool) {
        if reset { entity.position = start }
        // Kinematic motion belongs to the native solver. Reassigning a boot
        // transform after early contact could teleport a metre in one tick and
        // create an enormous, unphysical collision impulse.
        var velocity = (end - start) / Float(delta) + (start - entity.position) * 20
        if simd_length(velocity) > maximumSpeed { velocity = simd_normalize(velocity) * maximumSpeed }
        entity.components.set(PhysicsMotionComponent(linearVelocity: velocity,
                                                     angularVelocity: .zero))
    }

    private func moveBoot(_ entity: ModelEntity, from start: ReplayBallPlayerContact.Capsule,
                          to end: ReplayBallPlayerContact.Capsule, delta: TimeInterval, reset: Bool) {
        move(entity, from: (start.start + start.end) * 0.5, to: (end.start + end.end) * 0.5,
             delta: delta, maximumSpeed: 8, reset: reset)
        let direction = (reset ? start.end - start.start : end.end - end.start)
        if simd_length_squared(direction) > 0.0001 {
            let target = simd_quatf(from: [0, 1, 0], to: simd_normalize(direction))
            if reset { entity.orientation = target }
            else {
                let rotation = simd_normalize(target * entity.orientation.inverse)
                var angle = rotation.angle
                if angle > .pi { angle -= 2 * .pi }
                let angularSpeed = min(max(angle / Float(delta), -4 * .pi), 4 * .pi)
                var motion = entity.components[PhysicsMotionComponent.self] ?? .init()
                motion.angularVelocity = abs(angle) > 0.00001 ? rotation.axis * angularSpeed : .zero
                entity.components.set(motion)
            }
        }
    }

    func strike(intent: ReplayNativeBallPhysics.Intent, time: TimeInterval) throws -> ReplayNativeBallPhysics.Touch? {
        let playerPose = intent.player.presentationPose(at: time)
        let distance = simd_length(SIMD2(ball.position.x - playerPose.position.x,
                                        ball.position.z - playerPose.position.z))
        // Impulses are deliberate player actions, not remote attraction. If the
        // ball has missed the receiver, this action cannot magically recover it.
        switch intent.kind {
        case .header:
            guard distance <= 0.65, (1.55...1.95).contains(ball.position.y) else { return nil }
        case .save:
            // Standing parries cannot fire while the ball is still over a
            // metre away. Wait for the sphere to enter the two-hand envelope.
            // Actual near/low palm contact is checked on every authored save.
            guard intent.player.isGoalkeeper, distance <= 0.50,
                  (0.08...2.10).contains(ball.position.y) else { return nil }
        default:
            guard distance <= 1.05, ball.position.y <= 0.85 else { return nil }
            guard canReachBall(intent: intent, time: time) else { return nil }
        }
        let spinScale: Float = ball.position.y > 0.35 || intent.kind == .header || intent.kind == .save ? 0.18 : 1
        let desired = try ReplayNativeBallPhysicsAim.velocity(from: ball.position, to: intent.target,
                                                               duration: intent.arrivalTime - time,
                                                               spinScale: spinScale)
        applyContactVelocity(desired, spinScale: spinScale)
        let touch = ReplayNativeBallPhysics.Touch(time: time, playerID: intent.player.id,
                                                 position: ball.position, outgoingVelocity: desired,
                                                 kind: intent.kind, kickingLeg: intent.kickingLeg)
        completedTouches.append(touch)
        return touch
    }

    private func canReachBall(intent: ReplayNativeBallPhysics.Intent, time: TimeInterval) -> Bool {
        let estimate = ReplayNativeBallPhysicsAim.initialVelocity(from: ball.position, to: intent.target,
                                                                  duration: intent.arrivalTime - time)
        guard simd_length_squared(estimate) > 0.0001 else { return false }
        let cue = ReplayAthleteInteractionCue(playerID: intent.player.id,
                                             kind: ReplayAthleteInteractionCue.Kind(rawValue: intent.kind.rawValue) ?? .pass,
                                             contactTime: time, startTime: time - 0.32, endTime: time + 0.42,
                                             kickingLeg: intent.kickingLeg, contactBallWorldPosition: ball.position,
                                             outgoingDirectionWorld: estimate)
        let pose = intent.player.presentationPose(at: time)
        // Contact helper only needs the sparse source for the legacy path;
        // with an explicit cue it never infers a kick from these placeholders.
        let track = BallTrack(keyframes: [.init(time: time, position: .init(x: ball.position.x, z: ball.position.z),
                                               height: ball.position.y)])
        let geometry = ReplayBallPlayerContact(player: intent.player, ball: track, time: time,
                                               interaction: cue, presentationPose: pose)
        let toe = intent.kickingLeg == .left ? geometry.leftToe : geometry.rightToe
        let surface = ball.position - simd_normalize(estimate) * ReplayNativeBallPhysics.radius
        // Leave clearance for floor padding and the calibrated launch direction;
        // the rendered rigs must remain within the stricter 30 mm visual limit.
        return simd_distance(toe, surface) <= 0.020
    }

    func applyContactVelocity(_ desired: SIMD3<Float>, spinScale: Float) {
        let old = ball.components[PhysicsMotionComponent.self]?.linearVelocity ?? .zero
        ball.applyLinearImpulse((desired - old) * ReplayNativeBallPhysics.mass, relativeTo: root)
        let spin = SIMD3<Float>(desired.z, 0, -desired.x) / ReplayNativeBallPhysics.radius * spinScale
        let oldSpin = ball.components[PhysicsMotionComponent.self]?.angularVelocity ?? .zero
        // Use the native body's actual inertia rather than assuming a solid
        // sphere coefficient for a generated collision resource.
        if let inertia = ball.components[PhysicsBodyComponent.self]?.massProperties.inertia {
            ball.applyAngularImpulse((spin - oldSpin) * inertia, relativeTo: root)
        }
    }

    func advance(_ delta: TimeInterval) throws {
        // Grass dissipates rolling energy. RealityKit's native friction handles
        // slip/contact; this bounded opposing force models rolling resistance.
        if ball.position.y < ReplayNativeBallPhysics.radius + 0.025,
           let motion = ball.components[PhysicsMotionComponent.self] {
            let velocity = SIMD3<Float>(motion.linearVelocity.x, 0, motion.linearVelocity.z)
            let speed = simd_length(velocity)
            if speed > 0.005 {
                let deceleration: Float = min(0.28, speed / Float(max(delta, 0.0001)))
                ball.addForce(-velocity / speed * (ReplayNativeBallPhysics.mass * deceleration), relativeTo: root)
            }
        }
        try renderer.update(delta)
    }

    func sample(at time: TimeInterval) -> ReplayNativeBallPhysics.Sample {
        let motion = ball.components[PhysicsMotionComponent.self] ?? PhysicsMotionComponent()
        return .init(time: time, position: ball.position, orientation: ball.orientation,
                     velocity: motion.linearVelocity, angularVelocity: motion.angularVelocity)
    }
}
