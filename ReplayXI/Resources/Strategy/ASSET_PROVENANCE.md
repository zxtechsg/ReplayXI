# Original Replay XI strategy assets

## Ball

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

## Pitch and goals

Created in Blender 5.2.1 with `Scripts/blender/build_strategy_pitch.py`.
All geometry and turf grain are original procedural work. No downloaded models,
club branding, player likenesses, third-party photos or third-party textures.

- Playing field: 105 x 68 m; a 3 m end / 2 m side grass apron supports the goals.
- Goal interior: 7.32 m wide, 2.44 m below the crossbar. Markings include goal
  areas, penalty areas/arcs/spots, centre circle/spot and corner arcs.
  Dimensions reference [IFAB Law 1](https://www.theifab.com/laws/latest/the-field-of-play/).
- 2 static meshes, 4 material slots, 7,234 triangles; no animation or physics.
- 2 original 512 x 512 turf textures repeat every 2 m; no grass alpha cards.
- USDZ: 1,126,057 bytes. Runtime imports once before room entry and clones
  shared mesh/texture resources. The procedural pitch remains a fallback.
- Reviewed v2 SHA-256:
  `ad824e7a8d88d77ef330658000284d43a53dd691ddea62d4719a634b39a16de5`.

Editable Blender file, previews and report:
`.codex-derived/ReplayXI-StrategyPitch39-v2/`.
v1 lacked the grass apron and was not integrated. The importer preserves the
USD root's Z-up to Y-up conversion when flattening the two meshes.
