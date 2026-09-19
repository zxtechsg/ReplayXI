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

Dashboard roster improvements and native cut-blend work remain under validation.
Hands-on gesture testing remains pending; the locked Mac was not bypassed.
