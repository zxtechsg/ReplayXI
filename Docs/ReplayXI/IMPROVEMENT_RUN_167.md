# Cycle 167 — remove repeated playback work

Scope: local playback and annotation editing. No new cloud work, assets, saved-review schema, rendering budgets, or motion authoring changes.

## Changes

- Animated annotation revisions keep their intact scene tree and apply only the time-sampled geometry. Previously, a same-ID keyframe/track edit could write its base pose and then overwrite it with the sampled pose in the same frame. Hidden edits defer geometry until visible; removing animation still applies the static pose immediately. Hit targets follow the displayed pose.
- Gait sampling reuses the wrapped phase for run/slow-run frame selection. Idle skips unused phase work. The duration boundary still wraps to zero. Joint interpolation, contacts, model geometry and motion clips are unchanged.
- The store caches authored annotation IDs once per immutable scenario. Ten edit paths no longer construct the same `map` + `Set`; seven equivalent membership checks reuse the cache. Index-based storage preserves first-match and unknown-ID fallback semantics.
- Initial scene creation and ordinary updates now share one update function. Removed an unused annotation geometry argument. No transport or gesture-controller merge: their different ownership/input rules are intentional.

## Verification

- visionOS 26.5 Simulator: **239 tests passed, zero failed/skipped**. Result: `.codex-derived/replayxi-perf167/Regression265-01.xcresult`; log: `/private/tmp/replayxi167-regression265-01.log`.
- Both unsigned Release builds pass: visionOS device and Simulator. Logs: `/private/tmp/replayxi167-device-release.log` and `/private/tmp/replayxi167-simulator-release.log`.
- Swift syntax parsing and `git diff --check` pass.
- Confirmed counter reduction for the edited animated mark: **one sampled geometry update, zero base-pose updates**. Same timestamp, reverse seeking, hidden edits and selectable hit geometry are tested; unchanged paused geometry still skips work.
- Existing persistence, undo/redo, gesture, arc, draw-budget, player-detail and native rig tests are included. This is a selected regression suite, not every repository test.
- Main Simulator saved-review SHA-256 remains `a472d19ff9b2f3495dab0b38d98c306dddfed2e2e0493c8a450ce82f4e9b18cb`. Tests used the separate native-audit Simulator. Both player USDZ hashes are unchanged.

Added checks cover exact Tripo52/Rocketbox80 pose parity across playback, reverse seeks, invalid phases and slow-run blends; static/animated transitions; edits while hidden; home/away track anchors; hit targets; authored-mark protection; and scenario selection edge cases.

## Limits

These are reduced operations, not a measured headset FPS gain. No claim of lower GPU time or EAFC-level animation. Existing cloth, hand-pose and source-animation limitations remain. User-owned project/signing edits are outside this commit.
