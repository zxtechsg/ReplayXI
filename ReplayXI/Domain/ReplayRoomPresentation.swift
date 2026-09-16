import Foundation

/// Device-local presentation ownership. Open/dismiss callbacks and view events
/// can arrive in either order; only their current request may change the room.
struct ReplayRoomPresentation: Equatable, Sendable {
    enum Phase: Equatable, Sendable { case closed, opening, open, closing }

    private(set) var phase: Phase = .closed
    private(set) var requestID: UUID?
    private(set) var isVisible = false
    private var openingCompleted = false
    private var dismissalCompleted = false

    var isBusy: Bool { phase != .closed }
    var isOpening: Bool { phase == .opening }
    var isClosing: Bool { phase == .closing }
    var isOpen: Bool { phase == .open || (phase == .closing && isVisible) }

    func owns(_ id: UUID) -> Bool { requestID == id && isBusy }
    func isOpeningRequest(_ id: UUID) -> Bool { requestID == id && phase == .opening }
    func acceptsInteraction(for id: UUID) -> Bool { owns(id) && phase == .open && isVisible }

    mutating func beginOpening() -> UUID? {
        guard !isBusy else { return nil }
        let id = UUID()
        requestID = id
        phase = .opening
        isVisible = false
        openingCompleted = false
        dismissalCompleted = false
        return id
    }

    /// Appearance can precede the result of openImmersiveSpace.
    mutating func didAppear(_ id: UUID) -> UUID? {
        guard owns(id), phase == .opening || phase == .open else { return nil }
        phase = .open
        isVisible = true
        return id
    }

    @discardableResult
    mutating func completeOpening(_ id: UUID, opened: Bool) -> Bool {
        guard owns(id), !openingCompleted, phase == .opening || phase == .open else { return false }
        // A contradictory late failure must not erase a room that is visible.
        guard opened || !isVisible else { return false }
        openingCompleted = true
        if opened {
            phase = .open
        } else {
            self = Self()
        }
        return true
    }

    mutating func beginClosing(_ id: UUID) -> Bool {
        guard owns(id), phase == .open else { return false }
        phase = .closing
        dismissalCompleted = false
        return true
    }

    /// Keep Enter disabled until both explicit dismissal and disappearance
    /// finish. A system dismissal, with no pending dismiss call, closes now.
    @discardableResult
    mutating func didDisappear(_ id: UUID) -> Bool {
        guard owns(id), isVisible else { return false }
        isVisible = false
        if phase != .closing || dismissalCompleted { self = Self() }
        return true
    }

    @discardableResult
    mutating func completeClosing(_ id: UUID) -> Bool {
        guard owns(id), phase == .closing, !dismissalCompleted else { return false }
        dismissalCompleted = true
        if !isVisible { self = Self() }
        return true
    }
}
