import Foundation
import RealityKit
import XCTest
@testable import ReplayXI

@MainActor
final class ReplayXITests: XCTestCase {
    func testPlaybackWorkspaceCapturesPoseOnceWithoutFollowingHead() {
        let anchor = PlaybackAttachmentPlacement.makeAnchor(revision: 0)
        XCTAssertEqual(anchor.anchoring.trackingMode, .once)
        XCTAssertEqual(anchor.name, PlaybackAttachmentPlacement.anchorName)
        XCTAssertEqual(Set(PlaybackAttachmentPlacement.attachmentIDs).count, 5)
        XCTAssertTrue(PlaybackAttachmentPlacement.attachmentIDs.contains("coach-console"))
        XCTAssertTrue(PlaybackAttachmentPlacement.attachmentIDs.contains("playback-view-hud"))
        XCTAssertFalse(PlaybackAttachmentPlacement.needsRecenter(anchor, revision: 0))
    }

    func testLocalAnnotationVisibilityRoundTripRestoresMarksWithoutForcingInputAffordances() {
        let root = Entity()
        let marks = Entity()
        marks.name = "marks-root"
        let selection = Entity()
        selection.name = AnnotationSceneAffordance.selectionRootName
        let draft = Entity()
        draft.name = "annotation-draft-root"
        let surface = Entity()
        surface.name = "annotation-surface"
        [marks, selection, draft, surface].forEach { root.addChild($0) }

        PlaybackLocalOverlayVisibility.apply(
            to: root,
            showsAnnotations: false,
            canOverrideMarksRoot: true
        )
        XCTAssertFalse(marks.isEnabled)
        XCTAssertFalse(selection.isEnabled)
        XCTAssertFalse(draft.isEnabled)
        XCTAssertFalse(surface.isEnabled)

        // Mirror the scene update that precedes the local gate: a new draw is
        // active, while no annotation is selected.
        selection.isEnabled = false
        draft.isEnabled = true
        surface.isEnabled = true
        PlaybackLocalOverlayVisibility.apply(
            to: root,
            showsAnnotations: true,
            canOverrideMarksRoot: true
        )

        XCTAssertTrue(marks.isEnabled)
        XCTAssertFalse(selection.isEnabled)
        XCTAssertTrue(draft.isEnabled)
        XCTAssertTrue(surface.isEnabled)
    }

    func testLocalAnnotationVisibilityPreservesShapeOwnedMarksState() {
        let root = Entity()
        let marks = Entity()
        marks.name = "marks-root"
        marks.isEnabled = false
        let selection = Entity()
        selection.name = AnnotationSceneAffordance.selectionRootName
        selection.isEnabled = true
        let draft = Entity()
        draft.name = "annotation-draft-root"
        draft.isEnabled = true
        let surface = Entity()
        surface.name = "annotation-surface"
        surface.isEnabled = true
        [marks, selection, draft, surface].forEach { root.addChild($0) }

        PlaybackLocalOverlayVisibility.apply(
            to: root,
            showsAnnotations: false,
            canOverrideMarksRoot: false
        )

        XCTAssertFalse(marks.isEnabled)
        XCTAssertTrue(selection.isEnabled)
        XCTAssertTrue(draft.isEnabled)
        XCTAssertTrue(surface.isEnabled)
    }

    func testImmersiveInlinePanelsToggleExclusively() {
        let markID = UUID(uuidString: "AAAAAAAA-BBBB-4CCC-8DDD-EEEEEEEEEEEE")!

        XCTAssertEqual(
            PlaybackInlinePanel.toggled(current: nil, candidate: .settings),
            .settings
        )
        XCTAssertNil(
            PlaybackInlinePanel.toggled(current: .settings, candidate: .settings),
            "Pinching an already-open shelf should close it."
        )
        XCTAssertEqual(
            PlaybackInlinePanel.toggled(
                current: .settings,
                candidate: .annotationDuration(markID)
            ),
            .annotationDuration(markID),
            "Opening a second shelf must replace the first rather than stack a presentation."
        )
    }

    func testAnnotationInlinePanelsRemainBoundToTheirSelectedMark() {
        let selectedID = UUID(uuidString: "AAAAAAAA-BBBB-4CCC-8DDD-000000000001")!
        let otherID = UUID(uuidString: "AAAAAAAA-BBBB-4CCC-8DDD-000000000002")!
        let annotationPanels: [PlaybackInlinePanel] = [
            .annotationDuration(selectedID),
            .annotationGeometry(selectedID),
            .annotationLabel(selectedID),
            .annotationTracking(selectedID),
        ]

        XCTAssertTrue(PlaybackInlinePanel.settings.isValid(for: nil))
        XCTAssertTrue(PlaybackInlinePanel.annotationEdit.isValid(for: nil))
        for panel in annotationPanels {
            XCTAssertTrue(panel.isValid(for: selectedID))
            XCTAssertFalse(panel.isValid(for: otherID))
            XCTAssertFalse(panel.isValid(for: nil))
        }
    }

    func testImmersiveControlDeckAvoidsUnsupportedPresentationControls() throws {
        let projectRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let sourceURL = projectRoot
            .appendingPathComponent("ReplayXI")
            .appendingPathComponent("Immersive")
            .appendingPathComponent("FootballImmersiveView.swift")
        let source = try String(contentsOf: sourceURL, encoding: .utf8)
        let unsupportedPatterns = [
            "Menu {",
            ".sheet(",
            ".popover(",
            ".alert(",
            ".confirmationDialog(",
            ".contextMenu(",
            ".pickerStyle(.menu)",
        ]

        for pattern in unsupportedPatterns {
            XCTAssertFalse(
                source.contains(pattern),
                "Immersive attachments must use in-deck controls, not \(pattern)."
            )
        }
    }

    func testDemoCatalogueContainsExactlySixOrderedScenarios() {
        let scenarios = DemoScenarios.all

        XCTAssertEqual(scenarios.count, 6)
        XCTAssertEqual(scenarios.map(\.kind), ExperienceKind.allCases)
        XCTAssertEqual(
            scenarios.map(\.id),
            [
                "eleven-eyes",
                "everyone-with-seven",
                "triangle-lock",
                "lane-lens",
                "four-minds",
                "real-world-match-replay",
            ]
        )
        XCTAssertEqual(Set(scenarios.map(\.id)).count, scenarios.count)
        XCTAssertEqual(scenarios.first?.defaultViewMode, .tacticalTable)
    }

    func testEveryScenarioUsesTheCanonicalTwentyTwoPlayerThirtyTwoSecondReplay() throws {
        let scenarios = DemoScenarios.all
        let reference = try XCTUnwrap(scenarios.first)

        XCTAssertEqual(reference.players.count, 22)
        XCTAssertEqual(reference.homePlayers.count, 11)
        XCTAssertEqual(reference.awayPlayers.count, 11)
        XCTAssertEqual(Set(reference.players.map(\.id)).count, 22)

        for scenario in scenarios {
            XCTAssertEqual(scenario.duration, 32, accuracy: 0.000_1, scenario.id)
            XCTAssertEqual(scenario.players, reference.players, scenario.id)
            XCTAssertEqual(scenario.ball, reference.ball, scenario.id)
            XCTAssertEqual(scenario.players.count, 22, scenario.id)
            XCTAssertEqual(scenario.homePlayers.count, 11, scenario.id)
            XCTAssertEqual(scenario.awayPlayers.count, 11, scenario.id)

            for track in scenario.players {
                XCTAssertEqual(track.keyframes.first?.time, 0, track.id)
                XCTAssertEqual(track.keyframes.last?.time, 32, track.id)
                XCTAssertEqual(
                    track.keyframes.map(\.time),
                    track.keyframes.map(\.time).sorted(),
                    "Keyframes must be chronological for \(track.id)"
                )
            }

            XCTAssertEqual(scenario.ball.keyframes.first?.time, 0, scenario.id)
            XCTAssertEqual(scenario.ball.keyframes.last?.time, 32, scenario.id)
            XCTAssertEqual(
                scenario.ball.keyframes.map(\.time),
                scenario.ball.keyframes.map(\.time).sorted(),
                "Ball keyframes must be chronological for \(scenario.id)"
            )
        }
    }

    func testScenarioAndNestedIdentifiersAreUnique() {
        let scenarios = DemoScenarios.all

        XCTAssertEqual(Set(scenarios.map(\.id)).count, scenarios.count)

        for scenario in scenarios {
            XCTAssertEqual(
                Set(scenario.players.map(\.id)).count,
                scenario.players.count,
                "Duplicate player ID in \(scenario.id)"
            )
            XCTAssertEqual(
                Set(scenario.featuredPerspectiveIDs).count,
                scenario.featuredPerspectiveIDs.count,
                "Duplicate featured perspective in \(scenario.id)"
            )
            XCTAssertEqual(
                Set(scenario.moments.map(\.id)).count,
                scenario.moments.count,
                "Duplicate cue ID in \(scenario.id)"
            )
            XCTAssertEqual(
                Set(scenario.coachMarks.map(\.id)).count,
                scenario.coachMarks.count,
                "Duplicate coach-mark ID in \(scenario.id)"
            )
            XCTAssertEqual(
                Set(scenario.formationTargets.map(\.id)).count,
                scenario.formationTargets.count,
                "Duplicate formation-target ID in \(scenario.id)"
            )
        }

        let cueIDs = scenarios.flatMap { $0.moments.map(\.id) }
        let markIDs = scenarios.flatMap { $0.coachMarks.map(\.id) }
        let targetIDs = scenarios.flatMap { $0.formationTargets.map(\.id) }
        XCTAssertEqual(Set(cueIDs).count, cueIDs.count)
        XCTAssertEqual(Set(markIDs).count, markIDs.count)
        XCTAssertEqual(Set(targetIDs).count, targetIDs.count)
    }

    func testEveryFeaturedPerspectiveAndFormationTargetResolvesToAPlayer() {
        for scenario in DemoScenarios.all {
            let playerIDs = Set(scenario.players.map(\.id))

            XCTAssertTrue(playerIDs.contains(scenario.defaultPerspectiveID), scenario.id)
            XCTAssertFalse(scenario.featuredPerspectiveIDs.isEmpty, scenario.id)

            for featuredID in scenario.featuredPerspectiveIDs {
                XCTAssertTrue(
                    playerIDs.contains(featuredID),
                    "Unknown featured perspective \(featuredID) in \(scenario.id)"
                )
                XCTAssertNotNil(scenario.player(id: featuredID))
            }

            for target in scenario.formationTargets {
                XCTAssertTrue(
                    playerIDs.contains(target.playerID),
                    "Unknown target player \(target.playerID) in \(scenario.id)"
                )
                XCTAssertGreaterThan(target.toleranceMetres, 0)
            }

            XCTAssertEqual(
                scenario.moments.map(\.time),
                scenario.moments.map(\.time).sorted(),
                "Cue moments must be chronological in \(scenario.id)"
            )
            XCTAssertTrue(scenario.moments.allSatisfy { (0...scenario.duration).contains($0.time) })
            XCTAssertTrue(scenario.coachMarks.allSatisfy { (0...scenario.duration).contains($0.revealTime) })
        }
    }

    func testActiveCueIsChronologicalEvenWhenInputOrderIsReversed() throws {
        let base = try XCTUnwrap(DemoScenarios.all.first)
        let reversed = ReplayScenario(
            id: base.id,
            kind: base.kind,
            title: base.title,
            strapline: base.strapline,
            matchContext: base.matchContext,
            objective: base.objective,
            coachPrompt: base.coachPrompt,
            proofPoint: base.proofPoint,
            duration: base.duration,
            defaultViewMode: base.defaultViewMode,
            defaultPerspectiveID: base.defaultPerspectiveID,
            featuredPerspectiveIDs: base.featuredPerspectiveIDs,
            players: base.players,
            ball: base.ball,
            moments: Array(base.moments.reversed()),
            coachMarks: base.coachMarks,
            formationTargets: base.formationTargets
        )

        for moment in base.moments {
            XCTAssertEqual(reversed.activeMoment(at: moment.time)?.id, moment.id)
        }
        XCTAssertNil(reversed.activeMoment(at: -.infinity))
        XCTAssertNil(reversed.activeMoment(at: .nan))
    }

    func testPlayerAndBallInterpolationClampAtTheTrackEdges() {
        let track = PlayerTrack(
            id: "test-player",
            displayName: "Test Player",
            role: "Right winger",
            shirtNumber: 7,
            team: .home,
            isGoalkeeper: false,
            keyframes: [
                MotionKeyframe(
                    time: 0,
                    position: PitchPoint(x: 0, z: -10),
                    facingDegrees: 350
                ),
                MotionKeyframe(
                    time: 10,
                    position: PitchPoint(x: 20, z: 10),
                    facingDegrees: 10
                ),
            ]
        )
        let ball = BallTrack(keyframes: [
            BallKeyframe(time: 0, position: PitchPoint(x: -4, z: 2), height: 0.1),
            BallKeyframe(time: 10, position: PitchPoint(x: 6, z: 12), height: 1.1),
        ])

        let beforeStart = track.pose(at: -3)
        XCTAssertEqual(beforeStart.position, PitchPoint(x: 0, z: -10))
        XCTAssertEqual(beforeStart.facingDegrees, 350)

        let midpoint = track.pose(at: 5)
        XCTAssertEqual(midpoint.position.x, 10, accuracy: 0.000_1)
        XCTAssertEqual(midpoint.position.z, 0, accuracy: 0.000_1)
        XCTAssertEqual(midpoint.facingDegrees, 360, accuracy: 0.000_1)

        let afterEnd = track.pose(at: 14)
        XCTAssertEqual(afterEnd.position, PitchPoint(x: 20, z: 10))
        XCTAssertEqual(afterEnd.facingDegrees, 10)

        let ballMidpoint = ball.pose(at: 5)
        XCTAssertEqual(ballMidpoint.position.x, 1, accuracy: 0.000_1)
        XCTAssertEqual(ballMidpoint.position.z, 7, accuracy: 0.000_1)
        XCTAssertEqual(ballMidpoint.height, 0.6, accuracy: 0.000_1)
        XCTAssertEqual(ball.pose(at: -1), BallPose(position: PitchPoint(x: -4, z: 2), height: 0.1))
        XCTAssertEqual(ball.pose(at: 11), BallPose(position: PitchPoint(x: 6, z: 12), height: 1.1))

        let origin = PitchPoint(x: 1, z: 2)
        let destination = PitchPoint(x: 9, z: 10)
        XCTAssertEqual(origin.interpolated(to: destination, fraction: -2), origin)
        XCTAssertEqual(origin.interpolated(to: destination, fraction: 3), destination)
    }

    func testAngleInterpolationTakesTheShortestWrappedRoute() {
        XCTAssertEqual(
            ReplayGeometry.interpolateAngle(from: 350, to: 10, fraction: 0.5),
            360,
            accuracy: 0.000_1
        )
        XCTAssertEqual(
            ReplayGeometry.interpolateAngle(from: 10, to: 350, fraction: 0.5),
            0,
            accuracy: 0.000_1
        )
        XCTAssertEqual(
            ReplayGeometry.interpolateAngle(from: 90, to: 180, fraction: -1),
            90,
            accuracy: 0.000_1
        )
        XCTAssertEqual(
            ReplayGeometry.interpolateAngle(from: 90, to: 180, fraction: 2),
            180,
            accuracy: 0.000_1
        )
    }

    func testLaneGeometryUsesTheBoundedPassSegment() {
        let start = PitchPoint(x: 0, z: 0)
        let end = PitchPoint(x: 10, z: 0)

        XCTAssertEqual(
            ReplayGeometry.distanceFromSegment(
                point: PitchPoint(x: 5, z: 3),
                start: start,
                end: end
            ),
            3,
            accuracy: 0.000_1
        )
        XCTAssertEqual(
            ReplayGeometry.distanceFromSegment(
                point: PitchPoint(x: -2, z: 4),
                start: start,
                end: end
            ),
            hypot(2, 4),
            accuracy: 0.000_1
        )
        XCTAssertEqual(
            ReplayGeometry.distanceFromSegment(
                point: PitchPoint(x: 4, z: 3),
                start: start,
                end: start
            ),
            5,
            accuracy: 0.000_1
        )

        let clearance = ReplayGeometry.laneClearance(
            from: start,
            to: end,
            defenders: [PitchPoint(x: 5, z: 4), PitchPoint(x: 8, z: -2)]
        )
        XCTAssertEqual(clearance, 2, accuracy: 0.000_1)
        XCTAssertTrue(ReplayGeometry.laneClearance(from: start, to: end, defenders: []).isInfinite)

        XCTAssertEqual(
            ReplayGeometry.distance(PitchPoint(x: 0, z: 0), PitchPoint(x: 3, z: 4)),
            5,
            accuracy: 0.000_1
        )
        XCTAssertEqual(
            ReplayGeometry.angle(
                at: .zero,
                first: PitchPoint(x: 1, z: 0),
                second: PitchPoint(x: 0, z: 1)
            ),
            90,
            accuracy: 0.000_1
        )
    }

    func testReplayStoreClampsSeekRateAndUsesFullPlaybackElapsedTime() {
        let store = ReplayStore()
        let duration = store.selectedScenario.duration

        store.seek(to: -10, broadcast: false)
        XCTAssertEqual(store.playhead, 0)
        store.seek(to: duration + 10, broadcast: false)
        XCTAssertEqual(store.playhead, duration)
        store.skip(by: -100, broadcast: false)
        XCTAssertEqual(store.playhead, 0)

        store.setPlaybackRate(0.01, broadcast: false)
        XCTAssertEqual(store.playbackRate, 0.25)
        store.setPlaybackRate(9, broadcast: false)
        XCTAssertEqual(store.playbackRate, 4)
        XCTAssertEqual(ReplayStore.availablePlaybackRates, [0.25, 0.5, 0.75, 1, 1.5, 2, 4])
        store.setPlaybackRate(1, broadcast: false)

        store.setPlaying(true, broadcast: false)
        store.advance(by: 0.5)
        XCTAssertEqual(store.playhead, 0.5, accuracy: 0.000_1)

        let unchangedPlayhead = store.playhead
        store.advance(by: -1)
        store.advance(by: .infinity)
        store.advance(by: .nan)
        XCTAssertEqual(store.playhead, unchangedPlayhead, accuracy: 0.000_1)

        store.seek(to: duration - 0.05, broadcast: false)
        store.advance(by: 0.1)
        XCTAssertEqual(store.playhead, duration)
        XCTAssertFalse(store.isPlaying)

        store.seek(to: duration, broadcast: false)
        store.setPlaying(false, broadcast: false)
        store.togglePlayback(broadcast: false)
        XCTAssertEqual(store.playhead, 0)
        XCTAssertTrue(store.isPlaying)
    }

