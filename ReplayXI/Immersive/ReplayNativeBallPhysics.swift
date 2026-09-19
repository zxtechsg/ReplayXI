import Foundation
import RealityKit
import simd

/// A real, metre-scale RealityKit simulation is recorded once, then replayed
/// from immutable samples. Seeking never advances (or rewinds) a live solver.
/// Authored waypoints are kick intentions, not position constraints.
@MainActor
enum ReplayNativeBallPhysics {
    static let radius: Float = 0.11
    static let mass: Float = 0.43
    static let step: TimeInterval = 1.0 / 120.0
    static let maximumDuration: TimeInterval = 90
    static let maximumPlayers = 32
    static let maximumSourceFrames = 4_096
    static let maximumCachedRecordings = 4

    enum Failure: Error, Equatable {
        case invalidInput
        case nonFiniteSimulation
        case simulationDidNotAdvance
    }

    enum TouchKind: String, Hashable, Sendable { case receive, pass, shot, dribbleTouch, header, save }

    struct PlannedTouch: Equatable, Sendable {
        let time: TimeInterval
        let playerID: String
        let kind: TouchKind
        let kickingLeg: ReplayAthleteLeg
        let target: PitchPoint
        let targetHeight: Float
        let arrivalTime: TimeInterval
        /// Explicit reference technique; nil retains the original header gait.
        let headerSupportLeg: ReplayAthleteLeg?

        init(time: TimeInterval, playerID: String, kind: TouchKind = .pass,
             kickingLeg: ReplayAthleteLeg = .right, target: PitchPoint,
             targetHeight: Float = 0.11, arrivalTime: TimeInterval,
             headerSupportLeg: ReplayAthleteLeg? = nil) {
            self.time = time
            self.playerID = playerID
            self.kind = kind
            self.kickingLeg = kickingLeg
            self.target = target
            self.targetHeight = targetHeight
            self.arrivalTime = arrivalTime
            self.headerSupportLeg = headerSupportLeg
        }
    }

    struct Touch: Sendable {
        let time: TimeInterval
        let playerID: String
        let position: SIMD3<Float>
        let outgoingVelocity: SIMD3<Float>
        let kind: TouchKind
        let kickingLeg: ReplayAthleteLeg
        var headerSupportLeg: ReplayAthleteLeg? = nil
    }

    struct Sample: Sendable {
        let time: TimeInterval
        let position: SIMD3<Float>
        let orientation: simd_quatf
        let velocity: SIMD3<Float>
        let angularVelocity: SIMD3<Float>
    }

    struct Diagnostic: Sendable {
        let time: TimeInterval
        let position: SIMD3<Float>
        let velocity: SIMD3<Float>
        let nearestColliders: [String]
    }

    final class Recording: Sendable {
        let samples: [Sample]
        let ballTrack: BallTrack
        let touches: [Touch]
        let missedTouchCount: Int
        let nativeStepCount: Int
        /// Empty in Release. Debug receipts retain a bounded contact window.
        let diagnostics: [Diagnostic]

        init(samples: [Sample], touches: [Touch], missedTouchCount: Int, diagnostics: [Diagnostic] = []) {
            self.samples = samples
            ballTrack = BallTrack(keyframes: samples.map {
                BallKeyframe(time: $0.time, position: .init(x: $0.position.x, z: $0.position.z),
                             height: $0.position.y)
            })
            self.touches = touches
            self.missedTouchCount = missedTouchCount
            nativeStepCount = max(0, samples.count - 1)
            self.diagnostics = diagnostics
        }

        /// Binary search, no allocation, no mutable playback cursor. The same
        /// timestamp has the same result at every playback rate/direction.
        func sample(at time: TimeInterval) -> Sample {
            guard let first = samples.first, let last = samples.last else {
                return Sample(time: 0, position: [0, 0.11, 0],
                              orientation: simd_quatf(real: 1, imag: .zero),
                              velocity: .zero, angularVelocity: .zero)
            }
            guard time.isFinite, time > first.time else { return first }
            guard time < last.time else { return last }
            var lower = 0
            var upper = samples.count - 1
            while upper - lower > 1 {
                let middle = (lower + upper) / 2
                if samples[middle].time <= time { lower = middle } else { upper = middle }
            }
            let a = samples[lower]
            let b = samples[upper]
            let fraction = Float((time - a.time) / (b.time - a.time))
            return Sample(time: time, position: simd_mix(a.position, b.position, SIMD3(repeating: fraction)),
                          orientation: simd_slerp(a.orientation, b.orientation, fraction),
                          velocity: simd_mix(a.velocity, b.velocity, SIMD3(repeating: fraction)),
                          angularVelocity: simd_mix(a.angularVelocity, b.angularVelocity, SIMD3(repeating: fraction)))
        }

        func pose(at time: TimeInterval) -> BallPose {
            let sample = sample(at: time)
            return BallPose(position: .init(x: sample.position.x, z: sample.position.z), height: sample.position.y)
        }

        func orientation(at time: TimeInterval) -> simd_quatf { sample(at: time).orientation }
    }

