import Foundation

/// Deterministic, rights-safe demonstration data for Replay XI.
///
/// Every scenario uses the same 32-second match sequence. This lets the UI move
/// between teaching modes without changing the underlying football moment, and
/// keeps shared-session playback deterministic on every participant's device.
enum DemoScenarios {
    static let all: [ReplayScenario] = makeScenarios()

    static func scenario(for kind: ExperienceKind) -> ReplayScenario? {
        all.first { $0.kind == kind }
    }

    private static let sequenceDuration: TimeInterval = 32
    private static let matchContext =
        "Northbridge Athletic v Eastport United • 63:12 • Right-side overlap"

    private static let commonPlayers: [PlayerTrack] = makeCommonPlayers()
    private static let commonBall: BallTrack = makeCommonBall()

    private static func makeScenarios() -> [ReplayScenario] {
        [
            squadReplay,
            coachFocus,
            shapeLab,
            passingChannels,
            perspectiveMatrix,
            realWorldReplay
        ]
    }

    // MARK: - Scenario 01

    private static var squadReplay: ReplayScenario {
        ReplayScenario(
            id: "eleven-eyes",
            kind: .squadReplay,
            title: "Eleven Eyes",
            strapline: "One moment. Eleven honest pictures.",
            matchContext: matchContext,
            objective: "Review the same move from any of the 22 player positions on one local timeline.",
            coachPrompt: "Stay in your own eyes. Notice when the outside lane first becomes available.",
            proofPoint: "Switch roles to see what each player could see, then annotate the same moment.",
            duration: sequenceDuration,
            // Match Playback opens on the stable tactical board so the coach
            // can scrub, select and annotate before deliberately entering a
            // player's moving, free-look lens.
            defaultViewMode: .tacticalTable,
            defaultPerspectiveID: "navy-rw",
            featuredPerspectiveIDs: [
                "navy-gk", "navy-rb", "navy-rcb", "navy-lcb", "navy-lb",
                "navy-dm", "navy-rcm", "navy-lcm", "navy-rw", "navy-cf", "navy-lw"
            ],
            players: commonPlayers,
            ball: commonBall,
            moments: [
                cue("squad-ready", 0, "TEAM PERSPECTIVES", "Eleven roles, one clock", "Every Northbridge role is attached to the same deterministic match timeline."),
                cue("squad-build", 4.2, "BUILD-UP", "The right side opens", "The right centre-back carries forward and fixes the first line of pressure."),
                cue("squad-receive", 9.8, "OWN EYES", "The winger checks short", "Each player sees a different picture as the ball travels into the right winger."),
                cue("squad-window", 13.6, "DECISION", "The overlap breaks the line", "The right-back moves beyond the recovering winger while the full-back is drawn inside."),
                cue("squad-cutback", 18.2, "FINAL THIRD", "The cut-back is on", "The right midfielder arrives behind the holding player instead of crowding the forward line."),
                cue("squad-finish", 24.5, "OUTCOME", "The move reaches the far corner", "Rewind the same sequence while keeping your chosen perspective.")
            ],
            coachMarks: [
                mark("00000000-0000-4000-8000-000000000101", .pass, 12, -10, 25, 1, "Break the first line", 4.2),
                mark("00000000-0000-4000-8000-000000000102", .run, 26, 8, 31, 29, "Outside overlap", 11.0),
                mark("00000000-0000-4000-8000-000000000103", .space, 12, 23, 17, 30, "Late-arrival pocket", 16.0)
            ],
            formationTargets: [
                target("squad-gk", "navy-gk", 0, -47, 2.5, "Rest defence: goalkeeper"),
                target("squad-rb", "navy-rb", 28, 14, 2.0, "Advance outside the winger"),
                target("squad-rcb", "navy-rcb", 13, -7, 2.5, "Protect the right channel"),
                target("squad-lcb", "navy-lcb", -8, -16, 2.5, "Hold central cover"),
                target("squad-lb", "navy-lb", -22, -2, 3.0, "Balance the back line"),
                target("squad-dm", "navy-dm", 1, 2, 2.5, "Screen the counter"),
                target("squad-rcm", "navy-rcm", 13, 18, 2.0, "Stay beneath the ball"),
                target("squad-lcm", "navy-lcm", -8, 11, 3.0, "Hold the switch"),
                target("squad-rw", "navy-rw", 27, 22, 1.8, "Pin the full-back inside"),
                target("squad-cf", "navy-cf", 2, 34, 2.5, "Occupy both centre-backs"),
                target("squad-lw", "navy-lw", -27, 29, 3.0, "Keep far-side width")
            ]
        )
    }

