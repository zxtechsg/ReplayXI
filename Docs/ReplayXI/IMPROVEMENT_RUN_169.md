# Cycle 169 — movement, annotations and surroundings

Local-only Replay XI. User-supplied stadium replaces the rejected Tripo candidate.

## Changes

- Added small, gait-linked chest, shoulder, elbow and wrist follow-through on
  both teams and fallback rigs. Legs, limb lengths and protected ball contacts
  are preserved. Head aiming compensates for the extra chest motion.
- **Annotate in 3D** opens the paused replay's tools from the dashboard or video
  comparison. It preserves time/POV and existing marks. These are 3D replay
  annotations, not burned-in video overlays.
- Timing now starts with **Start here / End here** at the playhead. One Done
  action saves drafts together. Exact times and animated position keys remain
  under expandable sections; save/undo rules are unchanged.
- Added **Room / Stadium** surroundings. The supplied stadium is 24,768 tris,
  one material, one 2K authored colour/AO atlas, 3.14 MB. Resources are shared;
  imported scenery has no collision or input components. Missing/changed assets
  use local procedural scenery. Two fixed, shadow-free lights keep the pitch and
  players readable in full immersion; they switch off in Room mode. Physical
  positioning practice keeps passthrough.
- Removed the tabletop pitch tilt. In **View & overlays → Room → Pitch
  placement**, Find a surface detects a floor/table; Place confirms the fit.
  The board shrinks uniformly when needed, checks the measured mesh including
  holes/edges, and stays level. Cancel stops scanning; Reset restores the default
  pitch. The control bar never moves with this operation.
- Surface sensing asks for world-sensing permission only on request. A delayed
  headset pose cannot offer a target around the old/default origin. Scans are
  room-owned, preserve world tracking, and cannot replace active physical drills.
  Placement is session-local, not a saved room map or cross-launch anchor.

## Asset provenance and spend

[Source, calibration and rebuild instructions](../../Assets/ReplayXI/SuppliedStadium/README.md).
The original ZIP is preserved. It contained no MTL/textures/license file; colours
and shading were authored in Blender. Two central field triangles were removed
to leave the playable pitch clear. Source geometry was not decimated.

Tripo charged **55 credits** for the rejected stadium. One advertised free retry
left the observed balance unchanged at **2,115**. No Tripo stadium is bundled.
[Credit ledger](TRIPO_CREDIT_LEDGER.json). No further generation was purchased.

## Validation

- Final code: **280 selected visionOS 26.5 Simulator tests passed**, zero
  failures/skips: `.codex-derived/replayxi-flow169/FinalLighting265-02.xcresult`.
  A preceding focused surface/lifecycle/asset run also passed 53 tests.
- Both unsigned Release builds passed (device and Simulator):
  `/private/tmp/replayxi169-light-device-release02.log` and
  `/private/tmp/replayxi169-light-sim-release02.log`.
- Native images reviewed: both teams' movement, timing at regular/largest text,
  supplied stadium from four sides and overview, surface controls at regular,
  largest and narrow widths. Cancel remains present when a plane is found or
  none fits. The actual app was launched in Room and Stadium on the QA Simulator.
- The light test compares the same native player/pitch before and after fixed
  lights. It passes, as does explicit absence of Shadow components. An earlier
  `shadow = nil`/getter check failed; explicit component removal replaced it.
  [Apple's light-component reference](https://developer.apple.com/documentation/realitykit/directionallightcomponent).
- Main Simulator saved-review hash remains
  `a472d19ff9b2f3495dab0b38d98c306dddfed2e2e0493c8a450ce82f4e9b18cb`.
  Tests use the separate Native Audit Simulator and in-memory demo reviews.
  Player USDZs/source motion are unchanged. User signing/project edits are excluded.

[Stadium](Evidence169/stadium-north.png) · [Overview](Evidence169/stadium-overview.png)
· [Timing](Evidence169/timing-regular.png) · [Large text](Evidence169/timing-largest.png)
· [Surface controls](Evidence169/surface-largest.png)
· [Native player lighting](Evidence169/player-lit.png)
· [Room app capture](Evidence169/room-flat-native.png)
· [Validation metadata](Evidence169/validation.json).

## Limits / headset check

This is restrained procedural motion, not new motion capture or EAFC-level
animation. Cloth/hand/jersey artifacts remain. No FPS or headset performance
claim. Real plane detection, permission prompts, tracking loss/recovery and
physical board alignment still need Apple Vision Pro testing.

On headset: select Room + tabletop; Find a surface; confirm Place; check every
corner clears the table; cancel/restart a scan; reset; switch POV and return.
Then add a mark, set Start/End at the playhead, scrub both boundaries, save and
reopen the review. Stay seated or planted in Stadium mode.
