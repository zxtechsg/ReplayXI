# Original Replay XI strategy ball

Created in Blender 5.2.1 with `Scripts/blender/build_strategy_ball.py`.
No downloaded models, club logos, player likenesses or third-party textures.

- 32 curved panels and recessed seams; nominal diameter 0.22 m.
- 1 mesh, 2 materials, 2,592 triangles; no texture files or animation controllers.
- Runtime imports once at spatial-entry preparation, then clones cached resources.
- Reviewed v2 USDZ SHA-256:
  `4defbfdcdf09df651f11340cb52778890f609b556ff84e628cf93713a8798911`.

Editable Blender file and preview: `.codex-derived/ReplayXI-StrategyAssets37-v2/`.
Rebuild into a new output directory. Verify geometry, USDZ import and preview
before updating the runtime hash. v1 was rejected for panel/core intersections.
