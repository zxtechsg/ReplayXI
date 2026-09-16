# Loop 63 — Cheap decision-button availability

The Tools shelf built a complete decision snapshot just to check whether its
Decisions button should be enabled. That included scan history, passing options,
defender spacing, replay outcomes and presentation poses that were then discarded.

The button now uses a small eligibility check: finite time, valid duration and an
existing player. This shares the time validation used by the full snapshot and
does not calculate tactical analysis. Opening Decisions still builds the same
snapshot; no metric, ranking, time clamp or interaction barrier changed.

Three tests cover parity with actual snapshot availability for every bundled
player at five time boundaries, non-finite/missing-player rejection, and the UI
call site. All three passed as part of the **56-test** combined run:
`/private/tmp/replayxi-parallel62-fixed-01.xcresult`.

This removes a known unused calculation. No headset frame-rate improvement or
hardware performance measurement is claimed. Full native suite: **606 passed,
1 optional skip, 0 failed**. Device Release build passed. See
[batch verification](VERIFIED_BATCH_58_65_2026-09-17.md).
