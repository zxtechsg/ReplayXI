# Loop 91 — Draw tool label budgets

## Measurement plan

Both the drawing shelf and compact annotation strip use the same Run, Pass, Press, Zone and Label buttons. Their labels have fixed 70 × 48 pt frames, a headline SF symbol and an unshrunk monospaced caption2. Measure their actual platform font/symbol bounds at all 12 Dynamic Type categories before changing sizing.

The probe covers 60 labels, full requested width/height, a default-size control and live source wiring. It is not a SwiftUI screenshot or proof of headset comfort.

## Native evidence

`/private/tmp/replayxi-parallel88-91-repro-01.xcresult` reproduces two failing label cases with 26 assertions: 22 height misses and four width misses. The default-size, diagnostic and source checks pass. The largest measured tool stack is 78.027 pt against 48 pt available; widest caption is 80.361 pt against 70 pt. All misses are at accessibility sizes.

An additional instruction probe in `/private/tmp/replayxi-parallel88-91-mixed-02.xcresult` produces six width assertions in one case. Even omitting the Label gap and allowing its symbol to shrink, `PINCH END · OR TAP` needs 257.891 pt at the largest text size, against its 190 pt frame. `RELEASE TO SAVE` also misses. All regular-size instruction lower bounds fit. That mixed run has 27 cases, 22 passes and five expected pre-fix failures (three in this loop, two in the far-player floor checks).

Native label attachment: `/private/tmp/replayxi-draw91-before-01/27F65510-E53B-4081-9E1D-5420ADE576BB.json`.

## Change

Accessibility tools use 88 pt label width and an 84 pt minimum height, preserving the full requested font. Both drawing surfaces move their instruction above the shared five-tool row. The active row keeps Cancel, time and Edit reachable. Regular sizing and the single-row arrangement remain unchanged. All tool actions, draft state, gesture ownership and the room anchor are unchanged.

The same five button definitions now serve both surfaces. No duplicate actions or new drawing state are introduced. Post-fix checks add normal-policy preservation, room-allocation checks for every preset, and live shared-layout wiring. All eight cases pass in `/private/tmp/replayxi-parallel89-92-mixed-01.xcresult`; all ten Shape workspace cases also pass there. That mixed run includes three failures in the separate far-player/Tools work and is not a clean full-suite receipt. Full native/Release verification is pending.

Font and symbol bounds are measured. The 48 pt native-style allowance and row allocations are conservative budgets, not a rendered layout or a headset test.
