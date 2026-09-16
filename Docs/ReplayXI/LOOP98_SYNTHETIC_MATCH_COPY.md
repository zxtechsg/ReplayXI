# Loop 98 — Synthetic match replay copy

## Verified source mismatch

Match Replay navigation says “Synthetic match demo,” and Home says “Demo match · no video loaded.” The same Home page uses the scenario title “Real World Match Replay” and an objective claiming a reconstructed environment. Its cues claim a generated clip, telemetry and a completed world-manifest handoff. Home displays cue headlines; the immersive Timeline displays kickers and accessibility headlines. Reviews reuse the scenario title for suggested names and summaries.

The bundled scenario is a 32-second authored sequence. The world factory requires a valid admission receipt for optional visual context; the current app has no bundled receipt and uses the empty, non-rendering synthetic fallback. This is a source/data audit, not an interactive visual test.

## Regression and scope

`ReplaySyntheticDemoCopyTests` has four cases: two check truthful live metadata and cue copy; two retain the stable scenario ID, mode, tracks, timings, mark geometry/bindings and saved-review names/state. Save checks use an in-memory library, not user files. Native pre-fix receipt `/private/tmp/replayxi-parallel96-99-prefx-02.xcresult`: exactly the two copy cases failed, with eight assertions. Both identity/save controls passed.

The scenario now says “Synthetic match replay,” identifies authored player paths and explicitly says it was not recovered from video. Cue text explains local replay, player-bound marks and POV comparison, not generated footage or a completed reconstruction handoff. Its source comment no longer promises a particular generation service.

Only this scenario's presentation strings, cue text and explanatory comment changed. IDs, kinds, times, positions, marks, existing saved names and the separate future world-admission display name are unchanged. No navigation, renderer or import changes. All four targeted native cases pass in `/private/tmp/replayxi-parallel96-99-postfx-02.xcresult`. The clean full receipt `/private/tmp/replayxi-parallel96-101-full-01.xcresult` has 837 passed, one optional skip and zero failures (838 total). Unsigned device Release also passed: `/private/tmp/replayxi-parallel96-101-release-01.log`. Swift parse and whitespace checks pass.

Desktop locked: no screenshot, interactive, VoiceOver or headset QA claim.
