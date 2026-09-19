# Improvement run 139

Local-only Match Replay and Strategy Analysis. Previous pass made verified
progress; current goal remains active. User project/Info.plist changes preserved.

## Keyframed annotation / Follow

The Follow drawer offered 22 enabled player buttons for a keyed annotation, but
the Store correctly rejected every selection. Its status also claimed the moving
annotation was fixed to the pitch. Native baseline reproduces the mismatch: the
two UI-wiring assertions fail while explicit Freeze → Follow and Undo pass.

The keyed drawer now reports its saved positions and offers Edit keys, leading
to the existing Timing editor without changing selection or geometry. It does
not freeze/delete keys implicitly. Following stays unavailable until the user
explicitly chooses Freeze here. The Follow button retains its action name;
status and VoiceOver explain the timestamped positions. Both teams' existing
tracking paths and separate Freeze/Follow Undo entries are unchanged.

Five policy/Store/wiring tests and two native notice captures pass. Regular text
uses one row; largest accessibility text stacks the action without clipping.
Captures cover the new notice, not hands-on use of the full immersive deck.

## Annotation visibility work

With 128 hidden annotations, 60 native paused updates requested 30,780 writes to
unchanged visibility flags. Eight forward/reverse reveal-boundary updates wrote
4,104 flags while only 48 changed. Each audited assignment now checks the actual
entity value; no memoization or timestamp cache was added.

Candidate: zero paused writes; 48 boundary writes for 48 actual changes. All 17
externally altered flags in the repair fixture are restored, with the same entity
tree. Selection, POV caption limits, drawing and editable out-of-window behaviour
pass. These are property-call counts, not engine-internal savings or FPS claims.
The existing sync timing counter does not measure this visibility loop.

## Evidence so far

- Native baseline: /private/tmp/replayxi-cycle139-baseline.xcresult — eight tests,
  only the two expected Follow wiring assertion failures.
- Combined UI/performance candidate: 50 tests, zero failures.
  /private/tmp/replayxi-cycle139-ui-perf-candidate.xcresult.
- /private/tmp/replayxi-cycle139-follow-candidate-captures.
- /private/tmp/replayxi-cycle139-visibility-baseline-captures.
- /private/tmp/replayxi-cycle139-visibility-candidate-captures.

## Dashboard POV roster

Opening an opponent POV previously left the home team selected. Crossing teams
with Previous/Next also left the selected player offscreen. A native baseline
recorded zero horizontal offset for every last-player selection.

The roster now reveals the selected player and matching team on entry, POV
changes and scenario changes. Its scroll binding is presentation-only; browsing
the strip never changes the camera or replay time. View controls use named,
accessible icons with 44-point minimum targets instead of wrapped labels.
Selected shirts and view icons use dark text on lime for clearer contrast.

Four native/wiring tests pass, including both teams, a blocked POV request,
scenario changes and largest accessibility text. Native scroll offsets reach the
actual end for last-player selections and return to zero for the first opponent.
Seven native captures were exported; regular and largest-text captures were
inspected and the selected player and view controls fit.
Ten existing timeline tests also pass. This checks native hosting and Store
transitions, not hands-on headset gaze/gesture input.

- /private/tmp/replayxi-cycle139-dashboard-polish-captures.
- /private/tmp/replayxi-cycle139-motion-dashboard.xcresult: dashboard 4/4,
  timeline 10/10 and prior phase 6/6 pass. New motion tests are 3/4: the raw-zero
  transition check caught a 0.0356 weight step against its 0.03 bound. Motion
  work is not accepted by this checkpoint and remains under investigation.

Hands-on gesture testing remains pending; the locked Mac was not bypassed.

## Timed geometry at the key limit

At 64 saved positions, shape/arc controls used to offer edits between keys that
the Store then rejected as an invalid 65th key. Height changes could report an
unrelated pitch-height error. A shared capacity policy now distinguishes an
existing timestamp from a new one, preserving the strict `< 1e-6` replacement
tolerance. Timing, arc, endpoint and height controls agree, with a short reason
and accurate accessibility hints. No keys are evicted or silently frozen.

Seven native policy/Store/wiring tests pass: all nine attempted mutation routes
reject a new 65th key without changing playback, marks or Undo; five edit paths
still work at existing keys. Continuous preview can occupy the final slot, and
deleting a key permits a new position again. Regular and largest-text capacity
captures pass; the largest-text capture was inspected and the hint fits.

