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

The dashboard now has its own transaction controller too. Closing it cannot cancel
an immersive scrub; old value/end callbacks cannot take a replacement transaction or
fall back to a discrete seek. Both rails disable only for a foreign scrub, preserving
their own continuous drag. Explicit VoiceOver actions retain 0.1-second steps. A
same-turn staged sample supports native Slider's setter-before-start ordering without
seeking from an idle binding callback. A new explicit start or accessibility action
recovers after a missing end callback. Fourteen dashboard tests passed. After updating
an older immersive source-wiring expectation for the foreign-owner gate, all 42
timeline/controller/gesture-autosave tests passed in the integrated rerun:
/private/tmp/replayxi-cycle137-arc-baseline-dashboard-v2.xcresult. That combined batch
also exposed an unrelated pre-existing zero-quaternion arc fallback in its four new
arc tests; the fallback is being corrected separately.

Scope: native Slider supplies no gesture identity for `editing=true`. Delayed start
events are not claimed to be distinguishable from a new start. Generation checks
protect value/end/disappearance handling; no saved-review schema change is needed.

## Player-tag update baseline

Five native entity tests confirm that 60 unchanged updates of 22 tags request 3,960 transform
field writes, 9,240 style-property writes and 1,320 visibility writes. Input components already
avoid redundant writes. This counts requested RealityKit writes, not internal engine work or
headset FPS. Selection, focus, hidden-to-visible catch-up, cloned
entities, detached parents and pitch transforms are covered.

The optimized native rerun passed six tests. Unchanged updates now request zero writes;
the forward/reverse sequence requests 1,268 combined transform writes, one per changed
tag, instead of 14,520 property writes. Style, visibility and input writes are zero in
that sequence. Guards read actual entities, so external changes are repaired. Quaternion
sign equivalence is accepted; 0.0001 position, angle and scale changes are not discarded.

Evidence: /private/tmp/replayxi-cycle137-labels-fingerprint.xcresult and its exported
PlayerLabelWork receipt. This is reduced submission work, not a measured FPS gain.

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
