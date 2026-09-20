import Dispatch
import Foundation
import RealityKit
import simd
import XCTest
@testable import ReplayXI

/// Actual demo integration, not a new contact detector or an FPS benchmark.
@MainActor
final class ReplaySlowRunIntegration151Tests: XCTestCase {
    private typealias Skin = ReplaySkinnedAthleteInstance
    private typealias Counts = ReplaySkinnedAthleteMotion.ClipSampleCounts
    private struct Features {
        let time: Double
        let speed: Float
        let turn: Float
        let yaw: Float
        let weight: Float
        func value(_ key: String) -> Float { key == "speed" ? speed : key == "turn" ? turn : yaw }
    }
    private struct Plan {
        let times: [Double]
        let boundaries: [[String: Any]]
        let missing: [String]
    }
    private struct Body: Equatable {
        let detail: String
        let joints: [Transform]
        let root: Transform
        let front: Transform
        let back: Transform
        let weight: Float
    }
    private struct State: Equatable {
        let root: Transform
        let actors: [String: Transform]
        let ball: Transform
        let bodies: [String: Body]
    }
    private struct Peak {
        var value: Float = 0
        var player = ""
        var time: Double = 0
        var dt: Double = 0
        var joint = -1
        mutating func add(_ value: Float, player: String, time: Double, dt: Double, joint: Int = -1) {
            if value > self.value { self = .init(value: value, player: player, time: time, dt: dt, joint: joint) }
        }
        var row: [String: Any] { ["value": value, "player": player, "time": time, "dtSeconds": dt, "jointIndex": joint] }
    }

    override func tearDown() {
        PitchSceneFactory.fullSquadSkinsForTesting = false
        if let scenario = FootballReferenceScenarios.all.first {
            let root = Entity(), marks = Entity(); marks.name = "marks-root"; root.addChild(marks)
            _ = update(root, scenario, time: 0, perspective: scenario.defaultPerspectiveID, enabled: false)
            for child in Array(root.children) { child.removeFromParent() }
        }
        ReplayArticulatedFarKitProvider.resetForTesting(); ReplayArticulatedFarProvider.resetForTesting()
        ReplayFarAthleteHeadProvider.resetForTesting(); ReplaySkinnedAthleteProvider.resetForTesting()
        ReplayAthleteHeadProvider.resetForTesting(); ReplayFarAthletePaletteProvider.resetForTesting()
        ReplayNativeBallPhysics.resetCacheForTesting()
        ReplaySkinnedAthleteMotion.resetClipSampleCountsForTesting()
        super.tearDown()
    }

    func testActualFiveDemoSlowRunAdmissionProtectedActorsAndRewind151() async throws {
        try prepare()
        XCTAssertEqual(FootballReferenceScenarios.all.count, 5)
        var rows: [[String: Any]] = [], coverage = Set<String>(), positiveCoverage = Set<String>()
        for scenario in FootballReferenceScenarios.all {
            let sourcePlayers = scenario.players, sourceBall = scenario.ball
            let recording = try await recording(scenario)
            let ballPositions = recording.samples.map(\.position), ballVelocities = recording.samples.map(\.velocity)
            let ballRotations = recording.samples.map { $0.orientation.vector }
            let protected = Set(recording.touches.map(\.playerID))
                .union(scenario.players.filter(\.isGoalkeeper).map(\.id))
                .union(PlayerRagdollCue.authoredDemo(for: scenario).map { [$0.playerID] } ?? [])
            let eligible = scenario.players.filter { !protected.contains($0.id) }
            let scans = Dictionary(uniqueKeysWithValues: eligible.map { ($0.id, scan($0, duration: scenario.duration)) })
            for team in FootballTeam.allCases {
                // Focus the strongest real candidate on each team. No synthetic
                // trajectory or imposed speed is used to manufacture admission.
                let focus = try XCTUnwrap(eligible.filter { $0.team == team }.sorted { a, b in
                    let lhs = scans[a.id]!.map(\.weight).max()!, rhs = scans[b.id]!.map(\.weight).max()!
                    return lhs == rhs ? a.id < b.id : lhs > rhs
                }.first)
                let plan = makePlan(focus, scan: scans[focus.id]!, scenario: scenario, recording: recording)
                let result = try measure(scenario, recording: recording, focus: focus, plan: plan, protected: protected)
                rows.append(result.row); coverage.formUnion(result.coverage); positiveCoverage.formUnion(result.positive)
            }
            XCTAssertEqual(scenario.players, sourcePlayers); XCTAssertEqual(scenario.ball, sourceBall)
            XCTAssertEqual(recording.samples.map(\.position), ballPositions)
            XCTAssertEqual(recording.samples.map(\.velocity), ballVelocities)
            XCTAssertEqual(recording.samples.map { $0.orientation.vector }, ballRotations)
        }
        XCTAssertEqual(rows.count, 10)
        let required: Set<String> = ["home/near", "home/low", "away/near", "away/low"]
        XCTAssertEqual(coverage, required)
        XCTAssertFalse(positiveCoverage.isEmpty, "The real demos must actually exercise the new source")
        let report: [String: Any] = ["cases": rows, "coverage": coverage.sorted(),
            "positiveWeightCoverage": positiveCoverage.sorted(), "noPositiveWeightCoverage": required.subtracting(positiveCoverage).sorted(),
            "hasSlowRun": ReplaySkinnedAthleteProvider.motion?.hasSlowRun == true,
            "slowSHA256": ReplaySkinnedAthleteProvider.slowRunSHA256,
            "temporalSlopeLimitPerSecond": 4,
            "scope": "152 prepared admission: five native recordings, each team selected as near; remaining native actors low. Enabled/disabled Full squad roots share sampling history. Cold root construction and inner timeline preparation are separate from warm Factory.update CPU timings, which alternate A/B order without assertions/readback/rendering inside the interval.",
            "limits": "No rendering or hardware FPS claim. Floor clearance is geometry, not measured contact. Missing raw-track boundary crossings/positive cells are reported. Raw admission remains diagnostic; the prepared timeline is authoritative. Local joint steps are measured at gaps no larger than 1/120 s, not declared discontinuities."]
        try attach(report, name: "ReplayXI-SlowRun152-FiveDemoIntegration.json")
    }

