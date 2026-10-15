import RealityKit
import UIKit
import XCTest
@testable import ReplayXI

@MainActor
final class ReplayPlayerLabelClearanceTests: XCTestCase {
    override func setUp() {
        super.setUp()
        ReplaySkinnedAthleteProvider.resetForTesting()
        ReplayImportedAthleteProvider.resetPrewarmForTesting()
    }

    override func tearDown() {
        ReplaySkinnedAthleteProvider.resetForTesting()
        ReplayAthleteHeadProvider.resetForTesting()
        super.tearDown()
    }

    func testTouchlineTagsClearSelectedAndFeaturedAthleteHeads() throws {
        let scenario = try XCTUnwrap(DemoScenarios.scenario(for: .squadReplay))
        let root = PitchSceneFactory.makeMatchRoot(for: scenario)
        for selected in ["navy-rw", "navy-rb", "red-lb"] {
            for time in [10.1, 13.6, 17.5] {
                update(root, scenario: scenario, view: .touchline, selected: selected, time: time)
                for player in scenario.players {
                    try assertLabelClearsHead(root, player: player, context: "Touchline \(selected) at \(time)")
                }
            }
        }
    }

    func testShapeTagsClearAllVisibleProblemAndIdealAthletes() throws {
        let scenario = try XCTUnwrap(DemoScenarios.scenario(for: .shapeLab))
        let root = PitchSceneFactory.makeMatchRoot(for: scenario)
        for ideal in [false, true, false] {
            for time in [12.5, 14.0] {
                update(root, scenario: scenario, view: .positional,
                       selected: scenario.defaultPerspectiveID, time: time, ideal: ideal)
                for player in scenario.players {
                    let label = try XCTUnwrap(root.findEntity(named: "player-label-\(player.id)"))
                    if label.isEnabled {
                        try assertLabelClearsHead(root, player: player, context: "Shape ideal=\(ideal) at \(time)")
                    }
                }
            }
        }
    }

    func testTableSelectedTagsClearEveryShirtIncludingEvenHomeNumbers() throws {
        let scenario = try XCTUnwrap(DemoScenarios.scenario(for: .squadReplay))
        let root = PitchSceneFactory.makeMatchRoot(for: scenario)
        for player in scenario.players {
            update(root, scenario: scenario, view: .tacticalTable, selected: player.id, time: 13.6)
            try assertLabelClearsHead(root, player: player, context: "Table selected \(player.id)")
        }
    }

    func testFallbackHeadAndTableMarkerHaveNoVerticalAirGap() throws {
        let scenario = try XCTUnwrap(DemoScenarios.scenario(for: .squadReplay))
        let player = try XCTUnwrap(scenario.players.first)
        let far = try ReplayAthleteFactory.make(for: player, lod: .far)
        let torso = try XCTUnwrap(far.root.findEntity(named: "torso"))
        let head = try XCTUnwrap(far.root.findEntity(named: "head"))
        XCTAssertLessThanOrEqual(head.visualBounds(relativeTo: far.root).min.y,
                                 torso.visualBounds(relativeTo: far.root).max.y,
                                 "The cold far fallback must sit inside the shirt collar")

        let marker = PitchSceneFactory.makeTableMarker(
            shirtColor: .white, trimColor: .blue, limbColor: .white,
            skinColor: .brown, facingColor: .green)
        let markerTorso = try XCTUnwrap(marker.findEntity(named: "table-marker-body"))
        let markerNeck = try XCTUnwrap(marker.findEntity(named: "table-marker-neck"))
        let markerHead = try XCTUnwrap(marker.findEntity(named: "table-marker-head"))
        XCTAssertLessThanOrEqual(markerNeck.visualBounds(relativeTo: marker).min.y,
                                 markerTorso.visualBounds(relativeTo: marker).max.y)
        XCTAssertLessThanOrEqual(markerHead.visualBounds(relativeTo: marker).min.y,
                                 markerNeck.visualBounds(relativeTo: marker).max.y)
    }

