import Foundation
import simd

/// Immutable presentation path for authored, local replay. Ground travel has
/// bounded easing, loft has smooth height, contacts use the animated boot chain,
/// and nearby body/boot envelopes are swept before publishing the samples.
/// This is a constrained replay repair, not a live rigid-body match simulator.
/// Source keyframes, event times and saved review formats are never modified.
final class ReplayBallPlaybackMotion: Sendable {
    static let ballRadius: Float = 0.11
    static let bodyClearance: Float = 0.41
    /// Coarse upright body/head proxy in metres. Its vertical collision gate
    /// must include the moving sphere's radius, not just its centre height.
    static let bodyVerticalExtent: Float = 1.92
    static let bodyCollisionCentreCeiling: Float = bodyVerticalExtent + ballRadius
    static let maximumSourceFrames = 4_096
    static let maximumSamples = 16_384
    static let maximumPlayers = 32
    static let samplesPerSecond: Double = 90
    static let maximumPresentationOffset: Float = 1.10

    let rolling: ReplayBallRollingMotion
    let isValid: Bool
    /// A finite, ordered source may exceed the preparation budget. Keep its
    /// original playback live, but do not represent it as collision-corrected.
    let usesAuthoredFallback: Bool
    let sampleCount: Int
    let contactCount: Int
    let adjustedSampleCount: Int
    private let frames: [BallKeyframe]

    private struct Contact {
        let playerIndex: Int
        let position: PitchPoint
    }

    private struct Obstacle {
        let centres: [PitchPoint]
        let legs: [ReplayBallPlayerContact?]
    }

    /// Retain numeric values only. Neither a scene, an entity nor a root-owned
    /// motion/rolling object may be kept alive by this small reuse cache.
    private struct PreparedEntry {
        let source: BallTrack
        let players: [PlayerTrack]
        let frames: [BallKeyframe]
        let contacts: Int
        let adjusted: Int
    }

    @MainActor private static var preparedEntries: [PreparedEntry] = []
    static let maximumCachedPaths = 4
    #if DEBUG
    @MainActor private(set) static var preparationCacheHitsForTesting = 0
    @MainActor private(set) static var preparationCacheMissesForTesting = 0
    @MainActor static var cachedPathCountForTesting: Int { preparedEntries.count }
    @MainActor static func resetPreparationCacheForTesting() {
        preparedEntries.removeAll()
        preparationCacheHitsForTesting = 0
        preparationCacheMissesForTesting = 0
    }
    #endif

    /// Scene construction reuses an exact immutable source+player bake. A
    /// direct init intentionally remains cold for diagnostics and tests.
    @MainActor
    static func prepared(track: BallTrack, players: [PlayerTrack]) -> ReplayBallPlaybackMotion {
        if let index = preparedEntries.firstIndex(where: { $0.source == track && $0.players == players }) {
            let entry = preparedEntries.remove(at: index)
            preparedEntries.append(entry)
            #if DEBUG
            preparationCacheHitsForTesting += 1
            #endif
            return ReplayBallPlaybackMotion(prepared: entry)
        }
        #if DEBUG
        preparationCacheMissesForTesting += 1
        #endif
        let motion = ReplayBallPlaybackMotion(track: track, players: players)
        if motion.isValid {
            preparedEntries.append(PreparedEntry(source: track, players: players, frames: motion.frames,
                                                 contacts: motion.contactCount, adjusted: motion.adjustedSampleCount))
            if preparedEntries.count > maximumCachedPaths { preparedEntries.removeFirst() }
        }
        return motion
    }

    private init(prepared entry: PreparedEntry) {
        frames = entry.frames
        rolling = ReplayBallRollingMotion(track: .init(keyframes: entry.frames))
        isValid = true
        usesAuthoredFallback = false
        sampleCount = entry.frames.count
        contactCount = entry.contacts
        adjustedSampleCount = entry.adjusted
    }

