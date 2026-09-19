# Run 147 — whole-squad visual consistency

Status: verified DEBUG-only candidate and evidence checkpoint. The live four-skin / two-near-POV budget is unchanged.

## Measured baseline

- Rebound demo `final-108-rebound-v2`, Argentina 13 and 19, native ball recording.
- Actual submitted near, low and articulated-far arms were sampled at 120 Hz, 0.25–0.80 s. All 268 skin samples passed rewind, floor and ball controls. Two focused tests passed in `/private/tmp/replayxi-cycle147-baseline.xcresult`.
- Near/low arm bends match; endpoint difference is at most 1.35 mm from floor offset. Far differs by up to 72.91° in bend and 0.517 m in shoulder-relative wrist position. At 0.3 s the folded arm is about 98° near versus 32° far. The final floor/look stages do not explain this gap.
- Twelve matched native-renderer stills (two actors × three LODs × two views) were reviewed. The lower-detail skinned model preserves the detailed player's silhouette and kit. The articulated far model looks visibly stiffer and changes both body silhouette and gait pose. This is not evidence of a temporal snap in the native animation.
- A separate production scene test passed two cases in `/private/tmp/replayxi-cycle147-scene-baseline.xcresult`: wearer changes at 0.3 s, and two fixed wearers across the full seven seconds at 60 Hz. Argentina 13/19 stay near throughout for wearer 23 and far throughout for wearer 10. Wearer 10 has two other near-admission changes. Thus the forced comparison does not establish a naturally occurring LOD switch for these two target actors in this sequence.
- Current POV admission goes directly between near and far; it does not use the existing low skin. Near admission is based on neighbour ranking and hysteresis, not head gaze or the unused distance-based LOD helper.

## Candidate

`PitchSceneFactory.fullSquadSkinsForTesting` is false by default and absent in Release. When explicitly enabled in tests, it permits the existing low skinned asset for the remaining squad while leaving near selection unchanged. Table: normally one near + 21 low. POV: two near + 19 low, with the wearer hidden.

The low asset has 1,707 vertices, 2,129 triangles and the same 80-bone pose pipeline. It reuses prepared textures. This alone does not establish acceptable frame cost. Required checks: actual scene CPU/resource cost, matched group POV captures, body exclusivity, wearer switching, fallback, contact/floor preservation and exact rewind. Do not flatten the better native animation to match the inferior far fallback.

No hardware FPS, motion-capture accuracy or headset-comfort claim. Mac lock currently prevents hands-on UI testing; native offscreen captures remain available.

## Validation in progress

First candidate run: eight admission-policy tests passed; the new group-image test stopped at the test helper's 512-pixel maximum when requesting 1024 pixels. This was a fixture limit, not an unavailable Metal device. The helper now allows a bounded 1024×1024 colour target (4 MiB) and reports invalid dimensions separately from a missing device. Rerun required. Result: `/private/tmp/replayxi-cycle147-candidate-visual.xcresult`.

The corrected candidate suite passed 13 tests in `/private/tmp/replayxi-cycle147-candidate-safety.xcresult`: eight policies, four safety cases and one four-image group comparison. Safety covers body exclusivity, hidden wearer, mode/quality transitions, failure memoisation and recovery, authored impact promotion, real rebound shots/save, floor and exact rewind. The group captures exposed fixture weaknesses (cropped attacker, dim reverse view, missing pitch/ball prewarm); camera framing, fill and asset preparation are being corrected before visual acceptance.

Actual rebound remote-low shot boot-to-strike-target gaps are approximately 5 mm (near 6 mm), with 6 mm floor clearance. Save wrist-to-ball-centre distance is 152.003 mm low / 152.877 mm near; this is not hand-surface contact error. Low-oracle transforms match exactly. The original quaternion-angle receipt amplified floating-point roundoff; the metric is being corrected to a relative-quaternion atan2 measure.