    // MARK: - Scenario 02

    private static var coachFocus: ReplayScenario {
        ReplayScenario(
            id: "everyone-with-seven",
            kind: .coachFocus,
            title: "Everyone With Seven",
            strapline: "Step inside the decision.",
            matchContext: matchContext,
            objective: "Review the right winger's view and mark the timing of the overlap.",
            coachPrompt: "Everybody with seven. Read the full-back's hips, then find the runner outside him.",
            proofPoint: "Select a player and place instructions directly in that player's view.",
            duration: sequenceDuration,
            defaultViewMode: .firstPerson,
            defaultPerspectiveID: "navy-rw",
            featuredPerspectiveIDs: ["navy-rw", "navy-rb", "red-lb"],
            players: commonPlayers,
            ball: commonBall,
            moments: [
                cue("focus-context", 0, "TOUCHLINE", "See the full move first", "The tactical view establishes the press before you change perspective."),
                cue("focus-lock", 9.8, "COACH FOCUS", "Everybody with seven", "Pause on the winger's first touch and inspect the options."),
                cue("focus-hips", 11.6, "READ THE DEFENDER", "The full-back steps inside", "Eastport's left-back turns towards the ball and gives up the space behind his outside shoulder."),
                cue("focus-release", 14.1, "RELEASE", "Play before the lane closes", "The recovering wide player is still behind the overlapping right-back."),
                cue("focus-result", 18.2, "REWARD", "The runner reaches the byline", "The winger's early release creates a cut-back rather than a crowded cross.")
            ],
            coachMarks: [
                mark("00000000-0000-4000-8000-000000000201", .danger, 25, 24, 28, 27, "Full-back drawn inside", 10.8),
                mark("00000000-0000-4000-8000-000000000202", .run, 28, 14, 31, 35, "Right-back beyond", 11.2),
                mark("00000000-0000-4000-8000-000000000203", .pass, 27, 23, 31, 30, "Release outside", 13.6),
                mark("00000000-0000-4000-8000-000000000204", .space, 29, 28, 33, 36, "Attack this channel", 13.8)
            ],
            formationTargets: [
                target("focus-rw", "navy-rw", 27, 23, 1.5, "Receive on the defender's inside shoulder"),
                target("focus-rb", "navy-rb", 31, 29, 1.5, "Arrive outside at release"),
                target("focus-lb", "red-lb", 27, 25, 1.8, "Defender committed to the ball")
            ]
        )
    }

    // MARK: - Scenario 03

