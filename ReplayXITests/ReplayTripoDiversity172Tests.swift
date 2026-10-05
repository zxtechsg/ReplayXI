import Foundation
import RealityKit
import XCTest
@testable import ReplayXI

@MainActor
final class ReplayTripoDiversity172Tests: XCTestCase {
    override func setUp() {
        super.setUp()
        ReplayTripoAthleteProvider.resetForTesting()
        ReplaySkinnedAthleteProvider.resetForTesting()
    }

    override func tearDown() {
        ReplayTripoAthleteProvider.resetForTesting()
        ReplaySkinnedAthleteProvider.resetForTesting()
        super.tearDown()
    }

    private func track(team: FootballTeam, shirtNumber: Int, id: String,
                       isGoalkeeper: Bool = false, displayName: String = "Fictional player") -> PlayerTrack {
        PlayerTrack(id: id, displayName: displayName, role: isGoalkeeper ? "GK" : "CM",
            shirtNumber: shirtNumber, team: team, isGoalkeeper: isGoalkeeper, keyframes: [
                .init(time: 0, position: .init(x: 0, z: -4), facingDegrees: 0),
                .init(time: 4, position: .init(x: 0, z: 4), facingDegrees: 0),
            ])
    }

    private func deepTrack(for team: FootballTeam, id: String = "diversity-player",
                           isGoalkeeper: Bool = false, displayName: String = "Fictional player") -> PlayerTrack {
        // Keep the existing deterministic appearance slot: .deep is home #3 / away #1.
        track(team: team, shirtNumber: team == .home ? 3 : 1, id: id,
              isGoalkeeper: isGoalkeeper, displayName: displayName)
    }

    func testDiverseIdentitySelectionIsStableAndUsesFictionalRosterInputs() throws {
        for team in FootballTeam.allCases {
            for shirtNumber in 0..<15 {
                let first = track(team: team, shirtNumber: shirtNumber, id: "stable-a")
                let renamed = track(team: team, shirtNumber: shirtNumber, id: "stable-b",
                                    displayName: "Another fictional name")
                let expected = ReplayTripoAppearance.palette(for: first) == .deep
                XCTAssertEqual(ReplayTripoAthleteProvider.prefersDiverseGeometry(for: first), expected)
                XCTAssertEqual(ReplayTripoAthleteProvider.prefersDiverseGeometry(for: renamed), expected,
                               "Selection must not depend on a player name or ID")

                let keeper = deepTrack(for: team, id: "keeper-\(team.rawValue)", isGoalkeeper: true)
                XCTAssertTrue(ReplayTripoAthleteProvider.prefersDiverseGeometry(for: keeper),
                              "Goalkeeper kit choice must not change the geometry identity slot")
            }
        }
    }

    func testBothTeamsUseSeparateDiverseGeometryAtNearAndLowDetail() throws {
        try ReplayTripoAthleteProvider.prewarm()
        XCTAssertTrue(ReplayTripoAthleteProvider.isPrewarmed)
        XCTAssertTrue(ReplayTripoAthleteProvider.diversityIsPrewarmed,
            "Optional PlayerA geometry unavailable: \(ReplayTripoAthleteProvider.diversityPreparationErrorForTesting ?? "no error reported")")
        XCTAssertEqual(ReplayTripoAthleteProvider.loadedGeometryCount, 2)
        XCTAssertFalse(ReplaySkinnedAthleteProvider.isPrewarmed,
                       "The original and diverse Tripo rigs must not decode the Rocketbox family")

        for team in FootballTeam.allCases {
            let player = deepTrack(for: team, id: "diverse-\(team.rawValue)")
            XCTAssertTrue(ReplayTripoAthleteProvider.prefersDiverseGeometry(for: player))
            for detail in [ReplaySkinnedAthleteProvider.Detail.near, .lowDetail] {
                let base = try ReplayTripoAthleteProvider.make(for: player, detail: detail)
                let diverse = try ReplayTripoAthleteProvider.makeDiverse(for: player, detail: detail)
                let repeated = try ReplayTripoAthleteProvider.makeDiverse(for: player, detail: detail)
                XCTAssertFalse(base.model.model?.mesh === diverse.model.model?.mesh,
                               "\(team) \(detail) should load the separate PlayerA geometry")
                XCTAssertTrue(diverse.model.model?.mesh === repeated.model.model?.mesh,
                              "Repeated construction must reuse the same selected geometry")
                XCTAssertEqual(diverse.motion.rigProfile, .tripo52)
                XCTAssertEqual(diverse.model.jointNames.count, 52)
                XCTAssertEqual(diverse.model.jointNames, diverse.motion.jointNames)
                XCTAssertEqual(diverse.model.model?.materials.count, 1)
                let material = try XCTUnwrap(diverse.model.model?.materials.first as? PhysicallyBasedMaterial)
                XCTAssertEqual(material.faceCulling, .none,
                               "Thin generated cloth folds must not open backface pinholes")
                XCTAssertEqual(diverse.root.scale, base.root.scale,
                               "The new identity must keep the same world scale")
                XCTAssertNotNil(ReplaySkinnedAthleteFootballPose(motion: diverse.motion,
                                                                 bootMarkers: diverse.bootMarkers))
                XCTAssertNotNil(ReplaySkinnedAthleteImpactPose(motion: diverse.motion,
                                                                contactSurface: diverse.contactSurface))
            }
        }

        let homeKeeper = deepTrack(for: .home, id: "keeper-home", isGoalkeeper: true)
        let keeperBase = try ReplayTripoAthleteProvider.make(for: homeKeeper, detail: .near)
        let keeperDiverse = try ReplayTripoAthleteProvider.makePreferred(for: homeKeeper, detail: .near)
        XCTAssertFalse(keeperBase.model.model?.mesh === keeperDiverse.model.model?.mesh)
        XCTAssertEqual(keeperDiverse.root.scale, keeperBase.root.scale)
        XCTAssertEqual(keeperDiverse.model.model?.materials.count, 1)
    }

