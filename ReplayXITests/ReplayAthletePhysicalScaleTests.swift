import RealityKit
import XCTest
@testable import ReplayXI

@MainActor
final class ReplayAthletePhysicalScaleTests: XCTestCase {
    func testEveryViewUsesPhysicalBodyScaleIndependentOfProminence() {
        for view in ReplayViewMode.allCases {
            for selected in [false, true] {
                for featured in [false, true] {
                    for role in [false, true] {
                        for drill in [false, true] {
                            XCTAssertEqual(ReplayAthleteReviewLayout.focusScale(viewMode: view,
                                isSelected: selected, isFeatured: featured, isShapeRole: role,
                                isPhysicalDrill: drill), 1, "Body size must not encode selection or team prominence")
                        }
                    }
                }
            }
        }
    }

    func testUnmeasuredAppearancePalettesDoNotInventDifferentBodySizes() {
        for index in -5...15 {
            let appearance = ReplayAthleteAppearance.replayXI(index: index)
            XCTAssertEqual(appearance.heightScale, 1, "Skin palette is not a measured player height")
            XCTAssertEqual(appearance.widthScale, 1, "Skin palette is not measured anatomy")
        }
    }

    func testActualBothTeamPlayerRootsKeepPhysicalScaleThroughSelectionAndViews() throws {
        let scenario = try XCTUnwrap(DemoScenarios.scenario(for: .squadReplay))
        let root = PitchSceneFactory.makeMatchRoot(for: scenario)
        var rows: [[String: Any]] = []
        for selected in ["navy-rw", "red-lb"] {
            for view in [ReplayViewMode.tacticalTable, .touchline, .firstPerson] {
                PitchSceneFactory.update(root: root, scenario: scenario, time: 13.6,
                    viewMode: view, perspectiveID: selected, marks: [], showsLaneLens: false,
                    isDrawing: false, positionalOriginTransform: nil)
                for player in scenario.players {
                    let entity = try XCTUnwrap(root.findEntity(named: "player-\(player.id)"))
                    XCTAssertEqual(entity.scale, .one, "\(view) \(selected) \(player.id)")
                    rows.append(["playerID": player.id, "team": player.team.rawValue,
                        "selectedID": selected, "view": view.rawValue,
                        "scale": [entity.scale.x, entity.scale.y, entity.scale.z]])
                }
            }
        }
        let data = try JSONSerialization.data(withJSONObject: ["samples": rows], options: [.sortedKeys])
        let attachment = XCTAttachment(data: data, uniformTypeIdentifier: "public.json")
        attachment.name = "ReplayXI-Players124-PhysicalScale.json"
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
