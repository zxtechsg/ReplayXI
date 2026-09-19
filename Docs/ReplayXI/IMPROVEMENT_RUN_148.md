# Run 148 — local player-detail choice

Status: focused checks passed; full-suite native cleanup crashes remain under investigation. Not a stable-build claim.

Run 147 established native visual, safety and CPU evidence for the existing low skinned asset across the squad. This cycle turns that experiment into an optional local setting.

- Balanced remains the default. Unknown saved values fall back to Balanced.
- Full squad keeps near selection unchanged, fills the remaining roster with the low skinned asset, and hides the POV wearer. Missing low assets retain the normal fallback.
- The setting belongs inside Playback Settings, not the main toolbar. A real choice change pauses at the current timestamp. Selecting the already-active choice is a no-op; drawing, timeline scrubbing and geometry edits block a change.
- Only a local preference is stored. Match reviews, annotations, source tracks and ball recordings are unchanged.
- Both the immersive room and the read-only video comparison preview receive the same explicit typed preference. The renderer does not read preferences per player/frame.
- Native tests and the all-five CPU diagnostic must exercise the production argument with the old DEBUG override false. Full suite, device Release, UI snapshots, review hash and Git backup remain required before handoff.

Hardware FPS, thermal behaviour and headset comfort remain unverified; this option is not a FIFA-level fidelity claim. A separate possible next optimization is caching identical paused native pose inputs, but it is not part of this cycle.

## Verification so far

- Focused native/UI/model/policy cohort: **20 passed**, `/private/tmp/replayxi-cycle148-candidate.xcresult`.
- Production-argument CPU/resource diagnostic: **passed all 20 cases** in one test, `/private/tmp/replayxi-cycle148-optimised-cost.xcresult`; DEBUG override asserted false. Same Apple M5 Max / visionOS 27 simulator / optimized Debug setup as run 147, with no concurrent build or renderer benchmark.
- Forward per-case medians: Balanced 0.303–0.382 ms; Full squad 0.430–0.502 ms. Per-case p95: 0.361–1.646 ms versus 0.492–2.115 ms. Full initial population after prewarm: 10.147–11.119 ms; paused expansion: 7.262–8.230 ms. Resource bounds, shared assets, exact trajectories and warm identity checks remain intact. This does not measure headset FPS or GPU time.
- Receipt: `/private/tmp/replayxi-cycle148-cost-captures/0CCAA2F1-7019-4DF9-AFF4-5B105CECF1F0.json`.
- Root reviewed four UI images (regular, AX5, narrow, narrow AX5). Text fits, but white-on-cyan selection contrast was poor. Updated to black-on-cyan selected / white-on-dark unselected, retaining the no-op action guard. Refreshed images must be reviewed from the full run.
- Read-only independent integration review found no actionable regression. Three production scene-update call sites receive the preference. No review schema or physics change.
- New test actor-isolation warnings were corrected before the full run: explicit MainActor preference fixture and the 147 nested RealityKit coordinate helper.

## Full-run findings

- `/private/tmp/replayxi-cycle148-full.xcresult`: **1,491 passed, two skipped, two crashed**, 438.4 s on visionOS 27 build 24M5326f. The failing methods are HeaderHandoff141's actual stage/rewind test and NativeRendererLifecycle142's 12-bake test. These are process crashes, not assertion failures.
- Reports `ReplayXI-2026-09-20-064836.ips` and `064956.ips` match the earlier 054056 crash in the first 27 symbolic frames/offsets and framework UUIDs: invalid weak reference during `PhysicsSimulation` destruction from deferred `RealityRenderer.deinit`. Run 146's detachment is not a complete fix.
- First unknown-weak warning occurs during the header stage-only test, before capture begins. The second occurs during fresh-bake iteration 8. The currently running test does not identify the renderer that corrupted the weak reference. Do not attribute this to the new full-squad choice without evidence.
- All six new UI tests passed in the full run. Root reviewed all four refreshed images in `/private/tmp/replayxi-cycle148-final-ui/`: regular, narrow, AX5 and narrow AX5. Selected black-on-cyan text fits and is readable; no clipping observed in these fixtures.
- Saved-review SHA-256 remains `952e501de62f36e391a5b471175c883d0deb9e981a5c6cfc04f607c6dc5ded65` after the full run.
- Next diagnostic: same binary, bounded mixed workload on installed visionOS 26.5 build 23O470. Created a separate `ReplayXI Native Audit 26.5` simulator (`E0A4415E-98B8-4FC3-B2A8-C140B736E6C2`); no other simulator's data was erased. The first create attempt used an incompatible device type and failed without creating a device; the supported 4K type succeeded.
- Apple's [RealityRenderer reference](https://developer.apple.com/documentation/realitykit/realityrenderer) documents simulation updates and render-completion callbacks, but no explicit scene-destruction completion API. No arbitrary sleep, undocumented fence, physics removal or retained-world pool has been added.
- Unsigned device Release: `/private/tmp/replayxi-cycle148-release.log`, **build passed**.
- Implementation backup `dd04e95` pushed and remote verified. Normal simulator launch PID 77054 remained alive after 30 s; `/private/tmp/replayxi-cycle148-demo.png` shows the local dashboard. The Mac remains locked, so this is not hands-on immersive QA.
- Same-binary six-method mixed cohort, three repetitions: **18 invocations passed on each runtime**. Results: `/private/tmp/replayxi-cycle148-runtime265-mixed-02.xcresult` and `/private/tmp/replayxi-cycle148-runtime27-mixed.xcresult`. No weak warning or restart on either. This bounded negative reproduction does not prove a runtime-specific defect or fix the failed full run. First 26.5 attempt was interrupted before test execution because two selectors used an incorrect class name; corrected selectors are `ReplayCutRunPhase138Tests`.
- Next step is a bounded debugger run, breaking at the first `objc_weak_error` rather than inferring ownership from the later crash stack.