    func testActualReboundPOVNonNativeStationaryAndWholeTrackImpactGuards151() async throws {
        try prepare()
        let scenario = try XCTUnwrap(FootballReferenceScenarios.all.first { $0.id == "final-108-rebound-v2" })
        let recording = try await recording(scenario)
        let protected = Set(recording.touches.map(\.playerID)).union(scenario.players.filter(\.isGoalkeeper).map(\.id))
        let cue = PlayerRagdollCue(playerID: "arg-13", impactTime: 0.5, duration: 1)
        let definitions: [(String, Bool, ReplayViewMode, String, PlayerRagdollCue?, [Double])] = [
            ("POV-near", true, .firstPerson, "arg-23", nil, [0.25, 0.4666666666666667, 0.6166666666666667, 0.8]),
            ("POV-low", true, .firstPerson, "arg-10", nil, [0.25, 0.5, 0.65, 0.8]),
            ("non-native", false, .tacticalTable, "arg-13", nil, [0.25, 0.5, 0.8]),
            ("stationary-ideal", true, .positional, "arg-13", nil, [0.25, 0.5, 0.8]),
            ("explicit-impact-whole-track", true, .tacticalTable, "arg-13", cue, [0.25, 0.5, 0.65, 1.49, 1.5, 1.7])
        ]
        var rows: [[String: Any]] = []
        for (name, native, view, perspective, impact, times) in definitions {
            // nil alone permits the factory's prepared-recording cache fallback.
            // Keep our immutable recording reference for later explicit cases,
            // but clear that fallback before claiming a nonnative control.
            if !native { ReplayNativeBallPhysics.resetCacheForTesting() }
            let fast = PitchSceneFactory.makeMatchRoot(for: scenario, nativeRecording: native ? recording : nil)
            let enabled = PitchSceneFactory.makeMatchRoot(for: scenario, nativeRecording: native ? recording : nil)
            if !native {
                XCTAssertNil(PitchSceneFactory.nativeBallRecordingForTesting(in: fast))
                XCTAssertNil(PitchSceneFactory.nativeBallRecordingForTesting(in: enabled))
            } else {
                XCTAssertTrue(PitchSceneFactory.nativeBallRecordingForTesting(in: fast) === recording)
                XCTAssertTrue(PitchSceneFactory.nativeBallRecordingForTesting(in: enabled) === recording)
            }
            defer {
                for root in [fast, enabled] { for child in Array(root.children) { child.removeFromParent() } }
            }
            var saved: [Double: State] = [:], positive = Set<String>()
            for time in times {
                _ = update(fast, scenario, time: time, perspective: perspective, enabled: false, view: view, impact: impact)
                _ = update(enabled, scenario, time: time, perspective: perspective, enabled: true, view: view, impact: impact)
                let a = try snapshot(fast), b = try snapshot(enabled)
                assertTrajectory(a, b, label: name)
                XCTAssertEqual(Set(a.bodies.keys), Set(b.bodies.keys))
                if view == .firstPerson { XCTAssertNil(b.bodies[perspective]) }
                for (id, body) in b.bodies {
                    let prior = try XCTUnwrap(a.bodies[id])
                    if !native || view == .positional || protected.contains(id) || id == impact?.playerID {
                        XCTAssertEqual(body.weight, 0, "\(name)/\(id)/\(time)")
                        assertPose(body, prior, label: "\(name)/\(id)/\(time)")
                    }
                    if body.weight > 0 { positive.insert(id) }
                }
                saved[time] = b
            }
            for time in times.reversed() {
                _ = update(enabled, scenario, time: time, perspective: perspective, enabled: true, view: view, impact: impact)
                assertState(try snapshot(enabled), try XCTUnwrap(saved[time]), label: "\(name) rewind \(time)")
            }
            if name.hasPrefix("POV") { XCTAssertFalse(positive.isEmpty) }
            rows.append(["case": name, "times": times, "positivePlayers": positive.sorted(), "exactRewind": true,
                         "explicitImpactIsTestCue": impact != nil])
        }
        try attach(["cases": rows, "scope": "Actual rebound paths/ball, two wearer origins; nonnative and ideal-view fast-only guards; one explicit test impact cue excludes its subject before/during/after the cue."],
                   name: "ReplayXI-SlowRun152-FactoryGuards.json")
    }

