# Run 155 — steep 3D arcs

Status: final unsigned device Release build and full visionOS26.5 Debug regression passed: 1,574 passed, two intentional skips, zero failed.

## Scope

- Give newly drawn arcs a stable pitch-space bend direction. Keep a true 3D roll axis and permit raised/vertical endpoint spans of at least 0.8 m.
- Preserve exact legacy geometry until an accepted edit. Cancel and Undo must restore the original curve fields, including absent direction data.
- Timestamp poses interpolate the new bend direction deterministically. Reject new/mixed intervals whose interpolated endpoints collapse; do not invent a hidden path. Old all-legacy intervals stay readable.
- Store framed arcs with a versioned review document so older readers cannot silently misrender them. Retain atomic writes, backup recovery and newer-version read-only protection.
- Native mesh, arrow, selection and rewind checks supplement domain/transaction/persistence tests. Simulator checks are not headset comfort or hardware FPS evidence.

## Previous checkpoint

Run154 is committed and pushed as `cf9670f42106b1b8d6b8239c1b621a2ebeaacb95`. Its normal app launched on the main visionOS27 simulator, PID93667. Static screenshot `/private/tmp/replayxi-cycle154-launched.png` shows the restored local Strategy Analysis review. User review SHA-256 before/after install remains `952e501de62f36e391a5b471175c883d0deb9e981a5c6cfc04f607c6dc5ded65`.

The Mac is locked, so no interactive window, hand gesture or headset verification is claimed. The existing full152 cleanup crash is still unresolved; run154's clean full suite and two negative debugger probes do not prove a fix.

## Review and first build

- Read-only review found legacy tracked arcs with no explicit curve resolve their visible default bend from current player positions, not stored fallback endpoints. Editing and no-op checks must use that visible default. A related origin-return curve commit must also use the same effective curve to avoid accidentally changing a cancelled gesture.
- Simulator app build passed: `/private/tmp/replayxi-cycle155-appbuild.log`. Device Release builds passed in `cycle155-release.log` and `cycle155-release-final.log`; these precede the final origin-return correction and are not final validation of it.
- The first focused test attempt `/private/tmp/replayxi-cycle155-focused26.xcresult` did not execute tests: Swift exceeded its type-checking limit for a new test's long vector expression. Split the reference formula into explicit scalar weights. Production code was not implicated; retain the failed build record.

## Focused test evidence

`/private/tmp/replayxi-cycle155-focused-fixed26.xcresult`: 191 passed / one failed across 29 suites. Native tube centre-lines (independent Rodrigues rotation), curved hit volumes, arrow direction, selection rail/core, key seek/rewind and paused mesh reuse passed. Legacy sampling, framed interpolation, interval safety, versioned disk encoding/cache/recovery and preview/commit/Undo checks passed.

The only failure compares the saved Float direction `90.00001` to literal `90` in three editing routes within one test. Keep the exact pre-move captured-direction comparison and separately verify 90° within 0.00002°. This test-only correction does not loosen the spatial centre-line, ownership or Undo checks. Full rebuild/regression: `/private/tmp/replayxi-cycle155-full26.xcresult`; final device log: `/private/tmp/replayxi-cycle155-release-verified.log`.

Native SwiftUI captures were inspected at default and largest accessibility text sizes, plus the full-key-capacity disabled state. Labels and ± controls are legible without overlap or clipping. Files under `/private/tmp/replayxi-cycle155-focused-captures`: `DE5103CD-D901-4FA0-A902-22F3243C9126.png`, `FDB2A009-3D22-457E-98FE-B6391F0403F4.png`, `E4228477-F1E0-4D23-ADC5-30190D423521.png`. These isolated pad renders do not validate immersive reach, hand tracking or headset comfort.

Final evidence: `/private/tmp/replayxi-cycle155-full26.xcresult` passed all 1,574 executed tests, including the corrected exact-basis/approximate-angle test and both nil-curve tracked origin-return modes. Two existing tests intentionally skip. `/private/tmp/replayxi-cycle155-release-verified.log` passed after the final production correction. No new motion-fidelity or FPS claim; this cycle changes arc capability, controls and safe persistence. The intermittent full152 cleanup failure remains unresolved.
