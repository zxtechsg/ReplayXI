# Loop 50 — one autosave worker per editing burst

## Evidence and change

The pre-fix regression fed 600 paused timeline samples through the actual Store.
It observed **600 distinct autosave workers**, failing the one-worker bound.
`/private/tmp/replayxi-autosave50-repro.xcresult` records that intentional failure.

The Store now advances a monotonic 600 ms deadline while one worker waits.
At an old deadline the worker checks for a newer edit and sleeps for the remaining
time. It still saves 600 ms after the last change; it does not save every frame.
The same 600-sample test now observes **one worker**.

- Flush and restore retire the worker's identity before cancellation. A stale
  wake cannot clear a replacement worker or save over a restored review.
- Exit/background flush remains immediate and captures committed geometry/time.
- The worker keeps only a deadline, not a strong Store reference, across sleep.
- Memory-only demos and read-only future-schema libraries schedule no disk work.
- Existing masked-preview saves and final gesture commits are unchanged.
- No save schema, file path, backup rotation, or user review was changed.

## Checks

- **25 targeted tests passed**: eight scheduling/lifetime checks, two gesture-save
  regressions, fourteen persistence tests, and the requested player-pose export.
  `/private/tmp/replayxi-autosave50-targeted-01.xcresult`.
- The scheduling checks include deadline extension, explicit flush, restore/new
  edit, future-schema preservation, passive playback and Store release.
- Unsigned physical visionOS Release: **BUILD SUCCEEDED**.
  `/private/tmp/replayxi-autosave50-release-01.log`.
- Python checks: **110 passed, 12 optional skips**, no failures.
  `/private/tmp/replayxi-autosave50-python-01.log`.
- `git diff --check` passed. This backup excludes other agents' ongoing visual,
  UI and annotation-position work and the user's signing changes.

This proves bounded task creation, not a measured headset frame-rate gain.
Disk encoding/writing is still synchronous at the committed save boundary.
A full combined regression run follows when the parallel changes are ready.