    @MainActor
    init(track: BallTrack, players: [PlayerTrack]) {
        guard Self.accepts(track: track, players: players) else {
            // Budget exhaustion must not freeze a valid replay, but the spin
            // sampler's generous numeric bounds are not physical pose bounds.
            // Validate the complete source before constructing its spin table.
            let sourceRolling = Self.acceptsAuthoredFallback(track)
                ? ReplayBallRollingMotion(track: track) : nil
            if let sourceRolling, sourceRolling.isValid {
                frames = track.keyframes
                rolling = sourceRolling
                usesAuthoredFallback = true
                sampleCount = track.keyframes.count
            } else {
                let fallback = Self.safeFirstFrame(in: track)
                frames = [fallback]
                rolling = ReplayBallRollingMotion(track: .init(keyframes: [fallback]))
                usesAuthoredFallback = false
                sampleCount = 1
            }
            isValid = false
            contactCount = 0
            adjustedSampleCount = 0
            return
        }

        let source = track.keyframes
        let contacts: [Contact?] = source.enumerated().map { index, frame in
            guard frame.height <= 0.24 else { return nil }
            var nearest: (Int, Float)?
            for (playerIndex, player) in players.enumerated() {
                let distance = ReplayGeometry.distance(player.presentationPose(at: frame.time).position,
                                                       frame.position)
                if distance < 0.36, distance < (nearest?.1 ?? .greatestFiniteMagnitude) {
                    nearest = (playerIndex, distance)
                }
            }
            guard let (playerIndex, _) = nearest else { return nil }
            let player = players[playerIndex]
            let envelope = ReplayBallPlayerContact(player: player, ball: track, time: frame.time)
            let action = ReplayAthleteMotion.ballActionPose(for: player, ballTrack: track, at: frame.time)
            let leg: ReplayAthleteLeg
            if let action {
                leg = action.kickingLeg
            } else {
                let following = source[min(index + 1, source.count - 1)].position
                let facing = player.presentationPose(at: frame.time).facingDegrees * .pi / 180
                let lateral = (following.x - frame.position.x) * cos(facing)
                    - (following.z - frame.position.z) * sin(facing)
                leg = lateral >= 0 ? .right : .left
            }
            return Contact(playerIndex: playerIndex,
                           position: envelope.strikePoint(leg: leg, ballRadius: Self.ballRadius))
        }

        let anchors = source.enumerated().map { index, frame in
            BallKeyframe(time: frame.time, position: contacts[index]?.position ?? frame.position,
                         height: max(frame.height, Self.ballRadius))
        }
        var prepared: [BallKeyframe] = []
        var sourceSamples: [BallKeyframe] = []
        prepared.reserveCapacity(min(Self.maximumSamples, Int((source.last!.time - source[0].time)
                                                              * Self.samplesPerSecond) + source.count))
        sourceSamples.reserveCapacity(prepared.capacity)
        for index in 0..<(anchors.count - 1) {
            let start = anchors[index]
            let end = anchors[index + 1]
            let subdivisions = max(1, Int(ceil((end.time - start.time) * Self.samplesPerSecond)))
            for step in 0..<subdivisions {
                let fraction = Float(step) / Float(subdivisions)
                let time = start.time + (end.time - start.time) * Double(step) / Double(subdivisions)
                let sourcePosition = source[index].position.interpolated(to: source[index + 1].position,
                                                                          fraction: fraction)
                let interpolated = Self.interpolated(anchors: anchors, contacts: contacts, index: index,
                                                     time: time, fraction: fraction)
                // Sparse non-uniform samples can make otherwise monotone
                // component splines run well ahead of the authored event. Limit
                // that timing displacement before obstacle repair adds its own
                // small lateral clearance; the final bound is against SOURCE.
                let delta = Self.vector(interpolated.position) - Self.vector(sourcePosition)
                let position = simd_length_squared(delta) > 0.75 * 0.75
                    ? Self.vector(sourcePosition) + simd_normalize(delta) * 0.75
                    : Self.vector(interpolated.position)
                prepared.append(.init(time: time, position: .init(x: position.x, z: position.y),
                                      height: interpolated.height))
                sourceSamples.append(.init(time: time, position: sourcePosition, height: interpolated.height))
            }
        }
        prepared.append(anchors.last!)
        sourceSamples.append(source.last!)

        let initial = prepared
        // Only nearby legs need a joint-chain evaluation. Body centres are cheap
        // and retained for the continuous relative sweep between samples.
        let obstacles: [Obstacle] = players.map { player in
            var centres: [PitchPoint] = []
            var legs: [ReplayBallPlayerContact?] = []
            centres.reserveCapacity(prepared.count)
            legs.reserveCapacity(prepared.count)
            for frame in prepared {
                let centre = player.presentationPose(at: frame.time).position
                centres.append(centre)
                let needsLegs = frame.height < 1.0
                    && ReplayGeometry.distance(centre, frame.position) < 1.65
                legs.append(needsLegs
                    ? ReplayBallPlayerContact(player: player, ball: track, time: frame.time) : nil)
            }
            return Obstacle(centres: centres, legs: legs)
        }
        Self.clearObstacles(in: &prepared, source: sourceSamples, obstacles: obstacles)
        frames = prepared
        rolling = ReplayBallRollingMotion(track: .init(keyframes: prepared))
        isValid = true
        usesAuthoredFallback = false
        sampleCount = prepared.count
        contactCount = contacts.compactMap { $0 }.count
        adjustedSampleCount = zip(prepared, initial).reduce(0) { count, pair in
            count + (pair.0.position == pair.1.position ? 0 : 1)
        }
    }

