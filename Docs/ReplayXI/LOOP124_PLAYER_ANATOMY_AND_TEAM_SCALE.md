# Player anatomy, equal team scale and original kits

## Shipped change

- All review views use physical 1× actor roots. Selection/featured multipliers (previously up to 3.15×) no longer create an apparent team-size difference. Palette choice no longer changes height or width. Rings/tags retain the emphasis.
- The distant body now has shaped shoulders, waist, thighs, calves, hands and boots. Knees, elbows, wrists and ankles deform through four small three-joint skins. The existing licensed static face stays attached to the existing head/neck pivots.
- Both teams share the same per-LOD geometry. Near/low skins keep their admitted geometry, face, normal maps, skeleton and contacts, with original collar, cuff, panel, shorts-seam and sock detail. Away shorts are white across the skin and procedural kits.
- Six original 64×64 torso/shorts maps serve all far players. Cold preparation is explicit and atomic. Missing/invalid resources fall back to the old flat materials or rigid body; creation/posing performs no texture or asset loads.

## Geometry and limits

| Part | Vertices | Triangles | Joints |
|---|---:|---:|---:|
| Torso | 151 | 266 | 0 |
| Shorts | 67 | 120 | 0 |
| Each arm | 167 | 300 | 3 |
| Each leg and boot | 213 | 380 | 3 |
| Existing MIT face | 486 | 749 | 0 |
| Complete far player | **1,464** | **2,495** | **12** |

Seven model draws remain seven. The existing 1,800-vertex/2,500-triangle far ceilings and four full 80-joint skin cap are unchanged. New geometry package: 25,268 B, SHA256 `1a16ed08fe9c9272f5f2c2f4187ad1f747a39f52bc056ffaaacff9cee0c0a307`.

The leg guard caches all 426 native weighted vertices, with the actual three inverse binds. Every pose queries this bounded local chain; it never scans meshes or inverts the world transform. Correction is vertical/upward only. The original rigid fallback retains its separate 128-point cap and solver. Joint lengths and authored timing remain unchanged.

Far maps add 98,304 B of base-level decoded pixels; mipmaps, import/cache and GPU overhead are extra. Existing fifteen body maps remain 512×512. No headset FPS or measured memory saving is claimed.

## Blender MCP and provenance

The installed local Blender MCP connection was restored in a new factory-startup process, with an isolated `ReplayXI Players124 - Local modelling` scene. Native MCP reported Blender 5.2.1 LTS, addon1.6/protocol5 and telemetry off. External model services stayed disabled; no permissions were changed. Existing user scenes/preferences and admitted source assets were not overwritten.

Actual geometry creation, rigging, source-head import, preview posing and rendering used the native `execute_blender_code` tool with the user's exact request. Safe mode remained on. An initial `__name__` guard was rejected before mutation; the reviewed script was adjusted to use an explicit call, not bypass the sandbox. Package canonicalisation subsequently used local OpenUSD tools.

The public 300×300 thumbnail from the supplied paid 3dpassion page was a broad visual reference for adult proportions, fitted kit, socks and boots. No paid model, texture, logo or game asset was acquired or copied. New body geometry/maps are original Replay XI work. Retained faces/skin/full bodies remain Microsoft Rocketbox MIT derivatives under `Resources/Players/LICENSE-ROCKETBOX-MIT.txt`.

Derived authoring evidence:

- `.codex-derived/ReplayXI-Players124-Anatomy-01/ReplayXIFarAnatomy.blend` and raw USDC.
- `.codex-derived/ReplayXI-Players124-Anatomy-01/two-team-posed-preview.png`: illustrative Blender pose, not a native floor proof.
- `.codex-derived/ReplayXI-Players124-Canonical-01`: canonical Y-up/metre USDZ, strict USD checker receipt and geometry manifest.
- `.codex-derived/ReplayXI-Players124-Kits-02`: exact old/refined maps and hashes. Each map preserves 77,922 non-cloth/boundary pixels byte-for-byte. Geometry, skin weights and normal maps are unchanged.
- `.codex-derived/ReplayXI-Players124-FarKits-01`: six original maps. `PLAYER124_ASSET_MANIFEST.json` retains shipping hashes, dimensions, metrics and baseline Git revision.

