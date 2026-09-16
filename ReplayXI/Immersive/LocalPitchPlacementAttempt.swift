import Foundation

/// The preflight that started a request owns its result. Returning to Ideal,
/// withdrawing consent or closing the panel retires that ownership immediately,
/// even if ARKit ignores task cancellation until its next completion.
struct LocalPitchPlacementAttempt: Equatable, Sendable {
    private(set) var id: UUID?
    var isPending: Bool { id != nil }

    mutating func begin() -> UUID? {
        guard id == nil else { return nil }
        let request = UUID()
        id = request
        return request
    }

    func owns(_ request: UUID) -> Bool { id == request }

    @discardableResult
    mutating func finish(_ request: UUID) -> Bool {
        guard owns(request) else { return false }
        id = nil
        return true
    }

    mutating func cancel() { id = nil }
}
