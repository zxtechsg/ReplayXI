# Run 150 — texture semantics and native stride calibration

Status: in progress. No production rig or physics change yet.

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