## Identical clipped arcs

Different raw curve settings can resolve to the same clipped quadratic at the
touchline. The mesh cache now reuses exactly matching resolved geometry, even
when those settings differ. The previous translation tolerance remains limited
to unchanged curve parameters: tiny actual curve edits still rebuild.

For 60 forward/reverse samples of one selected clipped arc (base plus two
highlight tubes), native builds and mesh replacements fall from 180 to zero.
All generated vertices and normals are unchanged; real shape, thickness, height
and view changes rebuild correctly. External transform repair and reverse seeks
pass. This is measured construction work, not a headset FPS claim.

## Native cut-weight hand-off

Stage diagnostics located two abrupt knee/hip changes in the native football
retarget blend, rather than in source sampling, floor correction or look logic.
A source-gated three-tap cut-weight filter at absolute replay time, +/- 0.10 s,
now drives both retargeting and phase admission. It has no history-dependent
state and leaves the protected ball-contact core unchanged.

Measured maximum joint step per 120-Hz sample, near and low LODs:

- arg-10, rebound 1.20–1.65 s: 19.058 to 17.394 degrees.
- fra-5, counter 11.1917–11.3417 s: 9.249 to 6.611 degrees.
- Across 20 wider windows spanning all five studies and both teams: 14 maximum
  joint steps improve and six tie. No window maximum worsens. This does not
  mean every frame improves: one local release step rises from 3.75 to 5.95
  degrees. A protected header chest step of 30.743 degrees remains unchanged;
  the rebound's wider arm peak still reaches 25.770 degrees. Not EAFC quality.

The earlier 0.03/frame scalar assertion was not a valid discontinuity test:
neighbouring deltas increased smoothly. It was replaced, not relaxed, with
shrinking-epsilon tests of the two zero crossings and actual native poses. At
20-microsecond intervals, scalar differences are 0.000171/0.000103 and maximum
native rotation differences are about 0.056 degrees (float angular resolution).
A deliberately raw-zero-gated negative control retains jumps of 0.242/0.343.
Original aligned and unaligned control hashes, exact rewind, bone lengths and
floor guards pass. Eight matched native A/B stills were exported; near and low
pairs were inspected. Still images alone do not prove animation smoothness.

Actual work in those 20 wide windows: 2,852 extra locomotion samples across
1,700 native frames, bounded to zero or two per update. All 246 protected-core
frames remain exact. This measures call count, not CPU cost or FPS.

All five fresh ball recordings match the cycle138 trajectories, touches and
planned-touch data exactly: 6,125 samples, 27 contacts, zero missed touches.

## Integrated checkpoint

- 67 targeted native tests pass: new capacity, clipping, transport, motion and
  existing timeline, dashboard, reference-match and phase regressions.
  /private/tmp/replayxi-cycle139-integrated-candidate.xcresult.
- Unsigned visionOS device Release build succeeds; only the unused AppIntents
  metadata warning. /private/tmp/replayxi-cycle139-release.log.
- Dashboard transport now uses the referenced team and short position code,
  retaining the full player identity for accessibility. Three tests pass; the
  largest-text native capture fits without the former two-line role label.
- /private/tmp/replayxi-cycle139-motion-final-captures.
- /private/tmp/replayxi-cycle139-motion-visual-captures.
- /private/tmp/replayxi-cycle139-arc-candidate-captures.
- /private/tmp/replayxi-cycle139-capacity-captures.
- /private/tmp/replayxi-cycle139-ball-captures.

The first full regression completed 1,393 XCTest cases (two intentional skips)
and two Swift Testing cases. Three native arm/grounding methods failed with 542
assertions: the new smoother sampled neighbouring track poses despite explicit
caller-supplied straight/walking overrides. The native API now requires explicit
`allowsTrackLocomotionSampling` opt-in for this smoother, defaulting to false.
The shipping scene opts in only for track-derived locomotion, not stationary
overrides. Existing exact-source assertions were retained unchanged.

All 26 focused native regressions pass after this fix: arm swing, grounding,
scene bindings and both phase/transition diagnostic classes, including new
exact-override and real raw-zero opt-in checks.
/private/tmp/replayxi-cycle139-motion-opt-in.xcresult. A full rerun is pending.

Saved-review hash is unchanged from the previous checkpoint; no personal
signing or Info.plist edits are included.
