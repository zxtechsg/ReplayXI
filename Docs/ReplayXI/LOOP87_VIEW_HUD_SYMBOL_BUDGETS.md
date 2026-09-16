# Loop 87 — View HUD symbol sizing

## Native measurements

Receipt: `/private/tmp/replayxi-parallel85-87-mixed-01.xcresult`. The five-case HUD probe measured all 12 Dynamic Type categories. Header-frame checks failed 12 assertions and badge-circle checks failed 10; the diagnostic, expanded-row lower-bound and source checks passed. The mixed run had 15 passes and these two failures.

The Tactical icon first exceeds its 34 pt frame at regular XXXL: 36 pt. At AX5 it needs 58 pt. The largest overlay badge, ball highlight, needs 37 pt against its 28 pt circle. All header icon heights fit the existing 60 pt height; the chevrons fit their 34 pt width.

These are measured image-budget misses, not screenshots or proof that SwiftUI clips the glyphs. Expanded controls use minimum heights and may grow. Their unpadded width lower bounds fit; this does not measure system button padding or Label spacing.

## Fix

The live symbol policy gives mode icons 40 pt width at regular sizes and 64 pt at AX sizes. Chevron frames remain 34 pt. Badge circles stay 28 pt regular and become 40 pt at AX sizes. Regular mode frames are therefore 6 pt wider, not unchanged.

The complete collapsed header, including three badges, unwrapped eyebrow, title, exact gaps and minimum spacer, needs at most 372.087 pt regular and 534.084 pt AX. The smallest available widths are 478 pt and 578 pt. All room presets fit without changing the attachment width or anchor. The same three camera choices, overlay actions and gesture gates remain intact.

## Validation

Six updated tests use the live sizing policy, unchanged native metric tolerances and full-header width budgets across every preset. Source parse and whitespace checks pass. All six pass in the full native run; the Release build also passes. See `VERIFIED_BATCH_78_87_2026-09-17.md`.

Desktop locked: no interactive, screenshot, VoiceOver or headset-fit claim. UIFont/CoreText and configured UIKit SF-symbol sizes are native budgets, not a SwiftUI render.