    func testReplayStoreRejectsNonFiniteLocalTimelineInputs() {
        let store = ReplayStore()
        store.seek(to: 7.5, broadcast: false)
        store.setPlaybackRate(0.75, broadcast: false)
        var broadcastCount = 0
        store.onBroadcastSnapshot = { _ in broadcastCount += 1 }

        for invalidTime in [Double.nan, .infinity, -.infinity] {
            store.seek(to: invalidTime)
        }
        store.skip(by: .nan)
        for invalidRate in [Double.nan, .infinity, -.infinity] {
            store.setPlaybackRate(invalidRate)
        }

        XCTAssertEqual(store.playhead, 7.5, accuracy: 0.000_1)
        XCTAssertEqual(store.playbackRate, 0.75, accuracy: 0.000_1)
        XCTAssertTrue(store.progress.isFinite)
        XCTAssertEqual(broadcastCount, 0)
    }

    func testOfflinePlayerHasSoloControlsAndJoinedPlayerUsesCoachFollowRules() {
        let store = ReplayStore()
        store.localRole = .player

        store.togglePlayback()
        XCTAssertTrue(store.isPlaying)
        XCTAssertFalse(store.isLocallyPaused)

        let nextScenarioID = store.scenarios[1].id
        store.selectAdjacentScenario(by: 1)
        XCTAssertEqual(store.selectedScenarioID, nextScenarioID)

        let localLensID = store.selectedScenario.players[1].id
        store.setViewMode(.tacticalTable)
        store.setLocalPerspective(localLensID)
        XCTAssertEqual(store.viewMode, .tacticalTable)
        XCTAssertEqual(store.localPerspectiveID, localLensID)
        XCTAssertTrue(store.followsCoach)
        XCTAssertFalse(store.isLocallyPaused)

        store.setFollowingCoach(false)
        XCTAssertTrue(store.followsCoach)
        XCTAssertFalse(store.isLocallyPaused)

        store.setCollaborationActive(true)
        store.setViewMode(.firstPerson)
        XCTAssertFalse(store.followsCoach)
        XCTAssertTrue(store.isLocallyPaused)

        store.setFollowingCoach(true)
        XCTAssertTrue(store.followsCoach)
        XCTAssertFalse(store.isLocallyPaused)

        store.selectAdjacentScenario(by: 1)
        XCTAssertEqual(store.selectedScenarioID, nextScenarioID)

        store.togglePlayback()
        XCTAssertFalse(store.followsCoach)
        XCTAssertTrue(store.isLocallyPaused)
        XCTAssertFalse(store.isPlaying)
    }

    func testAllTwentyTwoPlayerLensesCanBeTraversedAndWrap() throws {
        let store = ReplayStore()
        let players = store.selectedScenario.players
        XCTAssertEqual(players.count, 22)

        store.setLocalPerspective(players[0].id)
        store.selectAdjacentPerspective(by: -1)
        XCTAssertEqual(store.localPerspectiveID, players[21].id)
        XCTAssertEqual(store.activePerspectiveID, players[21].id)

        store.selectAdjacentPerspective(by: 1)
        XCTAssertEqual(store.localPerspectiveID, players[0].id)

        let firstOpponent = try XCTUnwrap(store.selectedScenario.awayPlayers.first)
        store.setLocalPerspective(firstOpponent.id)
        XCTAssertEqual(store.activePerspective?.team, .away)
        XCTAssertEqual(store.activePerspectiveID, firstOpponent.id)
    }

    func testPlayerLensFollowsPlayerTranslationWithoutForcingRecordedRotation() throws {
        let scenario = try XCTUnwrap(DemoScenarios.scenario(for: .squadReplay))
        let root = PitchSceneFactory.makeMatchRoot(for: scenario)
        let player = try XCTUnwrap(scenario.player(id: "navy-rw"))

        PitchSceneFactory.update(
            root: root,
            scenario: scenario,
            time: 2,
            viewMode: .firstPerson,
            perspectiveID: "navy-rw",
            marks: scenario.coachMarks,
            showsLaneLens: false,
            isDrawing: false,
            positionalOriginTransform: nil
        )
        let initialPosition = root.position
        let initialOrientation = root.orientation.vector
        let initialScale = root.scale
        let initialPose = player.presentationPose(at: 2)
        let fixedPitchRotation = simd_quatf(angle: .pi, axis: [0, 1, 0])
        let expectedInitialPosition = -fixedPitchRotation.act(
            SIMD3<Float>(initialPose.position.x, 0, initialPose.position.z)
        )

        XCTAssertTrue(try XCTUnwrap(root.findEntity(named: "player-navy-rw")).isEnabled)
        XCTAssertEqual(initialScale, SIMD3<Float>(repeating: 1))
        XCTAssertEqual(initialPosition.x, expectedInitialPosition.x, accuracy: 0.000_1)
        XCTAssertEqual(initialPosition.y, 0, accuracy: 0.000_1)
        XCTAssertEqual(initialPosition.z, expectedInitialPosition.z, accuracy: 0.000_1)
        let facing = try XCTUnwrap(root.findEntity(named: "recorded-facing"))
        let firstFacingPosition = facing.position
        XCTAssertTrue(facing.isEnabled)
        XCTAssertNil(root.findEntity(named: "player-navy-rw")?.findEntity(named: "recorded-facing"))
        XCTAssertTrue(try XCTUnwrap(root.findEntity(named: "field-surface")).isEnabled)
        XCTAssertNil(root.findEntity(named: "player-navy-rw")?.findEntity(named: "full-rig"))
        XCTAssertFalse(try XCTUnwrap(root.findEntity(named: "selection-halo")).isEnabled)

        PitchSceneFactory.update(
            root: root,
            scenario: scenario,
            time: 19,
            viewMode: .firstPerson,
            perspectiveID: "navy-rw",
            marks: scenario.coachMarks,
            showsLaneLens: false,
            isDrawing: false,
            positionalOriginTransform: nil
        )

        let laterPose = player.presentationPose(at: 19)
        let expectedLaterPosition = -fixedPitchRotation.act(
            SIMD3<Float>(laterPose.position.x, 0, laterPose.position.z)
        )

        XCTAssertNotEqual(laterPose.facingDegrees, initialPose.facingDegrees)
        XCTAssertNotEqual(root.position, initialPosition)
        XCTAssertEqual(root.position.x, expectedLaterPosition.x, accuracy: 0.000_1)
        XCTAssertEqual(root.position.y, 0, accuracy: 0.000_1)
        XCTAssertEqual(root.position.z, expectedLaterPosition.z, accuracy: 0.000_1)
        // The pitch never adopts telemetry yaw/pitch. RealityKit therefore
        // leaves headset orientation entirely under the wearer's control.
        XCTAssertEqual(root.orientation.vector, initialOrientation)
        XCTAssertEqual(root.scale, initialScale)
        XCTAssertTrue(facing.isEnabled)
        XCTAssertNotEqual(facing.position, firstFacingPosition)
        XCTAssertEqual(
            facing.position,
            SIMD3<Float>(
                laterPose.position.x,
                0,
                laterPose.position.z
            )
        )
        let recordedFacingOrientation = simd_quatf(
            angle: laterPose.facingDegrees * .pi / 180,
            axis: [0, 1, 0]
        )
        XCTAssertEqual(facing.orientation.vector, recordedFacingOrientation.vector)

        // The cue remains at the head-mounted origin while its authored
        // direction rotates independently from the viewer's free look.
        let facingWorldPosition = root.orientation.act(facing.position) + root.position
        XCTAssertEqual(facingWorldPosition.x, 0, accuracy: 0.000_1)
        XCTAssertEqual(facingWorldPosition.z, 0, accuracy: 0.000_1)
    }

    func testPlayerLensUsesCappedNearestVisibleRigsAndNeverBuildsTheWearer() throws {
        let scenario = try XCTUnwrap(DemoScenarios.scenario(for: .squadReplay))
        let root = PitchSceneFactory.makeMatchRoot(for: scenario)
        let sampleTime: TimeInterval = 12
        let wearerID = scenario.defaultPerspectiveID
        let wearerPose = try XCTUnwrap(
            scenario.player(id: wearerID)?.presentationPose(at: sampleTime)
        )
        let neighbourDistances: [(id: String, distance: Float)] = scenario.players.compactMap {
            guard $0.id != wearerID else { return nil }
            return (
                id: $0.id,
                distance: ReplayGeometry.distance(
                    wearerPose.position,
                    $0.presentationPose(at: sampleTime).position
                )
            )
        }
        let orderedNeighbours = neighbourDistances.sorted { first, second in
            if first.distance == second.distance { return first.id < second.id }
            return first.distance < second.distance
        }
        let expectedNearestIDs: [String] = Array(
            orderedNeighbours
                .prefix(PitchSceneFactory.firstPersonDetailedRigLimit)
                .map(\.id)
        )
        let expectedNearestSet = Set(expectedNearestIDs)

        PitchSceneFactory.update(
            root: root,
            scenario: scenario,
            time: sampleTime,
            viewMode: .firstPerson,
            perspectiveID: wearerID,
            marks: scenario.coachMarks,
            showsLaneLens: false,
            isDrawing: false,
            positionalOriginTransform: nil
        )

        let wearer = try XCTUnwrap(root.findEntity(named: "player-\(wearerID)"))
        XCTAssertNil(wearer.children.first { $0.name == "full-rig" })
        XCTAssertFalse(
            try XCTUnwrap(wearer.children.first { $0.name == "table-marker" }).isEnabled
        )

        var firstRigByID: [String: Entity] = [:]
        for player in scenario.players {
            let entity = try XCTUnwrap(root.findEntity(named: "player-\(player.id)"))
            let fullRig = entity.children.first { $0.name == "full-rig" }
            let marker = try XCTUnwrap(entity.children.first { $0.name == "table-marker" })
            let expectsDetailed = expectedNearestSet.contains(player.id)

            XCTAssertEqual(fullRig?.isEnabled == true, expectsDetailed, player.id)
            XCTAssertEqual(marker.isEnabled, player.id != wearerID && !expectsDetailed, player.id)
            if let fullRig { firstRigByID[player.id] = fullRig }
        }
        XCTAssertEqual(firstRigByID.count, PitchSceneFactory.firstPersonDetailedRigLimit)
        XCTAssertEqual(Set(firstRigByID.keys), expectedNearestSet)

        PitchSceneFactory.update(
            root: root,
            scenario: scenario,
            time: sampleTime,
            viewMode: .firstPerson,
            perspectiveID: wearerID,
            marks: scenario.coachMarks,
            showsLaneLens: false,
            isDrawing: false,
            positionalOriginTransform: nil
        )
        for (playerID, firstRig) in firstRigByID {
            let repeatedRig = try XCTUnwrap(
                root.findEntity(named: "player-\(playerID)")?.children.first {
                    $0.name == "full-rig"
                }
            )
            XCTAssertTrue(firstRig === repeatedRig, playerID)
        }

        // Promote a previously detailed neighbour to the wearer. Its geometry
        // must be removed, not merely hidden or replaced by another avatar.
        let nextWearerID = try XCTUnwrap(expectedNearestIDs.first)
        PitchSceneFactory.update(
            root: root,
            scenario: scenario,
            time: sampleTime,
            viewMode: .firstPerson,
            perspectiveID: nextWearerID,
            marks: scenario.coachMarks,
            showsLaneLens: false,
            isDrawing: false,
            positionalOriginTransform: nil
        )
        let nextWearer = try XCTUnwrap(root.findEntity(named: "player-\(nextWearerID)"))
        XCTAssertNil(nextWearer.children.first { $0.name == "full-rig" })
        let nextWearerMarker: Entity = try XCTUnwrap(
            nextWearer.children.first { $0.name == "table-marker" }
        )
        XCTAssertFalse(nextWearerMarker.isEnabled)
        let retainedRigCount = scenario.players.filter {
            root.findEntity(named: "player-\($0.id)")?.children.contains {
                $0.name == "full-rig"
            } == true
        }.count
        XCTAssertEqual(retainedRigCount, PitchSceneFactory.firstPersonDetailedRigLimit)
    }

    func testLocomotionIsDeterministicAcrossSeekAndPlaybackRate() throws {
        let scenario = try XCTUnwrap(DemoScenarios.scenario(for: .squadReplay))
        let player = try XCTUnwrap(scenario.player(id: "navy-rw"))

        let firstSample = player.motion(at: 12.25)
        _ = player.motion(at: 24)
        let seekedSample = player.motion(at: 12.25)

        XCTAssertEqual(firstSample, seekedSample)
        XCTAssertGreaterThanOrEqual(firstSample.speedMetresPerSecond, 0)
        XCTAssertGreaterThanOrEqual(firstSample.distanceTravelled, 0)
        XCTAssertGreaterThanOrEqual(firstSample.effort, 0)
        XCTAssertLessThanOrEqual(firstSample.effort, 1)
    }

    func testArticulatedRigContractAndGlobalOverlays() throws {
        let scenario = try XCTUnwrap(DemoScenarios.scenario(for: .squadReplay))
        let root = PitchSceneFactory.makeMatchRoot(for: scenario)
        let initiallyDetailedIDs = Set([scenario.defaultPerspectiveID])

        XCTAssertTrue(
            scenario.players.allSatisfy {
                root.findEntity(named: "player-\($0.id)")?.findEntity(named: "full-rig") == nil
            },
            "The scene must defer detailed rigs until the actual view mode is known"
        )
        PitchSceneFactory.update(
            root: root,
            scenario: scenario,
            time: 12,
            viewMode: .tacticalTable,
            perspectiveID: scenario.defaultPerspectiveID,
            marks: scenario.coachMarks,
            showsLaneLens: false,
            isDrawing: false,
            positionalOriginTransform: nil
        )

        XCTAssertNotNil(root.findEntity(named: "recorded-facing"))
        XCTAssertNotNil(root.findEntity(named: "selection-halo"))
        let ball = try XCTUnwrap(root.findEntity(named: "ball"))
        if ReplayStrategyBallProvider.isPrewarmed {
            XCTAssertNotNil(ball.findEntity(named: ReplayStrategyBallProvider.visualRootName))
        } else {
            XCTAssertNotNil(ball.findEntity(named: "ball-shell"))
            XCTAssertEqual(ball.children.filter { $0.name.hasPrefix("ball-panel-") }.count, 6)
        }
        XCTAssertNotNil(root.findEntity(named: "ball-shadow"))

        for player in scenario.players {
            let playerRoot = try XCTUnwrap(root.findEntity(named: "player-\(player.id)"))
            XCTAssertNil(playerRoot.findEntity(named: "recorded-facing"))
            XCTAssertNil(playerRoot.findEntity(named: "selection-halo"))
            let tableMarker = try XCTUnwrap(playerRoot.children.first { $0.name == "table-marker" })
            XCTAssertEqual(
                tableMarker.isEnabled,
                !initiallyDetailedIDs.contains(player.id),
                player.id
            )
            // Background players use the production far ReplayAthlete LOD.
            // Assert semantic anatomy rather than its current mesh count so a
            // future batched/imported asset can preserve the same contract.
            for joint in ReplayAthleteJoint.allCases where joint != .bodyRoot {
                let entity = try XCTUnwrap(
                    tableMarker.findEntity(named: joint.rawValue),
                    "Missing far joint \(joint.rawValue) for \(player.id)"
                )
                XCTAssertEqual(entity.parent?.name, joint.expectedParentName, player.id)
            }
            for visual in ["torso", "head", "left-leg", "right-leg", "left-arm", "right-arm"] {
                XCTAssertNotNil(tableMarker.findEntity(named: visual), "\(player.id): \(visual)")
            }
            XCTAssertNil(tableMarker.findEntity(named: "shirt-number"), player.id)

            guard initiallyDetailedIDs.contains(player.id) else {
                XCTAssertNil(playerRoot.children.first { $0.name == "full-rig" }, player.id)
                continue
            }

            let fullRig = try XCTUnwrap(playerRoot.children.first { $0.name == "full-rig" })
            XCTAssertTrue(fullRig.isEnabled, player.id)
            XCTAssertNotNil(fullRig.findEntity(named: "contact-shadow"), player.id)
            let body = try XCTUnwrap(fullRig.findEntity(named: "body-root"))
            let hips = try XCTUnwrap(body.findEntity(named: "hips"))
            let spine = try XCTUnwrap(hips.findEntity(named: "spine"))
            let leftHip = try XCTUnwrap(hips.findEntity(named: "left-hip"))
            let rightHip = try XCTUnwrap(hips.findEntity(named: "right-hip"))
            let leftKnee = try XCTUnwrap(leftHip.findEntity(named: "left-knee"))
            let rightKnee = try XCTUnwrap(rightHip.findEntity(named: "right-knee"))
            let leftShoulder = try XCTUnwrap(spine.findEntity(named: "left-shoulder"))
            let rightShoulder = try XCTUnwrap(spine.findEntity(named: "right-shoulder"))

            XCTAssertNotNil(spine.findEntity(named: "torso"), player.id)
            XCTAssertNotNil(spine.findEntity(named: "left-kit-stripe"), player.id)
            XCTAssertNotNil(spine.findEntity(named: "shirt-number"), player.id)
            XCTAssertNotNil(spine.findEntity(named: "chest-number"), player.id)
            XCTAssertNotNil(spine.findEntity(named: "left-eye"), player.id)
            XCTAssertNotNil(spine.findEntity(named: "nose"), player.id)
            XCTAssertNotNil(leftKnee.findEntity(named: "left-ankle"), player.id)
            XCTAssertNotNil(rightKnee.findEntity(named: "right-ankle"), player.id)
            XCTAssertNotNil(leftKnee.findEntity(named: "left-boot"), player.id)
            XCTAssertNotNil(rightKnee.findEntity(named: "right-boot-accent"), player.id)
            XCTAssertNotNil(leftShoulder.findEntity(named: "left-wrist"), player.id)
            XCTAssertNotNil(rightShoulder.findEntity(named: "right-hand"), player.id)

            let bounds = fullRig.visualBounds(relativeTo: fullRig)
            XCTAssertGreaterThan(bounds.extents.y, 1.70, player.id)
            XCTAssertLessThan(bounds.extents.y, 2.10, player.id)
            XCTAssertGreaterThan(bounds.extents.x, 0.55, player.id)
        }

        let pitch = try XCTUnwrap(root.findEntity(named: "pitch"))
        let batchedMarkings = try XCTUnwrap(
            pitch.findEntity(named: "pitch-markings-and-goals") as? ModelEntity
        )
        XCTAssertNotNil(batchedMarkings.components[ModelComponent.self])
        XCTAssertTrue(batchedMarkings.children.isEmpty)
    }

