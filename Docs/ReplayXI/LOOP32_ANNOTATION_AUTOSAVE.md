# Loop 32 — durable annotation moves

## Fix

A coach could hold a moved annotation handle still long enough for the 600 ms
autosave to write the pre-drag geometry. That masking is intentional: an
unfinished pinch must not become the saved review.

Releasing the handle then removed the preview mask without changing the mark
value already on screen. No observed property changed, so another autosave
was not scheduled. A later relaunch could restore the old position.

Both successful geometry commit paths now explicitly schedule autosave:

- direct handle drag, including an unchanged final sample;
- joystick adjustment after its preview mask is removed.

The existing debounce, atomic disk writes, cancelled-gesture rollback, and
single SharePlay commit packet are unchanged. No per-frame save was added.

## Regression coverage

Two new disk-backed tests follow the actual boundary: preview a move, save the
masked baseline, commit without another state change, wait for the debounce,
then load a fresh library from disk and compare complete marks.

The tests run only in unique temporary folders. Cleanup happens after the
reload assertion so a final flush cannot hide the bug.

## Verification

- Tests-first run: XCTest reported 2 tests run, 2 failed. Xcode then stalled
  while collecting/finalising failure diagnostics; that process was stopped.
  The incomplete red report is not treated as a completed result bundle.
- Fixed-code full visionOS 27 Simulator suite: **348 passed, 1 skipped,
  0 failed**. This includes both new disk-backed regression tests plus the
  existing gesture cancellation, playback and shared-state tests.
  Report: `/private/tmp/replayxi-loop32-green.xcresult`.
- Simulator Debug and physical-device-target Release builds succeeded. The
  updated app was relaunched in normal persistent-save mode in Simulator.
  No physical headset test was performed.
- Swift parse and `git diff --check` pass.
- No UI/graphics changes in this batch. The prior post-fit player visual check
  remains pending while the Mac is locked.
- Git pushes remain paused pending the already-requested exact repository
  approval. This batch makes no push attempt.
