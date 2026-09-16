# Loop 51 — keep the complete boot above turf

## Verified defect and fix

The previous ankle-reference grounding missed the outside edges of banked boots
and the final walk/run blend. A new scan of 726 gait samples reproduced a worst
contact height of **−89.2286 mm**. The corresponding full Blender mesh confirmed
**−89.2287 mm**, so this was a visible mesh defect, not only a test proxy.

The final blended skin now receives a uniform upward correction only when its
audited contact surface would cross the pitch. The correction updates root Y and
the existing model-space matrices in place. It does not change joint rotation,
scale, limb length, horizontal motion or source flight height. No mesh readback,
additional hierarchy rebuild, new material or asset replacement was added.

## Visual and regression evidence

- Worst walk/run blend at 13.4 s: **−89.2287 mm → +5.9998 mm**.
- Worst right cut: **−16.3867 mm → +6.0000 mm**.
- Fourteen exact before/after full-mesh render comparisons ended between
  **4.5966 and 6.0001 mm** above turf. The sampled profile's existing 6 mm margin
  accounts for the difference between its finite sample and the full mesh.
- Parent and visual sub-agent inspected the walk/run comparison; the sub-agent
  also inspected both cuts and pass contact. Timestamps, rotations, scales and
  non-root translations match before/after exactly.
- New tests cover the six gait/transition sweeps, in-place matrix correctness,
  invalid input, retained run flight and chest-bound jersey numbers.
- Combined full suite: **517 passed, 1 optional skip, 0 failed (518 total)**.
  `/private/tmp/replayxi-parallel51-full-01.xcresult`.
- Unsigned physical visionOS Release and all Python checks passed.
  `/private/tmp/replayxi-parallel51-release-01.log`;
  `/private/tmp/replayxi-parallel51-python-01.log` (111 passed, 12 optional skips).

Render folders, each with PNGs and `report.json`:

- `.codex-derived/ReplayXI-Grounding50-worst-before/`
- `.codex-derived/ReplayXI-Grounding50-worst-after/`
- `.codex-derived/ReplayXI-Grounding50-runtime-baseline/`
- `.codex-derived/ReplayXI-Grounding50-runtime-after/`

The original Blender library and audited contact-profile hashes are unchanged.
A separate warm Mac helper benchmark retained its translation/matrix buffers;
this is not a headset frame-rate measurement. Hardware comfort/performance and
interactive native UI checks remain unverified while the desktop is locked.

This backup contains only the grounding fix. Parallel UI and annotation-origin
changes are being backed up separately; the timed goal remains active.
