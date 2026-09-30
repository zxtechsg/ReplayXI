# Run 162 — local app fixes while Tripo awaits sign-in

## Changes

- Position-key authoring explains why **Add here** is disabled at an existing
  key. It uses the same timestamp tolerance as capture; unresolved draft hints
  remain higher priority.
- Review naming shares the persistence validator. Invalid names show a short
  inline reason and block both Save and keyboard submission. Pasted names are
  no longer silently cut short. A rename uses the current review identity and
  read-only status, but does not inherit the 40-new-save limit or take ownership
  of a playback scrub. Valid names still trim surrounding whitespace.
- Player-label roots build a bounded child-index map once, instead of scanning
  the label children independently for every player on every update. Each
  cached index is checked against the live child's name; changed hierarchies
  use the original lookup. No retained player entities or global cache added.

## Verification

- Final focused visionOS27 regression: **76 passed, 0 failed, 0 skipped**.
  `/private/tmp/replayxi-cycle162-final.xcresult` covers annotation keys/capacity,
  timing drafts, save/rename/recovery, large-text layouts, player-label identity,
  clones/removal/reordering, and the POV → keyframed arc → scrub → save/restore
  workflow. Native default and largest-text forms were rendered and inspected;
  validation feedback and actions fit their existing scrollable panels.
- The first pass had two incorrect new-test assumptions: Store capture upserts
  existing keys, and RealityKit removal does not shift every child index. The
  next pass exposed a too-strict comparison of nil and explicit-zero elevation
  fields after an upsert. Corrected the fixtures to verify unchanged keyframes
  and sampled geometry and to use the original live child indices. No production
  behavior was changed to satisfy those assumptions. The capacity hint was also
  corrected before final verification so it does not suggest adding a 65th key.
- Label A/B: 1,000 updates per path in each of paused, forward and reverse
  playback, alternating call order and asserting matching transforms/visibility.
  Each 22-player update now uses 22 indexed lookups instead of 253 name scans.
  Final instrumented Debug median microseconds/update, fallback → indexed:
  paused 112.208 → 93.000; forward 118.270 → 98.959; reverse 116.791 → 97.333.
  These include DEBUG counters/clock overhead and cover only labels, not a whole
  scene, GPU, allocations or device FPS. Attachment exported under
  `/private/tmp/replayxi-cycle162-final-perf/`.
- Final unsigned visionOS device Release succeeded:
  `/private/tmp/replayxi-cycle162-release-final.log`.
- Latest Debug demo installed and launched on the main visionOS27 simulator,
  PID 19853. Launch capture inspected at `/private/tmp/replayxi-cycle162-launched.png`.
  Existing review bytes stayed unchanged before/after tests and normal launch:
  SHA-256 `8011f44456f802b17631b01fe886b14bb609d3ecb14521a5a22b45ae28d0d39e`.

No physical-headset, hand-tracking, comfort or animation-quality improvement is
claimed from this run. This is a focused regression, not a repeat of the entire
1,600-plus-test suite.

The user-owned project/signing and Info.plist edits are excluded from this work.
Tripo has spent 0 credits; new player generation/rigging still needs account
access. No existing player assets or motion clips were replaced in this run.
