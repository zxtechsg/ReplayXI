# Blender match assembly

This builds an editable Blender scene from supplied player/ball tracks. It does
not reconstruct video. The actual match reference is still pending.

## Current outputs

- `PendingReference-03.blend`: regulation-scale pitch; reference and tracks pending.
- `PendingReference-03.glb`: verified static inspection copy; no invented players or ball.
- `SYNTHETIC-TEST-ONLY-03.blend`: **two-second synthetic QA**, 22 rigged identities,
  44 editable jersey numbers, 23 cameras and timed tracked annotations.
- `SYNTHETIC-TEST-ONLY-03.glb`: posed inspection snapshot at 1 s, with companion MIT notice.
- `SYNTHETIC-TEST-ONLY-03.png`: tactical render of that QA scene.

All outputs are in `.codex-derived/ReplayXI-MatchAssembly/`. Earlier `-01` and
`-02` GLBs are obsolete: their scene evaluation was not valid for export.
These files are local working artifacts, not app assets or completed match reconstructions.

## Input

Prepare the selected clip using [Match reference prep](MATCH_REFERENCE_PREP.md).
Fill its `replay-tracks.template.json` with explicit tracks before building a match.

- Schema version 1; duration up to 60 s.
- `players`: empty while pending, otherwise all 22 identities, 11 per team.
- Player keys match the app: `id`, `displayName`, `team`, `shirtNumber`,
  `keyframes[{time, position:{x,z}, facingDegrees, evidence}]`.
- `ball.keyframes` adds `height`; all positions are metres.
- Every supplied sample declares manual/inferred/measured origin, confidence
  and source visibility. `sourceFrameID` is optional but checked when supplied.
- The source manifest hash, original video hash, path, duration and referenced
  frame IDs are checked. No unseen player positions are invented.
- `annotations` uses the app's run/pass/danger/space/playerLabel geometry,
  reveal/hide timestamps, elevations and optional player-track anchors.

Source X/Z maps to Blender X/Y; height maps to Blender Z. The pitch is 68 × 105 m.
Frame 1 is replay time 0. A missing track stays hidden. Player-attached marks
share the intersection of their players' known tracking intervals.

## Build

Run from the project root in **background Blender**. Use new output names:

```sh
/Applications/Blender.app/Contents/MacOS/Blender \
  --background --factory-startup --python-exit-code 2 \
  --python Scripts/blender/build_match_replay.py -- \
  --manifest /path/to/replay-tracks.json \
  --player-library .codex-derived/ReplayXI-Assets/Rocketbox-Loop32-Final/Blender/ReplayXIFootballPlayers.blend \
  --output .codex-derived/ReplayXI-MatchAssembly/MatchReview.blend \
  --glb-output .codex-derived/ReplayXI-MatchAssembly/MatchReview.glb \
  --preview-time 12
```

For the empty pending scene, use `Scripts/blender/reference-pending.json`, omit
the player library and set preview time to 0. `--validate-only` works with plain Python.

The `.blend` is authoritative: editable rigs, cameras, annotations and animation.
The optional GLB is a **static snapshot** at the requested time. Evaluated body
poses and curves are baked for reliable MCP import. It does not carry the timeline.

The script creates a new scene and preserves existing data. Its temporary scene
selection occurs only in the background process. It does not control the live GUI,
change preferences, delete user objects or overwrite files. MCP can import the
inspection GLB through its normal allowed glTF import operation.

## Editing and limits

`Track_<playerID>` contains translation. Its `BodyFacing_<playerID>` child follows
recorded facing. `POV_<playerID>` is a separate child of the translation root;
its rotation is unkeyed and can be changed freely. The default POV height is 1.68 m.

The player library contains a licensed Microsoft Rocketbox body with idle/run
actions. Gait timing follows track distance; limb movement is illustrative, not
measured football motion. There is no tackling/kicking clip or physics ragdoll.
The MIT notice is retained in the `.blend` and beside player-containing GLBs.

Tracks use bounded linear interpolation. Overshoot is avoided, uncertain intervals
remain labelled, and excessive annotation/keyframe density is rejected before scene
assembly. Keep all reference media and generated scenes outside the app bundle.

## Verification

```sh
python3 -m unittest discover -s Scripts/tests -p test_replayxi_blender_match_assembly.py

/Applications/Blender.app/Contents/MacOS/Blender \
  --background --factory-startup --python-exit-code 2 \
  --python Scripts/blender/test_match_replay_scene.py -- \
  --player-library .codex-derived/ReplayXI-Assets/Rocketbox-Loop32-Final/Blender/ReplayXIFootballPlayers.blend \
  --output /private/tmp/SYNTHETIC-TEST-ONLY.blend \
  --glb-output /private/tmp/SYNTHETIC-TEST-ONLY.glb \
  --render /private/tmp/SYNTHETIC-TEST-ONLY.png

/Applications/Blender.app/Contents/MacOS/Blender \
  --background --factory-startup --python-exit-code 2 \
  --python Scripts/blender/test_match_replay_glb.py -- \
  --glb /private/tmp/SYNTHETIC-TEST-ONLY.glb --synthetic-test
```

The headless checks cover fractional timestamps, single-sample idle, free-look
during player turns, timed/elevated tracked marks, preserved startup scene,
22 identities, jersey text, 80-bone rigs and GLB camera/ball/POV transforms.
