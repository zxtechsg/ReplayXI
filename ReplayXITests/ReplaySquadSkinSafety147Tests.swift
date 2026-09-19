import Foundation
import RealityKit
import simd
import XCTest
@testable import ReplayXI

/// Safety checks for the opt-in squad experiment; no frame-rate claim.
@MainActor
final class ReplaySquadSkinSafety147Tests: XCTestCase {
    private typealias Skin = ReplaySkinnedAthleteInstance
    private typealias Detail = ReplaySkinnedAthleteProvider.Detail
    private struct Context {
        let scenario: ReplayScenario
        let recording: ReplayNativeBallPhysics.Recording
    }
    private struct Saved: Equatable {
        let detail: Detail
        let joints: [Transform]
        let front: Transform
        let back: Transform
        init(_ skin: Skin) {
            detail = skin.detail; joints = skin.model.jointTransforms
            front = skin.front.transform; back = skin.back.transform
        }
    }
    private final class WeakRoot {
        weak var value: Entity?
        init(_ value: Entity) { self.value = value }
    }
    private final class WeakSkin {
        weak var value: Skin?
        init(_ value: Skin) { self.value = value }
    }
    private var roots: [WeakRoot] = []
    private var observedSkins: [WeakSkin] = []

    override func setUp() {
        super.setUp()
        PitchSceneFactory.fullSquadSkinsForTesting = false
        resetProviders()
    }

    override func tearDown() {
        PitchSceneFactory.fullSquadSkinsForTesting = false
        // Expired scene caches prune on the next cold cache creation. Do not
        // leave their strong skin/binding references behind after this test.
        if let scenario = FootballReferenceScenarios.all.first(where: { $0.id == "final-108-rebound-v2" }) {
            let empty = Entity(), marks = Entity()
            marks.name = "marks-root"; empty.addChild(marks)
            update(empty, scenario, time: 0, view: .firstPerson, wearer: "arg-10")
            for child in Array(empty.children) { child.removeFromParent() }
        }
        XCTAssertTrue(roots.allSatisfy { $0.value == nil })
        XCTAssertTrue(observedSkins.allSatisfy { $0.value == nil })
        roots.removeAll(); observedSkins.removeAll()
        resetProviders()
        super.tearDown()
    }

    func testFlagModeAndFormerLowWearerTransitionsKeepOneBodyAndExactRewind() async throws {
        let context = try await rebound()
        PitchSceneFactory.fullSquadSkinsForTesting = true
        defer { PitchSceneFactory.fullSquadSkinsForTesting = false }
        try withScene(context.scenario, recording: context.recording) { root in
            update(root, context.scenario, time: 0.3, view: .tacticalTable, wearer: "arg-10")
            let table = try assertScene(root, context.scenario, view: .tacticalTable, wearer: "arg-10")
            XCTAssertEqual(table.count, 22)
            XCTAssertEqual(table["arg-13"]?.detail, .lowDetail)
            let tablePose = table.mapValues(Saved.init)

            update(root, context.scenario, time: 0.3, view: .firstPerson, wearer: "arg-13")
            let pov = try assertScene(root, context.scenario, view: .firstPerson, wearer: "arg-13")
            assertTransition(from: table, to: pov)
            XCTAssertNil(table["arg-13"]?.root.parent, "A former low wearer must detach before this frame")
            let povPose = pov.mapValues(Saved.init)

            PitchSceneFactory.fullSquadSkinsForTesting = false
            update(root, context.scenario, time: 0.3, view: .firstPerson, wearer: "arg-13")
            let ordinary = try assertScene(root, context.scenario, view: .firstPerson, wearer: "arg-13", allSkins: false)
            XCTAssertEqual(ordinary.count, 2)
            XCTAssertTrue(ordinary.values.allSatisfy { $0.detail == .near })
            assertTransition(from: pov, to: ordinary)

            PitchSceneFactory.fullSquadSkinsForTesting = true
            update(root, context.scenario, time: 0.3, view: .firstPerson, wearer: "arg-13")
            let restored = try assertScene(root, context.scenario, view: .firstPerson, wearer: "arg-13")
            assertTransition(from: ordinary, to: restored)
            XCTAssertEqual(restored.mapValues(Saved.init), povPose)
            update(root, context.scenario, time: 1.2, view: .firstPerson, wearer: "arg-13")
            update(root, context.scenario, time: 0.3, view: .firstPerson, wearer: "arg-13")
            XCTAssertEqual(try assertScene(root, context.scenario, view: .firstPerson, wearer: "arg-13")
                .mapValues(Saved.init), povPose)

            update(root, context.scenario, time: 0.3, view: .tacticalTable, wearer: "arg-10")
            let tableAgain = try assertScene(root, context.scenario, view: .tacticalTable, wearer: "arg-10")
            XCTAssertEqual(tableAgain.mapValues(Saved.init), tablePose)
            assertNativeBall(root, context, at: 0.3)
        }
    }

