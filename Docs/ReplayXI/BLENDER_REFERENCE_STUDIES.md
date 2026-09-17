# Five-study Blender authoring workflow

The new workflow accepts short native app studies, not the older pending 60-second
video pipeline. It does **not** recover a complete match or captured limb motion
from broadcast video.

## Inputs

- A native XCTest export: `schemaVersion: 1`, `studies` array, pitch metres.
- All 22 named/shirt-numbered players per study with exact app root paths/facing.
- Actual recorded RealityKit ball samples and admitted contact times.
- Explicit evidence: authored/inferred/observed/measured, visibility, nullable confidence.
- Optional native actor rig samples: 80 local USD Y-up joints, 10 Hz plus exact
  contacts. These retain app posing for key actors; they are not match mocap.
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

## Scene controls

- One scene per study; source/evidence in scene custom properties and embedded JSON.
- Review and tactical cameras plus 22 player POV cameras.
- POV cameras follow player translation, with unkeyed orientation for free look.
- Timeline markers identify contact times and shirt numbers.
- Optional route collection, hidden by default, includes evidence on each route.
- Optional contact rings are hidden by default; actual ball/skin contact stays
  visible without a diagnostic ring covering the boot or head.
- Key actors use native rig samples when provided. Others share distance-timed
  idle/run source actions. These background gaits are illustrative.
- Ball translation and rotation are imported from the native physics recording, not resimulated
  or steered toward feet in Blender.

Native `(x,y,z)` maps to Blender `(-x,z,y)`. This is a right-handed rotation, not a
reflection, so body heading and local rig poses remain consistent. Scene units
are metres; player roots and ball path are not artist-scaled.

## Checked so far

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

## Final artifact receipts

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

Blender MCP connected to Blender 5.2.1 LTS, addon 1.6/protocol 5. Telemetry is off.
Safe mode stays enabled. `.blend` library loading was rejected, so the workflow
uses permitted USD imports; it does not bypass that restriction with another tool.
Script-capable Text datablocks are also blocked. Data and the MIT notice are held
as non-executable JSON/string scene properties, not Blender scripts.

No FIFA assets/engine, no claimed FIFA-level animation, no recovered off-camera
tracking, no automatic tactical AI. No app assets are replaced by this workflow.
The authoring output is a separate editable review artifact; app integration must
pass native model/contact/performance tests separately.
