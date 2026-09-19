# Improvement run 140

Local-only Match Replay and Strategy Analysis. Goal remains active. Personal
signing and Info.plist edits are excluded from these backups.

## Close Timing without losing work

Timing previously had no direct Close/Back control. Its fixed header now has a
named spatial-size Close icon. Clean close returns to the same selected mark's
inspector without seeking or writing. Dirty close requests the existing draft
resolution flow synchronously; it does not clear drafts or silently apply them.
Apply commits both drafts atomically, Discard keeps the saved replay unchanged,
and Keep editing retains both drafts and their owner.

Six route/session/wiring regressions and five native editor captures pass.
Largest-text and pending-draft captures were inspected: Close stays visible and
the header fits. Existing draft-session and timing-text tests also pass. These
checks do not claim hands-on headset button/gaze activation.

- /private/tmp/replayxi-cycle140-close-benchmark.xcresult: 33 tests, zero failures.
- /private/tmp/replayxi-cycle140-timing-captures.

## Ball setter experiment: not shipped

A test-only RealityKit microbenchmark compared ten unconditional setters with
exact live-value guards for the ball, shadow and highlight. It used the same
three parented entities, precomputed desired states and 12 alternating-order
pairs of 2,048 requests. Forward/reverse requests, external edits and quaternion
sign equivalence retain equivalent presentation.

Median guarded/direct ratios: paused 0.510, changing every request 1.279, seven
of eight requests held 0.626. Direct batches took about 0.89–0.98 ms: under half
a microsecond per request. The guard regresses the changing-state stress case,
and absolute potential savings are tiny. No shipping setter changes were made.

This is an unoptimized DEBUG synchronous property-access experiment, not an
active renderer, physics, device-CPU or FPS benchmark. Changing-state inputs
also stress style/visibility changes more often than normal replay. Raw paired
measurements are kept for review rather than generalized into app-level gains.

- /private/tmp/replayxi-cycle140-ball-setter-benchmark/
  C21983AD-1A63-4505-A62D-FBAB2154F8BD.json.

## Validation

The cycle139 caller-override fix passed all 26 focused motion regressions.
The fresh full native suite passes: 1,405 XCTest cases, two intentional skips,
zero failures, plus both Swift Testing asset cases. This includes unchanged
exact-source arm and airborne-pose assertions that caught the earlier regression.

- /private/tmp/replayxi-cycle140-full.xcresult and .log.
- Unsigned device Release succeeds; only unused AppIntents metadata warning.
  /private/tmp/replayxi-cycle140-release.log.

Normal demo relaunched successfully (PID 59698), then process-checked. Production
reviews remain byte-identical, SHA-256
`952e501de62f36e391a5b471175c883d0deb9e981a5c6cfc04f607c6dc5ded65`.
The Mac remains locked; no hands-on headset/gesture validation is claimed.

Next animation target: confirm the discrete chest-retarget switch when a header
cue ends. The existing 30.743-degree chest step is still present; it was not
hidden by reducing validation coverage or clamping joint angles.

Next performance target: attribute the full-skin floor scan with optimized
native measurements before changing it. Verified contact assets contain 339
vertices/603 influences (near) and 1,707/2,823 (low). One near plus three low
instances therefore scan 5,460 vertices and 9,072 influences per update. These
counts identify work, not measured time; no grounding coverage is reduced.
