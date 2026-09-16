# Loop 95 — Compact Speed font budgets

## Scope and contracts

The main Speed button is not a secondary rate choice: it uses headline monospaced-digit bold for the rate and caption semibold for “Speed.” The measured button had a 1 pt line gap, a fixed 74 × 60 pt frame and an allowed 0.8 text scale.

The five-case `PlaybackCompactSpeedTextMetricsTests` probe measures all seven live rates and the caption across all 12 Dynamic Type categories. Width checks use the allowed minimum scale. Height checks allow both text lines to shrink by the same permitted minimum, while keeping the VStack's 1 pt gap. Full-size misses alone are diagnostic, not declared defects. Separate controls check the original dimensions and permitted scale at all regular sizes, and source-link the actual fonts, frame, scale, formatter and action.

## Native result and narrow fix

Receipt: `/private/tmp/replayxi-speed95-prefx-01.xcresult`. The width case failed two assertions: at AX5, `0.25×` and `0.75×` need 78.465625 pt even at the allowed 0.8 scale. All four controls passed, including permitted stack height and regular-size bounds. No height defect was found.

Speed now uses the existing primary-control layout policy: 80 pt at AX sizes, 74 pt regular. The font, allowed scale, fixed 60 pt height, seven rates, action and gesture gate are unchanged. No extra panel width, height or layout expansion was added.

Loop 83's main-row allocation now reads Speed's live width instead of a hard-coded 74. The updated AX row allocates 1334 pt against 1336 pt available at every preset, including the unchanged 230 pt timeline. This preserves the same conservative style reserve; it is not measured SwiftUI button padding.

The updated six-case Speed class checks the live policy, unchanged regular width and every AX main-row preset. Native metric tolerances are unchanged. All six pass in the clean full receipt `/private/tmp/replayxi-parallel88-95-full-02.xcresult` (789 passed, one optional skip, zero failures). Unsigned device Release also passes; see `VERIFIED_BATCH_88_95_2026-09-17.md`. Source parse and whitespace checks pass.

UIFont/CoreText budgets are necessary bounds, not proof of SwiftUI compression or final layout. Desktop locked: no screenshot, interactive, VoiceOver or headset-fit claim.
