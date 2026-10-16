import Foundation

/// Give the dashboard a scheduling point and a cancellation check between
/// resource families. RealityKit resources stay on their owning main actor.
@MainActor
enum ReplayVisualPreparation {
    enum Step: CaseIterable, Equatable, Sendable {
        case environment, tripoPlayers, fallbackPlayers, athleteMeshes, importedPilot
        case farHeads, articulatedBodies, farKits, ball, pitch, stadium

        var label: String {
            switch self {
            case .environment, .stadium: "Preparing stadium…"
            case .athleteMeshes, .importedPilot: "Preparing player meshes…"
            case .tripoPlayers, .fallbackPlayers: "Preparing player animation…"
            case .farHeads, .articulatedBodies, .farKits: "Preparing squad details…"
            case .ball: "Preparing ball…"
            case .pitch: "Preparing pitch…"
            }
        }
    }

    static func run(shouldContinue: () -> Bool = { true },
                    progress: (String) -> Void = { _ in },
                    perform: (Step) throws -> Void) async throws {
        for step in Step.allCases {
            try Task.checkCancellation()
            guard shouldContinue() else { throw CancellationError() }
            progress(step.label)
            await Task.yield()
            try Task.checkCancellation()
            guard shouldContinue() else { throw CancellationError() }
            try perform(step)
        }
    }
}
