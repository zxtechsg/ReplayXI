# Improvement run 137

Local-only Match Replay and Strategy Analysis. Goal remains active.

## Timeline completion ownership

An immersive timeline's late `onEnded` could previously restart a cancelled scrub through its
preview helper, then commit and autosave the stale pinch time. The new controller only finishes
its own live transaction. Each accepted Store scrub has a device-local generation ID; an old
controller cannot preview, finish or cancel another control surface's replacement scrub.

Normal tap-to-seek, the final drag sample, precision mapping, transport restoration and autosave
are preserved. Generation IDs never enter saved reviews. Store cancellation, invalid commits
and immersive exit release ownership.

27 focused controller/mapping/discrete-action/gesture-autosave tests passed, including ten new
ownership tests. The combined baseline batch passed 34 tests total:
/private/tmp/replayxi-cycle137-baseline-v3.xcresult.

## Player-tag update baseline

Five native entity tests confirm that 60 unchanged updates of 22 tags request 3,960 transform
field writes, 9,240 style-property writes and 1,320 visibility writes. Input components already
avoid redundant writes. This counts requested RealityKit writes, not internal engine work or
headset FPS. Optimization is in progress; selection, focus, hidden-to-visible catch-up, cloned
entities, detached parents and pitch transforms are covered.

## Fast direction baseline

Counterattack fra-22 is travelling over 4.5 m/s while body direction differs by over 100°.
Directional footwork fades out above 4.5 m/s; inferred body heading switches abruptly from
ball-facing to travel-facing above 3.2 m/s, then catches up at a capped keyframe increment.
Actual presentation derivatives are separately measured: the 14°/100 ms keyframe bound is not
a guarantee of a 140°/s maximum after Hermite interpolation.

Two native baseline tests passed and eight calibrated near/low frames were captured. The
counterattack window and contact-adjacent rebound arg-10 control include 120 Hz sole, direction,
floor, bone-length and exact-rewind measurements. Near-floor samples are not asserted to be
measured foot contact forces. Changes must preserve all routes, explicitly authored headings,
goalkeepers and contact actors; the first target is inferred off-ball headings for no-touch
outfield players. No improved motion or recovered match telemetry is claimed yet.

Evidence: /private/tmp/replayxi-cycle137-baseline-v3-captures/manifest.json.