    func pose(at time: TimeInterval) -> BallPose {
        guard let first = frames.first else { return .init(position: .zero, height: Self.ballRadius) }
        guard time.isFinite, time > first.time else {
            return .init(position: first.position, height: first.height)
        }
        guard let last = frames.last, time < last.time else {
            let last = frames.last ?? first
            return .init(position: last.position, height: last.height)
        }
        var lower = 1
        var upper = frames.count - 1
        while lower < upper {
            let middle = lower + (upper - lower) / 2
            if frames[middle].time < time { lower = middle + 1 } else { upper = middle }
        }
        let start = frames[lower - 1]
        let end = frames[lower]
        let fraction = Float((time - start.time) / (end.time - start.time))
        return .init(position: start.position.interpolated(to: end.position, fraction: fraction),
                     height: start.height + (end.height - start.height) * fraction)
    }

    private static func accepts(track: BallTrack, players: [PlayerTrack]) -> Bool {
        let frames = track.keyframes
        guard frames.count >= 2, frames.count <= maximumSourceFrames,
              players.count <= maximumPlayers else { return false }
        var previous = -Double.infinity
        var samples = 1
        for frame in frames {
            guard frame.time.isFinite, abs(frame.time) <= 1_000_000,
                  frame.time > previous, frame.position.x.isFinite, frame.position.z.isFinite,
                  abs(frame.position.x) <= 150, abs(frame.position.z) <= 150,
                  frame.height.isFinite, frame.height >= 0, frame.height <= 20 else { return false }
            if previous.isFinite {
                let count = ceil((frame.time - previous) * samplesPerSecond)
                guard count <= Double(maximumSamples - samples) else { return false }
                samples += max(1, Int(count))
            }
            previous = frame.time
        }
        return players.allSatisfy { player in
            !player.keyframes.isEmpty && player.keyframes.count <= 65_536
                && player.keyframes.allSatisfy { frame in
                    frame.time.isFinite && frame.position.x.isFinite && frame.position.z.isFinite
                        && abs(frame.position.x) <= 150 && abs(frame.position.z) <= 150
                        && frame.facingDegrees.isFinite
                }
        }
    }

    private static func safeFirstFrame(in track: BallTrack) -> BallKeyframe {
        guard let first = track.keyframes.first,
              first.position.x.isFinite, first.position.z.isFinite,
              abs(first.position.x) <= 150, abs(first.position.z) <= 150 else {
            return .init(time: 0, position: .zero, height: ballRadius)
        }
        return .init(time: first.time.isFinite ? first.time : 0, position: first.position,
                     height: first.height.isFinite ? min(max(first.height, ballRadius), 20) : ballRadius)
    }

