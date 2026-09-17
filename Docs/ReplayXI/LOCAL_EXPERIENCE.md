# Local-only Replay XI

Current product scope: Strategy Analysis and Match Replay on one Vision Pro.
See [the current product goal](LOCAL_PRODUCT_GOAL.md) and [UI research](SPATIAL_UI_RESEARCH.md).
This supersedes the multiplayer scope in earlier loop reports and the original MVP.
Do not restore Group Activities, network rooms, invites or shared anchors unless
the user explicitly requests multiplayer again.

## Kept

- Synthetic 3D match playback, speed control and timeline gestures.
- All 22 player POVs with translation following and independent head look.
- Tactical/touchline views, overlay controls and retractable tool menus.
- 3D runs, passes, spaces and labels; player/time bindings; joystick editing;
  undo, erase and clear.
- Named local reviews and autosave, with the existing on-disk format.
- Local positioning markers and headset-relative feedback after clear-area consent.
- Licensed rigged player assets and rendering budgets.

## Quick demo

1. Choose **Match Replay** or **Strategy Analysis**, then enter the spatial room.
2. Use Play, Speed and the timeline. Pinch-drag horizontally to seek; raise the
   held pinch for finer control. The rail supports frame-sized steps.
3. Pinch a player or shirt tag to pause at that moment and enter their POV.
   The player moves along the authored run; your head controls where you look.
   The player menu also offers all 22 roles across both teams.
4. Open **Draw**, choose a run/pass/zone, and pinch-drag on the pitch. Release
   to save. Two taps are the alternative. Label uses a player tap.
5. Select a mark to adjust its endpoints, height, timing, label or player
   binding. Undo, Erase and confirmed Clear affect your marks, not lesson marks.
6. Open **Tools → Reviews** to save or load a local review. The unfinished
   gesture is not a saved edit. Normal app launches restore the local autosave.

Controls stay fixed in the room. **Place controls here** moves them once; it
does not restore head-following. Views and Tools keep secondary options folded
away. Touchline intentionally uses a transparent pitch surface; Tactical and
Player POV show the turf. Stay seated or stationary in a clear area.

## Current visual limits

The pitch and panelled ball are original Blender assets. Player bodies derive
from the bundled MIT-licensed Rocketbox source, not EA/FIFA assets. Up to four
skinned players are admitted in Tactical/Touchline; POV remains capped at two.
Spare tactical slots use the lighter skin, and remaining players use articulated
far rigs with a shared static face. Missing optional assets keep the fallback.
This is still visibly simplified game art, not FIFA-level fidelity.

Every bundled match is synthetic. The app does not contain a reconstructed
60-second real match, recovered player gaze, live camera capture or a Gaussian
world. See [the reference workflow](BLENDER_MATCH_WORKFLOW.md) for the unfinished
video-reference path. Native offscreen renders and CPU tests are not a headset
comfort, gesture or frame-rate validation.

## Removed

- Group Activities entitlement, imports, activity registration and scene associations.
- Session discovery, activation, invitations, messaging and network heartbeats.
- Shared POV controls, participant seats and coach/player permission selection.
- Nearby anchor sharing and sharing-availability observation.

The pure legacy snapshot test harness lives only in ReplayXITests, without network
APIs. Existing snapshot/domain types remain for compatibility and regression
coverage; the application creates no session coordinator or transport callback.

## Signing

Open ReplayXI.xcodeproj, select ReplayXI, then Signing & Capabilities.
Keep automatic signing and choose your personal team. Group Activities is no
longer required. Simulator builds do not require a provisioning profile.

The user's bundle ID and team selections are preserved, not managed by the
asset/UI changes. If Xcode reports a bundle-ID registration error, choose a
unique reverse-domain ID you own. Select the intended team when building or
archiving. Removing Group Activities fixes that capability requirement; it
does not verify account credentials or device provisioning.

This remains a visionOS app, not an iPhone app. Real video-to-3D reconstruction
and physical-headset performance/gesture validation are still unfinished.

## Regression checks

- `LocalExperienceTests`: local authority, 22 POVs, annotation editing, scrubbing,
  save/load and local positioning.
- `Scripts/tests/test_replayxi_local_capabilities.py`: no group entitlement,
  transport/invites, scene association or shared-anchor APIs in app sources.
- Full existing app suite continues to cover saved reviews, gestures, geometry,
  imported rigs and deterministic playback.

Latest verified 17 September 2026: simulator suite — 913 passed, one optional
skip, zero failures; unsigned device Release passed. See
[loops 115–120](VERIFIED_BATCH_115_120_2026-09-17.md) for exact receipts and limits.

Earlier baseline, 10 September 2026: simulator suite — 378 passed, 1 skipped (optional
transient asset fixture absent); capability guards — 4 passed. Simulator and
unsigned visionOS device builds passed. The simulator app has empty entitlements
and no Group Activities framework link. Physical-device signing and placement
still require hardware validation.
