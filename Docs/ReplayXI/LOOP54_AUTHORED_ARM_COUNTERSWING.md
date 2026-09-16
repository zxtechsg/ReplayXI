# Loop 54 — authored arm counter-swing

## Defect and scoped fix

Walking/cutting legs followed the authored footfall clock, but arms retained the
source run phase. Four controlled runtime frames showed the arm and leg on the
same side leading together. The pre-fix arm test produced four counter-swing
assertion failures; its other three tests passed.

The existing gait retarget now rotates six arm joints from the same authored
opposite-foot clock. It uses the audited neutral bone axes and current chest
orientation, retaining source translations, scales, torso, clavicles, head and
finger locals. The existing target buffer/hierarchy traversal is reused.

A separate walk/cut arm weight excludes ball-contact-only retargeting. Normal
source running and straight-running pass-only arms remain unchanged. No camera,
POV, floor-guard, mesh, material, texture, asset hash or licensing change was made.

## Exact-frame evidence

Values below are left-minus-right forward reach from each limb's own root, in
metres. Opposite arm/leg signs show counter-swing. The leg values did not change.

| Frame | Leg lead | Arm before | Arm after |
| --- | ---: | ---: | ---: |
| Walk, 12.23 s | -0.3299 | -0.1405 | +0.1525 |
| Walk, 13.8667 s | +0.3238 | +0.1118 | -0.1504 |
| Left cut, 15.0 s | +0.2693 | +0.4908 | -0.1163 |
| Right cut, 11.4 s | -0.5202 | -0.4930 | +0.1722 |

All eight before/after attachments retain identical timestamps, translations
and scales. The six gait frames change only joint rotations 16, 17, 42, 43, 48
and 49 (shoulders, elbows and wrists). Both source-run frames, at 12.0 s and
14.3333 s, are bit-identical across the complete exported pose.

The visual pass identified lower/open cut arms than the source run. A read-only
bone-angle check ruled out neutral-axis cancellation: the existing authored cut
requests 0.72–0.80 rad (41.253–45.837 degrees) of elbow bend. The rendered cuts
measure 0.720000/0.796454 rad and 0.796349/0.720000 rad. Their base bends agree
with 0.72 rad within 0.0000003 rad. The previous source-run leading elbows were
126.74 and 120.91 degrees. No aesthetic tuning was applied; this is the existing
authored cut style. Exact authored-quaternion bend assertions now cover all four
controlled walking/cutting frames.

Parent and visual sub-agent inspected the walk and both cut renders. Ground
heights and head positions are unchanged in every full-mesh Blender comparison:

| Frame | Lowest full-mesh vertex above turf |
| --- | ---: |
| Walk backward step | 6.0000 mm |
| Walk forward step | 5.9924 mm |
| Left cut | 4.9608 mm |
| Right cut | 6.0000 mm |
| Source run A | 5.9997 mm |
| Source run B | 6.0000 mm |
| Slow walk | 5.9998 mm |
| Walk/run blend | 5.9998 mm |

Render folders, each with eight PNGs and a full-mesh `report.json`:

- `.codex-derived/ReplayXI-Arms54-before/`
- `.codex-derived/ReplayXI-Arms54-after/`

## Regression receipts

- Intentional pre-fix failure: `/private/tmp/replayxi-arms54-repro-01.xcresult`.
- Dense arm class: **7 passed, 0 failed**.
  `/private/tmp/replayxi-arms54-dense-01.xcresult`.
  Includes 3,848 samples across eight partial speed/turn blends at 120 Hz,
  quaternion/joint continuity, speed/turn edges, exact rewind, finger locals,
  limb lengths, head-look independence, source-run/pass preservation and floor
  clearance.
- Initial combined suite: **556 passed, 1 optional skip, 0 failed (557 total)**.
  `/private/tmp/replayxi-parallel55-full-01.xcresult`.
- Latest combined suite: **557 passed, 1 optional skip, 0 failed (558 total)**.
  `/private/tmp/replayxi-parallel55-full-02.xcresult`.
- Unsigned physical visionOS Release: **BUILD SUCCEEDED**.
  `/private/tmp/replayxi-parallel55-release-01.log`.
- Final arm class, including exact authored bend assertions: **7 passed,
  0 failed**. `/private/tmp/replayxi-arms54-bend-01.xcresult`.
  Production code is unchanged from the full/Release checks.

This remains the licensed Rocketbox skin with authored gait, not football mocap
or FIFA assets. It does not establish physical-headset frame rate or comfort.
Native hand/click checks remain unavailable while the desktop is locked.