Repro tools: `build_replayxi_far_anatomy.py` runs in the isolated Blender scene; `package_replayxi_far_anatomy.py` preserves points/UVs/normals/weights while setting canonical USD hierarchy and Y-up metadata. The raw source uses literal app-local Y-up coordinates, so canonicalisation does not rotate points. `preview_replayxi_far_anatomy.py` copies only authored candidate objects into its own preview scene.

For kits, export UVs with Blender's Python using `refine_replayxi_kit_textures.py --export-geometry <new-json>`. Then run its texture mode with `--geometry`, `--baseline` (the exact fifteen original maps from manifest revision `b1d907f6ff472dac831a237855f420af60584ead`) and a fresh `--output`. All fifteen output PNGs were independently reproduced byte-for-byte in `ReplayXI-Players124-Kits-Reproduced-03`. `build_replayxi_far_kit_maps.py` regenerates the six tiny maps.

## Native evidence

- `/private/tmp/replayxi-articulated-player-admission-01.xcresult`: 1/1 candidate import test passed. Exact four parts, joint order, weights, UVs, counts, identity placements and independent clone rewind checked.
- First combined runtime receipt: all four new runtime tests, admission and physical-scale tests passed. Two unrelated old scene tests still expected the raw ball gaze input; root corrected those to the prepared displayed-ball input without loosening joint/floor assertions.
- `/private/tmp/replayxi-player-visuals-01.xcresult`: 17/17 passed. The eight far images isolate the geometric change using matching old materials. Sixteen near/low images isolate baseline/refined kit maps on the same mesh/pose. Native colour calibration: Display P3, top-first, maximum one code value error.
- `/private/tmp/replayxi-player-visuals-01-attachments`: inspected original/new red far front, and both teams' refined near fronts. Distant knees/elbows visibly bend; retained faces stay intact. Full skins show collar/cuff/short details and retain jersey numbers. No framing change was used to enlarge one team. Final six-map far captures and full-suite receipt are pending below.
- First full native run: 974 passed, 5 failed, 1 optional skip. Four failures exposed a packaging assumption: Xcode losslessly recompresses PNGs, so source encoded hashes cannot identify built images. Geometry admission was unchanged. Far-map admission now bounds encoded bytes at 16 KB, verifies single PNG/dimensions before decode, and pins exact opaque 8-bit sRGB/RGBA pixels. Local CoreGraphics and Pillow independently gave the same six pixel hashes. Native tests require valid re-encodings to pass and changed pixels/size/alpha or oversized input to fail. The other failure was an old arc-picking expectation, handled by root.

Tests now read the shipping geometry bundle, not ignored derived candidate files. The dedicated floor test independently skins native imported vertices, checks four tracks at eleven times plus reverse order, preserves raw horizontal/body/joint motion, and requires exact pose rewind. Other tests cover all 22 mesh identities/metrics, cold failures, near/mid invariance and the six-map cache/fallback lifecycle.

## Limits

This is a clearer stylised football body, not FIFA-level art or motion capture. The legacy procedural rest chain is about 9 cm taller than the licensed near/low body's 1.821 m rest height. This batch removes team/selection exaggeration and uses identical geometry within each LOD; it does not claim exact cross-LOD anatomical height parity or silently alter the ball/contact chain to achieve it.

Headset readability, sustained thermal performance and real-room comfort still need device QA. Weighted floor support is verified; it is not a full-body collision engine. The new far boot has a +0.200 m toe in ankle-local space, shorter than the ball contact proxy's +0.245 m marker. Any ball/boot clearance result is scoped to the sampled contact fixtures, not all players in all poses.

## Final verification

- `/private/tmp/replayxi-player-ball-arc-full-02.xcresult`: **986 total; 985 passed, 0 failed, 1 optional skip**. visionOS Simulator 27.0 on macOS 26.5.1. This includes the exact decoded-PNG admission tests, both-team final native kit/body captures, articulated floor/rewind controls and the new ball-to-far-boot surface fixtures.
- Geometry/UV/joint admission remains hash-pinned. PNG recompression is accepted only when exact canonical pixels match; no colour tolerance was added.
- Source, resources and tests are frozen at this passing snapshot. Device Release verification is recorded by root in the batch handoff; the Simulator receipt is not a headset FPS or comfort result.
