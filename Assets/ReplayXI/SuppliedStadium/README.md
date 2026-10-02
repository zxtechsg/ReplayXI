# Supplied stadium

User-supplied `3d-model.obj.zip`, unchanged. It contains one OBJ, no MTL,
textures, or license file. Ownership/licensing is not established by this
archive. This is not a Tripo asset; no Tripo geometry or textures are included.

Candidate04 keeps the supplied bowl shape. It removes two central field
triangles, retaining the apron outside the clear opening. Uniform calibration
leaves a 74×112 m clear rectangle at every height; the playable field is 68×105 m.
Output: Y-up/metres, 24,768 tris, one double-sided mesh/material, one 2K texture.

The navy/teal/steel colours are authored, not recovered source materials. The
atlas bakes those colours with local AO and a soft directional shading factor
for stable unlit rendering. It does not add seats or change the source shape.
Original UVs are archived in derived output; smart UVs are made on a mesh copy.

## Rebuild

Run from the repo root using Blender 5.2.1 LTS with its bundled NumPy/OpenUSD.
The output directory must be new. This starts a separate background process;
it does not open or clear a user's live Blender session.

```sh
/Applications/Blender.app/Contents/MacOS/Blender \
  --background --factory-startup --python-exit-code 1 \
  --python Scripts/blender/prepare_supplied_stadium169.py -- \
  --input Assets/ReplayXI/SuppliedStadium/3d-model.obj.zip \
  --expected-input-sha256 702ee7d612bcdb4450bb1676e86a781152594e221c975432951cb2bdb2f4d7b7 \
  --calibration Assets/ReplayXI/SuppliedStadium/calibration.json \
  --output-dir .codex-derived/Assets/ReplayXI/SuppliedStadium/rebuild01 \
  --bake-atlas --render-inspection
```

Bake budget: 2048², 32 Cycles samples, 16 AO rays, 8 CPU threads. The script
checks mesh identity across baking, pitch clearance, bounds, texture budget,
USDZ dependencies and `usdchecker --arkit`. PNG previews and the full audit
stay in ignored `.codex-derived`; only this source/provenance set belongs here.

`provenance.json` records the reviewed candidate04 hashes. Rebuild hashes may
vary by Blender/runtime; compare renders and rerun native admission tests before
updating the runtime asset/hash. A successful offline export is not native or
headset validation. The preparation script never changes runtime resources.
