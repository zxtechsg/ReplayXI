import RealityKit
import XCTest
@testable import ReplayXI

@MainActor
final class ReplayFarAthleteGroundingTests: XCTestCase {
    private let floorTolerance: Float = 0.001
    private let views: [ReplayViewMode] = [.tacticalTable, .touchline, .firstPerson]

    override func setUp() {
        super.setUp()
        ReplaySkinnedAthleteProvider.resetForTesting()
        ReplayImportedAthleteProvider.resetPrewarmForTesting()
    }

    override func tearDown() {
        ReplaySkinnedAthleteProvider.resetForTesting()
        ReplayImportedAthleteProvider.resetPrewarmForTesting()
        ReplayAthleteHeadProvider.resetForTesting()
        super.tearDown()
    }

    private func update(_ root: Entity, scenario: ReplayScenario, time: Double, view: ReplayViewMode) {
        PitchSceneFactory.update(root: root, scenario: scenario, time: time, viewMode: view,
                                 perspectiveID: "navy-gk", marks: [], showsLaneLens: false,
                                 isDrawing: false, positionalOriginTransform: nil)
    }

    private func farMarker(in root: Entity, playerID: String) throws -> (Entity, Entity) {
        let player = try XCTUnwrap(root.findEntity(named: "player-\(playerID)"))
        let marker = try XCTUnwrap(player.children.first { $0.name == "table-marker" })
        XCTAssertTrue(player.isEnabled)
        XCTAssertTrue(marker.isEnabledInHierarchy, "The measured far mesh must actually be visible")
        return (player, marker)
    }

    private func legPoints(in rig: Entity, relativeTo frame: Entity) throws -> [SIMD3<Float>] {
        try ["left-leg", "right-leg"].flatMap { name in
            let model = try XCTUnwrap(rig.findEntity(named: name) as? ModelEntity)
            let component = try XCTUnwrap(model.model)
            return component.mesh.contents.models.flatMap { mesh in
                mesh.parts.flatMap { part in
                    part.positions.elements.map { model.convert(position: $0, to: frame) }
                }
            }
        }
    }

    private func minimumY(in rig: Entity, relativeTo frame: Entity) throws -> Float {
        let points = try legPoints(in: rig, relativeTo: frame)
        XCTAssertFalse(points.isEmpty)
        XCTAssertTrue(points.allSatisfy { $0.x.isFinite && $0.y.isFinite && $0.z.isFinite })
        return try XCTUnwrap(points.map(\.y).min())
    }

    private func pose(for player: PlayerTrack, scenario: ReplayScenario, time: Double) -> ReplayAthleteLocomotionPose {
        let ball = scenario.ball.pose(at: time)
        return ReplayAthleteMotion.locomotionPose(for: player, at: time,
                                                 lookTargetWorldPosition: [ball.position.x, ball.height, ball.position.z],
                                                 ballTrack: scenario.ball)
    }

