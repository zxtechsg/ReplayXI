# Loop 104 — calibrated native offscreen preview

Test-only RealityRenderer preview now works for the measured path. No app, asset, camera-control or signing changes were made.

## Calibration and harness correction

Eight known sRGB swatches identify channel order, row origin and output gamut before any PNG is emitted. Expected sRGB and Display P3 values use Core Graphics conversion, not a fitted correction. The original unique-match limit remains four byte values.

The first setup disabled both renderer tone mapping and the Unlit initializer's tone-map setting. Grey 128 rendered as 147; the best Display P3 error was 34. The original capture correctly stopped before PNG export.

A bounded six-frame comparison separated a known grey clear from the four renderer/material combinations:

| Renderer tone | Unlit initializer tone | P3/top-first max error |
| --- | --- | --- |
| Off | Off | 34 |
| Off | On | 0 |
| On | Off | 1 |
| On | On | 42 |

Grey clears were exactly 128 in both renderer modes. Runtime defaults were tone mapping on, 4× multisampling, no image-based light resource and intensity exponent zero. The inspected XROS Swift interface exposes no RealityRenderer exposure control.

The corrected harness uses normal renderer tone mapping **on** and Unlit initializer tone mapping **off**, for calibration and the subsequent avatar render. The generic material program descriptor reported `true` even when the initializer received `false`. Treating these as a setter/getter pair was a second harness error: they are now logged separately and the fixed pixel expectations remain the contract. This is not an app/runtime fix.

Apple documents the separate [renderer tone switch](https://developer.apple.com/documentation/realitykit/realityrenderer/camerasettings-swift.struct/istonemappingenabled), [Unlit setting](https://developer.apple.com/documentation/realitykit/unlitmaterial/program-swift.class/descriptor-swift.struct/applypostprocesstonemap), and public [RealityRenderer API](https://developer.apple.com/documentation/realitykit/realityrenderer). GPU readback follows its async completion callback, with a ten-second deadline and no main-thread semaphore.

## Verified preview

The corrected capture uniquely matched Display P3, top-first rows, with maximum channel error **1**. PNGs have an explicit Display P3 profile; the Metal `_srgb` format alone was not treated as proof of sRGB primaries.

The 512×512 avatar preview uses the actual far `navy-rb` marker, UVs, textures and joint pose at 11.691666666666666 s. Its world translation is normalized; audit lights and camera are fixed. It contains 12,839 non-background pixels, bounds `[196, 109, 296, 378]`. Root and the audit agent inspected the native image.

This is a one-avatar offscreen material/pose check, **not** a SwiftUI, complete-scene, device-performance or headset validation. The preview exposed reversed-looking arm/leg colour placement; Loop 110 is isolating native UV sampling before any product fix.

## Native follow-up verified

`/private/tmp/replayxi-low109-contact112-palette110-after-01.xcresult` and `.log` passed **26 targeted tests**, including all three current Loop 104 cases. The later native far preview verifies the Loop 110 colour-placement correction: `/private/tmp/replayxi-native110-avatar-01/79FBDFA8-E7CC-4B2D-9182-9A59BE32A97C.png`.

The optional pinned Low109 candidate was also rendered directly in its `run` and `pass-contact` poses, with its canonical 80-joint writes and base lift unchanged. Both pass the same calibration, nonempty, in-frame bounds and distinct-pose checks. Run has 10,437 non-background pixels, bounds `[214, 140, 300, 388]`; pass has 9,538, bounds `[214, 126, 287, 389]`. Both images were inspected; they show distinct, coherent posed silhouettes, without visible clipping or exploded skin. They do not certify the full animation, runtime admission, contact physics or headset quality.

- Run: `/private/tmp/replayxi-low109-render-01/50A38ED5-BABF-4521-A6E4-3799D109DE78.png`; report `E6B3D358-C283-4FD9-8F92-840EB117A72F.json` in the same directory.
- Pass: `/private/tmp/replayxi-low109-render-01/CB0AE186-A416-4254-AF64-39FEDEABD69C.png`; report `BB2EB82A-1432-4C28-82C3-A636AC25959C.json` in the same directory.

File-profile inspection confirms Display P3 on all native previews above. The Low109 preview bypasses app admission and does not itself promote the candidate into a runtime tier.

## Actual runtime low-player preview

The bundled provider is now checked separately from the source fixture: `prewarm` → `prewarmLowDetail` → `make(.lowDetail)` for `navy-rw` at 13.6 s. It uses the current ball/look target and active pass retarget (influence 0.7825015), plus the real front/back number models. The test confirms the retarget changes the joint pose before rendering.

Both three-quarter views were inspected: **#7 is visible**, the body/limbs are coherent and unclipped, and both 512×512 files embed Display P3. Calibration error remains 1. This is basic usable fidelity, not FIFA-level quality or a headset/performance claim.

- Front: `/private/tmp/replayxi-low113-runtime-render-01/77374C95-9ED7-4CD8-9726-8698709C4AB3.png`; data `AAA9DBFB-7422-42B3-80E0-3A4621B96DEF.json`. 9,704 non-background pixels; bounds `[213, 131, 287, 392]`.
- Back: `/private/tmp/replayxi-low113-runtime-render-01/2528D870-B690-4ED8-AF7C-E19EBEC75F09.png`; data `D937DC77-4401-4A7B-8555-676429990256.json`. 9,705 pixels; bounds `[224, 131, 300, 388]`.

Those images came from `/private/tmp/replayxi-parallel102-114-full-01.xcresult`: the runtime render passed, while the run had one separate corrupt-bundle fixture failure. After that fixture correction, `/private/tmp/replayxi-parallel102-114-full-02.xcresult` and `.log` are clean: **883 total, 882 passed, 1 optional skip, 0 failures**, including all four current Loop 104 cases. Release verification remains parent-owned.

## Receipts

- Initial calibration refusal: `/private/tmp/replayxi-render104-skin105-optimised-01.xcresult` and `.log`. No PNG/ avatar was emitted.
- Bounded comparison: `/private/tmp/replayxi-render104-scene107-optimised-01.xcresult` and `.log`. Two descriptor-readback assertions failed; the colour evidence above was retained in `/private/tmp/replayxi-render104-tonemap-01/ED9113AC-73DA-4955-8A91-04D465E9FEA2.json`.
- Corrected targeted batch: `/private/tmp/replayxi-render104-scene107-optimised-02.xcresult` and `.log`: **3 passed**, including both Loop 104 tests and the separate Loop 107 diagnostic. Optimised Swift, DEBUG/testability retained.
- Calibration: `/private/tmp/replayxi-render104-verified-01/ED5FB28E-C512-459F-A00B-B4C05EEB3948.json`.
- Swatches: `/private/tmp/replayxi-render104-verified-01/63E9FA13-DA43-4DB0-B9CE-BC9DBCBAF3A4.png`.
- Avatar data: `/private/tmp/replayxi-render104-verified-01/5064B5E1-8B66-4188-8CA5-330EACAD724D.json`.
- Avatar PNG: `/private/tmp/replayxi-render104-verified-01/17BB63AD-4B17-488E-8080-2AFC1BB4CC8A.png`.

Simulator logs also contain unsupported shader-pipeline messages. They occurred concurrently; they are **not** established as the cause of the initial colour mismatch. No tolerances were widened, and no screenshot colour or row repair was used to hide a product defect. Full-suite/Release verification remains parent-owned.
