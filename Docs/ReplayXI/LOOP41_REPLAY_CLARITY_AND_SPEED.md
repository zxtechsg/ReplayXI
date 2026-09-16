# Loop 41 — clearer local replay and direct speed control

## Changes

- Removed 640 decorative tetrahedra around the synthetic match. They were not
  reconstructed data and appeared as distracting floating triangles in POV.
  The original pitch and authored player tracks remain. The hash/receipt-gated
  asset path is unchanged; failed admission still fails closed.
- Removes four rendered models, 2,560 triangles and 7,680 vertices from that
  preview. No measured FPS claim.
- Shortened demo copy to “Demo match · no video loaded” / “Synthetic match demo”.
  Scenario IDs, saved-review IDs and annotation bindings are unchanged.
- Added a direct Speed control beside the timeline. Its retractable shelf offers
  0.25×, 0.5×, 0.75×, 1×, 1.5×, 2× and 4×, then closes on selection.
- Speed is separate from Tools selection. Opening it does not light up or
  toggle the unrelated Tools command.
- Enlarged camera-choice and timeline text. The timeline grows with the readout
  text size. Speed and one-second step controls now have 60-point content height.
- Speed/play/tools controls now visibly lock while a timeline gesture owns input.

## Evidence

- Simulator suite: **400 passed, 1 optional asset fixture skipped, 0 failed**.
  `/private/tmp/replayxi-local41-verified-tests.xcresult`.
- Python replay checks: **107 passed, 12 optional fixtures/dependencies skipped**
  (119 total). `/private/tmp/replayxi-local41-python-verified.log`.
- Simulator player POV + open speed shelf and tactical view + expanded Settings
  inspected. Seven speed choices and workspace controls fit the standard panel;
  the colourful synthetic triangles are absent.
- Screenshot evidence: `/private/tmp/replayxi-local41-speed-pov.png` (before
  Tools highlight correction) and `/private/tmp/replayxi-local41-settings.png`.
- Unsigned device Release compilation passed (`/private/tmp/replayxi-local41-release.log`).
- Corrected Speed-highlight screenshot inspected:
  `/private/tmp/replayxi-local41-speed-final.png`. Only Speed is selected; Tools
  remains inactive. No text overlap seen in the inspected default-size layouts.
  Large accessibility text and physical hand interaction still need broader checks.

## Next fidelity audit

`ReplaySkinnedAthleteInstance.supports` currently rejects walking, cutting,
ball actions and impacts. These moments use the procedural fallback rig, which
can change player appearance during the most important review actions. Assess
continuous skinned rendering with deterministic joint offsets/retargeting before
claiming improved action fidelity. Keep free-look POV and annotation anchors intact.