    func testMissingAndFailedLowAssetsFallBackWithoutRetryingOrBlockingNear() async throws {
        let context = try await rebound()
        PitchSceneFactory.fullSquadSkinsForTesting = true
        defer { PitchSceneFactory.fullSquadSkinsForTesting = false }
        try withScene(context.scenario, recording: context.recording) { root in
            ReplaySkinnedAthleteProvider.setLowDetailMakeFailureForTesting(true)
            update(root, context.scenario, time: 0.3, view: .firstPerson, wearer: "arg-23")
            let near = try assertScene(root, context.scenario, view: .firstPerson, wearer: "arg-23", allSkins: false)
            XCTAssertEqual(near.count, 2)
            XCTAssertEqual(ReplaySkinnedAthleteProvider.lowDetailCloneAttemptCount, 19)
            update(root, context.scenario, time: 0.31, view: .firstPerson, wearer: "arg-23")
            _ = try assertScene(root, context.scenario, view: .firstPerson, wearer: "arg-23", allSkins: false)
            XCTAssertEqual(ReplaySkinnedAthleteProvider.lowDetailCloneAttemptCount, 19)

            // Leaving low admission clears its failure memo; returning can
            // retry successfully without replacing unaffected near instances.
            PitchSceneFactory.fullSquadSkinsForTesting = false
            update(root, context.scenario, time: 0.3, view: .firstPerson, wearer: "arg-23")
            ReplaySkinnedAthleteProvider.setLowDetailMakeFailureForTesting(false)
            PitchSceneFactory.fullSquadSkinsForTesting = true
            update(root, context.scenario, time: 0.3, view: .firstPerson, wearer: "arg-23")
            let complete = try assertScene(root, context.scenario, view: .firstPerson, wearer: "arg-23")
            assertTransition(from: near, to: complete)
            XCTAssertEqual(ReplaySkinnedAthleteProvider.lowDetailCloneAttemptCount, 38)

            ReplaySkinnedAthleteProvider.resetLowDetailForTesting()
            update(root, context.scenario, time: 0.3, view: .firstPerson, wearer: "arg-23")
            let fallback = try assertScene(root, context.scenario, view: .firstPerson, wearer: "arg-23", allSkins: false)
            XCTAssertEqual(fallback.count, 2)
            assertTransition(from: complete, to: fallback)
            try ReplaySkinnedAthleteProvider.prewarmLowDetail()
            update(root, context.scenario, time: 0.3, view: .firstPerson, wearer: "arg-23")
            _ = try assertScene(root, context.scenario, view: .firstPerson, wearer: "arg-23")
        }
    }

