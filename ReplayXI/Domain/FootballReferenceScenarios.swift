import Foundation
import simd

/// Authored teaching reconstructions, not recovered tracking or match footage.
/// The broadcast supplies the action sequence; coordinates, supporting runs,
/// timing and neutral kits are deliberately approximate.
enum FootballReferenceScenarios {
    static let sourceURL = URL(string: "https://www.youtube.com/watch?v=RgqKdplLIk4")!
    static let ids = ["final-36-counter", "final-81-volley", "final-108-rebound"]
    static let all: [ReplayScenario] = [counter, volley, rebound]

    static func contains(_ scenario: ReplayScenario) -> Bool { ids.contains(scenario.id) }

    struct Beat {
        let time: Double
        let playerID: String
        let point: PitchPoint
        let height: Float
        let kind: ReplayNativeBallPhysics.TouchKind
        let leg: ReplayAthleteLeg
        init(_ time: Double, _ player: String, _ x: Float, _ z: Float,
             height: Float = 0.11, kind: ReplayNativeBallPhysics.TouchKind = .pass,
             leg: ReplayAthleteLeg = .right) {
            self.time = time; playerID = player; point = .init(x: x, z: z)
            self.height = height; self.kind = kind; self.leg = leg
        }
    }

    private static let counterBeats = [
        Beat(0, "arg-26", 14, -2), Beat(1.2, "arg-10", 9, 3, leg: .left),
        Beat(2.5, "arg-9", 14, 10), Beat(4.6, "arg-20", 7, 28),
        Beat(6.8, "arg-11", -14, 38, kind: .shot, leg: .left),
        Beat(7.9, "", -1.5, 54)
    ]
    private static let volleyBeats = [
        Beat(0, "fra-20", -8, 5), Beat(1.1, "fra-14", -12, 13),
        Beat(2.6, "fra-10", -16, 28, height: 1.63, kind: .header), Beat(3.55, "fra-26", -7, 32),
        Beat(4.5, "fra-10", -12, 37, height: 0.50, kind: .shot),
        Beat(5.4, "", 1.6, 54, height: 0.30)
    ]
    private static let reboundBeats = [
        Beat(0, "arg-24", 3, 25), Beat(0.9, "arg-10", 6, 30, leg: .left),
        Beat(1.8, "arg-24", 3, 33),
        Beat(2.8, "arg-22", 11, 40, kind: .shot),
        Beat(3.55, "fra-1", 1, 48, height: 0.65, kind: .save),
        Beat(4.2, "arg-10", -1, 47, kind: .shot, leg: .left),
        Beat(4.55, "", -1.8, 54)
    ]

    static func touches(for scenario: ReplayScenario) -> [ReplayNativeBallPhysics.PlannedTouch]? {
        let beats: [Beat]
        switch scenario.id {
        case ids[0]: beats = counterBeats
        case ids[1]: beats = volleyBeats
        case ids[2]: beats = reboundBeats
        default: return nil
        }
        return zip(beats, beats.dropFirst()).map { current, next in
            .init(time: current.time, playerID: current.playerID, kind: current.kind,
                  kickingLeg: current.leg, target: next.point, targetHeight: next.height,
                  arrivalTime: next.time)
        }
    }

    static func teamTitle(_ team: FootballTeam, in scenario: ReplayScenario) -> String {
        contains(scenario) ? (team == .home ? "Argentina" : "France") : team.shortTitle
    }

    private struct Waypoint {
        let time: Double
        let point: PitchPoint
        init(_ time: Double, _ x: Float, _ z: Float) {
            self.time = time; point = .init(x: x, z: z)
        }
    }

    private static var counter: ReplayScenario {
        make(id: ids[0], title: "The counterattack", minute: "36′", duration: 10.5,
             beats: counterBeats, attacking: .home, perspective: "arg-11",
             objective: "Release early. Keep the far-side runner wide.",
             cues: [(0, "Release", "Break pressure with the first pass."),
                    (2.5, "Third-man run", "Mac Allister runs beyond the ball; Di María keeps the width."),
                    (6.8, "First-time finish", "Arrive ready to strike, without an extra touch.")],
             paths: [
                "arg-26": [.init(0,14,-2.5),.init(2.5,16,5),.init(6.8,20,16),.init(10.5,20,20)],
                "arg-10": [.init(0,9,-1),.init(1.2,9,2.5),.init(4.6,8,18),.init(10.5,7,32)],
                "arg-9": [.init(0,14,5),.init(2.5,14,9.5),.init(4.6,15,21),.init(6.8,10,34),.init(10.5,5,44)],
                "arg-20": [.init(0,7,4),.init(2.5,7,14),.init(4.6,7,27.5),.init(6.8,4,39),.init(10.5,2,45)],
                "arg-7": [.init(0,18,-4),.init(2.5,19,3),.init(4.6,18,17),.init(6.8,16,27),.init(10.5,9,40)],
                "arg-11": [.init(0,-23,9),.init(2.5,-22,19),.init(4.6,-19,29),.init(6.8,-14,37.5),.init(10.5,-9,46)],
                "fra-14": [.init(0,18,7),.init(2.5,17,11),.init(4.6,14,20),.init(6.8,10,30),.init(10.5,6,41)],
                "fra-1": [.init(0,0,50),.init(4.6,-1,49),.init(6.8,-4,46),.init(10.5,-3,48)]
             ])
    }

