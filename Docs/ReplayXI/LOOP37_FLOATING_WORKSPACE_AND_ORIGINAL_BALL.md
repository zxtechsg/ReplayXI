# Local pass 37 — floating workspace and original Blender ball

## Implemented

- All five spatial UI attachment types share a captured room-space anchor,
  outside the moving replay root. Tracking is `.once`, never `.continuous`.
- View panel and Settings expose **Place controls here**. A revision changes
  only on that explicit action. Existing attachment entities are retained when
  recentered; POV/time/scenario changes do not trigger it.
- Recenter is rejected during drawing, scrubbing and geometry editing.
- Newly created conditional panels attach to the same workspace after changing
  exercises or loading a review. No duplicate per-frame reparenting.
- Settings separates Time and Workspace rows. Strategy Analysis is the mode
  label; saved scenario and mode identifiers remain compatible.
- Match Replay's transport discloses that the current scene is synthetic and
  the reference clip is not loaded, including in immersive player POV.
- Original Blender 32-panel ball integrated: one model, two materials,
  2,592 triangles, 189,704-byte USDZ. This replaces the seven-model sphere/patch
  fallback when the asset passes admission. The fallback remains fail-soft.
- Ball import, hash/scale/material validation happens at spatial entry, not in
  the playback update. Instances share cached resources and own their transforms.

## Evidence and limits

- Full simulator suite: **384 passed, 1 skipped**. The skipped case needs the
  separate optional transient Rocketbox fixture. New asset tests validate the
  actual bundled USDZ's model/material/triangle counts, scale and cloned instances.
- Blender background builder completed and its v2 preview was inspected. v1
  was rejected for panel/core intersections; added curvature resolved them.
- Existing Python Blender assembly checks: 12 passed. Local capability/placement
  source guards also run separately.
- Unsigned visionOS Release device build passed. This does not validate signing
  or physical-headset frame rate.
- Simulator renders inspected: Strategy tactical board, expanded View and
  Settings panels, and Match Replay player POV. Panels remain separated and
  readable in the inspected default-text layout. The view origin and world
  coordinates have automated coverage; headset comfort and recenter behaviour
  under real head movement still need hands-on testing. CUA's camera drag and
  direct click attempts did not produce a reliable interaction trace; screenshots
  and scripted launch routes are not a substitute for that validation.
- No reference video supplied. No actual match reconstruction or new original
  player body/pitch is claimed. Existing player rigs remain the licensed baseline.
- Live Blender MCP was unavailable; modelling used an isolated background
  Blender 5.2.1 process and did not modify an open user scene.

See [new scope](LOCAL_PRODUCT_GOAL.md), [reference research](SPATIAL_UI_RESEARCH.md),
and `ReplayXI/Resources/Strategy/ASSET_PROVENANCE.md` for provenance and rebuild details.
