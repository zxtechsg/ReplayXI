import XCTest
@testable import ReplayXI

final class ReplayDecisionReviewTests: XCTestCase {
    func testCoachFocusBuildsTimeLockedDecisionSnapshot() throws {
        let scenario = try XCTUnwrap(DemoScenarios.scenario(for: .coachFocus))

        let snapshot = try XCTUnwrap(
            scenario.decisionReview(at: 14.1, playerID: "navy-rw")
        )

        XCTAssertEqual(snapshot.scenarioID, scenario.id)
        XCTAssertEqual(snapshot.playerID, "navy-rw")
        XCTAssertEqual(snapshot.time, 14.1, accuracy: 0.000_001)
        XCTAssertEqual(snapshot.cue?.id, "focus-release")
        XCTAssertEqual(snapshot.scanWindow.activeCueID, "focus-release")
        XCTAssertEqual(snapshot.scanWindow.startTime, 11.6, accuracy: 0.000_001)
        XCTAssertEqual(snapshot.scanWindow.endTime, 14.1, accuracy: 0.000_001)
        XCTAssertEqual(snapshot.scanWindow.duration, 2.5, accuracy: 0.000_001)
        XCTAssertGreaterThan(snapshot.scanWindow.bodyTurnDegrees, 0)
        XCTAssertFalse(snapshot.scanWindow.bodyFacingContextPlayerIDs.contains("navy-rw"))
        XCTAssertEqual(snapshot.evidence.provenance.sourceKind, .synthetic)
        XCTAssertEqual(snapshot.evidence.sampleClassification, .interpolated)
    }

    func testReceivingOrientationIsFiniteAndExplicitlyUsesBodyFacingProxy() throws {
        let scenario = try XCTUnwrap(DemoScenarios.scenario(for: .coachFocus))
        let snapshot = try XCTUnwrap(
            scenario.decisionReview(at: 14.1, playerID: "navy-rw")
        )
        let orientation = snapshot.receivingOrientation

        XCTAssertTrue(orientation.isWithinControlRadius)
        XCTAssertLessThan(orientation.ballDistanceMetres, 2)
        for angle in [
            orientation.facingToBallDegrees,
            orientation.facingToAttackingDirectionDegrees,
            orientation.ballToAttackingDirectionDegrees
        ] {
            XCTAssertTrue(angle.isFinite)
            XCTAssertGreaterThanOrEqual(angle, 0)
            XCTAssertLessThanOrEqual(angle, 180)
        }
        XCTAssertEqual(
            ReplayReceivingOrientation.evidenceLabel,
            "BODY FACING, NOT RECORDED HEAD OR EYE DIRECTION"
        )
        XCTAssertEqual(
            ReplayDecisionScanWindow.evidenceLabel,
            "BODY ORIENTATION PROXY • NO GAZE DATA"
        )
    }

    func testReplayedDestinationAndCoachSuggestionRemainSeparateEvidence() throws {
        let scenario = try XCTUnwrap(DemoScenarios.scenario(for: .coachFocus))
        let snapshot = try XCTUnwrap(
            scenario.decisionReview(at: 14.1, playerID: "navy-rw")
        )

        XCTAssertEqual(snapshot.observedDestination?.receiverID, "navy-rb")
        XCTAssertEqual(snapshot.coachSuggestion?.receiverID, "navy-rb")
        XCTAssertEqual(snapshot.coachSuggestion?.origin, .coachAnnotation)
        XCTAssertEqual(snapshot.coachSuggestion?.label, "Release outside")
        XCTAssertNotNil(snapshot.coachSuggestion?.coachMarkID)
        XCTAssertEqual(snapshot.replayedOption?.receiverID, "navy-rb")
        XCTAssertEqual(snapshot.coachSuggestedOption?.receiverID, "navy-rb")
        XCTAssertEqual(
            snapshot.replayedOption?.roles,
            [.replayedDestination, .coachSuggestion]
        )
        XCTAssertEqual(
            ReplayObservedDestination.evidenceLabel,
            "REPLAYED BALL DESTINATION"
        )
        XCTAssertEqual(
            ReplayCoachSuggestion.evidenceLabel,
            "COACH AUTHORED • NOT AN OBSERVED FACT"
        )
    }