    private static func acceptsAuthoredFallback(_ track: BallTrack) -> Bool {
        let frames = track.keyframes
        // Check the hard count before walking any input. Long duration and
        // dense sampling are allowed; impossible geometry is not.
        guard frames.count >= 2,
              frames.count <= ReplayBallRollingMotion.maximumKeyframes else { return false }
        var previous = -Double.infinity
        for frame in frames {
            guard frame.time.isFinite, abs(frame.time) <= 1_000_000,
                  frame.time > previous,
                  frame.position.x.isFinite, abs(frame.position.x) <= 150,
                  frame.position.z.isFinite, abs(frame.position.z) <= 150,
                  frame.height.isFinite, frame.height >= 0, frame.height <= 20 else { return false }
            previous = frame.time
        }
        return true
    }

    private static func interpolated(anchors: [BallKeyframe], contacts: [Contact?], index: Int,
                                     time: Double, fraction u: Float) -> BallKeyframe {
        let a = anchors[index]
        let b = anchors[index + 1]
        let duration = Float(b.time - a.time)
        let distance = ReplayGeometry.distance(a.position, b.position)
        let decelerates = distance / duration > 2.10
            && max(a.height, b.height) < 0.25
            && (contacts[index]?.playerIndex != contacts[index + 1]?.playerIndex
                || contacts[index] == nil)
        func axis(_ value: (BallKeyframe) -> Float) -> Float {
            let slope = (value(b) - value(a)) / duration
            let startTangent = (contacts[index] != nil || index == 0)
                ? slope : tangent(anchors, at: index, value: value)
            let endTangent = (contacts[index + 1] != nil || index + 1 == anchors.count - 1)
                ? slope : tangent(anchors, at: index + 1, value: value)
            let progress = decelerates ? u + 0.18 * u * (1 - u) : u
            return hermite(value(a), value(b), startTangent * duration,
                           endTangent * duration, progress)
        }
        let height = hermite(a.height, b.height,
                             tangent(anchors, at: index, value: { $0.height }) * duration,
                             tangent(anchors, at: index + 1, value: { $0.height }) * duration, u)
        return .init(time: time, position: .init(x: axis { $0.position.x }, z: axis { $0.position.z }),
                     height: max(height, ballRadius))
    }

    private static func tangent(_ frames: [BallKeyframe], at index: Int,
                                value: (BallKeyframe) -> Float) -> Float {
        if index == 0 {
            return (value(frames[1]) - value(frames[0])) / Float(frames[1].time - frames[0].time)
        }
        if index == frames.count - 1 {
            return (value(frames[index]) - value(frames[index - 1]))
                / Float(frames[index].time - frames[index - 1].time)
        }
        let before = (value(frames[index]) - value(frames[index - 1]))
            / Float(frames[index].time - frames[index - 1].time)
        let after = (value(frames[index + 1]) - value(frames[index]))
            / Float(frames[index + 1].time - frames[index].time)
        guard before * after > 0 else { return 0 }
        return 2 * before * after / (before + after)
    }

    private static func hermite(_ a: Float, _ b: Float, _ ma: Float, _ mb: Float, _ u: Float) -> Float {
        let u2 = u * u
        let u3 = u2 * u
        return min(max((2 * u3 - 3 * u2 + 1) * a + (u3 - 2 * u2 + u) * ma
                       + (-2 * u3 + 3 * u2) * b + (u3 - u2) * mb, min(a, b)), max(a, b))
    }

