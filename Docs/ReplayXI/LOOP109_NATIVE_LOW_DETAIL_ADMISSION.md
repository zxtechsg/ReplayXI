# Loop 109 — native low-detail admission diagnostic

Test only. No bundled asset, runtime provider, scene admission or model-cap changes.

The external candidate is `.codex-derived/ReplayXI-Low102-Canonical-03/ReplayXILow102Canonical.usdz` (1,263,724 bytes, SHA-256 `cd8a496a1f89166cf819177c8b959246d130f64ea5dfbd86910488b1dbe849ac`). Its pinned `native-admission-fixture.json` hash is `9cd03e16888fe635bc1e4d417d48895da33dd98b7be7dbf744e262f1177dd5fd`. Only an absent USDZ permits an optional skip. A changed, unreadable or malformed present asset, or absent/changed manifest, fails. A separate always-on test checks rejected identities.

The native probe checks canonical 80-joint order against the existing motion document; one coalesced model entity, two mesh models/materials/parts, 1,707 vertices and 2,129 triangles; finite metric bounds and identity import transforms; shared mesh/independent clones; exact repeated pose writes. Mesh-model IDs, part ownership and instance mappings are recorded separately from entity counts. The public visionOS SDK exposes imported inverse binds, rest transforms and per-vertex joint influences, so these are compared with the fixture. Vertex matching allows import reordering but preserves positions, UVs, weights, normals and oriented triangle topology.

Four canonical poses—source idle, run, cut-right and pass-contact—are written directly and revisited in reverse order. CPU linear-blend skinning uses the imported positions/weights/inverse binds and read-back joint transforms to compare with the independent posed-vertex fixture. The 16.436 mm source base lift is applied once to the root. This is mathematical/import parity, not renderer-evaluated geometry, contact/grounding qualification or FPS. The existing near-body contact envelope is not used.

`ReplayLowDetailAthleteFixture.loadAndPose(named:)` is a shared test-only helper for a later calibrated native render: its returned `.root` is ready to attach, with no animation controller. Native import and CPU-parity JSON attachments retain the exact observed structure/errors.

The first native run exposed one incorrect test assumption: one `ModelEntity` contains two `MeshResource.Model` values, not one. The unchanged strict part/topology checks found Body with 1,296 vertices/1,504 triangles and Head with 411 vertices/625 triangles, sharing one skeleton. All pose/clone/rewind and CPU parity checks passed; the maximum observed vertex-distance difference was 0.837 micrometres. Import evidence: `/private/tmp/replayxi-low109-native-01/75A6906D-3093-4976-9BE2-F8167382F761.json`; parity evidence: `/private/tmp/replayxi-low109-native-01/4AAE60CB-2237-4194-B3FE-1E10F218E675.json`.

The corrected test requires two one-part mesh models and one identity instance per model; the early import attachment now records that exact model/instance mapping before assertions. Hashes, geometry, skeleton and parity tolerances are unchanged. Both admission cases pass in `/private/tmp/replayxi-low109-contact112-palette110-after-01.xcresult` and `.log` (26 targeted tests passed overall). No interactive headset pass is claimed.

## Calibrated native render follow-up

The same batch passes `ReplayRealityRendererAuditTests.testCapturesCanonicalLowSkinRunAndPassWithCalibratedNativeRenderer`. This uses the pinned fixture directly, not the runtime provider, with its 80 joint transforms and single 16.436 mm base lift unchanged. Public RealityRenderer output uniquely calibrates to Display P3/top-first with maximum channel error 1; the original limit remains 4. Camera tone mapping is on and the calibration Unlit initializer tone setting is off.

The run and pass-contact frames are nonempty, unclipped and different. Both were visually inspected, with coherent posed silhouettes and no visible exploded skin. PNG profile inspection confirms Display P3, 512×512. This is native visual evidence for these two fixture poses, not full-animation, grounding, in-app admission, FPS or headset qualification.

- Run PNG: `/private/tmp/replayxi-low109-render-01/50A38ED5-BABF-4521-A6E4-3799D109DE78.png`; data: `/private/tmp/replayxi-low109-render-01/E6B3D358-C283-4FD9-8F92-840EB117A72F.json`. 10,437 non-background pixels; bounds `[214, 140, 300, 388]`.
- Pass PNG: `/private/tmp/replayxi-low109-render-01/CB0AE186-A416-4254-AF64-39FEDEABD69C.png`; data: `/private/tmp/replayxi-low109-render-01/BB2EB82A-1432-4C28-82C3-A636AC25959C.json`. 9,538 pixels; bounds `[214, 126, 287, 389]`.

Full native/Release integration remains parent-owned and pending for this batch.