    func testExplicitCoachSuggestionCanDisagreeWithReplayWithoutChangingIt() throws {
        let scenario = try XCTUnwrap(DemoScenarios.scenario(for: .coachFocus))
        let suggestion = ReplayCoachSuggestion(
            receiverID: "navy-rcm",
            label: "Hold for the inside return",
            author: "Coach Vale"
        )
        let snapshot = try XCTUnwrap(
            scenario.decisionReview(
                at: 14.1,
                playerID: "navy-rw",
                coachSuggestion: suggestion
            )
        )

        XCTAssertEqual(snapshot.observedDestination?.receiverID, "navy-rb")
        XCTAssertEqual(snapshot.coachSuggestion?.receiverID, "navy-rcm")
        XCTAssertEqual(snapshot.coachSuggestion?.origin, .explicitInput)
        XCTAssertEqual(snapshot.replayedOption?.receiverID, "navy-rb")
        XCTAssertEqual(snapshot.coachSuggestedOption?.receiverID, "navy-rcm")
        XCTAssertFalse(snapshot.replayedOption?.isCoachSuggestion ?? true)
        XCTAssertFalse(snapshot.coachSuggestedOption?.isReplayedDestination ?? true)
    }

    func testCurrentSharedPassMarksBecomeCoachSuggestionsImmediately() throws {
        let scenario = try XCTUnwrap(DemoScenarios.scenario(for: .coachFocus))
        let reviewTime: TimeInterval = 14.1
        let revealTime: TimeInterval = 14
        let source = try XCTUnwrap(scenario.player(id: "navy-rw"))
        let receiver = try XCTUnwrap(scenario.player(id: "navy-rcm"))
        let sharedMark = CoachMark(
            kind: .pass,
            start: source.presentationPose(at: revealTime).position,
            end: receiver.presentationPose(at: revealTime + 3).position,
            label: "Shared inside return",
            revealTime: revealTime,
            hideTime: 16,
            author: "Live coach"
        )

        let snapshot = try XCTUnwrap(
            scenario.decisionReview(
                at: reviewTime,
                playerID: source.id,
                currentMarks: [sharedMark]
            )
        )

        XCTAssertEqual(snapshot.observedDestination?.receiverID, "navy-rb")
        XCTAssertEqual(snapshot.coachSuggestion?.receiverID, receiver.id)
        XCTAssertEqual(snapshot.coachSuggestion?.label, "Shared inside return")
        XCTAssertEqual(snapshot.coachSuggestion?.author, "Live coach")
        XCTAssertEqual(snapshot.coachSuggestion?.origin, .coachAnnotation)
        XCTAssertEqual(snapshot.coachSuggestion?.coachMarkID, sharedMark.id)
        XCTAssertEqual(snapshot.coachSuggestedOption?.receiverID, receiver.id)

        let cleared = try XCTUnwrap(
            scenario.decisionReview(
                at: reviewTime,
                playerID: source.id,
                currentMarks: []
            )
        )
        XCTAssertNil(cleared.coachSuggestion)
        XCTAssertNil(cleared.coachSuggestedOption)
    }

    func testTrackedCoachMarkSourceResolvesAtRevealTime() throws {
        let scenario = try XCTUnwrap(DemoScenarios.scenario(for: .coachFocus))
        let revealTime: TimeInterval = 14
        let source = try XCTUnwrap(scenario.player(id: "navy-rw"))
        let receiver = try XCTUnwrap(scenario.player(id: "navy-rcm"))
        var configuration = ReplayDecisionConfiguration.standard
        configuration.coachMarkStartRadiusMetres = 0.05
        let targetTime = revealTime + configuration.outcomeLookAhead
        let mark = CoachMark(
            kind: .pass,
            start: PitchPoint(x: -34, z: -51),
            end: receiver.presentationPose(at: targetTime).position,
            label: "Tracked source",
            revealTime: revealTime,
            hideTime: 16,
            startTrackAnchor: CoachMarkTrackAnchor(playerID: source.id)
        )

        let snapshot = try XCTUnwrap(
            scenario.decisionReview(
                at: 15.9,
                playerID: source.id,
                currentMarks: [mark],
                configuration: configuration
            )
        )

        XCTAssertEqual(snapshot.coachSuggestion?.coachMarkID, mark.id)
        XCTAssertEqual(snapshot.coachSuggestion?.receiverID, receiver.id)
    }

    func testTrackedCoachMarkTargetResolvesAtOutcomeTime() throws {
        let scenario = try XCTUnwrap(DemoScenarios.scenario(for: .coachFocus))
        let revealTime: TimeInterval = 14
        let source = try XCTUnwrap(scenario.player(id: "navy-rw"))
        let receiver = try XCTUnwrap(scenario.player(id: "navy-rcm"))
        var configuration = ReplayDecisionConfiguration.standard
        configuration.coachMarkTargetRadiusMetres = 0.05
        let mark = CoachMark(
            kind: .pass,
            start: source.presentationPose(at: revealTime).position,
            end: PitchPoint(x: -34, z: -51),
            label: "Tracked target",
            revealTime: revealTime,
            hideTime: 16,
            endTrackAnchor: CoachMarkTrackAnchor(playerID: receiver.id)
        )

        let snapshot = try XCTUnwrap(
            scenario.decisionReview(
                at: 14.1,
                playerID: source.id,
                currentMarks: [mark],
                configuration: configuration
            )
        )

        XCTAssertEqual(snapshot.coachSuggestion?.coachMarkID, mark.id)
        XCTAssertEqual(snapshot.coachSuggestion?.receiverID, receiver.id)
    }

