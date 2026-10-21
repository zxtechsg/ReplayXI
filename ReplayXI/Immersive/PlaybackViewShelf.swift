import SwiftUI

/// One expanded group at a time. Selecting a section never moves the room
/// anchor, changes the replay clock, or silently changes the camera.
enum PlaybackViewShelf: String, CaseIterable, Identifiable, Sendable {
    case camera, overlays, space
    var id: Self { self }
    var title: String {
        switch self { case .camera: "View"; case .overlays: "Overlays"; case .space: "Room" }
    }
    var systemImage: String {
        switch self { case .camera: "viewfinder"; case .overlays: "square.3.layers.3d"; case .space: "cube.transparent" }
    }
}

struct PlaybackViewShelfPicker: View {
    @Binding var selection: PlaybackViewShelf

    var body: some View {
        HStack(spacing: 6) {
            ForEach(PlaybackViewShelf.allCases) { section in
                Button { selection = section } label: {
                    Image(systemName: section.systemImage)
                        .font(.title3.weight(.semibold))
                        .frame(maxWidth: .infinity, minHeight: 60)
                        .contentShape(RoundedRectangle(cornerRadius: 12))
                }
                .buttonStyle(.plain)
                .foregroundStyle(selection == section ? Color.black : Color.white)
                .background(selection == section ? ReplayTheme.signal : .white.opacity(0.08),
                            in: RoundedRectangle(cornerRadius: 12))
                .hoverEffect(.highlight)
                .help(section == .space
                    ? "Room controls. Pinch both hands: move together to place the pitch; spread or close to resize."
                    : "\(section.title) controls")
                .accessibilityLabel("\(section.title) controls")
                .accessibilityHint(section == .space
                    ? "Pinch both hands to place or resize the pitch. The workspace stays fixed after recentering."
                    : "Shows \(section.title.lowercased()) controls")
                .accessibilityAddTraits(selection == section ? .isSelected : [])
            }
        }
    }
}
