# Improvement run 132–133

Local-only. Match Replay and Strategy Analysis stay the focus.
User requested a 1,000,000,000-token goal and parallel work; the goal remains active.

## Backed-up checkpoints

- ef7fdca — individual position-key retiming; shift availability includes all keys. 17 focused tests passed.
- d99152e — skip repeated annotation geometry for held poses; reuse translated arc meshes. 32 focused tests passed.
- 26a3373 — keep thigh/shin length constant during partial contact. Both teams, near/low rigs. 28 focused tests passed.
- 61de85c — bar size percentage/reset and finite bounds; sampled-height inspector; explicit renderer test teardown.
- e1f403c — accurate selected-zone radius; finite transforms when animated endpoints cross. 23 focused tests passed.
- 14e7d9f — strict timestamp drafts, compact scrolling, individual-key controls, undoable Freeze here.

UI/domain/contact combined check: 49 tests passed. Compact-panel follow-up: 18 passed.
Native regular and largest-text captures inspected. This is not headset comfort or FPS validation.

## Motion follow-up and final validation

Off-ball tactical attention had a sharp neighbour-distance cutoff. The first smoothing attempt
failed continuity tests. The revised confidence fade keeps ball attention during near-overlaps,
then restores scans smoothly; strict motion checks pass.

Measured maximum head turn per 120Hz step: volley 2.392°, underlap 3.149°.
Near/low rigs agree; cervical bounds and exact reverse seeks pass. These are authored scenario
metrics, not match motion-capture accuracy.

Full simulator suite: 1,206 XCTest tests, 2 intentional skips, 0 failures; 2 Swift Testing tests
also passed. Unsigned device Release build passed. No headset FPS or comfort claim.

The earlier native crash stack was in RealityRenderer destruction / PhysicsSimulation weak
references. Header test resource teardown is now explicit; the isolated contact/header tests
pass, including in the full suite. Exact originating renderer remains unknown; a passing run
does not prove an intermittent framework teardown issue is permanently fixed.

## Next usability pass

- Timing should distinguish outside-window annotations from the selected editing preview.
- Make In/Out and selected-position draft actions unambiguous, with isolated Reset/submit.
- Keep keyboard and draft changes from being silently discarded when switching positions.

## Preservation

Existing project.pbxproj and Info.plist edits belong to the user and are excluded from commits.
Unrelated workspace projects remain untouched. Tests use isolated review libraries.
Pre-run production review SHA-256: 952e501de62f36e391a5b471175c883d0deb9e981a5c6cfc04f607c6dc5ded65.
