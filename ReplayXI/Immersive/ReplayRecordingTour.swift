#if DEBUG
import Foundation

/// Opt-in native-app capture route. Demo launch configuration supplies a
/// transient review library; this never runs in tests or a normal launch.
@MainActor
enum ReplayRecordingTour {
    static func run(store: ReplayStore, roomID: UUID,
                    ready: () -> Bool, selectMark: (UUID?) -> Void) async {
        func valid() -> Bool {
            !Task.isCancelled && store.roomPresentation.acceptsInteraction(for: roomID)
        }
        func wait(_ seconds: Double) async -> Bool {
            do { try await Task.sleep(for: .seconds(seconds)) } catch { return false }
            return valid()
        }
        guard await wait(3) else { return }
        let ids = ["final-36-counter-v2", "final-81-volley-v2", "final-108-rebound-v2",
                   "city-45-overlap-header", "city-57-underlap-cutback"]
        for id in ids {
            guard valid() else { return }
            selectMark(nil)
            store.setPlaying(false, broadcast: false)
            store.selectScenario(id: id, broadcast: false)
            store.setViewMode(.tacticalTable)
            guard await wait(0.25) else { return }
            var admitted = false
            for _ in 0..<240 {
                if ready() { admitted = true; break }
                guard await wait(0.25) else { return }
            }
            guard admitted, valid() else { return }
            store.seek(to: 0, broadcast: false)
            store.setPlaybackRate(1, broadcast: false)
            store.setPlaying(true, broadcast: false)
            guard await wait(store.selectedScenario.duration + 0.5) else { return }

            store.seek(to: 1, broadcast: false)
            store.openLocalPlayerPOV(store.selectedScenario.defaultPerspectiveID)
            guard await wait(0.3) else { return }
            faceBall(store)
            store.setPlaying(true, broadcast: false)
            guard await wait(3) else { return }
            if let other = store.selectedScenario.awayPlayers.first(where: { !$0.isGoalkeeper }) {
                store.openLocalPlayerPOV(other.id)
                faceBall(store)
                store.setPlaying(true, broadcast: false)
                guard await wait(2) else { return }
            }
            store.setViewMode(.touchline)
            store.setPlaybackRate(0.5, broadcast: false)
            store.setPlaying(true, broadcast: false)
            guard await wait(2) else { return }
            store.setPlaying(false, broadcast: false)
            store.setPlaybackRate(1, broadcast: false)
            store.setViewMode(.tacticalTable)
            store.seek(to: 1, broadcast: false)
            store.beginDrawing(.arc)
            _ = store.registerPitchTap(.init(x: -8, z: 0))
            guard let mark = store.registerPitchTap(.init(x: 12, z: 22)) else { return }
            selectMark(mark.id)
            _ = store.setCoachMarkWindow(id: mark.id, start: 1, end: min(8, store.selectedScenario.duration))
            _ = store.captureCoachMarkKeyframe(id: mark.id)
            guard await wait(1.5) else { return }
            store.seek(to: 4, broadcast: false)
            _ = store.setMacCoachMarkPose(id: mark.id, start: .init(x: -2, z: 5),
                end: .init(x: 20, z: 26), startElevation: 0, endElevation: 1.5,
                controlPoint: nil, recordMotion: true)
            guard await wait(2) else { return }
            store.seek(to: 1, broadcast: false)
            store.setPlaying(true, broadcast: false)
            guard await wait(3) else { return }
            store.setPlaying(false, broadcast: false)
        }
    }

    private static func faceBall(_ store: ReplayStore) {
        let ball = store.selectedScenario.ball.pose(at: store.playhead)
        let target = store.macRenderedBallSample.flatMap { sample in
            sample.scenarioID == store.selectedScenarioID && abs(sample.time - store.playhead) < 0.05
                ? sample.position : nil
        } ?? .init(ball.position.x, ball.height, ball.position.z)
        _ = store.facePOVTowards(target)
    }
}
#endif