    private struct CacheEntry {
        let source: BallTrack
        let players: [PlayerTrack]
        let plan: [PlannedTouch]?
        let recording: Recording
    }
    private static var cache: [CacheEntry] = []

    static func cached(track: BallTrack, players: [PlayerTrack], plannedTouches: [PlannedTouch]? = nil) -> Recording? {
        guard let index = cache.firstIndex(where: {
            $0.source == track && $0.players == players && $0.plan == plannedTouches
        }) else { return nil }
        let entry = cache.remove(at: index)
        cache.append(entry)
        return entry.recording
    }

    /// Called outside scene-frame updates. Fixed work is chunked to let the UI
    /// respond and cancellation discards the entire unfinished recording.
    @discardableResult
    static func prewarm(track: BallTrack, players: [PlayerTrack],
                        plannedTouches: [PlannedTouch]? = nil) async throws -> Recording {
        try Task.checkCancellation()
        if let recording = cached(track: track, players: players, plannedTouches: plannedTouches) { return recording }
        let recording = try await bake(track: track, players: players, plannedTouches: plannedTouches)
        try Task.checkCancellation()
        // A partially executed authored study is useful as a diagnostic, not
        // a successful warm cache. Retry must be able to perform a new bake.
        if plannedTouches != nil, recording.missedTouchCount > 0 { return recording }
        cache.append(CacheEntry(source: track, players: players, plan: plannedTouches, recording: recording))
        if cache.count > maximumCachedRecordings { cache.removeFirst() }
        return recording
    }

    static func bake(track: BallTrack, players: [PlayerTrack],
                     plannedTouches: [PlannedTouch]? = nil) async throws -> Recording {
        guard accepts(track: track, players: players), let first = track.keyframes.first,
              let last = track.keyframes.last else { throw Failure.invalidInput }
        let intents = try makeIntents(track: track, players: players, plan: plannedTouches)
        let world = try ReplayNativeBallPhysicsWorld()
        defer { world.finish() }
        world.configureIntents(intents)
        var initialPosition = SIMD3<Float>(first.position.x, max(first.height, radius + 0.002), first.position.z)
        // A source knot often names the carrier's root, not the ball surface.
        // Resolve this only for the initial condition; never teleport in-flight.
        if let owner = nearestPlayer(players, to: first.position, at: first.time, within: 0.55) {
            let contact = ReplayBallPlayerContact(player: owner, ball: track, time: first.time)
            let strike = contact.strikePoint(leg: .right, ballRadius: radius)
            initialPosition.x = strike.x
            initialPosition.z = strike.z
        }
        world.placeBall(position: initialPosition)
        // Kinematic IK proxies must see the final initial sphere position,
        // never the default origin followed by a one-frame contact teleport.
        world.addPlayers(players, ball: track, at: first.time)
        try world.start()
        var intentIndex = 0
        var samples: [Sample] = []
        var touches: [Touch] = []
        var missed = 0
        #if DEBUG
        var completedNativeStepsForTesting = 0
        defer { preparationObserverForTesting?(.finished(nativeSteps: completedNativeStepsForTesting)) }
        var diagnostics: [Diagnostic] = []
        diagnostics.reserveCapacity(256)
        #endif
        let count = Int(ceil((last.time - first.time) / step))
        samples.reserveCapacity(count + 1)
        touches.reserveCapacity(intents.count)
        samples.append(world.sample(at: first.time))
        for index in 0..<count {
            if index % 60 == 0 {
                try Task.checkCancellation()
                await Task.yield()
                #if DEBUG
                preparationObserverForTesting?(.resumedAfterYield(nativeSteps: completedNativeStepsForTesting))
                #endif
                try Task.checkCancellation()
            }
            let time = first.time + Double(index) * step
            let delta = min(step, last.time - time)
            world.movePlayers(players, ball: track, time: time, delta: delta)
            while intentIndex < intents.count, intents[intentIndex].time <= time + 0.12 {
                let intent = intents[intentIndex]
                if let touch = try world.strike(intent: intent, time: time) {
                    touches.append(touch)
                    intentIndex += 1
                } else if time > intent.time + 0.12 {
                    missed += 1
                    intentIndex += 1
                } else {
                    // Let the physical ball enter reach; no attraction,
                    // teleport or silent remote kick when timing differs.
                    break
                }
            }
            try world.advance(delta)
            #if DEBUG
            completedNativeStepsForTesting += 1
            #endif
            let sample = world.sample(at: time + delta)
            guard sample.position.x.isFinite, sample.position.y.isFinite, sample.position.z.isFinite,
                  simd_length(sample.position) < 500, simd_length(sample.velocity) < 100,
                  simd_length(sample.angularVelocity).isFinite,
                  simd_length(sample.orientation.vector).isFinite else {
                throw Failure.nonFiniteSimulation
            }
            samples.append(sample)
            #if DEBUG
            if diagnostics.count < 256,
               (index % 3 == 0 && intents.contains(where: { sample.time >= $0.time && sample.time <= $0.time + 0.28 })) {
                diagnostics.append(Diagnostic(time: sample.time, position: sample.position, velocity: sample.velocity,
                                               nearestColliders: world.nearestColliderNames(to: sample.position)))
            }
            #endif
        }
        missed += intents.count - intentIndex
        #if DEBUG
        return Recording(samples: samples, touches: touches, missedTouchCount: missed, diagnostics: diagnostics)
        #else
        return Recording(samples: samples, touches: touches, missedTouchCount: missed)
        #endif
    }

