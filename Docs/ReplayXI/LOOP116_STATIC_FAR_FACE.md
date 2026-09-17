# Loop116 — static far face integration

## Change

`ReplayFarAthleteHeadProvider` admits the Loop114 static MIT face for the
procedural far rig. It does not add a skeleton, change motion or raise the
skinned-player cap. Near and mid head selection stays unchanged.

The new resource is `ReplayXIFarAthleteHead.usdz`,540,760 bytes, SHA256
`0e8f602695ca0cca505a462db1e8f6a318b8aa72dcd914e0fcce2986bff3d1ce`.
Loop114 records its source licence, rejected first candidate, exact native
admission and matched source/candidate images.

Explicit prewarm checks file size/hash, one imported model/material, one
identity mesh instance referencing that model,486 vertices/749 triangles,
complete finite vertex attributes, index bounds and expected local bounds.
It requires no skeleton, joints or animations and publishes the mesh only
after all checks pass. Failed asset preparation is memoized. Missing shared
palettes do not consume the asset attempt.

`make` reuses the existing five prepared skin/normal materials and the single
cached mesh. It performs no file or texture loads. Prewarm's `Entity.load` may
transiently decode the asset's embedded maps; no zero-decoding or zero-memory-
cost claim is made for setup.

The textured head keeps the existing `head`/`head-root`/`neck` hierarchy,
local head-root Y0.125 m and mesh X scale1.07. If preparation fails, or shared
palettes are unavailable, the old far ellipsoid at Y0.170 m remains available.
The builder never starts asset preparation itself. Root-owned dashboard warm
wiring and resource accounting are separate from this provider change.

Verified far-rig budget is820 vertices/1,225 triangles across seven model
entities, within the unchanged1,800/2,500/seven limits. The fallback remains
399/574/seven. Native tests verify actual mesh counts, not just these constants.
There is no added skeletal contact work; the existing cached leg support and
deterministic authored joint animation stay in place.

## Verification

`ReplayFarAthleteHeadTests` has eight cases covering:

- Cold setup fallback without hidden asset loads.
- Dependency ordering, shared mesh/material identities and palette recovery.
- One-attempt failed-load memo and unchanged fallback.
- Wrong-size and changed-byte rejection.
- Actual geometry, instance and hierarchy limits.
- Exact unchanged near/mid meshes, transforms and metrics.
- Gaze, exact reverse/repeat poses, collar contact and other joint/floor parity.
- Calibrated full-body native previews for idle, jog and two sprint samples,
  with matched old-face fallback and new-face images.

The class resets both new and existing head caches in setup/teardown to avoid
order-dependent activation of old fallback fixtures. All eight tests pass in
`/private/tmp/replayxi-ui115-before-head116-01.xcresult`. The mixed batch has
15 cases:12 passed and three expected Loop115 pre-fix failures. This is not a
clean whole-app-suite claim. Source parse and whitespace checks also pass.

Four actual full-body native PNGs and frame reports are in
`/private/tmp/replayxi-head116-native-01/`; its manifest maps pose names to
exported filenames. Calibration is Display P3, top-first rows, maximum channel
error1. All four images were inspected: the face/hair and head direction are
readable, the neck meets the shirt, and the body, kit regions and feet match
the baseline. The new anatomical head is smaller in silhouette than the old
ellipsoid; the remaining rigid far-body simplification is still clear.

| Time | Fallback foreground pixels | Face foreground pixels | Face bounds, pixels |
| --- | ---: | ---: | --- |
|10 s |13,776 |13,374 |220,115–295,387 |
|12.1 s |13,512 |13,313 |214,117–295,388 |

Both face frames contain seven model entities and actual820/1,225 geometry;
the matched fallback remains seven/399/574. No frame is empty or clipped.
These two native images plus the collar/seek checks do not cover every pose,
skin tone or headset viewing condition.

### Extended running controls

The first two previews did not show a strong stride, so the same render and
joint/floor/collar test was extended with the exact Loop94 running fixtures.
The original cases and assertions remain. All eight Loop116 tests pass again
in `/private/tmp/replayxi-ui115-after-head116-02.xcresult`; all18 cases in that
mixed run pass, including seven Loop115 and three scene controls.

The eight matched PNGs and new player-ID/speed/state metadata are exported to
`/private/tmp/replayxi-head116-native-02/`. Calibration again reports Display
P3, top-first rows, maximum error1. The four added running PNGs were inspected:
necklines remain attached through the sampled body lean/head turns, no scalp
slit is visible, and the limbs, kit regions and boots match their fallback
counterparts. Root's independent visual review accepts the same frames.

| Player/time | Sampled speed | App gait state | Fallback/face foreground pixels |
| --- | ---: | --- | ---: |
| navy-rw10 s |0 m/s |idle |13,776/13,374 |
| navy-rw12.1 s |2.475 m/s |jog |13,512/13,313 |
| navy-rb11.691667 s |5.296 m/s |sprint |12,697/12,322 |
| red-lw14.083333 s |4.730 m/s |sprint |14,049/13,623 |

These are the app's sampled gait classifications, not measured human running
data. Full-suite/Release and root-owned cold-warm checks remain separate from
this targeted receipt. No further asset refinement is included in Loop116.

## Limits

This is a simplified far face, not facial animation or near-detail fidelity.
The same rigid far limbs remain. Actual headset FPS, frame timing and live
visual comfort need device QA; these tests do not supply those results.