    func testTacticalPreviewResolvesTrackedMarkAtDisplayedTime() throws {
        let scenario = try XCTUnwrap(DemoScenarios.scenario(for: .coachFocus))
        let source = try XCTUnwrap(scenario.player(id: "navy-rw"))
        let receiver = try XCTUnwrap(scenario.player(id: "navy-rcm"))
        let startOffset = PitchPoint(x: 0.75, z: -0.5)
        let endOffset = PitchPoint(x: -0.25, z: 1.25)
        let mark = CoachMark(
            kind: .pass,
            start: PitchPoint(x: -34, z: -51),
            end: PitchPoint(x: 34, z: 51),
            label: "Live preview",
            startTrackAnchor: CoachMarkTrackAnchor(
                playerID: source.id,
                offset: startOffset
            ),
            endTrackAnchor: CoachMarkTrackAnchor(
                playerID: receiver.id,
                offset: endOffset
            )
        )
        let displayedTime: TimeInterval = 17.25

        let geometry = TacticalPreview.resolvedMarkGeometry(
            for: mark,
            in: scenario,
            at: displayedTime
        )
        let sourceAtDisplay = source.presentationPose(at: displayedTime).position
        let receiverAtDisplay = receiver.presentationPose(at: displayedTime).position

        XCTAssertEqual(geometry.start.x, sourceAtDisplay.x + startOffset.x, accuracy: 0.000_001)
        XCTAssertEqual(geometry.start.z, sourceAtDisplay.z + startOffset.z, accuracy: 0.000_001)
        XCTAssertEqual(geometry.end.x, receiverAtDisplay.x + endOffset.x, accuracy: 0.000_001)
        XCTAssertEqual(geometry.end.z, receiverAtDisplay.z + endOffset.z, accuracy: 0.000_001)
        XCTAssertNotEqual(geometry.start, mark.start)
        XCTAssertNotEqual(geometry.end, mark.end)
    }

    func testPassingOptionsAreBoundedDeterministicAndDescriptive() throws {
        let scenario = try XCTUnwrap(DemoScenarios.scenario(for: .coachFocus))
        let first = try XCTUnwrap(
            scenario.decisionReview(at: 14.1, playerID: "navy-rw")
        )
        let second = try XCTUnwrap(
            scenario.decisionReview(at: 14.1, playerID: "navy-rw")
        )

        XCTAssertEqual(first, second)
        XCTAssertEqual(first.passingOptions, second.passingOptions)
        XCTAssertEqual(first.passingOptions.count, 4)
        XCTAssertEqual(Set(first.passingOptions.map(\.receiverID)).count, 4)
        for option in first.passingOptions {
            XCTAssertGreaterThan(option.passDistanceMetres, 0)
            XCTAssertTrue(option.passDistanceMetres.isFinite)
            XCTAssertTrue(option.laneClearanceMetres?.isFinite ?? false)
            XCTAssertTrue(option.targetPressureMetres?.isFinite ?? false)
            XCTAssertNotNil(option.nearestLaneDefenderID)
            XCTAssertFalse(option.roles.isEmpty)
        }
        XCTAssertEqual(
            ReplayPassingLaneOption.metricLabel,
            "DESCRIPTIVE SPACING AT THIS TIMESTAMP"
        )
    }

    func testInvalidSuggestionIsRejectedRatherThanPresentedAsCoachIntent() throws {
        let scenario = try XCTUnwrap(DemoScenarios.scenario(for: .squadReplay))
        let invalidSuggestion = ReplayCoachSuggestion(
            receiverID: "red-lb",
            label: "Invalid opposition receiver"
        )

        let snapshot = try XCTUnwrap(
            scenario.decisionReview(
                at: 14,
                playerID: "navy-rw",
                coachSuggestion: invalidSuggestion
            )
        )

        XCTAssertNil(snapshot.coachSuggestion)
        XCTAssertNil(snapshot.coachSuggestedOption)
        XCTAssertFalse(snapshot.passingOptions.contains { $0.receiverID == "red-lb" })
    }

