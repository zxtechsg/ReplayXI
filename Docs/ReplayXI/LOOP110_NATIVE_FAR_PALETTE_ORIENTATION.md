# Loop 110 — native far-player colour placement

## Reproduced defect

The calibrated Loop 104 native preview showed skin at the shoulder, a shirt-coloured wrist, sock-coloured thighs and exposed lower legs. CPU texture-row checks had passed because the image rows were correct; the mesh UV direction was not.

Two native tests isolate the distinction:

- An independent two-colour texture on a canonical bottom-origin UV quad passes, with source top and bottom rows at the expected physical heights.
- Actual far arm/leg mesh UV rings and the exact attached resource/sampler are placed unchanged on unlit strips. Eight anatomical samples from `navy-rb` and `red-lw` all fail before the fix. Expected kit/skin colours come from quantized source sRGB converted independently into the calibrated output gamut. Samples stay away from band boundaries.

Calibration uniquely identifies Display P3 and top-first pixels, maximum error 1. The colour assertion limit remains 4. Before the fix, the four home samples each have maximum channel error **193**; the four away samples each have error **87**. This is shader sampling evidence, not an offline render or a PNG-row correction.

## Narrow fix owned by root

`ReplayFarAthletePaletteProvider.textureCoordinate` now maps the top-origin image fraction to bottom-origin mesh V (`1 - oldV`). Half-texel insets, texture bytes, sampler, mipmaps, cache limits, geometry counts and per-frame work are unchanged. The old CPU UV formula test is updated to this native-verified convention.

The offline renderer also flipped V after already reordering image rows for Blender. That extra UV flip could mask the app defect. Root replaced it with a validated identity UV mapping: reorder pixel storage once, preserve native bottom-origin UVs.

These native controls supersede Loop 99's offline UV-origin/band-placement conclusion. Loop 99's actual texture-row, colour-space and tint readback tests remain valid, but did not establish native shader UV orientation. The earlier Blender images must not be used as proof that the app's sleeve/sock placement was correct.

## Receipts and scope

- Native before: `/private/tmp/replayxi-low109-contact112-palette110-before-03.xcresult` and `.log`. Loop 110: one positive control passed; one anatomical test failed all eight assertions. Unrelated Low109 harness assertions are separate.
- Native sample data: `/private/tmp/replayxi-palette110-before-01/8B9DDE14-BA02-476A-B611-28DD61FA6BC3.json`.
- Native strips: `/private/tmp/replayxi-palette110-before-01/3CBA082A-A480-408C-B31F-DD8D09D4202B.png`.
- Native after: `/private/tmp/replayxi-low109-contact112-palette110-after-01.xcresult` and `.log`: **26 passed**, including both Loop 110 tests, all ten existing far-palette tests and the three native renderer cases. All eight anatomical samples now pass; maximum observed colour error is **2**, without changing the original limit of 4.
- After sample data: `/private/tmp/replayxi-palette110-after-02/3C992D97-5B4A-4A03-8C6A-036CDC355549.json`.
- After strips: `/private/tmp/replayxi-palette110-after-02/DAB1A3E7-C456-4F7E-9966-5100AEA4562E.png`.
- Actual native far avatar after: `/private/tmp/replayxi-native110-avatar-01/79FBDFA8-E7CC-4B2D-9182-9A59BE32A97C.png`. Inspection confirms shirt at upper arm, exposed lower arm/thighs and socks below the knees. Both after images embed Display P3.
- Full native/Release checks remain pending with root.

Tests use the public calibrated RealityRenderer path, async GPU completion and a ten-second deadline. No app logic was edited by the audit agent. No new player asset, near/mid rig, pose, camera mode, annotation, save format or network capability is introduced. No headset validation or FPS claim.