    func testFirstPersonRetainsDistanceBandsAndHidesWearerTag() throws {
        let scenario = try XCTUnwrap(DemoScenarios.scenario(for: .squadReplay))
        let root = PitchSceneFactory.makeMatchRoot(for: scenario)
        let selected = scenario.defaultPerspectiveID
        update(root, scenario: scenario, view: .firstPerson, selected: selected, time: 13.6)
        let viewer = try XCTUnwrap(scenario.player(id: selected)).presentationPose(at: 13.6).position
        for player in scenario.players {
            let label = try XCTUnwrap(root.findEntity(named: "player-label-\(player.id)"))
            if player.id == selected { XCTAssertFalse(label.isEnabled) }
            guard label.isEnabled else { continue }
            let distance = ReplayGeometry.distance(viewer, player.presentationPose(at: 13.6).position)
            XCTAssertEqual(label.scale.x, PlaybackSpatialLabels.firstPersonLabelScale(forDistance: distance))
            try assertLabelClearsHead(root, player: player, context: "First person")
        }
    }

    func testGroundedProceduralHeadsRemainInsideTheStableHeightEnvelope() throws {
        let scenario = try XCTUnwrap(DemoScenarios.scenario(for: .squadReplay))
        for player in scenario.players {
            for lod in [ReplayAthleteLOD.near, .far] {
                let rig = try ReplayAthleteFactory.make(for: player, lod: lod)
                let parent = Entity()
                parent.addChild(rig.root)
                let head = try XCTUnwrap(rig.root.findEntity(named: "head-root"))
                for time in stride(from: 0.0, through: scenario.duration, by: 0.25) {
                    let ball = scenario.ball.pose(at: time)
                    ReplayAthleteMotion.update(
                        rig, from: player, at: time,
                        lookTargetWorldPosition: [ball.position.x, ball.height, ball.position.z],
                        ballTrack: scenario.ball
                    )
                    let actualCrown = head.visualBounds(relativeTo: parent).max.y
                    let cachedCrown = try XCTUnwrap(rig.joints.headUpperY(relativeTo: parent))
                    XCTAssertGreaterThanOrEqual(cachedCrown + 0.000_01, actualCrown)
                    XCTAssertLessThan(cachedCrown - actualCrown, 0.10,
                        "Cached head bounds must not inflate the label clearance")
                    XCTAssertLessThanOrEqual(
                        actualCrown,
                        ReplayAthleteReviewLayout.headClearanceEnvelope,
                        "\(player.id), \(lod), \(time): label allowance must cover the real head geometry"
                    )
                }
            }
        }
    }

    func testReviewTagReturnsToSamePoseAfterSeekAndViewSwitch() throws {
        let scenario = try XCTUnwrap(DemoScenarios.scenario(for: .squadReplay))
        let root = PitchSceneFactory.makeMatchRoot(for: scenario)
        let selected = "navy-rb"
        for view in [ReplayViewMode.tacticalTable, .touchline] {
            update(root, scenario: scenario, view: view, selected: selected, time: 10)
            let label = try XCTUnwrap(root.findEntity(named: "player-label-\(selected)"))
            let height = label.position.y
            for time in [11.0, 13.6, 17.5, 32.0, 10.0] {
                update(root, scenario: scenario, view: view, selected: selected, time: time)
                try assertLabelClearsHead(root,
                    player: XCTUnwrap(scenario.player(id: selected)), context: "Seek \(time)")
            }
            XCTAssertEqual(label.position.y, height, accuracy: 0.000_01)
            update(root, scenario: scenario, view: .firstPerson, selected: selected, time: 10)
            update(root, scenario: scenario, view: view, selected: selected, time: 10)
            XCTAssertEqual(label.position.y, height, accuracy: 0.000_01)
        }
    }