    private static var shapeLab: ReplayScenario {
        ReplayScenario(
            id: "triangle-lock",
            kind: .shapeLab,
            title: "Triangle Lock",
            strapline: "Stand still. See the passing shape change.",
            matchContext: matchContext,
            objective: "Set the right-back, right winger, and right midfielder at three distinct heights around the press.",
            coachPrompt: "Seven wider. Eight beneath the cover shadow. Two hold the outside route.",
            proofPoint: "Explore three role stations and relative spacing on one headset without running.",
            duration: sequenceDuration,
            defaultViewMode: .positional,
            defaultPerspectiveID: "navy-rcm",
            featuredPerspectiveIDs: ["navy-rb", "navy-rw", "navy-rcm"],
            players: commonPlayers,
            ball: commonBall,
            moments: [
                cue("shape-anchor", 0, "STATIONARY DRILL", "Anchor the right-side unit", "Three role stations represent the same match coordinates at a safe room scale."),
                cue("shape-flat", 8.0, "SHAPE CHECK", "The unit is almost flat", "From eight, the winger and full-back stack on one passing angle, so the holding defender can screen both."),
                cue("shape-stagger", 15.0, "ADJUST", "Create three heights", "The right-back continues outside while the midfielder stays beneath the ball."),
                cue("shape-green", 16.0, "TRIANGLE LOCK", "Two lanes stay open", "The press can take away one pass, but not both the overlap and the inside return."),
                cue("shape-transfer", 20.0, "TRANSFER", "Carry the picture into play", "The local targets correspond directly to the full-scale replay positions.")
            ],
            coachMarks: [
                mark("00000000-0000-4000-8000-000000000301", .pass, 26, 8, 27, 22, "Back to winger", 7.5),
                mark("00000000-0000-4000-8000-000000000302", .pass, 27, 22, 14, 23, "Inside return", 10.0),
                mark("00000000-0000-4000-8000-000000000303", .run, 26, 8, 31, 29, "Outside height", 10.5),
                mark("00000000-0000-4000-8000-000000000304", .danger, 12, 20, 18, 27, "Cover shadow", 11.0)
            ],
            formationTargets: [
                target("triangle-rb", "navy-rb", 31, 29, 1.5, "Outside and beyond"),
                target("triangle-rw", "navy-rw", 27, 23, 1.5, "Wide receiving point"),
                target("triangle-rcm", "navy-rcm", 14, 18, 1.8, "Inside and beneath")
            ]
        )
    }

    // MARK: - Scenario 04

    private static var passingChannels: ReplayScenario {
        ReplayScenario(
            id: "lane-lens",
            kind: .passingChannels,
            title: "Lane Lens",
            strapline: "Make the open lane impossible to miss.",
            matchContext: matchContext,
            objective: "Compare the blocked inside route, the safe reset, and the time-limited overlap channel.",
            coachPrompt: "Do not chase the green line. Read why it is green, and why it disappears half a second later.",
            proofPoint: "Pitch-locked lane marks turn defender spacing and timing into an immediate first-person picture.",
            duration: sequenceDuration,
            defaultViewMode: .firstPerson,
            defaultPerspectiveID: "navy-rw",
            featuredPerspectiveIDs: ["navy-rw", "navy-rb", "navy-rcm", "red-lb", "red-ldm"],
            players: commonPlayers,
            ball: commonBall,
            moments: [
                cue("lanes-scan", 8.8, "SCAN", "Three routes appear", "The winger can reset, play inside, or release the runner outside."),
                cue("lanes-blocked", 10.8, "INSIDE LANE", "The holding player screens eight", "The direct pass towards the right midfielder crosses the defender's interception radius."),
                cue("lanes-window", 13.2, "OUTSIDE LANE", "A short window opens", "The full-back has started forward before the recovering winger can match the run."),
                cue("lanes-close", 15.5, "TIMING", "The same lane is closing", "Delay lets the left-back turn and reduces the receiver's available space."),
                cue("lanes-cutback", 18.2, "NEXT ACTION", "See the second pass early", "The outside pass matters because it opens the cut-back behind the holding midfield line.")
            ],
            coachMarks: [
                mark("00000000-0000-4000-8000-000000000401", .pass, 27, 22, 14, 23, "Inside: screened", 10.0),
                mark("00000000-0000-4000-8000-000000000402", .danger, 12, 21, 16, 26, "Interception reach", 10.0),
                mark("00000000-0000-4000-8000-000000000403", .pass, 27, 23, 31, 29, "Outside: open", 12.8),
                mark("00000000-0000-4000-8000-000000000404", .run, 28, 14, 31, 35, "Overlap path", 11.0),
                mark("00000000-0000-4000-8000-000000000405", .pass, 30, 35, 15, 29, "Cut-back lane", 17.5)
            ],
            formationTargets: [
                target("lanes-source", "navy-rw", 27, 23, 1.5, "Pass origin"),
                target("lanes-overlap", "navy-rb", 31, 29, 1.5, "Time-limited receiver"),
                target("lanes-cutback", "navy-rcm", 15, 29, 1.8, "Second-action receiver"),
                target("lanes-screen", "red-ldm", 14, 24, 2.0, "Inside screen")
            ]
        )
    }

