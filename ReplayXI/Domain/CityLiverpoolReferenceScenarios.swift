import Foundation
import simd

/// Two authored reconstructions of Manchester City 4–0 Liverpool, 4 April 2026.
/// The video establishes the visible combinations, not full-pitch tracking.
/// Off-camera paths, metric coordinates and exact body/gaze poses are inferred.
enum CityLiverpoolReferenceScenarios {
    static let ids = ["city-45-overlap-header", "city-57-underlap-cutback"]
    static let all: [ReplayScenario] = [overlapHeader, underlapCutback]

    static func contains(_ scenario: ReplayScenario) -> Bool { ids.contains(scenario.id) }

    static func touches(for scenario: ReplayScenario) -> [ReplayNativeBallPhysics.PlannedTouch]? {
        let beats: [Beat]
        switch scenario.id {
        case ids[0]: beats = headerBeats
        case ids[1]: beats = cutbackBeats
        default: return nil
        }
        return zip(beats, beats.dropFirst()).map { current, next in
            .init(time: current.time, playerID: current.playerID, kind: current.kind,
                  kickingLeg: current.leg, target: next.point, targetHeight: next.height,
                  arrivalTime: next.time)
        }
    }

    private struct Beat {
        let time: Double
        let playerID: String
        let point: PitchPoint
        let height: Float
        let kind: ReplayNativeBallPhysics.TouchKind
        let leg: ReplayAthleteLeg

        init(_ time: Double, _ playerID: String, _ x: Float, _ z: Float,
             height: Float = 0.11, kind: ReplayNativeBallPhysics.TouchKind = .pass,
             leg: ReplayAthleteLeg = .right) {
            self.time = time
            self.playerID = playerID
            point = .init(x: x, z: z)
            self.height = height
            self.kind = kind
            self.leg = leg
        }
    }

    private struct Waypoint {
        let time: Double
        let point: PitchPoint
        init(_ time: Double, _ x: Float, _ z: Float) {
            self.time = time
            point = .init(x: x, z: z)
        }
    }

    // Receive/dribble beats describe the carry between visible release and
    // cross. Their feet/timing are authored, not frame-tracked footfalls.
    // The release, cross, cutback and finish feet were checked in the replays.
    private static let headerBeats: [Beat] = [
        .init(0, "city-10", 18, 33.5),
        .init(1.4, "city-42", 24, 39, kind: .receive, leg: .left),
        .init(2.2, "city-42", 24, 42.5, kind: .dribbleTouch, leg: .left),
        .init(3.0, "city-42", 24, 46),
        .init(4.25, "city-9", 1, 46.2, height: 1.55, kind: .header),
        .init(4.85, "", -2.5, 54, height: 0.75)
    ]

    private static let cutbackBeats: [Beat] = [
        .init(0, "city-11", -22, 32),
        .init(1.5, "city-33", -16, 39, kind: .receive, leg: .left),
        .init(2.2, "city-33", -14, 42.5, kind: .dribbleTouch, leg: .left),
        .init(3.0, "city-33", -12, 46, leg: .left),
        .init(4.0, "city-9", -1, 41.5, kind: .shot, leg: .left),
        .init(4.7, "", -2.5, 54, height: 2.34)
    ]

