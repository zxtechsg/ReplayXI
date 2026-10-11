# Recording-led fixes — 175

## Scope

Reviewed the local 17:07 app recording `ScreenRecording_10-08-2026 15-55-19_1.MP4`, including close player views and the transport UI. The recording predates pass 174; it is not evidence that every old issue remains in the current build. No recording was uploaded and no paid model job was started.

## Changes

- **POV entry:** keep the pitch and stadium hidden until the initial view direction is ready. Capture the evaluated head direction once; continue player translation with free look. A bounded fallback covers missing tracking, without a later forced reorientation.
- **Jerseys:** use bold system digits, cropped to their actual ink and fitted inside the cached 256 px mask. Keep the original shirt triangles and skin weights. Native captures show a clearer red-team “3”; keeper “1” is still weak at a distance.
- **Reference video:** a local clip can match two replay moments and then share replay time, pause and speed. Decoder seeks are coalesced. Matching is blocked during seeks and room transitions. The room hands its final time back on close, including when opened outside the comparison window. Leaving the source releases file access; no video enters the saved review or network state.
- **Mac link:** protocol v2 compresses large states and keeps exact mark bytes. Bound wire frames to 4 MB, decoded states to 16 MB and headset-bound commands to 8 KB. Rotate single-use PINs, report failed pairing, time out unfinished pairing and reject stale listener/browser callbacks. Rebuild both apps together.
- **Frame work:** reuse lane/triangle materials until style changes. Skip annotation key sampling once the draw budget cannot fit another mark. The dense fixture reduces candidate samples from 32 to 1 while preserving the previous admitted output. Mac-link change detection compares state values instead of encoding the full state merely to compare it, avoiding one redundant JSON pass per pulse.

The Mac link remains opt-in, local and unencrypted. A PIN and digest do not encrypt or authenticate the transport. Use only a trusted LAN.

## Checks

- `replayxi175-final07.xcresult`: **108 passed, 0 failed**. Native jersey images and independent cloth-clearance checks, source timing/seek races, annotation budgets, POV, pitch gestures, arcs, local service and save guards.
- `replayxi175-mac05.xcresult`: **9 passed, 0 failed**. Native layouts and TCP fixture; large keyed states; fragmented/coalesced frames; malformed, truncated and bounded compressed input; visible pairing errors.
- `replayxi175-regression08.xcresult`: **91 passed, 0 failed**. Ball contact/roll/grounding, head and arm motion bounds, player scale, controls, review persistence and annotation history.
- `replayxi175-verified09.xcresult`: **202 passed, 0 failed**. Combined focused regression after the room-close handoff fix. Includes external room entry, closing transitions and wrong-study timing guards.
- `replayxi175-sync11.xcresult`: **42 passed, 0 failed** after value-based network change detection. Local service, reference timing, native ball scene/proxies and physics.
- `replayxi175-mac10.xcresult`: **10 passed, 0 failed** after the same optimization. Adds differential DTO/canonical JSON change checks and packet roundtrip.
- Unsigned **visionOS device Release** and **macOS Release** builds passed.
- Latest comparison and player-POV screens were inspected in the dedicated simulator. Controls were not clipped. This is not a headset comfort, gesture or FPS test.
- Earlier checks caught and fixed a font-weight loss, incorrect bitmap byte-layout assumption, glyph line-box sizing, a queued-seek calibration race and source-window cleanup.

The shared Tripo account was logged out in the live Chrome check. Its current balance is unknown; no new jobs were submitted. Do not use the old credit ledger as a fresh balance check.

The complete legacy test suite was not rerun. Simulator work counters show avoided work, not a measured headset frame-rate gain. Changed Mac-link states are still serialized/compressed on the main actor; dense-state pulse duration needs on-device profiling before claiming it cannot stall rendering.

## Models

Blender MCP imported Player A into an isolated temporary scene. Its shoulder folds remained in the source/rest pose. A bounded shoulder-weight candidate produced no visible gain and was discarded. The temporary scene was removed and the user's original scene restored.

No source GLB, USDZ, UV, rig or contact asset was replaced. There are still two imported body identities. The neck bridge masks a source seam; it is not a topology repair. `Scripts/audit_replayxi_player_surface175.py` is a read-only seam diagnostic. Indexed components can include UV seams, and weighted point distance does not establish a visible hole.

## Research → next work

- SoccerNet Game State Reconstruction offers pitch localization, team/jersey identification and camera calibration. It is a useful input for player tracks, not full-body motion capture or proof of unseen actions. See the [official code and dataset guide](https://github.com/SoccerNet/sn-gamestate). It was not installed or run on this Mac.
- Apple's [3D pose API](https://developer.apple.com/documentation/vision/identifying-3d-human-body-poses-in-images) targets a prominent person. It does not by itself provide calibrated tracks for 22 distant players. Use it as an assisted pose input, not as the complete match conversion pipeline.
- For performance claims, record CPU/GPU/frame and memory traces on the headset using Apple's [visionOS performance guidance](https://developer.apple.com/documentation/visionos/analyzing-the-performance-of-your-visionos-app). No new physical trace was captured in this pass.

## Still open

1. Properly repair source neck/shoulder topology and author better full-body motion. Current gaze and off-camera actions remain estimates, not recovered footage.
2. Test real Mac↔Vision Pro pairing, simultaneous edits, two-hand placement, POV swaps and 3D arc drags. The physical headset was unavailable in the final device check.
3. Profile dense replay/annotations on the physical headset, including memory and thermal behavior.
4. Run actual video-to-tracks/3D work from an original match clip with a suitable compute pipeline. The supplied app recording is useful for QA, not a source match capture. Current replay remains authored; two-point time matching is not automatic reconstruction.

See [the reconstruction contract](REAL_WORLD_MATCH_REPLAY.md) and [the five video studies](FOOTBALL_REFERENCE_STUDIES.md). Do not label the current assets or movement as EA-level, motion-captured or a measured recreation.
