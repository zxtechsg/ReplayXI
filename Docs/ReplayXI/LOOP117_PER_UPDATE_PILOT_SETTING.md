# Loop117 — one pilot-setting read per scene update

## Confirmed repeated work

`ReplayImportedAthleteFeatureGate.isEnabled` reads `ProcessInfo.environment`
and `UserDefaults` on every access. `PitchSceneFactory.update` previously read
it once for low-skin eligibility and once for each admitted skin, before checking
whether that skin was already cached.

Native pre-fix receipt:
`/private/tmp/replayxi-gate117-joystick118-before-01.xcresult` and matching `.log`.
The six `ReplayImportedPilotReadBudgetTests` cases produced four failed cases
with 12 count assertions. All model-policy and resolved-value assertions passed.

| Scene | Reads per update before |
| --- | ---: |
| Near-only Tactical/touchline | 1 |
| Mixed Tactical/touchline | 5 |
| Player POV with low assets prepared | 3 |
| Shape with low assets prepared | 5 |
| Unprepared procedural fallback | 0 |

Changing the stored setting false → true → false produced 5 → 2 → 5 reads.
Low-skin admission followed those values correctly; freshness was not broken.

## Narrow change

The existing two Factory gate sites now share a local, per-update snapshot.
It short-circuits when the skin provider is unprepared, preserving zero reads
for the procedural fallback. Prepared scenes resolve the setting once per call.

This is not a global cache. Environment override precedence, live stored-setting
changes, skin caps, model selection, contact solving and gameplay are unchanged.
The DEBUG-only counter uses a lock-protected Sendable box. Release has no counter.

## Checks and limits

Six focused tests cover warm near-only, mixed Tactical/touchline, POV, Shape,
unprepared fallback, and fresh stored values on consecutive scene calls.
Existing pure override-precedence tests are unchanged.

Post-fix receipt:
`/private/tmp/replayxi-gate117-joystick118-scene119-after-01.xcresult` and matching
`.log`: all six Loop117 tests passed. Prepared views now make exactly one read
per update; unprepared fallback remains at zero. The combined 11-test batch had
10 passes and one unrelated Loop119 render-test failure, not a clean full-suite
receipt.

## Measured Factory CPU work

`/private/tmp/replayxi-gate117-faces116-optimised-01.xcresult` and matching `.log`:
all three scene diagnostics passed with `SWIFT_OPTIMIZATION_LEVEL=-O` and DEBUG
instrumentation retained. Each view measured 138 forward/reverse seeks after
warm-up. No renderer/Blender job ran concurrently with these cases.

Times are milliseconds; p95 uses nearest rank. “Mixed” means one near plus three
low skins in Tactical/touchline. POV retains its existing two-near/no-low cap.

| Assets / view | p50 before → after | p95 before → after |
| --- | ---: | ---: |
| Near-only / Tactical | 0.2976 → 0.2991 | 0.3170 → 0.3276 |
| Near-only / touchline | 0.2978 → 0.3024 | 0.3154 → 0.3210 |
| Near-only / POV | 0.3544 → 0.2707 | 0.4008 → 0.3187 |
| Mixed / Tactical | 0.6567 → 0.3369 | 0.7041 → 0.3642 |
| Mixed / touchline | 0.6647 → 0.3270 | 0.7029 → 0.3590 |
| Mixed / POV | 0.4374 → 0.2729 | 0.4842 → 0.3230 |
| Mixed + static faces / Tactical | — → 0.3254 | — → 0.3582 |
| Mixed + static faces / touchline | — → 0.3300 | — → 0.3581 |
| Mixed + static faces / POV | — → 0.2726 | — → 0.3271 |

Read counts prove less repeated setting work. These sampled CPU timings show
lower mixed-scene update cost, but do not isolate each contributor or prove
that static faces are faster. They exclude initial loading, rendering, GPU,
SwiftUI, input and the compositor. They are not paced playback, FPS, total
memory, cold-start or headset measurements. Full-suite and Release checks remain
pending parent verification.

Exact JSON receipts:

- Before near: `/private/tmp/replayxi-near113-scene-01/DC3138F9-6F94-4141-A0F8-A46FBB5BD3E1.json`.
- Before mixed: `/private/tmp/replayxi-mixed113-scene-01/9A7EFF69-139D-41BC-B5A8-052550FCFFAB.json`.
- After near: `/private/tmp/replayxi-gate117-faces116-cpu-01/9E218D34-4FEE-47B0-8903-7BD3D6515BD7.json`.
- After mixed: `/private/tmp/replayxi-gate117-faces116-cpu-01/CDD4BD57-68CB-45DE-B53C-AB9541969B18.json`.
- After mixed + faces: `/private/tmp/replayxi-gate117-faces116-cpu-01/82405527-4467-49FF-B1BC-5B3B0D23C63C.json`.