    private func prepare() throws {
        PitchSceneFactory.fullSquadSkinsForTesting = false
        try ReplayArmLOD147Probe.prepare(); try ReplayStrategyPitchProvider.prewarm(); try ReplayStrategyBallProvider.prewarm()
        XCTAssertTrue(try XCTUnwrap(ReplaySkinnedAthleteProvider.motion).hasSlowRun)
    }
    private func recording(_ scenario: ReplayScenario) async throws -> ReplayNativeBallPhysics.Recording {
        let touches = try XCTUnwrap(FootballReferenceScenarios.touches(for: scenario))
        let result = try await ReplayNativeBallPhysics.prewarm(track: scenario.ball, players: scenario.players, plannedTouches: touches)
        XCTAssertEqual(result.missedTouchCount, 0); XCTAssertEqual(result.touches.count, touches.count)
        try ReplayAthleteFactory.prewarm(for: scenario.players, lods: [.near, .far])
        return result
    }
    private func features(_ track: PlayerTrack, _ time: Double) -> Features {
        let locomotion = track.locomotion(at: time)
        let movement = ReplayAthleteMovementIntent.sample(track: track, at: time,
            presentationPose: track.presentationPose(at: time), lookTarget: nil)
        let yaw = abs(movement?.localTravelYaw ?? .pi)
        return .init(time: time, speed: locomotion.speedMetresPerSecond,
            turn: abs(locomotion.turnRateDegreesPerSecond), yaw: yaw,
            weight: movement == nil ? 0 : ReplaySlowRunAdmission.weight(locomotion: locomotion)
                * ReplaySlowRunAdmission.directionWeight(localTravelYaw: yaw))
    }
    private func scan(_ track: PlayerTrack, duration: Double) -> [Features] {
        (0...Int(ceil(duration * 30))).map { features(track, min(Double($0) / 30, duration)) }
    }
    private func makePlan(_ track: PlayerTrack, scan: [Features], scenario: ReplayScenario,
                          recording: ReplayNativeBallPhysics.Recording) -> Plan {
        var times = (0...8).map { scenario.duration * Double($0) / 8 }
        times += recording.touches.flatMap { [$0.time - 1 / 120.0, $0.time, $0.time + 1 / 120.0] }
        if let pair = regressionPair(scenario.id) { times += [pair.start, pair.end] }
        var boundaries: [[String: Any]] = [], missing: [String] = []
        for (key, threshold) in [("speed", Float(1)), ("speed", 1.9), ("speed", 2.2), ("speed", 2.9),
                                 ("turn", 20), ("turn", 38), ("yaw", 0.22), ("yaw", 0.72)] {
            let matches = (1..<scan.count).filter { index in
                let a = scan[index - 1].value(key) - threshold, b = scan[index].value(key) - threshold
                return a != b && a * b <= 0
            }.sorted { max(scan[$0 - 1].weight, scan[$0].weight) > max(scan[$1 - 1].weight, scan[$1].weight) }
            guard let index = matches.first else { missing.append("\(key)=\(threshold)"); continue }
            var low = scan[index - 1].time, high = scan[index].time
            let sign = features(track, low).value(key) - threshold
            for _ in 0..<24 {
                let mid = (low + high) * 0.5, value = features(track, mid).value(key) - threshold
                if sign * value > 0 { low = mid } else { high = mid }
            }
            let centre = (low + high) * 0.5
            times += [-1.0, 0, 1].map { centre + $0 / 120 }
            boundaries.append(["feature": key, "target": threshold, "time": centre,
                               "actual": features(track, centre).value(key)])
        }
        for name in ["weight-rise", "weight-fall", "turn-change", "yaw-change"] {
            let candidates = (1..<scan.count).map { index -> (Int, Float) in
                let a = scan[index - 1], b = scan[index]
                let score: Float = switch name {
                case "weight-rise": b.weight - a.weight
                case "weight-fall": a.weight - b.weight
                case "turn-change": max(a.weight, b.weight) > 0 ? abs(b.turn - a.turn) : 0
                default: max(a.weight, b.weight) > 0 ? abs(b.yaw - a.yaw) : 0
                }
                return (index, score)
            }
            guard let best = candidates.max(by: { $0.1 < $1.1 }), best.1 > 0 else { missing.append(name); continue }
            let centre = (scan[best.0 - 1].time + scan[best.0].time) * 0.5
            times += (-3...3).map { centre + Double($0) / 120 }
            boundaries.append(["feature": name, "time": centre, "scanDelta": best.1])
        }
        if let peak = scan.max(by: { $0.weight < $1.weight }) { times.append(peak.time) }
        let bounded = Array(Set(times.map { min(max($0, 0), scenario.duration) })).sorted()
        XCTAssertLessThanOrEqual(bounded.count, 96)
        return .init(times: bounded, boundaries: boundaries, missing: missing)
    }

