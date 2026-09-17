# Five-study Blender authoring workflow

The new workflow accepts short native app studies, not the older pending 60-second
video pipeline. It does **not** recover a complete match or captured limb motion
from broadcast video.

## Inputs

- A native XCTest export: `schemaVersion: 1`, `studies` array, pitch metres.
- All 22 named/shirt-numbered players per study with exact app root paths/facing.
- Actual recorded RealityKit ball samples and admitted contact times.
- Explicit evidence: authored/inferred/observed/measured, visibility, nullable confidence.
- Optional native actor rig samples: 80 local USD Y-up joints. The normal export
  uses 10 Hz plus exact contacts for contact actors; the opt-in single-study
  export below uses 20 Hz for all 22. Neither is match mocap.
- Existing Microsoft Rocketbox MIT skin and original Replay XI pitch/ball USDZs.

Never fill unknown confidence with a guessed number. Unknown/off-camera paths
remain visibly labelled. A reference URL is a citation, not a claim that video
was downloaded or geometrically reconstructed.

## Run

1. Export the app studies to a new JSON artifact.
2. Run `Scripts/blender/build_reference_studies.py` with `--manifest`,
   `--steps-output` and `--blend-output` pointing at new files/folders under
   `.codex-derived` or outside the repo. `--validate-only` needs no Blender.
3. Send each generated Python step, in `steps.json` order, directly as Blender
   MCP code. Do not wrap it in `exec`, disable safe mode, or load external `.blend`
   libraries. USD import/render/save operators are allowed by the installed addon.
4. Check each built scene, player/ball positions and native contact poses before
   using the Blender artifact as a visual reference.
5. The final step saves a **new copy**. Existing scenes and the current file path
   are retained. Choose a new output name for every run.

`--exclude-study ID` can stage a verified subset while another study is revised.
`--shared-assets-loaded` first checks the existing template/data/actions, then
reuses them without reimporting. Each study gets separate embedded data, so a
later verified study can be appended without overwriting another scene. The
scene retains the SHA-256 of its exact original native export.

## Optional all-player native export — Reference 129

This export path is implemented, but **no new native export, Blender build or
visual verification is recorded here yet**. The verified Reference 127 artifact
below is a different receipt and retains the original `final-81-volley` scene.

Run the XCTest
`ReplayXITests/ReplayReferenceBlenderExportTests/testExportFivePlayableReferenceStudies`
with these variables in the **XCTest host's environment** (the scheme's test
environment or a separate `.xctestrun` configuration):

| Variable | Example |
|---|---|
| `REPLAYXI_EXPORT_STUDY` | `final-81-volley-v2` |
| `REPLAYXI_EXPORT_ALL_RIGS` | `1` |

Setting only the build command's shell environment is not proof those variables
reach the test host. Check that the resulting attachment contains one selected
study and `rigSampling.scope` is `all-players`. All-rig export requires a selected
current study; unknown IDs fail. With neither variable, the normal five-study,
10 Hz contact-actor export remains the default.

The opt-in attachment is named
`ReplayXI-final-81-volley-v2-All-Native-Rigs.json`. It includes:

- All 22 players' native **near-rig** poses at 20 Hz plus exact recorded contacts.
- The native tactical-attention calculation, nearest-contact selection and its
  shared preparation margins, not a separate illustrative background gait.
- Root/facing samples at every exported rig instant as well as the 30 Hz root
  grid, so a 20 Hz bone pose cannot be paired with an interpolated, different root.
- Header support-leg metadata where authored. Source visibility/confidence remain
  unknown unless actually established; these poses are not recovered from video.
- `float32-vector-table-v1`: repeated transform vectors share table entries;
  each float is stored as its original eight-digit IEEE Float32 hex word. The
  decoder uses bounded numeric operations. No rounding, executable payload,
  quaternion sign change or pose quantization is introduced. Times/root tracks
  retain their existing numeric representation. Legacy numeric pose arrays still
  work, and the manifest reader's **40 MB cap remains unchanged**.

Use a new steps folder and `.blend` filename. The new `final-81-volley-v2` ID can
coexist with the previously built original scene; the workflow refuses to
overwrite an existing same-ID scene or embedded data. With templates already
loaded, `--shared-assets-loaded` retains the existing asset checks.

`steps.json` now reports metadata bytes, step count and native pose-frame count.
The verifier evaluates shared pose timestamps once for the whole squad, then
checks each rig's matrices. Verify the actual artifact size and mapping receipt
after export; an estimate is not a completed build.

Current offline parser/decoder tests: **27 passed**, including exact Float32
round-trip, signed zero/subnormals, malformed indices/hex, contact/root coverage
and the original size cap. These Python tests do not execute Blender or prove
that the new Swift export has run.

All-22 near-rig posing is an **offline authoring option**. It does not change the
app's runtime LOD limits, establish headset frame rate, prove natural animation,
or demonstrate match-specific mocap accuracy. Native app integration and visual
review remain separate checks.

## Scene controls

- One scene per study; source/evidence in scene custom properties and embedded JSON.
- Review and tactical cameras plus 22 player POV cameras.
- POV cameras follow player translation, with unkeyed orientation for free look.
- Timeline markers identify contact times and shirt numbers.
- Optional route collection, hidden by default, includes evidence on each route.
- Optional contact rings are hidden by default; actual ball/skin contact stays
  visible without a diagnostic ring covering the boot or head.