    private func assertAuthoredPose(_ expected: ReplayAthleteLocomotionPose,
                                    rig: Entity, allowsVerticalLift: Bool) throws {
        // Factory bindings are created before the root is renamed table-marker.
        // Inspect the live joints without re-binding or mutating that graph.
        let actualBody = try XCTUnwrap(rig.findEntity(named: ReplayAthleteJoint.bodyRoot.rawValue)).position
        XCTAssertEqual(actualBody.x, expected.bodyPosition.x)
        XCTAssertEqual(actualBody.z, expected.bodyPosition.z)
        if allowsVerticalLift {
            XCTAssertGreaterThanOrEqual(actualBody.y, expected.bodyPosition.y,
                                        "A floor correction must never pull a clear or airborne pose down")
        } else {
            XCTAssertEqual(actualBody.y, expected.bodyPosition.y)
        }
        XCTAssertEqual(try XCTUnwrap(rig.findEntity(named: ReplayAthleteJoint.hips.rawValue)).position, expected.hipsPosition)
        let orientations: [(ReplayAthleteJoint, simd_quatf)] = [
            (.bodyRoot, expected.bodyOrientation), (.hips, expected.hipsOrientation),
            (.spine, expected.spineOrientation), (.neck, expected.neckOrientation), (.headRoot, expected.headOrientation),
            (.leftHip, expected.leftHipOrientation), (.rightHip, expected.rightHipOrientation),
            (.leftKnee, expected.leftKneeOrientation), (.rightKnee, expected.rightKneeOrientation),
            (.leftAnkle, expected.leftAnkleOrientation), (.rightAnkle, expected.rightAnkleOrientation),
            (.leftShoulder, expected.leftShoulderOrientation), (.rightShoulder, expected.rightShoulderOrientation),
            (.leftElbow, expected.leftElbowOrientation), (.rightElbow, expected.rightElbowOrientation),
            (.leftWrist, expected.leftWristOrientation), (.rightWrist, expected.rightWristOrientation),
        ]
        for (joint, orientation) in orientations {
            let entity = try XCTUnwrap(rig.findEntity(named: joint.rawValue))
            XCTAssertEqual(entity.orientation.vector, orientation.vector,
                           "Floor correction must not change \(joint.rawValue) articulation")
        }
    }

    private func raised(_ pose: ReplayAthleteLocomotionPose, by height: Float) -> ReplayAthleteLocomotionPose {
        ReplayAthleteLocomotionPose(
            bodyPosition: pose.bodyPosition + SIMD3(0, height, 0), bodyOrientation: pose.bodyOrientation,
            hipsPosition: pose.hipsPosition, hipsOrientation: pose.hipsOrientation,
            spineOrientation: pose.spineOrientation, neckOrientation: pose.neckOrientation, headOrientation: pose.headOrientation,
            leftHipOrientation: pose.leftHipOrientation, rightHipOrientation: pose.rightHipOrientation,
            leftKneeOrientation: pose.leftKneeOrientation, rightKneeOrientation: pose.rightKneeOrientation,
            leftAnkleOrientation: pose.leftAnkleOrientation, rightAnkleOrientation: pose.rightAnkleOrientation,
            leftShoulderOrientation: pose.leftShoulderOrientation, rightShoulderOrientation: pose.rightShoulderOrientation,
            leftElbowOrientation: pose.leftElbowOrientation, rightElbowOrientation: pose.rightElbowOrientation,
            leftWristOrientation: pose.leftWristOrientation, rightWristOrientation: pose.rightWristOrientation
        )
    }