    private static var volley: ReplayScenario {
        make(id: ids[1], title: "The one-two volley", minute: "81′", duration: 8.5,
             beats: volleyBeats, attacking: .away, perspective: "fra-10",
             objective: "Pass, turn and attack the return before the defence sets.",
             cues: [(0, "Win it back", "React to the turnover as a unit."),
                    (2.6, "Give and go", "Mbappé releases to Thuram, then attacks the return."),
                    (4.5, "Meet the return", "Open the body and strike the dropping ball first time.")],
             paths: [
                "fra-20": [.init(0,-8,4.5),.init(2.6,-5,15),.init(5.4,0,26),.init(8.5,2,31)],
                "fra-14": [.init(0,-12,9),.init(1.1,-12,12.5),.init(4.5,-7,25),.init(8.5,-2,32)],
                "fra-10": [.init(0,-21,16),.init(2.6,-15.96,27.7),.init(3.55,-15,31),.init(4.5,-12,36.5),.init(8.5,-5,44)],
                "fra-26": [.init(0,-6,24),.init(2.6,-7,29),.init(3.55,-7,31.5),.init(5.4,-4,38),.init(8.5,2,44)],
                "arg-23": [.init(0,0,50.5),.init(2.6,-2,50),.init(4.5,-4.5,49.5),.init(8.5,-2,50)]
             ])
    }

    private static var rebound: ReplayScenario {
        make(id: ids[2], title: "Follow the rebound", minute: "108′", duration: 7,
             beats: reboundBeats, attacking: .home, perspective: "arg-10",
             objective: "Keep running after the pass. React to the second ball.",
             cues: [(0, "Combine", "A short exchange opens the inside-right channel."),
                    (2.8, "Attack the box", "The first shot is not the end of the move."),
                    (4.2, "Second ball", "Messi follows the shot; the defenders must recover towards goal.")],
             paths: [
                "arg-10": [.init(0,6,24.5),.init(0.9,6,29.5),.init(1.8,6,36),.init(2.8,1,40),.init(4.2,-1,46.5),.init(7,-2,49.5)],
                "arg-24": [.init(0,3,24.5),.init(1.8,3,32.5),.init(2.8,2,35),.init(7,0,40)],
                "arg-22": [.init(0,14,29),.init(1.8,12,34),.init(2.8,11,39.5),.init(4.2,6,46),.init(7,3,49)],
                "fra-4": [.init(0,5,35),.init(2.8,4,40),.init(4.2,3,44),.init(7,1,49)],
                "fra-1": [.init(0,0,50),.init(2.8,1,48.5),.init(3.55,1.3,47.9),.init(7,0,49)]
             ])
    }

    private static func make(id: String, title: String, minute: String, duration: Double,
                             beats: [Beat], attacking: FootballTeam, perspective: String,
                             objective: String, cues: [(Double,String,String)],
                             paths: [String:[Waypoint]]) -> ReplayScenario {
        let ball = BallTrack(keyframes: beats.map {
            BallKeyframe(time: $0.time, position: $0.point, height: $0.height)
        } + [BallKeyframe(time: duration, position: beats.last!.point, height: 0.11)])
        let roster = players(duration: duration, beats: beats, ball: ball,
                             attacking: attacking, paths: paths, id: id)
        let featured = Array(beats.map(\.playerID).filter { !$0.isEmpty }.reduce(into: [String]()) {
            if !$0.contains($1) { $0.append($1) }
        })
        return ReplayScenario(id: id, kind: .squadReplay, title: title,
            strapline: "World Cup final · \(minute) · Reconstruction",
            matchContext: "Argentina v France · 2022 final · \(minute)",
            objective: objective, coachPrompt: objective,
            proofPoint: "Broadcast-inspired, manually authored positions. Not recovered tracking. Neutral demo kits.",
            duration: duration, defaultViewMode: .tacticalTable, defaultPerspectiveID: perspective,
            featuredPerspectiveIDs: featured, players: roster, ball: ball,
            moments: cues.enumerated().map { index, item in
                .init(id: "\(id)-cue-\(index)", time: item.0, kicker: minute,
                      headline: item.1, explanation: item.2)
            }, coachMarks: [], formationTargets: [])
    }