    private static var overlapHeader: ReplayScenario {
        make(id: ids[0], title: "Overlap and header", minute: "45+2′", duration: 10,
             beats: headerBeats, perspective: "city-42",
             objective: "Release the overlap. Cross before the back line can reset.",
             cues: [(0, "Release outside", "Cherki releases Semenyo beyond the full-back."),
                    (3, "Cross on the run", "Semenyo delivers from the right; Haaland attacks in front of his marker."),
                    (4.25, "Across the keeper", "Haaland glances the header towards the far corner.")],
             paths: [
                "city-1": [.init(0,0,-42), .init(5,1,-40), .init(10,1,-39)],
                "city-27": [.init(0,23,20), .init(3,24,24), .init(5,22,27), .init(10,21,26)],
                "city-45": [.init(0,10,2), .init(4,12,5), .init(10,12,7)],
                "city-15": [.init(0,-7,3), .init(4,-5,6), .init(10,-5,7)],
                "city-33": [.init(0,-20,21), .init(3,-17,27), .init(5,-15,30), .init(10,-14,29)],
                "city-16": [.init(0,2,17), .init(3,5,22), .init(5,5,24), .init(10,4,24)],
                "city-20": [.init(0,10,27), .init(3,12,31), .init(5,10,35), .init(10,9,36)],
                "city-10": [.init(0,18,33), .init(1.4,18,34), .init(3,17,36), .init(5,14,38), .init(10,12,39)],
                "city-42": [.init(0,23,32), .init(1.4,24,38.5), .init(2.2,24,42), .init(3,24.4,45.5), .init(4.25,23,48), .init(6,20,49), .init(10,18,47)],
                "city-11": [.init(0,-19,33), .init(3,-15,39), .init(4.25,-11,44), .init(6,-8,47), .init(10,-7,47)],
                "city-9": [.init(0,3,37), .init(1.4,3,40), .init(3,2.5,43), .init(4.25,1.04,46), .init(5.5,-1,48), .init(10,-2,48)],
                "liv-25": [.init(0,1,50), .init(3,2.5,49.6), .init(4.25,2.2,49.3), .init(5.5,0.5,50), .init(10,0,50)],
                "liv-2": [.init(0,-16,37), .init(3,-13,42), .init(4.25,-10,45), .init(6,-9,47), .init(10,-8,46)],
                "liv-5": [.init(0,4,38), .init(1.4,4,41), .init(3,4,44), .init(4.25,3,46.4), .init(6,1,48), .init(10,1,47)],
                "liv-4": [.init(0,-5,38), .init(3,-4,42), .init(4.25,-4,45.4), .init(6,-3.8,49), .init(10,-4,47)],
                "liv-6": [.init(0,18,36.5), .init(1.4,21.6,39), .init(3,20.5,44), .init(4.25,20,46), .init(6,18.5,48), .init(10,16,46)],
                "liv-38": [.init(0,6,30), .init(3,7,35), .init(4.25,6,39), .init(6,5,42), .init(10,5,40)],
                "liv-17": [.init(0,-5,29), .init(3,-4,34), .init(5,-2,39), .init(10,-3,38)],
                "liv-8": [.init(0,10,22), .init(3,12,27), .init(5,12,31), .init(10,10,30)],
                "liv-7": [.init(0,20,28), .init(1.4,22,32), .init(3,24,40), .init(5,23,43), .init(10,20,41)],
                "liv-11": [.init(0,-21,20), .init(3,-19,23), .init(5,-17,26), .init(10,-18,25)],
                "liv-22": [.init(0,-1,13), .init(4,1,17), .init(10,0,16)]
             ])
    }