    func testDiverseNearAndLowMotionStaysFiniteAndReverseSeekStable() throws {
        try ReplayTripoAthleteProvider.prewarm()
        XCTAssertTrue(ReplayTripoAthleteProvider.diversityIsPrewarmed,
            "Optional PlayerA geometry unavailable: \(ReplayTripoAthleteProvider.diversityPreparationErrorForTesting ?? "no error reported")")
        for team in FootballTeam.allCases {
            let player = deepTrack(for: team, id: "motion-\(team.rawValue)")
            for detail in [ReplaySkinnedAthleteProvider.Detail.near, .lowDetail] {
                let skin = try ReplayTripoAthleteProvider.makeDiverse(for: player, detail: detail)
                func seek(_ time: Double) {
                    XCTAssertTrue(skin.update(at: time, track: player,
                        locomotion: player.locomotion(at: time), lookTarget: nil, ballAction: nil))
                }
                seek(1.25)
                let expected = skin.model.jointTransforms
                seek(3.1); seek(0.4); seek(1.25)
                XCTAssertEqual(skin.model.jointTransforms, expected,
                               "Seeking backwards must reproduce the same pose")

                let head = try XCTUnwrap(skin.motion.semanticJointIndices["head"])
                let leftShoulder = try XCTUnwrap(skin.motion.semanticJointIndices["leftShoulder"])
                let rightShoulder = try XCTUnwrap(skin.motion.semanticJointIndices["rightShoulder"])
                for index in [head, leftShoulder, rightShoulder] {
                    let transform = skin.model.jointTransforms[index]
                    let values = [transform.translation.x, transform.translation.y, transform.translation.z,
                                  transform.rotation.vector.x, transform.rotation.vector.y,
                                  transform.rotation.vector.z, transform.rotation.vector.w,
                                  transform.scale.x, transform.scale.y, transform.scale.z]
                    XCTAssertTrue(values.allSatisfy(\.isFinite),
                                  "\(team) \(detail) joint \(skin.model.jointNames[index]) must stay finite")
                }
            }
        }
    }