    func testVisibleTagBottomStaysCloseToSuppliedCrownForEveryStyleAndSeek() throws {
        let scenario = try XCTUnwrap(DemoScenarios.scenario(for: .squadReplay))
        let root = Entity()
        root.addChild(PlaybackSpatialLabels.makePlayerLabels(for: scenario))
        let poses = Dictionary(uniqueKeysWithValues: scenario.players.map {
            ($0.id, $0.presentationPose(at: 4))
        })
        // A crouch, upright pose, jump and rewind must use the current crown,
        // not a fixed band or a maximum retained from an earlier frame.
        let crowns: [Float] = [1.35, 1.82, 2.18, 1.35]
        for crown in crowns {
            for view in [ReplayViewMode.tacticalTable, .touchline, .positional, .firstPerson] {
                PlaybackSpatialLabels.updatePlayerLabels(
                    in: root, scenario: scenario, posesByPlayerID: poses,
                    viewMode: view, perspectiveID: scenario.defaultPerspectiveID,
                    headTopForPlayer: { _ in crown })
                for player in scenario.players {
                    let label = try XCTUnwrap(root.findEntity(named: "player-label-\(player.id)"))
                    guard label.isEnabled else { continue }
                    let bottom = try XCTUnwrap(visibleModelMinimumY(label, relativeTo: root))
                    XCTAssertEqual(bottom - crown, ReplayAthleteReviewLayout.tagHeadGap,
                        accuracy: 0.001, "\(view), \(player.id), crown \(crown)")
                }
            }
        }
    }

    func testCompactNumberDoesNotReserveAnInvisibleCardOrChangePicking() throws {
        let scenario = try XCTUnwrap(DemoScenarios.scenario(for: .squadReplay))
        let root = Entity()
        root.addChild(PlaybackSpatialLabels.makePlayerLabels(for: scenario))
        let poses = Dictionary(uniqueKeysWithValues: scenario.players.map {
            ($0.id, $0.presentationPose(at: 4))
        })
        PlaybackSpatialLabels.updatePlayerLabels(
            in: root, scenario: scenario, posesByPlayerID: poses,
            viewMode: .tacticalTable, perspectiveID: scenario.defaultPerspectiveID,
            headTopForPlayer: { _ in 1.8 })
        let selected = try XCTUnwrap(root.findEntity(named: "player-label-\(scenario.defaultPerspectiveID)"))
        XCTAssertEqual(selected.scale.x, 2.8)
        let compact = try XCTUnwrap(root.findEntity(named: "player-label-navy-rb"))
        XCTAssertLessThan(compact.position.y, selected.position.y)
        XCTAssertLessThan(compact.position.y, 2.2)
        XCTAssertNotNil(compact.components[InputTargetComponent.self])
        XCTAssertNotNil(compact.components[CollisionComponent.self])
        PlaybackSpatialLabels.resetUpdateWorkForTesting()
        PlaybackSpatialLabels.updatePlayerLabels(
            in: root, scenario: scenario, posesByPlayerID: poses,
            viewMode: .tacticalTable, perspectiveID: scenario.defaultPerspectiveID,
            headTopForPlayer: { _ in 1.8 })
        XCTAssertEqual(PlaybackSpatialLabels.updateWork.transformWrites, 0)
        XCTAssertEqual(PlaybackSpatialLabels.updateWork.stylePropertyWrites, 0)
    }