    private func measure(_ scenario: ReplayScenario, recording: ReplayNativeBallPhysics.Recording,
                         focus: PlayerTrack, plan: Plan, protected: Set<String>) throws
        -> (row: [String: Any], coverage: Set<String>, positive: Set<String>) {
        let fastStart = DispatchTime.now().uptimeNanoseconds
        let fast = PitchSceneFactory.makeMatchRoot(for: scenario, nativeRecording: recording)
        let fastConstruction = DispatchTime.now().uptimeNanoseconds - fastStart
        let enabledStart = DispatchTime.now().uptimeNanoseconds
        let enabled = PitchSceneFactory.makeMatchRoot(for: scenario, nativeRecording: recording)
        let enabledConstruction = DispatchTime.now().uptimeNanoseconds - enabledStart
        defer { for root in [fast, enabled] { for child in Array(root.children) { child.removeFromParent() } } }
        let timelines = PitchSceneFactory.slowRunTimelinesForTesting(in: enabled)
        let fastTimelines = PitchSceneFactory.slowRunTimelinesForTesting(in: fast)
        XCTAssertEqual(Set(timelines.keys), Set(scenario.players.map(\.id)).subtracting(protected))
        XCTAssertEqual(Set(timelines.keys), Set(fastTimelines.keys))
        for (id, timeline) in timelines {
            XCTAssertTrue(timeline.knotsForTesting == fastTimelines[id]?.knotsForTesting, "Deterministic cold preparation \(id)")
        }
        let coldFast = timelineMetrics(fast, constructionNanoseconds: fastConstruction)
        let coldEnabled = timelineMetrics(enabled, constructionNanoseconds: enabledConstruction)
        let fastBuildNS = PitchSceneFactory.slowRunBuildNanosecondsForTesting(in: fast)
        let enabledBuildNS = PitchSceneFactory.slowRunBuildNanosecondsForTesting(in: enabled)
        for _ in 0..<2 {
            _ = update(fast, scenario, time: plan.times[0], perspective: focus.id, enabled: false)
            _ = update(enabled, scenario, time: plan.times[0], perspective: focus.id, enabled: true)
        }
        var savedFast: [State] = [], savedEnabled: [State] = [], cpuFast: [UInt64] = [], cpuEnabled: [UInt64] = []
        var rows: [[String: Any]] = [], coverage = Set<String>(), positive = Set<String>(), changed = 0
        var fastPeak = Peak(), enabledPeak = Peak(), focusFastPeak = Peak(), focusEnabledPeak = Peak(), weightPeak = Peak()
        var riseRate = Peak(), fallRate = Peak()
        for (index, time) in plan.times.enumerated() {
            var fastCounts = Counts(), enabledCounts = Counts()
            // Alternating order removes a fixed A-always-first timing bias.
            for on in index.isMultiple(of: 2) ? [false, true] : [true, false] {
                ReplaySkinnedAthleteMotion.resetClipSampleCountsForTesting()
                let ns = update(on ? enabled : fast, scenario, time: time, perspective: focus.id, enabled: on)
                let counts = ReplaySkinnedAthleteMotion.clipSampleCountsForTesting
                if on { cpuEnabled.append(ns); enabledCounts = counts } else { cpuFast.append(ns); fastCounts = counts }
            }
            let a = try snapshot(fast), b = try snapshot(enabled)
            assertTrajectory(a, b, label: "\(scenario.id)/\(focus.id)/\(time)")
            XCTAssertEqual(Set(a.bodies.keys), Set(b.bodies.keys)); XCTAssertEqual(b.bodies.count, scenario.players.count)
            XCTAssertEqual(b.bodies[focus.id]?.detail, "near")
            XCTAssertEqual(fastCounts.slowRun, 0)
            for (counts, bodies) in [(fastCounts, a.bodies), (enabledCounts, b.bodies)] {
                XCTAssertGreaterThanOrEqual(counts.total, bodies.count); XCTAssertLessThanOrEqual(counts.total, bodies.count * 3)
            }
            let ball = recording.pose(at: time)
            XCTAssertEqual(b.ball.translation, [ball.position.x, max(ball.height, 0.11), ball.position.z])
            var expectedSlowSamples = 0, positiveIDs: [String] = []
            for player in scenario.players {
                let body = try XCTUnwrap(b.bodies[player.id]), control = try XCTUnwrap(a.bodies[player.id])
                let label = "\(scenario.id)/\(player.id)/\(body.detail)/\(time)"
                let cell = "\(player.team.rawValue)/\(body.detail)"; coverage.insert(cell)
                XCTAssertEqual(control.weight, 0)
                XCTAssertTrue(body.weight.isFinite && (0...1).contains(body.weight), label)
                let raw = features(player, time)
                let expected = protected.contains(player.id) ? Float(0) : timelines[player.id]?.weight(at: time) ?? 0
                XCTAssertEqual(body.weight, expected, label)
                if raw.weight == 0 {
                    XCTAssertEqual(body.weight, 0, "Prepared source must retain known raw zero/fast-cut gate: \(label)")
                }
                if protected.contains(player.id) || body.weight == 0 { assertPose(body, control, label: label) }
                if body.weight > 0 {
                    positive.insert(cell); positiveIDs.append(player.id)
                    let locomotion = player.locomotion(at: time)
                    if locomotion.effort * min(max(locomotion.speedMetresPerSecond / 2.4, 0), 1) > 0.02 { expectedSlowSamples += 1 }
                    if body.joints != control.joints { changed += 1 }
                }
            }
            XCTAssertEqual(enabledCounts.slowRun, expectedSlowSamples, "Actual admitted source sampling, not asset presence")
            if index > 0 {
                let dt = time - plan.times[index - 1]
                if dt > 0, dt <= 1 / 120.0 + 0.0000001 {
                    for (id, body) in b.bodies {
                        let old = savedEnabled[index - 1].bodies[id]!, before = savedFast[index - 1].bodies[id]!, control = a.bodies[id]!
                        let weightChange = abs(body.weight - old.weight)
                        XCTAssertLessThanOrEqual(weightChange, Float(4 * dt) + 0.000001,
                            "4/s temporal admission bound: \(scenario.id)/\(id)/\(time), dt=\(dt)")
                        weightPeak.add(weightChange, player: id, time: time, dt: dt)
                        // Report signed rates only on actual 120 Hz pairs, not
                        // tiny merged gaps between independent boundary probes.
                        if abs(dt - 1 / 120.0) < 0.0000001 {
                            let rate = (body.weight - old.weight) / Float(dt)
                            riseRate.add(rate, player: id, time: time, dt: dt)
                            fallRate.add(-rate, player: id, time: time, dt: dt)
                        }
                        let ab = jointStep(before.joints, control.joints), bb = jointStep(old.joints, body.joints)
                        fastPeak.add(ab.angle, player: id, time: time, dt: dt, joint: ab.joint)
                        enabledPeak.add(bb.angle, player: id, time: time, dt: dt, joint: bb.joint)
                        if id == focus.id {
                            focusFastPeak.add(ab.angle, player: id, time: time, dt: dt, joint: ab.joint)
                            focusEnabledPeak.add(bb.angle, player: id, time: time, dt: dt, joint: bb.joint)
                        }
                    }
                }
            }
            savedFast.append(a); savedEnabled.append(b)
            let feature = features(focus, time)
            rows.append(["time": time, "focusWeight": b.bodies[focus.id]!.weight, "speed": feature.speed,
                "rawFocusWeight": feature.weight, "turn": feature.turn, "absoluteTravelYaw": feature.yaw, "positiveIDs": positiveIDs.sorted(),
                "fastClipSamples": countsRow(fastCounts), "enabledClipSamples": countsRow(enabledCounts)])
        }
        for (index, time) in plan.times.enumerated().reversed() {
            _ = update(fast, scenario, time: time, perspective: focus.id, enabled: false)
            _ = update(enabled, scenario, time: time, perspective: focus.id, enabled: true)
            assertState(try snapshot(fast), savedFast[index], label: "fast rewind \(scenario.id)/\(focus.id)/\(time)")
            assertState(try snapshot(enabled), savedEnabled[index], label: "enabled rewind \(scenario.id)/\(focus.id)/\(time)")
        }
        XCTAssertEqual(PitchSceneFactory.slowRunBuildNanosecondsForTesting(in: fast), fastBuildNS)
        XCTAssertEqual(PitchSceneFactory.slowRunBuildNanosecondsForTesting(in: enabled), enabledBuildNS)
        return (["scenario": scenario.id, "focus": focus.id, "focusTeam": focus.team.rawValue,
            "frames": rows, "sampleCount": plan.times.count, "sampledBoundaries": plan.boundaries,
            "missingBoundaries": plan.missing, "protectedIDs": protected.sorted(), "changedPositivePoses": changed,
            "maxFastJointStepDegrees": fastPeak.row, "maxEnabledJointStepDegrees": enabledPeak.row,
            "maxFocusFastJointStepDegrees": focusFastPeak.row, "maxFocusEnabledJointStepDegrees": focusEnabledPeak.row,
            "maxWeightDelta": weightPeak.row, "cpuFast": timing(cpuFast), "cpuEnabled": timing(cpuEnabled),
            "coldFastRoot": coldFast, "coldEnabledRoot": coldEnabled,
            "pairedRegression": try pairedRegression(scenario, plan: plan, fast: savedFast, enabled: savedEnabled),
            "maxPositiveWeightDerivative": slopeRow(riseRate, sign: 1, scenario: scenario, focus: focus, timelines: timelines),
            "maxNegativeWeightDerivative": slopeRow(fallRate, sign: -1, scenario: scenario, focus: focus, timelines: timelines),
            "exactRewind": true, "sourceBallRoutesExact": true], coverage, positive)
    }

