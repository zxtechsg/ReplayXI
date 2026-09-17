import Foundation

/// Pitch-line estimates from the official FIFA broadcast, not tracking data.
/// The original short/half-pitch sequence remains under its old ID for saves.
enum WorldCupCounterReference {
    private typealias Beat = FootballReferenceScenarios.Beat
    private static let beats: [Beat] = [
        .init(0, "arg-26", 31, -18),
        .init(3, "arg-20", 8, -17),
        .init(4.8, "arg-10", 15, -7, leg: .left),
        .init(6.6, "arg-9", 25, 2),
        .init(9.5, "arg-20", 13, 34),
        .init(11.5, "arg-11", -10, 46, kind: .shot, leg: .left),
        .init(12.3, "", 1.5, 54, height: 0.35)
    ]

    static var touches: [ReplayNativeBallPhysics.PlannedTouch] {
        zip(beats, beats.dropFirst()).map { current, next in
            .init(time: current.time, playerID: current.playerID, kind: current.kind,
                  kickingLeg: current.leg, target: next.point, targetHeight: next.height,
                  arrivalTime: next.time)
        }
    }

    static var scenario: ReplayScenario {
        FootballReferenceScenarios.make(id: "final-36-counter-v2", title: "The counterattack",
            minute: "36′", duration: 13.5, beats: beats, attacking: .home, perspective: "arg-11",
            objective: "Escape pressure. Release the third-man runner and finish across goal.",
            cues: [(0, "Escape the touchline", "Molina finds Mac Allister inside before the layoff to Messi."),
                   (6.6, "Release the runner", "Álvarez finds Mac Allister running through the right channel."),
                   (9.5, "Use the far-side width", "Di María cuts inside to meet the square pass first time.")],
            paths: [
                "arg-26": [.init(0,31,-18.5),.init(4.8,30,-10),.init(9.5,26,13),.init(13.5,23,23)],
                "arg-20": [.init(0,8,-23),.init(3,8,-17.5),.init(4.8,8,-8),.init(6.6,10,7),.init(9.5,13,33.5),.init(11.5,10,42),.init(13.5,6,47)],
                "arg-10": [.init(0,15,-18),.init(4.8,15,-7.5),.init(6.6,14,0),.init(9.5,11,20),.init(13.5,8,34)],
                "arg-9": [.init(0,25,-13),.init(4.8,25,-5),.init(6.6,25,1.5),.init(9.5,15,25),.init(11.5,10,35),.init(13.5,6,44)],
                "arg-11": [.init(0,-27,-12),.init(4.8,-26.8,-4),.init(6,-26,2),.init(8.2,-22,22),.init(9.5,-17,33),.init(11.5,-10,45.5),.init(13.5,-5,48)],
                // Supporting routes remain explicit estimates, not invisible
                // telemetry. Rest defence advances less than the attacking unit.
                "arg-23": [.init(0,0,-47),.init(9.5,0,-43),.init(13.5,0,-42)],
                "arg-13": [.init(0,12,-30),.init(9.5,11,-9),.init(13.5,10,0)],
                "arg-19": [.init(0,-5,-31),.init(9.5,-5,-12),.init(13.5,-4,-2)],
                "arg-3": [.init(0,-24,-25),.init(9.5,-22,-3),.init(13.5,-20,10)],
                "arg-24": [.init(0,-2,-19),.init(9.5,-1,7),.init(13.5,0,20)],
                "arg-7": [.init(0,21,-24),.init(3,20,-22),.init(6.6,20,-2),.init(9.5,20,19),.init(13.5,15,33)],
                "fra-1": [.init(0,0,50),.init(9.5,-1,50),.init(11.5,-5,48),.init(13.5,-4,49)],
                "fra-5": [.init(0,-17,-3),.init(6.6,-13,12),.init(9.5,-8,35),.init(11.5,3,46),.init(13.5,2,49)],
                "fra-4": [.init(0,5,1),.init(6.6,7,16),.init(9.5,6,33),.init(11.5,6,40),.init(13.5,2,47)],
                "fra-18": [.init(0,-5,0),.init(6.6,-3,15),.init(9.5,1,34),.init(11.5,3,44),.init(13.5,0,48)],
                "fra-22": [.init(0,25,-4),.init(6.6,24,7),.init(9.5,18,26),.init(11.5,15,32),.init(13.5,10,43)],
                "fra-8": [.init(0,-1,-8),.init(6.6,-2,12),.init(9.5,-3,33),.init(11.5,-3,44),.init(13.5,-1,49)],
                "fra-14": [.init(0,17,-12),.init(6.6,19,4),.init(9.5,17,26),.init(13.5,12,41)],
                "fra-7": [.init(0,6,-18),.init(6.6,3,-3),.init(9.5,2,18),.init(13.5,3,32)],
                "fra-11": [.init(0,-24,-12),.init(6.6,-22,0),.init(9.5,-18,18),.init(13.5,-15,29)],
                "fra-9": [.init(0,0,-26),.init(6.6,1,-11),.init(9.5,2,6),.init(13.5,1,20)],
                "fra-10": [.init(0,25,-22),.init(6.6,25,-10),.init(9.5,21,6),.init(13.5,18,17)]
            ])
    }
}
