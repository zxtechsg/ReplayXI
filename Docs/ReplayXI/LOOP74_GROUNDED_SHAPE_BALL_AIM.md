# Loop 74 — Shape players aim at the presented ball height

## Reproduced mismatch

Problem and Ideal place the ball beside the displayed source player and keep its physical centre at **0.11 m**. Its enlarged marker centre is **0.198 m**; that visual enlargement is not a loft.

Player animation already used the presented X/Z position, but still used the replay's raw loft: **0.28 m at 14.15 s** and **0.85 m at 25.4 s**. Both procedural and skinned players consume that aim target.

A read-only evaluation of the existing `lookPose` source measured an Ideal winger difference of **0.772° neck pitch + 1.499° head pitch** at 25.4 s when using the grounded reference. Yaw was unchanged. The nearby source player's pitch was already clamped, so its difference was zero. These are bounded presentation differences, not measured human eye tracking or an anatomical claim.

## Regression coverage

`ReplayShapeBallAimPresentationTests` checks actual scene neck/head rotations for:

- Procedural and skinned Problem/Ideal players at 14.15 → 25.4 → 14.15 s.
- Exact return after rewind and Problem → Ideal → Problem.
- Unchanged raw-loft aim in Table, Touchline and first-person views after leaving Shape.
- Unchanged authored ball tracks.

Reference height is recovered from the scene marker after removing its radius enlargement. JSON attachments retain per-joint angular differences.

The production change shares Shape's physical ball-height sample with its aim target and visible ball/shadow. Match aim still uses its raw recorded loft. Camera/free-look, animation policy and assets are unchanged. The five earlier Shape animation references now use the grounded 0.11 m target; their exact pose assertions remain intact.

## Verification

- Pre-fix actual-scene tests: both Shape cases failed with **92 assertions**; both match-loft controls passed. Receipt: `/private/tmp/replayxi-parallel74-77-repro-01.xcresult` (and same-stem log).
- Actual procedural and skin neck/head rotations differed from the grounded reference; failures were isolated to aim, while the rewind and unmodified-track assertions passed.
- Post-fix targeted batch: **39 passed, zero failures**, including all four new ball-aim cases and the five existing Shape animation cases. Receipt: `/private/tmp/replayxi-parallel74-75-77-fixed-01.xcresult`.
- Final full native suite: **675 passed, 1 optional skip, 0 failed** (676 total),
  `/private/tmp/replayxi-parallel77-full-01.xcresult`.
- Unsigned device Release: **BUILD SUCCEEDED**,
  `/private/tmp/replayxi-parallel77-release-01.log`. No headset validation is claimed.
