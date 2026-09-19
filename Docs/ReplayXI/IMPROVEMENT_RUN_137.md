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

The candidate anticipates acceleration by up to 0.65 seconds, blending ball-facing
and travel-facing intent before the run. It preserves the existing 140°/s waypoint
step limit; that is not a claim about interpolated angular speed. Only non-contact
outfield actors without explicit facing paths use it. Goalkeepers, contact actors,
authored facing streams and all three legacy references bypass it.

Native A/B checks across all five studies passed: among 5,854 samples above 4.5 m/s,
backwards-facing samples (>90° mismatch) fell from 51 to zero. Counterattack away-team
peak mismatch fell from 145.55° to 11.39°. Not every metric improved: volley home-team
peak mismatch rose from 1.07° to 7.36°. Actual 120 Hz heading rate stays below the
215°/s regression ceiling. Independent pre-change fingerprints match every waypoint
and 120 Hz player position, plus all protected headings, across five current and
three legacy studies.

Five freshly baked RealityKit recordings retained exactly the same 27 contacts and
all 6,125 position/velocity samples as the baseline (zero missed touches and zero
path deltas). Native near/low frames show fra-22 facing his run, not running backwards.
This remains inferred reconstruction, not recovered telemetry.

Residual footwork issue: fra-22's near-floor candidate distance fell 4.08→0.865 m,
but its candidate duration also fell 0.675→0.258 s. Peak near-floor sole speed rose
7.71→10.61 m/s; maximum joint step stayed 9.81°. These are geometric candidates,
not measured planted contacts. Sliding is not solved. The protected arg-10 control
is unchanged, including its 19.31° joint-step peak.

Candidate evidence: /private/tmp/replayxi-cycle137-motion-arc-candidate.xcresult;
baseline distribution: /private/tmp/replayxi-cycle137-heading-distribution-baseline.xcresult;
baseline full ball paths: /private/tmp/replayxi-cycle137-ball-baseline.xcresult.

## Arc hit-target sampling

Native baseline tests found a real degenerate arc bug: `simd_quatf()` is a zero
quaternion, not an identity rotation. Tiny/flat arc segments now use explicit unit
identity; tests check unit length and forward-vector preservation. Related zero
quaternion uses elsewhere are queued for a separate, measured fix.

The moving-arc baseline performs 1,920 control-point resolutions and 1,920 point
samples over 60 updates. The optimized native rerun passes all four arc tests:
60 control-point resolutions and 1,020 samples, with no persistent cache or sample
array. Paused updates still request zero work. Independent old-method samples
check roll, elevation, clipping, degenerate endpoints, same-time edits, hide/reveal,
rewind and externally changed/cloned targets.

Receipt: /private/tmp/replayxi-cycle137-arc-optimized-captures/80620952-F851-4C16-881C-71BD189D9DCC.json.
The unsigned visionOS Release build passes with no Swift warnings; the generic
AppIntents metadata-extraction warning remains because that framework is not used.

## Next bounded checks

- Replace remaining zero-quaternion identity fallbacks with unit rotations, with
  native annotation and procedural-rig regressions. Do not alter unrelated poses.
  Independent native SIMD probing confirms zero quaternion → zero upper 3×3
  matrix, not identity. Four annotation targets/selected paths and three pitch
  draft/rail/guide resets are affected; the procedural model default is another
  case (the imported far-body branch already repairs it). Existing local-coordinate
  checks can miss collapsed child transforms; add converted-axis/handle tests.
- Direct annotation handles still identify an edit by mark, unlike token-owned
  curve/joystick edits. Store-level A-preview → cancel → B-preview → stale A-end can
  affect B on the same mark. UI cleanup blocks several paths; delayed delivery after
  a new recognizer sequence is not yet a verified headset repro. Add a regression
  before changing this path.
- Measure near-floor foot motion separately from run-facing error. Better heading
  is not evidence of correct foot contact or recovered player tracking.
- Hands-on native Slider ordering remains unverified: computer-use reported the
  Mac locked. Code/controller tests and native render tests can run while locked.

## Final integrated verification

The first full run exposed two more old source-wiring assertions that banned any
timeline-active condition, including the new correctly scoped foreign-owner gate.
Both now require the generation comparison while preserving own-drag admission.
No production code changed after the passing Release build.

Final full rerun: **1,325 XCTest tests, two intentional skips, zero failures**;
both Swift Testing asset checks also pass. Evidence:
/private/tmp/replayxi-cycle137-full-v2.log and .xcresult.
Unsigned device Release: /private/tmp/replayxi-cycle137-release.log.

Production review SHA-256 remains
`952e501de62f36e391a5b471175c883d0deb9e981a5c6cfc04f607c6dc5ded65`.
All task commits are backed up to origin/main; unrelated project/plist changes
and unrelated untracked projects are preserved. The improvement goal remains active.