    func testRemoteLowRecordedStrikesAndSaveMatchInputsAndStayGrounded() async throws {
        let context = try await rebound()
        PitchSceneFactory.fullSquadSkinsForTesting = true
        defer { PitchSceneFactory.fullSquadSkinsForTesting = false }
        let contacts = context.recording.touches.filter { $0.kind == .shot || $0.kind == .save }
        XCTAssertEqual(contacts.count, 3)
        XCTAssertEqual(contacts.filter { $0.kind == .save }.count, 1)
        var rows: [[String: Any]] = []
        try withScene(context.scenario, recording: context.recording) { root in
            for touch in contacts {
                let player = try XCTUnwrap(context.scenario.player(id: touch.playerID))
                let cues = try context.recording.touches.filter { $0.playerID == player.id }.map(cue)
                let contactCue = try XCTUnwrap(cues.first { $0.contactTime == touch.time })
                update(root, context.scenario, time: touch.time, view: .firstPerson, wearer: "arg-23")
                let actual = try XCTUnwrap(try assertScene(root, context.scenario, view: .firstPerson,
                    wearer: "arg-23")[player.id])
                XCTAssertEqual(actual.detail, .lowDetail, "Contact subject must really be a remote low skin")
                let first = Saved(actual)
                let action = try XCTUnwrap(ReplayAthleteInteractionPose.sample(cue: contactCue, at: touch.time,
                    track: player, presentationPose: player.presentationPose(at: touch.time)))
                XCTAssertEqual(action.influence, 1, accuracy: 0.00001)
                var comparisons: [[String: Any]] = []
                for detail in [Detail.lowDetail, .near] {
                    let oracle = try ReplaySkinnedAthleteProvider.make(for: player, detail: detail)
                    try updateOracle(oracle, context, player: player, cues: cues, time: touch.time)
                    let clearance = assertFloor(oracle)
                    if detail == .lowDetail {
                        XCTAssertEqual(Saved(oracle), first, "Scene must supply the exact recorded contact inputs")
                    }
                    let maxAngle = zip(actual.pose.rotations, oracle.pose.rotations).map {
                        rotationGapDegrees($0.0, $0.1)
                    }.max() ?? 0
                    if detail == .lowDetail { XCTAssertEqual(maxAngle, 0) }
                    let metric = try contactMetric(oracle, action: action)
                    XCTAssertTrue(metric.isFinite)
                    comparisons.append(["detail": String(describing: detail), "floorClearanceMetres": clearance,
                        "maximumRotationGapFromSceneLowDegrees": maxAngle,
                        "contactMetricMetres": metric,
                        "metric": touch.kind == .save ? "nearest wrist to ball centre" : "striking boot to strike surface"])
                }
                for time in [touch.time - 1 / 60.0, touch.time + 1 / 60.0, touch.time] {
                    update(root, context.scenario, time: time, view: .firstPerson, wearer: "arg-23")
                    let skin = try XCTUnwrap(skins(root)[player.id])
                    XCTAssertEqual(skin.detail, .lowDetail)
                    _ = assertFloor(skin)
                    assertNativeBall(root, context, at: time)
                }
                XCTAssertEqual(Saved(try XCTUnwrap(skins(root)[player.id])), first)
                rows.append(["player": player.id, "kind": touch.kind.rawValue, "actualContactTime": touch.time,
                             "isGoalkeeper": player.isGoalkeeper, "comparisons": comparisons])
            }
        }
        try attach(rows)
    }

