# Loop 101 — touchline annotation persistence

## Reproduced failure

In Eleven Eyes at 15.6 s, draw a Run from the right-back (`navy-rb`, 30.8 / 32.7) to the opposite touchline (-34 / 35). The Store accepted the mark, but its generated Float offset reconstructed the endpoint at -34.000004. Strict saved-review bounds then rejected the whole review and autosave, leaving only the earlier valid save after relaunch.

Native pre-fix receipt: `/private/tmp/replayxi-parallel96-101-target-01.xcresult` and matching `.log`. The touchline case failed seven assertions across bounds, validation, save, autosave and disk relaunch. Three controls passed: an interior run, rejected off-pitch drawing, and rejected invalid imported anchors.

## Bounded correction

Local anchor writers now share one offset helper. Only when finite, in-pitch source and destination coordinates reconstruct outside the pitch does it move the generated offset one representable Float step inward. The candidate must reconstruct inside the original strict boundary. Ordinary offsets are unchanged. Draw, preset, tracking and handle-edit paths use the same representation.

The stored fallback endpoint, player identity, timestamp and saved schema are unchanged. No epsilon is added to import validation; the original outward-rounded imported anchor remains invalid. A final validity gate also prevents a newly generated invalid mark from being appended and blocking every later save.

## Regression coverage

The original four cases are unchanged. Additional cases cover all four edge midpoints and corners from all 22 players at five replay times, ordinary offsets for both teams, and direct-edit / Follow routes at the touchline. They check strict bounds, unchanged fallback points and timing, and at most one inward Float step. These are deterministic native correctness tests, not headset or performance claims.

Full native receipt: `/private/tmp/replayxi-parallel96-101-full-01.xcresult` has 838 tests, 837 passed, one optional skip and zero failures. All seven Loop 101 cases pass, including 880 edge/corner draws and 66 ordinary-offset checks; existing impact and Ideal-shape alignment cases also pass. Unsigned device Release succeeded in `/private/tmp/replayxi-parallel96-101-release-01.log`. No physical-headset validation was performed.