    private func slopeRow(_ peak: Peak, sign: Float, scenario: ReplayScenario, focus: PlayerTrack,
                          timelines: [String: ReplaySlowRunTimeline]) -> [String: Any] {
        guard let player = scenario.player(id: peak.player), peak.value > 0 else { return ["observed": false] }
        let before = features(player, peak.time - peak.dt), after = features(player, peak.time)
        return ["observed": true, "player": player.id, "team": player.team.rawValue,
            "detail": player.id == focus.id ? "near" : "low", "signedWeightPerSecond": sign * peak.value,
            "startTime": before.time, "endTime": after.time, "dtSeconds": peak.dt,
            "weightBeforeAfter": [timelines[player.id]?.weight(at: before.time) ?? 0, timelines[player.id]?.weight(at: after.time) ?? 0],
            "rawWeightBeforeAfter": [before.weight, after.weight], "speedBeforeAfter": [before.speed, after.speed],
            "turnBeforeAfter": [before.turn, after.turn], "absoluteTravelYawBeforeAfter": [before.yaw, after.yaw]]
    }

    private func timelineMetrics(_ root: Entity, constructionNanoseconds: UInt64) -> [String: Any] {
        let timelines = PitchSceneFactory.slowRunTimelinesForTesting(in: root)
        var knots = 0, samples = 0, bytes = 0
        var rows: [[String: Any]] = []
        for id in timelines.keys.sorted() {
            let timeline = timelines[id]!, metrics = timeline.metricsForTesting
            var cells = max(1, Int(ceil(timeline.duration * ReplaySlowRunTimeline.sampleRate)))
            if cells > 1, timeline.startTime + Double(cells - 1) / ReplaySlowRunTimeline.sampleRate >= timeline.endTime { cells -= 1 }
            XCTAssertEqual(metrics.knotCount, cells + 1)
            XCTAssertEqual(metrics.rawSampleCount, (metrics.knotCount - 1) * 2 + 1)
            XCTAssertEqual(metrics.storageBytes, metrics.knotCount * MemoryLayout<Float>.stride)
            XCTAssertTrue(timeline.knotsForTesting.allSatisfy { $0.isFinite && (0...1).contains($0) })
            knots += metrics.knotCount; samples += metrics.rawSampleCount; bytes += metrics.storageBytes
            rows.append(["player": id, "startTime": timeline.startTime, "endTime": timeline.endTime,
                         "duration": timeline.duration, "knotCount": metrics.knotCount,
                         "rawSampleCount": metrics.rawSampleCount, "storageBytes": metrics.storageBytes])
        }
        return ["rootConstructionNanoseconds": constructionNanoseconds,
            "timelineBuildNanoseconds": PitchSceneFactory.slowRunBuildNanosecondsForTesting(in: root),
            "timelineCount": timelines.count, "knotCount": knots, "rawSampleCount": samples,
            "storedWeightBytes": bytes, "players": rows,
            "scope": "Cold per-root preparation after shared asset/physics prewarm; root construction includes graph work. Weight payload excludes array/dictionary/allocator overhead. Raw samples count policy requests, not expensive movement-intent evaluations. Separate from warm update timings."]
    }