    // MARK: - Scenario 05

    private static var perspectiveMatrix: ReplayScenario {
        ReplayScenario(
            id: "four-minds",
            kind: .perspectiveMatrix,
            title: "Four Minds",
            strapline: "Same second. Four different decisions.",
            matchContext: matchContext,
            objective: "Compare the right winger, overlapping full-back, supporting midfielder, and defending full-back at one timestamp.",
            coachPrompt: "Hold the clock at 63:25. What is obvious to two, but hidden from seven and their defender?",
            proofPoint: "Fast, time-locked perspective changes build empathy without making the squad reconstruct the play from broadcast footage.",
            duration: sequenceDuration,
            defaultViewMode: .tacticalTable,
            defaultPerspectiveID: "navy-rw",
            featuredPerspectiveIDs: ["navy-rw", "navy-rb", "navy-rcm", "red-lb"],
            players: commonPlayers,
            ball: commonBall,
            moments: [
                cue("matrix-context", 8.8, "COMMON CLOCK", "Freeze one decision", "Every card is tied to the same ball and player samples."),
                cue("matrix-seven", 10.5, "RIGHT WINGER", "The defender fills the picture", "Seven sees pressure arriving and must find the runner without following the ball."),
                cue("matrix-two", 12.8, "RIGHT-BACK", "The channel is opening", "Two can see that the recovering wide player is behind the run."),
                cue("matrix-defender", 14.0, "LEFT-BACK", "The runner leaves the blind side", "The defender's focus on seven hides the overlap for one decisive beat."),
                cue("matrix-eight", 16.2, "RIGHT MIDFIELDER", "The cut-back pocket is free", "Eight delays the arrival so the holding player cannot mark both ball and receiver."),
                cue("matrix-answer", 18.2, "SHARED ANSWER", "Four views explain one move", "The tactical view reconnects each local picture to the same successful action.")
            ],
            coachMarks: [
                mark("00000000-0000-4000-8000-000000000501", .danger, 25, 23, 28, 27, "Defender's attention", 10.5),
                mark("00000000-0000-4000-8000-000000000502", .run, 28, 14, 31, 35, "Runner outside view", 11.5),
                mark("00000000-0000-4000-8000-000000000503", .space, 12, 25, 17, 31, "Midfielder's picture", 15.5)
            ],
            formationTargets: [
                target("matrix-rw", "navy-rw", 27, 23, 1.5, "View A: ball carrier"),
                target("matrix-rb", "navy-rb", 31, 29, 1.5, "View B: overlap"),
                target("matrix-rcm", "navy-rcm", 15, 29, 1.8, "View C: cut-back"),
                target("matrix-lb", "red-lb", 28, 27, 1.8, "View D: defender")
            ]
        )
    }

    // MARK: - Scenario 06

