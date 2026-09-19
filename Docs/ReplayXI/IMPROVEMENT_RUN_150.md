# Run 150 — texture semantics and native stride calibration

Status: timing fix shipped; cross-runtime texture checks corrected; native slow-run candidate verified only in test. No production rig or physics change yet.

## Cross-runtime texture checks

Run 149's full visionOS 26.5 suite completed without a cleanup crash but failed five Swift texture-wrapper identity checks. Generation counters and pixel checks passed. A fresh-resource probe will compare public equality, independent identical-pixel textures, and replacement/readback through retained material aliases on both runtimes. This must establish the appropriate test contract before changing the failing assertions; it cannot establish private GPU allocation identity.

- Fresh unnamed texture probe passed on both 26.5 (`replayxi-cycle150-texture265.xcresult`) and 27 (`replayxi-cycle150-texture27.xcresult`), using the same compiled binary. Each retained 24 material aliases over original/replaced/restored phases, performed 45 pair comparisons and 54 exact native pixel readbacks. Independent textures with identical pixels stayed distinct and unchanged.
- On 26.5, material getters returned distinct Swift wrappers; on 27, they returned the original wrapper. Public resource equality and replacement/restore aliasing matched on both. This establishes the public test contract, not private GPU allocation identity.
- Corrected only the five failing test methods and the untimed squad texture census to use public equality. Kept load/preparation counts, pixel checks and mesh identity checks. All 25 focused tests passed on both 26.5 (`replayxi-cycle150-texture-fixes265.xcresult`) and 27 (`replayxi-cycle150-texture-fixes27.xcresult`), including the 20-case factory resource census. No unknown-weak warning or process restart occurred in these bounded runs; the earlier intermittent cleanup crash remains unresolved.

## Original running source

- Retrieved only the pinned Microsoft Rocketbox run FBX into `/private/tmp/replayxi-run-calibration150.QRfKEu/`, outside the repository. Source commit: `0943055db6ec570bcef9f2c8b41c9e5467c808f9`.
- Relative source: `Assets/Animations/all_animations_max_motextr_xy/m_run_fast_01.max.fbx`.
- File: 833,040 bytes; SHA-256 `81d096f62465ae038149e7726485133264e4a47d105d236370b00dc18c650526`. Verified before parsing. Trusted Assimp conversion also matches the previously pinned glTF/bin hashes.
- Independent installed Blender FBX parser: 19 keys, 18 intervals, exact duration 0.600 s. Bip01 and MotionExtractionHelper horizontal curves agree. Measured root displacement is approximately `[-0.000000153, 0, 3.503692017]` metres, along +Z; mean speed 5.839486694 m/s. Per-key-interval forward speeds vary from 4.8195 to 7.3523 m/s.
- FBX units are centimetres, +Y up/+Z forward. The existing builder converts to metres and removes horizontal root travel; the runtime therefore lacks this stride calibration. The previous 300–400 cm statement was only a pilot acceptance range, not the measurement above.
- At track speed 2.03 m/s, current cadence is about 1.121 cycles/s. Applying it to this source stride corresponds to about 3.9291 m/s; matching forward stride would require a ratio near 0.5167. Such a large adjustment needs visual and anatomical validation, and perhaps a more suitable jog clip. No simple ratio is being shipped without testing.

## Moving native evidence

An independent test will capture Argentina 13/19 at near/low detail with fixed cameras, a fixed pitch frame and non-colliding ground references. Actual actor travel and joint poses must remain unchanged. Source support indicators are not measured ground-contact labels. Prefer one renderer per sequence with awaited completion and explicit release, rather than one renderer per frame.

