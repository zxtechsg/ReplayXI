# Head attachment and player numbers — 176

## Confirmed causes

- The licensed near/far head ends in a sloping open neck. Its rear edge sat about 38 mm above the far shirt collar. The old test checked only the lowest front vertices, missing the rear gap.
- Tripo jersey ink used the old seven-segment mesh bounds despite switching to a square font texture. This shifted `1`/`11` sideways and squeezed `1`. The shared 77%-of-height anchor also put ink too close to each body's collar.
- Identity tags reserved an oversized card and a fixed head envelope. Selected Table tags could sit above 3 m. Authored player-label cards had a separate fixed-height path.

## Repairs

- Derive and cache a neck skirt for each admitted near/far head. Only the 22-point lower opening changes. Skull/face vertices, UVs, triangle count, gaze pivots and header contact bounds stay unchanged. No extra draw or per-frame mesh rebuild.
- Keep Tripo A/B heads at their original positions: native front/side/rear checks did not reproduce a gap in those active skins. The existing A bridge remains.
- Project jersey ink through a centred square canvas, lower it against each body's collar, and retain the original shirt triangles and skin weights.
- Place visible tag bottoms 7 cm above the posed crown. Cache glyph/card bounds once; use bounded existing skull probes or eight cached head-box corners. Reduce the selected Table tag scale.
- Apply the same crown clearance to authored player labels, including selected outlines and their tethers. Other annotation types retain their placement.

## Evidence

- `replayxi176-placement02.xcresult`: 1 passed; 12 native A/B near/low front, side and rear captures. Shirt `3` is lower and centred.
- `replayxi176-crown04.xcresult`: 2 passed. Reduced crown queries match independently skinned full-head vertices within 2 cm across both bodies/LODs, movement, crouching, scaling and reverse seeks.
- `replayxi176-neckvisual05.xcresult`: 1 passed; 8 matched raw/repaired near/far rear views. The original rear gap is visible and the repaired neck joins the collar without moving the skull.
- `replayxi176-regression06.xcresult`: 79 passed; one old near-neck depth assertion failed after the hidden skirt was extended. Its replacement checks the whole lower ring, not only the front minimum.
- `replayxi176-headverified07.xcresult`: 9 passed after that test correction, including source-asset admission, near-head checks and before/after renders.
- `replayxi176-labelverified08.xcresult`: 58 passed after the authored-label fix. Covers actual opaque jersey ink on both bodies/LODs, label clearance and picking, selection, tethers, keyframed annotations, paused write counts, cache lifecycle and native `1`/`11` renders.
- Latest Player POV demo launched in the dedicated simulator. Its screenshot shows tags close above the players and the lowered shirt `7` (`/private/tmp/replayxi176-final-demo.png`).

Initial checks also caught micrometre-level transform recomposition differences in exact seek assertions. Seek comparisons now use a 10 µm tolerance; paused write-count checks remain strict.

## Limits

The imported bodies still have source cloth/shoulder defects. Player A has measured holes within the numeral area; independent triangle checks distinguish absent source cloth from a missing decal and require every valid cloth sample to carry ink. These changes do not repair that topology. Both teams use the same corrected code paths, but this is not a claim of new body assets or higher-fidelity motion capture.

The physical Vision Pro was unavailable in the device check. Native rendering and tests here use the dedicated visionOS 26.5 simulator, not headset comfort or FPS measurements. No paid asset jobs or remote uploads were used. User signing/project and Info.plist edits are preserved.
