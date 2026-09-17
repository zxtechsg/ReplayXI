import Foundation
import simd

/// Explicit recorded contact intent. Positions are pitch-space metres, and
/// times are absolute replay seconds. This does not move the player or ball.
struct ReplayAthleteInteractionCue: Equatable, Sendable {
    enum Kind: String, Equatable, Sendable {
        case receive, pass, shot, dribbleTouch, header, save

        var usesFeet: Bool { self != .header && self != .save }
    }

    let playerID: String
    let kind: Kind
    let contactTime: TimeInterval
    let startTime: TimeInterval
    let endTime: TimeInterval
    let kickingLeg: ReplayAthleteLeg
    let contactBallWorldPosition: SIMD3<Float>
    let outgoingDirectionWorld: SIMD3<Float>
    let supportFootWorldPosition: SIMD3<Float>?

    init(playerID: String, kind: Kind, contactTime: TimeInterval,
         startTime: TimeInterval, endTime: TimeInterval,
         kickingLeg: ReplayAthleteLeg, contactBallWorldPosition: SIMD3<Float>,
         outgoingDirectionWorld: SIMD3<Float>, supportFootWorldPosition: SIMD3<Float>? = nil) {
        self.playerID = playerID
        self.kind = kind
        self.contactTime = contactTime
        self.startTime = startTime
        self.endTime = endTime
        self.kickingLeg = kickingLeg
        self.contactBallWorldPosition = contactBallWorldPosition
        self.outgoingDirectionWorld = outgoingDirectionWorld
        self.supportFootWorldPosition = supportFootWorldPosition
    }
}

/// Compact actor-local goals, shared by the procedural rig, licensed skin and
/// native ball's boot proxies. No Entity lookup or previous-frame state.
struct ReplayAthleteInteractionSample: Sendable {
    let kind: ReplayAthleteInteractionCue.Kind
    let kickingLeg: ReplayAthleteLeg
    let ballCentreTarget: SIMD3<Float>
    let strikeSurfaceTarget: SIMD3<Float>
    let supportSoleTarget: SIMD3<Float>
    let footOrientation: simd_quatf
    let supportFootOrientation: simd_quatf
    let influence: Float
    let pelvisTurn: Float
    let upperBodyPitch: Float
    let headPitch: Float

    func plantedSoleTarget(for side: ReplayAthleteLeg) -> SIMD3<Float> {
        guard side == kickingLeg else { return supportSoleTarget }
        return supportSoleTarget + supportFootOrientation.act([side == .left ? -0.274 : 0.274, 0, 0])
    }
}

/// Shared geometric palm goal. The palm marker is a rig-space convention;
/// unlike boot markers it is not a promise of exact deformed hand-surface contact.
enum ReplayAthleteParryIK {
    static let palmMarker = SIMD3<Float>(0, -0.070, 0.020)
    struct Solution {
        let elbow: SIMD3<Float>
        let wrist: SIMD3<Float>
        let upperRotation: simd_quatf
        let lowerRotation: simd_quatf
        let handRotation: simd_quatf
    }

    static func solve(ballCentre: SIMD3<Float>, shoulder: SIMD3<Float>, side: ReplayAthleteLeg,
                      upperLength: Float, lowerLength: Float) -> Solution? {
        let delta = ballCentre - shoulder
        let length = simd_length(delta)
        guard length.isFinite, length > 0.000_01 else { return nil }
        let direction = delta / length
        let palm = ballCentre - direction * 0.11
        let hand = simd_quatf(from: [0, 0, 1], to: direction)
        let wrist = palm - hand.act(palmMarker)
        guard let solved = ReplayAthleteTwoBoneIK.solve(hip: shoulder, ankle: wrist,
            upperLength: upperLength, lowerLength: lowerLength,
            pole: [side == .left ? -1 : 1, 0.15, 0.2]) else { return nil }
        return Solution(elbow: solved.knee, wrist: solved.ankle,
                        upperRotation: solved.upperRotation, lowerRotation: solved.lowerRotation,
                        handRotation: hand)
    }
}

enum ReplayAthleteTwoBoneIK {
    struct Solution: Sendable {
        let knee: SIMD3<Float>
        let ankle: SIMD3<Float>
        let upperRotation: simd_quatf
        let lowerRotation: simd_quatf
        let wasClamped: Bool
    }