    private static var underlapCutback: ReplayScenario {
        make(id: ids[1], title: "Underlap and cutback", minute: "57′", duration: 10,
             beats: cutbackBeats, perspective: "city-33",
             objective: "Run inside the winger. Find the striker behind the retreating line.",
             cues: [(0, "Release inside", "The wide player holds the full-back as O’Reilly runs inside."),
                    (3, "Pull it back", "O’Reilly cuts the ball back into the space behind the recovering defenders."),
                    (4, "Check, then finish", "Haaland checks away from Van Dijk and meets the cutback first time with his left foot.")],
             paths: [
                "city-1": [.init(0,-1,-42), .init(5,-1,-40), .init(10,0,-40)],
                "city-27": [.init(0,23,20), .init(3,20,24), .init(5,18,25), .init(10,18,24)],
                "city-45": [.init(0,10,4), .init(4,7,8), .init(10,7,9)],
                "city-15": [.init(0,-9,6), .init(4,-11,10), .init(10,-11,11)],
                "city-33": [.init(0,-19,30), .init(1.5,-16,38.5), .init(2.2,-14,42), .init(3,-12.2,45.5), .init(4.5,-10,48), .init(6,-8,48), .init(10,-7,47)],
                "city-16": [.init(0,-4,18), .init(3,-5,23), .init(5,-4,25), .init(10,-3,25)],
                "city-20": [.init(0,-9,27), .init(3,-7,31), .init(5,-6,35), .init(10,-5,35)],
                "city-10": [.init(0,6,31), .init(3,5,35), .init(4.7,6,39), .init(7,7,42), .init(10,7,41)],
                "city-42": [.init(0,20,33), .init(3,15,39), .init(4.7,10,44), .init(6,8,47), .init(10,8,46)],
                "city-11": [.init(0,-22,31.5), .init(1.5,-23,33), .init(3,-22,37), .init(5,-19,40), .init(10,-18,39)],
                "city-9": [.init(0,0,36), .init(1.5,0,40), .init(2.6,0,42), .init(3.4,-1,41.2), .init(4,-1,41), .init(5.5,0,45), .init(10,1,47)],
                "liv-25": [.init(0,-1,50), .init(3,-3.3,49), .init(4,-3.3,49), .init(5.5,-1,50), .init(10,0,50)],
                "liv-2": [.init(0,-19,34), .init(1.5,-19,37), .init(3,-15,44), .init(4.5,-12,47), .init(10,-10,45)],
                "liv-5": [.init(0,-8,36), .init(1.5,-9,39), .init(3,-8,44), .init(4,-7,46), .init(6,-5,49), .init(10,-5,47)],
                "liv-4": [.init(0,2,38), .init(1.5,2,41), .init(3,1,44), .init(4,1,44.5), .init(6,2,48), .init(10,2,46)],
                "liv-6": [.init(0,17,34), .init(3,13,39), .init(4.7,10,44), .init(6,9,46), .init(10,9,44)],
                "liv-38": [.init(0,-2,30), .init(1.5,-3,33), .init(3,-3,36), .init(4,-2.5,38), .init(6,-1,42), .init(10,-1,41)],
                "liv-17": [.init(0,-13,27), .init(1.5,-15,31), .init(3,-16,36), .init(5,-13,40), .init(10,-12,39)],
                "liv-8": [.init(0,2,22), .init(3,0,27), .init(5,0,31), .init(10,1,30)],
                "liv-7": [.init(0,18,23), .init(3,16,26), .init(5,14,29), .init(10,15,28)],
                "liv-11": [.init(0,-22,23), .init(1.5,-23,26), .init(3,-23,30), .init(5,-21,33), .init(10,-21,32)],
                "liv-22": [.init(0,-2,13), .init(4,-4,17), .init(10,-3,16)]
             ])
    }

    private struct RosterEntry {
        let number: Int
        let name: String
        let role: String
    }

    private static let city: [RosterEntry] = [
        .init(number: 1, name: "Trafford", role: "Goalkeeper"),
        .init(number: 27, name: "Nunes", role: "Right back"),
        .init(number: 45, name: "Khusanov", role: "Right centre-back"),
        .init(number: 15, name: "Guéhi", role: "Left centre-back"),
        .init(number: 33, name: "O’Reilly", role: "Left back"),
        .init(number: 16, name: "Rodri", role: "Holding midfield"),
        .init(number: 20, name: "Bernardo Silva", role: "Central midfielder"),
        .init(number: 42, name: "Semenyo", role: "Right winger"),
        .init(number: 10, name: "Cherki", role: "Attacking midfielder"),
        .init(number: 11, name: "Doku", role: "Left winger"),
        .init(number: 9, name: "Haaland", role: "Striker")
    ]

    private static let liverpool: [RosterEntry] = [
        .init(number: 25, name: "Mamardashvili", role: "Goalkeeper"),
        .init(number: 2, name: "Gomez", role: "Right back"),
        .init(number: 5, name: "Konaté", role: "Right centre-back"),
        .init(number: 4, name: "Van Dijk", role: "Left centre-back"),
        .init(number: 6, name: "Kerkez", role: "Left back"),
        .init(number: 38, name: "Gravenberch", role: "Holding midfield"),
        .init(number: 17, name: "Jones", role: "Central midfielder"),
        .init(number: 8, name: "Szoboszlai", role: "Attacking midfielder"),
        .init(number: 7, name: "Wirtz", role: "Left winger"),
        .init(number: 11, name: "Salah", role: "Right winger"),
        .init(number: 22, name: "Ekitiké", role: "Striker")
    ]