- `/private/tmp/replayxi-cycle150-moving-baseline.xcresult`: passed on 27. Four sequences, 136 native 512×512 PNG frames at 60 Hz, 20,740,902 PNG bytes. One awaited renderer per sequence with explicit cleanup; exact actor/ball/joint non-advancement, near/low admission, frozen boot anchors, bounded framing and reverse sampling all passed.
- Captures: `/private/tmp/replayxi-cycle150-moving-captures/`; manifest `F4966C6C-9C5C-4488-9261-DACC3C1786E8.json`. Root inspected six original near-detail support-window frames for players 13/19. The knees still rise like a fast run at this slower travel speed; still frames alone do not prove contact/sliding or headset quality.

## Slower source candidate

- Downloaded only two additional animation-data files from the same pinned Rocketbox commit, outside the repo. Verified pinned byte sizes and Git blob hashes before import; independently checked original FBX curves with installed Blender's parser against Assimp exports.
- `m_run_slow_01.max.fbx`: 877,200 bytes, SHA-256 `56af7ac64b05653d40f64205b58b2bf915646ee70dd6e2a68bc4536d71f07c1c`. Measured 1.848146057 m/cycle over 23/30 s. At existing 2.03 m/s track cadence, the required average stride ratio is 0.97947, versus fast's 0.51666.
- `m_run_neutral_01.max.fbx`: 868,752 bytes, SHA-256 `5a22052ea750805ea7e097310f36cd448c838e7c88bc842a78632d9606869fa8`. Measured 2.111797943 m/cycle over 22/30 s; ratio 0.85719.
- All 80 required source joints, nearest weighted parents and TRS channels match. Slow's maximum weighted local endpoint rotation difference is approximately 0.000058°. These are source compatibility checks, not a native visual fix.
- Detailed source report retained at `/private/tmp/replayxi-run-comparison150.OqHjSn/COMPARISON.md`. A test-only slow-source extraction and phase comparison is next. Do not reuse fast-specific footfall/cut assumptions or change protected contact clips without validation.

- Reproducible, offline probe: `Scripts/build_replayxi_slow_run_probe.py`. It verifies both original FBXs, glTF/bin exports and the current motion hash, reconstructs the complete fast clip exactly, then replaces only the run in the test fixture. All other fields (80-joint rest/order, idle, geometry and contact data) stay unchanged. No app asset is changed.
- Test fixture: `ReplayXITests/Fixtures/Generated/ReplayXIRocketboxSlowRun150.json`, 829,689 bytes, SHA-256 `81633d787043a30cff0b86ef5272542522d619b7bc9186c7105d75a489bf3062`. Derived Microsoft Rocketbox animation; the retained MIT notice is `ReplayXI/Resources/Players/LICENSE-ROCKETBOX-MIT.txt`. Slow FBX source is `Assets/Animations/all_animations_max_motextr_xy/m_run_slow_01.max.fbx` at the pinned commit above.
- A 360-phase × 360-offset local-quaternion comparison gives a balanced legs/arms/torso minimum at −5°: 18.410° RMS versus unshifted 18.471°. Regional minima differ (legs −3°, arms −19°, torso +6°); the small gain is not a uniquely correct alignment. Use unshifted slow first, retaining the original source frames. No force/contact labels follow from this pose comparison.

## Annotation timing boundary fix

- Reproduced valid decimal-window rejection: `8.2 - 7.7` is slightly below 0.5, while `35.7 - 5.7` is slightly above 30. The draft, both commit routes and final saved-mark validation previously used strict duration comparisons.
- Shared min/max checks now admit only subtraction-scale roundoff (two operand ULPs). Typed timestamps are not rounded or shifted. Existing clip-end tolerance and strict direct-duration input are unchanged; older saved short/off-clip windows remain readable.
- Four new tests cover draft/store agreement, 1 µs outside-bound rejection, exact keyframes/geometry, JSON/autosave and one-step Undo/Redo through direct and session commits. All **45 focused timing tests passed** on visionOS 27: `/private/tmp/replayxi-cycle150-timing-02.xcresult`. The first build was cancelled by an actor-isolation error in the separate, unfinished motion A/B test helper; making its pure distance helper nonisolated resolved compilation. No timing tests ran in that cancelled attempt.
- Root independently regenerated the slow fixture with the checked-in builder into `/private/tmp/replayxi-slow-probe-root150.CarCpl/slow-run.json`; byte count and SHA matched exactly. Native A/B is still pending; no new run animation has shipped.