    private func attach(_ rows: [[String: Any]], named name: String) throws {
        let data = try JSONSerialization.data(withJSONObject: ["samples": rows], options: [.sortedKeys])
        let attachment = XCTAttachment(data: data, uniformTypeIdentifier: "public.json")
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    func testVisibleFarSceneMeshesStayAbovePitchAcrossViewsAndSkinAdmission() throws {
        let scenario = try XCTUnwrap(DemoScenarios.scenario(for: .squadReplay))
        let fixtures: [(String, Double)] = [("navy-rb", 6.95), ("navy-rb", 11.691666666666666),
                                             ("red-lw", 14.083333333333334)]
        var report: [[String: Any]] = []
        for usesSkin in [false, true] {
            ReplaySkinnedAthleteProvider.resetForTesting()
            if usesSkin { try ReplaySkinnedAthleteProvider.prewarm() }
            let root = PitchSceneFactory.makeMatchRoot(for: scenario)
            for view in views {
                for (playerID, time) in fixtures {
                    update(root, scenario: scenario, time: time, view: view)
                    let (player, marker) = try farMarker(in: root, playerID: playerID)
                    let minimum = try minimumY(in: marker, relativeTo: root)
                    XCTAssertGreaterThanOrEqual(minimum, -floorTolerance,
                                               "\(playerID) at \(time), \(view): actual far vertices must not be buried")
                    let source = try XCTUnwrap(scenario.player(id: playerID)).presentationPose(at: time)
                    XCTAssertEqual(player.position, SIMD3(source.position.x, 0, source.position.z))
                    report.append([
                        "playerID": playerID, "time": time, "view": view.rawValue, "skinPrewarmed": usesSkin,
                        "minimumPitchLocalY": minimum, "focusScale": player.scale.x,
                        "appearanceScale": [marker.scale.x, marker.scale.y, marker.scale.z],
                        "roomScale": root.scale.x, "markerVisible": marker.isEnabledInHierarchy,
                    ])
                }
            }
        }
        try attach(report, named: "ReplayXI-FarGround89-Scene.json")
    }

    func testFarSceneBallActionsKeepArticulationAndClearThePitch() throws {
        let scenario = try XCTUnwrap(DemoScenarios.scenario(for: .squadReplay))
        let root = PitchSceneFactory.makeMatchRoot(for: scenario)
        var report: [[String: Any]] = []
        for view in views {
            for (playerID, time) in [("navy-rw", 10.1), ("navy-rw", 13.6), ("navy-rb", 17.5)] {
                let player = try XCTUnwrap(scenario.player(id: playerID))
                let action = try XCTUnwrap(ReplayAthleteMotion.ballActionPose(for: player, ballTrack: scenario.ball, at: time))
                XCTAssertGreaterThan(action.influence, 0.05)
                update(root, scenario: scenario, time: time, view: view)
                let (_, marker) = try farMarker(in: root, playerID: playerID)
                try assertAuthoredPose(pose(for: player, scenario: scenario, time: time), rig: marker, allowsVerticalLift: true)
                let minimum = try minimumY(in: marker, relativeTo: root)
                XCTAssertGreaterThanOrEqual(minimum, -floorTolerance,
                                           "An active touch must not bury the far support silhouette")
                report.append(["playerID": playerID, "time": time, "view": view.rawValue,
                               "actionInfluence": action.influence, "minimumPitchLocalY": minimum])
            }
        }
        try attach(report, named: "ReplayXI-FarGround89-Actions.json")
    }

    func testNearAndMidRemainExactlyTheAuthoredPoseAcrossRunAndBallActionSamples() throws {
        let scenario = try XCTUnwrap(DemoScenarios.scenario(for: .squadReplay))
        for playerID in ["navy-rb", "navy-rw", "red-lw"] {
            let player = try XCTUnwrap(scenario.player(id: playerID))
            for lod in [ReplayAthleteLOD.near, .mid] {
                let rig = try ReplayAthleteFactory.make(for: player, lod: lod)
                for time in [6.95, 12.233333333333333, 13.6, 17.5, 26.54] {
                    let authored = pose(for: player, scenario: scenario, time: time)
                    ReplayAthleteMotion.apply(authored, to: rig.joints)
                    try assertAuthoredPose(authored, rig: rig.root, allowsVerticalLift: false)
                }
            }
        }
    }

    func testAlreadyClearFarFlightAndAddedAuthoredHeightRemainUntouched() throws {
        let scenario = try XCTUnwrap(DemoScenarios.scenario(for: .squadReplay))
        for (playerID, time) in [("navy-rb", 7.166666666666666), ("navy-rb", 12.233333333333333),
                                  ("red-lw", 13.925)] {
            let player = try XCTUnwrap(scenario.player(id: playerID))
            let rig = try ReplayAthleteFactory.make(for: player, lod: .far)
            let stage = Entity()
            stage.addChild(rig.root)
            let authored = pose(for: player, scenario: scenario, time: time)
            ReplayAthleteMotion.apply(authored, to: rig.joints)
            // These measured fixtures already have both far soles clear.
            // The check is geometric, not an invented physiological limit.
            XCTAssertGreaterThan(try minimumY(in: rig.root, relativeTo: stage), 0.04)
            try assertAuthoredPose(authored, rig: rig.root, allowsVerticalLift: false)
        }
        let player = try XCTUnwrap(scenario.player(id: "red-lw"))
        let rig = try ReplayAthleteFactory.make(for: player, lod: .far)
        let stage = Entity()
        stage.addChild(rig.root)
        let lifted = raised(pose(for: player, scenario: scenario, time: 14.083333333333334), by: 0.30)
        ReplayAthleteMotion.apply(lifted, to: rig.joints)
        XCTAssertGreaterThan(try minimumY(in: rig.root, relativeTo: stage), 0.15)
        try assertAuthoredPose(lifted, rig: rig.root, allowsVerticalLift: false)
    }

    func testFarSceneGeometryRepeatsExactlyAfterReverseSeekAndViewChanges() throws {
        let scenario = try XCTUnwrap(DemoScenarios.scenario(for: .squadReplay))
        let root = PitchSceneFactory.makeMatchRoot(for: scenario)
        let time = 14.083333333333334
        update(root, scenario: scenario, time: time, view: .tacticalTable)
        let (player, marker) = try farMarker(in: root, playerID: "red-lw")
        let expectedPoints = try legPoints(in: marker, relativeTo: root)
        let expectedPlayer = player.transform
        let expectedBody = try XCTUnwrap(marker.findEntity(named: "body-root")).transform
        for (otherTime, view) in [(32.0, ReplayViewMode.firstPerson), (7.0, .touchline), (0, .tacticalTable),
                                  (time, .tacticalTable), (time, .tacticalTable)] {
            update(root, scenario: scenario, time: otherTime, view: view)
        }
        XCTAssertEqual(try legPoints(in: marker, relativeTo: root), expectedPoints)
        XCTAssertEqual(player.transform, expectedPlayer)
        XCTAssertEqual(try XCTUnwrap(marker.findEntity(named: "body-root")).transform, expectedBody)
        XCTAssertEqual(PitchSceneFactory.proceduralAthleteBindingCacheDiagnostics(for: root).hierarchyResolutions, 0,
                       "Actual scene playback must retain its setup-time joint bindings")
    }

    func testFarSupportIsBoundedAndPreparedOnceWithoutPlaybackMeshReads() throws {
        let scenario = try XCTUnwrap(DemoScenarios.scenario(for: .squadReplay))
        let player = try XCTUnwrap(scenario.player(id: "navy-rb"))
        ReplayFarAthleteFloorSupport.resetDiagnosticsForTesting()
        for lod in [ReplayAthleteLOD.near, .mid] {
            let rig = try ReplayAthleteFactory.make(for: player, lod: lod)
            XCTAssertNil(rig.joints.farFloorSupport)
        }
        XCTAssertEqual(ReplayFarAthleteFloorSupport.preparationCount, 0)
        XCTAssertEqual(ReplayFarAthleteFloorSupport.sourceVertexReadCount, 0)
        let far = try ReplayAthleteFactory.make(for: player, lod: .far)
        var geometryReport: [[String: Any]] = []
        var uniqueSourcePoints = 0
        for (joint, name) in [(ReplayAthleteJoint.leftHip, "left-leg"), (.rightHip, "right-leg")] {
            let hip = far.joints[joint]
            let model = try XCTUnwrap(hip.children.first { $0.name == name } as? ModelEntity)
            let component = try XCTUnwrap(model.model)
            var unique: [SIMD3<Float>] = []
            for mesh in component.mesh.contents.models {
                for part in mesh.parts {
                    let points = Array(part.positions.elements)
                    for point in points where !unique.contains(point) { unique.append(point) }
                    geometryReport.append(["leg": name, "parentIdentity": model.parent === hip,
                                           "bufferCount": part.positions.count, "elementCount": points.count,
                                           "uniqueCount": unique.count,
                                           "finite": points.allSatisfy { $0.x.isFinite && $0.y.isFinite && $0.z.isFinite },
                                           "modelTranslation": [model.position.x, model.position.y, model.position.z],
                                           "modelScale": [model.scale.x, model.scale.y, model.scale.z]])
                }
            }
            uniqueSourcePoints += unique.count
        }
        try attach(geometryReport, named: "ReplayXI-FarGround89-SetupGeometry.json")
        let support = try XCTUnwrap(far.joints.farFloorSupport)
        XCTAssertGreaterThan(support.pointCount, 0)
        XCTAssertEqual(support.pointCount, uniqueSourcePoints,
                       "The factory's invertible static transforms must not collapse support geometry")
        XCTAssertLessThanOrEqual(support.pointCount, ReplayFarAthleteFloorSupport.maximumPointCount)
        XCTAssertEqual(ReplayFarAthleteFloorSupport.preparationCount, 1)
        let root = PitchSceneFactory.makeMatchRoot(for: scenario)
        let prepared = ReplayFarAthleteFloorSupport.preparationCount
        let sourceReads = ReplayFarAthleteFloorSupport.sourceVertexReadCount
        let queries = ReplayFarAthleteFloorSupport.queryCount
        XCTAssertGreaterThan(prepared, 1)
        for view in views {
            for time in [0.0, 6.95, 11.691666666666666, 14.083333333333334, 17.5, 32, 0] {
                update(root, scenario: scenario, time: time, view: view)
            }
        }
        XCTAssertEqual(ReplayFarAthleteFloorSupport.preparationCount, prepared)
        XCTAssertEqual(ReplayFarAthleteFloorSupport.sourceVertexReadCount, sourceReads,
                       "Frame updates must use immutable support data, not read mesh vertices")
        XCTAssertGreaterThan(ReplayFarAthleteFloorSupport.queryCount, queries)
        try attach([["pointsPerFarRig": support.pointCount, "preparedIncludingStandaloneRig": prepared,
                     "setupSourceReads": sourceReads, "playbackSourceReads": 0,
                     "playbackQueries": ReplayFarAthleteFloorSupport.queryCount - queries]],
                   named: "ReplayXI-FarGround89-Cache.json")
    }

    func testCachedSupportMatchesWholeSilhouetteUnderCurrentHipTransforms() throws {
        let scenario = try XCTUnwrap(DemoScenarios.scenario(for: .squadReplay))
        let player = try XCTUnwrap(scenario.player(id: "red-lw"))
        let rig = try ReplayAthleteFactory.make(for: player, lod: .far)
        // Static mesh-local transforms are captured at preparation, not assumed
        // to be identity. Production leaves these transforms fixed thereafter.
        let left = try XCTUnwrap(rig.root.findEntity(named: "left-leg"))
        let right = try XCTUnwrap(rig.root.findEntity(named: "right-leg"))
        left.position = [0.013, -0.024, 0.009]
        left.scale = [0.96, 1.02, 1.03]
        right.orientation = simd_quatf(angle: 0.08, axis: [0, 0, 1])
        let support = try XCTUnwrap(ReplayFarAthleteFloorSupport(
            leftHip: rig.joints[.leftHip], rightHip: rig.joints[.rightHip]))
        let sourceReads = ReplayFarAthleteFloorSupport.sourceVertexReadCount
        var report: [[String: Any]] = []
        for (index, angle) in [Float(0), 0.7, -.pi / 2, .pi / 2, .pi, -.pi].enumerated() {
            rig.joints[.bodyRoot].position = [0.2, Float(index) * 0.03, -0.07]
            rig.joints[.bodyRoot].orientation = simd_quatf(angle: angle * 0.17, axis: [0, 0, 1])
            rig.joints[.hips].orientation = simd_quatf(angle: angle * 0.13, axis: [0, 1, 0])
            rig.joints[.leftHip].orientation = simd_quatf(angle: angle, axis: [1, 0, 0])
            rig.joints[.rightHip].orientation = simd_quatf(angle: -angle * 0.8, axis: [0, 0, 1])
            let measured = try minimumY(in: rig.root, relativeTo: rig.root)
            let cached = support.minimumY(relativeTo: rig.root)
            XCTAssertTrue(cached.isFinite)
            XCTAssertEqual(cached, measured, accuracy: 0.000001,
                           "Use whole-mesh support even when a sole is no longer its lowest point")
            XCTAssertEqual(support.upwardCorrection(relativeTo: rig.root), max(-measured, 0), accuracy: 0.000001)
            report.append(["angle": angle, "measuredMinimumY": measured, "cachedMinimumY": cached])
        }
        XCTAssertEqual(ReplayFarAthleteFloorSupport.sourceVertexReadCount, sourceReads)
        XCTAssertLessThanOrEqual(support.pointCount, ReplayFarAthleteFloorSupport.maximumPointCount)
        try attach(report, named: "ReplayXI-FarGround89-Support.json")
    }

    func testUnsupportedFarGeometryDoesNotCreateAnUnboundedSupportCache() throws {
        let leftHip = Entity(), rightHip = Entity()
        let rigRoot = Entity(), body = Entity(), hips = Entity()
        rigRoot.addChild(body)
        body.addChild(hips)
        hips.addChild(leftHip)
        hips.addChild(rightHip)
        XCTAssertNil(ReplayFarAthleteFloorSupport(leftHip: leftHip, rightHip: rightHip))
        let sphere = ModelEntity(mesh: .generateSphere(radius: 0.1))
        sphere.name = "left-leg"
        leftHip.addChild(sphere)
        let vertexCount = try XCTUnwrap(sphere.model).mesh.contents.models.reduce(0) { count, model in
            count + model.parts.reduce(0) { $0 + $1.positions.count }
        }
        XCTAssertGreaterThan(vertexCount, ReplayFarAthleteFloorSupport.maximumPointCount)
        let sourceReads = ReplayFarAthleteFloorSupport.sourceVertexReadCount
        XCTAssertNil(ReplayFarAthleteFloorSupport(leftHip: leftHip, rightHip: rightHip))
        XCTAssertEqual(ReplayFarAthleteFloorSupport.sourceVertexReadCount, sourceReads,
                       "Reject an oversized part before copying its vertex buffer")

        let scenario = try XCTUnwrap(DemoScenarios.scenario(for: .squadReplay))
        let rig = try ReplayAthleteFactory.make(for: XCTUnwrap(scenario.players.first), lod: .far)
        let leg = try XCTUnwrap(rig.root.findEntity(named: "left-leg"))
        leg.position.x = 6
        XCTAssertNil(ReplayFarAthleteFloorSupport(leftHip: rig.joints[.leftHip], rightHip: rig.joints[.rightHip]),
                     "Unexpected metre-scale local geometry must fail softly at setup")
    }

    func testVisibleFarCorrectionAddsNoStepBeyondRawSupportMotionAt120Hz() throws {
        let scenario = try XCTUnwrap(DemoScenarios.scenario(for: .squadReplay))
        let root = PitchSceneFactory.makeMatchRoot(for: scenario)
        var report: [[String: Any]] = []
        for (playerID, start) in [("navy-rb", 11.55), ("red-lw", 13.8)] {
            let player = try XCTUnwrap(scenario.player(id: playerID))
            let rawRig = try ReplayAthleteFactory.make(for: player, lod: .far)
            var previous: (minimum: Float, lift: Float, authoredY: Float, presentedY: Float)?
            var hadLift = false
            var hadClearPose = false
            for frame in 0...60 {
                let time = start + Double(frame) / 120
                let authored = pose(for: player, scenario: scenario, time: time)
                ReplayAthleteMotion.apply(authored, to: rawRig.joints)
                // A separate test-only rig restores the raw authored translation
                // to measure the old floor error. The visible graph is untouched.
                rawRig.joints[.bodyRoot].position = authored.bodyPosition
                let rawMinimum = try minimumY(in: rawRig.root, relativeTo: rawRig.root)
                update(root, scenario: scenario, time: time, view: .firstPerson)
                let (_, marker) = try farMarker(in: root, playerID: playerID)
                let presentedY = try XCTUnwrap(marker.findEntity(named: "body-root")).position.y
                let lift = presentedY - authored.bodyPosition.y
                let expectedLift = max(-rawMinimum, 0)
                XCTAssertEqual(lift, expectedLift, accuracy: 0.00001)
                try assertAuthoredPose(authored, rig: marker, allowsVerticalLift: true)
                let actualMinimum = try minimumY(in: marker, relativeTo: root)
                XCTAssertGreaterThanOrEqual(actualMinimum, -floorTolerance)
                if expectedLift > 0 { hadLift = true } else {
                    hadClearPose = true
                    XCTAssertEqual(presentedY, authored.bodyPosition.y)
                }
                if let previous {
                    // max(-height, 0) is 1-Lipschitz: the guard cannot introduce
                    // a correction jump larger than the measured raw support
                    // change. This is a math bound, not a guessed gait limit.
                    let rawChange = abs(rawMinimum - previous.minimum)
                    XCTAssertLessThanOrEqual(abs(lift - previous.lift), rawChange + 0.00002)
                    XCTAssertLessThanOrEqual(abs(presentedY - previous.presentedY),
                                            abs(authored.bodyPosition.y - previous.authoredY) + rawChange + 0.00002)
                }
                report.append(["playerID": playerID, "time": time, "rawMinimumRigY": rawMinimum,
                               "lift": lift, "authoredBodyY": authored.bodyPosition.y,
                               "presentedBodyY": presentedY, "minimumPitchLocalY": actualMinimum])
                previous = (rawMinimum, lift, authored.bodyPosition.y, presentedY)
            }
            XCTAssertTrue(hadLift, "The short window must exercise a genuine floor correction")
            XCTAssertTrue(hadClearPose, "The short window must also exercise its zero-lift join")
        }
        try attach(report, named: "ReplayXI-FarGround89-Continuity120Hz.json")
    }

    func testSupportMinimumIsExactlyIndependentOfWorldAncestors() throws {
        let scenario = try XCTUnwrap(DemoScenarios.scenario(for: .squadReplay))
        let player = try XCTUnwrap(scenario.player(id: "red-lw"))
        let rig = try ReplayAthleteFactory.make(for: player, lod: .far)
        let support = try XCTUnwrap(rig.joints.farFloorSupport)
        let stage = Entity()
        stage.addChild(rig.root)
        let authored = pose(for: player, scenario: scenario, time: 14.083333333333334)
        ReplayAthleteMotion.apply(authored, to: rig.joints)
        rig.joints[.bodyRoot].position = authored.bodyPosition
        let bodyTransform = rig.joints[.bodyRoot].transform
        let expected = support.minimumY(relativeTo: rig.root)
        var report: [[String: Any]] = []
        let presentations: [(Float, simd_quatf, SIMD3<Float>)] = [
            (0.0255, simd_quatf(angle: 0.22, axis: [1, 0, 0]), [0, 0.92, -3.15]),
            (0.06, simd_quatf(angle: .pi / 2, axis: [0, 1, 0]), [0, 0.02, -4.1]),
            (1, simd_quatf(angle: -1.1, axis: [0, 1, 0]), [-29, 0, -21]),
            (1, simd_quatf(real: 1, imag: .zero), .zero),
        ]
        for (scale, orientation, position) in presentations {
            stage.scale = SIMD3(repeating: scale)
            stage.orientation = orientation
            stage.position = position
            let measured = support.minimumY(relativeTo: rig.root)
            XCTAssertEqual(measured, expected,
                           "A rig-local support minimum must not depend on the prior world/view transform")
            XCTAssertEqual(rig.joints[.bodyRoot].transform, bodyTransform)
            report.append(["worldScale": scale, "worldPosition": [position.x, position.y, position.z],
                           "minimumRigY": measured, "baselineMinimumRigY": expected,
                           "difference": measured - expected])
        }
        try attach(report, named: "ReplayXI-FarGround89-WorldIndependence.json")
    }
}
