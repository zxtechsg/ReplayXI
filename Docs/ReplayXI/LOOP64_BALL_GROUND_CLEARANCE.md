# Loop 64 — Ball ground clearance

## Fixed defects

The ball was enlarged for distant review views but kept the original 0.11 m centre height. Its nominal radius increased while its centre did not, burying the lower portion in the pitch.

The positional view intentionally grounds its ball, but its shadow still expanded from the hidden replay ball's airborne height.

## Bounded change

The ball block in `PitchSceneFactory` now:

1. Resolves presented physical height: at least 0.11 m for match views; exactly 0.11 m for positional view.
2. Adds the visual radius increase, `0.11 × (scale − 1)`, to its centre.
3. Computes shadow lift from the same presented height, excluding visual enlargement.

Telemetry, player look target, ball X/Z, ball rotation, view scales, assets, materials, annotations and athlete logic are unchanged. The ball provider only gains a DEBUG cache reset for isolated fallback/Blender tests.

## Evidence

Pre-fix native regression: **3 failed, 1 passed**. Ground/loft/shadow assertions failed; exact repeat/seek passed.

`/private/tmp/replayxi-ball64-repro-01.xcresult`

Post-fix native run: **all 4 ball tests passed**, plus **5 Shape tests**, no failures.

`/private/tmp/replayxi-ball64-fixed-01.xcresult`

Tests explicitly confirm the procedural fallback and prewarmed Blender asset, preventing test-order-dependent coverage. They sample four view scales at 13.6 s and 14.15 s, then verify repeat/seek and view-switch transforms without modifying the source track.

### Grounded ball, 13.6 s

All values below use pitch-local metres. Before depths are derived directly from the old centre and nominal scaled radius; after values come from native exports for both meshes.

| View | Visual scale | Before nominal bottom | After centre | After nominal bottom |
| --- | ---: | ---: | ---: | ---: |
| Player POV | 1.0 | 0 | 0.110 | 0 |
| Tactical table | 3.2 | −0.242 | 0.352 | 0 |
| Touchline | 1.5 | −0.055 | 0.165 | 0 |
| Positional | 1.8 | −0.088 | 0.198 | Approximately 0 |

The largest remaining floating-point difference is 0.000000015 m. Blender geometry bounds agree with those values. The procedural fallback has raised decorative panels extending 1 mm beyond the sphere, or 3.2 mm at maximum visual scale; tests separately allow that existing geometry detail.

### Lofted ball, 14.15 s

The authored centre is 0.28 m. All three match views now preserve its **0.17 m bottom clearance**. Native centres are 0.280 m, 0.522 m and 0.335 m for Player POV, table and touchline. Their shadow spread remains driven by 0.17 m physical lift.

Positional view remains grounded at centre 0.198 m after enlargement. Its shadow X scale is **1.8**, not the old source-derived 1.84896. The view no longer shows a lofted-ball shadow under a grounded marker.

### Native export files

- Procedural ground: `/private/tmp/replayxi-ball64-after-procedural/09B877DF-E4CF-4AFB-88B5-CD73AD47F141.json`
- Blender ground: `/private/tmp/replayxi-ball64-after-blender/B3FE78A3-5AAB-43A1-A982-903E67E793ED.json`
- Both meshes, loft: `/private/tmp/replayxi-ball64-after-loft/8BF9EC38-2014-4CA6-9C54-8C2F2080B55C.json`

These contain all 16 samples, including centre, scale, nominal bottom, local-geometry bound and actual/expected shadow scale. Geometry bounds are inspected in ball-local axes before scaling; rotating a sphere's bounding box would overestimate its occupied radius.

## Limits

No live headset, unlocked Simulator UI or new Blender render was used in this batch. This is a presentation correction, not a ball physics change. The separate fixed-rate rolling-spin issue is not changed or claimed fixed here. Full native suite: **606 passed, 1 optional skip, 0 failed**. Device Release build passed. See [batch verification](VERIFIED_BATCH_58_65_2026-09-17.md).
