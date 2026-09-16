# Loop 107 — full-scene CPU baseline

Diagnostic only; no app, asset, admission or cap changes.

`ReplaySceneWorkDiagnosticsTests.testRecordsFullSquadSceneCPUAcrossViewsAndReversePlayback` measures `PitchSceneFactory.update` for the current 22-player Match Replay in Tactical, Touchline and Player POV. Each view gets a fresh scene. Current procedural rigs, admitted skin, pitch and ball are prepared before timing. Three initial updates are also untimed.

Samples cover the full 0–32-second move at half-second intervals plus exact cue timestamps, forwards then backwards. This is sampled seek work, not paced 30 Hz playback. Timing includes track/ball sampling, current far/near articulation, admitted skin updates, annotations/labels, existing diagnostic instrumentation and any ordinary POV-neighbour replacements. Initial scene creation, prewarm, assertions and count walks are excluded.

The JSON attachment `ReplayXI-Scene107-CPUWork.json` reports median, nearest-rank p95 and maximum update time per view. A separate untimed replay records min/max retained and enabled models, material slots, rig counts and shared mesh resources. Enabled counts use hierarchy flags, not camera visibility or renderer draw calls. Player-index reuse, binding reuse, one action sample per player, stable texture preparation and the existing four-skin/two-POV caps are checked without a timing threshold. With no impact cue, actual admission remains one skin in Tactical/Touchline and two in POV; the wearer stays hidden.

Test setup/teardown reset the exposed test-only providers/counters; each view detaches its own graph. Immutable caches without a reset seam are merely prewarmed, so no cold-start timing is claimed. An explicitly enabled legacy imported-player pilot skips this default-admission baseline without changing user settings.

The first optimised run (`/private/tmp/replayxi-render104-scene107-optimised-01.xcresult`) failed the cross-frame mesh-identity check: Tactical retained one observed wrapper identity, Touchline four, POV fifteen. Per-frame model, rig and distinct-mesh counts stayed stable, and all admission/cap checks passed. The original helper kept only `ObjectIdentifier` values, unlike the provider clone-sharing test which holds a strong mesh reference. That result does not establish native resource growth.

The diagnostic now keeps compared `MeshResource` references alive throughout the untimed pass and scopes them to the admitted skin root. Exact joint-model paths/counts and any paths outside that root are attached. The one-shared-skin-mesh assertion is unchanged.

## Corrected optimised Simulator receipt

`/private/tmp/replayxi-render104-scene107-optimised-02.xcresult`: this diagnostic passed; all three cases in the combined bundle passed. Debug configuration used `SWIFT_OPTIMIZATION_LEVEL=-O` on the Mac-hosted visionOS Simulator. Attachment: `/private/tmp/replayxi-scene107-optimised-02/1A8EA3B8-9292-4772-9353-4289C15E48B9.json`.

| View | Updates | Median | p95 | Maximum |
| --- | ---: | ---: | ---: | ---: |
| Tactical | 138 | 0.286 ms | 0.316 ms | 0.366 ms |
| Touchline | 138 | 0.289 ms | 0.316 ms | 0.355 ms |
| Player POV | 138 | 0.340 ms | 0.399 ms | 1.624 ms |

With strong references held, every view reports exactly one shared skin mesh and no joint-model paths outside admitted skins. The whole-scene distinct mesh-resource counts are stable at 199/199/200, not the earlier 86/85/87 address-only counts. The original census allowed wrapper release/address reuse and was not a valid resource count. This corrects the test instrumentation, not the app. Retained model counts remain 495/495/522 and actual skin counts 1/1/2. These public mesh-resource counts are not GPU-buffer or texture-memory measurements.

This test has no renderer, GPU, compositor, SwiftUI/input or headset measurement. It cannot establish FPS or justify a larger live-player budget. Compiler settings and execution hardware must accompany any reported timing receipt.
