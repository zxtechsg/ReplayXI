# Loop 120 — name a circular zone's actual controls

Repro: Draw → Zone → select its mark → Adjust. The second joystick says `CORNER`, its accessibility target says `opposite corner`, and quick actions say `Move arrow point`. The real zone is a circular ring: start is its centre; the distance to end sets its radius. It has neither an opposite corner nor an arrow.

UI-only fix: `CENTRE` / `EDGE`, corresponding accessibility names, quick actions and movement feedback. Directional marks retain their existing Start/Arrow tip language. No endpoint, clamp, timing, tracking, drawing or Undo behavior changes.

The baseline has two private-UI wiring cases and two actual Factory/Store geometry controls. The latter check circular ring origin/radius, mesh reuse, edge-only and centre-only movement, and exact Undo. Moving only the centre may change radius; this is not presented as translating the whole zone at a fixed size.

Native pre-fix receipt: `/private/tmp/replayxi-scene119-after-zone120-before-01.xcresult` (log uses the same stem). Both copy cases failed as expected; both real geometry/Undo controls passed. The combined run had 5 cases: 3 passed and these 2 failed.

The four tests are unchanged for the fix and all pass in `/private/tmp/replayxi-parallel115-120-full-01.xcresult`. Full integration: 914 total, 913 passed, 1 optional skipped, 0 failed. Syntax parsing passed. Unsigned device Release passed; see [batch receipts](VERIFIED_BATCH_115_120_2026-09-17.md). No interactive/headset QA claim while the desktop remains locked.
