# Player, ball, movable-controls and Arc checkpoint

Verified 17 September 2026. Local-only Replay XI; no service, purchase or upload was added.

## What changed

- Both teams use physical 1× player roots. Selection no longer enlarges a player. New original Blender-built distant bodies bend at the elbows and knees; refined kits cover both teams at every detail level. The supplied [3dpassion reference](https://3dpassion.net/product/pack-6-arsenal-26-27/) informed proportions and kit detail; its paid assets were not downloaded.
- Match-ball presentation now corrects the bundled demo's player/boot intersections, smooths ground travel and derives roll from travelled distance. Seek and playback speed use the same absolute-time path. Source footage/tracks and event times are unchanged.
- A **Move** grip beside the immersive console moves the control workspace, not the pitch. Release retains its room-relative position; **Place controls here** resets it.
- **Draw → Arc:** pick a start and an end. Select the arc, then **Adjust → Curve** to change **Bend** and **Lift** with the pad or buttons. Existing endpoint, height, player/time binding, Undo, erase and save controls also apply.

## Final checks

| Check | Result | Local receipt |
|---|---|---|
| Full native suite | 985 passed, 0 failed, 1 optional fixture skipped | `/private/tmp/replayxi-player-ball-arc-full-02.xcresult` |
| Supporting Python checks | 126 passed, 12 optional skips | `/private/tmp/replayxi-player-ball-arc-python-02.log` |
| Generic visionOS Release build | Passed, signing disabled | `/private/tmp/replayxi-player-ball-arc-release-01.log` |
| Whitespace check | Passed | `git diff --check` |
| Current install | Matches final tested Debug executable SHA256 | `6ba711b6e5e3689962d28fdda70284815aa7e456df63cd62be44fcf58504f82e` |

The native suite ran on visionOS Simulator 27.0. Its sole skip is the absent optional transient Rocketbox qualification fixture, not the new shipping-model tests. Final native captures include both teams, near/low kits, articulated distant bodies and ball-to-boot surface fixtures. Their originals and manifests are under `/private/tmp/replayxi-player-ball-arc-full-02-attachments`.

The final app was launched without debug fixture flags. Its dashboard is visible in Simulator. The saved-review SHA256 is unchanged from the task's initial backup: `89d4201e444f635b33cd0b953a5d41a6bb084e311610d0c0b390871b4901355e`. User signing/project metadata and unrelated files are excluded from this feature backup.

## Limits that remain

- Players are improved but still stylised, not FIFA-level assets or motion capture. Both teams share geometry within each detail level; the inherited near/far rest-height difference is about 9 cm.
- Ball repair uses bounded body/boot contact proxies and tested skin-surface fixtures. It is not a general rigid-body match engine or proof of every pose/input. Valid oversized imported tracks explicitly fall back to uncorrected authored playback.
- The Move grip and Arc editor were visually checked, and their state/ownership/Undo behaviour is tested. Simulator mouse/drag attempts returned `noWindowsAvailable`; a successful hands-on drag was not observed. Headset pinch, room comfort and sustained frame rate still need device testing.
- The Release receipt proves compilation, not signed installation or physical-headset execution.

Details: [players](LOOP124_PLAYER_ANATOMY_AND_TEAM_SCALE.md), [native comparisons](PLAYER_NATIVE_VISUAL_COMPARISON.md), [ball contact](BALL_PLAYBACK_CONTACT.md), [Move and Arc](MOVABLE_WORKSPACE_AND_ARC_UI.md).