    func testIntegratedDetailedRigUsesSharedGroundedLocomotionPoseDeterministically() throws {
        let scenario = try XCTUnwrap(DemoScenarios.scenario(for: .squadReplay))
        let root = PitchSceneFactory.makeMatchRoot(for: scenario)
        PitchSceneFactory.update(
            root: root,
            scenario: scenario,
            time: 12,
            viewMode: .touchline,
            perspectiveID: "navy-rw",
            marks: scenario.coachMarks,
            showsLaneLens: false,
            isDrawing: false,
            positionalOriginTransform: nil
        )
        let playerRoot = try XCTUnwrap(root.findEntity(named: "player-navy-rw"))
        let fullRig = try XCTUnwrap(playerRoot.children.first { $0.name == "full-rig" })
        let body = try XCTUnwrap(fullRig.findEntity(named: "body-root"))
        let hips = try XCTUnwrap(fullRig.findEntity(named: "hips"))
        let leftAnkle = try XCTUnwrap(fullRig.findEntity(named: "left-ankle"))
        let leftWrist = try XCTUnwrap(fullRig.findEntity(named: "left-wrist"))
        let spine = try XCTUnwrap(fullRig.findEntity(named: "spine"))

        PitchSceneFactory.update(
            root: root,
            scenario: scenario,
            time: 12,
            viewMode: .touchline,
            perspectiveID: "navy-rw",
            marks: scenario.coachMarks,
            showsLaneLens: false,
            isDrawing: false,
            positionalOriginTransform: nil
        )
        let firstAnkle = leftAnkle.orientation.vector
        let firstWrist = leftWrist.orientation.vector
        let firstSpine = spine.orientation.vector
        let firstBodyPosition = body.position
        let expectedFirst = ReplayAthleteMotion.locomotionPose(
            for: try XCTUnwrap(scenario.player(id: "navy-rw")),
            at: 12
        )
        XCTAssertEqual(body.position, expectedFirst.bodyPosition)
        XCTAssertEqual(body.orientation.vector, expectedFirst.bodyOrientation.vector)
        XCTAssertEqual(hips.position, expectedFirst.hipsPosition)
        XCTAssertEqual(hips.orientation.vector, expectedFirst.hipsOrientation.vector)
        XCTAssertEqual(leftAnkle.orientation.vector, expectedFirst.leftAnkleOrientation.vector)
        XCTAssertEqual(leftWrist.orientation.vector, expectedFirst.leftWristOrientation.vector)
        XCTAssertEqual(spine.orientation.vector, expectedFirst.spineOrientation.vector)

        PitchSceneFactory.update(
            root: root,
            scenario: scenario,
            time: 12.7,
            viewMode: .touchline,
            perspectiveID: "navy-rw",
            marks: scenario.coachMarks,
            showsLaneLens: false,
            isDrawing: false,
            positionalOriginTransform: nil
        )
        let expectedLater = ReplayAthleteMotion.locomotionPose(
            for: try XCTUnwrap(scenario.player(id: "navy-rw")),
            at: 12.7
        )
        XCTAssertEqual(body.position, expectedLater.bodyPosition)
        XCTAssertEqual(body.orientation.vector, expectedLater.bodyOrientation.vector)
        XCTAssertEqual(hips.position, expectedLater.hipsPosition)
        XCTAssertEqual(hips.orientation.vector, expectedLater.hipsOrientation.vector)
        XCTAssertNotEqual(leftAnkle.orientation.vector, firstAnkle)
        XCTAssertNotEqual(leftWrist.orientation.vector, firstWrist)
        XCTAssertNotEqual(spine.orientation.vector, firstSpine)
        XCTAssertNotEqual(body.position, firstBodyPosition)

        PitchSceneFactory.update(
            root: root,
            scenario: scenario,
            time: 12,
            viewMode: .touchline,
            perspectiveID: "navy-rw",
            marks: scenario.coachMarks,
            showsLaneLens: false,
            isDrawing: false,
            positionalOriginTransform: nil
        )
        XCTAssertEqual(leftAnkle.orientation.vector, firstAnkle)
        XCTAssertEqual(leftWrist.orientation.vector, firstWrist)
        XCTAssertEqual(spine.orientation.vector, firstSpine)
        XCTAssertEqual(body.position, firstBodyPosition)
    }

    func testOverviewLODUsesHumanMarkersOnlyForBackgroundPlayers() throws {
        let scenario = try XCTUnwrap(DemoScenarios.scenario(for: .squadReplay))
        let root = PitchSceneFactory.makeMatchRoot(for: scenario)
        let selectedBackgroundID = try XCTUnwrap(
            scenario.players.first { $0.id != scenario.defaultPerspectiveID }?.id
        )

        PitchSceneFactory.update(
            root: root,
            scenario: scenario,
            time: 12,
            viewMode: .tacticalTable,
            perspectiveID: selectedBackgroundID,
            marks: scenario.coachMarks,
            showsLaneLens: false,
            isDrawing: false,
            positionalOriginTransform: nil
        )

        var backgroundMarkerCount = 0
        var retainedDetailedCount = 0
        for player in scenario.players {
            let playerRoot = try XCTUnwrap(root.findEntity(named: "player-\(player.id)"))
            let fullRig = playerRoot.children.first { $0.name == "full-rig" }
            let tableMarker = try XCTUnwrap(playerRoot.children.first { $0.name == "table-marker" })
            let expectsActiveFullRig = player.id == selectedBackgroundID

            XCTAssertEqual(fullRig?.isEnabled == true, expectsActiveFullRig, player.id)
            XCTAssertEqual(tableMarker.isEnabled, !expectsActiveFullRig, player.id)
            if fullRig != nil { retainedDetailedCount += 1 }
            if !expectsActiveFullRig { backgroundMarkerCount += 1 }
        }
        XCTAssertGreaterThan(backgroundMarkerCount, 0)
        XCTAssertLessThanOrEqual(retainedDetailedCount, 2)

        PitchSceneFactory.update(
            root: root,
            scenario: scenario,
            time: 12,
            viewMode: .touchline,
            perspectiveID: selectedBackgroundID,
            marks: scenario.coachMarks,
            showsLaneLens: false,
            isDrawing: false,
            positionalOriginTransform: nil
        )

        for player in scenario.players {
            let playerRoot = try XCTUnwrap(root.findEntity(named: "player-\(player.id)"))
            let fullRig = playerRoot.children.first { $0.name == "full-rig" }
            let tableMarker = try XCTUnwrap(playerRoot.children.first { $0.name == "table-marker" })
            let expectsActiveFullRig = player.id == selectedBackgroundID
            XCTAssertEqual(fullRig?.isEnabled == true, expectsActiveFullRig, player.id)
            XCTAssertEqual(tableMarker.isEnabled, !expectsActiveFullRig, player.id)
        }
    }

    func testDetailedRigSelectionIsBoundedAndDefaultRigSurvivesAtoBtoA() throws {
        let scenario = try XCTUnwrap(DemoScenarios.scenario(for: .squadReplay))
        let root = PitchSceneFactory.makeMatchRoot(for: scenario)
        let defaultID = scenario.defaultPerspectiveID
        let alternateID = try XCTUnwrap(
            scenario.players.first { $0.id != defaultID }?.id
        )
        let defaultPlayer = try XCTUnwrap(root.findEntity(named: "player-\(defaultID)"))
        PitchSceneFactory.update(
            root: root,
            scenario: scenario,
            time: 12,
            viewMode: .tacticalTable,
            perspectiveID: defaultID,
            marks: scenario.coachMarks,
            showsLaneLens: false,
            isDrawing: false,
            positionalOriginTransform: nil
        )
        let originalDefaultRig = try XCTUnwrap(
            defaultPlayer.children.first { $0.name == "full-rig" }
        )

        PitchSceneFactory.update(
            root: root,
            scenario: scenario,
            time: 12,
            viewMode: .tacticalTable,
            perspectiveID: alternateID,
            marks: scenario.coachMarks,
            showsLaneLens: false,
            isDrawing: false,
            positionalOriginTransform: nil
        )

        XCTAssertFalse(originalDefaultRig.isEnabled)
        let alternatePlayer = try XCTUnwrap(root.findEntity(named: "player-\(alternateID)"))
        let alternateRig = try XCTUnwrap(
            alternatePlayer.children.first { $0.name == "full-rig" }
        )
        XCTAssertTrue(alternateRig.isEnabled)
        XCTAssertEqual(
            scenario.players.filter {
                root.findEntity(named: "player-\($0.id)")?.children.contains {
                    $0.name == "full-rig"
                } == true
            }.count,
            2
        )

        PitchSceneFactory.update(
            root: root,
            scenario: scenario,
            time: 12.033,
            viewMode: .tacticalTable,
            perspectiveID: alternateID,
            marks: scenario.coachMarks,
            showsLaneLens: false,
            isDrawing: false,
            positionalOriginTransform: nil
        )
        let repeatedAlternateRig = try XCTUnwrap(
            alternatePlayer.children.first { $0.name == "full-rig" }
        )
        XCTAssertTrue(alternateRig === repeatedAlternateRig)

        PitchSceneFactory.update(
            root: root,
            scenario: scenario,
            time: 12,
            viewMode: .tacticalTable,
            perspectiveID: defaultID,
            marks: scenario.coachMarks,
            showsLaneLens: false,
            isDrawing: false,
            positionalOriginTransform: nil
        )

        let returnedDefaultRig = try XCTUnwrap(
            defaultPlayer.children.first { $0.name == "full-rig" }
        )
        XCTAssertTrue(originalDefaultRig === returnedDefaultRig)
        XCTAssertTrue(returnedDefaultRig.isEnabled)
        XCTAssertNil(alternatePlayer.children.first { $0.name == "full-rig" })
        XCTAssertEqual(
            scenario.players.filter {
                root.findEntity(named: "player-\($0.id)")?.children.contains {
                    $0.name == "full-rig"
                } == true
            }.count,
            1
        )
    }

    func testPlayerUpdatesResolveByStableIDInsteadOfRealityKitChildOrder() throws {
        let scenario = try XCTUnwrap(DemoScenarios.scenario(for: .squadReplay))
        let root = PitchSceneFactory.makeMatchRoot(for: scenario)
        let playersRoot = try XCTUnwrap(root.findEntity(named: "players-root"))
        let originalPlayers = Array(playersRoot.children)

        for entity in originalPlayers {
            entity.removeFromParent()
        }
        let unrelatedChild = Entity()
        unrelatedChild.name = "diagnostic-child"
        unrelatedChild.position = [91, 92, 93]
        playersRoot.addChild(unrelatedChild)
        for entity in originalPlayers.reversed() {
            playersRoot.addChild(entity)
        }

        let selectedID = "red-lb"
        let sampleTime: TimeInterval = 13.25
        PitchSceneFactory.update(
            root: root,
            scenario: scenario,
            time: sampleTime,
            viewMode: .touchline,
            perspectiveID: selectedID,
            marks: scenario.coachMarks,
            showsLaneLens: false,
            isDrawing: false,
            positionalOriginTransform: nil
        )

        XCTAssertEqual(unrelatedChild.position, SIMD3<Float>(91, 92, 93))
        for player in scenario.players {
            let entity = try XCTUnwrap(root.findEntity(named: "player-\(player.id)"))
            let expected = player.presentationPose(at: sampleTime).position
            XCTAssertEqual(entity.position.x, expected.x, accuracy: 0.000_1, player.id)
            XCTAssertEqual(entity.position.z, expected.z, accuracy: 0.000_1, player.id)
            let fullRig = entity.children.first { $0.name == "full-rig" }
            XCTAssertEqual(fullRig?.isEnabled == true, player.id == selectedID, player.id)
        }
    }

    func testCenteredGaitEffortIsSmoothAndDeterministicAcrossAKeyframeSeek() throws {
        let scenario = try XCTUnwrap(DemoScenarios.scenario(for: .squadReplay))
        let player = try XCTUnwrap(scenario.player(id: "navy-rw"))
        // The winger's authored change from checking still to accelerating now
        // begins at 10.4 s after the match-tempo retiming pass.
        let keyframeTime: TimeInterval = 10.4

        let justBefore = PitchSceneFactory.gaitEffort(for: player, at: keyframeTime - 0.001)
        let justAfter = PitchSceneFactory.gaitEffort(for: player, at: keyframeTime + 0.001)
        _ = PitchSceneFactory.gaitEffort(for: player, at: 27.4)
        let seekedBefore = PitchSceneFactory.gaitEffort(for: player, at: keyframeTime - 0.001)

        XCTAssertEqual(justBefore, seekedBefore)
        XCTAssertLessThan(abs(justAfter - justBefore), 0.01)
        XCTAssertGreaterThan(justBefore, 0)
        XCTAssertLessThanOrEqual(justAfter, 1)
    }

    func testMatchPlaybackBuildsReadablePlayerTagsAndDirectHitTargets() throws {
        let scenario = try XCTUnwrap(DemoScenarios.scenario(for: .squadReplay))
        let root = PitchSceneFactory.makeMatchRoot(for: scenario)

        PitchSceneFactory.update(
            root: root,
            scenario: scenario,
            time: 13.6,
            viewMode: .tacticalTable,
            perspectiveID: scenario.defaultPerspectiveID,
            marks: scenario.coachMarks,
            showsLaneLens: false,
            isDrawing: false,
            positionalOriginTransform: nil
        )

        let labelsRoot = try XCTUnwrap(root.findEntity(named: "player-labels-root"))
        XCTAssertEqual(labelsRoot.children.count, scenario.players.count)

        for player in scenario.players {
            let label = try XCTUnwrap(
                labelsRoot.children.first { $0.name == "player-label-\(player.id)" },
                player.id
            )
            XCTAssertTrue(label.isEnabled, player.id)
            XCTAssertNotNil(label.findEntity(named: "label-glyph"), player.id)
            XCTAssertNotNil(label.findEntity(named: "compact-label-glyph"), player.id)
            XCTAssertNotNil(label.findEntity(named: "team-strip"), player.id)
            XCTAssertNotNil(label.components[InputTargetComponent.self], player.id)
            XCTAssertNotNil(label.components[CollisionComponent.self], player.id)
            let labelAccessibility = try XCTUnwrap(
                label.components[AccessibilityComponent.self],
                player.id
            )
            XCTAssertFalse(labelAccessibility.isAccessibilityElement, player.id)
            XCTAssertEqual(
                label.position.y,
                PlaybackSpatialLabels.tacticalLabelHeight(
                    team: player.team,
                    shirtNumber: player.shirtNumber
                ),
                accuracy: 0.000_1,
                player.id
            )

            let playerRoot = try XCTUnwrap(root.findEntity(named: "player-\(player.id)"))
            let target = try XCTUnwrap(playerRoot.findEntity(named: "interaction-target"))
            XCTAssertNotNil(target.components[InputTargetComponent.self], player.id)
            XCTAssertNotNil(target.components[CollisionComponent.self], player.id)
            let bodyAccessibility = try XCTUnwrap(
                target.components[AccessibilityComponent.self],
                player.id
            )
            XCTAssertTrue(bodyAccessibility.isAccessibilityElement, player.id)
            XCTAssertTrue(bodyAccessibility.systemActions.contains(.activate), player.id)
            XCTAssertTrue(target.isEnabled, player.id)
            let worldFootprintScale = target.scale.x * playerRoot.scale.x
            XCTAssertEqual(worldFootprintScale, 2.4, accuracy: 0.000_1, player.id)
        }

        let selectedLabel = try XCTUnwrap(
            labelsRoot.findEntity(named: "player-label-\(scenario.defaultPerspectiveID)")
        )
        XCTAssertTrue(try XCTUnwrap(selectedLabel.findEntity(named: "selected-outline")).isEnabled)
        XCTAssertTrue(try XCTUnwrap(selectedLabel.findEntity(named: "label-glyph")).isEnabled)
        XCTAssertFalse(try XCTUnwrap(selectedLabel.findEntity(named: "compact-label-glyph")).isEnabled)
        XCTAssertEqual(selectedLabel.scale.x, 4.75, accuracy: 0.000_1)
        let compactLabel = try XCTUnwrap(labelsRoot.findEntity(named: "player-label-navy-rb"))
        XCTAssertFalse(try XCTUnwrap(compactLabel.findEntity(named: "label-glyph")).isEnabled)
        let numberOnlyGlyph = try XCTUnwrap(compactLabel.findEntity(named: "compact-label-glyph"))
        XCTAssertTrue(numberOnlyGlyph.isEnabled)
        XCTAssertNotNil(numberOnlyGlyph.components[ModelComponent.self])
        XCTAssertFalse(try XCTUnwrap(compactLabel.findEntity(named: "label-board")).isEnabled)
        XCTAssertFalse(try XCTUnwrap(compactLabel.findEntity(named: "team-strip")).isEnabled)
        XCTAssertTrue(try XCTUnwrap(selectedLabel.findEntity(named: "label-board")).isEnabled)
        XCTAssertTrue(try XCTUnwrap(selectedLabel.findEntity(named: "team-strip")).isEnabled)
        XCTAssertLessThan(
            PlaybackSpatialLabels.tacticalLabelHeight(team: .home, shirtNumber: 7),
            PlaybackSpatialLabels.tacticalLabelHeight(team: .away, shirtNumber: 2)
        )
        let pitch = try XCTUnwrap(root.findEntity(named: "pitch"))
        XCTAssertTrue(try XCTUnwrap(pitch.findEntity(named: "tactical-board-rim")).isEnabled)
        XCTAssertEqual(try XCTUnwrap(root.findEntity(named: "ball")).scale.x, 3.2, accuracy: 0.000_1)
    }

