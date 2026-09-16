# Loop 93 — annotation revision work

Scope: local Match Replay annotations. DEBUG counters and memory-only Store save/restore tests first; no lazy-loading rewrite, asset change or save-schema change.

## Measured baseline

Both diagnostics passed in `/private/tmp/replayxi-parallel88-94-mixed-01.xcresult`. Each creates 16 or 64 total marks (3 bundled marks), saves, switches scenario, restores, then measures actual scene updates.

| Work | 16 marks | 64 marks |
| --- | ---: | ---: |
| Cold saved-review application: new mark trees | 13 | 61 |
| Cold resident mark entities / models | 187 / 111 | 715 / 447 |
| Cold retained annotation glyph resources | 16 | 64 |
| Cold visible mark roots / models | 0 / 0 | 0 / 0 |
| 60 unchanged playback frames: geometry updates / new trees | 0 / 0 | 0 / 0 |
| 60 single-endpoint previews: geometry updates | 960 | 3,840 |
| Of those, unchanged marks | 900 | 3,780 |
| Preview visible mark roots / models | 2 / 7 | 2 / 7 |

No preview creates a new tree. Shared text-cache entries remain bounded at 64; retained glyph resources are counted separately, not mistaken for cache entries or allocated bytes.

Instrumented annotation-sync elapsed totals: cold 58.32 / 233.36 ms; 60 steady frames 0.55 / 2.10 ms; 60 preview samples 6.27 / 24.21 ms. These simulator samples are descriptive, not thread CPU time, headset FPS or a hardware performance guarantee. Cold measurement excludes initial bundled-scene construction.

Raw attachments:

- `/private/tmp/replayxi-annotation93-sixteen-before-01/CC1FB47F-5D9E-4040-AF95-67DE94C6A9B5.json`
- `/private/tmp/replayxi-annotation93-sixtyfour-before-01/71E66C56-9C50-42F1-97A2-1D396A2B6AA4.json`

## Narrow fix and regression gate

On a semantic revision, skip geometry updates for an exact-equal binding only if its existing parent links and required geometry children are intact. Changed geometry still updates in place; changed label/kind and incomplete trees retain their existing update/replacement path. The ordinary full-cache equality path remains unchanged. No additional repair behavior is promised for externally retained detached targets or previously unvalidated label descendants.

The 16/64 diagnostics now require exactly 60 geometry updates and zero unchanged updates for 60 one-endpoint samples. Separate controls cover missing geometry across all five mark kinds, a released body target, label/kind replacement, and visible/hidden tracked geometry through unrelated edits and reverse seeking. Released-target tests exercise the existing weak-reference repair contract, not a new promise to repair externally retained detached targets.

Strict pre-fix receipt: `/private/tmp/replayxi-parallel89-93-prefx-01.xcresult`. Both 16/64 contracts failed their four expected assertions (960 / 900 and 3,840 / 3,780 versus 60 / 0); all four binding-reuse controls passed, including the existing repair paths.

Post-fix targeted receipt: `/private/tmp/replayxi-parallel89-93-postfix-01.xcresult`. All six Loop 93 cases pass (17/17 combined with Loops 89/94). Both 16/64 previews now perform exactly 60 geometry updates and zero unchanged updates, with identity, cancellation, save-state, repair and tracking controls intact. This removes 900 / 3,780 redundant updates in the measured 60-sample workflows. Resident entity/model/glyph counts and visibility are unchanged; cold load still builds 13 / 61 trees.

Post-fix annotation-sync samples: cold 60.57 / 243.96 ms; 60 steady frames 0.60 / 2.16 ms; 60 previews 3.93 / 14.59 ms. Preview sync is lower in these samples (previously 6.27 / 24.21 ms), but these are single instrumented simulator runs, not a matched statistical benchmark or a guaranteed frame-rate change. The exact removed work is the regression contract.

- `/private/tmp/replayxi-annotation93-sixteen-after-01/243C88C4-4D1E-476D-B8EE-A4082DE58CA2.json`
- `/private/tmp/replayxi-annotation93-sixtyfour-after-01/8A6C9553-0309-4D26-8BA9-A9D19972612A.json`

Full suite and Release pending parent. Physical-headset validation not performed; no headset claims.
