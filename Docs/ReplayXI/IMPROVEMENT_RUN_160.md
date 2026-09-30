# Run 160 — pitch detail, annotation guard and label work

## Tripo access and spending

The supplied account's password login on official Tripo Studio returned
"Incorrect password". Corrected access was requested. No model generation,
rigging, texture job or credit-consuming task was submitted: **0 credits spent**.
The account balance remains unknown. Credentials are not stored in this repo.

On successful login, record the starting balance B before any paid action.
Keep cumulative spend at or below floor(0.70 × B), reserve ceil(0.30 × B), and
check the current balance and quoted charge before every job because others
share this account. Do not buy credits, upgrade, or start unpriced jobs.
Begin with one neutral, complete footballer in a clean A/T pose; inspect before
any reroll, then derive team kits locally. Verify skinning and LODs against the
current 80-joint contract before admitting a generated mesh to production.

## Implemented

- Original Blender pitch: directional grass texture and three-span net cords;
  7,926 triangles, 2 meshes, 4 material slots, two 512² textures. USDZ is
  951,366 bytes, down from 1,126,057. Triangle count increases by 692; the
  existing runtime limits remain 8,000 triangles and 1.5 MB. Inspected goal
  previews and imported the final USDZ through Blender MCP into a new scene,
  preserving the existing scene. No cloud credits used for the pitch.
- Annotation timing: block Add here while either visibility or position-time
  draft is pending; expose its existing explanation as a VoiceOver hint.
- POV labels: calculate distance once per visible eligible label instead of
  three times. Hidden non-candidates retain lazy pose lookup. This is fewer
  calculations, not a measured CPU or headset FPS claim.

## Validation

- Focused visionOS27 simulator suite: **32 passed, 0 failed, 0 skipped**.
  Covers pitch import/bounds/materials/visibility, player label selection and
  styling, annotation drafts and native editor layouts, and combined
  POV → keyframed arc → scrub → save → restore workflow.
  Result: `/private/tmp/replayxi-cycle160-focused.xcresult`.
- Blender candidate check passed under the actual runtime limits.
  Artifact directory: `.codex-derived/replayxi-pitch160/final/`.
- Existing home/away/keeper Blender library and GLB deformation checks:
  **6 passed**. These validate the current assets; no Tripo player was produced.
- Unsigned visionOS device Release build passed; only expected missing
  App Intents metadata warning. Latest Debug demo launched on the main
  visionOS27 simulator as PID 11951. Saved-review SHA-256 stayed
  `8011f44456f802b17631b01fe886b14bb609d3ecb14521a5a22b45ae28d0d39e`
  before/after normal launch. Capture: `/private/tmp/replayxi-cycle160-launched.png`.
- Physical Vision Pro devices remain unavailable; real hand input, comfort,
  thermal behavior and FPS have not been assessed in this run.

Tripo player generation, new player rigging/retargeting and production asset
replacement remain blocked on account access. The broad realism and video
reconstruction goals are not completed by these small local improvements.