    func testProvenanceClampsOnlyDeclaredConfidenceAndNeverFabricatesIt() {
        let tooHigh = ReplayDataProvenance(
            providerName: "  Tracking Partner  ",
            pipelineVersion: "  4.2  ",
            sourceKind: .opticalTracking,
            declaredConfidence: 1.7,
            confidenceScope: "  calibrated position confidence  "
        )
        let missing = ReplayDataProvenance(
            providerName: "",
            pipelineVersion: "",
            sourceKind: .broadcastReconstruction,
            declaredConfidence: .nan
        )

        XCTAssertEqual(tooHigh.providerName, "Tracking Partner")
        XCTAssertEqual(tooHigh.pipelineVersion, "4.2")
        XCTAssertEqual(tooHigh.declaredConfidence, 1)
        XCTAssertEqual(tooHigh.confidenceScope, "calibrated position confidence")
        XCTAssertEqual(tooHigh.confidenceLabel, "OPTICAL • 100%")
        XCTAssertEqual(missing.providerName, "Unknown provider")
        XCTAssertEqual(missing.pipelineVersion, "Unversioned")
        XCTAssertNil(missing.declaredConfidence)
        XCTAssertEqual(missing.confidenceLabel, "RECONSTRUCTED • CONFIDENCE UNAVAILABLE")
        XCTAssertEqual(
            ReplayDataProvenance.syntheticDemo.confidenceLabel,
            "SYNTHETIC • CONFIDENCE N/A"
        )
    }

    func testSampleClassificationAndTimelineInputAreSafeAtEdges() throws {
        let scenario = try XCTUnwrap(DemoScenarios.scenario(for: .coachFocus))

        XCTAssertNil(scenario.decisionReview(at: .nan, playerID: "navy-rw"))
        XCTAssertNil(scenario.decisionReview(at: 14.1, playerID: "missing"))

        let beforeStart = try XCTUnwrap(
            scenario.decisionReview(at: -20, playerID: "navy-rw")
        )
        let afterEnd = try XCTUnwrap(
            scenario.decisionReview(at: 200, playerID: "navy-rw")
        )
        XCTAssertEqual(beforeStart.time, 0)
        XCTAssertEqual(afterEnd.time, scenario.duration)
        XCTAssertEqual(beforeStart.evidence.sampleClassification, .observed)
        XCTAssertEqual(afterEnd.evidence.sampleClassification, .observed)
    }

    func testDecisionSnapshotCodableRoundTripPreservesEvidenceRoles() throws {
        let scenario = try XCTUnwrap(DemoScenarios.scenario(for: .coachFocus))
        let snapshot = try XCTUnwrap(
            scenario.decisionReview(at: 14.1, playerID: "navy-rw")
        )

        let data = try JSONEncoder().encode(snapshot)
        let decoded = try JSONDecoder().decode(ReplayDecisionSnapshot.self, from: data)

        XCTAssertEqual(decoded, snapshot)
        XCTAssertEqual(decoded.replayedOption?.roles, [.replayedDestination, .coachSuggestion])
    }

    func testEveryPlayerAndScenarioProducesFiniteBoundedReviewFrames() throws {
        let sampleTimes: [TimeInterval] = [0, 4.2, 9.8, 13.6, 14.1, 18.2, 24.5, 32]

        for scenario in DemoScenarios.all {
            for player in scenario.players {
                for time in sampleTimes {
                    let snapshot = try XCTUnwrap(
                        scenario.decisionReview(at: time, playerID: player.id),
                        "\(scenario.id) • \(player.id) • \(time)"
                    )
                    XCTAssertLessThanOrEqual(snapshot.passingOptions.count, 4)
                    XCTAssertTrue(snapshot.scanWindow.bodyTurnDegrees.isFinite)
                    XCTAssertTrue(snapshot.receivingOrientation.ballDistanceMetres.isFinite)
                    XCTAssertGreaterThanOrEqual(snapshot.scanWindow.startTime, 0)
                    XCTAssertLessThanOrEqual(snapshot.scanWindow.endTime, scenario.duration)
                    XCTAssertEqual(
                        Set(snapshot.passingOptions.map(\.receiverID)).count,
                        snapshot.passingOptions.count
                    )
                    for option in snapshot.passingOptions {
                        let receiver = try XCTUnwrap(scenario.player(id: option.receiverID))
                        XCTAssertEqual(receiver.team, player.team)
                        XCTAssertNotEqual(receiver.id, player.id)
                        XCTAssertTrue(option.passDistanceMetres.isFinite)
                        XCTAssertGreaterThanOrEqual(option.passDistanceMetres, 0)
                    }
                }
            }
        }
    }
}
