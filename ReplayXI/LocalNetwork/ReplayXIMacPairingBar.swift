import SwiftUI

struct ReplayXIMacPairingBar: View {
    let service: ReplayXILocalCoachService

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "laptopcomputer.and.visionpro")
            Text("Mac coach")
                .fontWeight(.semibold)
            Text(service.isPaired ? "Connected" : service.isRunning ? "PIN \(service.pin)" : "Off")
                .monospacedDigit()
                .fontWeight(.bold)
            Text(service.status)
                .lineLimit(1)
                .foregroundStyle(.secondary)
            Spacer()
            Button(service.isRunning ? "Stop Mac link" : "Start Mac link") {
                if service.isRunning { service.stop() } else { service.start() }
            }
            if service.isRunning && !service.isPaired {
                Button("New PIN") { service.resetPairing() }
            }
        }
        .font(.caption)
        .padding(.horizontal, 16)
        .padding(.vertical, 9)
        .background(.ultraThinMaterial)
    }
}