    func testAuthoredDistantImpactPromotesLowAndKeepsWearerHidden() throws {
        let scenario = try XCTUnwrap(DemoScenarios.scenario(for: .coachFocus))
        let impact = try XCTUnwrap(PlayerRagdollCue.authoredDemo(for: scenario))
        try prepareAssets(scenario)
        PitchSceneFactory.fullSquadSkinsForTesting = true
        defer { PitchSceneFactory.fullSquadSkinsForTesting = false }
        let time = impact.impactTime + 0.55
        let target = try XCTUnwrap(scenario.player(id: impact.playerID)).presentationPose(at: time).position
        let wearer = try XCTUnwrap(scenario.players.filter { $0.id != impact.playerID }.max {
            ReplayGeometry.distance($0.presentationPose(at: time).position, target)
                < ReplayGeometry.distance($1.presentationPose(at: time).position, target)
        }).id
        try withScene(scenario) { root in
            update(root, scenario, time: time, view: .firstPerson, wearer: wearer)
            let ordinary = try assertScene(root, scenario, view: .firstPerson, wearer: wearer)
            let previous = try XCTUnwrap(ordinary[impact.playerID])
            XCTAssertEqual(previous.detail, .lowDetail)
            update(root, scenario, time: time, view: .firstPerson, wearer: wearer, impact: impact)
            let promoted = try assertScene(root, scenario, view: .firstPerson, wearer: wearer)
            assertTransition(from: ordinary, to: promoted)
            let near = try XCTUnwrap(promoted[impact.playerID])
            XCTAssertEqual(near.detail, .near)
            XCTAssertNil(previous.root.parent)
            let saved = Saved(near)
            let subject = try XCTUnwrap(root.findEntity(named: "player-\(impact.playerID)"))
            XCTAssertNotNil(subject.findEntity(named: "ragdoll-physics-active"))
            update(root, scenario, time: time + 0.4, view: .firstPerson, wearer: wearer, impact: impact)
            update(root, scenario, time: time, view: .firstPerson, wearer: wearer, impact: impact)
            XCTAssertEqual(Saved(try XCTUnwrap(skins(root)[impact.playerID])), saved)
            update(root, scenario, time: time, view: .firstPerson, wearer: wearer)
            XCTAssertEqual(try assertScene(root, scenario, view: .firstPerson, wearer: wearer)[impact.playerID]?.detail,
                           .lowDetail)
            XCTAssertNil(subject.findEntity(named: "ragdoll-physics-active"))
            update(root, scenario, time: time, view: .firstPerson, wearer: impact.playerID, impact: impact)
            _ = try assertScene(root, scenario, view: .firstPerson, wearer: impact.playerID)
        }
    }

    private func rebound() async throws -> Context {
        let scenario = try XCTUnwrap(FootballReferenceScenarios.all.first { $0.id == "final-108-rebound-v2" })
        try prepareAssets(scenario)
        let recording = try await ReplayNativeBallPhysics.prewarm(track: scenario.ball, players: scenario.players,
            plannedTouches: FootballReferenceScenarios.touches(for: scenario))
        XCTAssertEqual(recording.samples.count, 841)
        XCTAssertEqual(recording.missedTouchCount, 0)
        return Context(scenario: scenario, recording: recording)
    }

    private func prepareAssets(_ scenario: ReplayScenario) throws {
        try XCTSkipIf(ReplayImportedAthleteFeatureGate.isEnabled, "Default skin path only")
        try ReplaySkinnedAthleteProvider.prewarm()
        try ReplaySkinnedAthleteProvider.prewarmLowDetail()
        try ReplayFarAthleteHeadProvider.prewarm()
        try ReplayArticulatedFarProvider.prewarm()
        try ReplayArticulatedFarKitProvider.prewarm()
        try ReplayAthleteFactory.prewarm(for: scenario.players, lods: [.near, .far])
    }

    private func withScene<T>(_ scenario: ReplayScenario, recording: ReplayNativeBallPhysics.Recording? = nil,
                              body: (Entity) throws -> T) rethrows -> T {
        let root = PitchSceneFactory.makeMatchRoot(for: scenario, nativeRecording: recording)
        roots.append(WeakRoot(root))
        defer { for child in Array(root.children) { child.removeFromParent() } }
        return try body(root)
    }

    private func update(_ root: Entity, _ scenario: ReplayScenario, time: Double, view: ReplayViewMode,
                        wearer: String, impact: PlayerRagdollCue? = nil) {
        PitchSceneFactory.update(root: root, scenario: scenario, time: time, viewMode: view, perspectiveID: wearer,
            marks: scenario.coachMarks, showsLaneLens: false, isDrawing: false,
            positionalOriginTransform: nil, ragdollCue: impact)
        for skin in skins(root).values where !observedSkins.contains(where: { $0.value === skin }) {
            observedSkins.append(WeakSkin(skin))
        }
    }

    private func skins(_ root: Entity) -> [String: Skin] { PitchSceneFactory.skinnedAthletesForTesting(in: root) }