    /// This local demo uses authored player and ball paths, not recovered video.
    /// Future reconstructed visual context must pass the world-admission checks;
    /// it must not silently replace the replay's player identities or paths.
    private static var realWorldReplay: ReplayScenario {
        ReplayScenario(
            id: "real-world-match-replay",
            kind: .realWorldReplay,
            title: "Synthetic match replay",
            strapline: "Authored play. Local review.",
            matchContext: "ORIGINAL SYNTHETIC DEMO • AUTHORED PLAYER PATHS",
            objective: "Replay authored player paths, switch POVs and annotate the play. This demo is simulated, not recovered from video.",
            coachPrompt: "Freeze the release. Link the run to two, the pass to seven and two, then scrub to prove every mark follows the play.",
            proofPoint: "Review one authored move from any player position, with marks tied to player paths and replay time.",
            duration: sequenceDuration,
            defaultViewMode: .tacticalTable,
            defaultPerspectiveID: "navy-rw",
            featuredPerspectiveIDs: ["navy-rw", "navy-rb", "navy-rcm", "red-lb"],
            players: commonPlayers,
            ball: commonBall,
            moments: [
                cue("world-source", 0, "AUTHORED DEMO", "Simulated match, no video", "These player and ball paths are authored. They are not recovered from match footage."),
                cue("world-register", 8.8, "REPLAY CLOCK", "One local match clock", "Scrub the timeline to review every player and the ball at the same moment."),
                cue("world-overlap", 11.3, "LINKED RUN", "Two accelerates outside", "The run arrow follows the right-back's authored path as you scrub."),
                cue("world-release", 13.6, "LINKED PASS", "Seven finds the outside lane", "Each pass endpoint stays linked to its chosen player during replay."),
                cue("world-cutback", 17.5, "SECOND ACTION", "Eight arrives behind the line", "Pause, label and compare the move from a player's position with free head look."),
                cue("world-proof", 24.0, "REVIEW AGAIN", "Compare the same move from another POV", "Rewind or switch players to examine this simulated move. Player identities and annotation links stay the same.")
            ],
            coachMarks: [
                mark(
                    "00000000-0000-4000-8000-000000000601",
                    .run,
                    28, 14, 31, 35,
                    "#2 tracked overlap",
                    11.3,
                    startPlayerID: "navy-rb",
                    endPlayerID: "navy-rb"
                ),
                mark(
                    "00000000-0000-4000-8000-000000000602",
                    .pass,
                    27, 23, 31, 29,
                    "#7 → #2 release",
                    13.6,
                    startPlayerID: "navy-rw",
                    endPlayerID: "navy-rb"
                ),
                mark(
                    "00000000-0000-4000-8000-000000000603",
                    .danger,
                    27, 24, 30, 30,
                    "#3 recovery line",
                    13.6,
                    startPlayerID: "red-lb",
                    endPlayerID: "red-lb"
                ),
                mark(
                    "00000000-0000-4000-8000-000000000604",
                    .space,
                    12, 24, 17, 31,
                    "Cut-back pocket",
                    16.2
                )
            ],
            formationTargets: [
                target("world-rw", "navy-rw", 27, 23, 1.5, "Tracked source #7"),
                target("world-rb", "navy-rb", 31, 29, 1.5, "Tracked receiver #2"),
                target("world-rcm", "navy-rcm", 15, 29, 1.8, "Tracked arrival #8"),
                target("world-lb", "red-lb", 28, 27, 1.8, "Tracked defender #3")
            ]
        )
    }

    // MARK: - Shared 22-player sequence

