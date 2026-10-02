import Foundation
import Observation

/// A one-shot UI request, separate from persisted annotations and drawing state.
/// The room ID prevents a cancelled entry from opening tools in a later room.
@MainActor
@Observable
final class ReplayAnnotationEntrySession {
    struct Request: Equatable, Sendable {
        let id = UUID()
        let roomID: UUID
        let scenarioID: String
    }

    private(set) var pending: Request?

    func request(roomID: UUID, scenarioID: String) {
        pending = Request(roomID: roomID, scenarioID: scenarioID)
    }

    @discardableResult
    func consume(roomID: UUID, scenarioID: String) -> Bool {
        guard let request = pending, request.roomID == roomID else { return false }
        pending = nil
        return request.scenarioID == scenarioID
    }

    func cancel(roomID: UUID) {
        guard pending?.roomID == roomID else { return }
        pending = nil
    }
}
