# Loop 65 — Saved-review feedback

## Issue and fix

A named save could be rejected during an active edit while the saved-review drawer still displayed an earlier **Review saved** message. The disabled Save button also gave no capacity explanation at 40 reviews.

One Store-derived blocking reason now drives save availability, rejection status and the drawer header. It distinguishes an unfinished drawing, timeline scrub, annotation adjustment and the 40-review limit. Read-only libraries keep their specific recovery/version diagnostic. The drawer highlights the warning and provides the same accessibility hint.

This changes feedback only. Cancel stays available. The selected save snapshot is not recaptured. Drafts, gesture ownership, committed marks and saved data are unchanged. Preview masking and normal idle/open-room saves remain in place.

## Validation

- Pre-fix full run: 607 total; 599 passed, 1 optional skip and exactly 7 expected failures (18 assertions), all in the new 8-case save-feedback class. Idle/open-room control passed. Receipt: `/private/tmp/replayxi-parallel64-full-save-repro-01.xcresult`.
- The tests cover draft, scrub, direct handle, joystick, 40-save capacity, read-only diagnostics/unchanged bytes, normal saving and drawer wiring.
- Post-fix source parse and whitespace checks pass. Clean full native suite: **606 passed, 1 optional skip, 0 failed**, including all 8 save-feedback tests. Updated device Release build passed. See [batch verification](VERIFIED_BATCH_58_65_2026-09-17.md).

Drawer wiring is source-checked, not an interactive visual pass. The desktop remains locked. No production save files were read or changed by this audit or its tests.
