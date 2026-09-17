import Foundation
import XCTest
@testable import ReplayXI

@MainActor
final class PlayerPositionCodeTests: XCTestCase {
    func testConventionalAbbreviationsKeepEveryLetter() {
        let codes = ["GK", "RB", "RCB", "CB", "LCB", "LB", "RWB", "WB", "LWB",
                     "DM", "RDM", "LDM", "CDM", "CM", "RCM", "LCM", "RM", "LM",
                     "AM", "CAM", "RAM", "LAM", "RW", "LW", "CF", "ST", "SS", "RF", "LF"]
        for code in codes {
            for role in [code, code.lowercased(), " \t\(code)\n"] {
                XCTAssertEqual(player(role: role).positionCode, code, role)
            }
        }
    }

    func testLegacyNamedRolesKeepTheirCodesAcrossWhitespaceCaseAndDashVariants() {
        let roles = ["Goalkeeper": "GK", "Right back": "RB", "Right centre-back": "RCB",
                     "Left centre-back": "LCB", "Left back": "LB", "Holding midfielder": "DM",
                     "Right holding midfielder": "RDM", "Left holding midfielder": "LDM",
                     "Right midfielder": "RM", "Left midfielder": "LM", "Attacking midfielder": "AM",
                     "Right winger": "RW", "Centre forward": "CF", "Left winger": "LW"]
        for (role, code) in roles {
            let words = role.replacingOccurrences(of: "-", with: " ").components(separatedBy: " ")
            for separator in [" ", "  ", "\t", "\n", "-", "‐", "‑", "‒", "–", "—", "−"] {
                let variant = " \t" + words.joined(separator: separator).uppercased() + "\n"
                XCTAssertEqual(player(role: variant).positionCode, code, variant)
            }
        }
    }

    func testReferenceSlotsStayHonestAboutTheirAuthoredMeaning() {
        let expected = ["Goalkeeper": "GK", "Right back": "RB", "Right centre-back": "RCB",
                        "Left centre-back": "LCB", "Left back": "LB", "Holding midfield": "DM",
                        "Right support": "RS", "Left support": "LS", "Right attack": "RA",
                        "Centre-forward": "CF", "Left attack": "LA"]
        for scenario in FootballReferenceScenarios.all where FootballReferenceScenarios.worldCupIDs.contains(scenario.id) {
            for track in scenario.players {
                XCTAssertEqual(track.positionCode, expected[track.role], "\(scenario.id): \(track.role)")
                XCTAssertLessThanOrEqual(track.positionCode.count, 3)
            }
        }
        for code in ["RS", "LS", "RA", "LA"] {
            XCTAssertEqual(player(role: code).positionCode, code)
        }
    }

    func testUnknownRolesHaveShortFallbackWithoutAnInventedPosition() {
        XCTAssertEqual(player(role: "Pressing trigger").positionCode, "PT")
        XCTAssertEqual(player(role: "Midfielder").positionCode, "M")
        XCTAssertEqual(player(role: "Free roaming supporting player").positionCode, "FRS")
        XCTAssertEqual(player(role: "  Test\tRole\nLabel   Extra").positionCode, "TRL")
        XCTAssertEqual(player(role: "8").positionCode, "8")
        for role in ["", " \t\n", "—", "! ?"] {
            XCTAssertEqual(player(role: role).positionCode, "—")
        }
    }

    func testCompactLabelDoesNotRewriteAuthoredRoleOrEncodedReview() throws {
        let role = "  Centre‑forward\t"
        let original = player(role: role)
        XCTAssertEqual(original.positionCode, "CF")
        XCTAssertEqual(original.role, role)
        let data = try JSONEncoder().encode(original)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(object["role"] as? String, role)
        XCTAssertNil(object["positionCode"])
        let decoded = try JSONDecoder().decode(PlayerTrack.self, from: data)
        XCTAssertEqual(decoded, original)
        XCTAssertEqual(decoded.role, role)
        XCTAssertEqual(decoded.positionCode, "CF")
    }

    private func player(role: String) -> PlayerTrack {
        PlayerTrack(id: "position-code", displayName: "Player", role: role, shirtNumber: 8,
                    team: .home, isGoalkeeper: false, keyframes: [])
    }
}
