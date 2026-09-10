# Blender match reconstruction

## Current priority — 10 September 2026

Only **Situation Roleplay** and **Match Replay** are in scope. Both use replay,
timeline seeking, selectable/free-look player POVs, POV comparison, and 3D
annotations/coaching demonstrations. Existing scenario IDs and review saves
remain unchanged.

Build order:

1. Reconstruct one selected 60-second real-match sequence in Blender.
2. Verify timing, player identity, ball movement, POVs and annotations against
   the reference. Mark estimated and unseen positions as inferred.
3. Integrate that reconstruction into Match Replay.
4. Improve strategy-sim players, pitch and ball using original or licensed art.

The existing Match Replay entry is still a **synthetic reconstruction preview**.
No actual match clip, measured tracking, Gaussian splat or completed 60-second
real-match reconstruction has been imported. The earlier YouTube reference
could not be read; its public oEmbed endpoint returned HTTP 401. A local clip
and selected time range are still needed. A single broadcast angle cannot
establish all hidden positions or true recorded head gaze.

## Verified local connection

- Blender **5.2.1 LTS**, `/Applications/Blender.app`.
- Upstream [Blender MCP](https://github.com/ahujasid/blender-mcp) **1.9.1**,
  source commit `5f8ddaf6e987c4aa0c3467fcc548838b28f64477`.
- PyPI wheel SHA-256:
  `ede3aed34926f77142b8f00ee4f8544f68067d2dc747da8295d1c456171355b2`.
- Installed add-on SHA-256:
  `f43469c8518c7021e0060e32cfe52e3beb126b0f62fbae7293106642a3ebda89`.
- Add-on protocol **5**; handshake and scene read verified through an actual
  MCP `ClientSession`, not merely a TCP port check.
- Codex server name `blender`; executable
  `/Users/zx/.local/bin/blender-mcp`.
- Bound to **127.0.0.1:9876** only. No LAN exposure or port forwarding.
- `DISABLE_TELEMETRY=true`, `BLENDER_MCP_SAFE_MODE=1`.
- Blender add-on `telemetry_consent=False`, saved in preferences. External
  asset services remain off. The package may create a local anonymous UUID
  even while network telemetry is disabled.

The upstream socket has no authentication. Local software could connect to it;
MCP safe mode checks generated scripts but is not an OS sandbox. Stop the
connection in Blender when not in use. Do not enable cloud generation or paste
service credentials without a separate user request.

The shared MCP config follows [official Codex setup documentation](https://learn.chatgpt.com/docs/extend/mcp?surface=cli).
An already-running task may not refresh its native tool list. This workspace
has a small MCP client for continuing without restarting the app:

```sh
/Users/zx/.local/share/uv/tools/blender-mcp/bin/python \
  Scripts/replayxi_blender_mcp.py \
  --intent 'Blender installed, go connect and CAD.'
```

`--script path/to/reviewed.py` sends a reviewed modelling script through the
same MCP safety checks. Only one agent operates the live Blender scene. Other
agents use isolated, factory-startup background Blender processes and separate
output files. Never overwrite an open user scene, startup file or preferences
as part of asset generation.

The client allows 60 seconds for status and 180 seconds for scripts. A timeout
does not cancel work already queued in Blender. Inspect the scene before a
retry; the client never retries a mutation automatically. The supplied server
path is resolved before validation and launch so PATH cannot substitute it.

The verified `SYNTHETIC-TEST-ONLY-03.glb` was imported through safe-mode MCP into
the separate live scene `ReplayXI Rig QA - synthetic snapshot`. Existing scenes
were preserved. Its 161 objects and tactical camera at `(0, -135, 125)` survived
the live import. This is a static inspection snapshot, not the animated app.

See [scene assembly](BLENDER_MATCH_ASSEMBLY.md) for the editable `.blend`,
track/annotation contract and rebuild commands, and [reference prep](MATCH_REFERENCE_PREP.md)
for the local video workflow. Source footage and derived scenes stay out of Git
and the app bundle.

## Validation this batch

- Two-mode navigation: **355 passed, 1 skipped, 0 failed** on visionOS 27
  Simulator; result `/private/tmp/replayxi-loop34-modes.xcresult`.
- Dashboard visually inspected in Simulator: both modes, retractable exercise
  list and Saved reviews remain visible without overlapping text.
- visionOS device Release build passed; physical-headset testing remains pending.
- Final Python suite in the pinned asset environment: **106 passed, 3 skipped,
  0 failed**. Skips require separate optional converter/built-asset fixtures.
  This run includes the three skinned-transform checks.
- Saved Blender player library and all three GLB kits: **6/6 passed**, including
  evaluated run deformation, scale, bone count, materials and jersey attachment.
- Synthetic 22-player assembly passed free-look, fractional-time gait, timed
  player-linked annotation, jersey-number and existing-scene preservation checks.
  Static GLB reimport passed camera, ball and POV transform checks. The tactical
  and close-up renders were inspected; these are two-second QA, not match footage.
- At this Blender checkpoint, the rigged body and idle/run motion were staged
  outside the app bundle. [Loop 35](LOOP35_SKINNED_PLAYERS_AND_HEADING.md) records
  their subsequent near-field runtime integration and remaining limits.