    struct Intent {
        let time: TimeInterval
        let player: PlayerTrack
        let target: SIMD3<Float>
        let arrivalTime: TimeInterval
        let loft: Float
        let kind: TouchKind
        let kickingLeg: ReplayAthleteLeg
        var headerSupportLeg: ReplayAthleteLeg? = nil
    }

    private static func makeIntents(track: BallTrack, players: [PlayerTrack], plan: [PlannedTouch]?) throws -> [Intent] {
        if let plan {
            guard plan.count <= 512, let start = track.keyframes.first?.time,
                  let end = track.keyframes.last?.time else { throw Failure.invalidInput }
            var previous = -Double.infinity
            var intents: [Intent] = []
            for touch in plan {
                guard touch.time.isFinite, touch.time >= previous, touch.time >= start, touch.time < end,
                      touch.arrivalTime.isFinite, touch.arrivalTime > touch.time,
                      touch.arrivalTime <= end + 5, touch.target.x.isFinite, touch.target.z.isFinite,
                      abs(touch.target.x) <= 100, abs(touch.target.z) <= 100,
                      touch.targetHeight.isFinite, (0...25).contains(touch.targetHeight),
                      touch.headerSupportLeg == nil || touch.kind == .header,
                      let player = players.first(where: { $0.id == touch.playerID }) else {
                    throw Failure.invalidInput
                }
                previous = touch.time
                intents.append(Intent(time: touch.time, player: player,
                                      target: [touch.target.x, max(radius, touch.targetHeight), touch.target.z],
                                      arrivalTime: touch.arrivalTime, loft: touch.targetHeight,
                                      kind: touch.kind, kickingLeg: touch.kickingLeg,
                                      headerSupportLeg: touch.headerSupportLeg))
            }
            return intents
        }
        var result: [Intent] = []
        for index in 0..<(track.keyframes.count - 1) {
            let frame = track.keyframes[index]
            guard frame.height < 0.65,
                  let player = nearestPlayer(players, to: frame.position, at: frame.time, within: 0.90) else { continue }
            let next = track.keyframes[index + 1]
            let distance = ReplayGeometry.distance(frame.position, next.position)
            guard distance > 0.05 else { continue }
            result.append(Intent(time: frame.time, player: player,
                                 target: [next.position.x, max(radius, next.height), next.position.z],
                                 arrivalTime: next.time, loft: max(frame.height, next.height),
                                 kind: .pass, kickingLeg: .right))
        }
        guard result.count <= 512 else { throw Failure.invalidInput }
        return result
    }

    private static func nearestPlayer(_ players: [PlayerTrack], to point: PitchPoint,
                                      at time: TimeInterval, within reach: Float) -> PlayerTrack? {
        var nearest: PlayerTrack?
        var distance = reach
        for player in players {
            let candidate = ReplayGeometry.distance(player.presentationPose(at: time).position, point)
            if candidate < distance { nearest = player; distance = candidate }
        }
        return nearest
    }

    private static func accepts(track: BallTrack, players: [PlayerTrack]) -> Bool {
        guard (2...maximumSourceFrames).contains(track.keyframes.count), players.count <= maximumPlayers,
              let first = track.keyframes.first, let last = track.keyframes.last,
              first.time.isFinite, last.time.isFinite, first.time >= 0, last.time <= 1_000_000,
              last.time > first.time, last.time - first.time <= maximumDuration else { return false }
        var previous = -Double.infinity
        for frame in track.keyframes {
            guard frame.time.isFinite, frame.time > previous, frame.position.x.isFinite,
                  frame.position.z.isFinite, abs(frame.position.x) <= 100, abs(frame.position.z) <= 100,
                  frame.height.isFinite, (0...25).contains(frame.height) else { return false }
            previous = frame.time
        }
        for player in players {
            guard !player.keyframes.isEmpty, player.keyframes.count <= maximumSourceFrames else { return false }
            previous = -Double.infinity
            for frame in player.keyframes {
                guard frame.time.isFinite, frame.time > previous, frame.position.x.isFinite,
                      frame.position.z.isFinite, abs(frame.position.x) <= 100, abs(frame.position.z) <= 100,
                      frame.facingDegrees.isFinite else { return false }
                previous = frame.time
            }
        }
        guard Set(players.map(\.id)).count == players.count else { return false }
        return true
    }

    #if DEBUG
    enum PreparationCheckpointForTesting {
        case resumedAfterYield(nativeSteps: Int)
        case finished(nativeSteps: Int)
    }
    /// Numeric checkpoints only; observers must not retain native solver state.
    static var preparationObserverForTesting: ((PreparationCheckpointForTesting) -> Void)?
    static func resetCacheForTesting() { cache.removeAll() }
    static var cacheCountForTesting: Int { cache.count }
    #endif
}