    func testFirstPersonCapsSpatialLabelsAndRemovesWearerHitTarget() throws {
        let scenario = try XCTUnwrap(DemoScenarios.scenario(for: .squadReplay))
        let root = PitchSceneFactory.makeMatchRoot(for: scenario)

        PitchSceneFactory.update(
            root: root,
            scenario: scenario,
            time: 13.6,
            viewMode: .firstPerson,
            perspectiveID: "navy-rw",
            marks: scenario.coachMarks,
            showsLaneLens: false,
            isDrawing: false,
            positionalOriginTransform: nil
        )

        let labelsRoot = try XCTUnwrap(root.findEntity(named: "player-labels-root"))
        let visibleLabels = labelsRoot.children.filter(\.isEnabled)
        XCTAssertFalse(visibleLabels.isEmpty)
        XCTAssertLessThanOrEqual(
            visibleLabels.count,
            PlaybackSpatialLabels.firstPersonVisibleLabelLimit
        )
        for label in visibleLabels {
            XCTAssertGreaterThanOrEqual(label.scale.x, 0.34, label.name)
            XCTAssertLessThanOrEqual(label.scale.x, 0.62, label.name)
            XCTAssertGreaterThanOrEqual(label.position.y, 2.20, label.name)
            XCTAssertLessThanOrEqual(label.position.y, 2.60, label.name)
        }
        let wearerPose = try XCTUnwrap(
            scenario.player(id: "navy-rw")
        ).presentationPose(at: 13.6)
        let nearPlayers = scenario.players.filter { player in
            player.id != "navy-rw"
                && ReplayGeometry.distance(
                    wearerPose.position,
                    player.presentationPose(at: 13.6).position
                )
                    < PlaybackSpatialLabels.firstPersonMinimumLabelDistance
        }
        for player in nearPlayers {
            XCTAssertFalse(
                try XCTUnwrap(labelsRoot.findEntity(named: "player-label-\(player.id)")).isEnabled,
                player.id
            )
        }
        let closestPlayer = try XCTUnwrap(
            scenario.players
                .filter { $0.id != "navy-rw" }
                .min {
                    ReplayGeometry.distance(
                        wearerPose.position,
                        $0.presentationPose(at: 13.6).position
                    ) < ReplayGeometry.distance(
                        wearerPose.position,
                        $1.presentationPose(at: 13.6).position
                    )
                }
        )
        let closeRig = try XCTUnwrap(
            root.findEntity(named: "player-\(closestPlayer.id)")?
                .findEntity(named: "full-rig")
        )
        XCTAssertNotNil(
            closeRig.findEntity(named: "shirt-number")?.components[ModelComponent.self],
            "A hidden close-range tag must hand identity off to the geometric jersey number"
        )
        XCTAssertFalse(
            try XCTUnwrap(labelsRoot.findEntity(named: "player-label-navy-rw")).isEnabled
        )
        let wearer = try XCTUnwrap(root.findEntity(named: "player-navy-rw"))
        XCTAssertFalse(try XCTUnwrap(wearer.findEntity(named: "interaction-target")).isEnabled)
        let pitch = try XCTUnwrap(root.findEntity(named: "pitch"))
        XCTAssertFalse(try XCTUnwrap(pitch.findEntity(named: "tactical-board-rim")).isEnabled)
    }

    func testFirstPersonLabelSizingIsDistanceAwareAndBounded() {
        let nearScale = PlaybackSpatialLabels.firstPersonLabelScale(forDistance: 1)
        let midfieldScale = PlaybackSpatialLabels.firstPersonLabelScale(forDistance: 20)
        let distantScale = PlaybackSpatialLabels.firstPersonLabelScale(forDistance: 200)

        XCTAssertLessThan(nearScale, midfieldScale)
        XCTAssertLessThan(midfieldScale, distantScale)
        XCTAssertEqual(distantScale, 0.62, accuracy: 0.000_1)
        XCTAssertEqual(
            PlaybackSpatialLabels.firstPersonLabelHeight(forDistance: 200),
            2.36,
            accuracy: 0.000_1
        )

        let nearAnnotation = PlaybackSpatialLabels.firstPersonAnnotationScale(forDistance: 1)
        let midfieldAnnotation = PlaybackSpatialLabels.firstPersonAnnotationScale(forDistance: 20)
        let distantAnnotation = PlaybackSpatialLabels.firstPersonAnnotationScale(forDistance: 200)
        XCTAssertLessThan(nearAnnotation, midfieldAnnotation)
        XCTAssertLessThan(midfieldAnnotation, distantAnnotation)
        XCTAssertEqual(nearAnnotation, 0.34, accuracy: 0.000_1)
        XCTAssertEqual(distantAnnotation, 0.58, accuracy: 0.000_1)
    }

    func testTimestampedPlayerLabelRendersAndFollowsItsTargetTrack() throws {
        let scenario = try XCTUnwrap(DemoScenarios.scenario(for: .squadReplay))
        let store = ReplayStore(scenarios: [scenario])
        store.seek(to: 12.5, broadcast: false)
        store.beginDrawing(.playerLabel)
        let mark = try XCTUnwrap(store.labelPlayer("red-lb"))
        let root = PitchSceneFactory.makeMatchRoot(for: scenario)

        PitchSceneFactory.update(
            root: root,
            scenario: scenario,
            time: 16,
            viewMode: .tacticalTable,
            perspectiveID: scenario.defaultPerspectiveID,
            marks: store.marks,
            showsLaneLens: false,
            isDrawing: false,
            positionalOriginTransform: nil
        )

        let markRoot = try XCTUnwrap(root.findEntity(named: "mark-\(mark.id.uuidString)"))
        let label = try XCTUnwrap(markRoot.findEntity(named: "annotation-label"))
        let targetPose = try XCTUnwrap(
            scenario.player(id: "red-lb")
        ).presentationPose(at: 16)
        XCTAssertTrue(markRoot.isEnabled)
        XCTAssertEqual(label.position.x, targetPose.position.x, accuracy: 0.000_1)
        XCTAssertEqual(label.position.y, 9.40, accuracy: 0.000_1)
        XCTAssertEqual(label.position.z, targetPose.position.z, accuracy: 0.000_1)

        PitchSceneFactory.update(
            root: root,
            scenario: scenario,
            time: 12,
            viewMode: .tacticalTable,
            perspectiveID: scenario.defaultPerspectiveID,
            marks: store.marks,
            showsLaneLens: false,
            isDrawing: false,
            positionalOriginTransform: nil
        )
        XCTAssertFalse(markRoot.isEnabled)

        PitchSceneFactory.update(
            root: root,
            scenario: scenario,
            time: try XCTUnwrap(mark.hideTime) + 0.01,
            viewMode: .tacticalTable,
            perspectiveID: scenario.defaultPerspectiveID,
            marks: store.marks,
            showsLaneLens: false,
            isDrawing: false,
            positionalOriginTransform: nil
        )
        XCTAssertFalse(markRoot.isEnabled)
    }

    func testAnnotationDraftRendersAtFirstTapAndClearsWhenCancelled() throws {
        let scenario = try XCTUnwrap(DemoScenarios.scenario(for: .squadReplay))
        let root = PitchSceneFactory.makeMatchRoot(for: scenario)
        let start = PitchPoint(x: 14, z: 21)

        PitchSceneFactory.update(
            root: root,
            scenario: scenario,
            time: 13.6,
            viewMode: .tacticalTable,
            perspectiveID: scenario.defaultPerspectiveID,
            marks: scenario.coachMarks,
            showsLaneLens: false,
            isDrawing: true,
            draftStart: start,
            draftKind: .pass,
            positionalOriginTransform: nil
        )

        let draft = try XCTUnwrap(root.findEntity(named: "annotation-draft-root"))
        XCTAssertTrue(draft.isEnabled)
        XCTAssertEqual(draft.position.x, start.x, accuracy: 0.000_1)
        XCTAssertEqual(draft.position.z, start.z, accuracy: 0.000_1)
        let reticle = try XCTUnwrap(draft.findEntity(named: "annotation-draft-ring"))
        XCTAssertEqual(reticle.children.count, 4)
        XCTAssertFalse(reticle is ModelEntity)
        let draftLabel = try XCTUnwrap(draft.findEntity(named: "annotation-label"))
        XCTAssertTrue(
            try XCTUnwrap(draftLabel.findEntity(named: "annotation-draft-label-pass")).isEnabled
        )
        XCTAssertFalse(
            try XCTUnwrap(draftLabel.findEntity(named: "annotation-draft-label-run")).isEnabled
        )

        PitchSceneFactory.update(
            root: root,
            scenario: scenario,
            time: 13.7,
            viewMode: .tacticalTable,
            perspectiveID: scenario.defaultPerspectiveID,
            marks: scenario.coachMarks,
            showsLaneLens: false,
            isDrawing: false,
            draftStart: nil,
            draftKind: .pass,
            positionalOriginTransform: nil
        )
        XCTAssertFalse(draft.isEnabled)
    }

    func testSpaceAnnotationUsesAReadableRingWithoutFloodingThePitch() throws {
        let scenario = try XCTUnwrap(DemoScenarios.scenario(for: .coachFocus))
        let mark = try XCTUnwrap(scenario.coachMarks.first { $0.kind == .space })
        let root = PitchSceneFactory.makeMatchRoot(for: scenario)

        PitchSceneFactory.update(
            root: root,
            scenario: scenario,
            time: mark.revealTime + 0.1,
            viewMode: .firstPerson,
            perspectiveID: scenario.defaultPerspectiveID,
            marks: scenario.coachMarks,
            selectedAnnotationID: mark.id,
            selectedAnnotationIsEditable: false,
            showsLaneLens: false,
            isDrawing: false,
            positionalOriginTransform: nil
        )

        let markRoot = try XCTUnwrap(root.findEntity(named: "mark-\(mark.id.uuidString)"))
        let ring = try XCTUnwrap(
            markRoot.findEntity(named: "annotation-mark-space") as? ModelEntity
        )
        XCTAssertNotNil(ring.components[ModelComponent.self])
        XCTAssertTrue(ring.children.isEmpty)
        XCTAssertEqual(ring.position.y, 0.072, accuracy: 0.000_1)
        let selectionRoot = try XCTUnwrap(
            root.findEntity(named: AnnotationSceneAffordance.selectionRootName)
        )
        let selectedRing = try XCTUnwrap(
            selectionRoot.findEntity(named: "annotation-selection-zone") as? ModelEntity
        )
        XCTAssertTrue(selectedRing.isEnabled)
        XCTAssertNotNil(selectedRing.components[ModelComponent.self])
        XCTAssertTrue(selectedRing.children.isEmpty)
        let marksRoot = try XCTUnwrap(root.findEntity(named: "marks-root"))
        let visibleLabels = marksRoot.children.compactMap {
            $0.findEntity(named: "annotation-label")
        }.filter(\.isEnabled)
        XCTAssertLessThanOrEqual(
            visibleLabels.count,
            PlaybackSpatialLabels.firstPersonVisibleAnnotationLimit
        )
        XCTAssertTrue(try XCTUnwrap(markRoot.findEntity(named: "annotation-label")).isEnabled)
    }

    func testAnnotationSceneCacheReusesStableEntitiesAndRebuildsEditedMarks() throws {
        let scenario = try XCTUnwrap(DemoScenarios.scenario(for: .squadReplay))
        let root = PitchSceneFactory.makeMatchRoot(for: scenario)
        let id = UUID(uuidString: "8B60A442-6E1A-4C50-81A2-A8A17BBE3C5F")!
        let original = CoachMark(
            id: id,
            kind: .pass,
            start: PitchPoint(x: 2, z: 3),
            end: PitchPoint(x: 9, z: 12),
            label: "Original",
            revealTime: 0
        )

        func render(_ marks: [CoachMark], time: TimeInterval) {
            PitchSceneFactory.update(
                root: root,
                scenario: scenario,
                time: time,
                viewMode: .tacticalTable,
                perspectiveID: scenario.defaultPerspectiveID,
                marks: marks,
                showsLaneLens: false,
                isDrawing: false,
                positionalOriginTransform: nil
            )
        }

        render([original], time: 1)
        let first = try XCTUnwrap(root.findEntity(named: "mark-\(id.uuidString)"))
        render([original], time: 2)
        let reused = try XCTUnwrap(root.findEntity(named: "mark-\(id.uuidString)"))
        XCTAssertTrue(first === reused)

        let edited = CoachMark(
            id: id,
            kind: .pass,
            start: original.start,
            end: PitchPoint(x: 14, z: 16),
            label: "Edited",
            revealTime: 0
        )
        render([edited], time: 2)
        let rebuilt = try XCTUnwrap(root.findEntity(named: "mark-\(id.uuidString)"))
        XCTAssertFalse(first === rebuilt)

        render([], time: 2)
        XCTAssertNil(root.findEntity(named: "mark-\(id.uuidString)"))
    }

    func testTabletopSquadLODUsesTelemetryDrivenLimbAnimation() throws {
        let scenario = try XCTUnwrap(DemoScenarios.scenario(for: .squadReplay))
        let root = PitchSceneFactory.makeMatchRoot(for: scenario)
        let backgroundID = "red-lb"

        PitchSceneFactory.update(
            root: root,
            scenario: scenario,
            time: 12,
            viewMode: .tacticalTable,
            perspectiveID: scenario.defaultPerspectiveID,
            marks: scenario.coachMarks,
            showsLaneLens: false,
            isDrawing: false,
            positionalOriginTransform: nil
        )
        let marker = try XCTUnwrap(
            root.findEntity(named: "player-\(backgroundID)")?
                .findEntity(named: "table-marker")
        )
        let shoulder = try XCTUnwrap(marker.findEntity(named: "left-shoulder"))
        let body = try XCTUnwrap(marker.findEntity(named: "body-root"))
        let firstOrientation = shoulder.orientation.vector

        PitchSceneFactory.update(
            root: root,
            scenario: scenario,
            time: 13,
            viewMode: .tacticalTable,
            perspectiveID: scenario.defaultPerspectiveID,
            marks: scenario.coachMarks,
            showsLaneLens: false,
            isDrawing: false,
            positionalOriginTransform: nil
        )
        let player = try XCTUnwrap(scenario.player(id: backgroundID))
        let expected = ReplayAthleteMotion.locomotionPose(for: player, at: 13)
        XCTAssertNotEqual(shoulder.orientation.vector, firstOrientation)
        XCTAssertEqual(shoulder.orientation.vector, expected.leftShoulderOrientation.vector)
        XCTAssertEqual(body.position, expected.bodyPosition)
    }

    func testDenseAnnotationAdmissionStaysWithinNormalAndDecisionDrawLimits() {
        let kinds: [CoachMarkKind] = [.run, .pass, .danger, .space, .playerLabel]
        var marks: [CoachMark] = []
        marks.reserveCapacity(80)
        for index in 0..<80 {
            marks.append(CoachMark(
                id: UUID(),
                kind: kinds[index % kinds.count],
                start: PitchPoint(x: Float(index % 8), z: Float(index / 8)),
                end: PitchPoint(x: Float(index % 8) + 3, z: Float(index / 8) + 4),
                label: "Dense \(index)",
                revealTime: 0
            ))
        }
        guard let selectedID = marks.first(where: { $0.kind == .space })?.id else {
            return XCTFail("Dense fixture must include a space annotation")
        }
        let priorityIndices = PlaybackSceneRenderBudget.priorityIndices(for: marks)

        for decisionReviewIsVisible in [false, true] {
            let visible = PlaybackSceneRenderBudget.visibleAnnotationIDs(
                in: marks,
                priorityIndices: priorityIndices,
                at: 1,
                selectedID: selectedID,
                selectedIsEditable: true,
                decisionReviewIsVisible: decisionReviewIsVisible
            )
            let estimated = PlaybackSceneRenderBudget.estimatedAnnotationDraws(
                for: marks,
                visibleIDs: visible
            )
            let limit = decisionReviewIsVisible
                ? PlaybackSceneRenderBudget.decisionAnnotationDrawLimit
                : PlaybackSceneRenderBudget.normalAnnotationDrawLimit

            XCTAssertLessThan(visible.count, marks.count)
            XCTAssertTrue(visible.contains(selectedID))
            XCTAssertLessThanOrEqual(estimated, limit)
            XCTAssertLessThanOrEqual(
                estimated + PlaybackSceneRenderBudget.selectedEditableOverlayDraws,
                PlaybackSceneRenderBudget.selectedAnnotationSystemDrawLimit
            )
        }
    }

    func testLocalCoachPOVImmediatelyPausesSquadWithoutReplacingSharedView() throws {
        let store = ReplayStore()
        let coordinator = LegacySnapshotCoordinator(store: store)
        coordinator.state = .joined
        coordinator.authoritativeCoachID = coordinator.localID
        store.setCollaborationActive(true)
        store.setViewMode(.tacticalTable)
        store.setPlaying(true)

        let published = try XCTUnwrap(coordinator.snapshotForHeartbeat())
        XCTAssertEqual(published.viewMode, .tacticalTable)
        XCTAssertTrue(published.isPlaying)

        store.openLocalPlayerPOV("red-lb")
        XCTAssertTrue(store.isCoachLocalReview)
        XCTAssertEqual(store.viewMode, .firstPerson)
        XCTAssertFalse(store.isPlaying)
        let pausedForLocalReview = try XCTUnwrap(coordinator.snapshotForHeartbeat())
        XCTAssertEqual(pausedForLocalReview.playhead, published.playhead, accuracy: 0.000_1)
        XCTAssertFalse(pausedForLocalReview.isPlaying)
        XCTAssertEqual(pausedForLocalReview.viewMode, published.viewMode)
        XCTAssertEqual(pausedForLocalReview.coachFocusPerspectiveID, published.coachFocusPerspectiveID)
        XCTAssertEqual(pausedForLocalReview.coachLockEnabled, published.coachLockEnabled)

        // Subsequent shared edits must not smuggle the coach's unshared local
        // first-person view into the room.
        store.beginDrawing(.pass)
        let paused = try XCTUnwrap(coordinator.snapshotForHeartbeat())
        XCTAssertEqual(paused.viewMode, .tacticalTable)
        XCTAssertFalse(paused.isPlaying)

        // View changes now wait until drawing releases the camera frame.
        store.cancelDrawing()
        store.broadcastPerspective("red-lb")
        let sharedPOV = try XCTUnwrap(coordinator.snapshotForHeartbeat())
        XCTAssertFalse(store.isCoachLocalReview)
        XCTAssertEqual(sharedPOV.viewMode, .firstPerson)
        XCTAssertEqual(sharedPOV.coachFocusPerspectiveID, "red-lb")
        XCTAssertTrue(sharedPOV.coachLockEnabled)
    }