    func testDiverseWeightedVerticesStayFiniteAndGroundedAcrossGaits() throws {
        try ReplayTripoAthleteProvider.prewarm()
        XCTAssertTrue(ReplayTripoAthleteProvider.diversityIsPrewarmed,
            "Optional PlayerA geometry unavailable: \(ReplayTripoAthleteProvider.diversityPreparationErrorForTesting ?? "no error reported")")
        for team in FootballTeam.allCases {
            let player = deepTrack(for: team, id: "weighted-\(team.rawValue)")
            for detail in [ReplaySkinnedAthleteProvider.Detail.near, .lowDetail] {
                let skin = try ReplayTripoAthleteProvider.makeDiverse(for: player, detail: detail)
                let contents = try XCTUnwrap(skin.model.model).mesh.contents
                let skeleton = try XCTUnwrap(contents.skeletons.first)
                let part = try XCTUnwrap(contents.models.first?.parts.first)
                let weights = try XCTUnwrap(part.jointInfluences).influences.elements
                XCTAssertEqual(weights.count, part.positions.count * 4)
                let bindings = part.positions.elements.enumerated().map { index, point in
                    weights[(index * 4)..<(index * 4 + 4)].map {
                        (joint: $0.jointIndex,
                         point: skeleton.joints[$0.jointIndex].inverseBindPoseMatrix * SIMD4(point, 1),
                         weight: $0.weight)
                    }
                }

                for (speed, turn) in [(Float(1.1), Float(0)), (3.6, 0), (3.0, 100)] {
                    for time in stride(from: 0.0, through: 1.0, by: 0.25) {
                        let authored = player.locomotion(at: time)
                        let sample = PlayerLocomotionSample(
                            motion: authored.motion, speedMetresPerSecond: speed,
                            accelerationMetresPerSecondSquared: 0,
                            turnRateDegreesPerSecond: turn,
                            state: PlayerLocomotionSample.classify(speedMetresPerSecond: speed,
                                                                  turnRateDegreesPerSecond: turn))
                        let context = "\(team) \(detail) speed=\(speed) turn=\(turn) effort=\(sample.effort) phase=\(authored.motion.locomotionPhase) time=\(time)"
                        var sourcePose = skin.motion.makePoseBuffer()
                        skin.motion.sample(time: time, locomotionEffort: sample.effort,
                            gaitPhase: player.gaitPhase(at: time), into: &sourcePose)
                        let sourceClearance = try weightedMeshMinimumY(skin, pose: sourcePose)
                            - skin.motion.geometry.restMinY
                        XCTAssertTrue(skin.update(at: time, track: player, locomotion: sample,
                            lookTarget: [4, 0.7, 7], ballAction: nil), context)

                        var minimumClearance = Float.infinity
                        for influences in bindings {
                            var point = SIMD4<Float>.zero
                            for influence in influences where influence.weight > 0 {
                                point += skin.pose.modelSpaceTransforms[influence.joint]
                                    * influence.point * influence.weight
                            }
                            XCTAssertTrue(point.x.isFinite && point.y.isFinite && point.z.isFinite,
                                          "\(context) weighted point must stay finite")
                            XCTAssertLessThan(simd_length(SIMD3(point.x, point.y, point.z)), 4, context)
                            minimumClearance = min(minimumClearance,
                                point.y - skin.motion.geometry.restMinY)
                        }
                        XCTAssertGreaterThanOrEqual(minimumClearance, -0.005,
                            "\(context) actual weighted mesh must not penetrate the pitch")
                        // PlayerA's authored run includes real flight: native near/low
                        // readback reached 0.129 m. Allow the wider bound only when
                        // this exact source phase is airborne; keep walk/stance tight.
                        let sourceIsAirborne = speed >= 3 && sourceClearance > 0.08
                        if sourceIsAirborne {
                            XCTAssertLessThan(sourceClearance, 0.16,
                                              "\(context) authored flight itself exceeds the run bound")
                        }
                        let maximumClearance: Float = sourceIsAirborne ? 0.16 : 0.08
                        XCTAssertLessThan(minimumClearance, maximumClearance,
                            "\(context) weighted-mesh clearance exceeds its gait bound")
                    }
                }
            }
        }
    }

