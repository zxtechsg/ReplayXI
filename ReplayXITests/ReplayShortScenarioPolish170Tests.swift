import Dispatch
import RealityKit
import simd
import XCTest
@testable import ReplayXI

/// Tests shipping scene poses, not only a detached animation clip. CPU samples
/// are DEBUG Simulator timings; they are not device FPS or motion-capture data.
@MainActor
final class ReplayShortScenarioPolish170Tests: XCTestCase {
    func testCounterattackFullSquadRecoveryContactsGroundingAndRewind() async throws {
        try await audit("final-36-counter-v2")
    }

    func testVolleyFullSquadRecoveryContactsGroundingAndRewind() async throws {
        try await audit("final-81-volley-v2")
    }

    func testHeaderFullSquadRecoveryContactsGroundingAndRewind() async throws {
        try await audit("city-45-overlap-header")
    }

    func testCutbackFullSquadRecoveryContactsGroundingAndRewind() async throws {
        try await audit("city-57-underlap-cutback")
    }

    func testReboundFullSquadRecoveryContactsGroundingAndRewind() async throws {
        try await audit("final-108-rebound-v2")
    }

    private func audit(_ id: String) async throws {
        ReplayTripoAthleteProvider.resetForTesting()
        PitchSceneFactory.fullSquadSkinsForTesting = true
        defer {
            PitchSceneFactory.fullSquadSkinsForTesting = false
            ReplayTripoAthleteProvider.resetForTesting()
            ReplayNativeBallPhysics.resetCacheForTesting()
        }
        let scenario = try XCTUnwrap(FootballReferenceScenarios.all.first { $0.id == id })
        try ReplayTripoAthleteProvider.prewarm()
        try ReplayAthleteFactory.prewarm(for: scenario.players, lods: [.near, .far])
        let initialAssetLoads = ReplayTripoAthleteProvider.nativeAssetLoadAttemptsForTesting
        let initialTexturePreparations = ReplayTripoAthleteProvider.texturePreparationAttemptsForTesting
        let planned = try XCTUnwrap(FootballReferenceScenarios.touches(for: scenario))
        let recording = try await ReplayNativeBallPhysics.prewarm(track: scenario.ball,
            players: scenario.players, plannedTouches: planned)
        XCTAssertEqual(recording.missedTouchCount, 0)
        XCTAssertEqual(recording.touches.count, planned.count)
        let protected = Set(recording.touches.map(\.playerID))
            .union(scenario.players.filter(\.isGoalkeeper).map(\.id))
        let control = PitchSceneFactory.makeMatchRoot(for: scenario, nativeRecording: recording)
        let improved = PitchSceneFactory.makeMatchRoot(for: scenario, nativeRecording: recording)
        defer { for root in [control, improved] { for child in Array(root.children) { child.removeFromParent() } } }
        var active = Set<String>(), changed = Set<String>()
        var maximumRecoveryWeights: [String: Float] = [:]
        var cpuControl: [Double] = [], cpuImproved: [Double] = []
        var minimumClearance: Float = .greatestFiniteMagnitude
        var maximumLowerBodyDelta: Float = 0
        for frame in 0...Int(ceil(scenario.duration * 30)) {
            let time = min(Double(frame) / 30, scenario.duration)
            // Alternate measurement order so one path does not always get a
            // warmer CPU/cache. Assertions and pose readbacks are outside it.
            if frame.isMultiple(of: 2) {
                cpuControl.append(update(control, scenario, time, enabled: false))
                cpuImproved.append(update(improved, scenario, time, enabled: true))
            } else {
                cpuImproved.append(update(improved, scenario, time, enabled: true))
                cpuControl.append(update(control, scenario, time, enabled: false))
            }
            let before = PitchSceneFactory.skinnedAthletesForTesting(in: control)
            let after = PitchSceneFactory.skinnedAthletesForTesting(in: improved)
            XCTAssertEqual(before.count, 22); XCTAssertEqual(after.count, 22)
            for player in scenario.players {
                let a = try XCTUnwrap(before[player.id]), b = try XCTUnwrap(after[player.id])
                XCTAssertEqual(b.motion.rigProfile, .tripo52)
                XCTAssertTrue(b.motion.hasSlowRun)
                let floor = b.contactSurface.minimumY(in: b.pose) - b.motion.geometry.restMinY
                minimumClearance = min(minimumClearance, floor)
                XCTAssertGreaterThanOrEqual(floor, b.contactSurface.paddingMetres - 0.000_02)
                if protected.contains(player.id) {
                    XCTAssertEqual(b.slowRunWeightForTesting, 0)
                    XCTAssertEqual(a.model.jointTransforms, b.model.jointTransforms)
                } else if b.slowRunWeightForTesting > 0 {
                    active.insert(player.id)
                    maximumRecoveryWeights[player.id] = max(maximumRecoveryWeights[player.id] ?? 0,
                        b.slowRunWeightForTesting)
                    if a.model.jointTransforms != b.model.jointTransforms { changed.insert(player.id) }
                    // Arms must not change the boots, root or lower-body source.
                    for name in ["hips", "leftHip", "rightHip", "leftKnee", "rightKnee", "leftAnkle", "rightAnkle"] {
                        let joint = try XCTUnwrap(b.motion.semanticJointIndices[name])
                        let delta = matrixDelta(a.pose.modelSpaceTransforms[joint], b.pose.modelSpaceTransforms[joint])
                        maximumLowerBodyDelta = max(maximumLowerBodyDelta, delta)
                        XCTAssertLessThan(delta, 0.000_001, "\(player.id) \(name) at \(time)")
                    }
                }
            }
        }
        XCTAssertFalse(active.isEmpty)
        // An infinitesimal admission fade can round to the same pose. Require
        // actual differences for meaningful weights, not every positive ULP.
        let meaningful = Set(maximumRecoveryWeights.filter { $0.value >= 0.02 }.map(\.key))
        XCTAssertFalse(meaningful.isEmpty)
        XCTAssertTrue(changed.isSubset(of: active))
        XCTAssertTrue(meaningful.isSubset(of: changed), "\(maximumRecoveryWeights)")
        for team in FootballTeam.allCases {
            XCTAssertTrue(scenario.players.contains { $0.team == team && meaningful.contains($0.id) && changed.contains($0.id) })
        }
        let anchorTime = min(4.5, scenario.duration)
        _ = update(improved, scenario, anchorTime, enabled: true)
        let expected = PitchSceneFactory.skinnedAthletesForTesting(in: improved).mapValues { $0.model.jointTransforms }
        for time in [scenario.duration, 0, 2.3, anchorTime] { _ = update(improved, scenario, time, enabled: true) }
        XCTAssertEqual(PitchSceneFactory.skinnedAthletesForTesting(in: improved).mapValues { $0.model.jointTransforms }, expected)
        XCTAssertEqual(ReplayTripoAthleteProvider.nativeAssetLoadAttemptsForTesting, initialAssetLoads)
        XCTAssertEqual(ReplayTripoAthleteProvider.texturePreparationAttemptsForTesting, initialTexturePreparations)
        let report: [String: Any] = ["scenario": id, "frames": cpuControl.count, "skins": 22,
            "activeRecoveryPlayers": active.sorted(), "protectedPlayers": protected.sorted(),
            "changedRecoveryPlayers": changed.sorted(), "maximumRecoveryWeights": maximumRecoveryWeights,
            "meaningfulWeightThreshold": 0.02,
            "minimumSkinClearanceMetres": minimumClearance,
            "maximumLowerBodyMatrixComponentDelta": maximumLowerBodyDelta,
            "loadedBaseTextureBytesNotTotalMemory": ReplayTripoAthleteProvider.loadedBaseTextureBytes,
            "hotPathNativeAssetLoads": ReplayTripoAthleteProvider.nativeAssetLoadAttemptsForTesting - initialAssetLoads,
            "hotPathTexturePreparations": ReplayTripoAthleteProvider.texturePreparationAttemptsForTesting - initialTexturePreparations,
            "controlWarmCPU": metrics(Array(cpuControl.dropFirst())),
            "improvedWarmCPU": metrics(Array(cpuImproved.dropFirst())),
            "scope": "DEBUG Simulator CPU update only. No device FPS claim. Authored tracks; not recovered poses."]
        let attachment = XCTAttachment(data: try JSONSerialization.data(withJSONObject: report, options: [.sortedKeys]),
                                       uniformTypeIdentifier: "public.json")
        attachment.name = "ReplayXI-Scenario170-\(id).json"; attachment.lifetime = .keepAlways; add(attachment)
    }

    private func update(_ root: Entity, _ scenario: ReplayScenario, _ time: Double, enabled: Bool) -> Double {
        let start = DispatchTime.now().uptimeNanoseconds
        PitchSceneFactory.update(root: root, scenario: scenario, time: time, viewMode: .tacticalTable,
            perspectiveID: scenario.defaultPerspectiveID, marks: scenario.coachMarks, showsLaneLens: false,
            isDrawing: false, positionalOriginTransform: nil, showsIdealBranch: false,
            playerDetail: .fullSquad, allowsSlowRunSource: enabled)
        return Double(DispatchTime.now().uptimeNanoseconds - start) / 1_000_000
    }

    private func metrics(_ values: [Double]) -> [String: Double] {
        let sorted = values.sorted()
        return ["medianMilliseconds": sorted[sorted.count / 2],
                "p95Milliseconds": sorted[min(Int(Double(sorted.count) * 0.95), sorted.count - 1)]]
    }

    private func matrixDelta(_ a: simd_float4x4, _ b: simd_float4x4) -> Float {
        var maximum: Float = 0
        for column in 0..<4 {
            for row in 0..<4 { maximum = max(maximum, abs(a[column][row] - b[column][row])) }
        }
        return maximum
    }
}
