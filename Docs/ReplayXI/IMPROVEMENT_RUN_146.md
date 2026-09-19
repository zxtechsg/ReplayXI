# Improvement run 146 — native cleanup and annotation move guidance

## Baseline investigation

Run 145's full suite and smaller repeated cohort both crashed during asynchronous RealityRenderer destruction. The latest crash reports (`053223` and `054056`, 20 September 2026) have the same leading 27 symbolic frames and offsets as the earlier reports: CoreRE physics-scene cleanup reaches an invalid Objective-C weak reference. The current tests' source locations do not identify which renderer is being destroyed.

Two separate old-binary baselines used `test-without-building`, so candidate source edits cannot affect their results:

- `/private/tmp/replayxi-cycle146-physics-only-baseline.xcresult`: three invocations of the 12-bake/stage-only lifecycle test passed (36 fresh bakes, no capture renderers).
- `/private/tmp/replayxi-cycle146-visual-only-baseline.xcresult`: three repetitions of three pure-visual methods passed (nine invocations, no native match bakes).

Neither proves the crash is fixed or exclusively caused by mixing the paths. Both are bounded negative reproductions; the mixed reduced baseline did crash.

## Implementation

- Explicitly detach completed native worlds while their owning Swift object still holds the renderer and entity graph. Cover normal completion, cancellation and thrown errors in both main bakes and aim previews. Do not add solver ticks, delays, scene-component stripping or retained-world pools.
- Explain when annotation MOVE is blocked by a saved position key leaving the replay, rather than wrongly suggesting that shortening In/Out can fix it. Preserve timing math, button dimensions and persistence behavior.

The native calls register `defer { world.finish() }` immediately after constructing each main/aim world. `finish()` only removes renderer roots; it is idempotent and leaves the still-owned hierarchy/components intact. Debug-only hooks allow comparison with the previous release order and injection of start errors. Device Release excludes those hooks.

MOVE now uses one block-reason policy for enablement, help and accessibility. Its existing hint slot says `CHECK KEYS` for out-of-range position keys. Other guidance distinguishes a held gesture, invalid timestamp, unchanged time and visibility-window fit. No new panel, button size, timing threshold or persistence mutation was added.

## Candidate evidence

- `/private/tmp/replayxi-cycle146-candidate.xcresult`: **13 passed, one failed**. All six physics/lifecycle methods passed. The new annotation fixture had automatically attached its start to a player, so it could not record independent position keys; that setup error produced the failure and is being corrected without changing production behavior.
- All five detached recordings exactly match the legacy release-order controls: **6,125 samples, 27 contacts, zero missed touches**. Comparisons include sample times, position, orientation, linear/angular velocity and every touch field.
- Each side constructed 65 main/preview worlds. Candidate worlds finished with zero renderer roots and detached root/ball scenes; all observed Swift world/renderer references were released. Numeric receipts: `/private/tmp/replayxi-cycle146-detachment-captures/`.
- Direct repeated detachment preserves the live sample, children and physics components. Cancellation leaves no cache entry. Injected primary and preview start failures propagate and detach all constructed worlds.

- Corrected focused run: `/private/tmp/replayxi-cycle146-candidate-02.xcresult`: **14 passed**. The annotation test now unlinks player tracking through the real command before recording keys and stops early if setup fails. It verifies that shortening the window does not unblock an out-of-bounds key, retiming that key does, and Undo restores the exact pre-move mark.

Mixed stress, full suite, device Release and demo relaunch pending. This is explicit ownership cleanup, not proof of a framework crash fix, a frame-rate gain or headset comfort verification.
