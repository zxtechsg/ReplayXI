import RealityKit
import XCTest
@testable import ReplayXI

@MainActor
final class ReplaySkinnedAthleteImpactTests: XCTestCase {
    override func tearDown() {
        ReplaySkinnedAthleteProvider.resetForTesting()
        ReplayAthleteHeadProvider.resetForTesting()
        super.tearDown()
    }

    private func prepare() throws -> (PlayerTrack, PlayerRagdollCue, ReplaySkinnedAthleteInstance) {
        try ReplaySkinnedAthleteProvider.prewarm()
        let scenario = try XCTUnwrap(DemoScenarios.scenario(for: .coachFocus))
        let cue = try XCTUnwrap(PlayerRagdollCue.authoredDemo(for: scenario))
        let player = try XCTUnwrap(scenario.player(id: cue.playerID))
        return (player, cue, try ReplaySkinnedAthleteProvider.make(for: player))
    }

    private func update(_ skin: ReplaySkinnedAthleteInstance, player: PlayerTrack,
                        cue: PlayerRagdollCue, at time: Double,
                        file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertTrue(skin.update(at: time, track: player, locomotion: player.locomotion(at: time),
                                  lookTarget: [9, 0.2, 20], ballAction: nil,
                                  impact: PlayerRagdollPlayback.sample(for: cue, at: time)), file: file, line: line)
        XCTAssertTrue(skin.root.isEnabled, file: file, line: line)
    }

    private func position(_ matrix: simd_float4x4) -> SIMD3<Float> {
        SIMD3(matrix.columns.3.x, matrix.columns.3.y, matrix.columns.3.z)
    }

    func testImpactKeepsSkinNumbersAndExactArbitraryRewind() throws {
        let (player, cue, skin) = try prepare()
        let mesh = try XCTUnwrap(skin.model.model?.mesh)
        let time = cue.impactTime + 1
        update(skin, player: player, cue: cue, at: time)
        let transforms = skin.model.jointTransforms
        let front = skin.front.transform
        let back = skin.back.transform
        let head = try XCTUnwrap(skin.motion.semanticJointIndices["head"])
        XCTAssertLessThan(position(skin.pose.modelSpaceTransforms[head]).y, 1)
        let hips = try XCTUnwrap(skin.motion.semanticJointIndices["hips"])
        XCTAssertLessThan(position(skin.pose.modelSpaceTransforms[hips]).y, 0.35,
                          "A contacted arm must fold instead of levitating the whole torso")
        for seek in [cue.endTime + 1, 2, cue.impactTime + 0.12, cue.endTime - 0.1, time] {
            update(skin, player: player, cue: cue, at: seek)
            XCTAssertTrue(skin.model.model?.mesh === mesh)
        }
        XCTAssertEqual(skin.model.jointTransforms, transforms)
        XCTAssertEqual(skin.front.transform, front)
        XCTAssertEqual(skin.back.transform, back)
        let chest = skin.pose.modelSpaceTransforms[skin.motion.numberAnchors.jointIndex]
        for (number, anchor) in [(skin.front, skin.motion.numberAnchors.front),
                                 (skin.back, skin.motion.numberAnchors.back)] {
            let expected = chest * SIMD4(anchor, 1)
            XCTAssertLessThan(simd_distance(number.position, SIMD3(expected.x, expected.y, expected.z)), 0.00001)
        }
    }

    func testEveryImpactFrameHasFiniteRigidLimbsAndSmoothEdges() throws {
        let (player, cue, skin) = try prepare()
        var pairs: [(Int, Int)] = []
        for side in ["left", "right"] {
            for (first, second) in [("Hip", "Knee"), ("Knee", "Ankle"), ("Shoulder", "Elbow"), ("Elbow", "Wrist")] {
                pairs.append((try XCTUnwrap(skin.motion.semanticJointIndices[side + first]),
                              try XCTUnwrap(skin.motion.semanticJointIndices[side + second])))
            }
        }
        var previous: [Transform]?
        for time in stride(from: cue.impactTime - 0.03, through: cue.endTime + 0.03, by: 1.0 / 240) {
            update(skin, player: player, cue: cue, at: time)
            XCTAssertTrue(skin.pose.translations.allSatisfy { $0.x.isFinite && $0.y.isFinite && $0.z.isFinite })
            XCTAssertTrue(skin.pose.rotations.allSatisfy { abs(simd_length($0.vector) - 1) < 0.0001 })
            for (first, second) in pairs {
                let expected = simd_distance(position(skin.motion.restPose.modelSpaceTransforms[first]),
                                             position(skin.motion.restPose.modelSpaceTransforms[second]))
                let actual = simd_distance(position(skin.pose.modelSpaceTransforms[first]),
                                           position(skin.pose.modelSpaceTransforms[second]))
                XCTAssertEqual(actual, expected, accuracy: 0.004, "Limb length at \(time)")
            }
            if let previous {
                for (index, pair) in zip(previous, skin.model.jointTransforms).enumerated() {
                    let (before, after) = pair
                    XCTAssertLessThan(simd_distance(before.translation, after.translation), 0.04, "Translation at \(time)")
                    XCTAssertGreaterThan(abs(simd_dot(before.rotation.vector, after.rotation.vector)), 0.995,
                                         "\(skin.motion.joints[index].sourceName) rotation at \(time)")
                }
            }
            previous = skin.model.jointTransforms
        }
    }

