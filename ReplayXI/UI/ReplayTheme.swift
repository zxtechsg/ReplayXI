import SwiftUI

enum ReplayTheme {
    static let signal = Color(red: 0.78, green: 0.94, blue: 0.19)
    static let cyan = Color(red: 0.22, green: 0.91, blue: 0.88)
    static let orange = Color(red: 1.0, green: 0.42, blue: 0.12)
    static let danger = Color(red: 1.0, green: 0.25, blue: 0.34)
    static let navy = Color(red: 0.07, green: 0.12, blue: 0.24)
    static let red = Color(red: 0.66, green: 0.09, blue: 0.13)
    static let pitch = Color(red: 0.035, green: 0.17, blue: 0.11)
    static let panel = Color.white.opacity(0.065)
    static let hairline = Color.white.opacity(0.11)
}

struct Eyebrow: View {
    let text: String
    var color: Color = ReplayTheme.signal

    var body: some View {
        Text(text.uppercased())
            .font(.caption2.monospaced().weight(.black))
            .tracking(1.4)
            .foregroundStyle(color)
    }
}

struct StatusPill: View {
    let text: String
    let systemImage: String
    var color: Color = ReplayTheme.signal

    var body: some View {
        Label(text.uppercased(), systemImage: systemImage)
            .font(.caption2.monospaced().weight(.bold))
            .foregroundStyle(color)
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(color.opacity(0.11), in: Capsule())
            .overlay {
                Capsule().stroke(color.opacity(0.28), lineWidth: 1)
            }
    }
}

struct MetricTile: View {
    let value: String
    let label: String

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(value)
                .font(.title3.monospacedDigit().weight(.black))
                .foregroundStyle(.white)
            Text(label.uppercased())
                .font(.caption2.monospaced().weight(.bold))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(ReplayTheme.panel, in: RoundedRectangle(cornerRadius: 16))
        .overlay {
            RoundedRectangle(cornerRadius: 16).stroke(ReplayTheme.hairline, lineWidth: 1)
        }
    }
}

struct KeyHint: View {
    let text: String
    let systemImage: String

    var body: some View {
        Label(text, systemImage: systemImage)
            .font(.caption.weight(.medium))
            .foregroundStyle(.secondary)
    }
}
