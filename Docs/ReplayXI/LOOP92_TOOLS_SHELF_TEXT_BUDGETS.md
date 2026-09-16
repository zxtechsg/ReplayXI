# Loop 92 — Tools shelf text budgets

## Measured issue

Tools offered Timeline, Decisions, Settings, Reviews and Edit marks as horizontal labels in fixed 126/132/126/126/124 pt frames, all 60 pt high. The first four had no permitted text shrink; Edit permitted 0.78. The shelf heading could wrap and was not treated as a clipping defect.

Receipt: `/private/tmp/replayxi-parallel89-92-mixed-01.xcresult`. One width case failed 15 assertions; all four controls passed, including all regular text sizes and every horizontal-label height. At AX5, full text + symbol widths were 166.265, 188.886, 163.968, 144.557 and 193.487 pt respectively. Edit still needed 150.920 pt at its most generous 0.78 scale versus 124 pt available.

The initial five-case `PlaybackToolsShelfTextMetricsTests` probe used the actual subheadline black/bold fonts and configured SF symbols at all 12 Dynamic Type sizes. Width checks omitted both Label spacing and native button padding. Edit's hard lower bound even scaled its symbol as well as its text, avoiding an assumption about SwiftUI's scale propagation.

## Bounded fix

AX choices use 208 pt labels with a 60 pt minimum height and no shrinking. This covers the largest 193.487 pt native content plus a 12 pt Label-gap allowance. The AX header is separate; its 148 pt title frame covers the measured 139.778 pt heading. A grid minimum of 256 pt per cell includes a 48 pt button-style allowance. Four cells and three 10 pt gaps allocate 1054 pt against 1316 pt available; five require 1320 pt, so the last choice wraps.

Normal row order, fixed label frames, header width and Edit's allowed scale remain unchanged. Both layouts share the original actions and disabled states. Compact Edit buttons elsewhere are untouched. No deck size or room-placement change was made.

## Validation limits

Seven updated tests use the live policy, retain the native measurement tolerances, check normal dimensions and cover AX full-size labels and grid allocation at every preset. All seven passed in `/private/tmp/replayxi-parallel88-94-mixed-01.xcresult`. That mixed run had 52 passes and one unrelated exact-rewind failure; it was not a clean full-suite result. Full suite and Release: pending.

The gap/style allowances are allocation reserves, not rendered measurements. Regular label budgets fit, but this does not prove the complete normal row fits any assumed button padding. The JSON attachment records native text/symbol bounds, not rendered SwiftUI geometry.

Desktop locked: no screenshot, interactive, VoiceOver or headset-fit claim. Source parse and whitespace checks pass.
