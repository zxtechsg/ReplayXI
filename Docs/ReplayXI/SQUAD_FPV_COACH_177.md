# Squad models, FPV body and Mac Coach

## Changes

- Full squad is now the normal local quality setting, including existing installations. Both teams use the prepared Tripo bodies; near players retain the denser mesh. Lightweight remains available.
- The 22-player skin budget includes the FPV wearer. No second animated body or per-frame model loading.
- FPV uses the same player's animation, kit, chest, arms and legs. The head is removed only from that local view. A cached skinned neck closure prevents a hollow torso; boundary matching accounts for UV-split vertices. Leaving FPV restores the full model.
- Entry captures a fixed eye-height offset as well as gaze direction. Seated viewers are aligned once; later headset movement remains free. Eye height uses the posed crown with a standing-height minimum so entering during a header cannot later put the camera inside the chest. A 15 cm forward eye offset follows body translation/facing, never forcing view rotation. These are estimated eye anchors, not recovered eyeball markers.
- Mac Coach has a compact tool shelf, searchable marks/players, direct player POV selection, exact-time entry, small time steps, visible annotation ranges and motion keys, and simpler timing controls.
- Simulator pairing uses an explicit same-Mac loopback connection and the normal PIN. Physical Vision Pro keeps its existing opt-in local-network route.

## Limits

These are the two existing Tripo body identities with kit/appearance variants, not 22 newly generated unique people. Player A still has source garment/shoulder defects. This change does not claim EA-level assets or recovered motion capture.

Simulator tests cannot establish headset frame rate, comfort or physical Mac–Vision Pro pairing. The wire protocol is not an encrypted remote-control service; the Simulator route stays on localhost.

## Validation

- `replayxi177-check03.xcresult`: 40/40 passed, including native look-down captures, skin/cap/pose/cache checks, both-team admission, free look, localhost PIN authentication, unauthenticated rejection, occupied-port recovery and retry.
- `replayxi177-check02.xcresult`: older admission/quality-control regression tests passed; its cut-mesh and fixed-port failures were repaired and rerun in check03.
- `replayxi177-mac11.xcresult`: 16/16 passed. Real TCP tests exercise the Mac client with a fixture server; visionOS tests exercise the real service with a fixture client. These are separate tests, not a completed manual pairing of both app UIs.
- Mac Release build passed. Native window-backed UI captures checked at 1360×840 and 1060×700.
- Check03 also collected an unrelated `backboardd` crash from the other booted visionOS 27 simulator (`1AA6…`); the dedicated 26.5 audit simulator (`E0A4…`) completed all 40 tests. No settings or process changes were made to that other simulator.

## Pair with visionOS Simulator

1. Run the updated Replay XI app in the visionOS Simulator. In its main dashboard, select **Start Mac link**.
2. Open Replay XI Coach on the same Mac. Select **Simulator on this Mac**.
3. Enter the displayed six-digit PIN and select **Pair**. Pause playback before editing annotations.

The simulator listener binds only `127.0.0.1:49311`. Only one Replay XI simulator link can use that port at a time; stop the other link before retrying. No account, Bonjour permission or physical headset is required for this route. UI automation was unavailable in this session, so the final manual pairing remains for the user.