## Native slow/fast A/B result

- `/private/tmp/replayxi-cycle150-slow-ab.xcresult`: **passed**, 11.5 s. Two separate native actors copy the actual factory actor's transform; the fast standalone joints and fixed boot patch exactly equal the actual factory oracle at every frame. Eight cases × 67 frames at 120 Hz, exact reverse poses/points, fixed bones, floor bounds, unchanged ball/routes/peers and zero fast-specific cut admission all passed.
- 24 original 512×512 native PNGs, 3,639,229 bytes, shared fixed cameras/lights/grid; not interpolated/generated images. Receipt: `/private/tmp/replayxi-cycle150-slow-ab-captures/BB0831B0-934A-47CD-B16E-0AEA0F3B7229.json`. Root reviewed ten near images; independent review includes every low-detail image. The slow source gives a more upright, smaller-stride jog at this pace.
- In the previously frozen comparison windows, maximum fixed-point paths within 20 mm of the pitch change from about **126→42 mm** (Argentina 13) and **216→92 mm** (19); near/low agree closely. Maxima can select different vertices, and neither window is measured slow-source support/contact.
- Across the entire 0.25–0.8 s window, 20 mm maxima improve less: near **211→182 mm** (13), **351→292 mm** (19). At 40 mm, maxima instead increase **270→337 mm** and **409→452 mm**, with different/longer low-height intervals. This is not universal sliding reduction or proof of a planted foot. Preserve these contrary observations when judging the candidate.
- Maximum observed joint step (toe) at 120 Hz changes **7.05→4.66°** and **7.09→4.64°**. These are normalized-quaternion step measurements, not a proof of continuity or a hardware comfort result. Speed transitions, contacts, keepers and the rest of the demos remain untested with the slow source; it is still test-only.
- Additional unchanged-binary timing checks on visionOS 26.5: **18 passed** (`replayxi-cycle150-timing265.xcresult`). These model tests did not compile or read changing Swift source. Saved user reviews remain byte-identical; normal updated demo PID 81993 was alive before the full-suite run.
- Full visionOS 27 suite ran with all Swift frozen. LLDB attached only to verified simulator test-host PID 82626 to stop at the first `objc_weak_error`, capture stacks, then detach/resume. This was a diagnostic run, not a timing benchmark. No cleanup-fix claim follows from a negative reproduction.

## Final validation

- Full 27 diagnostic suite: **1,501 passed, two intentional skips, zero failures**, 1,503 total, approximately 454 s. `/private/tmp/replayxi-cycle150-full27-provenance.xcresult`. No unknown-weak warning, crash or runner restart. Native asset-manager cleanup warnings still occurred; they are not asserted to cause the earlier crash.
- LLDB resolved `objc_weak_error` but did not hit it. The test app exited normally (status 0); the queued backtrace then failed because no stopped process remained, so LLDB returned 1. This is another negative reproduction, not a captured fault or a fix. Log: `/private/tmp/replayxi-cycle150-first-weak-lldb.log`.
- Unsigned visionOS device Release build passed: `/private/tmp/replayxi-cycle150-release.log`. Only the existing unused AppIntents metadata warning. Test-only slow-run data is absent from the Release app.
- Normal latest simulator demo relaunched as PID 83399 and verified alive. Saved reviews still match SHA-256 `952e501de62f36e391a5b471175c883d0deb9e981a5c6cfc04f607c6dc5ded65`. Mac remains locked; no fresh hands-on gesture or headset-performance claim.
- Verified remote backups: `fad1e0c` (texture semantics/native baseline), `902fda9` (timing fix/source fixture), `70c26a8` (native A/B). User project/signing edits and unrelated work remain excluded. The broad improvement goal stays active; next candidate scope is in `IMPROVEMENT_RUN_151.md`.
