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
                    VStack(spacing: 3) {
                        Image(systemName: section.systemImage).font(.headline)
                        Text(section.title).font(.caption.weight(.semibold))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .frame(maxWidth: .infinity, minHeight: 60)
                    .contentShape(RoundedRectangle(cornerRadius: 12))
                }
                .buttonStyle(.plain)
                .foregroundStyle(selection == section ? Color.black : Color.white)
                .background(selection == section ? ReplayTheme.signal : .white.opacity(0.08),
                            in: RoundedRectangle(cornerRadius: 12))
                .hoverEffect(.highlight)
                .accessibilityLabel("\(section.title) controls")
                .accessibilityAddTraits(selection == section ? .isSelected : [])
            }
        }
    }
}
