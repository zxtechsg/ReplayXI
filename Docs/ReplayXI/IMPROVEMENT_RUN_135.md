# Improvement run 135

Local-only Match Replay and Strategy Analysis. Goal remains active.

## Timestamp clarity and navigation

- Saved-position chips use only enough decimal places to distinguish nearby keys.
  Labels rebuild when timestamps change, not on each replay frame.
- Selected annotations show cyan position diamonds on the main timeline. Dense keys cluster
  into bounded bins; total count is accessible. The overlay never takes scrub input.
- Key-time labels: 29 focused tests passed; native close-key screenshot inspected.
- Timeline: 45 focused tests passed, including actual observation of add/remove/retime changes.

## Arc rendering work

- Cache fixed tube topology and six cross-section directions.
- Resolve one control point per rebuilt tube, rather than 102 repeated evaluations.
- Skip unchanged selected-tube transform writes.
- 27 focused tests passed. Vertex/normal/index comparisons preserve eight edge cases.
  Forward/reverse morph checks cover 60 changed tubes; 60 held frames cause no highlight
  transform writes. These are work counts, not headset FPS measurements.

## Backups and preservation

3c53d94 covers separate timing drafts and full-library save safety.
806c200 covers precise key labels; 797f526 covers arc work reduction.
All are pushed to origin/main. Pre-existing project/Info edits remain excluded.
Production review bytes were unchanged after the timing/library run.

## Planted keeper knees

- Reproduced a keeper-save defect before patching: knees followed the outgoing rebound
  while boots used the planted support direction. Baseline had 132 failed assertions.
- Imported near/low skins now use the support boot frame for save knee direction, matching
  the procedural keeper. Foot targets, other contact types and physics stay unchanged.
- Seven save/contact tests and thirteen goalkeeper readiness/scene tests passed.
  Before/after calibrated native renders inspected. Knee-to-boot-forward alignment changed
  from approximately −0.60…−0.68 to 1.0. Limb lengths, sole contact and exact rewind pass.

## Still in progress

Saved Reviews large-text layout.
No claim of match mocap accuracy, FIFA fidelity, or measured headset performance.
