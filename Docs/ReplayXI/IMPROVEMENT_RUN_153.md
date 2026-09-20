# Run 153 — setup work and cleanup diagnosis

Status: optimized Debug build, thirteen focused/native tests on visionOS 26.5 and unsigned device Release build passed. Cleanup diagnosis remains in progress using the unchanged run152 Debug binary. No normal demo launch or clean full regression claimed.

## Scope

- Skip a slow-run cell's midpoint policy evaluation when either endpoint already guarantees the entire cell is excluded. Preserve the original knot caps, zero-cell flags, envelope and lookup bit-for-bit.
- Keep the original logical grid-size counter; add separate actual policy-evaluation and skipped-midpoint counts. Do not report logical requests as executed work.
- Compare every non-keeper track in all five demos against the unchanged run152 unconditional-midpoint builder. Include shifted starts, short/partial final cells, stationary tracks and exact Float bit patterns.
- Measure existing native root-construction stages without extra scene/render loops. This is profiling to choose a subsequent fix, not a performance improvement by itself. Separate nested timeline cost from total cache work and label process-first versus repeated roots honestly.
- Investigate the run152 native crash before claiming the regression suite is clean. The exact matched-binary stack identifies release of the `Array(root.children)` cleanup snapshot in `captureSupport149`, after renderer detachment. This is stronger ownership evidence than the previous physics-world stack, but neither identifies the corrupted child nor establishes cause.

## Arc audit

A raised arc still uses a horizontal minimum-length guard; true vertical chords also lose bend in the current curve basis. Any capability change must preserve old review geometry, use consistent validation across edits/keyframes/persistence, and prevent abrupt flips near vertical endpoints. This is an audit, not an implemented feature.

## Focused evidence

- Build: `/private/tmp/replayxi-cycle153-build.log`, `SWIFT_OPTIMIZATION_LEVEL=-O ENABLE_TESTABILITY=YES`. The exact run152 Debug binary remains in Local37 for the cleanup probe; new code is in Optimised105.
- Eleven tests passed in `/private/tmp/replayxi-cycle153-pure26.xcresult` on visionOS 26.5: six existing dense/boundary timeline tests, two new exact-preparation tests and three raised-arc baseline tests.
- Exact Float knot/lookup equality across all 100 non-keeper tracks: 244,900 logical grid positions, 156,151 actual policy evaluations, 88,749 skipped midpoints. This corpus intentionally includes protected actors for sampler coverage; native admission still excludes them. No timing saving is inferred from the operation count alone.
- Receipt: `/private/tmp/replayxi-cycle153-pure26-captures/473409B0-CF6C-4596-B49E-07D73CD106D4.json`. The unchanged envelope is tested separately; the comparison builder independently retains run152's unconditional midpoint policy calls, not a second independent envelope implementation.
- Arc tests confirm three edit APIs reject the short-horizontal raised chord without changing saved state, playback or Undo. Existing save/import/keyframe validation already accepts vertical curves, so tightening it would break compatibility. A 2 mm crossing around the current vertical pole can move the legacy midpoint about 2 m. These passing baseline tests document a limitation; they do not fix it.
- User review SHA-256 remains `952e501de62f36e391a5b471175c883d0deb9e981a5c6cfc04f607c6dc5ded65` in the current simulator data container.

## Stage-probe correction and clean rerun

The first native stage run on 26.5 failed one new diagnostic assertion: the first paired roots counted 82 versus 79 unique mesh wrappers, despite matching 868 entities, 357 models, 360 material slots and identical player/label hierarchies. The new census retained only `ObjectIdentifier`s, unlike the existing census that holds mesh references throughout traversal. The original failed run is retained at `/private/tmp/replayxi-cycle153-stages26.xcresult`.

The corrected census keeps wrappers alive during both traversals. The first pair's old nonretaining counts remain 82/79, while retained counts are 101/101, repeat counts 101/101, with zero changed getter-identity paths and exactly the same 101 sharing groups over 357 model paths. Every paired hierarchy/resource-count check passes across all 20 roots. This establishes a census lifetime error, not a demonstrated production graph difference. Counts concern public wrappers, not private GPU allocations.

- Clean rerun: `/private/tmp/replayxi-cycle153-census26.xcresult`, 13 passed/0 failed. It includes independent cap-derived actual-evaluation counts added after peer review; no longer relying only on an algebraic sum check.
- Receipt: `/private/tmp/replayxi-cycle153-census26-captures/4D1910F8-A33F-49B2-B777-BE5AE4DBF1A8.json`.
- Labels/selection is the largest stage in all 20 roots: 32.186–175.565 ms (48.99–72.54% of measured construction). The first root is 175.565 ms; the other 19 are 32.186–93.308 ms. This stage includes facing/selection helpers, so do not assign all cost to text without a narrower check.
- Whole-root construction: 61.578–249.975 ms; nested timeline preparation: 7.442–10.323 ms. These measurements are on **26.5**, whereas run152's optimized baseline is on **27**; no causal wall-time improvement is claimed across different runtimes.
- Across the 20 roots: 796,648 logical grid positions, 520,580 actual policy evaluations, 276,068 skipped (34.65%). Per-root retained weight payload remains 57,188–97,260 bytes. Policy-call reduction is not a movement-intent-call count or a timing estimate.
- Device Release: `/private/tmp/replayxi-cycle153-release.log`, successful. DEBUG stage timing/census is absent from this build; the exact-output midpoint optimization remains.

## Cleanup probe

The unchanged run152 test module UUID is checked before installing four narrow debugger tracepoints. They record root/child addresses around the existing detach/snapshot-destruction path, without calling getters or changing ownership. A first weak-runtime error or bad access stops and records frames/registers/images. The bounded ten-iteration reproduction and debugger alter timing; failure to reproduce cannot establish a fix.

- `/private/tmp/replayxi-cycle153-cleanup-repeat27.xcresult`: the single method passed all ten repetitions in the same host, PID 90592. The result summary counts one distinct method; the console log records all ten executions.
- `/private/tmp/replayxi-cycle153-cleanup-lldb.log`: 38 complete observed root cleanups (684 child detachments), each entering snapshot destruction and returning. Attachment occurred after two early cleanups, so coverage is 38 of 40 rather than all 40. No weak-error breakpoint or bad-access stop; host exit 0. Both debugger and test sessions closed normally.
- A subsequent unchanged-binary ordered cohort, 145 → 147 → 149, also passed: `/private/tmp/replayxi-cycle154-cleanup-prefix27.xcresult`. Its debugger observed all four149 cleanups, host exit0. No cleanup code was changed. Full152's failure remains unresolved and recorded; these negative reproductions do not prove framework blame or a fix.
