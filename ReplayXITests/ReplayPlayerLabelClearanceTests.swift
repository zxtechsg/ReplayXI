import RealityKit
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
            let expected = PlaybackSpatialLabels.firstPersonLabelHeight(forDistance: distance)
                + (player.team == .away ? 0.16 : 0)
                + (player.shirtNumber.isMultiple(of: 2) ? 0 : 0.08)
            XCTAssertEqual(label.position.y, expected)
            XCTAssertEqual(label.scale.x, PlaybackSpatialLabels.firstPersonLabelScale(forDistance: distance))
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
                    XCTAssertLessThanOrEqual(
                        head.visualBounds(relativeTo: parent).max.y,
                        ReplayAthleteReviewLayout.headClearanceEnvelope,
                        "\(player.id), \(lod), \(time): label allowance must cover the real head geometry"
                    )
                }
            }
        }
    }

    func testReviewTagHeightDoesNotBobWithTimeAndReturnsAfterViewSwitch() throws {
        let scenario = try XCTUnwrap(DemoScenarios.scenario(for: .squadReplay))
        let root = PitchSceneFactory.makeMatchRoot(for: scenario)
        let selected = "navy-rb"
        for view in [ReplayViewMode.tacticalTable, .touchline] {
            update(root, scenario: scenario, view: view, selected: selected, time: 10)
            let label = try XCTUnwrap(root.findEntity(named: "player-label-\(selected)"))
            let height = label.position.y
            for time in [11.0, 13.6, 17.5, 32.0, 10.0] {
                update(root, scenario: scenario, view: view, selected: selected, time: time)
                XCTAssertEqual(label.position.y, height)
            }
            update(root, scenario: scenario, view: .firstPerson, selected: selected, time: 10)
            update(root, scenario: scenario, view: view, selected: selected, time: 10)
            XCTAssertEqual(label.position.y, height)
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