    private static func players(duration: Double, beats: [Beat], ball: BallTrack,
                                attacking: FootballTeam, paths: [String:[Waypoint]], id: String) -> [PlayerTrack] {
        let homeNumbers = id == ids[2] ? [23,4,13,19,3,24,5,20,10,22,8]
            : id == ids[1] ? [23,26,13,19,3,24,7,20,10,9,8] : [23,26,13,19,3,24,7,20,10,9,11]
        let awayNumbers = id == ids[0] ? [1,5,4,18,22,8,14,7,11,9,10]
            : id == ids[2] ? [1,5,4,18,25,8,13,20,12,26,10]
            : [1,5,4,18,25,8,14,20,12,26,10]
        let names: [String:String] = ["arg-23":"E. Martínez", "arg-26":"Molina", "arg-10":"Messi",
            "arg-9":"Álvarez", "arg-20":"Mac Allister", "arg-11":"Di María", "arg-24":"Enzo Fernández",
            "arg-22":"Lautaro Martínez", "fra-1":"Lloris", "fra-10":"Mbappé", "fra-26":"Thuram",
            "fra-20":"Coman", "fra-14":"Rabiot"]
        let roles = ["Goalkeeper","Right back","Right centre-back","Left centre-back","Left back",
                     "Holding midfield","Right support","Left support","Right attack","Centre-forward","Left attack"]
        let base: [PitchPoint] = [.init(x:0,z:-48),.init(x:25,z:-8),.init(x:9,z:-18),.init(x:-9,z:-18),
            .init(x:-25,z:-8),.init(x:0,z:0),.init(x:13,z:9),.init(x:-13,z:9),
            .init(x:25,z:20),.init(x:0,z:27),.init(x:-25,z:20)]
        return FootballTeam.allCases.flatMap { team in
            let numbers = team == .home ? homeNumbers : awayNumbers
            let prefix = team == .home ? "arg" : "fra"
            return numbers.enumerated().map { slot, number in
                let playerID = "\(prefix)-\(number)"
                let isAttacking = team == attacking
                let origin = base[slot]
                let start = PitchPoint(x: origin.x,
                    z: isAttacking ? origin.z : (slot == 0 ? 50 : max(8, -origin.z + 15)))
                let end = PitchPoint(x: start.x * 0.88,
                    z: slot == 0 ? start.z - (isAttacking ? -1.2 : 1.2)
                        : min(47, start.z + (isAttacking ? 12 : 10)))
                let waypoints = paths[playerID] ?? [.init(0,start.x,start.z),
                    .init(duration*0.48,(start.x+end.x)*0.5,start.z+(end.z-start.z)*0.55),
                    .init(duration,end.x,end.z)]
                let skeleton = PlayerTrack(id: playerID, displayName: names[playerID] ?? "\(team == .home ? "Argentina" : "France") #\(number)",
                    role: roles[slot], shirtNumber: number, team: team, isGoalkeeper: slot == 0,
                    keyframes: waypoints.map { .init(time:$0.time,position:$0.point,facingDegrees:0) })
                var heading: Float = isAttacking ? 0 : 180
                let frames = (0...Int(ceil(duration*10))).map { sampleIndex -> MotionKeyframe in
                    let time = min(duration, Double(sampleIndex)*0.1)
                    let p = skeleton.presentationPose(at: time).position
                    let before = skeleton.presentationPose(at: max(0,time-0.12)).position
                    let after = skeleton.presentationPose(at: min(duration,time+0.12)).position
                    let travel = SIMD2(after.x-before.x,after.z-before.z)
                    let ballPoint = ball.pose(at: time).position
                    let toBall = SIMD2(ballPoint.x-p.x,ballPoint.z-p.z)
                    let speed = simd_length(travel) / 0.24
                    var desired = speed > 3.2 ? travel : toBall
                    if let beatIndex = beats.indices.first(where: {
                        beats[$0].playerID == playerID && abs(beats[$0].time-time)<0.6 && $0+1<beats.count
                    }) {
                        // A keeper meets the incoming shot; he must not turn
                        // away to face the planned rebound receiver.
                        let target = beats[beatIndex].kind == .save && beatIndex > 0
                            ? beats[beatIndex-1].point : beats[beatIndex+1].point
                        desired = SIMD2(target.x-p.x,target.z-p.z)
                    }
                    if simd_length_squared(desired)>0.0001 {
                        let target = atan2(desired.x,desired.y)*180/Float.pi
                        let delta = (target-heading+540).truncatingRemainder(dividingBy:360)-180
                        heading += sampleIndex == 0 ? delta : min(max(delta,-14),14)
                    }
                    return .init(time:time,position:p,facingDegrees:heading)
                }
                return PlayerTrack(id: skeleton.id, displayName:skeleton.displayName, role:skeleton.role,
                    shirtNumber:number,team:team,isGoalkeeper:slot==0,keyframes:frames)
            }
        }
    }
}
