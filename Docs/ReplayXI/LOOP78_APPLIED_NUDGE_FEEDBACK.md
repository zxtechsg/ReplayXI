# Loop 78 — Actual distance for annotation nudges

## Issue and fix

An accessibility quarter-metre step near a touchline could report more movement than occurred. For example, moving a run endpoint right from x = 33.9 m stops at 34 m: about 0.10 m, not the requested 0.25 m. Visible feedback and the joystick's accessibility announcement both used the requested distance.

A small UI adapter now samples the live mark's presented geometry before and after the existing atomic Store action. It returns the selected endpoint's actual delta. Both feedback paths consume that result. Player-bound marks are measured at the same current replay time, rather than from their authored coordinates.

Store contracts, clamping, rejection, playback pause, saved data and Undo behavior are unchanged. A rejected or zero-movement action returns no success feedback. Normal quarter-metre controls still use the same command.

## Validation

- The adapter was first extracted with the original requested-delta behavior and wired into both UI paths. This enabled native behavioral reproduction without duplicating the private UI callback in tests.
- Pre-fix receipt: `/private/tmp/replayxi-parallel78-80-repro-01.xcresult`. Exactly 2 behavioral cases failed with 16 assertions; all 7 controls passed.
- The 9-case class covers partial cardinal and diagonal clamping for runs/spaces and both endpoints; zero movement; minimum-size rejection; player-bound marks after a seek; normal quarter steps, one broadcast and exact Undo; held timeline ownership; missing marks; and shared UI wiring. Exact test tolerances were not changed for the fix.
- All 9 post-fix cases pass in `/private/tmp/replayxi-parallel78-82-mixed-01.xcresult`. That mixed bundle also contains separate pre-fix Loop80/82 failures, so it is not a clean full-suite result. The later full native suite and Release pass: see `VERIFIED_BATCH_78_87_2026-09-17.md`. Source parse and whitespace checks pass.

Native tests exercise the actual UI adapter and Store. Wiring assertions do not execute private SwiftUI callbacks. The desktop was locked, so no interactive or VoiceOver-use QA is claimed.
