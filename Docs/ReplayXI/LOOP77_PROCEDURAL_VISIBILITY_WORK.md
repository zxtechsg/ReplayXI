# Loop 77 — Transition-only procedural mesh visibility

## Measured work

The scene recursively rewrote every procedural model's visibility each update,
even when the same skin or procedural body remained selected. Native counters
found the following repeated work after the first presentation:

| Stable presentation | Hierarchy visits | Model enable writes |
| --- | ---: | ---: |
| One procedural subject | 47 | 29 |
| One skinned subject | 42 | 24 |
| Skinned impact with query marker | 43 | 24 |
| Two POV neighbours | 84 | 48 |
| Four Shape subjects | 168 | 96 |

Pre-fix receipt: `/private/tmp/replayxi-parallel74-77-repro-01.xcresult`.
All five work-count cases failed with 32 assertions. Their actual visibility,
model-identity, query-joint and transition controls passed. Other classes in the
same bundle intentionally tested separate pre-fix defects.

## Change

One Bool component on each procedural rig records its last requested visibility.
Only an initial application or skin/procedural transition walks its model tree.
No global cache, additional entity, asset changes or pose caching is introduced.

The rig's model hierarchy is built synchronously and does not change during
playback. Impact adds/removes a non-rendering query marker and physics components.
Imported/skinned visuals are siblings, not procedural descendants. This helper
is the only production writer of procedural model enable bits. The rig root's
own enable state remains independent, so hidden query joints can still animate.

The tests check repeated and reversed time, active impacts, Problem/Ideal changes,
POV neighbours, new roots, skin removal and later return. Model identities are
rechecked through impact. Counters are DEBUG-only and absent from Release.

## Verification and limits

All five post-fix cases passed in
`/private/tmp/replayxi-parallel74-75-77-fixed-01.xcresult`: **39 passed, 0 failed**
including existing Shape, skinned-motion, impact and action-sampling controls.
Every stable presentation above now records **0 hierarchy visits and 0 model
enable writes**; admission/restoration transitions still apply the correct bits.
The full native suite passed: **675 passed, 1 optional skip, 0 failed** (676 total)
in `/private/tmp/replayxi-parallel77-full-01.xcresult`. The unsigned device Release
also passed in `/private/tmp/replayxi-parallel77-release-01.log`.
This is a work-count improvement,
not a measured headset FPS gain. The optional legacy imported-skin feature gate
is disabled in this test run; its restore path uses the same helper but is not
claimed as runtime-tested here. No interactive UI or headset check is claimed.
