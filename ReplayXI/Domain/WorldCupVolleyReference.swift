import Foundation

/// Revised authored study, informed by FIFA Training Centre's Example 3:
/// https://www.fifatrainingcentre.com/en/game/individual-qualities/world-class-skills/mbappe-predator-in-the-box.php#example_3
/// The release-to-volley interval is roughly 7–8 s in the reference, not 4.5 s.
/// These rounded beats and metre-scale routes are estimates, not calibrated
/// frames or imported tracking. All unseen supporting/defending actions below
/// are tactical inferences. The original study remains frozen for saved marks.
enum WorldCupVolleyReference {
    private typealias Beat = FootballReferenceScenarios.Beat
    private static let beats: [Beat] = [
        .init(0, "fra-20", -8, 5),
        .init(2.6, "fra-14", -12, 13),
        .init(4.6, "fra-10", -16, 28, height: 1.63, kind: .header),
        .init(5.6, "fra-26", -7, 32),
        // Legacy kick IDs name X lanes. Negative-X (`.left`) drives the
        // source's anatomical R_Foot for the reference's right-foot volley.
        .init(7.4, "fra-10", -12, 37, height: 0.50, kind: .shot, leg: .left),
        .init(8.2, "", 1.6, 54, height: 0.30)
    ]

    static var touches: [ReplayNativeBallPhysics.PlannedTouch] {
        zip(beats, beats.dropFirst()).map { current, next in
            .init(time: current.time, playerID: current.playerID, kind: current.kind,
                  kickingLeg: current.leg, target: next.point, targetHeight: next.height,
                  arrivalTime: next.time, headerSupportLeg: current.kind == .header ? .right : nil)
        }
    }

