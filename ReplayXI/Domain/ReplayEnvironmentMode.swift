import Foundation

/// A local presentation preference, not part of a saved match or annotation.
enum ReplayEnvironmentMode: String, CaseIterable, Identifiable {
    case room
    case stadium

    static let storageKey = "ReplayXI.EnvironmentMode"
    static let defaultSelection = Self.stadium
    var id: String { rawValue }
    var title: String { self == .stadium ? "Stadium" : "Room" }
    var systemImage: String { self == .stadium ? "sportscourt" : "house" }

    static func effective(_ rawValue: String, isPhysicalPractice: Bool) -> Self {
        // Physical placement must keep passthrough, regardless of the last
        // replay choice. Unknown saved values also fail back to the room.
        guard !isPhysicalPractice else { return .room }
        return Self(rawValue: rawValue) ?? .room
    }
}
