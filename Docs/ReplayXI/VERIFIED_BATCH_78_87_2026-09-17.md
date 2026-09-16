# Verified batch — loops 78–87

Verified on 17 September 2026, before the 09:00 SGT stop.

## Changes

- Strategy/Shape now exposes Draw and the shared annotation editor. Its controls remain mounted while a gesture owns the edit, with explicit Close/Back actions.
- Annotation nudge feedback reports the applied distance, including partial steps at the pitch edge.
- Wide 3D annotation labels fit their cards; collision boxes and selection outlines reuse the measured width.
- Larger accessibility labels fit duration, roster, primary controls and View HUD budgets. The HUD stays room-fixed.
- The roster only claims an active POV in first-person mode, while retaining the selected player for later re-entry.
- Near-idle path cues no longer create the measured keeper head reversal. Confident running and stationary controls remain unchanged.

Loop81 is hover diagnosis only; no unverified hover behavior was shipped. Loop86 measures foot contact only; it identifies far-LOD floor clipping for a follow-up, without changing cadence or claiming physically accurate contact.

## Verification

- Native Debug: **736 total; 735 passed, 1 optional skip, 0 failed**.
  `/private/tmp/replayxi-parallel78-87-full-01.xcresult`
- Unsigned physical-device Release: **BUILD SUCCEEDED**.
  `/private/tmp/replayxi-parallel78-87-release-01.log`
- Python: **126 total; 114 passed, 12 optional skips, 0 failed**.
  `/private/tmp/replayxi-parallel78-87-python-01.log`
- Whitespace validation: passed.

The optional native skip is the transient legacy imported-asset check. Required bundled-asset tests pass. Pre-fix failures and measurement limits are recorded in each loop note; none of those mixed diagnostic runs is presented as a clean full-suite result.

## Limits

Native font/mesh bounds and deterministic scene tests are not interactive UI or headset QA. The desktop remains locked. Sixteen offline keeper/control renders use the existing canonical Blender mesh and actual native poses, not the final in-app kit/appearance. There is no headset FPS claim.

Local-only operation, existing saves, free-look POV, asset files and user signing edits are preserved. Match Replay remains an explicitly synthetic demo; no authorised local video has been supplied for reconstruction. User project/Info.plist edits and unrelated workspace files are excluded from the Git backup.
