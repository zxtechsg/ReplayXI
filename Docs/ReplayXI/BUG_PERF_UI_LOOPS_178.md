# Three bug, performance and UI passes — 16 October 2026

## 1. Boot and pitch visibility

- Debug demo routes now require `--replayxi-demo` and run once per app session. Old flags cannot silently auto-enter FPV, add marks, or disable saved reviews during a normal launch.
- A fresh visionOS 27 room launch reproduced a compositor crash while decoding the generated FPV neck cap. The retained body's index data was 64,980 bytes, leaving the next part misaligned by 4 bytes. Small zero-area padding triangles now align both generated index streams to 16 bytes. Actual tactical and FPV room launches then succeeded on the same simulator. Original visible triangles, vertices, UVs and rig weights are unchanged and checked by regression tests.
- Room preparation loads the selected scenario, yields between resource groups, shows progress and supports cancellation before the OS starts presenting the room. Cancellation, retries and late completions keep their request ownership.
- Turf stays visible in all match review views. The physical positioning drill keeps its own local markers.
- Initial tactical markings use unlit ivory. The original net material and turf textures remain intact.
- A seated POV can lower the virtual pitch below the room origin. The stadium backdrop floor now moves below it instead of covering the grass. Native before/after renders reproduce and check this failure.
- Review tables capture a level placement in front of the viewer. **Bring pitch here** recovers their placement. Capturing waits for a usable tracked or one-shot head anchor, including while paused. Placement is blocked during annotation and timeline edits.
- Looking straight up/down uses the headset's right axis to retain a usable horizontal heading. Comparison-window entry now has its own loading state and Cancel, even when the dashboard is closed.
- FPV also captures the viewer's room X/Z once per player entry instead of always placing the athlete's eye at room origin. It still does not steer the view from later recorded head motion or live viewer leaning.

Validation: `replayxi178-loop1-fixes.xcresult`, 22/22 passed. Native render tests cover tactical/touchline returns and seated floor occlusion. A fresh dedicated visionOS 27 simulator also cold-started the dashboard. The user's existing simulator was not reset.

## 2. Repeated scene work

- Stable full-squad membership reuses its array instead of rebuilding/sorting it each frame.
- Tripo players no longer allocate hidden procedural near rigs unless a failed skin or active impact needs one.
- FPV only samples weighted head surfaces for visible player tags or authored player labels.
- Constant grounding and unchanged visibility are not rewritten. Hidden neck bridges stop receiving transform writes and restore the current pose on FPV exit.
- Unchanged paused joint arrays are not sent to RealityKit again.

Validation: `replayxi178-loop2.xcresult`, 76/76 passed, including all new launch/lifecycle checks, both body identities, contacts, shirt numbers, FPV restoration, pose seeks and head bounds. The first publication-only A/B test removed 1,056 native array writes over 16 paused full-squad frames; CPU medians remained about 6.1 ms, so it did not establish a large CPU improvement.

## 3. Native controls and final review

- VisionOS controls use their system glass without opaque navy overlays. The dashboard lets its native window material show through. Labels use calmer system typography.
- Mac Coach uses a native collapsible inspector and toolbar, with Liquid Glass on macOS 26 and a material fallback on older supported Macs.
- Pairing remains pending until an authenticated state arrives; cancellation, wrong PINs, timeouts and PIN edits are handled consistently.
- Independent inspector fields merge without losing unsaved height/timing edits. Float wire acknowledgements do not create false conflicts.
- Choosing a drawing tool pauses replay before enabling it. Arc dragging previews live and map targets are larger.
- Exact paused animation inputs can reuse the completed pose. The key includes the full track and every input; changed gaze, actions, keeper state, slow-run/cut admission, time and debug options invalidate it. Diagnostic observers still evaluate poses. Only one checkpoint is retained per instance.

Mac validation: `replayxi178-mac03.xcresult`, 22/22 passed; Release build passed. Actual native windows were checked at 1360×840 and 1060×700 using a PIN-authenticated TCP fixture. This is not a completed manual Mac–Simulator UI pairing.

Final focused visionOS checks:

- `replayxi178-loop3.xcresult`: 58/58, native pitch renders, UI layouts, accessible text sizes, lifecycle, placement, local coach TCP security and exact pose-input invalidation.
- `replayxi178-final-mesh-motion.xcresult`: 35/35, generated mesh alignment, both Tripo identities/details, FPV restore, contact transitions and paused pose reuse.
- `replayxi178-placement-final.xcresult`: 20/20, including vertical-head placement, launch flags and cancellation ownership.
- `replayxi178-pov-final.xcresult`: 27/27, including translated FPV entry, fixed room capture, seeks and view switches.
- `git diff --check`: passed.

The final paused full-squad A/B test measured about **6.18 ms → 0.04 ms** per pose pass, with 352 repeated pose evaluations and 1,056 joint-array writes avoided over 16 frames. This is Debug simulator CPU work for unchanged paused inputs, **not headset FPS or an advancing-playback/GPU benchmark**. Advancing time, changed inputs and diagnostics retain evaluation. Individual asset-provider imports still run synchronously within their preparation stage.

Native launch evidence: `/private/tmp/replayxi178-aligned-room27-loaded.png` and `/private/tmp/replayxi178-aligned-fpv27.png`. The user's existing simulator was not reset. Device Release builds are unsigned compilation checks, not a physical-headset performance test.

Final Debug Simulator and unsigned visionOS Release builds passed after the placement fixes. Mac Release also passed. Normal launch with stale `--replayxi-autostart --replayxi-player-pov` flags, but without `--replayxi-demo`, correctly stayed on the dashboard: `/private/tmp/replayxi178-final-normal27.png`.

Remaining manual validation: actual Mac–Simulator UI pairing and a physical-headset interaction/performance pass. Automated pointer taps produced hover but no reliable activation in Simulator; neither an end-to-end UI pairing nor spatial gesture usability is claimed from those attempts. Existing native renders and model/state/TCP tests are recorded above.

## Launch

Normal launch needs no arguments. For an isolated debug demo, use `--replayxi-demo` followed by the existing scenario flags and `--replayxi-autostart`. A Release build ignores debug routes.

Mac: `.codex-derived/ReplayXICoachMac178/Build/Products/Release/ReplayXICoachMac.app`.

Code backups: `7306694` (Mac), `a838f15` (mesh boot crash), `938e6f1` (paused pose work), `9514345` (entry, pitch, placement and native glass). Existing project/signing/Info.plist edits were preserved and not staged.
