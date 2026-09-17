import Foundation

/// Source windows describe the broadcast, not a frame-perfect timeline mapping.
/// Legacy synthetic saves deliberately have no video reference.
enum ReplayReferenceLibrary {
    private static let reconstructionNote = "Manually reconstructed from the broadcast. Off-camera movement, body poses and gaze are inferred, not measured tracking. Neutral demo kits."

    static func reference(for scenarioID: String) -> ReplayVideoReference? {
        switch scenarioID {
        case "final-36-counter-v2":
            worldCup("ARG–FRA · 36′", start: 2_205, end: 2_220)
        case "final-36-counter":
            worldCup("ARG–FRA · 36′ · Legacy", start: 2_205, end: 2_220)
        case "final-81-volley-v2", "final-81-volley":
            worldCup("ARG–FRA · 81′", start: 5_439, end: 5_460)
        case "final-108-rebound-v2":
            worldCup("ARG–FRA · 108′", start: 7_779, end: 7_800,
                     angles: [.init(title: "Close replay · finish", startSeconds: 7_852)])
        case "final-108-rebound":
            worldCup("ARG–FRA · 108′ · Legacy", start: 7_779, end: 7_800,
                     angles: [.init(title: "Close replay · finish", startSeconds: 7_852)])
        case "city-45-overlap-header":
            cityLiverpool("MCI–LIV · 45+2′", start: 2_786, end: 2_808,
                          angles: [.init(title: "Wide end-line replay", startSeconds: 2_841),
                                   .init(title: "Close reverse replay", startSeconds: 2_853)])
        case "city-57-underlap-cutback":
            cityLiverpool("MCI–LIV · 57′", start: 3_574, end: 3_591,
                          angles: [.init(title: "Build-up replay", startSeconds: 3_624),
                                   .init(title: "Reverse end-line replay", startSeconds: 3_639)])
        default:
            nil
        }
    }

    private static func worldCup(_ label: String, start: Int, end: Int,
                                 angles: [ReplayVideoReferenceAngle] = []) -> ReplayVideoReference {
        .init(matchTitle: "Argentina v France · World Cup final · 18 Dec 2022",
              shortLabel: label, videoID: "RgqKdplLIk4", startSeconds: start, endSeconds: end,
              reconstructionNote: reconstructionNote, alternateAngles: angles)
    }

    private static func cityLiverpool(_ label: String, start: Int, end: Int,
                                      angles: [ReplayVideoReferenceAngle]) -> ReplayVideoReference {
        .init(matchTitle: "Manchester City v Liverpool · FA Cup QF · 4 Apr 2026",
              shortLabel: label, videoID: "05ny1bmo-Kk", startSeconds: start, endSeconds: end,
              reconstructionNote: reconstructionNote, alternateAngles: angles)
    }
}
