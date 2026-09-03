import SwiftUI

/// A compact, descriptive freeze-frame readout. Metrics explain the geometry
/// available to the selected player; they deliberately do not grade a decision
/// or claim access to eye gaze.
struct PlaybackDecisionStrip: View {
    let snapshot: ReplayDecisionSnapshot
    let scenario: ReplayScenario
    let onSelectPlayer: (String) -> Void
    let onClose: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Button(action: onClose) {
                Image(systemName: "xmark")
                    .frame(width: 32, height: 56)
            }
            .buttonStyle(.bordered)
            .accessibilityLabel("Close decision options")

            VStack(alignment: .leading, spacing: 3) {
                Eyebrow(text: "Options", color: ReplayTheme.cyan)
                Text(snapshot.evidence.compactLabel)
                    .font(.caption2.monospaced().weight(.black))
                    .foregroundStyle(.secondary)
            }
            .frame(width: 104, alignment: .leading)

            metric(
                value: "\(snapshot.scanWindow.duration.formatted(.number.precision(.fractionLength(1))))s",
                label: "SCAN"
            )
            metric(
                value: "\(Int(snapshot.scanWindow.bodyTurnDegrees.rounded()))°",
                label: "BODY"
            )

            Divider()
                .frame(height: 42)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(snapshot.passingOptions) { option in
                        optionButton(option)
                    }
                }
                .padding(.horizontal, 2)
            }
            // A horizontal ScrollView otherwise accepts the parent's proposed
            // height in a glass attachment, producing a large empty sheet.
            .frame(height: 60)
            .layoutPriority(1)
        }
        .padding(10)
        .frame(height: 80)
        .background(ReplayTheme.cyan.opacity(0.07), in: RoundedRectangle(cornerRadius: 17))
        .overlay {
            RoundedRectangle(cornerRadius: 17)
                .stroke(ReplayTheme.cyan.opacity(0.24), lineWidth: 1)
        }
        .accessibilityElement(children: .contain)
        .accessibilityHint(
            "\(ReplayDecisionScanWindow.evidenceLabel) \(snapshot.evidence.provenance.confidenceLabel)"
        )
    }

    private func metric(value: String, label: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(value)
                .font(.headline.monospacedDigit().weight(.black))
            Text(label)
                .font(.caption2.monospaced().weight(.black))
                .foregroundStyle(.secondary)
        }
        .frame(width: 66, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    private func optionButton(_ option: ReplayPassingLaneOption) -> some View {
        let player = scenario.player(id: option.receiverID)
        let role = option.isReplayedDestination
            ? "PLAYED"
            : (option.isCoachSuggestion ? "COACH" : "OPTION")
        let color = optionColor(option)
        let clearance = option.laneClearanceMetres.map {
            $0.formatted(.number.precision(.fractionLength(1))) + "m"
        } ?? "OPEN"

        return Button {
            onSelectPlayer(option.receiverID)
        } label: {
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 5) {
                    Text("#\(player?.shirtNumber ?? 0) \(player?.positionCode ?? "—")")
                        .font(.subheadline.monospacedDigit().weight(.black))
                    Text(role)
                        .font(.caption2.monospaced().weight(.black))
                        .foregroundStyle(color)
                }
                Text("\(option.availability.rawValue.uppercased()) · \(clearance)")
                    .font(.caption2.monospacedDigit().weight(.bold))
                    .foregroundStyle(.secondary)
            }
            .frame(minWidth: 124, minHeight: 56, alignment: .leading)
        }
        .buttonStyle(.borderedProminent)
        .tint(color.opacity(0.18))
        .foregroundStyle(.white)
        .accessibilityLabel(
            "Number \(player?.shirtNumber ?? 0), \(player?.role ?? "player"), \(role.lowercased()) option"
        )
        .accessibilityValue(
            "\(option.availability.rawValue), lane clearance \(clearance)"
        )
        .accessibilityHint("Opens this player's freely lookable point of view")
    }

    private func optionColor(_ option: ReplayPassingLaneOption) -> Color {
        if option.isCoachSuggestion { return ReplayTheme.signal }
        return switch option.availability {
        case .blocked: ReplayTheme.danger
        case .tight: ReplayTheme.orange
        case .clear: ReplayTheme.cyan
        }
    }
}
