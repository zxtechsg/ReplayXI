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
Seven native captures were inspected; the selected player and view controls fit.
Ten existing timeline tests also pass. This checks native hosting and Store
transitions, not hands-on headset gaze/gesture input.

- /private/tmp/replayxi-cycle139-dashboard-polish-captures.
- /private/tmp/replayxi-cycle139-motion-dashboard.xcresult: dashboard 4/4,
  timeline 10/10 and prior phase 6/6 pass. New motion tests are 3/4: the raw-zero
  transition check caught a 0.0356 weight step against its 0.03 bound. Motion
  work is not accepted by this checkpoint and remains under investigation.

Hands-on gesture testing remains pending; the locked Mac was not bypassed.