    /// A fixed-length, pole-constrained solve. Unreachable goals are projected
    /// onto the reachable shell; neither bone is stretched to hide the error.
    static func solve(hip: SIMD3<Float>, ankle goal: SIMD3<Float>,
                      upperLength: Float, lowerLength: Float,
                      pole: SIMD3<Float>) -> Solution? {
        guard finite(hip), finite(goal), finite(pole),
              upperLength.isFinite, lowerLength.isFinite,
              (0.05...1.5).contains(upperLength), (0.05...1.5).contains(lowerLength)
        else { return nil }
        let delta = goal - hip
        let rawDistance = simd_length(delta)
        guard rawDistance.isFinite else { return nil }
        let direction = rawDistance > 0.000_001 ? delta / rawDistance : SIMD3<Float>(0, -1, 0)
        let minimum = abs(upperLength - lowerLength) + 0.000_01
        let maximum = upperLength + lowerLength - 0.000_01
        let distance = min(max(rawDistance, minimum), maximum)
        var bend = pole - direction * simd_dot(pole, direction)
        if simd_length_squared(bend) < 0.000_001 {
            let fallback: SIMD3<Float> = abs(direction.z) < 0.9 ? [0, 0, 1] : [1, 0, 0]
            bend = fallback - direction * simd_dot(fallback, direction)
        }
        bend = simd_normalize(bend)
        let projection = (upperLength * upperLength - lowerLength * lowerLength
                          + distance * distance) / (2 * distance)
        let height = sqrt(max(upperLength * upperLength - projection * projection, 0))
        let knee = hip + direction * projection + bend * height
        let ankle = hip + direction * distance
        return Solution(knee: knee, ankle: ankle,
                        upperRotation: simd_quatf(from: [0, -1, 0], to: simd_normalize(knee - hip)),
                        lowerRotation: simd_quatf(from: [0, -1, 0], to: simd_normalize(ankle - knee)),
                        wasClamped: distance != rawDistance)
    }

    private static func finite(_ point: SIMD3<Float>) -> Bool {
        point.x.isFinite && point.y.isFinite && point.z.isFinite
    }
}

@MainActor
enum ReplayAthleteInteractionPose {
    static let ballRadius: Float = 0.11
    // Markers on the admitted articulated-far boot. Other meshes use their own
    // rest-space anchors; these are not a claim of exact imported skin collision.
    static let bootStrikeMarker = SIMD3<Float>(0, -0.050, 0.200)
    static let bootSoleMarker = SIMD3<Float>(0, -0.092, 0.035)

    static func sample(cue: ReplayAthleteInteractionCue?, at time: TimeInterval,
                       track: PlayerTrack, presentationPose: PlayerPose? = nil)
        -> ReplayAthleteInteractionSample? {
        guard let cue, cue.playerID == track.id, time.isFinite,
              cue.startTime.isFinite, cue.contactTime.isFinite, cue.endTime.isFinite,
              cue.startTime <= cue.contactTime, cue.contactTime <= cue.endTime,
              cue.contactTime - cue.startTime <= 2, cue.endTime - cue.contactTime <= 2,
              cue.endTime > cue.startTime, time >= cue.startTime, time <= cue.endTime,
              valid(cue.contactBallWorldPosition), valid(cue.outgoingDirectionWorld),
              cue.supportFootWorldPosition.map(valid) ?? true,
              (-0.05...(cue.kind.usesFeet ? 1.2 : 2.8)).contains(cue.contactBallWorldPosition.y)
        else { return nil }
        let directionLength = simd_length(cue.outgoingDirectionWorld)
        guard directionLength > 0.000_01, directionLength.isFinite else { return nil }
        let direction = cue.outgoingDirectionWorld / directionLength
        let current = presentationPose ?? track.presentationPose(at: time)
        let contact = track.presentationPose(at: cue.contactTime)
        guard valid(current), valid(contact) else { return nil }
        let origin = SIMD3<Float>(current.position.x, 0, current.position.z)
        let heading = simd_quatf(angle: current.facingDegrees * .pi / 180, axis: [0, 1, 0])
        let contactHeading = simd_quatf(angle: contact.facingDegrees * .pi / 180, axis: [0, 1, 0])
        let contactOrigin = SIMD3<Float>(contact.position.x, 0, contact.position.z)
        let supportX: Float = cue.kickingLeg == .left ? 0.137 : -0.137
        let supportWorld = cue.supportFootWorldPosition
            ?? (contactOrigin + contactHeading.act([supportX, 0, 0.035]))

        // A short full-support interval makes the plant a real stable target,
        // not a single frame. The outer quintic edges have zero endpoint slope.
        let plantStart = max(cue.startTime, cue.contactTime - 0.055)
        let plantEnd = min(cue.endTime, cue.contactTime + 0.070)
        let entering = plantStart > cue.startTime
            ? smooth(Float((time - cue.startTime) / (plantStart - cue.startTime))) : 1
        let leaving = cue.endTime > plantEnd
            ? 1 - smooth(Float((time - plantEnd) / (cue.endTime - plantEnd))) : 1
        let influence = min(entering, leaving)
        guard influence > 0 else { return nil }

        let phase: Float
        if time <= cue.contactTime {
            let duration = max(cue.contactTime - cue.startTime, 0.000_001)
            phase = -smooth(Float((cue.contactTime - time) / duration))
        } else {
            let duration = max(cue.endTime - cue.contactTime, 0.000_001)
            phase = smooth(Float((time - cue.contactTime) / duration))
        }
        let travel: Float
        switch cue.kind {
        case .receive: travel = phase < 0 ? phase * 0.025 : -phase * 0.065
        case .dribbleTouch: travel = phase * 0.055
        case .pass: travel = phase * (phase < 0 ? 0.16 : 0.22)
        case .shot: travel = phase * (phase < 0 ? 0.24 : 0.32)
        case .header, .save: travel = 0
        }
        let surfaceWorld = cue.contactBallWorldPosition - direction * ballRadius + direction * travel
        let localDirection = heading.inverse.act(direction)
        let horizontal = SIMD2<Float>(localDirection.x, localDirection.z)
        let yaw = simd_length_squared(horizontal) > 0.000_001 ? atan2(horizontal.x, horizontal.y) : 0
        // Launch elevation is an impulse direction, not the boot's angle.
        // Tilting a grounded toe up to that vector drives the heel through
        // turf, then the floor guard necessarily lifts the contact away.
        let elevatedFoot = smooth((cue.contactBallWorldPosition.y - 0.22) / 0.30)
        let pitch = -asin(min(max(localDirection.y, -0.45), 0.45)) * elevatedFoot
        return ReplayAthleteInteractionSample(
            kind: cue.kind,
            kickingLeg: cue.kickingLeg,
            ballCentreTarget: heading.inverse.act(cue.contactBallWorldPosition - origin),
            strikeSurfaceTarget: heading.inverse.act(surfaceWorld - origin),
            supportSoleTarget: heading.inverse.act(supportWorld - origin),
            footOrientation: simd_quatf(angle: yaw, axis: [0, 1, 0])
                * simd_quatf(angle: pitch, axis: [1, 0, 0]),
            supportFootOrientation: simd_normalize(heading.inverse * contactHeading),
            influence: influence,
            pelvisTurn: min(max(yaw, -0.35), 0.35),
            upperBodyPitch: cue.kind == .header ? -0.12 - phase * 0.18 : (cue.kind == .save ? -0.08 : 0),
            headPitch: cue.kind == .header ? -0.05 - phase * 0.12 : 0
        )
    }