    func testSupportEnvelopeClearsTurfForAllImpactDirections() throws {
        let (player, _, skin) = try prepare()
        let retargeter = try XCTUnwrap(ReplaySkinnedAthleteImpactPose(motion: skin.motion, contactSurface: skin.contactSurface))
        for angle in stride(from: Float(0), to: 2 * .pi, by: .pi / 4) {
            for impulse: Float in [0.35, 1, 2.1] {
                let cue = PlayerRagdollCue(playerID: player.id, impactTime: 12, duration: 3.2,
                                          impactDirection: [sin(angle), cos(angle)], impulse: impulse)
                for elapsed in [0.2, 0.5, 1, 2] {
                    update(skin, player: player, cue: cue, at: cue.impactTime + elapsed)
                    XCTAssertEqual(cue.influence(at: cue.impactTime + elapsed), 1)
                    XCTAssertGreaterThanOrEqual(retargeter.minimumSupportY(in: skin.pose)
                        - skin.motion.geometry.restMinY, -0.0001)
                    if PlayerRagdollPlayback.pose(for: cue, at: cue.impactTime + elapsed).fallAngle >= 1.479 {
                        XCTAssertEqual(retargeter.minimumSupportY(in: skin.pose) - skin.motion.geometry.restMinY,
                                       skin.contactSurface.paddingMetres, accuracy: 0.0001,
                                       "Landed bodies must settle, not hover above oversized support shapes")
                    }
                }
            }
        }
    }

    func testImpactTargetIsContinuousBeforeRecoveryBlend() throws {
        let (player, cue, skin) = try prepare()
        var previous: [Transform]?
        for time in stride(from: cue.impactTime, to: cue.endTime, by: 1.0 / 240) {
            let impact = PlayerRagdollPlayback.Sample(playerID: player.id, time: time,
                pose: PlayerRagdollPlayback.pose(for: cue, at: time), influence: 1)
            XCTAssertTrue(skin.update(at: time, track: player, locomotion: player.locomotion(at: time),
                                      lookTarget: nil, ballAction: nil, impact: impact))
            if let previous {
                for (index, pair) in zip(previous, skin.model.jointTransforms).enumerated() {
                    XCTAssertGreaterThan(abs(simd_dot(pair.0.rotation.vector, pair.1.rotation.vector)), 0.995,
                                         "\(skin.motion.joints[index].sourceName) target at \(time)")
                }
            }
            previous = skin.model.jointTransforms
        }
    }

    func testContactRetargetIsContinuousForEightFallDirections() throws {
        let (player, _, skin) = try prepare()
        for angle in stride(from: Float(0), to: 2 * .pi, by: .pi / 4) {
            let cue = PlayerRagdollCue(playerID: player.id, impactTime: 12, duration: 3.2,
                                      impactDirection: [sin(angle), cos(angle)], impulse: 1.15)
            var previous: [Transform]?
            for time in stride(from: cue.impactTime - 0.01, through: cue.endTime + 0.01, by: 1.0 / 120) {
                update(skin, player: player, cue: cue, at: time)
                XCTAssertTrue(skin.pose.rotations.allSatisfy { abs(simd_length($0.vector) - 1) < 0.0001 })
                if let previous {
                    for (index, pair) in zip(previous, skin.model.jointTransforms).enumerated() {
                        XCTAssertLessThan(simd_distance(pair.0.translation, pair.1.translation), 0.08,
                                          "\(skin.motion.joints[index].sourceName), angle \(angle), time \(time)")
                        XCTAssertGreaterThan(abs(simd_dot(pair.0.rotation.vector, pair.1.rotation.vector)), 0.99,
                                             "\(skin.motion.joints[index].sourceName), angle \(angle), time \(time)")
                    }
                }
                previous = skin.model.jointTransforms
            }
        }
    }

