import Foundation

/// Navigation groups reuse stable scenario IDs. Saved reviews and shared-room
/// payloads keep their existing format when the dashboard changes shape.
enum ReplayAppMode: String, CaseIterable, Identifiable, Hashable, Sendable {
    case situationRoleplay
    case matchReplay

    var id: String { rawValue }

    init(scenario: ReplayScenario) {
        self = scenario.kind == .realWorldReplay ? .matchReplay : .situationRoleplay
    }

    var title: String {
        switch self {
        case .situationRoleplay: "Situation roleplay"
        case .matchReplay: "Match replay"
        }
    }

    var subtitle: String {
        switch self {
        case .situationRoleplay: "Synthetic 3D exercises"
        case .matchReplay: "Synthetic reconstruction preview"
        }
    }

    var systemImage: String {
        switch self {
        case .situationRoleplay: "figure.soccer"
        case .matchReplay: "play.rectangle"
        }
    }

    func scenarios(in catalogue: [ReplayScenario]) -> [ReplayScenario] {
        catalogue.filter { ReplayAppMode(scenario: $0) == self }
    }

    func scenarioID(in catalogue: [ReplayScenario], preferredID: String?) -> String? {
        let available = scenarios(in: catalogue)
        if let preferredID, available.contains(where: { $0.id == preferredID }) {
            return preferredID
        }
        return available.first?.id
    }

    static func exerciseTitle(for scenario: ReplayScenario) -> String {
        switch scenario.kind {
        case .squadReplay: "Team perspectives"
        case .coachFocus: "Coach demonstration"
        case .shapeLab: "Positioning"
        case .passingChannels: "Passing lanes"
        case .perspectiveMatrix: "Compare POVs"
        case .realWorldReplay: "Reconstruction demo"
        }
    }
}
