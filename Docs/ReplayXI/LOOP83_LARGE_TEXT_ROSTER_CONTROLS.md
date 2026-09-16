# Loop 83 — Large-text roster and entry controls

## Native measurements

Receipt: `/private/tmp/replayxi-parallel83-84-mixed-01.xcresult`. The 5-case probe measured all 12 Dynamic Type categories. Two cases failed with 12 assertions: 11 compact-control budget misses and one full-size roster-height miss; three controls passed.

At AX5, the original 60 pt compact height was smaller than the measured minimum stacks: POV 74.4424 pt, Tools 71.0273 pt, Draw 79.0273 pt. The POV label still needed 131.7926 pt at its allowed 0.82 scale versus 116 pt available; Tools needed 80.3613 pt versus 78 pt. Full-size POV text needed 160.7227 pt and its full stack needed 80.0273 pt.

Roster number + role lines needed 65.6348 pt at AX5 versus 60 pt. Its allowed role shrinking could fit 57.8779 pt, so that finding is a full-size accessibility improvement, not proof of unavoidable clipping.

## Fix

An AX-only label policy gives POV 168 pt width, Tools 88 pt and Draw its unchanged 76 pt width. All three use minimum 88 pt height. Roster cells keep their 72 pt width and use minimum 72 pt height. AX labels no longer rely on shrinking; regular dimensions and permitted scales are unchanged. Entry actions, selection and gesture barriers are untouched.

The worst-case AX coach row allocates 1328 pt against 1336 pt available at every deck preset. This includes the existing 230 pt timeline, row gaps and a 48 pt style allowance for each of eight buttons. Both complete roster rows fit; AX control growth stays within the existing deck-width increase. No room-placement or deck-width changes were needed.

## Validation limits

The updated 7-case class checks the live layout policy, exact font/symbol metrics, full-size AX labels, unchanged regular controls and row width allocations. No font tolerances were relaxed. Source parse and whitespace checks pass. All 7 post-fix cases passed in `/private/tmp/replayxi-parallel83-85-mixed-01.xcresult`; that mixed run also contains expected Loop 85 pre-fix failures. The later full native suite and Release pass: see `VERIFIED_BATCH_78_87_2026-09-17.md`.

UIFont/CoreText and configured UIKit SF-symbol sizes are native size budgets, not a SwiftUI render. The button-style allowance is not a measured pixel bound. Desktop locked: no interactive, screenshot or headset-fit claim.