    private static func makeCommonPlayers() -> [PlayerTrack] {
        [
            // Northbridge Athletic — 4-3-3
            player("navy-gk", "Rowan Beck", "Goalkeeper", 1, .home, true, [
                k(0, 0, -48, 0), k(8, 0, -47.5, 0), k(16, 0.5, -46.5, 4),
                k(24, 1, -46, 0), k(27, 0, -46.5, 0), k(32, 0, -47, 0)
            ]),
            player("navy-rb", "Eli Ward", "Right back", 2, .home, false, [
                k(0, 23, -7, 5), k(3, 24, -4, 0), k(6, 25, 1, 0),
                k(8, 26, 8, 0), k(10.5, 27, 11, 0), k(11.3, 28, 14, 2),
                k(12.5, 30, 20, 7), k(13.5, 31, 25, 5), k(14.4, 31.5, 26, 0),
                k(15.6, 30.8, 32.7, -7), k(17.5, 30.5, 35, -12),
                k(20, 29.5, 36, -120),
                k(24, 28, 35, 180), k(27, 27, 33, 180), k(32, 26, 30, 180)
            ]),
            player("navy-rcb", "Noah Mercer", "Right centre-back", 4, .home, false, [
                k(0, 10, -17, 0), k(3, 12, -11, 10), k(6, 13, -8, 20),
                k(10, 14, -6, 5), k(16, 15, -4, 0), k(24, 13, -2, 0),
                k(27, 12, -4, 180), k(32, 11, -8, 180)
            ]),
            player("navy-lcb", "Luca Perrin", "Left centre-back", 5, .home, false, [
                k(0, -9, -20, 0), k(8, -8, -18, 0), k(16, -7, -15, 0),
                k(24, -6, -12, 0), k(27, -7, -13, 180), k(32, -8, -16, 180)
            ]),
            player("navy-lb", "Samir Hale", "Left back", 3, .home, false, [
                k(0, -25, -5, 0), k(8, -24, -3, 0), k(16, -23, 1, 0),
                k(24, -22, 5, 0), k(27, -23, 3, 180), k(32, -24, 0, 180)
            ]),
            player("navy-dm", "Theo Marr", "Holding midfielder", 6, .home, false, [
                k(0, 0, -6, 0), k(6, 1, -2, 0), k(12, 2, 3, 0),
                k(18, 3, 8, 0), k(24, 2, 12, 0), k(27, 1, 10, 180),
                k(32, 0, 6, 180)
            ]),
            player("navy-rcm", "Jae Okoro", "Right midfielder", 8, .home, false, [
                k(0, 11, 7, 0), k(6, 12, 10, 0), k(10, 14, 13, 0),
                k(13.5, 13, 23, 0), k(15.5, 14, 23, 5), k(16.5, 15, 27, 3),
                k(18, 15, 29, 35), k(21.5, 13, 31, 0), k(24, 11, 34, 0),
                k(27, 10, 34, 180), k(32, 10, 31, 180)
            ]),
            player("navy-lcm", "Milo Arden", "Left midfielder", 10, .home, false, [
                k(0, -11, 7, 0), k(8, -10, 9, 0), k(16, -8, 13, 0),
                k(24, -6, 20, 0), k(27, -7, 19, 180), k(32, -8, 15, 180)
            ]),
            player("navy-rw", "Ari Quinn", "Right winger", 7, .home, false, [
                k(0, 28, 19, 180), k(6, 28, 20, 170), k(8, 27, 18, 180),
                k(10.4, 27, 18, 165), k(11.0, 27.4, 19.5, 135),
                k(11.8, 26.8, 21.2, 110), k(12.7, 26.45, 22.9, 60),
                k(13.6, 27, 23, 20), k(16, 27, 24, 0), k(20, 26, 28, 0),
                k(24, 25, 32, 0), k(27, 25, 33, 180), k(32, 24, 32, 180)
            ]),
            player("navy-cf", "Leon Pike", "Centre forward", 9, .home, false, [
                k(0, 1, 28, 0), k(8, 1, 30, 0), k(14, 2, 33, 0),
                k(18, 3, 36, 0), k(21, 4, 38, 0), k(24, 4, 40, 15),
                k(25, 3, 41, 0), k(27, 2, 42, 180), k(32, 1, 39, 180)
            ]),
            player("navy-lw", "Niko Vale", "Left winger", 11, .home, false, [
                k(0, -27, 24, 0), k(8, -27, 26, 0), k(16, -27, 29, 0),
                k(24, -24, 34, 15), k(27, -23, 35, 180), k(32, -24, 32, 180)
            ]),

            // Eastport United — 4-2-3-1
            player("red-gk", "Dario Moss", "Goalkeeper", 1, .away, true, [
                k(0, 0, 49, 180), k(12, 0, 49, 180), k(20, 0, 49, 180),
                k(24, -0.5, 49.5, 180), k(25.2, -2, 50.5, -110),
                k(26.5, -3.5, 51.5, -90), k(28, -3, 51, 90), k(32, -1, 49.5, 180)
            ]),
            player("red-rb", "Felix Orr", "Right back", 2, .away, false, [
                k(0, -25, 28, 180), k(8, -25, 27, 180), k(16, -24, 30, 180),
                k(24, -22, 36, 180), k(27, -21, 37, 0), k(32, -22, 34, 0)
            ]),
            player("red-rcb", "Ivo Gray", "Right centre-back", 4, .away, false, [
                k(0, -8, 35, 180), k(8, -8, 34, 180), k(16, -7, 36, 180),
                k(21, -4, 39, 180), k(24, -2, 43, 180), k(27, -3, 44, 0),
                k(32, -5, 40, 0)
            ]),
            player("red-lcb", "Mateo Finn", "Left centre-back", 5, .away, false, [
                k(0, 8, 35, 180), k(6, 9, 34, 180), k(10, 10, 33, 180),
                k(13, 12, 33, 170), k(16, 14, 34, 150), k(18, 13, 36, 180),
                k(21, 10, 39, 180), k(24, 7, 43, 180), k(27, 7, 44, 0),
                k(32, 6, 40, 0)
            ]),
            player("red-lb", "Remy Cole", "Left back", 3, .away, false, [
                k(0, 25, 28, 180), k(6, 25, 27, 180), k(8, 26, 25, 180),
                k(10, 25.5, 24, 180), k(11.2, 25.8, 22.4, 170),
                k(12.2, 26.4, 22.5, 145), k(13.2, 27.2, 24.4, 110),
                k(14.0, 28.4, 27, 65), k(15.0, 30, 30, 15),
                k(16.4, 29.2, 34, -5),
                k(20, 25, 35, 180), k(24, 23, 37, 180), k(27, 24, 38, 0),
                k(32, 24, 35, 0)
            ]),
            player("red-rdm", "Bruno Dene", "Right holding midfielder", 8, .away, false, [
                k(0, -8, 18, 180), k(8, -7, 18, 180), k(16, -5, 22, 180),
                k(24, -3, 33, 180), k(27, -4, 34, 0), k(32, -5, 30, 0)
            ]),
            player("red-ldm", "Otis Carr", "Left holding midfielder", 6, .away, false, [
                k(0, 9, 19, 180), k(6, 10, 18, 180), k(10, 12, 20, 180),
                k(12, 14, 21, 180), k(14, 14, 24, 180), k(16, 15, 26, 180),
                k(18, 16, 28, 180), k(20, 15, 29, 180), k(22, 12, 33, 180),
                k(24, 10, 36, 180), k(27, 10, 37, 0), k(32, 9, 33, 0)
            ]),
            player("red-am", "Soren Lane", "Attacking midfielder", 10, .away, false, [
                k(0, 0, 4, 180), k(6, 2, 3, 120), k(12, 4, 7, 0),
                k(18, 5, 13, 0), k(24, 4, 20, 0), k(27, 3, 18, 180),
                k(32, 2, 14, 180)
            ]),
            player("red-rw", "Kai Noor", "Right winger", 7, .away, false, [
                k(0, -24, 9, 180), k(8, -23, 8, 180), k(16, -21, 12, 0),
                k(24, -18, 24, 0), k(27, -19, 25, 180), k(32, -21, 20, 180)
            ]),
            player("red-cf", "Hugo Wynn", "Centre forward", 9, .away, false, [
                k(0, 0, -4, 180), k(3, 7, -7, 135), k(6, 10, -5, 45),
                k(10, 7, 0, 0), k(16, 5, 5, 0), k(24, 4, 12, 0),
                k(27, 2, 10, 180), k(32, 1, 6, 180)
            ]),
            player("red-lw", "Eden Frost", "Left winger", 11, .away, false, [
                k(0, 24, 10, 180), k(6, 24, 8, 180), k(8, 24.5, 9, 90),
                k(10, 25, 11, 20), k(12.4, 27, 14, 10),
                k(13.4, 28.5, 18, 5), k(14.5, 29.5, 23, 0),
                k(15.4, 29, 27, -15), k(16.3, 27, 29, -60),
                k(20, 27, 29, 180),
                k(24, 24, 30, 180), k(27, 24, 31, 0), k(32, 23, 28, 0)
            ])
        ]
    }