    func testAuthoredPlayerCardReplacesChipAndKeepsItsTetherAtTheVisibleBottom() throws {
        let scenario = try XCTUnwrap(DemoScenarios.scenario(for: .squadReplay))
        let player = try XCTUnwrap(scenario.player(id: "red-lb"))
        let mark = CoachMark(kind: .playerLabel, start: .zero, end: .zero,
            label: "#2 LEFT BACK", revealTime: 8, hideTime: 20, playerID: player.id)
        let root = PitchSceneFactory.makeMatchRoot(for: scenario)
        for view in [ReplayViewMode.tacticalTable, .touchline, .firstPerson] {
            for selected in [false, true] {
                var firstHeight: Float?
                for time in [10.0, 16, 10] {
                    PitchSceneFactory.update(root: root, scenario: scenario, time: time,
                        viewMode: view, perspectiveID: scenario.defaultPerspectiveID,
                        marks: [mark], selectedAnnotationID: selected ? mark.id : nil,
                        showsLaneLens: false, isDrawing: false, positionalOriginTransform: nil)
                    let card = try XCTUnwrap(root.findEntity(named: "mark-\(mark.id.uuidString)")?
                        .findEntity(named: "annotation-label"))
                    let chip = try XCTUnwrap(root.findEntity(named: "player-label-\(player.id)"))
                    XCTAssertTrue(card.isEnabled)
                    XCTAssertFalse(chip.isEnabled, "The coach card replaces the ordinary number")
                    let body = try XCTUnwrap(root.findEntity(named: "player-\(player.id)"))
                    let rig = try XCTUnwrap(body.children.first {
                        ($0.name == "full-rig" || $0.name == "table-marker") && $0.isEnabled
                    })
                    let head = try XCTUnwrap(rig.findEntity(named: "head-root"))
                    let crown = head.visualBounds(relativeTo: root).max.y
                    let bottom = try XCTUnwrap(visibleModelMinimumY(card, relativeTo: root))
                    let clearanceBottom: Float
                    if selected {
                        let outline = try XCTUnwrap(root.findEntity(named: "annotation-selection-label-outline"))
                        clearanceBottom = min(bottom, outline.visualBounds(relativeTo: root).min.y)
                    } else { clearanceBottom = bottom }
                    XCTAssertGreaterThan(clearanceBottom - crown, 0.05)
                    XCTAssertLessThan(clearanceBottom - crown, 0.18)
                    let attachment = try XCTUnwrap(root.findEntity(named: "mark-\(mark.id.uuidString)")?
                        .findEntity(named: AnnotationSceneAffordance.playerAttachmentName))
                    let stem = try XCTUnwrap(attachment.findEntity(named: "annotation-attachment-stem"))
                    XCTAssertEqual(stem.visualBounds(relativeTo: root).max.y, bottom, accuracy: 0.000_01)
                    let pose = player.presentationPose(at: time)
                    XCTAssertEqual(card.position.x, pose.position.x, accuracy: 0.000_01)
                    XCTAssertEqual(card.position.z, pose.position.z, accuracy: 0.000_01)
                    if view == .tacticalTable { XCTAssertEqual(card.scale.y, 2.8) }
                    if time == 10 {
                        if let firstHeight { XCTAssertEqual(card.position.y, firstHeight, accuracy: 0.000_01) }
                        else { firstHeight = card.position.y }
                    }
                }
            }
        }
    }

    private func assertLabelClearsHead(
        _ root: Entity, player: PlayerTrack, context: String,
        file: StaticString = #filePath, line: UInt = #line
    ) throws {
        let body = try XCTUnwrap(root.findEntity(named: "player-\(player.id)"), file: file, line: line)
        let rig = try XCTUnwrap(body.children.first {
            ($0.name == "full-rig" || $0.name == "table-marker") && $0.isEnabled
        }, file: file, line: line)
        let head = try XCTUnwrap(rig.findEntity(named: "head-root"), file: file, line: line)
        let label = try XCTUnwrap(root.findEntity(named: "player-label-\(player.id)"), file: file, line: line)
        let headTop = head.visualBounds(relativeTo: root).max.y
        let labelBottom = try XCTUnwrap(visibleModelMinimumY(label, relativeTo: root), file: file, line: line)
        XCTAssertGreaterThan(labelBottom, headTop + 0.05,
                             "\(context), \(player.id): tag bottom \(labelBottom) intersects head top \(headTop)",
                             file: file, line: line)
    }

    private func visibleModelMinimumY(_ entity: Entity, relativeTo root: Entity) -> Float? {
        guard entity.isEnabled else { return nil }
        var result: Float? = entity.components[ModelComponent.self] == nil
            ? nil : entity.visualBounds(recursive: false, relativeTo: root).min.y
        for child in entity.children {
            guard let value = visibleModelMinimumY(child, relativeTo: root) else { continue }
            result = result.map { min($0, value) } ?? value
        }
        return result
    }

    private func update(_ root: Entity, scenario: ReplayScenario, view: ReplayViewMode,
                        selected: String, time: Double, ideal: Bool = false) {
        PitchSceneFactory.update(
            root: root, scenario: scenario, time: time, viewMode: view,
            perspectiveID: selected, marks: [], showsLaneLens: false,
            isDrawing: false, positionalOriginTransform: nil, showsIdealBranch: ideal
        )
    }
}