    private func regressionPair(_ scenarioID: String) -> (id: String, joint: Int, start: Double, end: Double)? {
        switch scenarioID {
        case "city-57-underlap-cutback": ("liv-38", 56, 4.0666666666666664, 4.075)
        case "city-45-overlap-header": ("liv-2", 61, 2.8833333333333333, 2.8916666666666666)
        default: nil
        }
    }

    private func pairedRegression(_ scenario: ReplayScenario, plan: Plan, fast: [State], enabled: [State]) throws -> [[String: Any]] {
        guard let pair = regressionPair(scenario.id) else { return [] }
        let start = try XCTUnwrap(plan.times.firstIndex(of: pair.start)), end = try XCTUnwrap(plan.times.firstIndex(of: pair.end))
        let motion = try XCTUnwrap(ReplaySkinnedAthleteProvider.motion)
        let majorNames = ["hips", "spine", "chest", "neck", "head", "leftHip", "rightHip", "leftKnee", "rightKnee",
                          "leftAnkle", "rightAnkle", "leftToe", "rightToe", "leftShoulder", "rightShoulder",
                          "leftElbow", "rightElbow", "leftWrist", "rightWrist"]
        let majorIndices = try majorNames.map { try XCTUnwrap(motion.semanticJointIndices[$0]) }
        var variants: [[String: Any]] = []
        for (name, states) in [("fast", fast), ("prepared", enabled)] {
            let a = try XCTUnwrap(states[start].bodies[pair.id]), b = try XCTUnwrap(states[end].bodies[pair.id])
            let all = jointStep(a.joints, b.joints)
            let major = majorIndices.map { ($0, jointAngle(a.joints[$0], b.joints[$0])) }.max { $0.1 < $1.1 }!
            var global = Peak()
            for (id, before) in states[start].bodies {
                let after = try XCTUnwrap(states[end].bodies[id]), step = jointStep(before.joints, after.joints)
                global.add(step.angle, player: id, time: pair.end, dt: pair.end - pair.start, joint: step.joint)
            }
            variants.append(["variant": name, "detail": b.detail, "weightBeforeAfter": [a.weight, b.weight],
                "offendingFingerDegrees": jointAngle(a.joints[pair.joint], b.joints[pair.joint]),
                "actorAllJointMaximum": ["degrees": all.angle, "jointIndex": all.joint,
                    "jointName": all.joint >= 0 ? motion.jointNames[all.joint] : "none"],
                "actorMajorJointMaximum": ["degrees": major.1, "jointIndex": major.0, "jointName": motion.jointNames[major.0]],
                "samePairAllPlayersMaximum": global.row,
                "majorJointSteps": zip(majorNames, majorIndices).map { semantic, index in
                    ["semantic": semantic, "jointIndex": index, "degrees": jointAngle(a.joints[index], b.joints[index])] as [String: Any]
                }])
        }
        let player = try XCTUnwrap(scenario.player(id: pair.id))
        let before = features(player, pair.start), after = features(player, pair.end)
        return [["player": pair.id, "startTime": pair.start, "endTime": pair.end, "dtSeconds": pair.end - pair.start,
            "offendingFingerJointIndex": pair.joint, "offendingFingerJointName": motion.jointNames[pair.joint],
            "rawWeightBeforeAfter": [before.weight, after.weight], "speedBeforeAfter": [before.speed, after.speed],
            "turnBeforeAfter": [before.turn, after.turn], "yawBeforeAfter": [before.yaw, after.yaw], "variants": variants,
            "scope": "Exact same actor/joint/time pair. Major set includes semantic trunk, head, limbs and toes, excludes fingers; global row covers all actors at this same pair."]]
    }