    func testImpactSampleRejectsInvalidTimesAndWrongSubject() throws {
        let (player, cue, skin) = try prepare()
        let upright = PlayerRagdollPlayback.pose(for: cue, at: cue.impactTime)
        for time in [Double.nan, .infinity, -.infinity] {
            XCTAssertNil(PlayerRagdollPlayback.sample(for: cue, at: time))
            XCTAssertEqual(PlayerRagdollPlayback.pose(for: cue, at: time), upright)
        }
        XCTAssertNil(PlayerRagdollPlayback.sample(for: cue, at: cue.endTime))
        let time = cue.impactTime + 1
        let wrongCue = PlayerRagdollCue(playerID: "not-this-player", impactTime: cue.impactTime)
        XCTAssertFalse(skin.update(at: time, track: player, locomotion: player.locomotion(at: time),
                                   lookTarget: nil, ballAction: nil,
                                   impact: PlayerRagdollPlayback.sample(for: wrongCue, at: time)))
        XCTAssertFalse(skin.root.isEnabled)
        XCTAssertFalse(skin.update(at: time, track: player, locomotion: player.locomotion(at: time),
                                   lookTarget: nil, ballAction: nil,
                                   impact: PlayerRagdollPlayback.sample(for: cue, at: time - 0.1)))
        update(skin, player: player, cue: cue, at: time)
    }

    func testImpactPoseBuffersAreReusedAcrossSeeks() throws {
        let (player, cue, skin) = try prepare()
        update(skin, player: player, cue: cue, at: cue.impactTime + 1)
        let translations = skin.pose.translations.withUnsafeBufferPointer { UInt(bitPattern: $0.baseAddress!) }
        let rotations = skin.pose.rotations.withUnsafeBufferPointer { UInt(bitPattern: $0.baseAddress!) }
        let hierarchy = skin.pose.modelSpaceTransforms.withUnsafeBufferPointer { UInt(bitPattern: $0.baseAddress!) }
        for time in stride(from: cue.endTime + 1, through: cue.impactTime - 1, by: -0.03) {
            update(skin, player: player, cue: cue, at: time)
        }
        XCTAssertEqual(skin.pose.translations.withUnsafeBufferPointer { UInt(bitPattern: $0.baseAddress!) }, translations)
        XCTAssertEqual(skin.pose.rotations.withUnsafeBufferPointer { UInt(bitPattern: $0.baseAddress!) }, rotations)
        XCTAssertEqual(skin.pose.modelSpaceTransforms.withUnsafeBufferPointer { UInt(bitPattern: $0.baseAddress!) }, hierarchy)
    }

    func testSceneKeepsImpactSkinAndUpdatesHiddenQueryRig() throws {
        let (player, cue, _) = try prepare()
        let scenario = try XCTUnwrap(DemoScenarios.scenario(for: .coachFocus))
        let root = PitchSceneFactory.makeMatchRoot(for: scenario)
        func update(_ time: Double, mode: ReplayViewMode = .tacticalTable) {
            PitchSceneFactory.update(root: root, scenario: scenario, time: time, viewMode: mode,
                                     perspectiveID: scenario.defaultPerspectiveID, marks: [], showsLaneLens: false,
                                     isDrawing: false, positionalOriginTransform: nil, ragdollCue: cue)
        }
        func skins(_ entity: Entity) -> [Entity] {
            (entity.name == ReplaySkinnedAthleteProvider.visualRootName ? [entity] : [])
                + entity.children.flatMap { skins($0) }
        }
        update(cue.impactTime - 0.1)
        XCTAssertEqual(skins(root).count, 1)
        update(cue.impactTime + 0.55)
        let subject = try XCTUnwrap(root.findEntity(named: "player-\(player.id)"))
        let skin = try XCTUnwrap(subject.findEntity(named: ReplaySkinnedAthleteProvider.visualRootName))
        XCTAssertTrue(skin.isEnabled)
        XCTAssertEqual(skins(root).count, 2)
        let fullRig = try XCTUnwrap(subject.findEntity(named: "full-rig"))
        let body = try XCTUnwrap(fullRig.findEntity(named: "body-root"))
        let firstPose = body.transform
        XCTAssertNotNil(fullRig.findEntity(named: "ragdoll-physics-active"))
        XCTAssertEqual(fullRig.findEntity(named: "spine")?.components[PhysicsBodyComponent.self]?.mode, .kinematic)
        XCTAssertFalse(try XCTUnwrap(fullRig.findEntity(named: "left-thigh")).isEnabled)
        update(cue.impactTime + 1.5)
        XCTAssertNotEqual(body.transform, firstPose, "Invisible physics must not retain a stale run pose")
        XCTAssertTrue(skin.parent === subject)
        update(cue.impactTime + 0.55)
        XCTAssertEqual(body.transform, firstPose)
        update(cue.impactTime + 0.55, mode: .firstPerson)
        XCTAssertLessThanOrEqual(skins(root).count, PitchSceneFactory.firstPersonDetailedRigLimit)
        XCTAssertTrue(try XCTUnwrap(subject.findEntity(named: ReplaySkinnedAthleteProvider.visualRootName)).isEnabled)
        let wearer = try XCTUnwrap(root.findEntity(named: "player-\(scenario.defaultPerspectiveID)"))
        XCTAssertTrue(skins(wearer).isEmpty)
        update(cue.endTime + 0.1)
        XCTAssertEqual(skins(root).count, 1)
        XCTAssertNil(subject.findEntity(named: ReplaySkinnedAthleteProvider.visualRootName))
        XCTAssertNil(subject.findEntity(named: "ragdoll-physics-active"))
    }

