# Loop 105 — skin-update CPU scaling

Purpose: a lighter mesh alone does not remove the cost of the existing 80-bone animation/contact path. Measure that work before considering a wider skin budget. This is diagnostic-only; the shipping near cap stays four, or two in Player POV.

`ReplaySkinnedAthleteWorkDiagnosticsTests` prepares the existing admitted skin, then measures 64 forward/reverse frame updates at one, four and 22 instances. The first four tracks are the active home/away wingers and full-backs; the full squad uses the same authored sequence. Track/ball sampling, assertions, creation and warm-up are outside the timed interval. `Instance.update` includes football retargeting, head look, hierarchy rebuilding, 339 weighted contact vertices / 603 influences and native joint writes. Resources stay shared and the final joint transforms stay finite.

## Initial Debug Simulator receipt

`/private/tmp/replayxi-skin105-cost-01.xcresult`: one test passed.

Actual attachment: `/private/tmp/replayxi-skin105-cost-01/16002ED3-15BD-4EF9-8015-A153AD205CD9.json`.

| Existing skins | Median group update | p95 | Maximum |
| --- | ---: | ---: | ---: |
| 1 | 0.240 ms | 0.304 ms | 0.314 ms |
| 4 | 0.855 ms | 0.985 ms | 1.062 ms |
| 22 | 4.886 ms | 5.296 ms | 5.350 ms |

Cold prewarm in this run was 540 ms. Instance-creation timings are also attached but include order-dependent cache warm-up and are not compared as cold-start benchmarks. No Blender render was active during this run.

These are unoptimised Debug timings on the Mac-hosted Simulator, not a headset frame budget or FPS. They exclude scene traversal, renderer/GPU/compositor work, input and track sampling. Different group sizes contain different player motion; this is the actual mixed squad, not an identical-work scaling law. There is no brittle timing threshold in the regression test.

## Compiler-optimised Simulator receipt

`/private/tmp/replayxi-render104-skin105-optimised-01.xcresult`: the CPU diagnostic passed. The separate RealityRenderer calibration in the same bundle failed; this is not an overall passing test bundle or visual receipt.

Actual CPU attachment: `/private/tmp/replayxi-skin105-optimised-01/A0591682-83E9-4976-AF68-E9FA2825334B.json`.

| Existing skins | Median group update | p95 | Maximum |
| --- | ---: | ---: | ---: |
| 1 | 0.0083 ms | 0.0116 ms | 0.0167 ms |
| 4 | 0.0313 ms | 0.0393 ms | 0.0452 ms |
| 22 | 0.1699 ms | 0.1925 ms | 0.1979 ms |

This used a separate `.codex-derived/ReplayXI-Optimised105` build with `SWIFT_OPTIMIZATION_LEVEL=-O`, `ENABLE_TESTABILITY=YES` and `DEBUG` compilation conditions retained. The attachment's generic “Debug Simulator CPU” scope remains true but does not encode the compiler flag; the command receipt does. This is not a shipping Release or physical-device result. No Blender render was active. Prewarm was 780 ms after the separate offscreen renderer diagnostic; it is not an isolated cold-start comparison.

The optimised result shows that unoptimised Debug timings greatly overstate this particular CPU cost. It still does not measure full-scene, skinning/rendering or headset cost, and it does not authorise a new live cap. Physical-device qualification remains open; the app limits are unchanged.