    func testHeartbeatProjectionAdvancesAcrossIntervalsAndPreservesPublishedPerspective() throws {
        let store = ReplayStore()
        let coordinator = LegacySnapshotCoordinator(store: store)
        store.setCollaborationActive(true)
        store.broadcastPerspective("navy-rw")
        store.seek(to: 3, broadcast: false)
        store.setPlaying(true)

        let published = try XCTUnwrap(coordinator.snapshotForHeartbeat())
        XCTAssertEqual(published.viewMode, .firstPerson)
        XCTAssertEqual(published.coachFocusPerspectiveID, "navy-rw")
        XCTAssertTrue(published.coachLockEnabled)

        let firstHeartbeat = try XCTUnwrap(
            coordinator.advancePublishedTimelineForHeartbeat(by: 2)
        )
        XCTAssertEqual(firstHeartbeat.playhead, 5, accuracy: 0.000_1)
        XCTAssertTrue(firstHeartbeat.isPlaying)
        XCTAssertEqual(firstHeartbeat.viewMode, published.viewMode)
        XCTAssertEqual(firstHeartbeat.coachFocusPerspectiveID, published.coachFocusPerspectiveID)
        XCTAssertEqual(firstHeartbeat.coachLockEnabled, published.coachLockEnabled)

        let secondHeartbeat = try XCTUnwrap(
            coordinator.advancePublishedTimelineForHeartbeat(by: 3)
        )
        XCTAssertEqual(secondHeartbeat.playhead, 8, accuracy: 0.000_1)
        XCTAssertTrue(secondHeartbeat.isPlaying)
        XCTAssertEqual(secondHeartbeat.viewMode, published.viewMode)
        XCTAssertEqual(secondHeartbeat.coachFocusPerspectiveID, published.coachFocusPerspectiveID)
        XCTAssertEqual(secondHeartbeat.coachLockEnabled, published.coachLockEnabled)
    }

    func testHeartbeatProjectionStopsAtScenarioEndAndDoesNotRestart() throws {
        let store = ReplayStore()
        let coordinator = LegacySnapshotCoordinator(store: store)
        let duration = store.selectedScenario.duration
        store.setCollaborationActive(true)
        store.seek(to: duration - 0.25, broadcast: false)
        store.setPlaying(true)

        let ended = try XCTUnwrap(
            coordinator.advancePublishedTimelineForHeartbeat(by: 1)
        )
        XCTAssertEqual(ended.playhead, duration, accuracy: 0.000_1)
        XCTAssertFalse(ended.isPlaying)

        let laterHeartbeat = try XCTUnwrap(
            coordinator.advancePublishedTimelineForHeartbeat(by: 5)
        )
        XCTAssertEqual(laterHeartbeat.playhead, duration, accuracy: 0.000_1)
        XCTAssertFalse(laterHeartbeat.isPlaying)
    }

    func testTriangleLockDefaultsResetsAndCollaborationCloseToVisualise() throws {
        let store = ReplayStore()
        let shapeLab = try XCTUnwrap(DemoScenarios.scenario(for: .shapeLab))
        let anchorID = UUID(uuidString: "AAAAAAAA-BBBB-4CCC-8DDD-111111111111")!

        store.selectScenario(id: shapeLab.id, broadcast: false)
        XCTAssertEqual(store.triangleLockMode, .visualise)
        XCTAssertEqual(store.shapeFocusStage, .problem)
        XCTAssertEqual(store.playhead, ShapeFocusStage.problem.referenceTime, accuracy: 0.000_1)
        XCTAssertFalse(store.hasLocallyAcknowledgedTrianglePlacement)

        store.activateTrianglePlacement(anchorID: anchorID)
        XCTAssertEqual(store.triangleLockMode, .place)
        XCTAssertEqual(store.shapeFocusStage, .ideal)
        XCTAssertTrue(store.hasLocallyAcknowledgedTrianglePlacement)

        store.resetScenario()
        XCTAssertEqual(store.triangleLockMode, .visualise)
        XCTAssertEqual(store.shapeFocusStage, .problem)
        XCTAssertFalse(store.hasLocallyAcknowledgedTrianglePlacement)
        XCTAssertNil(store.sharedPitchAnchorID)

        store.activateTrianglePlacement(anchorID: anchorID)
        store.resetCollaborationState()
        XCTAssertEqual(store.triangleLockMode, .visualise)
        XCTAssertFalse(store.hasLocallyAcknowledgedTrianglePlacement)
        XCTAssertNil(store.sharedPitchAnchorID)
    }

    func testShapeFocusStagesAreDeterministicAndSynchronizeCoachToPlayer() throws {
        let shapeLab = try XCTUnwrap(DemoScenarios.scenario(for: .shapeLab))
        let coach = ReplayStore()
        coach.selectScenario(id: shapeLab.id, broadcast: false)
        var broadcasts: [SharedPlaybackSnapshot] = []
        coach.onBroadcastSnapshot = { broadcasts.append($0) }

        coach.seek(to: 31, broadcast: false)
        coach.setPlaying(true, broadcast: false)
        coach.setViewMode(.firstPerson, broadcast: false)
        coach.setShapeFocusStage(.ideal)

        XCTAssertEqual(coach.shapeFocusStage, .ideal)
        XCTAssertTrue(coach.showsIdealBranch)
        XCTAssertEqual(coach.playhead, ShapeFocusStage.ideal.referenceTime, accuracy: 0.000_1)
        XCTAssertEqual(coach.viewMode, .positional)
        XCTAssertFalse(coach.isPlaying)
        XCTAssertEqual(broadcasts.count, 1)
        XCTAssertEqual(broadcasts[0].shapeFocusStage, .ideal)

        let player = ReplayStore()
        player.localRole = .player
        player.setCollaborationActive(true)
        player.applyRemote(broadcasts[0])

        XCTAssertEqual(player.selectedScenarioID, shapeLab.id)
        XCTAssertEqual(player.shapeFocusStage, .ideal)
        XCTAssertTrue(player.showsIdealBranch)
        XCTAssertEqual(player.playhead, ShapeFocusStage.ideal.referenceTime, accuracy: 0.000_1)
        XCTAssertEqual(player.viewMode, .positional)
    }

    func testShapeFocusProblemIsFlatAndIdealHasThreeDistinctHeights() throws {
        let scenario = try XCTUnwrap(DemoScenarios.scenario(for: .shapeLab))
        let problemHeights = scenario.formationTargets.compactMap { target in
            scenario.player(id: target.playerID)?
                .presentationPose(at: ShapeFocusStage.problem.referenceTime).position.z
        }
        let idealHeights = scenario.formationTargets.map(\.position.z)

        XCTAssertEqual(problemHeights.count, 3)
        XCTAssertLessThan(
            try XCTUnwrap(problemHeights.max()) - XCTUnwrap(problemHeights.min()),
            4
        )
        XCTAssertEqual(Set(idealHeights).count, 3)
        XCTAssertGreaterThan(
            try XCTUnwrap(idealHeights.max()) - XCTUnwrap(idealHeights.min()),
            10
        )
    }

    func testShapeFocusDashboardPreviewContainsOnlyTheTeachingUnit() throws {
        let scenario = try XCTUnwrap(DemoScenarios.scenario(for: .shapeLab))
        let problem = try XCTUnwrap(
            ShapeFocusPreviewPresentation.make(
                scenario: scenario,
                time: ShapeFocusStage.problem.referenceTime,
                stage: .problem
            )
        )

        XCTAssertEqual(problem.players.count, 4)
        XCTAssertEqual(
            Set(problem.players.map(\.id)),
            Set(scenario.formationTargets.map(\.playerID) + ["red-ldm"])
        )
        XCTAssertEqual(problem.defenderPlayerID, "red-ldm")
        XCTAssertEqual(problem.sourcePlayerID, "navy-rcm")
        XCTAssertEqual(problem.players.filter(\.isSource).map(\.track.shirtNumber), [8])
        XCTAssertEqual(problem.players.filter(\.isDefender).count, 1)
        XCTAssertTrue(problem.targetPoints.isEmpty)

        for target in scenario.formationTargets {
            let player = try XCTUnwrap(scenario.player(id: target.playerID))
            let previewPlayer = try XCTUnwrap(problem.players.first { $0.id == player.id })
            XCTAssertEqual(
                previewPlayer.position,
                player.presentationPose(at: ShapeFocusStage.problem.referenceTime).position
            )
        }

        let problemSource = try XCTUnwrap(problem.players.first(where: \.isSource))
        XCTAssertEqual(problem.ballPosition.x - problemSource.position.x, 0.55, accuracy: 0.000_1)
        XCTAssertEqual(problem.ballPosition.z - problemSource.position.z, 0.25, accuracy: 0.000_1)
    }

    func testShapeFocusDashboardIdealMovesRolesToTargetsAndKeepsBallWithEight() throws {
        let scenario = try XCTUnwrap(DemoScenarios.scenario(for: .shapeLab))
        let ideal = try XCTUnwrap(
            ShapeFocusPreviewPresentation.make(
                scenario: scenario,
                time: ShapeFocusStage.ideal.referenceTime,
                stage: .ideal
            )
        )

        XCTAssertEqual(ideal.players.count, 4)
        XCTAssertEqual(ideal.targetPoints, scenario.formationTargets.map(\.position))
        for target in scenario.formationTargets {
            let previewPlayer = try XCTUnwrap(ideal.players.first { $0.id == target.playerID })
            XCTAssertEqual(previewPlayer.position, target.position)
        }

        let source = try XCTUnwrap(ideal.players.first(where: \.isSource))
        XCTAssertEqual(source.track.shirtNumber, 8)
        XCTAssertEqual(ideal.ballPosition.x - source.position.x, 0.55, accuracy: 0.000_1)
        XCTAssertEqual(ideal.ballPosition.z - source.position.z, 0.25, accuracy: 0.000_1)
    }

    func testShapeFocusReferenceFramesUseStageConsistentCoachCues() throws {
        let scenario = try XCTUnwrap(DemoScenarios.scenario(for: .shapeLab))
        let problemCue = try XCTUnwrap(
            scenario.activeMoment(at: ShapeFocusStage.problem.referenceTime)
        )
        let idealCue = try XCTUnwrap(
            scenario.activeMoment(at: ShapeFocusStage.ideal.referenceTime)
        )

        XCTAssertEqual(problemCue.id, "shape-flat")
        XCTAssertEqual(problemCue.headline, "The unit is almost flat")
        XCTAssertEqual(idealCue.id, "shape-green")
        XCTAssertEqual(idealCue.headline, "Two lanes stay open")
    }

    func testShapeFocusSceneMakesProblemAndCorrectionVisiblyDifferent() throws {
        let scenario = try XCTUnwrap(DemoScenarios.scenario(for: .shapeLab))
        let root = PitchSceneFactory.makeMatchRoot(for: scenario)

        PitchSceneFactory.update(
            root: root,
            scenario: scenario,
            time: ShapeFocusStage.problem.referenceTime,
            viewMode: .positional,
            perspectiveID: scenario.defaultPerspectiveID,
            marks: scenario.coachMarks,
            showsLaneLens: false,
            isDrawing: false,
            positionalOriginTransform: nil,
            showsIdealBranch: false
        )

        for target in scenario.formationTargets {
            let player = try XCTUnwrap(scenario.player(id: target.playerID))
            let entity = try XCTUnwrap(root.findEntity(named: "player-\(target.playerID)"))
            let recorded = player.presentationPose(
                at: ShapeFocusStage.problem.referenceTime
            ).position
            XCTAssertEqual(entity.position.x, recorded.x, accuracy: 0.000_1)
            XCTAssertEqual(entity.position.z, recorded.z, accuracy: 0.000_1)
            XCTAssertTrue(entity.isEnabled)
        }
        XCTAssertFalse(try XCTUnwrap(root.findEntity(named: "targets-root")).isEnabled)
        XCTAssertFalse(try XCTUnwrap(root.findEntity(named: "selection-halo")).isEnabled)

        let enabledProblemOpponents = scenario.awayPlayers.filter {
            root.findEntity(named: "player-\($0.id)")?.isEnabled == true
        }
        XCTAssertEqual(enabledProblemOpponents.map(\.id), ["red-ldm"])

        let marksRoot = try XCTUnwrap(root.findEntity(named: "marks-root"))
        XCTAssertTrue(marksRoot.isEnabled)
        let visibleProblemMarks = scenario.coachMarks.filter {
            root.findEntity(named: "mark-\($0.id.uuidString)")?.isEnabled == true
        }
        XCTAssertEqual(visibleProblemMarks.map(\.kind), [.danger])

        PitchSceneFactory.update(
            root: root,
            scenario: scenario,
            time: ShapeFocusStage.ideal.referenceTime,
            viewMode: .positional,
            perspectiveID: scenario.defaultPerspectiveID,
            marks: scenario.coachMarks,
            showsLaneLens: false,
            isDrawing: false,
            positionalOriginTransform: nil,
            showsIdealBranch: true
        )

        for target in scenario.formationTargets {
            let entity = try XCTUnwrap(root.findEntity(named: "player-\(target.playerID)"))
            XCTAssertEqual(entity.position.x, target.position.x, accuracy: 0.000_1)
            XCTAssertEqual(entity.position.z, target.position.z, accuracy: 0.000_1)
            XCTAssertTrue(entity.isEnabled)
        }
        XCTAssertTrue(try XCTUnwrap(root.findEntity(named: "targets-root")).isEnabled)
        XCTAssertTrue(try XCTUnwrap(root.findEntity(named: "visualise-marker")).isEnabled)
        XCTAssertFalse(marksRoot.isEnabled)
    }

    func testJoinedPlayerCanCompareShapeLocallyWithoutBroadcastingOverCoach() throws {
        let shapeLab = try XCTUnwrap(DemoScenarios.scenario(for: .shapeLab))
        let coach = ReplayStore()
        coach.selectScenario(id: shapeLab.id, broadcast: false)
        coach.setShapeFocusStage(.ideal, broadcast: false)

        let player = ReplayStore()
        player.localRole = .player
        player.setCollaborationActive(true)
        player.applyRemote(coach.makeSnapshot())
        var playerBroadcastCount = 0
        player.onBroadcastSnapshot = { _ in playerBroadcastCount += 1 }

        player.setShapeFocusStage(.problem)

        XCTAssertEqual(player.shapeFocusStage, .problem)
        XCTAssertFalse(player.followsCoach)
        XCTAssertTrue(player.isLocallyPaused)
        XCTAssertEqual(playerBroadcastCount, 0)

        player.setFollowingCoach(true)
        XCTAssertEqual(player.shapeFocusStage, .ideal)
        XCTAssertTrue(player.followsCoach)
        XCTAssertFalse(player.isLocallyPaused)
    }

    func testPhysicalPlacementLocksShapeAndScenarioUntilCoachEndsIt() throws {
        let shapeLab = try XCTUnwrap(DemoScenarios.scenario(for: .shapeLab))
        let anchorID = UUID(uuidString: "AAAAAAAA-BBBB-4CCC-8DDD-555555555555")!
        let store = ReplayStore()
        store.selectScenario(id: shapeLab.id, broadcast: false)
        store.activateTrianglePlacement(anchorID: anchorID)
        var retiredAnchorIDs: [UUID] = []
        store.onRetirePitchAnchor = { retiredAnchorIDs.append($0) }

        store.setShapeFocusStage(.problem)
        XCTAssertEqual(store.shapeFocusStage, .ideal)
        XCTAssertEqual(store.triangleLockMode, .place)

        let otherScenarioID = try XCTUnwrap(store.scenarios.first { $0.kind != .shapeLab }?.id)
        store.selectScenario(id: otherScenarioID)
        XCTAssertEqual(store.selectedScenarioID, shapeLab.id)
        XCTAssertEqual(store.sharedPitchAnchorID, anchorID)

        store.endTrianglePlacement()
        XCTAssertEqual(retiredAnchorIDs, [anchorID])
        store.selectScenario(id: otherScenarioID)
        XCTAssertEqual(store.selectedScenarioID, otherScenarioID)
        XCTAssertNil(store.sharedPitchAnchorID)
    }

    func testCoachTrianglePlacementBroadcastIsAtomicAndPlayerCannotControlIt() throws {
        let shapeLab = try XCTUnwrap(DemoScenarios.scenario(for: .shapeLab))
        let anchorID = UUID(uuidString: "AAAAAAAA-BBBB-4CCC-8DDD-222222222222")!
        let coach = ReplayStore()
        coach.selectScenario(id: shapeLab.id, broadcast: false)
        coach.setPlaying(true, broadcast: false)
        var broadcasts: [SharedPlaybackSnapshot] = []
        coach.onBroadcastSnapshot = { broadcasts.append($0) }

        coach.activateTrianglePlacement(anchorID: anchorID)

        XCTAssertEqual(broadcasts.count, 1)
        XCTAssertEqual(broadcasts[0].triangleLockMode, .place)
        XCTAssertEqual(broadcasts[0].sharedPitchAnchorID, anchorID)
        XCTAssertEqual(broadcasts[0].viewMode, .positional)
        XCTAssertFalse(broadcasts[0].isPlaying)

        let player = ReplayStore()
        player.selectScenario(id: shapeLab.id, broadcast: false)
        player.localRole = .player
        player.activateTrianglePlacement(anchorID: anchorID)
        XCTAssertEqual(player.triangleLockMode, .visualise)
        XCTAssertNil(player.sharedPitchAnchorID)
        player.endTrianglePlacement()
        XCTAssertEqual(player.triangleLockMode, .visualise)
    }

    func testRemoteTrianglePlacementRequiresLocalConsentAndNewAnchorRefreshesIt() throws {
        let shapeLab = try XCTUnwrap(DemoScenarios.scenario(for: .shapeLab))
        let firstAnchor = UUID(uuidString: "AAAAAAAA-BBBB-4CCC-8DDD-333333333333")!
        let secondAnchor = UUID(uuidString: "AAAAAAAA-BBBB-4CCC-8DDD-444444444444")!
        let coach = ReplayStore()
        coach.selectScenario(id: shapeLab.id, broadcast: false)
        coach.activateTrianglePlacement(anchorID: firstAnchor)

        let player = ReplayStore()
        player.localRole = .player
        player.applyRemote(coach.makeSnapshot())
        XCTAssertEqual(player.triangleLockMode, .place)
        XCTAssertFalse(player.hasLocallyAcknowledgedTrianglePlacement)

        player.acknowledgeTrianglePlacementLocally()
        XCTAssertTrue(player.hasLocallyAcknowledgedTrianglePlacement)
        XCTAssertFalse(player.makeSnapshot().triangleLockMode == .visualise)

        var localConsentBroadcastCount = 0
        player.onBroadcastSnapshot = { _ in localConsentBroadcastCount += 1 }
        player.revokeTrianglePlacementConsentLocally()
        XCTAssertFalse(player.hasLocallyAcknowledgedTrianglePlacement)
        XCTAssertEqual(player.triangleLockMode, .place)
        XCTAssertEqual(player.sharedPitchAnchorID, firstAnchor)
        XCTAssertEqual(localConsentBroadcastCount, 0)
        player.acknowledgeTrianglePlacementLocally()

        coach.activateTrianglePlacement(anchorID: secondAnchor)
        player.applyRemote(coach.makeSnapshot())
        XCTAssertEqual(player.sharedPitchAnchorID, secondAnchor)
        XCTAssertFalse(player.hasLocallyAcknowledgedTrianglePlacement)
    }