    func testDiverseNearAndLowKeepWeightedMeshOnRealContactTargets() throws {
        try ReplayTripoAthleteProvider.prewarm()
        XCTAssertTrue(ReplayTripoAthleteProvider.diversityIsPrewarmed,
            "Optional PlayerA geometry unavailable: \(ReplayTripoAthleteProvider.diversityPreparationErrorForTesting ?? "no error reported")")
        let player = PlayerTrack(id: "diversity-contact", displayName: "Fictional player", role: "CM",
            shirtNumber: 3, team: .home, isGoalkeeper: false,
            keyframes: [.init(time: 0, position: .zero, facingDegrees: 0),
                        .init(time: 2, position: .zero, facingDegrees: 0)])
        let goalkeeper = PlayerTrack(id: "diversity-keeper-contact", displayName: "Fictional keeper", role: "GK",
            shirtNumber: 3, team: .home, isGoalkeeper: true,
            keyframes: [.init(time: 0, position: .zero, facingDegrees: 0),
                        .init(time: 2, position: .zero, facingDegrees: 0)])
        let pass = ReplayAthleteInteractionCue(playerID: player.id, kind: .pass,
            contactTime: 1, startTime: 0.7, endTime: 1.4, kickingLeg: .right,
            contactBallWorldPosition: [0.137, 0.11, 0.42], outgoingDirectionWorld: [0, 0, 1],
            supportFootWorldPosition: [-0.137, 0, 0.035])
        let header = ReplayAthleteInteractionCue(playerID: player.id, kind: .header,
            contactTime: 1, startTime: 0.7, endTime: 1.4, kickingLeg: .right,
            contactBallWorldPosition: [0, 1.72, 0.25], outgoingDirectionWorld: [0, 0, 1],
            supportFootWorldPosition: [-0.137, 0, 0.035], headerSupportLeg: .left)
        let save = ReplayAthleteInteractionCue(playerID: goalkeeper.id, kind: .save,
            contactTime: 1, startTime: 0.7, endTime: 1.4, kickingLeg: .right,
            contactBallWorldPosition: [0, 1.05, 0.25], outgoingDirectionWorld: [0, 0, 1],
            supportFootWorldPosition: [-0.137, 0, 0.035])

        for detail in [ReplaySkinnedAthleteProvider.Detail.near, .lowDetail] {
            let skin = try ReplayTripoAthleteProvider.makeDiverse(for: player, detail: detail)
            let markers = try XCTUnwrap(skin.bootMarkers)
            XCTAssertEqual(markers.markers.count, 2)
            XCTAssertTrue(skin.update(at: 1, track: player, locomotion: player.locomotion(at: 1),
                lookTarget: pass.contactBallWorldPosition, ballAction: nil, interaction: pass))
            let marker = try XCTUnwrap(markers.markers.first {
                (skin.motion.restPose.modelSpaceTransforms[$0.ankleIndex].columns.3.x < 0)
                    == (pass.kickingLeg == .left)
            })
            let boot4 = skin.pose.modelSpaceTransforms[marker.ankleIndex]
                * SIMD4(marker.ankleLocalPosition, 1)
            let actualBoot = SIMD3<Float>(boot4.x, boot4.y - skin.motion.geometry.restMinY, boot4.z)
            let expectedBoot = pass.contactBallWorldPosition
                - pass.outgoingDirectionWorld * ReplayAthleteInteractionPose.ballRadius
            XCTAssertLessThanOrEqual(simd_distance(actualBoot, expectedBoot), 0.03,
                                     "\(detail) weighted boot marker must meet the ball")
            XCTAssertGreaterThanOrEqual(skin.contactSurface.minimumY(in: skin.pose)
                - skin.motion.geometry.restMinY, skin.contactSurface.paddingMetres - 0.000_01)

            XCTAssertTrue(skin.update(at: 1, track: player, locomotion: player.locomotion(at: 1),
                lookTarget: header.contactBallWorldPosition, ballAction: nil, interaction: header))
            let headTriangles = try weightedTriangles(skin, subtree: "head")
            XCTAssertGreaterThan(headTriangles.count, 20, "\(detail) needs actual weighted head triangles")
            let nearestHead = try XCTUnwrap(headTriangles.map {
                nearestPoint(header.contactBallWorldPosition, $0.0, $0.1, $0.2)
            }.min { simd_distance_squared($0, header.contactBallWorldPosition)
                < simd_distance_squared($1, header.contactBallWorldPosition) })
            XCTAssertLessThanOrEqual(abs(simd_distance(nearestHead, header.contactBallWorldPosition)
                - ReplayNativeBallPhysics.radius), 0.03,
                "\(detail) actual weighted head surface must meet the ball")
            let chest = skin.pose.modelSpaceTransforms[skin.motion.numberAnchors.jointIndex]
            let restChestRotation = simd_quatf(skin.motion.restPose.modelSpaceTransforms[
                skin.motion.numberAnchors.jointIndex]).inverse
            let frontAnchor = skin.motion.numberAnchors.front
                + restChestRotation.act(SIMD3<Float>(0, 0, 0.022))
            let front = chest * SIMD4(frontAnchor, 1)
            XCTAssertLessThan(simd_distance(skin.front.position, SIMD3(front.x, front.y, front.z)), 0.000_01,
                              "\(detail) front number must stay attached to the PlayerA chest")

            let keeperSkin = try ReplayTripoAthleteProvider.makeDiverse(for: goalkeeper, detail: detail)
            XCTAssertTrue(keeperSkin.update(at: 1, track: goalkeeper,
                locomotion: goalkeeper.locomotion(at: 1), lookTarget: save.contactBallWorldPosition,
                ballAction: nil, interaction: save))
            let shoulderIndex = try XCTUnwrap(keeperSkin.motion.semanticJointIndices["rightShoulder"])
            let wrist = try XCTUnwrap(keeperSkin.motion.semanticJointIndices["rightWrist"])
            let shoulder4 = keeperSkin.pose.modelSpaceTransforms[shoulderIndex].columns.3
            let shoulder = SIMD3<Float>(shoulder4.x,
                shoulder4.y - keeperSkin.motion.geometry.restMinY, shoulder4.z)
            let handDirection = simd_normalize(save.contactBallWorldPosition - shoulder)
            let elbow = try XCTUnwrap(keeperSkin.motion.semanticJointIndices["rightElbow"])
            let rest = keeperSkin.motion.restPose.modelSpaceTransforms
            let wristRest = rest[wrist].columns.3, elbowRest = rest[elbow].columns.3
            let lowerArm = SIMD3<Float>(wristRest.x - elbowRest.x,
                                        wristRest.y - elbowRest.y,
                                        wristRest.z - elbowRest.z)
            let wristNeutral = simd_quatf(from: simd_normalize(lowerArm), to: [0, -1, 0])
                * simd_quatf(rest[wrist])
            let localPalm = wristNeutral.inverse.act(ReplayAthleteParryIK.palmMarker)
            let palm = keeperSkin.pose.modelSpaceTransforms[wrist]
                * SIMD4(localPalm, 1)
            let actualPalm = SIMD3<Float>(palm.x, palm.y - keeperSkin.motion.geometry.restMinY, palm.z)
            let expectedPalm = save.contactBallWorldPosition - handDirection * 0.11
            XCTAssertLessThanOrEqual(simd_distance(actualPalm, expectedPalm), 0.14,
                                     "\(detail) keeper parry palm must meet the ball")
            XCTAssertGreaterThanOrEqual(keeperSkin.contactSurface.minimumY(in: keeperSkin.pose)
                - keeperSkin.motion.geometry.restMinY,
                keeperSkin.contactSurface.paddingMetres - 0.000_01)

            let impactCue = PlayerRagdollCue(playerID: player.id, impactTime: 1, duration: 2.5)
            let impactTime = 1.55
            let impact = try XCTUnwrap(PlayerRagdollPlayback.sample(for: impactCue, at: impactTime))
            XCTAssertTrue(skin.update(at: impactTime, track: player,
                locomotion: player.locomotion(at: impactTime), lookTarget: nil,
                ballAction: nil, impact: impact))
            XCTAssertGreaterThan(impact.pose.fallAngle, 0.8,
                                 "The native mesh check must sample a real fall, not neutral rest")
            let minimum = try weightedMeshMinimumY(skin)
            XCTAssertGreaterThanOrEqual(minimum - skin.motion.geometry.restMinY, -0.005,
                                        "\(detail) impact mesh must not penetrate the pitch")
            XCTAssertLessThan(minimum - skin.motion.geometry.restMinY, 0.08,
                              "\(detail) impact mesh must remain grounded")
        }
    }