    private static func makeCommonBall() -> BallTrack {
        BallTrack(keyframes: [
            ball(0, 10, -17, 0.11),
            ball(2.8, 12, -11, 0.11),
            ball(4.0, 13, -8, 0.11),
            ball(5.4, 23, -1, 0.20),
            ball(6.2, 25, 1, 0.11),
            ball(8.2, 26, 8, 0.11),
            ball(9.0, 26.5, 11, 0.18),
            ball(10.1, 27, 18, 0.11),
            ball(11.8, 27, 20.5, 0.11),
            ball(13.6, 27, 23, 0.11),
            ball(14.15, 28, 24.2, 0.28),
            ball(14.8, 31.2, 30, 0.11),
            ball(16.2, 30.6, 34.2, 0.11),
            ball(17.5, 30.5, 35, 0.11),
            ball(18.2, 28, 34.5, 0.16),
            ball(19.8, 15, 29, 0.11),
            ball(21.2, 13, 31, 0.11),
            ball(22.8, 4, 38.5, 0.16),
            ball(24.0, 4, 40, 0.11),
            ball(24.6, 2, 43, 0.30),
            ball(25.4, -1, 48, 0.85),
            ball(26.2, -4, 52, 0.65),
            ball(27.0, -4, 53, 0.11),
            ball(32.0, -4, 53, 0.11)
        ])
    }