    func testImpactRetargetPoseGallery() throws {
        let (player, cue, skin) = try prepare()
        var samples: [[String: Any]] = []
        for (name, elapsed) in [("before", -0.1), ("entry", 0.08), ("fall", 0.25), ("land", 0.55),
                                ("settled", 1.5), ("recover-a", 2.25), ("recover-b", 2.6), ("after", 2.9)] {
            update(skin, player: player, cue: cue, at: cue.impactTime + elapsed)
            samples.append([
                "name": name, "time": cue.impactTime + elapsed, "groundOffset": -skin.motion.geometry.restMinY,
                "translations": skin.pose.translations.map { [$0.x, $0.y, $0.z] },
                "rotations": skin.pose.rotations.map { [$0.vector.x, $0.vector.y, $0.vector.z, $0.vector.w] },
                "scales": skin.pose.scales.map { [$0.x, $0.y, $0.z] }
            ])
        }
        let data = try JSONSerialization.data(withJSONObject: ["samples": samples], options: [.sortedKeys])
        let attachment = XCTAttachment(data: data, uniformTypeIdentifier: "public.json")
        attachment.name = "ReplayXI-ImpactRetarget-Poses.json"
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    func testContactCalibrationPoseGallery() throws {
        let (player, _, skin) = try prepare()
        var samples: [[String: Any]] = []
        var batch = 0
        for direction in 0..<8 {
            let angle = Float(direction) * .pi / 4
            for (strength, impulse) in [Float(0.35), 1, 2.1].enumerated() {
                let cue = PlayerRagdollCue(playerID: player.id, impactTime: 12, duration: 3.2,
                                          impactDirection: [sin(angle), cos(angle)], impulse: impulse)
                for (phase, elapsed) in [0.2, 0.45, 0.9, 2.0].enumerated() {
                    update(skin, player: player, cue: cue, at: cue.impactTime + elapsed)
                    samples.append([
                        "name": "impact-d\(direction)-s\(strength)-p\(phase)",
                        "time": cue.impactTime + elapsed, "groundOffset": -skin.motion.geometry.restMinY,
                        "translations": skin.pose.translations.map { [$0.x, $0.y, $0.z] },
                        "rotations": skin.pose.rotations.map { [$0.vector.x, $0.vector.y, $0.vector.z, $0.vector.w] },
                        "scales": skin.pose.scales.map { [$0.x, $0.y, $0.z] }
                    ])
                }
                if samples.count == 24 {
                    let data = try JSONSerialization.data(withJSONObject: ["samples": samples], options: [.sortedKeys])
                    let attachment = XCTAttachment(data: data, uniformTypeIdentifier: "public.json")
                    attachment.name = "ReplayXI-ContactCalibration-\(batch).json"
                    attachment.lifetime = .keepAlways
                    add(attachment)
                    samples.removeAll(keepingCapacity: true)
                    batch += 1
                }
            }
        }
        XCTAssertEqual(batch, 4)
        XCTAssertTrue(samples.isEmpty)
    }
}
