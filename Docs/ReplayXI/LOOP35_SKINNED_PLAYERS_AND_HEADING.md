# Loop 35 — skinned players and heading

## Changes

- Bundled the licensed Rocketbox full body, 80-joint idle/run sidecar and fifteen
  neutral team/skin palettes. Near subjects use direct skeletal poses; no hidden
  animation clock advances during pause, reverse or timeline seeking.
- Head look uses the same absolute-time tactical target as other avatars.
  Biped clavicles are children of Neck; inverse local compensation prevents
  cervical turns from pulling the shoulders and arms around.
- Front/back jersey numbers follow the sampled chest transform. Meshes, textures
  and geometry digits are shared; per-player pose buffers are reused.
- Asset admission checks USDZ/sidecar hashes, exact joint order and the actual
  imported Body/Head material sections. Failed preparation retains the standard rig.
- At most two near skins in first person or four in external/positional views.
  Selection changes release old skins before admitting new subjects. The wearer
  remains hidden in first person; camera rotation is not tied to recorded heading.
- Fixed mirrored player, ideal-Shape and recorded-direction yaw. Positive pitch
  bearing now turns local +Z towards +X, matching the track coordinates. Cervical
  yaw and signed path curvature follow the same convention.
- Imported locomotion no longer suppresses procedural ball touches/kicks.
- Added a packaging audit for smooth normals, normal-map colour space, mesh skin
  binding and joint order. Existing asset bytes did not need rebuilding.

## Evidence

- visionOS 27 Simulator: **375 passed, 1 skipped, 0 failed**.
  `/private/tmp/replayxi-loop35-full-02.xcresult`.
- New focused rig/sampling/heading tests: **20/20 passed**.
  `/private/tmp/replayxi-loop35-rig-04.xcresult`.
- Device Release build passed. Log: `/private/tmp/replayxi-loop35-device.log`.
- Surface/transform Python checks: **8/8 passed**.
- Complete Python pipeline suite: **111 passed, 3 optional fixtures skipped**.
- Latest normal demo launched in Simulator. Tactical and first-person views were
  inspected. The near opposing player visibly uses the textured full-body skin,
  a coherent running pose and the large back number; this is an actual in-app
  view, not the Blender preview. Close-up deformation in a physical headset and
  continuous motion capture remain unverified.
- Actual RealityKit import: one skinned ModelEntity, 80 named transforms, Body
  material 0 with 3,288 vertices, Head material 1 with 1,724 vertices. Both material
  sections and original skin bindings remain intact; geometry was not rebuilt.
- The first full-suite attempt exposed a test-isolation issue: the new tests left
  the shared face cache warm. Their teardown now resets it; the complete suite was
  rerun successfully. Two sampler fixture compile errors were fixed before testing.

## Remaining work / pause

This is still a prototype, not FIFA-level art or measured football mocap. Walking,
cuts, contacts and impacts retain the procedural body until equivalent clips and
retargeting are qualified. Distant subjects retain lower-cost models. Physical
headset frame time, multiplayer device testing and broader motion blending are
not proved by Simulator tests.

Actual 60-second match reconstruction still needs the reference clip. Existing
match content remains explicitly synthetic. No Gaussian reconstruction was claimed.

The user requested finishing this batch and pausing. The hourly improvement
heartbeat is **PAUSED**. The goal remains unfinished; no new agents or improvement
passes should start without the user resuming. Git publication remains pending
explicit destination approval; keep the verified backup local.