- Players use native rig samples when provided. In the normal export, remaining
  players share illustrative distance-timed idle/run actions. An all-player
  export requires all 22 native rigs and cannot silently use that fallback.
- Ball translation and rotation are imported from the native physics recording, not resimulated
  or steered toward feet in Blender.

Native `(x,y,z)` maps to Blender `(-x,z,y)`. This is a right-handed rotation, not a
reflection, so body heading and local rig poses remain consistent. Scene units
are metres; player roots and ball path are not artist-scaled.

## Verified Reference 127 history

The following counts and renders belong to the earlier five-study receipt, not
the optional all-player Reference 129 export above.

- 16 parser/math/safety tests pass, including generated-step syntax, native joint
  and quaternion validation, unknown-confidence preservation and overwrite checks.
- MCP imported the real USD assets, packed both kit textures and built shared
  source actions. A separate, clearly synthetic 22-player scene rendered.
- Actual imported USD rig probe: all 80 bone world matrices checked against the
  native local transform chain at a translated root and 30-degree heading. Worst
  matrix-element error `9.54e-7`; head error `3.58e-7`. The extra Z half-turn in
  the authoring coordinate conversion is accounted for, not silently doubled.
- The generated workflow independently checks all exported player root positions,
  headings and ball positions. It also checks every exported actor's bone matrices and
  records nearest head/body mesh distance at each admitted ball contact. Contact
  distances are diagnostic, not fabricated limb tracking. A save's native palm
  marker contract is different from its nearest full-body mesh surface.
- All five native studies have been built and reviewed: `final-36-counter-v2`,
  `final-81-volley`, `final-108-rebound-v2`, `city-45-overlap-header`, and
  `city-57-underlap-cutback`. Final native export SHA-256:
  `d4e70d6a42bb1a06342d6af6c1d1c3fdbba456ff4afd2c13041ba8de3456b8af`.
  The first three staged studies were compared field-for-field with that final
  export; their data is unchanged. Their earlier build hash is retained too.
  Across all five: 154,800 bone matrices, 32,846 root samples and 5,885 ball
  samples checked. Position errors at supplied timestamps are zero; maximum bone
  matrix-element error is `3.82e-6`, heading error `4.77e-7` radians.
- Reviewed clean native contact close-ups and wide context renders for all five.
  Jersey numbers and the source-status caption are readable. The volley header
  is a crown/top-of-head glance; it does **not** prove source-matched forehead
  technique. These are procedural app poses, not captured broadcast body motion.
- Both header nearest-mesh sphere gaps are under 6.2 mm in Blender. The keeper's
  whole-body nearest-surface overlap is 13 mm; this is not a palm-contact test.
  Native tests provide the separate foot/head/palm contract. Neither this metric
  nor a still image proves natural motion throughout the whole clip.

## Reference 127 artifact receipts

All large outputs are ignored artifacts under `.codex-derived/Reference127/`:

- `ReplayXI-FiveReferenceStudies-01.blend`: five editable studies, 110 player
  roots, licensed rigs/textures, player POVs, source metadata and verification.
- `final-blender-verification.json`: full mapping and contact-surface receipts.
- `Contact-counter-shot-clean.png`, `Contact-volley-header-clean.png`,
  `Contact-cutback-shot-clean.png`, `Contact-city-header-clean.png`,
  `Contact-rebound-save-clean.png`, `Contact-rebound-finish-clean.png`.
- Wide context: `Overview-counter-finish.png`, `Overview-final-81-volley.png`,
  `Overview-city-57-underlap-cutback.png`, `Overview-city-header.png`,
  `Overview-rebound-finish.png`.

Four agent-owned synthetic QA scenes were removed from the final review file.
They remain recoverable in `ReplayXI-ThreeStable-01.blend`. The user's original
startup scene (`Cube`, `Light`, `Camera`) and untitled file path were preserved.
No app USDZ, motion JSON or other app asset was replaced.

## Safety and limits

### Reference 129 follow-up receipt

The optional all-player route is now exercised for `final-81-volley-v2`:
22 native rigs at 20 Hz plus exact contacts, 4,708 poses, 376,640 verified bone
matrices, 9,328 root samples and 1,261 ball samples. Source JSON SHA-256 is
`685267b1c47d17fb260374d57c8b328e39fcf34af914cf50e0bd545cbbfe2b98`.
Root/ball timestamp errors are zero and the maximum matrix-element error is
`3.82e-6`. These are mapping checks, not motion-capture or visual-realism scores.

The new copy is `.codex-derived/Reference129/ReplayXI-Volley-Native22-01.blend`.
It preserves all earlier scenes and the user's original untitled file path.
A 30 fps, 4.83-second native-pose review render accompanies it. See
`REFERENCE129_CHECKPOINT.md` for tests, visual limits and saved-work receipts.
The addon enforces a 200,000-byte safe-script limit; retain the generated small
data steps or keep ordered, length-guarded batches below that limit.

Blender MCP connected to Blender 5.2.1 LTS, addon 1.6/protocol 5. Telemetry is off.
Safe mode stays enabled. `.blend` library loading was rejected, so the workflow
uses permitted USD imports; it does not bypass that restriction with another tool.
Script-capable Text datablocks are also blocked. Data and the MIT notice are held
as non-executable JSON/string scene properties, not Blender scripts.

No FIFA assets/engine, no claimed FIFA-level animation, no recovered off-camera
tracking, no automatic tactical AI. No app assets are replaced by this workflow.
The authoring output is a separate editable review artifact; app integration must
pass native model/contact/performance tests separately.
