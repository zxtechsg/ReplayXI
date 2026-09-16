# Verified batch — loops 88–95

Verified on 17 September 2026, during the run ending at 09:00 SGT.

## Changes

- Distant players no longer intersect the pitch at the checked running/touch poses. The correction uses cached real mesh support, keeps horizontal motion and all joint poses, and repeats exactly after reverse seeks or view changes. Near/mid poses are unchanged.
- Dragging one annotation no longer rewrites the unchanged marks' geometry. Sixty endpoint samples now make 60 geometry updates instead of 960 with 16 marks or 3,840 with 64. Repair, relabel, tracked-mark and reverse-seek behaviour is preserved.
- Shape/Strategy's annotation list now follows the same view/stage eligibility as the 3D scene. A hidden preset cannot remain a misleading selected item; gesture-owned cleanup is deferred safely.
- Height buttons correctly disable while another gesture owns the edit.
- Large-text Draw instructions/tools and the retractable Tools shelf have measured label budgets and separate/wrapping rows. The compact Speed button gets a narrow accessibility-only width fix. Normal controls, actions and room anchors stay unchanged.
- Added a bounded native-mesh export and isolated Blender visual check. The comparison shows floor clearance with unchanged geometry, not new close-up player art.

## Verification

- Native Debug: **790 total; 789 passed, 1 optional skip, 0 failed**.
  `/private/tmp/replayxi-parallel88-95-full-02.xcresult`
- Unsigned physical-device Release: **BUILD SUCCEEDED**.
  `/private/tmp/replayxi-parallel88-95-release-01.log`
- Python: **132 total; 120 passed, 12 optional skips, 0 failed**.
  `/private/tmp/replayxi-parallel88-94-python-01.log`
- Whitespace validation: passed.
- Four inspected native-mesh Blender renders and report:
  `.codex-derived/ReplayXI-Far94-native-final-01`.

The first full native run had one stale test expecting the raw, below-floor far-body Y. It now checks exact corrected Y, unchanged X/Z/shoulder motion and the actual mesh floor bound. No floor tolerance was relaxed. Other pre-fix failures and the two unsuccessful intermediate floor implementations are recorded in the loop notes, not presented as successful receipts.

The optional native skip remains the transient legacy imported-asset check; required bundled-asset tests pass. This batch's receipts supersede “full verification pending” in the earlier targeted loop notes.

## Limits and preservation

The desktop is locked. Native font/geometry tests and illustrative Blender renders are not interactive UI, VoiceOver or physical-headset QA. Work counts are not FPS claims. Far players remain simplified silhouettes; this batch does not deliver realistic player art or physical foot locking.

The app remains local-only, with existing saves and free-look POV preserved. Match Replay is still synthetic; no authorised local match clip has been supplied. Existing asset files are unchanged. The user's project/signing/Info.plist changes and unrelated workspace files are excluded from this local Git backup.
