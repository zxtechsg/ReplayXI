# Loop 118 — joystick versus direct-handle ownership

With a coach mark's Adjust shelf open, a direct 3D endpoint drag owns geometry but has no joystick owner. The existing joystick helper treats that missing owner as permission, leaving both joysticks enabled. Store correctly rejects their previews. This is an affordance mismatch, not evidence of committed data loss.

The narrow fix changes only the helper's no-joystick-owner branch: allow input only when no geometry preview is active. Its matching joystick owner stays usable; a blanket `canChangePlaybackView` gate would incorrectly disable that owner after its first sample.

Pre-fix receipt: `/private/tmp/replayxi-gate117-joystick118-before-01.xcresult`. The helper UI-wiring case failed on its expected assertion; all three real Store controls passed. Those four cases cover direct/joystick/timeline ownership, normal entry, commit/cancel, rejected callbacks and Undo. Source checking is not a simulated UI gesture.

All four post-fix cases pass in `/private/tmp/replayxi-gate117-joystick118-scene119-after-01.xcresult` (10 cases passed overall; one unrelated scene-render case failed). The helper fix is syntax-checked.

Full integration passed in `/private/tmp/replayxi-parallel115-120-full-01.xcresult`: 914 total, 913 passed, 1 optional skipped, 0 failed. Unsigned device Release passed; see [batch receipts](VERIFIED_BATCH_115_120_2026-09-17.md). No Store, rail, cancellation or sizing changes; no interactive/headset QA is claimed.