    static var scenario: ReplayScenario {
        FootballReferenceScenarios.make(id: "final-81-volley-v2", title: "The one-two volley",
            minute: "81′", duration: 10.5, beats: beats, attacking: .away, perspective: "fra-10",
            objective: "Cushion the header, turn inside and meet the return on the volley.",
            cues: [(0, "React to the turnover", "Coman releases inside; Rabiot finds Mbappé before the defence resets."),
                   (4.6, "Set, then turn", "Cushion the header with the right foot planted, then accelerate inside the marker."),
                   (7.4, "Settle into the volley", "Shorten the final steps, open the trunk and meet the dropping return with the right foot.")],
            paths: [
                // The four visible actors retain the established contact
                // locations. Extra approach/exit knots give the one-two room
                // to turn, accelerate and brake rather than rush every beat.
                "fra-20": [.init(0,-8,4.5),.init(2.6,-5,11),.init(4.6,-2,18),.init(7.4,1,28),.init(10.5,3,34)],
                "fra-14": [.init(0,-12,9),.init(2.6,-12,12.5),.init(4.6,-11,18.5),.init(7.4,-8,27),.init(10.5,-5,31)],
                "fra-10": [.init(0,-21,16),.init(2.6,-19,22),.init(4.6,-15.96,27.7),
                           .init(5.2,-16,29.5),.init(5.6,-15,31),.init(6.6,-12.9,35),
                           .init(7,-12.5,36),.init(7.4,-12,36.5),.init(8.2,-10.6,38.3),.init(10.5,-6,44)],
                "fra-26": [.init(0,-6,24),.init(2.6,-7,27),.init(4.6,-7,29),.init(5.6,-7,31.5),.init(7.4,-5,36.5),.init(10.5,0,42)],

                // Inferred far-side run: occupy the second centre-back and
                // arrive for a spill, instead of all attackers chasing the ball.
                "fra-12": [.init(0,16,22),.init(2.6,13,26),.init(4.6,11,30.5),.init(5.6,10,33),.init(7.4,5,41),.init(8.2,3.5,44),.init(10.5,3,45)],
                "fra-25": [.init(0,-27,1),.init(2.6,-24,8),.init(4.6,-22,15),.init(7.4,-19,22),.init(10.5,-18,27)],
                "fra-5": [.init(0,25,0),.init(2.6,24,5),.init(4.6,22,10),.init(7.4,20,17),.init(10.5,18,20)],
                "fra-8": [.init(0,3,5),.init(2.6,1,10),.init(4.6,-1,14),.init(7.4,-1,20),.init(10.5,0,23)],
                // Inferred rest defence squeezes up more slowly and retains
                // two staggered cover lanes rather than following into the box.
                "fra-4": [.init(0,9,-14),.init(2.6,7,-10),.init(4.6,5,-5),.init(7.4,5,1),.init(10.5,5,5)],
                "fra-18": [.init(0,-9,-14),.init(2.6,-10,-8),.init(4.6,-11,-3),.init(7.4,-9,2),.init(10.5,-8,6)],
                "fra-1": [.init(0,0,-46),.init(4.6,-0.8,-44.5),.init(7.4,-1,-42.5),.init(10.5,-1,-41)],

                // Inferred recovery: the outside marker must turn after the
                // set, the centre-backs protect different lanes, and the far
                // full-back tracks the arriving runner. This is not a claim
                // that these unseen individual paths were measured in video.
                "arg-26": [.init(0,-21,24),.init(2.6,-20,27.5),.init(4.6,-18.7,30.2),.init(5.6,-18.2,32.6),.init(7.4,-13.5,38.4),.init(8.2,-10,42),.init(10.5,-8,45)],
                "arg-13": [.init(0,-6,28.5),.init(2.6,-7.5,31),.init(4.6,-9,34),.init(5.6,-10,36.5),.init(7.4,-5,41),.init(8.2,-3.8,44),.init(10.5,-3.5,46)],
                "arg-19": [.init(0,4,30),.init(2.6,3,32),.init(4.6,2,34.5),.init(5.6,0.8,36),.init(7.4,-1,41),.init(8.2,0,44),.init(10.5,0.5,47)],
                "arg-3": [.init(0,20,25),.init(2.6,18,29),.init(4.6,15,32),.init(5.6,13,35),.init(7.4,9,41),.init(8.2,7,44),.init(10.5,6,45)],
                "arg-24": [.init(0,-1,16),.init(2.6,-3,20),.init(4.6,-4,26),.init(5.6,-3,29),.init(7.4,-5,35),.init(8.2,-4,38),.init(10.5,-2,42)],
                "arg-7": [.init(0,-17,9),.init(2.6,-16,13),.init(4.6,-15,19),.init(5.6,-14,23),.init(7.4,-13,29),.init(8.2,-10,34),.init(10.5,-8,39)],
                "arg-20": [.init(0,8,9),.init(2.6,7,14),.init(4.6,5,20),.init(5.6,5,23.5),.init(7.4,4,30),.init(8.2,4,33),.init(10.5,3,38)],
                "arg-8": [.init(0,-28,10),.init(2.6,-26,15),.init(4.6,-25,21),.init(5.6,-24,24),.init(7.4,-22,30),.init(8.2,-20,34),.init(10.5,-18,38)],
                // The dispossessed player checks and trails; the other forward
                // stays available for an outlet. Neither runs like a centre-back.
                "arg-10": [.init(0,-4.6,4.5),.init(1.2,-5,7),.init(2.6,-5.5,9),.init(4.6,-5.5,12),.init(7.4,-5,16),.init(10.5,-3.5,21)],
                "arg-9": [.init(0,5,-1),.init(2.6,4,3),.init(4.6,3,6),.init(7.4,3,10),.init(10.5,4,13)],
                "arg-23": [.init(0,0,50.5),.init(4.6,-2,50),.init(7.4,-4.5,49.5),.init(8.2,-3.5,49.7),.init(10.5,-2,50)]
            ],
            facingPaths: [
                // An authored demonstration of the reference's wrong-facing
                // marker: open to the loft, then turn into the recovery run.
                // The exact angle and player-to-marker pairing are inferred.
                "arg-26": [.init(0,155),.init(2.6,170),.init(4.6,158),.init(5.1,150),
                           .init(5.6,105),.init(6.3,40),.init(7.4,23),.init(8.2,30),.init(10.5,48)]
            ])
    }
}