    private func snapshot(_ root: Entity) throws -> State {
        let players = try XCTUnwrap(root.findEntity(named: "players-root")), ball = try XCTUnwrap(root.findEntity(named: "ball"))
        var bodies: [String: Body] = [:]
        for (id, skin) in PitchSceneFactory.skinnedAthletesForTesting(in: root) {
            let pose = skin.pose
            XCTAssertGreaterThanOrEqual(skin.contactSurface.minimumY(in: pose) - skin.motion.geometry.restMinY,
                                       skin.contactSurface.paddingMetres - 0.0001, "\(id) floor geometry")
            for side in ["left", "right"] {
                for pair in [("Hip", "Knee"), ("Knee", "Ankle"), ("Shoulder", "Elbow"), ("Elbow", "Wrist")] {
                    let a = try XCTUnwrap(skin.motion.semanticJointIndices[side + pair.0]), b = try XCTUnwrap(skin.motion.semanticJointIndices[side + pair.1])
                    XCTAssertEqual(simd_distance(pose.modelSpaceTransforms[a].columns.3, pose.modelSpaceTransforms[b].columns.3),
                        simd_distance(skin.motion.restPose.modelSpaceTransforms[a].columns.3, skin.motion.restPose.modelSpaceTransforms[b].columns.3), accuracy: 0.0002)
                }
            }
            bodies[id] = .init(detail: skin.detail == .near ? "near" : "low", joints: skin.model.jointTransforms,
                root: skin.root.transform, front: skin.front.transform, back: skin.back.transform, weight: skin.slowRunWeightForTesting)
        }
        return .init(root: root.transform, actors: Dictionary(uniqueKeysWithValues: players.children.map { ($0.name, $0.transform) }),
                     ball: ball.transform, bodies: bodies)
    }
    private func update(_ root: Entity, _ scenario: ReplayScenario, time: Double, perspective: String,
                        enabled: Bool, view: ReplayViewMode = .tacticalTable, impact: PlayerRagdollCue? = nil) -> UInt64 {
        let start = DispatchTime.now().uptimeNanoseconds
        PitchSceneFactory.update(root: root, scenario: scenario, time: time, viewMode: view, perspectiveID: perspective,
            marks: scenario.coachMarks, showsLaneLens: false, isDrawing: false, positionalOriginTransform: nil,
            showsIdealBranch: view == .positional, ragdollCue: impact, playerDetail: .fullSquad, allowsSlowRunSource: enabled)
        return DispatchTime.now().uptimeNanoseconds - start
    }
    private func assertTrajectory(_ a: State, _ b: State, label: String) {
        XCTAssertEqual(a.root, b.root, label); XCTAssertEqual(a.ball, b.ball, label)
        XCTAssertTrue(a.actors == b.actors, "Actor trajectories: \(label)")
    }
    private func assertPose(_ a: Body, _ b: Body, label: String) {
        XCTAssertEqual(a.detail, b.detail, label); XCTAssertTrue(a.joints == b.joints, "Exact joints: \(label)")
        XCTAssertEqual(a.root, b.root, label); XCTAssertEqual(a.front, b.front, label); XCTAssertEqual(a.back, b.back, label)
    }
    private func assertState(_ a: State, _ b: State, label: String) {
        assertTrajectory(a, b, label: label); XCTAssertEqual(Set(a.bodies.keys), Set(b.bodies.keys), label)
        for (id, body) in a.bodies {
            guard let saved = b.bodies[id] else { XCTFail("Missing rewind body \(id)"); continue }
            assertPose(body, saved, label: "\(label)/\(id)"); XCTAssertEqual(body.weight, saved.weight, label)
        }
    }
    nonisolated private func jointStep(_ a: [Transform], _ b: [Transform]) -> (angle: Float, joint: Int) {
        var result: (Float, Int) = (0, -1)
        for index in a.indices {
            let angle = jointAngle(a[index], b[index])
            if angle > result.0 { result = (angle, index) }
        }
        return result
    }
    nonisolated private func jointAngle(_ a: Transform, _ b: Transform) -> Float {
        let p = a.rotation.vector, q = b.rotation.vector
        let x = SIMD4<Double>(Double(p.x), Double(p.y), Double(p.z), Double(p.w))
        let y = SIMD4<Double>(Double(q.x), Double(q.y), Double(q.z), Double(q.w))
        let denominator = sqrt(simd_dot(x, x) * simd_dot(y, y))
        guard denominator.isFinite, denominator > 0 else { XCTFail("Invalid native quaternion norm"); return 0 }
        return Float(2 * acos(min(max(abs(simd_dot(x, y)) / denominator, 0), 1)) * 180 / Double.pi)
    }
    private func countsRow(_ counts: Counts) -> [String: Int] { ["idle": counts.idle, "fast": counts.fastRun, "slow": counts.slowRun, "total": counts.total] }
    private func timing(_ values: [UInt64]) -> [String: Any] {
        let sorted = values.sorted(), n = sorted.count
        return ["samples": n, "medianMilliseconds": Double(sorted[n / 2]) / 1_000_000,
                "p95Milliseconds": Double(sorted[max(0, Int(ceil(Double(n) * 0.95)) - 1)]) / 1_000_000,
                "maximumMilliseconds": Double(sorted.last!) / 1_000_000,
                "scope": "Warm unpaced Factory.update CPU only; optimization level external; not FPS"]
    }
    private func attach(_ value: [String: Any], name: String) throws {
        let attachment = XCTAttachment(data: try JSONSerialization.data(withJSONObject: value, options: [.sortedKeys]), uniformTypeIdentifier: "public.json")
        attachment.name = name; attachment.lifetime = .keepAlways; add(attachment)
    }
}