    func testSharedPhysicalStationRequiresIdentityBoundFormationAssignment() throws {
        let shapeLab = try XCTUnwrap(DemoScenarios.scenario(for: .shapeLab))
        let participantID = UUID(uuidString: "AAAAAAAA-0000-4000-8000-000000000101")!
        let anchorID = UUID(uuidString: "AAAAAAAA-0000-4000-8000-000000000102")!
        let coach = ReplayStore()
        coach.selectScenario(id: shapeLab.id, broadcast: false)
        coach.activateTrianglePlacement(anchorID: anchorID)

        let player = ReplayStore()
        player.localRole = .player
        player.setCollaborationActive(true)
        player.applyRemote(coach.makeSnapshot())
        player.setLocalPerspective("navy-rb", entersLocalReview: false)

        XCTAssertNil(
            player.physicalTriangleTarget(
                participantID: participantID,
                sharedSession: true
            ),
            "Shared mode must not fall back to Player POV or the first target."
        )
        player.acknowledgeTrianglePlacementLocally(
            participantID: participantID,
            sharedSession: true
        )
        XCTAssertFalse(player.hasLocallyAcknowledgedTrianglePlacement)

        player.participantSeatAssignments[participantID] = "navy-rcm"
        XCTAssertEqual(
            player.physicalTriangleTarget(
                participantID: participantID,
                sharedSession: true
            )?.playerID,
            "navy-rcm"
        )
        player.acknowledgeTrianglePlacementLocally(
            participantID: participantID,
            sharedSession: true
        )
        XCTAssertTrue(player.hasLocallyAcknowledgedTrianglePlacement)
    }

    func testPhysicalAssignmentPrioritizationProducesUniqueTargetRoles() throws {
        let shapeLab = try XCTUnwrap(DemoScenarios.scenario(for: .shapeLab))
        let store = ReplayStore()
        store.selectScenario(id: shapeLab.id, broadcast: false)
        let participants = (1...4).map {
            UUID(uuidString: "00000000-0000-4000-8000-00000000010\($0)")!
        }
        store.participantSeatAssignments = [
            participants[0]: "navy-gk",
            participants[1]: "navy-rw",
            participants[2]: "navy-rb",
            participants[3]: "navy-lb",
        ]

        store.prioritizePhysicalTriangleAssignments()

        let assignedValues = Array(store.participantSeatAssignments.values)
        XCTAssertEqual(Set(assignedValues).count, assignedValues.count)
        XCTAssertEqual(
            Set(assignedValues).intersection(shapeLab.formationTargets.map(\.playerID)),
            Set(shapeLab.formationTargets.map(\.playerID))
        )
        XCTAssertEqual(store.participantSeatAssignments[participants[1]], "navy-rw")
        XCTAssertEqual(store.participantSeatAssignments[participants[2]], "navy-rb")
    }

    func testLocalTrianglePreviewNeverEntersSharedSnapshotAndEndsBeforeCollaboration() throws {
        let shapeLab = try XCTUnwrap(DemoScenarios.scenario(for: .shapeLab))
        let anchorID = UUID(uuidString: "AAAAAAAA-0000-4000-8000-000000000103")!
        let store = ReplayStore()
        store.selectScenario(id: shapeLab.id, broadcast: false)
        var retiredAnchorIDs: [UUID] = []
        store.onRetirePitchAnchor = { retiredAnchorIDs.append($0) }

        store.activateLocalTrianglePreview(anchorID: anchorID)

        XCTAssertTrue(store.isLocalTrianglePreview)
        XCTAssertEqual(store.triangleLockMode, .place)
        XCTAssertEqual(store.sharedPitchAnchorID, anchorID)
        XCTAssertEqual(store.makeSnapshot().triangleLockMode, .visualise)
        XCTAssertNil(store.makeSnapshot().sharedPitchAnchorID)

        store.setCollaborationActive(true)

        XCTAssertFalse(store.isLocalTrianglePreview)
        XCTAssertEqual(store.triangleLockMode, .visualise)
        XCTAssertNil(store.sharedPitchAnchorID)
        XCTAssertEqual(retiredAnchorIDs, [anchorID])
    }

    func testPhysicalPlacementRouteIsUnavailableDuringSharePlayTransitions() {
        let coordinator = LegacySnapshotCoordinator(store: ReplayStore())

        coordinator.state = .offline
        XCTAssertEqual(coordinator.physicalPlacementRoute, .localPreview)
        coordinator.state = .preparing
        XCTAssertNil(coordinator.physicalPlacementRoute)
        coordinator.state = .waiting
        XCTAssertNil(coordinator.physicalPlacementRoute)
        coordinator.state = .joined
        XCTAssertEqual(coordinator.physicalPlacementRoute, .sharedSquad)
        coordinator.state = .unavailable("test")
        XCTAssertNil(coordinator.physicalPlacementRoute)
    }

    func testPositionCorrectionRotatesIntoWearerHeading() {
        let facingPitchForward = LocalPitchAnchorCoordinator.HorizontalHeadsetPose(
            x: 0,
            z: 0,
            yawRadians: 0,
            sampledAt: 1
        )
        let forward = LocalPitchAnchorCoordinator.wearerRelativeDisplacement(
            from: facingPitchForward,
            targetX: 1,
            targetZ: -2
        )
        XCTAssertEqual(forward.rightMetres, 1, accuracy: 0.000_1)
        XCTAssertEqual(forward.forwardMetres, 2, accuracy: 0.000_1)

        let facingPitchRight = LocalPitchAnchorCoordinator.HorizontalHeadsetPose(
            x: 0,
            z: 0,
            yawRadians: .pi / 2,
            sampledAt: 2
        )
        let rotated = LocalPitchAnchorCoordinator.wearerRelativeDisplacement(
            from: facingPitchRight,
            targetX: 2,
            targetZ: 0
        )
        XCTAssertEqual(rotated.rightMetres, 0, accuracy: 0.000_1)
        XCTAssertEqual(rotated.forwardMetres, 2, accuracy: 0.000_1)
        XCTAssertEqual(rotated.distanceMetres, 2, accuracy: 0.000_1)
    }

    func testRemotePhysicalPlacementOverridesIncompatibleLocalComfortStateSafely() throws {
        let shapeLab = try XCTUnwrap(DemoScenarios.scenario(for: .shapeLab))
        let anchorID = UUID(uuidString: "AAAAAAAA-BBBB-4CCC-8DDD-666666666666")!
        let coach = ReplayStore()
        coach.selectScenario(id: shapeLab.id, broadcast: false)
        coach.activateTrianglePlacement(anchorID: anchorID)

        let player = ReplayStore()
        player.localRole = .player
        player.setCollaborationActive(true)
        player.setFollowingCoach(false)
        XCTAssertNotEqual(player.selectedScenarioID, shapeLab.id)

        player.applyRemote(coach.makeSnapshot())

        XCTAssertEqual(player.selectedScenarioID, shapeLab.id)
        XCTAssertEqual(player.triangleLockMode, .place)
        XCTAssertEqual(player.shapeFocusStage, .ideal)
        XCTAssertEqual(player.viewMode, .positional)
        XCTAssertEqual(player.sharedPitchAnchorID, anchorID)
        XCTAssertFalse(player.hasLocallyAcknowledgedTrianglePlacement)
        XCTAssertTrue(player.isLocallyPaused)
        XCTAssertFalse(player.isPlaying)
    }

    func testPlaceSnapshotWithoutAnchorFallsBackToVisualise() throws {
        let shapeLab = try XCTUnwrap(DemoScenarios.scenario(for: .shapeLab))
        let base = ReplayStore()
        base.selectScenario(id: shapeLab.id, broadcast: false)
        let snapshot = SharedPlaybackSnapshot(
            scenarioID: shapeLab.id,
            playhead: 4,
            isPlaying: true,
            playbackRate: 2,
            viewMode: .positional,
            coachFocusPerspectiveID: nil,
            coachLockEnabled: false,
            marks: shapeLab.coachMarks,
            seatAssignments: [:],
            showsLaneLens: false,
            sharedPitchAnchorID: nil,
            triangleLockMode: .place
        )

        base.localRole = .player
        base.applyRemote(snapshot)
        XCTAssertEqual(base.triangleLockMode, .visualise)
        XCTAssertFalse(base.hasLocallyAcknowledgedTrianglePlacement)
    }

    func testTriangleLayoutGuaranteesSafePlaceSpacingAndCompactVisualiseFootprint() throws {
        let scenario = try XCTUnwrap(DemoScenarios.scenario(for: .shapeLab))
        let targets = scenario.formationTargets
        let placeScale = TriangleLockLayout.placeScale(for: targets)
        XCTAssertEqual(placeScale, 1.5 / sqrt(Float(52)), accuracy: 0.000_1)

        for firstIndex in targets.indices {
            for secondIndex in targets.indices where secondIndex > firstIndex {
                let physicalDistance = ReplayGeometry.distance(
                    targets[firstIndex].position,
                    targets[secondIndex].position
                ) * placeScale
                XCTAssertGreaterThanOrEqual(
                    physicalDistance,
                    TriangleLockLayout.placeMinimumCentreSeparation - 0.000_1
                )
                XCTAssertGreaterThan(
                    physicalDistance,
                    TriangleLockLayout.placeTolerance * 2
                )
            }
        }

        let xValues = targets.map(\.position.x)
        let visualiseWidth = ((xValues.max() ?? 0) - (xValues.min() ?? 0))
            * TriangleLockLayout.visualiseScale
        XCTAssertLessThan(visualiseWidth, 0.70)
    }

    func testTriangleSceneUsesTabletopFallbackUntilPhysicalPlacementIsReady() throws {
        let scenario = try XCTUnwrap(DemoScenarios.scenario(for: .shapeLab))
        let root = PitchSceneFactory.makeMatchRoot(for: scenario)

        PitchSceneFactory.update(
            root: root,
            scenario: scenario,
            time: 8,
            viewMode: .positional,
            perspectiveID: scenario.defaultPerspectiveID,
            marks: scenario.coachMarks,
            showsLaneLens: false,
            isDrawing: false,
            positionalOriginTransform: nil,
            triangleLockMode: .place,
            isTrianglePlacementReady: false,
            showsIdealBranch: true
        )

        XCTAssertEqual(root.scale.x, TriangleLockLayout.visualiseScale, accuracy: 0.000_1)
        XCTAssertEqual(root.position.y, TriangleLockLayout.visualiseHeight, accuracy: 0.000_1)
        XCTAssertTrue(try XCTUnwrap(root.findEntity(named: "visualise-marker")).isEnabled)
        XCTAssertFalse(try XCTUnwrap(root.findEntity(named: "place-marker")).isEnabled)

        PitchSceneFactory.update(
            root: root,
            scenario: scenario,
            time: 8,
            viewMode: .positional,
            perspectiveID: scenario.defaultPerspectiveID,
            marks: scenario.coachMarks,
            showsLaneLens: false,
            isDrawing: false,
            positionalOriginTransform: matrix_identity_float4x4,
            triangleLockMode: .place,
            isTrianglePlacementReady: true,
            showsIdealBranch: true
        )

        XCTAssertEqual(
            root.scale.x,
            TriangleLockLayout.placeScale(for: scenario.formationTargets),
            accuracy: 0.000_1
        )
        XCTAssertFalse(try XCTUnwrap(root.findEntity(named: "visualise-marker")).isEnabled)
        XCTAssertTrue(try XCTUnwrap(root.findEntity(named: "place-marker")).isEnabled)
        XCTAssertFalse(try XCTUnwrap(root.findEntity(named: "players-root")).children.contains { $0.isEnabled })
        XCTAssertFalse(try XCTUnwrap(root.findEntity(named: "ball")).isEnabled)
        XCTAssertFalse(try XCTUnwrap(root.findEntity(named: "marks-root")).isEnabled)
    }

    func testScenarioResetRestoresFixtureStateAndLaneLensDefaults() throws {
        let store = ReplayStore()
        let laneScenario = try XCTUnwrap(DemoScenarios.scenario(for: .passingChannels))
        store.selectScenario(id: laneScenario.id, broadcast: false)

        store.seek(to: 19, broadcast: false)
        store.setPlaying(true, broadcast: false)
        store.setViewMode(.touchline, broadcast: false)
        store.setLocalPerspective("red-lb")
        store.broadcastPerspective("navy-rb")
        store.marks.append(
            CoachMark(
                id: UUID(uuidString: "00000000-0000-4000-8000-000000009999")!,
                kind: .danger,
                start: .zero,
                end: PitchPoint(x: 2, z: 3),
                label: "Temporary"
            )
        )
        store.beginDrawing(.space)
        XCTAssertNil(store.registerPitchTap(PitchPoint(x: 7, z: 8)))
        store.showsLaneLens = false

        store.resetScenario()

        XCTAssertEqual(store.selectedScenarioID, laneScenario.id)
        XCTAssertEqual(store.playhead, 0)
        XCTAssertFalse(store.isPlaying)
        XCTAssertEqual(store.viewMode, laneScenario.defaultViewMode)
        XCTAssertEqual(store.localPerspectiveID, laneScenario.defaultPerspectiveID)
        XCTAssertNil(store.coachFocusPerspectiveID)
        XCTAssertFalse(store.coachLockEnabled)
        XCTAssertEqual(store.marks, laneScenario.coachMarks)
        XCTAssertEqual(store.selectedTool, .run)
        XCTAssertNil(store.pendingDrawStart)
        XCTAssertFalse(store.isDrawing)
        XCTAssertEqual(store.shapeFocusStage, .problem)
        XCTAssertFalse(store.showsIdealBranch)
        XCTAssertTrue(store.showsLaneLens)
        XCTAssertEqual(store.statusMessage, laneScenario.coachPrompt)
    }

    func testCoachCanFocusSquadAndReleaseBackToLocalPerspectives() {
        let store = ReplayStore()
        store.setLocalPerspective("navy-rb")
        store.setPlaying(true, broadcast: false)

        store.broadcastPerspective("navy-rw")

        XCTAssertFalse(store.isPlaying)
        XCTAssertEqual(store.coachFocusPerspectiveID, "navy-rw")
        XCTAssertTrue(store.coachLockEnabled)
        XCTAssertTrue(store.followsCoach)
        XCTAssertEqual(store.viewMode, .firstPerson)
        XCTAssertEqual(store.activePerspectiveID, "navy-rw")

        // Coach focus changes the coach's own review lens as well as the squad
        // broadcast. Follow/pause is a player-only interaction in the UI.
        store.setFollowingCoach(false)
        XCTAssertEqual(store.activePerspectiveID, "navy-rw")
        store.setFollowingCoach(true)
        XCTAssertEqual(store.activePerspectiveID, "navy-rw")

        store.releaseSquad()
        XCTAssertNil(store.coachFocusPerspectiveID)
        XCTAssertFalse(store.coachLockEnabled)
        XCTAssertEqual(store.activePerspectiveID, "navy-rw")

        store.localRole = .player
        store.setViewMode(.tacticalTable, broadcast: false)
        store.setPlaying(true, broadcast: false)
        store.broadcastPerspective("red-lb")
        XCTAssertNil(store.coachFocusPerspectiveID)
        XCTAssertFalse(store.coachLockEnabled)
        XCTAssertEqual(store.viewMode, .tacticalTable)
        XCTAssertTrue(store.isPlaying)
    }

    func testTwoPitchTapsCreateOneAnnotationAndUndoRemovesIt() throws {
        let store = ReplayStore()
        let fixtureMarkCount = store.marks.count
        var broadcasts: [SharedPlaybackSnapshot] = []
        store.onBroadcastSnapshot = { broadcasts.append($0) }
        store.seek(to: 12.25, broadcast: false)
        store.setPlaying(true, broadcast: false)

        store.beginDrawing(.pass)
        XCTAssertFalse(store.isPlaying)
        XCTAssertTrue(store.isDrawing)

        let start = PitchPoint(x: 8, z: 9)
        let end = PitchPoint(x: 18, z: 24)
        XCTAssertNil(store.registerPitchTap(start))
        XCTAssertEqual(store.pendingDrawStart, start)
        XCTAssertEqual(store.marks.count, fixtureMarkCount)
        XCTAssertEqual(broadcasts.count, 1)
        XCTAssertFalse(try XCTUnwrap(broadcasts.last).isPlaying)

        let mark = try XCTUnwrap(store.registerPitchTap(end))
        XCTAssertEqual(mark.kind, .pass)
        XCTAssertEqual(mark.start, start)
        XCTAssertEqual(mark.end, end)
        XCTAssertEqual(mark.label, "Release the lane")
        XCTAssertEqual(mark.revealTime, 12.25, accuracy: 0.000_1)
        XCTAssertEqual(
            try XCTUnwrap(mark.hideTime),
            12.25 + ReplayStore.coachAnnotationDisplayDuration,
            accuracy: 0.000_1
        )
        XCTAssertEqual(mark.author, "Coach")
        XCTAssertEqual(store.marks.last, mark)
        XCTAssertEqual(store.marks.count, fixtureMarkCount + 1)
        XCTAssertNil(store.pendingDrawStart)
        XCTAssertFalse(store.isDrawing)
        XCTAssertEqual(broadcasts.count, 2)
        XCTAssertEqual(broadcasts.last?.marks.last, mark)

        store.undoMark()
        XCTAssertEqual(store.marks.count, fixtureMarkCount)
        XCTAssertEqual(broadcasts.count, 3)
        XCTAssertEqual(broadcasts.last?.marks, store.marks)
    }