    private func assertScene(_ root: Entity, _ scenario: ReplayScenario, view: ReplayViewMode, wearer: String,
                             allSkins: Bool = true) throws -> [String: Skin] {
        let admitted = skins(root)
        if allSkins { XCTAssertEqual(admitted.count, scenario.players.count - (view == .firstPerson ? 1 : 0)) }
        if view == .firstPerson {
            XCTAssertLessThanOrEqual(admitted.values.filter { $0.detail == .near }.count, 2)
            XCTAssertNil(admitted[wearer])
        }
        for player in scenario.players {
            let body = try XCTUnwrap(root.findEntity(named: "player-\(player.id)"))
            let attached = body.children.filter { $0.name == ReplaySkinnedAthleteProvider.visualRootName }
            XCTAssertEqual(attached.count, admitted[player.id] == nil ? 0 : 1, "No orphan skin roots: \(player.id)")
            let far = try XCTUnwrap(body.children.first { $0.name == "table-marker" })
            let full = body.children.first { $0.name == "full-rig" }
            let isWearer = view == .firstPerson && player.id == wearer
            if isWearer {
                XCTAssertTrue(attached.isEmpty)
                XCTAssertNil(full)
                XCTAssertFalse(far.isEnabledInHierarchy)
                XCTAssertFalse(try XCTUnwrap(body.findEntity(named: "interaction-target")).isEnabledInHierarchy)
                continue
            }
            let skinVisible = admitted[player.id]?.model.isEnabledInHierarchy == true
            let farVisible = models(far).contains { $0.isEnabledInHierarchy }
            let fullVisible = full.map { models($0).contains { $0.isEnabledInHierarchy } } ?? false
            XCTAssertEqual([skinVisible, farVisible, fullVisible].filter { $0 }.count, 1,
                           "Exactly one visible body branch: \(player.id)")
            if let skin = admitted[player.id] {
                XCTAssertTrue(skin.root.parent === body)
                XCTAssertTrue(skinVisible)
                XCTAssertFalse(farVisible)
                XCTAssertFalse(fullVisible)
                if view == .firstPerson && skin.detail == .lowDetail { XCTAssertNil(full) }
            }
        }
        return admitted
    }

    private func models(_ root: Entity) -> [ModelEntity] {
        ((root as? ModelEntity).map { [$0] } ?? []) + root.children.flatMap { models($0) }
    }

    private func assertTransition(from before: [String: Skin], to after: [String: Skin]) {
        for (id, old) in before {
            if let current = after[id], current.detail == old.detail { XCTAssertTrue(current === old, id) }
            else { XCTAssertNil(old.root.parent, "Departed/replaced visual must detach: \(id)") }
        }
    }

    private func rotationGapDegrees(_ lhs: simd_quatf, _ rhs: simd_quatf) -> Float {
        if lhs.vector == rhs.vector || lhs.vector == -rhs.vector { return 0 }
        let relative = simd_normalize(simd_normalize(lhs).inverse * simd_normalize(rhs))
        return 2 * atan2(simd_length(relative.imag), abs(relative.real)) * 180 / Float.pi
    }

    @discardableResult
    private func assertFloor(_ skin: Skin) -> Float {
        let floor = skin.contactSurface.minimumY(in: skin.pose) - skin.motion.geometry.restMinY
        XCTAssertGreaterThanOrEqual(floor, skin.contactSurface.paddingMetres - 0.0001)
        XCTAssertTrue(skin.pose.translations.allSatisfy { $0.x.isFinite && $0.y.isFinite && $0.z.isFinite })
        XCTAssertTrue(skin.pose.rotations.allSatisfy { abs(simd_length($0.vector) - 1) < 0.0001 })
        XCTAssertEqual(skin.model.jointTransforms.count, 80)
        return floor
    }

    private func assertNativeBall(_ root: Entity, _ context: Context, at time: Double) {
        XCTAssertTrue(PitchSceneFactory.nativeBallRecordingForTesting(in: root) === context.recording)
        let position = context.recording.sample(at: time).position
        XCTAssertEqual(root.findEntity(named: "ball")?.position, [position.x, max(position.y, 0.11), position.z])
    }

    private func cue(_ touch: ReplayNativeBallPhysics.Touch) throws -> ReplayAthleteInteractionCue {
        ReplayAthleteInteractionCue(playerID: touch.playerID,
            kind: try XCTUnwrap(ReplayAthleteInteractionCue.Kind(rawValue: touch.kind.rawValue)),
            contactTime: touch.time, startTime: touch.time - 0.32, endTime: touch.time + 0.42,
            kickingLeg: touch.kickingLeg, contactBallWorldPosition: touch.position,
            outgoingDirectionWorld: touch.outgoingVelocity, headerSupportLeg: touch.headerSupportLeg)
    }

