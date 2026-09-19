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

- Matched three-repeat mixed workload: `/private/tmp/replayxi-cycle146-mixed-stress.xcresult`: **36 test invocations passed** (12 unique tests), without a process restart. The equivalent pre-change workload crashed. One successful bounded repeat is evidence of improvement, not proof that the intermittent failure is eliminated.

- Full suite: `/private/tmp/replayxi-cycle146-full-02.xcresult`: **1,470 passed, two skipped, zero failed**, 335.8 s. No process restart or unknown-weak-reference warning. The first full-run command had a mistyped simulator ID and was terminated before testing; its unused output remains at `cycle146-full`.
- Unsigned device Release: `/private/tmp/replayxi-cycle146-release.log`: **build passed**.
- Normal simulator app relaunched as PID 70510 and remained alive after 51 s. Dashboard screenshot `/private/tmp/replayxi-cycle146-demo.png` was inspected: the selected volley study, local-only status and replay controls are visible. This is not a hands-on immersive/headset check.
- Saved-review SHA-256 remains `952e501de62f36e391a5b471175c883d0deb9e981a5c6cfc04f607c6dc5ded65`, unchanged from before testing. User project/signing changes and unrelated files remain untouched and uncommitted.
- Implementation backup: `e66d75e`, pushed to `origin/main` before the full run.

This is explicit ownership cleanup with successful bounded stress and full-suite evidence, not proof of a permanent framework crash fix, a frame-rate gain or headset comfort verification. The earlier failing runs remain recorded.

## Next bounded motion probe

Existing run-145 receipt `/private/tmp/replayxi-cycle145-offball-candidate/2C4965C8-B010-4E40-8665-6692C24F737C.json`, zero-based rows 11–14, reports roughly 66° native/far elbow differences for rebound `arg-13` and `arg-19` at 0.3 s. This does not prove either pose is wrong. Before changing the rig, inspect matched near/low/far images and actual LOD switching across 0.25–0.8 s, matching anatomical lanes through `nativeIsLeft`. Separate source phase from bend amplitude and preserve contact, source-leg, root, ball and rewind controls.
