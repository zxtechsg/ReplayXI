# Loop 94 — Native far-player mesh visual audit

Export the actual static mesh vertices, triangles and material tints from two visible distant players at the Loop89 floor-error fixtures. Geometry is expressed in player-local space, including appearance scale. The comparison restores only the authored body Y in a test-owned scene; it is not a second animation rig or a screenshot of an older build.

Native assertions require every vertex's X/Z, topology and tint to stay identical, with one common vertical correction. The uncured baseline must reproduce below-floor geometry, and the corrected sample must clear the same pitch plane. Four samples are attached for isolated Blender rendering.

The Blender utility writes only to a new `.codex-derived` directory. It does not modify app assets or load/save a user Blender file. Input filenames, mesh sizes, indices, colours, finite coordinates and measured minima are validated. Six Python tests cover that contract.

## Verified result

The native export passes in `/private/tmp/replayxi-parallel89-93-postfix-01.xcresult`, after the final ancestor-independent Loop89 correction. Export: `/private/tmp/replayxi-far94-native-final-01/4BB54755-8520-4A74-A19B-CE48BC021EA1.json`.

Each sample retains 399 vertices and 574 triangles. The navy runner changes from −89.639 mm below the floor to −0.000119 mm; the red runner changes from −95.980 mm to +0.000179 mm. Those sub-micrometre residuals are native floating-point results, not a claim of exact physical contact. All X/Z, topology, tint and uniform-lift assertions pass.

An isolated Blender run completed and wrote four 640×800 PNGs plus `report.json` in `.codex-derived/ReplayXI-Far94-native-final-01`. The before/after images were inspected: the grounded leg no longer disappears into the floor. The unaltered far silhouette is still visibly basic; this correction does not add knee bending, boots, kit detail or face quality. The full Python suite passes: 132 tests, 120 passed, 12 optional skips (`/private/tmp/replayxi-parallel88-94-python-01.log`).

Limits: this is the existing simplified far LOD, not the licensed close-up skin. Mesh positions and base tints are native; Blender lighting and smooth shading are illustrative. It is not an interactive screenshot, a texture-quality comparison, real-match footage or a headset performance test.