    func testProductionSceneUsesDiverseGeometryForSelectedPlayers() throws {
        try ReplayTripoAthleteProvider.prewarm()
        XCTAssertTrue(ReplayTripoAthleteProvider.diversityIsPrewarmed,
            "Optional PlayerA geometry unavailable: \(ReplayTripoAthleteProvider.diversityPreparationErrorForTesting ?? "no error reported")")
        let scenario = try XCTUnwrap(DemoScenarios.scenario(for: .squadReplay))
        try ReplayAthleteFactory.prewarm(for: scenario.players, lods: [.near, .far])
        PitchSceneFactory.fullSquadSkinsForTesting = true
        defer { PitchSceneFactory.fullSquadSkinsForTesting = false }

        let root = PitchSceneFactory.makeMatchRoot(for: scenario)
        defer { for child in Array(root.children) { child.removeFromParent() } }
        PitchSceneFactory.update(root: root, scenario: scenario, time: 1.25, viewMode: .tacticalTable,
            perspectiveID: scenario.defaultPerspectiveID, marks: scenario.coachMarks,
            showsLaneLens: false, isDrawing: false, positionalOriginTransform: nil,
            playerDetail: .fullSquad)

        let skins = PitchSceneFactory.skinnedAthletesForTesting(in: root)
        XCTAssertEqual(skins.count, scenario.players.count)
        var selectedTeams = Set<FootballTeam>()
        for player in scenario.players where ReplayTripoAthleteProvider.prefersDiverseGeometry(for: player) {
            let selected = try XCTUnwrap(skins[player.id], player.id)
            let base = try ReplayTripoAthleteProvider.make(for: player, detail: selected.detail)
            XCTAssertFalse(selected.model.model?.mesh === base.model.model?.mesh, player.id)
            XCTAssertEqual(selected.motion.rigProfile, .tripo52)
            selectedTeams.insert(player.team)
        }
        XCTAssertEqual(selectedTeams, Set(FootballTeam.allCases),
                       "Both teams must reach the production scene with the optional identity")
    }