    // MARK: - Builders

    private static func player(
        _ id: String,
        _ displayName: String,
        _ role: String,
        _ shirtNumber: Int,
        _ team: FootballTeam,
        _ isGoalkeeper: Bool,
        _ keyframes: [MotionKeyframe]
    ) -> PlayerTrack {
        PlayerTrack(
            id: id,
            displayName: displayName,
            role: role,
            shirtNumber: shirtNumber,
            team: team,
            isGoalkeeper: isGoalkeeper,
            keyframes: keyframes
        )
    }

    private static func k(
        _ time: TimeInterval,
        _ x: Float,
        _ z: Float,
        _ facingDegrees: Float
    ) -> MotionKeyframe {
        MotionKeyframe(
            time: time,
            position: PitchPoint(x: x, z: z),
            facingDegrees: facingDegrees
        )
    }

    private static func ball(
        _ time: TimeInterval,
        _ x: Float,
        _ z: Float,
        _ height: Float
    ) -> BallKeyframe {
        BallKeyframe(time: time, position: PitchPoint(x: x, z: z), height: height)
    }

    private static func cue(
        _ id: String,
        _ time: TimeInterval,
        _ kicker: String,
        _ headline: String,
        _ explanation: String
    ) -> CueMoment {
        CueMoment(
            id: id,
            time: time,
            kicker: kicker,
            headline: headline,
            explanation: explanation
        )
    }

    private static func mark(
        _ id: String,
        _ kind: CoachMarkKind,
        _ startX: Float,
        _ startZ: Float,
        _ endX: Float,
        _ endZ: Float,
        _ label: String,
        _ revealTime: TimeInterval,
        startPlayerID: String? = nil,
        endPlayerID: String? = nil
    ) -> CoachMark {
        guard let identifier = UUID(uuidString: id) else {
            preconditionFailure("Invalid deterministic coach-mark UUID: \(id)")
        }
        let start = PitchPoint(x: startX, z: startZ)
        let end = PitchPoint(x: endX, z: endZ)

        func anchor(playerID: String?, endpoint: PitchPoint) -> CoachMarkTrackAnchor? {
            guard let playerID,
                  let player = commonPlayers.first(where: { $0.id == playerID }) else {
                return nil
            }
            let playerPosition = player.presentationPose(at: revealTime).position
            return CoachMarkTrackAnchor(
                playerID: playerID,
                offset: PitchPoint(
                    x: endpoint.x - playerPosition.x,
                    z: endpoint.z - playerPosition.z
                )
            )
        }

        return CoachMark(
            id: identifier,
            kind: kind,
            start: start,
            end: end,
            label: label,
            revealTime: revealTime,
            author: "Coach Vale",
            startTrackAnchor: anchor(playerID: startPlayerID, endpoint: start),
            endTrackAnchor: anchor(playerID: endPlayerID, endpoint: end)
        )
    }

    private static func target(
        _ id: String,
        _ playerID: String,
        _ x: Float,
        _ z: Float,
        _ toleranceMetres: Float,
        _ label: String
    ) -> FormationTarget {
        FormationTarget(
            id: id,
            playerID: playerID,
            position: PitchPoint(x: x, z: z),
            toleranceMetres: toleranceMetres,
            label: label
        )
    }
}
