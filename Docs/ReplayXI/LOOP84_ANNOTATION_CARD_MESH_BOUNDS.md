# Loop 84 — 3D annotation text stays inside its card

## Native reproduction

The card width was estimated from character count, while the actual text used proportional 3D glyphs and was uppercased. These are not equivalent: a 22-character wide label produced a 2.482 m glyph mesh on a 1.936 m card. Valid text that expands when uppercased could exceed the card further. The live match path also overflowed after its existing 22-character compaction.

`/private/tmp/replayxi-parallel80-84-mixed-01.xcresult` reproduced four failing cases with 17 assertions. Wide text and uppercase expansion extended beyond the board. One common-label assertion concerned a tight accent-side margin, **not** text extending outside the board. Other normal labels fit.

## Change

The existing native glyph mesh is measured once at card construction. Cards grow to fit within the existing 3.20 m maximum. Normal and wide ASCII text keep the same font size; only text exceeding that bound is uniformly scaled to fit. The existing card mesh, font, material count, truncation and stored coach text are unchanged.

The measured width is cached as an entity component and reused by its collision box and selection outline. Scene updates perform a constant-time metadata lookup, not text measurement. Hit names, input ownership, annotation timestamps, tracking and save formats are unchanged.

## Validation

- First post-fix run: `/private/tmp/replayxi-parallel83-84-mixed-01.xcresult`.
- All four original label cases passed without changing their tolerances. Existing scene-budget and spatial-focus cases also passed. That mixed run's two failures were the separate pre-fix Loop83 UI metrics.
- All six label cases passed in `/private/tmp/replayxi-parallel83-85-mixed-01.xcresult`, including collision-box/selection-outline alignment, card reuse across seeks, full-size wide ASCII, and bounded uniform scaling for uppercase expansion. That mixed run's four failures were the separate pre-fix Loop85 route checks. The later full native suite and Release pass: see `VERIFIED_BATCH_78_87_2026-09-17.md`.

This verifies actual native mesh bounds and scene transforms. It does not establish headset readability or rendered hover feedback. No assets or textures were regenerated.
