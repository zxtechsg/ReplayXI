# Player shading and cloth investigation — 2 October 2026

The native-v6 assets use welded USD topology with per-corner UVs. Both teams
and both detail levels retain their original geometry, skin weights and kits.

Final checks: 187 regression tests on visionOS 27, 11 player/contact/render
checks on 26.5, and 19 offline tests passed. Both release builds passed;
the physical-headset build is unsigned and was not run on a headset.
[Validation record](validation.json).

- [Updated home player — visionOS 26.5](updated-home265.png)
- [Updated away player — visionOS 26.5](updated-away265.png)

The following paired static/skinned images are diagnostic controls, not a
CPU-skinned implementation added to the app.

## Shading

The faceting also reproduces on the visionOS 26.5 simulator, using the same
SDK 26.5 build. It is not limited to the visionOS 27 simulator.

The paired native/static test keeps posed positions, triangles, lighting,
camera and flat PBR material fixed. Native skinning nearly matches normals
recomputed from incident triangles without welding UV-split vertices: only
2 RGB pixels differ at idle, and 1 in the sampled run pose (512×512 images).
Using transformed authored normals on static geometry gives visibly smooth
shading. Four additional render frames do not change the native image.

- [Native skinned control](native-skinned-control.png)
- [Static authored-normal control](static-normal-control.png) — diagnostic only;
  not a runtime implementation or performance claim.
- [Measurements](shading-diagnosis.json), from
  `.codex-derived/replayxi-tripo166/Shading-02.xcresult`.

No duplicate triangles, degenerate faces or conflicting winding were found.
Near geometry has 9,075 UV-split vertices at 4,096 distinct positions; low has
3,269 at 1,118. Coincident records have identical skin weights and authored
normals, but different UVs. An ordinary UV-preserving weld cannot remove them.

A direct `MeshResource.generate` experiment with welded positions and
face-varying UVs lost the UV buffer and rendered incorrectly. It is rejected.
Its failing diagnostic is not part of the app test target.

The USD importer does preserve smoothing when the weld is authored offline.
Both detail levels retain all ordered triangle-corner attributes. The app
therefore imports welded USDZs, not a runtime-regenerated mesh. Near has 4,096
authored points, expanded to 9,075 imported vertices; low has 1,118, expanded to
3,267. Contact sidecars keep their original 9,075/3,269 source-count contract.
The importer counts are checked separately; fallback rig limits are unchanged.

The old `MeshResource.generate(from: importedMesh.contents)` visual experiment
trapped in the visionOS 27 renderer after import. It is removed from the capture
test, not bypassed in app code: the app shares/clones the imported native mesh
and never round-trips its contents through that generator. Home/away/keeper,
run, flat-material, rest-pose and jersey-number captures remain.

`Scripts/build_replayxi_tripo_athlete.py --normal-mode area-weighted
--weld-uv-topology` reproduces this layout with the existing source arguments.
Every exported corner is checked after packaging for position, normal, UV,
joint and weight preservation. Divergent normals fail closed.

[Runtime corner parity](runtime-corner-parity.json) additionally compares the old
and new models after RealityKit import. Positions, UVs, four weights and joint
slots are exactly equal for all 28,947 corners. The regression fingerprints
come from this measured old-runtime baseline, not offline USD fingerprints.

Apple documents tangent-frame skinning in the newer
[SkinningDeformer API](https://developer.apple.com/documentation/realitykit/skinningdeformer).
It is absent from the installed visionOS 26.5 SDK. No private API, CPU mesh
rebuild per frame, beta SDK dependency or extra runtime texture was added.

## Cloth

The white jersey is texture on a closed torso shell, not an open garment hem.
The shorts are a separate 502-face shell. Moving 150 waistband vertices from
thigh to pelvis weighting preserved rest geometry and UVs but made the
high-knee seam worse and introduced an idle edge artifact. That candidate is
rejected. Fewer surface intersections did not mean better appearance.

[Reproduction details and hashes](cloth-candidate.json).

Production asset hashes are updated for native-v6. Motion, contact sample
values, textures and saved-review formats remain unchanged. The two USDZs are
827,309 bytes together versus 986,979 previously. No device FPS claim is made.