    private func updateOracle(_ skin: Skin, _ context: Context, player: PlayerTrack,
                              cues: [ReplayAthleteInteractionCue], time: Double) throws {
        let pose = player.presentationPose(at: time), locomotion = player.locomotion(at: time)
        let ball = context.recording.sample(at: time).position
        let poses = Dictionary(uniqueKeysWithValues: context.scenario.players.map { ($0.id, $0.presentationPose(at: time)) })
        let interaction = cues.filter { ReplayAthleteMovementIntent.includesPreparation($0, at: time) }
            .min { abs($0.contactTime - time) < abs($1.contactTime - time) }
        let look = ReplayAthleteTacticalAttention.target(for: player, at: time, pose: pose, ball: ball,
            players: context.scenario.players, poses: poses, contacts: cues)
        let shots = ReplayFootballShotTimeline(touches: context.recording.touches, players: context.scenario.players)
        let keeper = player.isGoalkeeper ? ReplayGoalkeeperReadiness.sample(track: player, at: time,
            presentationPose: pose, ballPosition: ball, shot: shots.latestOpposingShot(for: player, at: time),
            actionInfluence: ReplayAthleteInteractionPose.sample(cue: interaction, at: time, track: player,
                presentationPose: pose)?.influence ?? 0, enabled: true, locomotion: locomotion) : nil
        XCTAssertTrue(skin.update(at: time, track: player, locomotion: locomotion, lookTarget: look,
            ballAction: nil, interaction: interaction, presentationPose: pose, goalkeeperReadiness: keeper,
            allowsTrackLocomotionSampling: true))
    }

    /// Unscaled actor-local geometry, matching the interaction solver's basis.
    /// These values are evidence, not invented contact-quality thresholds.
    private func contactMetric(_ skin: Skin, action: ReplayAthleteInteractionSample) throws -> Float {
        func point(_ index: Int, _ offset: SIMD3<Float> = .zero) -> SIMD3<Float> {
            let p = skin.pose.modelSpaceTransforms[index] * SIMD4(offset, 1)
            return [p.x, p.y - skin.motion.geometry.restMinY, p.z]
        }
        if action.kind == .save {
            return try ["leftWrist", "rightWrist"].map {
                simd_distance(point(try XCTUnwrap(skin.motion.semanticJointIndices[$0])), action.ballCentreTarget)
            }.min() ?? 0
        }
        let marker = try XCTUnwrap(skin.bootMarkers?.markers.first {
            (skin.motion.restPose.modelSpaceTransforms[$0.ankleIndex].columns.3.x < 0) == (action.kickingLeg == .left)
        })
        return simd_distance(point(marker.ankleIndex, marker.ankleLocalPosition), action.strikeSurfaceTarget)
    }

    private func attach(_ rows: [[String: Any]]) throws {
        let data = try JSONSerialization.data(withJSONObject: [
            "scope": "Actual native rebound contact times; production remote-low scene versus direct low/near providers",
            "limit": "Unscaled actor-local boot/wrist metrics; not mesh-surface collision, visual approval or headset FPS",
            "contacts": rows
        ], options: [.prettyPrinted, .sortedKeys])
        let attachment = XCTAttachment(data: data, uniformTypeIdentifier: "public.json")
        attachment.name = "SquadSkinSafety147-ActualRemoteContacts"
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    private func resetProviders() {
        ReplayArticulatedFarKitProvider.resetForTesting()
        ReplayArticulatedFarProvider.resetForTesting()
        ReplayFarAthleteHeadProvider.resetForTesting()
        ReplaySkinnedAthleteProvider.resetForTesting()
        ReplayImportedAthleteProvider.resetPrewarmForTesting()
        ReplayAthleteHeadProvider.resetForTesting()
        ReplayFarAthletePaletteProvider.resetForTesting()
        ReplayNativeBallPhysics.resetCacheForTesting()
    }
}