    private static func make(id: String, title: String, minute: String, duration: Double,
                             beats: [Beat], perspective: String, objective: String,
                             cues: [(Double, String, String)], paths: [String: [Waypoint]]) -> ReplayScenario {
        let ball = BallTrack(keyframes: beats.map {
            .init(time: $0.time, position: $0.point, height: $0.height)
        } + [.init(time: duration, position: beats.last!.point, height: 0.11)])
        let players = roster(duration: duration, ball: ball, beats: beats, paths: paths)
        let featured = beats.map(\.playerID).filter { !$0.isEmpty }.reduce(into: [String]()) {
            if !$0.contains($1) { $0.append($1) }
        }
        return ReplayScenario(id: id, kind: .realWorldReplay, title: title,
            strapline: "FA Cup · \(minute) · Reconstruction",
            matchContext: "Man City v Liverpool · 4 Apr 2026 · \(minute)",
            objective: objective, coachPrompt: objective,
            proofPoint: "Broadcast-inspired, manually authored positions. Not recovered tracking. Off-camera movement and body poses are inferred. Neutral demo kits.",
            duration: duration, defaultViewMode: .tacticalTable, defaultPerspectiveID: perspective,
            featuredPerspectiveIDs: featured, players: players, ball: ball,
            moments: cues.enumerated().map { index, cue in
                .init(id: "\(id)-cue-\(index)", time: cue.0, kicker: minute,
                      headline: cue.1, explanation: cue.2)
            }, coachMarks: [], formationTargets: [])
    }

    private static func roster(duration: Double, ball: BallTrack, beats: [Beat],
                               paths: [String: [Waypoint]]) -> [PlayerTrack] {
        FootballTeam.allCases.flatMap { team in
            let entries = team == .home ? city : liverpool
            let prefix = team == .home ? "city" : "liv"
            return entries.map { entry in
                let playerID = "\(prefix)-\(entry.number)"
                // Every player has a deliberately authored route; there is no
                // generic fallback that pulls the entire side towards goal.
                let route = paths[playerID]!
                let skeleton = PlayerTrack(id: playerID, displayName: entry.name, role: entry.role,
                    shirtNumber: entry.number, team: team, isGoalkeeper: entry.role == "Goalkeeper",
                    keyframes: route.map { .init(time: $0.time, position: $0.point, facingDegrees: 0) })
                var heading: Float = team == .home ? 0 : 180
                var frames = (0...Int(ceil(duration * 10))).map { sample -> MotionKeyframe in
                    let time = min(duration, Double(sample) * 0.1)
                    let position = skeleton.presentationPose(at: time).position
                    let before = skeleton.presentationPose(at: max(0, time - 0.12)).position
                    let after = skeleton.presentationPose(at: min(duration, time + 0.12)).position
                    let travel = SIMD2(after.x - before.x, after.z - before.z)
                    let ballPoint = ball.pose(at: time).position
                    let toBall = SIMD2(ballPoint.x - position.x, ballPoint.z - position.z)
                    let speed = simd_length(travel) / 0.24
                    var desired = speed > 3.2 ? travel : toBall
                    // A carry touch must not hold the torso facing upfield
                    // through the following cross/cutback preparation.
                    if let index = beats.indices.last(where: {
                        beats[$0].playerID == playerID && abs(beats[$0].time - time) < 0.6 && $0 + 1 < beats.count
                    }) {
                        // Meet the incoming cross before glancing it across
                        // goal; facing the finish early leaves the ball behind
                        // the head. The existing turn-rate cap governs follow-through.
                        let target = beats[index].kind == .header && index > 0 && time <= beats[index].time
                            ? beats[index - 1].point : beats[index + 1].point
                        desired = SIMD2(target.x - position.x, target.z - position.z)
                    }
                    if simd_length_squared(desired) > 0.0001 {
                        let target = atan2(desired.x, desired.y) * 180 / Float.pi
                        let delta = (target - heading + 540).truncatingRemainder(dividingBy: 360) - 180
                        heading += sample == 0 ? delta : min(max(delta, -14), 14)
                    }
                    return .init(time: time, position: position, facingDegrees: heading)
                }
                if !skeleton.isGoalkeeper, !beats.contains(where: { $0.playerID == playerID }) {
                    frames = ReplayInferredRunningHeading.applying(to: frames, route: skeleton, ball: ball)
                }
                return PlayerTrack(id: playerID, displayName: entry.name, role: entry.role,
                    shirtNumber: entry.number, team: team, isGoalkeeper: entry.role == "Goalkeeper",
                    keyframes: frames)
            }
        }
    }
}