    func testUndoAndTargetedDeletePreserveAuthoredMatchOverlays() throws {
        let store = ReplayStore()
        let authoredMarks = store.selectedScenario.coachMarks
        var broadcasts: [SharedPlaybackSnapshot] = []
        store.onBroadcastSnapshot = { broadcasts.append($0) }

        store.undoMark()
        XCTAssertEqual(store.marks, authoredMarks)
        XCTAssertTrue(broadcasts.isEmpty)

        store.beginDrawing(.pass)
        XCTAssertNil(store.registerPitchTap(PitchPoint(x: 2, z: 3)))
        let first = try XCTUnwrap(store.registerPitchTap(PitchPoint(x: 8, z: 12)))
        store.beginDrawing(.run)
        XCTAssertNil(store.registerPitchTap(PitchPoint(x: -4, z: 5)))
        let second = try XCTUnwrap(store.registerPitchTap(PitchPoint(x: 1, z: 14)))

        XCTAssertFalse(store.removeCoachMark(id: try XCTUnwrap(authoredMarks.first?.id)))
        XCTAssertTrue(store.removeCoachMark(id: first.id))
        XCTAssertFalse(store.marks.contains(where: { $0.id == first.id }))
        XCTAssertTrue(store.marks.contains(where: { $0.id == second.id }))
        XCTAssertTrue(authoredMarks.allSatisfy { store.marks.contains($0) })

        store.undoMark()
        XCTAssertEqual(store.marks, authoredMarks + [first, second], "Undo must restore the erased mark")
        store.clearMarks()
        XCTAssertEqual(store.marks, authoredMarks)
    }

    func testRetimeCoachMarkPreservesGeometryAndVisibilityWindow() throws {
        let store = ReplayStore()
        var broadcasts: [SharedPlaybackSnapshot] = []
        store.onBroadcastSnapshot = { broadcasts.append($0) }
        store.seek(to: 4.25, broadcast: false)
        store.beginDrawing(.pass)
        XCTAssertNil(store.registerPitchTap(PitchPoint(x: 3, z: 6)))
        let original = try XCTUnwrap(
            store.registerPitchTap(PitchPoint(x: 11, z: 18))
        )
        let originalWindow = try XCTUnwrap(original.hideTime) - original.revealTime
        broadcasts.removeAll()

        XCTAssertTrue(store.retimeCoachMark(id: original.id, to: 20))

        let shifted = try XCTUnwrap(store.marks.first { $0.id == original.id })
        XCTAssertEqual(shifted.id, original.id)
        XCTAssertEqual(shifted.kind, original.kind)
        XCTAssertEqual(shifted.start, original.start)
        XCTAssertEqual(shifted.end, original.end)
        XCTAssertEqual(shifted.label, original.label)
        XCTAssertEqual(shifted.author, original.author)
        XCTAssertEqual(shifted.playerID, original.playerID)
        XCTAssertEqual(shifted.revealTime, 20, accuracy: 0.000_1)
        XCTAssertEqual(
            try XCTUnwrap(shifted.hideTime) - shifted.revealTime,
            originalWindow,
            accuracy: 0.000_1
        )
        XCTAssertEqual(broadcasts.count, 1)
        XCTAssertEqual(broadcasts.last?.marks.first { $0.id == original.id }, shifted)

        let acceptedState = store.marks
        let acceptedBroadcastCount = broadcasts.count
        XCTAssertFalse(store.retimeCoachMark(id: original.id, to: .nan))
        XCTAssertFalse(
            store.retimeCoachMark(
                id: original.id,
                to: store.selectedScenario.duration + 0.01
            )
        )
        XCTAssertFalse(
            store.retimeCoachMark(
                id: try XCTUnwrap(store.selectedScenario.coachMarks.first?.id),
                to: 10
            )
        )
        XCTAssertEqual(store.marks, acceptedState)
        XCTAssertEqual(broadcasts.count, acceptedBroadcastCount)
    }

    func testCoachMarkDurationAndGeometryEditsAreBoundedAndBroadcastOnce() throws {
        let store = ReplayStore()
        store.seek(to: 6, broadcast: false)
        store.beginDrawing(.pass)
        XCTAssertNil(store.registerPitchTap(PitchPoint(x: 2, z: 3)))
        let original = try XCTUnwrap(
            store.registerPitchTap(PitchPoint(x: 8, z: 12))
        )
        var broadcasts: [SharedPlaybackSnapshot] = []
        store.onBroadcastSnapshot = { broadcasts.append($0) }

        XCTAssertTrue(store.setCoachMarkDuration(id: original.id, duration: 3))
        var edited = try XCTUnwrap(store.marks.first { $0.id == original.id })
        XCTAssertEqual(edited.revealTime, 6, accuracy: 0.000_1)
        XCTAssertEqual(try XCTUnwrap(edited.hideTime), 9, accuracy: 0.000_1)
        XCTAssertEqual(broadcasts.count, 1)

        let newStart = PitchPoint(x: -4, z: 7)
        let newEnd = PitchPoint(x: 3, z: 19)
        XCTAssertTrue(
            store.updateCoachMarkGeometry(
                id: original.id,
                start: newStart,
                end: newEnd,
                broadcast: false
            )
        )
        XCTAssertEqual(broadcasts.count, 1)
        XCTAssertTrue(
            store.updateCoachMarkGeometry(
                id: original.id,
                start: newStart,
                end: newEnd
            )
        )
        edited = try XCTUnwrap(store.marks.first { $0.id == original.id })
        XCTAssertEqual(edited.start, newStart)
        XCTAssertEqual(edited.end, newEnd)
        XCTAssertEqual(edited.label, original.label)
        XCTAssertEqual(edited.hideTime, 9)
        XCTAssertEqual(broadcasts.count, 2)

        XCTAssertTrue(store.setCoachMarkDuration(id: original.id, duration: nil))
        edited = try XCTUnwrap(store.marks.first { $0.id == original.id })
        XCTAssertNil(edited.hideTime)
        XCTAssertEqual(broadcasts.count, 3)

        let accepted = store.marks
        XCTAssertFalse(store.setCoachMarkDuration(id: original.id, duration: .nan))
        XCTAssertFalse(store.setCoachMarkDuration(id: original.id, duration: 0.1))
        XCTAssertFalse(
            store.updateCoachMarkGeometry(
                id: original.id,
                start: PitchPoint(x: .infinity, z: 1),
                end: newEnd
            )
        )
        XCTAssertEqual(store.marks, accepted)
        XCTAssertEqual(broadcasts.count, 3)
    }

    func testPitchAnnotationRejectsNonFiniteAndOutOfBoundsTaps() {
        let store = ReplayStore()
        let originalMarks = store.marks
        store.beginDrawing(.pass)

        XCTAssertNil(store.registerPitchTap(PitchPoint(x: .nan, z: 2)))
        XCTAssertNil(store.registerPitchTap(PitchPoint(x: 201, z: 2)))
        XCTAssertNil(store.pendingDrawStart)
        XCTAssertEqual(store.marks, originalMarks)
        XCTAssertTrue(store.isDrawing)
    }

    func testPitchAnnotationRechecksCapacityBeforeSecondTap() {
        let store = ReplayStore()
        store.beginDrawing(.run)
        XCTAssertNil(store.registerPitchTap(PitchPoint(x: 1, z: 2)))

        while store.marks.count < ReplayStore.maximumSharedCoachMarks {
            store.marks.append(
                CoachMark(
                    kind: .space,
                    start: .zero,
                    end: PitchPoint(x: 1, z: 1),
                    label: "Concurrent annotation"
                )
            )
        }
        let marksAtCapacity = store.marks

        XCTAssertNil(store.registerPitchTap(PitchPoint(x: 8, z: 12)))
        XCTAssertEqual(store.marks, marksAtCapacity)
        XCTAssertNil(store.pendingDrawStart)
        XCTAssertFalse(store.isDrawing)
    }

    func testEveryPitchMarkKindStillRequiresTwoPitchTaps() throws {
        let pitchMarkKinds: [CoachMarkKind] = [.run, .pass, .danger, .space]
        let start = PitchPoint(x: 4, z: 7)
        let end = PitchPoint(x: 11, z: 19)

        for kind in pitchMarkKinds {
            let store = ReplayStore()
            let fixtureMarkCount = store.marks.count

            store.beginDrawing(kind)
            XCTAssertNil(store.registerPitchTap(start), "\(kind) completed after only one pitch tap")
            XCTAssertEqual(store.pendingDrawStart, start)
            XCTAssertEqual(store.marks.count, fixtureMarkCount)

            let mark = try XCTUnwrap(store.registerPitchTap(end))
            XCTAssertEqual(mark.kind, kind)
            XCTAssertEqual(mark.start, start)
            XCTAssertEqual(mark.end, end)
            XCTAssertNil(mark.playerID)
            XCTAssertEqual(store.marks.count, fixtureMarkCount + 1)
            XCTAssertNil(store.pendingDrawStart)
            XCTAssertFalse(store.isDrawing)
        }
    }

    func testPlayerLabelUsesOnePlayerTapAtCurrentTimestampAndBroadcasts() throws {
        let store = ReplayStore()
        let fixtureMarkCount = store.marks.count
        let player = try XCTUnwrap(store.selectedScenario.player(id: "navy-rw"))
        var broadcasts: [SharedPlaybackSnapshot] = []
        store.onBroadcastSnapshot = { broadcasts.append($0) }
        store.seek(to: 12.25, broadcast: false)
        store.setPlaying(true, broadcast: false)

        store.beginDrawing(.playerLabel)
        XCTAssertFalse(store.isPlaying)
        XCTAssertTrue(store.isDrawing)
        XCTAssertNil(store.pendingDrawStart)

        XCTAssertNil(store.registerPitchTap(PitchPoint(x: 8, z: 9)))
        XCTAssertNil(store.pendingDrawStart)
        XCTAssertEqual(store.marks.count, fixtureMarkCount)
        XCTAssertEqual(broadcasts.count, 1)

        let mark = try XCTUnwrap(store.labelPlayer(player.id))
        let expectedPosition = player.presentationPose(at: 12.25).position
        XCTAssertEqual(mark.kind, .playerLabel)
        XCTAssertEqual(mark.playerID, player.id)
        XCTAssertEqual(mark.start, expectedPosition)
        XCTAssertEqual(mark.end, expectedPosition)
        XCTAssertEqual(mark.label, "#\(player.shirtNumber) \(player.displayName) · \(player.positionCode)")
        XCTAssertEqual(mark.revealTime, 12.25, accuracy: 0.000_1)
        XCTAssertEqual(
            try XCTUnwrap(mark.hideTime),
            12.25 + ReplayStore.coachAnnotationDisplayDuration,
            accuracy: 0.000_1
        )
        XCTAssertEqual(mark.author, "Coach")
        XCTAssertEqual(store.marks.last, mark)
        XCTAssertEqual(store.marks.count, fixtureMarkCount + 1)
        XCTAssertNil(store.pendingDrawStart)
        XCTAssertFalse(store.isDrawing)
        XCTAssertEqual(broadcasts.count, 2)
        XCTAssertEqual(broadcasts.last?.marks.last, mark)
    }

    func testCancelDrawingFullyClearsPitchAndPlayerLabelDraftState() {
        let store = ReplayStore()
        store.beginDrawing(.pass)
        XCTAssertNil(store.registerPitchTap(PitchPoint(x: 3, z: 5)))

        store.cancelDrawing()

        XCTAssertEqual(store.selectedTool, .run)
        XCTAssertNil(store.pendingDrawStart)
        XCTAssertFalse(store.isDrawing)

        store.beginDrawing(.playerLabel)
        store.cancelDrawing()

        XCTAssertEqual(store.selectedTool, .run)
        XCTAssertNil(store.pendingDrawStart)
        XCTAssertFalse(store.isDrawing)
    }

    func testPlayerRoleCannotDrawOrUndoCoachAnnotations() {
        let store = ReplayStore()
        let fixtureMarks = store.marks
        store.localRole = .player

        store.beginDrawing(.danger)
        XCTAssertFalse(store.isDrawing)
        XCTAssertNil(store.registerPitchTap(PitchPoint(x: 1, z: 2)))
        XCTAssertNil(store.labelPlayer("navy-rw"))

        store.undoMark()
        XCTAssertEqual(store.marks, fixtureMarks)

        store.localRole = .coach
        XCTAssertNil(store.labelPlayer("missing-player"))
        XCTAssertEqual(store.marks, fixtureMarks)
    }

    func testSharedPitchAnchorIsCoachOwnedAndPhysicalPlacementRoundTripsInPlaybackState() throws {
        let anchorID = UUID(uuidString: "DDDDDDDD-EEEE-4FFF-8000-BBBBBBBBBBBB")!
        let shapeLab = try XCTUnwrap(DemoScenarios.scenario(for: .shapeLab))
        let coachStore = ReplayStore()
        coachStore.selectScenario(id: shapeLab.id, broadcast: false)
        var broadcasts: [SharedPlaybackSnapshot] = []
        coachStore.onBroadcastSnapshot = { broadcasts.append($0) }

        coachStore.activateTrianglePlacement(anchorID: anchorID)

        XCTAssertEqual(coachStore.sharedPitchAnchorID, anchorID)
        XCTAssertEqual(broadcasts.last?.sharedPitchAnchorID, anchorID)

        let playerStore = ReplayStore()
        playerStore.localRole = .player
        playerStore.setCollaborationActive(true)
        playerStore.applyRemote(coachStore.makeSnapshot())
        XCTAssertEqual(playerStore.sharedPitchAnchorID, anchorID)
        XCTAssertEqual(playerStore.triangleLockMode, .place)
        XCTAssertFalse(playerStore.hasLocallyAcknowledgedTrianglePlacement)

        playerStore.setSharedPitchAnchor(nil)
        XCTAssertEqual(playerStore.sharedPitchAnchorID, anchorID)
    }

    func testUnexpectedSelectedAnchorRemovalRestoresSafeTabletopState() throws {
        let shapeLab = try XCTUnwrap(DemoScenarios.scenario(for: .shapeLab))
        let anchorID = UUID(uuidString: "DDDDDDDD-EEEE-4FFF-8000-CCCCCCCCCCCC")!
        let coach = ReplayStore()
        coach.selectScenario(id: shapeLab.id, broadcast: false)
        coach.activateTrianglePlacement(anchorID: anchorID)
        coach.acknowledgeTrianglePlacementLocally()
        var broadcasts: [SharedPlaybackSnapshot] = []
        coach.onBroadcastSnapshot = { broadcasts.append($0) }

        coach.handleSharedPitchAnchorRemoval(anchorID)

        XCTAssertEqual(coach.triangleLockMode, .visualise)
        XCTAssertEqual(coach.shapeFocusStage, .ideal)
        XCTAssertEqual(coach.viewMode, .positional)
        XCTAssertNil(coach.sharedPitchAnchorID)
        XCTAssertFalse(coach.hasLocallyAcknowledgedTrianglePlacement)
        XCTAssertFalse(coach.isPlaying)
        XCTAssertEqual(broadcasts.count, 1)
        XCTAssertEqual(broadcasts[0].triangleLockMode, .visualise)
        XCTAssertNil(broadcasts[0].sharedPitchAnchorID)
    }

    func testLocalComfortPauseCachesCoachTimelineUntilResume() {
        let coachStore = ReplayStore()
        coachStore.seek(to: 8, broadcast: false)
        coachStore.setPlaying(true, broadcast: false)

        let playerStore = ReplayStore()
        playerStore.localRole = .player
        playerStore.setCollaborationActive(true)
        playerStore.applyRemote(coachStore.makeSnapshot())
        XCTAssertEqual(playerStore.playhead, 8)
        XCTAssertTrue(playerStore.isPlaying)
        let viewBeforeComfortPause = playerStore.viewMode

        playerStore.setFollowingCoach(false)
        coachStore.seek(to: 21, broadcast: false)
        coachStore.setViewMode(.tacticalTable, broadcast: false)
        playerStore.applyRemote(coachStore.makeSnapshot())

        XCTAssertEqual(playerStore.playhead, 8)
        XCTAssertEqual(playerStore.viewMode, viewBeforeComfortPause)
        XCTAssertTrue(playerStore.isLocallyPaused)

        playerStore.setFollowingCoach(true)

        XCTAssertEqual(playerStore.playhead, 21)
        XCTAssertEqual(playerStore.viewMode, .tacticalTable)
        XCTAssertTrue(playerStore.isPlaying)
        XCTAssertFalse(playerStore.isLocallyPaused)
    }

    func testClosingSquadRoomClearsSessionOnlyState() {
        let store = ReplayStore()
        let anchorID = UUID(uuidString: "EEEEEEEE-FFFF-4000-8000-CCCCCCCCCCCC")!
        store.setSharedPitchAnchor(anchorID)
        store.participantSeatAssignments[UUID()] = "navy-rw"
        store.broadcastPerspective("navy-rw")
        store.localRole = .player
        store.setCollaborationActive(true)
        store.setFollowingCoach(false)
        store.selectedTool = .space
        store.pendingDrawStart = PitchPoint(x: 2, z: 4)
        store.isDrawing = true

        store.resetCollaborationState()

        XCTAssertEqual(store.localRole, .coach)
        XCTAssertFalse(store.isCollaborationActive)
        XCTAssertTrue(store.participantSeatAssignments.isEmpty)
        XCTAssertNil(store.sharedPitchAnchorID)
        XCTAssertNil(store.coachFocusPerspectiveID)
        XCTAssertFalse(store.coachLockEnabled)
        XCTAssertTrue(store.followsCoach)
        XCTAssertFalse(store.isLocallyPaused)
        XCTAssertFalse(store.isPlaying)
        XCTAssertEqual(store.selectedTool, .run)
        XCTAssertNil(store.pendingDrawStart)
        XCTAssertFalse(store.isDrawing)
    }