The first optimized five-demo CPU/resource run completed all cases but failed one whole-state equality check after repeated quality switches. Do not treat it as a passed benchmark. Concise membership-versus-pose diagnostics now replace its unwieldy whole-scene failure dump. Hardware: Apple M5 Max, Mac17,6, 128 GiB; visionOS 27 simulator, SDK 26.5; Debug with `SWIFT_OPTIMIZATION_LEVEL=-O`, testability and DEBUG diagnostics enabled. Initial allocation and paused quality-switch costs are recorded separately from warm updates. Weak instance references avoid both extending retired lifetimes and mistaking recycled addresses for unchanged players.

The diagnostic rerun isolated that failure to volley/table at 7.358333 s: the original three low slots retain Argentina 7 through hysteresis; expanding to the squad then shrinking selects closer Argentina 24 instead. France 10 stays near, the other low players stay unchanged, all common visible poses and trajectories remain exact, and full-squad returns match completely. This is an unequal admission-history fixture, not a demonstrated animation defect. Normalize both switch cases through the same untimed full-squad membership before comparing repeated states; retain strict pose/key assertions and add an explicit cap-shrink policy regression.

## Accepted optimized cost run

`/private/tmp/replayxi-cycle147-optimised-cost-03.xcresult`: **10 passed**, including nine policy tests and the 20-case native-squad diagnostic. Its receipt is `/private/tmp/replayxi-cycle147-cost-03-captures/8D91E673-84A9-44C9-A43E-21ADD0BC9ADD.json`. No concurrent build or renderer benchmark ran during this measurement.

| Actual factory work, across five demos × table/POV | Current | Full squad |
| --- | ---: | ---: |
| Forward-update median per case | 0.301–0.369 ms | 0.404–0.489 ms |
| Forward-update p95 per case | 0.327–1.572 ms | 0.485–2.052 ms |
| Initial population, assets already prepared | 2.978–9.100 ms | 9.801–10.785 ms |
| Enabled models, table | 172 | 100 |
| Enabled material slots, table | 179 | 125 |
| Enabled models, POV | 162–165 | 86–89 |
| Enabled material slots, POV | 167–170 | 110–113 |

Paused expansion to the full squad takes 7.147–8.132 ms in these samples. Retained entities increase from 942 to 1,086 in table view, or 968 to 1,120 in POV; dormant fallback rigs remain allocated. Near/low mesh resources are shared. Repeated same-time updates create no new low clones and preserve identities/resources/poses exactly. All native trajectories, recorded contacts and rewind controls pass.

These measurements support testing an **optional** full-squad visual setting, not a hardware FPS guarantee or a new default. The intended next implementation is a local, explicit Balanced / Full squad choice inside Settings, with playback paused while switching. It must not alter reviews, annotation timing, near selection or fallbacks. Target-headset CPU/GPU, memory and thermal testing remains open.

## Final checks

- Native regression cohort: **38 passed**, `/private/tmp/replayxi-cycle147-final-cohort.xcresult`; includes old low-detail admission/runtime/contact coverage plus new safety, arm and actual-scene probes.
- Root reviewed the final four 1024 px group captures in `/private/tmp/replayxi-cycle147-final-captures/`. Actual pitch/ball assets are present, both target bodies fit, and both teams are readable. Full-squad skins improve kit/number visibility and body/arm consistency versus the far fallback. These are still images, not a claim of FIFA-level motion fidelity.
- Optimized cost/policy cohort: **10 passed**, as above. Do not add this to 38 as a unique-test count; policy coverage overlaps.
- Unsigned device Release build passed: `/private/tmp/replayxi-cycle147-release.log`. The experiment flag is absent from Release. No full-suite rerun in this evidence-only cycle; run it when integrating the user-facing option.
- Saved review SHA-256 remains `952e501de62f36e391a5b471175c883d0deb9e981a5c6cfc04f607c6dc5ded65`.
- No live quality/default change, asset replacement, physics trajectory change, UI option or annotation migration is shipped by this checkpoint. Those claims require the next integration step.
