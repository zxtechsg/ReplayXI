# Loop 44 — annotation timing and draft safety

## Reproduced issues

Five new behaviour tests failed against the prior code:
`/private/tmp/replayxi-timing44-repro.xcresult`.

- New marks near a clip's end stored an eight-second window beyond that clip.
- The UI rejected some late retiming operations while the store accepted them.
  Duration choices could also create windows that did not fit the replay.
- Store transport commands could play, seek or change speed during a two-point
  drawing, even though the main visible controls were disabled.
- Preset arrows pointing out of a pitch corner were clamped into a zero-length
  or unreadably short mark.

## Fixes

- New marks retain the normal eight-second duration when it fits. At the clip
  tail they use **To end**, including the final paused frame. This applies to
  drawn strokes, labels and presets.
- One authoring-time policy is shared by duration/retiming controls and store
  mutations. Finite windows must fit; unavailable duration buttons explain
  that To end is available. The duration shelf shows the mark's start time,
  rather than implying its duration begins at the current playhead.
- Historical saved windows extending beyond the clip remain valid and editable.
  No stricter disk schema or destructive migration was introduced. Their timing
  can be corrected with To end or a duration that fits.
- Playing, toggling transport, seeking, skipping and changing speed cannot move
  an unfinished drawing's clock. Safety pause and Cancel remain available.
  Passive clock advancement also refuses to move while drawing.
- Non-finite/off-clip times cannot create new marks. Presets turn back into the
  pitch near its edges and pass geometry/state validation before insertion.

## Verification

- The five reproduced behaviours passed after the changes, alongside history,
  timeline and view-ownership regression checks.
  `/private/tmp/replayxi-timing44-targeted-01.xcresult`.
- Final full Simulator suite, including legacy-save and malformed-input checks:
  **426 passed, 1 optional skip, 0 failed (427 total)**.
  `/private/tmp/replayxi-timing44-full-01.xcresult`.
- Unsigned visionOS Release build passed:
  `/private/tmp/replayxi-timing44-release-01.log`.
- Python pipeline checks: **107 passed, 12 optional skips**, no failures.
  `/private/tmp/replayxi-timing44-python-01.log`.
- New tests cover every mark kind at the replay end, exact final-frame
  visibility, autosaves, old-save compatibility, action history, all transport
  routes during drawing, each pitch corner and non-finite inputs.

Live UI/hand testing remains unverified while the Mac is locked. This is a
verified code/Simulator batch; the timed goal remains active until the 9am handoff.