    static func apply(to base: ReplayAthleteLocomotionPose, cue: ReplayAthleteInteractionCue?,
                      at time: TimeInterval, track: PlayerTrack,
                      presentationPose: PlayerPose? = nil) -> ReplayAthleteLocomotionPose {
        guard let sample = sample(cue: cue, at: time, track: track, presentationPose: presentationPose)
        else { return base }
        return apply(to: base, sample: sample)
    }

    static func apply(to base: ReplayAthleteLocomotionPose,
                      sample: ReplayAthleteInteractionSample) -> ReplayAthleteLocomotionPose {
        let weight = sample.influence
        let pelvis = simd_quatf(angle: sample.pelvisTurn * weight, axis: [0, 1, 0]) * base.hipsOrientation
        // Local crouch creates knee flexion for a supporting boot; it does not
        // alter the authoritative player root or the action's pitch-space target.
        let crouch: Float
        if sample.kind == .save {
            // Even a high parry needs knee room for a real support plant.
            // Zero crouch can put ankle goals beyond the .39+.35m leg shell.
            crouch = min(max(1.08 - sample.ballCentreTarget.y, 0.045), 0.34)
        } else { crouch = sample.kind.usesFeet ? 0.045 : 0 }
        let bodyPosition = base.bodyPosition - SIMD3<Float>(0, crouch * weight, 0)
        let hipsPosition = bodyPosition + base.bodyOrientation.act(base.hipsPosition)
        let hipsRotation = simd_normalize(base.bodyOrientation * pelvis)

        func leg(_ side: ReplayAthleteLeg) -> (simd_quatf, simd_quatf, simd_quatf) {
            let hip = side == .left ? base.leftHipOrientation : base.rightHipOrientation
            let knee = side == .left ? base.leftKneeOrientation : base.rightKneeOrientation
            let ankle = side == .left ? base.leftAnkleOrientation : base.rightAnkleOrientation
            guard sample.kind.usesFeet || sample.kind == .save else { return (hip, knee, ankle) }
            let striking = sample.kind.usesFeet && side == sample.kickingLeg
            let orientation = striking ? sample.footOrientation : sample.supportFootOrientation
            let marker = striking ? bootStrikeMarker : bootSoleMarker
            let surface = striking ? sample.strikeSurfaceTarget : sample.plantedSoleTarget(for: side)
            let target = surface - orientation.act(marker)
            let hipPosition = hipsPosition + hipsRotation.act([side == .left ? -0.137 : 0.137, -0.070, 0])
            guard let solved = ReplayAthleteTwoBoneIK.solve(hip: hipPosition, ankle: target,
                                                          upperLength: 0.390, lowerLength: 0.350,
                                                          pole: orientation.act([0, 0, 1]))
            else { return (hip, knee, ankle) }
            return (blend(hip, hipsRotation.inverse * solved.upperRotation, weight),
                    blend(knee, solved.upperRotation.inverse * solved.lowerRotation, weight),
                    blend(ankle, solved.lowerRotation.inverse * orientation, weight))
        }
        let left = leg(.left)
        let right = leg(.right)
        let counter = simd_quatf(angle: -sample.pelvisTurn * weight * 0.45, axis: [0, 1, 0])
        let spineOrientation = simd_quatf(angle: sample.upperBodyPitch * weight, axis: [1, 0, 0])
            * counter * base.spineOrientation
        let spinePosition = hipsPosition + hipsRotation.act([0, 0.14, 0])
        let torso = hipsRotation * spineOrientation
        func arm(_ side: ReplayAthleteLeg) -> (simd_quatf, simd_quatf, simd_quatf) {
            let oldShoulder = side == .left ? base.leftShoulderOrientation : base.rightShoulderOrientation
            let oldElbow = side == .left ? base.leftElbowOrientation : base.rightElbowOrientation
            let oldWrist = side == .left ? base.leftWristOrientation : base.rightWristOrientation
            if sample.kind == .save {
                let shoulder = spinePosition + torso.act([side == .left ? -0.218 : 0.218, 0.470, 0])
                if let solved = ReplayAthleteParryIK.solve(ballCentre: sample.ballCentreTarget,
                    shoulder: shoulder, side: side, upperLength: 0.310, lowerLength: 0.275) {
                    return (blend(oldShoulder, torso.inverse * solved.upperRotation, weight),
                            blend(oldElbow, solved.upperRotation.inverse * solved.lowerRotation, weight),
                            blend(oldWrist, solved.lowerRotation.inverse * solved.handRotation, weight))
                }
            }
            return (blend(oldShoulder, simd_quatf(angle: side == .left ? -0.28 : 0.28, axis: [0, 0, 1])
                * simd_quatf(angle: -0.18, axis: [1, 0, 0]), weight),
                    blend(oldElbow, simd_quatf(angle: -0.55, axis: [1, 0, 0]), weight), oldWrist)
        }
        let leftArm = arm(.left)
        let rightArm = arm(.right)
        return ReplayAthleteLocomotionPose(
            bodyPosition: bodyPosition, bodyOrientation: base.bodyOrientation,
            hipsPosition: base.hipsPosition, hipsOrientation: pelvis,
            spineOrientation: spineOrientation,
            neckOrientation: base.neckOrientation,
            headOrientation: simd_quatf(angle: sample.headPitch * weight, axis: [1, 0, 0]) * base.headOrientation,
            leftHipOrientation: left.0, rightHipOrientation: right.0,
            leftKneeOrientation: left.1, rightKneeOrientation: right.1,
            leftAnkleOrientation: left.2, rightAnkleOrientation: right.2,
            leftShoulderOrientation: leftArm.0, rightShoulderOrientation: rightArm.0,
            leftElbowOrientation: leftArm.1, rightElbowOrientation: rightArm.1,
            leftWristOrientation: leftArm.2, rightWristOrientation: rightArm.2
        )
    }

    nonisolated static func blend(_ a: simd_quatf, _ b: simd_quatf, _ weight: Float) -> simd_quatf {
        let target = simd_dot(a.vector, b.vector) < 0 ? simd_quatf(vector: -b.vector) : b
        return simd_normalize(simd_slerp(a, target, weight))
    }

    private static func smooth(_ value: Float) -> Float {
        let x = min(max(value, 0), 1)
        return x * x * x * (x * (x * 6 - 15) + 10)
    }

    private static func valid(_ point: SIMD3<Float>) -> Bool {
        point.x.isFinite && point.y.isFinite && point.z.isFinite
            && abs(point.x) < 10_000 && abs(point.y) < 10_000 && abs(point.z) < 10_000
    }

    private static func valid(_ pose: PlayerPose) -> Bool {
        pose.position.x.isFinite && pose.position.z.isFinite && pose.facingDegrees.isFinite
            && abs(pose.position.x) < 10_000 && abs(pose.position.z) < 10_000
            && abs(pose.facingDegrees) < 100_000
    }
}
