# Five referenced plays — 17 September 2026

## Delivered scope

- Three Strategy analysis studies: Argentina–France counterattack, one-two volley,
  and rebound finish.
- Two Match replay studies: Manchester City–Liverpool overlap/header and
  underlap/cutback.
- Compact video-source badges beside situation titles, with timestamped links,
  verified alternate replay angles and explicit reconstruction limits.
- All 22 players named in each study, with match-specific shirt numbers.
- Rebuilt full-pitch counter with the missing early Mac Allister layoff, corrected
  rebound chain/finishing foot, and separately authored City supporting routes.
- Real native ball recordings, explicit receiving/dribble contacts and bounded
  turns. The City header now prepares towards the incoming cross instead of
  turning towards goal before contact.
- Versioned counter/rebound IDs preserve original paths and times for old saved
  annotations. Restored legacy matches remain visible in the sidebar.
- A Blender MCP authoring pipeline shares native paths, ball physics and key-actor
  rig poses. The Blender review file is separate from the app; it does not replace
  runtime assets or add per-frame Blender work to the headset.

## Evidence

Source windows, rosters, foot checks and alternate views are recorded in
[SECOND_MATCH_REFERENCE.md](SECOND_MATCH_REFERENCE.md) and
[FOOTBALL_REFERENCE_STUDIES.md](FOOTBALL_REFERENCE_STUDIES.md).

The final focused native run, `replayxi-reference127-contacts-export-15`, passed
32 tests. It checks all five recordings, all 27 planned contacts, goal entry,
foot/head contact across three model detail levels, keeper palm contact, source
metadata, versioned saves and 120 Hz path-speed sampling.

The manifest at `.codex-derived/Reference127/five-studies.json` has SHA-256
`d4e70d6a42bb1a06342d6af6c1d1c3fdbba456ff4afd2c13041ba8de3456b8af`.
It contains all 110 player tracks, recorded ball motion, actual contact instants
and sampled 80-joint poses for the ball-contact actors.

The earlier full run found a real visible-header gap and three outdated test
expectations. The header was corrected; the contact limits were not loosened.
Final verification:

- `replayxi-reference127-full-16`: 1,093 XCTest cases, one optional skip, zero
  failures; both separate Swift Testing asset tests pass as well.
- After the final copy-only change from “Tracked replay” to “3D replay”,
  `replayxi-reference127-copy-17` passed all 13 source/copy/navigation tests.
- Unsigned Release build for physical visionOS: `BUILD SUCCEEDED` in
  `/private/tmp/replayxi-reference127-device-final.log`. Signing/installing on a
  physical headset and headset performance were not tested.
- Python: 154 tests, 12 environment/optional skips, zero failures. This includes
  16 Blender workflow tests.
- Simulator screenshots show the two Match replay entries, source badge and
  loaded spatial pitch/control deck. The UI connection rejected click actions;
  live popover interaction is not claimed as verified. The latest City header
  demo was launched in memory-only debug mode; edits there do not persist.
- The persistent review file remained byte-for-byte identical to its pre-test
  backup (SHA-256 `e80a4722882e6bd823889c1eda73bfd8ec49b384d14bc8d37efce6c063453348`).

Blender output: `.codex-derived/Reference127/ReplayXI-FiveReferenceStudies-01.blend`
(35,034,683 bytes), SHA-256
`3044c174ea9ffebb20454fafd133174731cb4be2acda782d6ca2ee4a8e298be1`.
All five scenes were built through Blender MCP. 154,800 bone matrices, 32,846
player-root samples and 5,885 ball samples were checked. The source transform
mapping is verified; natural animation and frame-accurate reconstruction are
not implied. See [Blender receipts](BLENDER_REFERENCE_STUDIES.md).

Four agent-owned synthetic QA scenes were removed from the final review copy.
They remain recoverable in `ReplayXI-ThreeStable-01.blend`; the user's original
startup scene and app assets were not changed.

## Data found, not silently bundled

- [PFF's World Cup dataset](https://www.blog.fc.pff.com/blog/enhanced-2022-world-cup-dataset)
  advertises broadcast tracking and events for all 64 games. Access is via a form.
  No personal data was submitted; files and their reuse terms were not obtained.
- [StatsBomb open data](https://github.com/hudl/open-data) includes the final's
  events and sparse 360 snapshots. Its published agreement was checked. No raw
  dataset or derived coordinates were committed or bundled.
- The supplied City–Liverpool broadcast includes useful end-line and reverse
  replays. A focused search did not find an open continuous tracking feed for
  that exact fixture.

## Limits

This is an authored, video-referenced MVP, not FIFA-level motion capture or an
exact reconstruction. Off-camera positions, gaze and limb motion remain estimates.
The neutral kit/body assets are not player likenesses. Surface contact tests do
not prove correct football technique; the volley includes a crown glance, and the
City finish is not a verified crossbar collision. Blender's background locomotion
is illustrative. Simulator/test renders do not establish headset FPS or comfort.

The next fidelity step is licensed continuous tracking plus football-specific
motion capture and frame-by-frame camera calibration, not more guessed keyframes.
