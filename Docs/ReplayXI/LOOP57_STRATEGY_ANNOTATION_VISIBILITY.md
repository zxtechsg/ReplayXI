# Loop 57 — visible Strategy annotations

## Fixed

Shape Focus accepted and saved a new run in Ideal, but disabled the entire
annotation root. Problem also filtered every mark to pressure arrows, including
the coach's own runs, passes, zones and player labels. This made valid edits
disappear immediately after drawing.

- All five coach-created mark types now appear in both tabletop stages and can
  show their selection handles. Preset marks remain separate: only the authored
  pressure cue appears in Problem, and no preset problem overlay appears in Ideal.
- The physical station drill still hides annotation geometry and handles. Ending
  the drill restores the saved tabletop annotations.
- Presentation-ineligible marks are excluded before draw-budget admission. Hidden
  presets and hidden/stale selections cannot consume slots needed by visible marks.
- The filter uses existing cached priority indices and a predicate, not a new
  per-frame filtered array. Draw caps are unchanged. Timed visibility, rewind and
  stable entity reuse remain intact.

No annotation data, save schema or preset identity changed. This does not add
physical-room annotation authoring or automated video tracking.

## Checks

- Pre-fix native regression failed: a user run saved in Ideal had a hidden root
  and no selection affordance. Receipt:
  `/private/tmp/replayxi-boundaries55-repro-01.xcresult`.
- Five scene tests cover all five mark kinds in both stages, selection, preset
  suppression, physical placement/end, timing and exact entity reuse on rewind.
- Five budget tests cover hidden recent marks, excluded/stale/expired selections,
  fully hidden scenes and the unchanged selected-mark draw envelope.
- Combined Simulator run: **556 passed, 1 optional skip, 0 failed (557 total)**.
  `/private/tmp/replayxi-parallel55-full-01.xcresult`.
- Python checks: **111 passed, 12 optional skips**.
  `/private/tmp/replayxi-parallel55-python-01.log`.
- Unsigned physical-device Release: **BUILD SUCCEEDED**.
  `/private/tmp/replayxi-parallel55-release-01.log`.
- Swift parsing and `git diff --check` passed.

Scene assertions establish visibility and input geometry, not headset comfort or
frame rate. Interactive UI checks remain pending while the desktop is locked.