    func testDiverseNativeAssetMetadataReadback() throws {
        let variants = [
            ("near", ReplayTripoDiversityAssets.near),
            ("low", ReplayTripoDiversityAssets.low),
        ]
        var reports: [[String: Any]] = []
        for (detail, spec) in variants {
            let url = Bundle.main.url(forResource: spec.asset.name, withExtension: "usdz",
                                      subdirectory: "Resources/Players")
                ?? Bundle.main.url(forResource: spec.asset.name, withExtension: "usdz")
            let assetURL = try XCTUnwrap(url, "Missing native PlayerA \(detail) asset")
            let data = try Data(contentsOf: assetURL)
            let loaded = try Entity.load(contentsOf: assetURL)
            loaded.stopAllAnimations(recursive: true)
            let models = ReplaySkinnedAthleteProvider.skinnedModels(in: loaded)
            XCTAssertEqual(models.count, 1, "PlayerA \(detail) must contain one skinned model")
            let model = try XCTUnwrap(models.first)
            XCTAssertEqual(model.jointNames.count, 52)
            XCTAssertEqual(model.jointTransforms.count, 52)
            let component = try XCTUnwrap(model.model)
            let parts = component.mesh.contents.models.flatMap { Array($0.parts) }
            XCTAssertEqual(parts.count, 1)
            let part = try XCTUnwrap(parts.first)
            let positions = part.positions.count
            let normals = try XCTUnwrap(part.normals)
            let uv = try XCTUnwrap(part.textureCoordinates)
            let influences = try XCTUnwrap(part.jointInfluences).influences
            let indices = try XCTUnwrap(part.triangleIndices)
            XCTAssertGreaterThan(positions, 0)
            XCTAssertEqual(normals.rate, .vertex)
            XCTAssertEqual(normals.count, positions)
            XCTAssertEqual(uv.rate, .vertex)
            XCTAssertEqual(uv.count, positions)
            XCTAssertEqual(influences.count, positions * 4)
            XCTAssertGreaterThan(indices.count, 0)
            XCTAssertEqual(indices.count % 3, 0)
            XCTAssertTrue(influences.elements.allSatisfy {
                (0..<52).contains($0.jointIndex) && $0.weight.isFinite && $0.weight >= 0
            })
            reports.append([
                "detail": detail,
                "resource": spec.asset.name,
                "assetSHA256": spec.asset.sha256,
                "assetBytes": data.count,
                "jointCount": model.jointNames.count,
                "sourceVertices": spec.sourceVertices,
                "expectedImportedVertices": spec.importedVertices,
                "expectedTriangles": spec.triangles,
                "realityKitPositions": positions,
                "realityKitNormals": normals.count,
                "realityKitUVs": uv.count,
                "realityKitInfluences": influences.count,
                "realityKitTriangleIndices": indices.count,
                "parts": parts.count,
            ])
        }
        let attachment = XCTAttachment(data: try JSONSerialization.data(withJSONObject: reports,
                                                                         options: [.sortedKeys]),
                                       uniformTypeIdentifier: "public.json")
        attachment.name = "ReplayXI-Diversity172-Native-Asset-Metadata.json"
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    func testMissingOptionalDiversityResourcesFallBackToBaseGeometry() throws {
        try withAssetBundle(includesDiversity: false) { bundle in
            try ReplayTripoAthleteProvider.prewarm(in: bundle)
            XCTAssertTrue(ReplayTripoAthleteProvider.isPrewarmed)
            XCTAssertFalse(ReplayTripoAthleteProvider.diversityIsPrewarmed)
            XCTAssertEqual(ReplayTripoAthleteProvider.loadedGeometryCount, 1)

            for team in FootballTeam.allCases {
                let player = deepTrack(for: team, id: "fallback-\(team.rawValue)")
                let base = try ReplayTripoAthleteProvider.make(for: player, detail: .near)
                let preferred = try ReplayTripoAthleteProvider.makePreferred(for: player, detail: .near)
                XCTAssertTrue(base.model.model?.mesh === preferred.model.model?.mesh)
                XCTAssertEqual(preferred.motion.rigProfile, .tripo52)
            }
        }
    }

    func testPartialDiversityAssetFailureRejectsWholeOptionalIdentity() throws {
        let brokenContact = ReplayTripoDiversityAssets.low.contacts
        try withAssetBundle(includesDiversity: true, corrupting: brokenContact) { bundle in
            try ReplayTripoAthleteProvider.prewarm(in: bundle)
            XCTAssertTrue(ReplayTripoAthleteProvider.isPrewarmed)
            XCTAssertFalse(ReplayTripoAthleteProvider.diversityIsPrewarmed)
            XCTAssertEqual(ReplayTripoAthleteProvider.loadedGeometryCount, 1)
            XCTAssertNotNil(ReplayTripoAthleteProvider.diversityPreparationErrorForTesting)

            for team in FootballTeam.allCases {
                let player = deepTrack(for: team, id: "partial-fallback-\(team.rawValue)")
                let base = try ReplayTripoAthleteProvider.make(for: player, detail: .lowDetail)
                let preferred = try ReplayTripoAthleteProvider.makePreferred(for: player, detail: .lowDetail)
                XCTAssertTrue(base.model.model?.mesh === preferred.model.model?.mesh)
                XCTAssertEqual(preferred.motion.rigProfile, .tripo52)
            }
        }
    }

    private func withAssetBundle(includesDiversity: Bool,
                                 corrupting diversityResource: ReplayTripoDiversityAssets.Resource? = nil,
                                 _ body: (Bundle) throws -> Void) throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("ReplayXI-Diversity172-\(UUID().uuidString).bundle")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: directory) }
        let info = ["CFBundleIdentifier": "test.replayxi.diversity172", "CFBundlePackageType": "BNDL"]
        let infoData = try PropertyListSerialization.data(fromPropertyList: info, format: .xml, options: 0)
        try infoData.write(to: directory.appendingPathComponent("Info.plist"))

        var resources = [
            ("ReplayXITripoAthlete", "usdz"), ("ReplayXITripoLow", "usdz"),
            ("ReplayXITripoMotion", "json"), ("ReplayXITripoContactSurface", "json"),
            ("ReplayXITripoLowContactSurface", "json"),
            ("ReplayXITripoHome", "png"), ("ReplayXITripoAway", "png"), ("ReplayXITripoKeeper", "png"),
        ]
        if includesDiversity {
            resources += [
                (ReplayTripoDiversityAssets.motion.name, "json"),
                (ReplayTripoDiversityAssets.near.asset.name, "usdz"),
                (ReplayTripoDiversityAssets.near.contacts.name, "json"),
                (ReplayTripoDiversityAssets.low.asset.name, "usdz"),
                (ReplayTripoDiversityAssets.low.contacts.name, "json"),
            ]
            resources += ReplayTripoDiversityAssets.atlases.map { ($0.name, "png") }
        }
        for (name, suffix) in resources {
            let source = Bundle.main.url(forResource: name, withExtension: suffix,
                                         subdirectory: "Resources/Players")
                ?? Bundle.main.url(forResource: name, withExtension: suffix)
            try FileManager.default.copyItem(at: XCTUnwrap(source),
                                             to: directory.appendingPathComponent("\(name).\(suffix)"))
        }
        if let diversityResource {
            try Data("broken optional asset".utf8).write(
                to: directory.appendingPathComponent("\(diversityResource.name).json"))
        }
        try body(XCTUnwrap(Bundle(url: directory)))
    }

    private func weightedMeshMinimumY(_ skin: ReplaySkinnedAthleteInstance,
                                      pose: ReplaySkinnedAthleteMotion.Pose? = nil) throws -> Float {
        let contents = try XCTUnwrap(skin.model.model).mesh.contents
        let skeleton = try XCTUnwrap(contents.skeletons.first)
        let parts = contents.models.flatMap { Array($0.parts) }
        let pose = pose ?? skin.pose
        var minimum = Float.infinity
        for part in parts {
            let weights = try XCTUnwrap(part.jointInfluences).influences.elements
            XCTAssertEqual(weights.count, part.positions.count * 4)
            for (index, point) in part.positions.elements.enumerated() {
                var posed = SIMD4<Float>.zero
                for weight in weights[(index * 4)..<(index * 4 + 4)] where weight.weight > 0 {
                    posed += pose.modelSpaceTransforms[weight.jointIndex]
                        * skeleton.joints[weight.jointIndex].inverseBindPoseMatrix
                        * SIMD4(point, 1) * weight.weight
                }
                XCTAssertTrue(posed.y.isFinite)
                minimum = min(minimum, posed.y)
            }
        }
        return minimum
    }

    private func weightedTriangles(_ skin: ReplaySkinnedAthleteInstance, subtree semantic: String) throws
        -> [(SIMD3<Float>, SIMD3<Float>, SIMD3<Float>)] {
        let contents = try XCTUnwrap(skin.model.model).mesh.contents
        let part = try XCTUnwrap(contents.models.flatMap { Array($0.parts) }.first)
        let skeleton = try XCTUnwrap(contents.skeletons.first)
        let root = try XCTUnwrap(skin.motion.semanticJointIndices[semantic])
        let descendants = Set(skin.motion.joints.indices.filter { index in
            var parent = index
            while parent >= 0 {
                if parent == root { return true }
                parent = skin.motion.joints[parent].parentIndex
            }
            return false
        })
        let weights = try XCTUnwrap(part.jointInfluences).influences.elements
        let positions = part.positions.elements
        var vertices = Array(repeating: SIMD3<Float>.zero, count: positions.count)
        var subtreeWeights = Array(repeating: Float.zero, count: positions.count)
        for index in positions.indices {
            var posed = SIMD4<Float>.zero
            for influence in weights[(index * 4)..<(index * 4 + 4)] where influence.weight > 0 {
                if descendants.contains(influence.jointIndex) { subtreeWeights[index] += influence.weight }
                posed += skin.pose.modelSpaceTransforms[influence.jointIndex]
                    * skeleton.joints[influence.jointIndex].inverseBindPoseMatrix
                    * SIMD4(positions[index], 1) * influence.weight
            }
            vertices[index] = SIMD3(posed.x, posed.y, posed.z)
        }
        let indices = try XCTUnwrap(part.triangleIndices).elements
        var triangles: [(SIMD3<Float>, SIMD3<Float>, SIMD3<Float>)] = []
        for offset in stride(from: 0, to: indices.count, by: 3) {
            let a = Int(indices[offset]), b = Int(indices[offset + 1]), c = Int(indices[offset + 2])
            guard subtreeWeights[a] >= 0.8, subtreeWeights[b] >= 0.8, subtreeWeights[c] >= 0.8 else { continue }
            triangles.append((skin.model.convert(position: vertices[a], to: nil),
                              skin.model.convert(position: vertices[b], to: nil),
                              skin.model.convert(position: vertices[c], to: nil)))
        }
        return triangles
    }

    private func nearestPoint(_ point: SIMD3<Float>, _ a: SIMD3<Float>,
                              _ b: SIMD3<Float>, _ c: SIMD3<Float>) -> SIMD3<Float> {
        let ab = b - a, ac = c - a
        let normal = simd_cross(ab, ac)
        let squaredNormal = simd_length_squared(normal)
        if squaredNormal > 0.000_000_000_1 {
            let projected = point - normal * (simd_dot(point - a, normal) / squaredNormal)
            let relative = projected - a
            let aa = simd_dot(ab, ab), bb = simd_dot(ab, ac), cc = simd_dot(ac, ac)
            let denominator = aa * cc - bb * bb
            if abs(denominator) > 0.000_000_000_1 {
                let u = (cc * simd_dot(relative, ab) - bb * simd_dot(relative, ac)) / denominator
                let v = (aa * simd_dot(relative, ac) - bb * simd_dot(relative, ab)) / denominator
                if u >= 0, v >= 0, u + v <= 1 { return projected }
            }
        }
        func edge(_ start: SIMD3<Float>, _ end: SIMD3<Float>) -> SIMD3<Float> {
            let delta = end - start
            let length = simd_length_squared(delta)
            let t = length > 0.000_000_000_1
                ? min(max(simd_dot(point - start, delta) / length, 0), 1) : 0
            return start + delta * t
        }
        return [edge(a, b), edge(b, c), edge(c, a)].min {
            simd_distance_squared(point, $0) < simd_distance_squared(point, $1)
        }!
    }
}
