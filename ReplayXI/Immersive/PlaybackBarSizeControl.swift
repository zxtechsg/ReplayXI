import SwiftUI

struct PlaybackBarSizeControl: View {
    @Binding var size: Double
    private var safeSize: Binding<Double> {
        Binding(get: { PlaybackControlDeckLayout.clampedSize(size) },
                set: { size = PlaybackControlDeckLayout.clampedSize($0) })
    }
    private var percentage: String {
        "\(Int((safeSize.wrappedValue * 100).rounded()))%"
    }

    var body: some View {
        HStack(spacing: 16) {
            Label("Bar size", systemImage: "arrow.up.left.and.arrow.down.right")
                .font(.subheadline.weight(.semibold)).fixedSize()
            Slider(value: safeSize, in: 0.8...1.5, step: 0.05)
                .accessibilityLabel("Control bar size")
                .accessibilityValue(percentage)
                .accessibilityHint("Changes size without moving the controls")
            Text(percentage).font(.subheadline.monospacedDigit().weight(.semibold))
                .frame(minWidth: 64).fixedSize()
            Button { size = 1 } label: {
                Image(systemName: "arrow.counterclockwise").frame(minWidth: 52, minHeight: 52)
            }
            .buttonStyle(.bordered)
            .disabled(abs(safeSize.wrappedValue - 1) < 0.001)
            .accessibilityLabel("Reset bar size to 100 percent")
            .help("Reset size")
        }
    }
}
