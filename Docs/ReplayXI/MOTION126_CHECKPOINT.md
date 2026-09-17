# Motion and playback refinement — 17 September 2026

## Changes

- Removed a backward-travel angle seam that could snap gaze between opposite
  shoulder checks. Rearward travel now fades out of neck attention smoothly;
  the authored body heading still owns where the player faces.
- Bounded the **complete rendered head-to-chest rotation**, including imported
  animation plus procedural gaze. Soft limits approach 70° yaw, 40° pitch and
  22° roll, with smooth joins at 55°/25°/12°. These are presentation limits,
  not clinical claims. Ordinary poses remain unchanged.
- Near/low player rigs now consume the authored chest lean and counter-bank
  during the existing football-pose blend. Conversion uses the actual source
  skeleton's parent/rest frames. Save pitch is not applied twice; header aiming
  remains in its existing actual-rig solver. Zero-weight source running stays
  untouched.
- Fast-running boot/shin colliders now receive an extra root-motion budget.
  The old contact controller remains exact up to 8 m/s, blends smoothly from
  8–9 m/s, then separates root travel from local articulation. Full sprint mode
  bounds relative motion at 8 m/s and total motion at 20 m/s; the transition
  does not claim the same relative-speed bound.
- The existing previous/next playback icons jump to **actual recorded** passes,
  shots, headers and saves in the three native studies. They pause at contact,
  preserve POV and respect active editing. Legacy scenes keep their cue steps.
- Compact position labels preserve abbreviations such as RB/CM/CF and handle
  spacing/hyphen variants. Stored roles and reconstructed formations are not
  changed or reclassified.

No new assets, network features, camera motion or save schema were introduced.

## Evidence

The baseline diagnostic caught more than a 100° gaze jump across a 0.012°
change in backward-travel bearing. Actual near/low heads also reached 73.94°
relative to the chest even though the separately added gaze was bounded.
This does **not** show a literal 180° source animation; it identifies both the
angular discontinuity and the uncovered combined-rotation bound.

After correction, all 44 focused head, posture, arm, navigation and label tests
pass in `/private/tmp/replayxi-refine126-motion-01.xcresult`. The same actual-skin
sweep measures a 65.76° maximum chest-relative yaw. Exact rewind and ordinary
pose preservation are covered independently.

The first sprint-controller implementation accelerated a receiving boot and
broke the counterattack. It was rejected. The final candidate preserves the
existing ordinary-speed controller; source routes, contact gates and collision
participation were not changed to conceal that regression.

## Final verification

| Check | Result | Local receipt |
| --- | --- | --- |
| Full native suite | 1,072 XCTest cases, one optional skip, zero failures; both separate asset tests pass | `/private/tmp/replayxi-refine126-full-01.xcresult` |
| Complete plays | All 16 planned contacts admitted, no misses, all three finishes enter the goal | Same full-suite receipt |
| Python regression | 138 cases, 12 optional skips, zero failures | `/private/tmp/replayxi-refine126-python.log` |
| Unsigned device Release | Build succeeds | `/private/tmp/replayxi-refine126-device-release.log` |

Six calibrated native near/low renders were inspected: running with a lateral
ball glance, braking/cutting and backpedalling. Head and torso orientation is
coherent across both detail levels; limbs and frame bounds are intact. The cut
remains a stylised lean and the source run is still visibly limited. These are
512 px static audit frames, not mocap-quality motion or headset performance
evidence. Actual neck continuity, floor clearance and rewind have separate tests.
Frames and JSON are in `/private/tmp/replayxi-refine126-full-01-attachments/`;
the movement report is `B9DD9855-86D2-4252-8EBA-596822BACEB7.json`.

The simulator's saved-review collection and annotations match the previous
backup. Only the live autosave timestamp and playhead differ; no saves were
restored or overwritten. The latest Debug app was launched normally, without
in-memory demo flags, and its process was confirmed running. The Mac remained
locked at the final UI check, so that launch is not a visual interaction test.

No test thresholds, contact gates or study routes were relaxed to get this
checkpoint green. The new visual tests supplement, rather than replace, the
existing contact and scene checks.

## Remaining fidelity work

This is still procedural retargeting over existing idle/run clips, not FIFA/EA
motion matching or recovered match mocap. The three plays use authored positions
and facing intentions. Exact broadcast head/eye directions have not been
recovered. Better licensed motion clips, event-specific animation and reference
pose annotation are needed for a larger fidelity jump. Headset comfort,
hand-tracking and sustained hardware performance still need device testing.