    func testRemoteSnapshotValidationIsAtomicAndSanitizesUnsafeFields() {
        let store = ReplayStore()
        store.localRole = .player
        store.setCollaborationActive(true)
        store.seek(to: 6.25, broadcast: false)
        store.setPlaybackRate(0.75, broadcast: false)
        store.selectedTool = .pass
        store.pendingDrawStart = PitchPoint(x: 1, z: 2)
        store.isDrawing = true
        let original = store.makeSnapshot()

        let unknownScenarioSnapshot = SharedPlaybackSnapshot(
            scenarioID: "missing-scenario",
            playhead: 20,
            isPlaying: true,
            playbackRate: 2,
            viewMode: .touchline,
            coachFocusPerspectiveID: "navy-rw",
            coachLockEnabled: true,
            marks: [],
            seatAssignments: [UUID(): "navy-rw"],
            showsLaneLens: true,
            sharedPitchAnchorID: UUID(),
            triangleLockMode: .place
        )
        store.applyRemote(unknownScenarioSnapshot)
        XCTAssertEqual(store.makeSnapshot(), original)
        XCTAssertEqual(store.selectedTool, .pass)
        XCTAssertEqual(store.pendingDrawStart, PitchPoint(x: 1, z: 2))
        XCTAssertTrue(store.isDrawing)

        let validMark = CoachMark(
            id: UUID(uuidString: "11111111-2222-4333-8444-555555555551")!,
            kind: .pass,
            start: PitchPoint(x: 3, z: 4),
            end: PitchPoint(x: 8, z: 12),
            label: "Valid lane",
            revealTime: 5
        )
        let invalidMark = CoachMark(
            id: UUID(uuidString: "11111111-2222-4333-8444-555555555552")!,
            kind: .run,
            start: PitchPoint(x: .nan, z: 1),
            end: PitchPoint(x: 2, z: 3),
            label: "Invalid geometry",
            revealTime: .infinity
        )
        let invalidWindowMark = CoachMark(
            id: UUID(uuidString: "11111111-2222-4333-8444-555555555557")!,
            kind: .space,
            start: PitchPoint(x: 4, z: 5),
            end: PitchPoint(x: 8, z: 11),
            label: "Backwards window",
            revealTime: 9,
            hideTime: 8
        )
        let validPlayerLabel = CoachMark(
            id: UUID(uuidString: "11111111-2222-4333-8444-555555555553")!,
            kind: .playerLabel,
            start: PitchPoint(x: 14, z: 22),
            end: PitchPoint(x: 14, z: 22),
            label: "#7 Luca Hale • RW",
            revealTime: 6,
            playerID: "navy-rw"
        )
        let invalidPlayerLabel = CoachMark(
            id: UUID(uuidString: "11111111-2222-4333-8444-555555555554")!,
            kind: .playerLabel,
            start: PitchPoint(x: 14, z: 22),
            end: PitchPoint(x: 14, z: 22),
            label: "Unknown player",
            revealTime: 6,
            playerID: "missing-player"
        )
        let missingTargetPlayerLabel = CoachMark(
            id: UUID(uuidString: "11111111-2222-4333-8444-555555555555")!,
            kind: .playerLabel,
            start: PitchPoint(x: 14, z: 22),
            end: PitchPoint(x: 14, z: 22),
            label: "Missing target",
            revealTime: 6
        )
        let firstParticipant = UUID(uuidString: "00000000-0000-4000-8000-000000000001")!
        let duplicateParticipant = UUID(uuidString: "00000000-0000-4000-8000-000000000002")!
        let invalidParticipant = UUID(uuidString: "00000000-0000-4000-8000-000000000003")!
        let unsafeSnapshot = SharedPlaybackSnapshot(
            scenarioID: store.selectedScenarioID,
            playhead: .nan,
            isPlaying: true,
            playbackRate: .infinity,
            viewMode: .touchline,
            coachFocusPerspectiveID: "missing-player",
            coachLockEnabled: true,
            marks: [
                validMark,
                invalidMark,
                invalidWindowMark,
                validPlayerLabel,
                invalidPlayerLabel,
                missingTargetPlayerLabel,
            ],
            seatAssignments: [
                firstParticipant: "navy-rw",
                duplicateParticipant: "navy-rw",
                invalidParticipant: "red-lb",
            ],
            showsLaneLens: true,
            sharedPitchAnchorID: nil,
            triangleLockMode: .visualise
        )

        store.applyRemote(unsafeSnapshot)

        XCTAssertEqual(store.playhead, 6.25, accuracy: 0.000_1)
        XCTAssertEqual(store.playbackRate, 0.75, accuracy: 0.000_1)
        XCTAssertTrue(store.playhead.isFinite)
        XCTAssertTrue(store.playbackRate.isFinite)
        XCTAssertNil(store.coachFocusPerspectiveID)
        XCTAssertFalse(store.coachLockEnabled)
        XCTAssertEqual(store.marks, [validMark, validPlayerLabel])
        XCTAssertEqual(store.participantSeatAssignments, [firstParticipant: "navy-rw"])
        XCTAssertFalse(store.showsLaneLens)
        XCTAssertEqual(store.selectedTool, .run)
        XCTAssertNil(store.pendingDrawStart)
        XCTAssertFalse(store.isDrawing)

        store.setFollowingCoach(false)
        store.seek(to: 14, broadcast: false)
        store.setPlaybackRate(2, broadcast: false)
        store.setFollowingCoach(true)
        XCTAssertEqual(store.playhead, 6.25, accuracy: 0.000_1)
        XCTAssertEqual(store.playbackRate, 0.75, accuracy: 0.000_1)
    }

    func testTerminalRemoteSnapshotCannotRestartAnyExperience() {
        let receiver = ReplayStore()
        receiver.localRole = .player
        receiver.setCollaborationActive(true)

        for scenario in DemoScenarios.all {
            let sender = ReplayStore()
            sender.selectScenario(id: scenario.id, broadcast: false)
            sender.seek(to: scenario.duration, broadcast: false)
            sender.setPlaying(true, broadcast: false)

            XCTAssertTrue(receiver.applyRemote(sender.makeSnapshot()), scenario.id)
            XCTAssertEqual(receiver.selectedScenarioID, scenario.id)
            XCTAssertEqual(receiver.playhead, scenario.duration, accuracy: 0.000_1)
            XCTAssertFalse(receiver.isPlaying, scenario.id)
        }
    }

    func testRemoteSnapshotDeduplicatesAndBoundsRenderedAnnotations() throws {
        let store = ReplayStore()
        store.localRole = .player
        store.setCollaborationActive(true)
        let duplicateID = UUID(uuidString: "11111111-2222-4333-8444-555555555550")!
        let duplicate = CoachMark(
            id: duplicateID,
            kind: .pass,
            start: PitchPoint(x: 1, z: 2),
            end: PitchPoint(x: 3, z: 4),
            label: "Keep first",
            revealTime: 1
        )
        let invalidGeometry = CoachMark(
            kind: .run,
            start: PitchPoint(x: 201, z: 0),
            end: .zero,
            label: "Outside pitch envelope",
            revealTime: 1
        )
        let invalidText = CoachMark(
            kind: .space,
            start: .zero,
            end: PitchPoint(x: 2, z: 2),
            label: String(repeating: "X", count: ReplayStore.maximumCoachMarkLabelLength + 1),
            revealTime: 1
        )
        let invalidCombiningText = CoachMark(
            kind: .space,
            start: .zero,
            end: PitchPoint(x: 2, z: 2),
            label: "A" + String(repeating: "\u{0301}", count: 500),
            revealTime: 1
        )
        var generated: [CoachMark] = []
        generated.reserveCapacity(ReplayStore.maximumSharedCoachMarks + 12)
        for index in 0..<(ReplayStore.maximumSharedCoachMarks + 12) {
            generated.append(CoachMark(
                kind: .pass,
                start: PitchPoint(x: Float(index % 20), z: 0),
                end: PitchPoint(x: Float(index % 20) + 1, z: 3),
                label: "Lane \(index)",
                revealTime: TimeInterval(index % 30)
            ))
        }
        let secondDuplicate = CoachMark(
            id: duplicateID,
            kind: .danger,
            start: .zero,
            end: PitchPoint(x: 5, z: 5),
            label: "Must be discarded",
            revealTime: 2
        )
        let base = store.makeSnapshot()
        let snapshot = SharedPlaybackSnapshot(
            scenarioID: base.scenarioID,
            playhead: base.playhead,
            isPlaying: base.isPlaying,
            playbackRate: base.playbackRate,
            viewMode: base.viewMode,
            coachFocusPerspectiveID: base.coachFocusPerspectiveID,
            coachLockEnabled: base.coachLockEnabled,
            marks: [
                invalidGeometry,
                invalidText,
                invalidCombiningText,
                duplicate,
                secondDuplicate,
            ] + generated,
            seatAssignments: base.seatAssignments,
            showsLaneLens: base.showsLaneLens,
            sharedPitchAnchorID: base.sharedPitchAnchorID,
            triangleLockMode: base.triangleLockMode,
            shapeFocusStage: base.shapeFocusStage
        )

        store.applyRemote(snapshot)

        XCTAssertEqual(store.marks.count, ReplayStore.maximumSharedCoachMarks)
        XCTAssertEqual(Set(store.marks.map(\.id)).count, store.marks.count)
        XCTAssertEqual(store.marks.first?.id, duplicateID)
        XCTAssertEqual(store.marks.first?.label, "Keep first")
        XCTAssertFalse(store.marks.contains(invalidGeometry))
        XCTAssertFalse(store.marks.contains(invalidText))
        XCTAssertFalse(store.marks.contains(invalidCombiningText))
    }

    func testIncrementalRemoteAnnotationSurvivesLocalPauseAndResume() throws {
        let coach = ReplayStore()
        let player = ReplayStore()
        player.localRole = .player
        player.setCollaborationActive(true)
        player.applyRemote(coach.makeSnapshot())
        player.setFollowingCoach(false)
        let mark = CoachMark(
            kind: .run,
            start: PitchPoint(x: 2, z: 3),
            end: PitchPoint(x: 7, z: 14),
            label: "Delayed overlap",
            revealTime: 4,
            hideTime: 12
        )

        XCTAssertTrue(player.appendRemoteCoachMark(mark))
        XCTAssertFalse(player.appendRemoteCoachMark(mark))
        player.setFollowingCoach(true)

        XCTAssertTrue(player.marks.contains(mark))
    }

    func testSharedCommandCodableRoundTripPreservesSnapshotAndAnnotation() throws {
        let mark = CoachMark(
            id: UUID(uuidString: "11111111-2222-4333-8444-555555555555")!,
            kind: .playerLabel,
            start: PitchPoint(x: 3.5, z: -8),
            end: PitchPoint(x: 3.5, z: -8),
            label: "#7 Luca Hale • RW",
            revealTime: 13.5,
            hideTime: 21.5,
            author: "Coach Morgan",
            playerID: "navy-rw"
        )
        let snapshot = SharedPlaybackSnapshot(
            scenarioID: "everyone-with-seven",
            playhead: 13.5,
            isPlaying: false,
            playbackRate: 0.65,
            viewMode: .firstPerson,
            coachFocusPerspectiveID: "navy-rw",
            coachLockEnabled: true,
            marks: [mark],
            seatAssignments: [
                UUID(uuidString: "BBBBBBBB-CCCC-4DDD-8EEE-FFFFFFFFFFFF")!: "navy-rw"
            ],
            showsLaneLens: false,
            sharedPitchAnchorID: UUID(uuidString: "CCCCCCCC-DDDD-4EEE-8FFF-AAAAAAAAAAAA")!,
            triangleLockMode: .visualise,
            shapeFocusStage: .ideal
        )
        let command = SharedCommand(
            kind: .coachAnnotation,
            sequence: 42,
            authorID: UUID(uuidString: "AAAAAAAA-BBBB-4CCC-8DDD-EEEEEEEEEEEE")!,
            sentAt: Date(timeIntervalSinceReferenceDate: 123_456),
            authorRole: .coach,
            snapshot: snapshot,
            mark: mark
        )

        let encoded = try JSONEncoder().encode(command)
        let decoded = try JSONDecoder().decode(SharedCommand.self, from: encoded)

        XCTAssertEqual(decoded, command)

        let request = SharedCommand(
            kind: .requestState,
            sequence: 43,
            authorID: command.authorID,
            sentAt: command.sentAt,
            authorRole: .player,
            snapshot: nil,
            mark: nil
        )
        let requestData = try PropertyListEncoder().encode(request)
        XCTAssertEqual(try PropertyListDecoder().decode(SharedCommand.self, from: requestData), request)
    }

    func testCoachMarkDecodesLegacyPayloadWithoutPlayerTarget() throws {
        let legacyPayload = Data(
            #"""
            {
              "id": "11111111-2222-4333-8444-555555555556",
              "kind": "pass",
              "start": { "x": 3.5, "z": -8 },
              "end": { "x": 19, "z": 27.25 },
              "label": "Legacy overlap",
              "revealTime": 13.5,
              "author": "Coach Morgan"
            }
            """#.utf8
        )

        let mark = try JSONDecoder().decode(CoachMark.self, from: legacyPayload)

        XCTAssertEqual(mark.kind, .pass)
        XCTAssertEqual(mark.start, PitchPoint(x: 3.5, z: -8))
        XCTAssertEqual(mark.end, PitchPoint(x: 19, z: 27.25))
        XCTAssertEqual(mark.label, "Legacy overlap")
        XCTAssertNil(mark.hideTime)
        XCTAssertNil(mark.playerID)
    }

    func testLegacySnapshotWithoutShapeStageDecodesAsProblem() throws {
        let snapshot = ReplayStore().makeSnapshot()
        let encoded = try JSONEncoder().encode(snapshot)
        var object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: encoded) as? [String: Any]
        )
        object.removeValue(forKey: "shapeFocusStage")
        let legacyData = try JSONSerialization.data(withJSONObject: object)

        let decoded = try JSONDecoder().decode(SharedPlaybackSnapshot.self, from: legacyData)

        XCTAssertEqual(decoded.shapeFocusStage, .problem)
    }

    func testSequenceGateRejectsDuplicateAndStaleCommandsPerAuthor() {
        let authorA = UUID(uuidString: "AAAAAAAA-0000-4000-8000-000000000001")!
        let authorB = UUID(uuidString: "BBBBBBBB-0000-4000-8000-000000000002")!
        var gate = SequenceGate()

        XCTAssertTrue(gate.shouldAccept(command(sequence: 1, authorID: authorA)))
        XCTAssertFalse(gate.shouldAccept(command(sequence: 1, authorID: authorA)))
        XCTAssertFalse(gate.shouldAccept(command(sequence: 0, authorID: authorA)))
        XCTAssertTrue(gate.shouldAccept(command(sequence: 3, authorID: authorA)))
        XCTAssertFalse(gate.shouldAccept(command(sequence: 2, authorID: authorA)))

        XCTAssertTrue(gate.shouldAccept(command(sequence: 1, authorID: authorB)))
        XCTAssertFalse(gate.shouldAccept(command(sequence: 1, authorID: authorB)))

        XCTAssertEqual(gate.lastSequenceByAuthor[authorA], 3)
        XCTAssertEqual(gate.lastSequenceByAuthor[authorB], 1)
        XCTAssertEqual(gate.lastSequenceByAuthor.count, 2)

        gate.reset()
        XCTAssertTrue(gate.lastSequenceByAuthor.isEmpty)
        XCTAssertTrue(gate.shouldAccept(command(sequence: 1, authorID: authorA)))
        XCTAssertEqual(gate.lastSequenceByAuthor[authorA], 1)
    }

    func testRejectedFirstSyncDoesNotBindOrPoisonLateJoinRecovery() {
        let player = ReplayStore()
        player.localRole = .player
        player.setCollaborationActive(true)
        let coordinator = LegacySnapshotCoordinator(store: player)
        coordinator.state = .joined

        let coachID = UUID(uuidString: "AAAAAAAA-0000-4000-8000-000000000010")!
        let rejectedSource = UUID(uuidString: "BBBBBBBB-0000-4000-8000-000000000011")!
        let validSource = UUID(uuidString: "CCCCCCCC-0000-4000-8000-000000000012")!
        coordinator.authoritativeCoachID = coachID

        let base = player.makeSnapshot()
        let unsupported = SharedPlaybackSnapshot(
            scenarioID: "future-unsupported-scenario",
            playhead: 17,
            isPlaying: true,
            playbackRate: 2,
            viewMode: .firstPerson,
            coachFocusPerspectiveID: nil,
            coachLockEnabled: false,
            marks: base.marks,
            seatAssignments: base.seatAssignments,
            showsLaneLens: false,
            sharedPitchAnchorID: nil,
            triangleLockMode: .visualise
        )
        let rejected = SharedCommand(
            kind: .sync,
            sequence: .max,
            authorID: coachID,
            sentAt: Date(),
            authorRole: .coach,
            snapshot: unsupported,
            mark: nil
        )

        coordinator.receiveForTesting(rejected, sourceParticipantID: rejectedSource)

        XCTAssertNil(coordinator.authoritativeCoachParticipantID)
        XCTAssertEqual(coordinator.lastSync, .distantPast)
        XCTAssertEqual(player.selectedScenarioID, base.scenarioID)

        let coach = ReplayStore()
        coach.seek(to: 7.5, broadcast: false)
        coach.setPlaybackRate(1.5, broadcast: false)
        coach.setPlaying(true, broadcast: false)
        let recovery = SharedCommand(
            kind: .sync,
            sequence: 1,
            authorID: coachID,
            sentAt: Date(),
            authorRole: .coach,
            snapshot: coach.makeSnapshot(),
            mark: nil
        )

        coordinator.receiveForTesting(recovery, sourceParticipantID: validSource)

        XCTAssertEqual(coordinator.authoritativeCoachParticipantID, validSource)
        XCTAssertGreaterThan(coordinator.lastSync, .distantPast)
        XCTAssertEqual(player.playhead, 7.5, accuracy: 0.000_1)
        XCTAssertEqual(player.playbackRate, 1.5, accuracy: 0.000_1)
        XCTAssertTrue(player.isPlaying)

        let wrongSourceUpdate = SharedCommand(
            kind: .sync,
            sequence: 2,
            authorID: coachID,
            sentAt: Date(),
            authorRole: .coach,
            snapshot: base,
            mark: nil
        )
        coordinator.receiveForTesting(
            wrongSourceUpdate,
            sourceParticipantID: rejectedSource
        )
        XCTAssertEqual(player.playhead, 7.5, accuracy: 0.000_1)
    }

    func testLeavingRoomClearsStaleSynchronizationTimestamp() {
        let store = ReplayStore()
        let coordinator = LegacySnapshotCoordinator(store: store)
        coordinator.state = .joined
        coordinator.lastSync = Date()

        coordinator.leaveRoom()

        XCTAssertEqual(coordinator.state, .offline)
        XCTAssertEqual(coordinator.lastSync, .distantPast)
    }

    private func command(sequence: UInt64, authorID: UUID) -> SharedCommand {
        SharedCommand(
            kind: .sync,
            sequence: sequence,
            authorID: authorID,
            sentAt: Date(timeIntervalSinceReferenceDate: TimeInterval(sequence)),
            authorRole: .coach,
            snapshot: nil,
            mark: nil
        )
    }
}
