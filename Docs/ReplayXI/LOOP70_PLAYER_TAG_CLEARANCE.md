# Loop 70 — Keep jersey tags above review-sized players

## Reproduced

Touchline and Shape tags stayed at 2.16 m while their bodies were enlarged.
Selected tabletop tags could also cut through taller heads, especially in the
lower home-team number band.

The native geometry check found Shape tag bottoms at **1.723–1.815 m**, while
sampled head tops reached **6.437 m** after review scaling. A selected table
right-back's tag bottom was **5.297 m**, below his **6.150 m** head top.

Pre-fix receipt:
`/private/tmp/replayxi-parallel68-70-71-repro-fixed66-67-69-01.xcresult`

The three affected-view tests failed (233 assertions); the unchanged POV
distance-band/hide-wearer control passed. These are actual native scene bounds,
not a rendered screenshot or a headset comfort measurement.

## Change

One shared focus-scale policy now feeds both body sizing and label clearance.
It retains the existing avatar scales. Review tags reserve a stable, conservative
2.30 m head envelope before focus scaling, their lower card half and 0.10 m of
clearance. Existing team/number lanes remain a minimum, not a clipping height.

Labels do not query visual bounds or follow head animation each frame. POV tag
heights/scales, player geometry, X/Z positions, hit-target geometry, rendering limits,
physical-drill hiding and saved data are unchanged. The envelope is a visual
allowance for bundled rigs, not a claim about a player's real height.

## Verification

All six post-fix cases passed in
`/private/tmp/replayxi-parallel71-fixed-01.xcresult`. The combined run had
164 passes and one unrelated ball-height fixture rounding failure.

Coverage checks every grounded near/far procedural head across 22 players and
the 32-second clip at 0.25-second steps (**5,676 poses**), plus stable tag heights
through time and view changes. The main existing replay tests also passed with
their tag-height expectation updated to the new clearance policy.

Existing offline full-skin reports from Shape 62, Gaze 61 and Arms 54 contain
22 sampled poses. The largest upper mesh bound, with the maximum 1.035 appearance
height scale, is **1.892117 m**: 0.407883 m below the allowance. These samples
support the skinned envelope but do not certify every possible skin animation.
No source mesh, pose or old render was changed for this check.

The final full suite passed: **656 passed, 1 optional skip, 0 failed** in
`/private/tmp/replayxi-parallel73-full-03.xcresult`. The unsigned device Release
build also passed in `/private/tmp/replayxi-parallel73-release-01.log`.

No unlocked Simulator or physical-headset visual pass is claimed.
