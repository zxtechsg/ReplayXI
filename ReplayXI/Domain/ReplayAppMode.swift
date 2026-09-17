import Foundation

/// Navigation groups reuse stable scenario IDs and saved review formats.
enum ReplayAppMode: String, CaseIterable, Identifiable, Hashable, Sendable {
    case situationRoleplay
    case matchReplay

    var id: String { rawValue }

    init(scenario: ReplayScenario) {
        self = scenario.kind == .realWorldReplay ? .matchReplay : .situationRoleplay
    }

    var title: String {
        switch self {
        case .situationRoleplay: "Strategy analysis"
        case .matchReplay: "Match replay"
        }
    }

    var subtitle: String {
        switch self {
        case .situationRoleplay: "3D plays, POVs and annotations"
        case .matchReplay: "Synthetic match demo"
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

    func featuredScenarios(in catalogue: [ReplayScenario]) -> [ReplayScenario] {
        let available = scenarios(in: catalogue)
        let studies = available.filter { FootballReferenceScenarios.contains($0) }
        return self == .situationRoleplay && !studies.isEmpty ? studies : available
    }

    func scenarioID(in catalogue: [ReplayScenario], preferredID: String?) -> String? {
        let available = scenarios(in: catalogue)
        if let preferredID, available.contains(where: { $0.id == preferredID }) {
            return preferredID
        }
        return available.first?.id
    }

    static func exerciseTitle(for scenario: ReplayScenario) -> String {
        if FootballReferenceScenarios.contains(scenario) { return scenario.title }
        return switch scenario.kind {
        case .squadReplay: "Team perspectives"
        case .coachFocus: "Coach demonstration"
        case .shapeLab: "Positioning"
        case .passingChannels: "Passing lanes"
        case .perspectiveMatrix: "Compare POVs"
        case .realWorldReplay: "Demo match"
        }
    }
}