    private static func clearObstacles(in frames: inout [BallKeyframe], source: [BallKeyframe],
                                      obstacles: [Obstacle]) {
        guard frames.count > 1 else { return }
        for _ in 0..<10 {
            var changed = false
            for obstacle in obstacles {
                var index = 0
                while index < frames.count - 1 {
                    guard let hit = collision(frames: frames, obstacle: obstacle, index: index) else {
                        index += 1
                        continue
                    }
                    var worst = hit
                    var worstIndex = index
                    var last = index + 1
                    while last < frames.count - 1,
                          let next = collision(frames: frames, obstacle: obstacle, index: last) {
                        if next.depth > worst.depth { worst = next; worstIndex = last }
                        last += 1
                    }
                    let before = max(0, worstIndex - 3)
                    let after = min(frames.count - 1, worstIndex + 3)
                    let relativeStart = vector(frames[before].position) - vector(obstacle.centres[before])
                    let relativeEnd = vector(frames[after].position) - vector(obstacle.centres[after])
                    let velocity = (relativeEnd - relativeStart)
                        / Float(frames[after].time - frames[before].time)
                    let speed = simd_length(velocity)
                    let normal: SIMD2<Float>
                    if speed > 0.20 {
                        var side = simd_normalize(SIMD2<Float>(-velocity.y, velocity.x))
                        if simd_dot(worst.relative, side) < -0.004 { side = -side }
                        normal = side
                    } else {
                        normal = simd_length_squared(worst.relative) > 0.000_01
                            ? simd_normalize(worst.relative) : SIMD2<Float>(1, 0)
                    }
                    let amount = max(worst.required - simd_dot(worst.relative, normal) + 0.014, 0.018)
                    let centre = frames[worstIndex].time
                    let halfWindow = min(max(Double(worst.required * 3.1 / max(speed, 0.75)), 0.12), 0.85)
                    let firstAffected = max(0, worstIndex - Int(ceil(halfWindow * samplesPerSecond)) - 2)
                    let lastAffected = min(frames.count - 1,
                                           worstIndex + Int(ceil(halfWindow * samplesPerSecond)) + 2)
                    for target in firstAffected...lastAffected {
                        let phase = abs(frames[target].time - centre) / halfWindow
                        guard phase < 1 else { continue }
                        let weight = Float(0.5 + 0.5 * cos(.pi * phase))
                        let current = frames[target]
                        let proposed = vector(current.position) + normal * (amount * weight)
                        let baseline = vector(source[target].position)
                        let delta = proposed - baseline
                        let bounded = simd_length_squared(delta) > maximumPresentationOffset * maximumPresentationOffset
                            ? baseline + simd_normalize(delta) * maximumPresentationOffset : proposed
                        frames[target] = .init(time: current.time,
                                               position: .init(x: bounded.x, z: bounded.y), height: current.height)
                    }
                    changed = true
                    index = last
                }
            }
            if !changed { break }
        }
    }

    private struct Hit {
        let depth: Float
        let relative: SIMD2<Float>
        let required: Float
    }

    private static func collision(frames: [BallKeyframe], obstacle: Obstacle, index: Int) -> Hit? {
        let a = frames[index]
        let b = frames[index + 1]
        guard min(a.height, b.height) < bodyCollisionCentreCeiling else { return nil }
        let start = vector(a.position) - vector(obstacle.centres[index])
        let end = vector(b.position) - vector(obstacle.centres[index + 1])
        let delta = end - start
        let length = simd_length_squared(delta)
        let fraction = length > 0.000_001 ? min(max(-simd_dot(start, delta) / length, 0), 1) : 0
        let nearest = start + delta * fraction
        var result: Hit? = simd_length(nearest) < bodyClearance + 0.006
            ? Hit(depth: bodyClearance + 0.006 - simd_length(nearest), relative: nearest,
                  required: bodyClearance + 0.006) : nil
        if let legs = obstacle.legs[index] {
            let point = SIMD3<Float>(a.position.x, a.height, a.position.z)
            func test(_ capsule: ReplayBallPlayerContact.Capsule) {
                let closest = capsule.nearestPoint(to: point)
                let radius = capsule.radius + ballRadius + 0.008
                let vertical = point.y - closest.y
                guard abs(vertical) < radius else { return }
                let required = sqrt(max(radius * radius - vertical * vertical, 0))
                let relative = SIMD2<Float>(point.x - closest.x, point.z - closest.z)
                let depth = required - simd_length(relative)
                if depth > 0, depth > (result?.depth ?? 0) {
                    result = Hit(depth: depth, relative: relative, required: required)
                }
            }
            test(legs.leftShin)
            test(legs.rightShin)
            test(legs.leftBoot)
            test(legs.rightBoot)
        }
        return result
    }

    private static func vector(_ point: PitchPoint) -> SIMD2<Float> { [point.x, point.z] }
}
