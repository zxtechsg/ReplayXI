import Foundation
import simd

/// Prepared once from admitted native contacts, never from future targets or
/// the current playback direction. Only actual opposing shots cue a keeper.
struct ReplayFootballShotTimeline: Sendable {
    private let home: [ReplayGoalkeeperReadiness.Shot]
    private let away: [ReplayGoalkeeperReadiness.Shot]

    init(touches: [ReplayNativeBallPhysics.Touch], players: [PlayerTrack]) {
        var teams: [String: FootballTeam] = [:]
        var duplicateIDs = Set<String>()
        for player in players {
            if teams.updateValue(player.team, forKey: player.id) != nil { duplicateIDs.insert(player.id) }
        }
        var home: [ReplayGoalkeeperReadiness.Shot] = []
        var away: [ReplayGoalkeeperReadiness.Shot] = []
        let contactTimes = touches.filter {
            $0.time.isFinite && $0.time >= 0 && teams[$0.playerID] != nil
                && !duplicateIDs.contains($0.playerID)
        }.map(\.time).sorted()
        for touch in touches where touch.kind == .shot {
            guard touch.time.isFinite, touch.time >= 0,
                  touch.position.x.isFinite, touch.position.y.isFinite, touch.position.z.isFinite,
                  touch.outgoingVelocity.x.isFinite, touch.outgoingVelocity.y.isFinite,
                  touch.outgoingVelocity.z.isFinite,
                  !duplicateIDs.contains(touch.playerID), let team = teams[touch.playerID] else { continue }
            var shot = ReplayGoalkeeperReadiness.Shot(time: touch.time, origin: touch.position,
                                                     velocity: touch.outgoingVelocity)
            // A subsequent recorded touch changes flight. The helper only
            // consumes this cutoff once playback reaches it, with a short
            // release rather than reviving the old velocity after a save.
            shot.supersededAt = contactTimes.first { $0 > touch.time }
            if team == .home { home.append(shot) } else { away.append(shot) }
        }
        self.home = home.sorted { $0.time < $1.time }
        self.away = away.sorted { $0.time < $1.time }
    }

    func latestOpposingShot(for player: PlayerTrack, at time: TimeInterval) -> ReplayGoalkeeperReadiness.Shot? {
        guard player.isGoalkeeper, time.isFinite else { return nil }
        let shots = player.team == .home ? away : home
        var lower = 0
        var upper = shots.count
        while lower < upper {
            let middle = lower + (upper - lower) / 2
            if shots[middle].time <= time { lower = middle + 1 } else { upper = middle }
        }
        return lower > 0 ? shots[lower - 1] : nil
    }
}
