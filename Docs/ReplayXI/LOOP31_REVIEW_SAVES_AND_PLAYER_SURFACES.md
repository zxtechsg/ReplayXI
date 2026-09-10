# Loop 31 — saved reviews and player surfaces

## Delivered

- Saved reviews in the dashboard and in `Tools → Reviews` inside the immersive deck. One retractable shelf; no extra permanent transport buttons.
- Save a named copy, rename, confirm deletion, or load paused. Save and load capture the chosen snapshot so playback cannot shift the selected moment while a name/confirmation is open.
- Normal launch restores the last local session paused. Saves retain player POV, time, speed, view mode, and marks across visited scenarios.
- Tapping the current scenario no longer clears annotations. Reset remains explicit.
- Versioned, bounded JSON with atomic replacement, previous-good backup, recovery when the primary is missing/corrupt, and read-only protection for newer schemas. Damaged bytes are preserved.
- Room identities, anchors, consent, running flags, and incomplete gestures are never persisted. Loading is blocked during shared sessions, placement, and active edits.
- Autosave is debounced after committed changes and flushed when backgrounding or leaving immersive playback. No periodic file writes during uninterrupted playback. A force-kill mid-play can therefore resume at the last committed transport checkpoint.
- Imported MIT Rocketbox facial geometry, hair, eyes, normal map, and five 512-pixel skin palettes. The existing gaze joints drive the face; far players retain low-cost geometry.
- Fixed inside-out limb normals/winding, removed invisible shirt-number backs, and removed the duplicate neck beneath imported faces. The textured neckline now meets the collar.
- Worst-case textured near athlete: 24 model entities, 4,550 vertices, 5,728 triangles, within the existing limits. Meshes/textures are shared and prewarmed before room entry.
- Hidden/cull-limited annotations skip track-geometry updates; culled annotations no longer take POV caption slots. Elevated tethers now count toward the draw limit. Two temporary per-frame player-index sets were removed.
- World replay UI now plainly identifies authored synthetic data and the missing Gaussian reconstruction, rather than showing internal hash/batch metrics as product features.

## Verification

- Final visionOS 27 Simulator suite: **346 passed, 1 skipped, 0 failed** (`/private/tmp/replayxi-loop31-final-fit.xcresult`).
- Python asset/world suite: **77 passed, 4 skipped, 0 failed** (`/private/tmp/replayxi-loop31-python.log`). Optional local acquisition inputs were not provided to the skipped cases.
- Simulator Debug and physical-device-target Release builds succeeded. No physical headset installation or on-device performance measurement was performed.
- Dashboard library and immersive shelf visually checked without clipped controls: `/private/tmp/replayxi-loop31-saved-reviews.png`, `/private/tmp/replayxi-loop31-immersive-reviews.png`.
- The initial in-scene head capture revealed a duplicate/long neck (`/private/tmp/replayxi-loop31-pov-head.png`), which was fixed. Geometry checks across six replay times pass; **post-fix visual inspection is pending because the Mac locked**. The final source builds and tests above include that correction.
- CUA pointer attempts did not activate the visionOS controls reliably. Save/load/rename/delete are covered by store/disk tests, not a completed manual UI interaction test. Headset gesture QA remains open.

Screenshots and Xcode reports stay in `/private/tmp`; they are not production assets.

## Boundaries and next work

- The new head is a static surface attached to the existing articulated rig, not a new deforming full-body skeleton. The body is still visibly stylised. No FIFA assets were used.
- Real hand tracking, headset comfort, sustained frame time, and 11–20-device SharePlay require physical-device testing. Simulator images and domain tests do not prove those behaviours.
- The scripted `--replayxi-*` launch routes use temporary memory-only saves and say so. Normal launches use durable storage. `--replayxi-saved-reviews` opens the library with a sample; combine with `--replayxi-autostart` for the immersive shelf.
- Next priority: a licensed full-body skinned athlete with verified idle/run/turn/pass transitions, then test touch/pinch controls on a physical headset. Preserve deterministic timeline seeking and current render limits.
- Hourly improvement follow-ups are attached to this task. Each run should ship a small verified batch, preserve unrelated projects, and report only meaningful progress or blockers. No new paid generation is authorised by that schedule.

See [asset provenance](THIRD_PARTY_ASSETS.md) and [selection notes](PLAYER_ASSET_SELECTION.md).
