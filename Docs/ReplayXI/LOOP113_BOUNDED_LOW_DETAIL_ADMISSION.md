# Loop 113 — bounded low-detail admission

## Scope

- Match Replay Tactical/Touchline can use spare slots for the validated low-detail body after explicit provider preparation.
- The total cap stays four. Player POV stays two near skins. Shape/Positioning gets no extra low skins.
- Selected and active impact subjects keep near priority. Normally the mix is one near + three low; an additional impact uses two near + two low.
- After separate native/runtime/CPU checks, the dashboard now prepares the
  optional low asset on its cold path. Failure keeps existing player visuals.

## Lifecycle

A pure policy ranks actual presented player positions around the selected player, across both teams. Player IDs break distance ties. Cached membership changes only when a challenger is more than 1.25 m nearer. Changing match/selection, leaving eligible views or losing low readiness resets that context. Tactical↔Touchline keeps it.

Factory releases departed or wrong-detail skins before iterating players. Failure keys include both player and detail, so a failed low clone cannot block near promotion. Failed clones immediately keep the existing far body. Repeat failures are not retried every frame while that variant remains admitted.

Near procedural/query-rig selection is unchanged. A successful low skin hides only its far visual; it does not request a new detailed query rig. Player transforms, pick targets, labels and annotation positions keep their existing paths.

Hysteresis is intentionally history-dependent inside its 1.25 m band. It is not a promise that every rewind retains the same low-detail membership. Body/jersey poses remain absolute-time samples.

## Verification

- New policy tests: spare cap/impact exclusion, deterministic ties, hysteresis, promotion/shrink, context changes, mode/readiness gates, missing/nonfinite tracks.
- New native scene tests: explicit readiness, retained roots, no extra query rigs, selected/impact promotion, POV/Shape limits, variant failure/fallback, exact low pose/number rewind, optional-resource retirement, unchanged picking/annotation origins.
- All 16 new policy/scene cases pass in `/private/tmp/replayxi-parallel102-114-full-01.xcresult`. The corrected low importer and renderer passed in `/private/tmp/replayxi-low109-contact112-palette110-after-01.xcresult`.
- Parent's optimized native diagnostics pass all seven runtime/scene cases. The measured full-scene Tactical/Touchline medians were 0.657/0.665 ms with mixed detail versus 0.298/0.298 ms near-only; POV was 0.437 ms versus 0.354 ms. Tactical/Touchline keep four skins and one procedural near/query rig. These sampled simulator CPU results include more work for the extra visible skins, not a free performance gain. Parent records the exact optimized attachment/bundle in the batch receipt.
- Clean full native run: `/private/tmp/replayxi-parallel102-114-full-02.xcresult`:
  883 total,882 passed, one optional skip, zero failures. Full01's only failure
  was a new test bundle indexed before its contact fixture was added. Publishing
  the complete fixture before lookup fixed the test; no validator was relaxed.
- Optimised bundle: `/private/tmp/replayxi-mixed113-optimised-01.xcresult`.
  Scene receipts: `/private/tmp/replayxi-mixed113-scene-01/9A7EFF69-139D-41BC-B5A8-052550FCFFAB.json`
  and `/private/tmp/replayxi-near113-scene-01/DC3138F9-6F94-4141-A0F8-A46FBB5BD3E1.json`.
  Mixed Tactical/Touchline p95 values0.704/0.703ms versus0.317/0.315ms near-only.
- Five runtime tests also cover shared independent clones, full-mesh floor
  contact through482 forward/reverse frames, exact jersey rewind, and missing
  or changed asset/contact bytes leaving near players intact. Actual runtime
  low-player front/back #7 renders were calibrated and inspected. Device
  Release remains pending the next batch.
- No interactive, headset, rendering-performance or GPU claim. Full low contact geometry can cost more CPU than the near contact proxy; unchanged skin count is not proof of unchanged frame time.
