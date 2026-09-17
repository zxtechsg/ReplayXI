# Both-team native player comparison

Both `ReplayPlayerVisualComparisonTests` cases pass in the final full bundle `/private/tmp/replayxi-player-ball-arc-full-02.xcresult`: **986 total, 985 passed, zero failures, one optional transient-fixture skip**. Final attachments: `/private/tmp/replayxi-player-ball-arc-full-02-attachments`. Generic visionOS Release also passed with signing disabled: `/private/tmp/replayxi-player-ball-arc-release-01.log`.

- **Far:** Northbridge #2 and Eastport #3 at 13.6 s, current cold fallback versus admitted articulated body + kit. Face mesh/materials, limb palette, pose input, physical scale, camera and lighting stay matched. Front/back pairs total eight PNGs. Uses the shipping asset through `ReplayArticulatedFarProvider.prewarm()`; no derived file or optional skip for this case. Visual01 below isolated geometry before the far-kit addition.
- **Near/low:** the same two players, two skin details and front/back views, with exact baseline/refined maps from `.codex-derived/ReplayXI-Players124-Kits-02`. Only body material 0's colour texture changes. One retained clone preserves its mesh, pose, normal map, roughness, head and numbers. Sixteen PNGs compare the maps; the final test also verifies shipping maps match the refined decoded pixels and dimensions. The test itself changes no runtime resources.

The kit manifest is SHA-pinned (`035774ad…974637`), and each used PNG is checked against its before/after hash. A genuinely absent optional fixture skips explicitly; a present incomplete or changed fixture fails.

Every capture requires the established native swatch calibration before PNG export. JSON receipts record camera/root transforms, asset hashes, model/joint counts, model bounds and measured raster bounds. Empty/clipped captures fail. Before/after RGB differences must be non-zero; this is evidence of a visible change, not a claim that it looks better.

Model bounds are not claimed to be deformed-skin bounds. These are offscreen RealityRenderer captures in body-local coordinates, not UI, headset comfort, animation-video or performance evidence. Parent owns native execution and image review.

## Visual01 evidence

Initial matched evidence came from the **17/17, zero-failure** targeted bundle `/private/tmp/replayxi-player-visuals-01.xcresult`; attachments at `/private/tmp/replayxi-player-visuals-01-attachments`.

All 24 native PNGs were inspected. Articulated far bodies show bent knees/elbows instead of rigid limbs, with the same face resource. Both near/low kits show the new cuffs/collars; the away kit's white shorts and the existing #2/#3 remain visible front/back. No captured body is clipped. The far body remains visibly stylised; this is not FIFA-level fidelity.

Calibration uniquely resolved **Display P3, top-first rows, maximum error 1 byte**. All roots remained scale `[1, 1, 1]`. Far before/after pairs changed 12,902–15,193 RGB pixels; colour-only near/low pairs changed 7,373–7,616. Kit-pair raster bounds stayed identical. These counts prove actual rendered changes, not subjective quality or frame rate.

The kit02 captures above use explicit staged maps. The final full-02 run warms the new far-kit provider and checks its torso/shorts textures, recording their bundled hashes. That far pair is explicitly **current cold fallback versus articulated body + kit**, not a geometry-only isolation. The near/low test also proves shipping pixels match refined02.

## Packaging check correction

The first full run exposed an incorrect test assumption: Xcode's PNG packaging changes encoded file SHA values. Source fixture/manifest SHA checks remain strict. Shipping versus refined equality uses bounded ImageIO decoding into exact 512 × 512, opaque, 8-bit premultiplied RGBA/sRGB pixels, with no channel tolerance. Receipts distinguish packaged-file SHA from canonical-pixel SHA. No camera, pose or visual acceptance threshold changed; full-02 passes this corrected check.

## Final rendered review

Inspected all four full-02 `far-articulated-kit` home/away front/back images. Both complete bodies render within frame; home white/navy and away red/white kit colours are consistent. Knees/elbows retain articulation, with no missing head or limb in these poses. Foreground counts are 12,907–13,344 pixels; the calibration remains Display P3/top-first/error 1 byte. These remain deliberately low-detail, stylised far bodies. No animation-video, headset or frame-rate result is implied by four stills or the signing-disabled build.
