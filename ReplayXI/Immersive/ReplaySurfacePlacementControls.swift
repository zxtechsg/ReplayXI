import SwiftUI

/// Surface placement lives under View & overlays, not on the transport bar.
/// Discovery never places or moves the pitch until the wearer presses Place.
struct ReplaySurfacePlacementControls: View {
    let targetLabel: String?
    let statusText: String
    let isBusy: Bool
    let isScanning: Bool
    let hasPlacement: Bool
    let canEdit: Bool
    let findSurface: () -> Void
    let place: () -> Void
    let reset: () -> Void
    let cancel: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Eyebrow(text: "Pitch placement", color: ReplayTheme.cyan)
            Button(action: targetLabel == nil ? findSurface : place) {
                Label(targetLabel.map { "Place on \($0.lowercased())" } ?? (hasPlacement ? "Move pitch" : "Find a surface"),
                      systemImage: targetLabel == nil ? "viewfinder" : "pin.fill")
                    .font(.subheadline.weight(.semibold))
                    .frame(maxWidth: .infinity, minHeight: 60)
                    .foregroundStyle(.black)
                    .background(ReplayTheme.signal, in: Capsule())
            }
            .buttonStyle(.plain)
            .disabled(!canEdit || isBusy)
            .accessibilityHint(targetLabel == nil
                ? "Detects floors and tables, then lets you confirm placement."
                : "Places the level pitch on this surface. Controls stay where they are.")
            if isScanning {
                Button("Cancel scan", systemImage: "xmark", action: cancel)
                    .buttonStyle(.bordered).controlSize(.large)
            }
            if targetLabel != nil || hasPlacement {
                HStack(spacing: 8) {
                    if targetLabel != nil {
                        Button("Scan again", systemImage: "arrow.clockwise", action: findSurface)
                    }
                    if hasPlacement {
                        Button("Reset pitch", systemImage: "arrow.uturn.backward", action: reset)
                    }
                }
                .font(.caption.weight(.semibold))
                .buttonStyle(.bordered)
                .controlSize(.large)
                .disabled(!canEdit || isBusy)
            }
            HStack(alignment: .top, spacing: 6) {
                if isBusy { ProgressView().controlSize(.small) }
                Text(statusText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}
