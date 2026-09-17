# Reference 128 — additional footage and tracking research

Checked 18 September 2026. Research only; no app changes, media downloads, forms, purchases, or data imports.

## Result

- **Usable now as an external reference:** FIFA Training Centre's exact Mbappé volley breakdown, verified playable at 1920×1080, with nine annotated stills.
- **New camera coverage found:** a separate, playable 1920×1080 cable-camera archive covers all three World Cup scenes. Its anonymous upload has **no verified reuse licence**. Do not embed, redistribute, or bundle it in Replay XI.
- **Tracking leads exist, but are not ready inputs:** WorldPose requires approved academic access and separate footage permission; PFF requires an access form and rights review. Neither was obtained.
- No additional, verified independent camera feed or public continuous tracking was found for the two City–Liverpool scenes. Existing broadcast replay angles remain the reliable visual reference.

## Coverage of the exact five scenes

Times below are **video-player times**, not match-clock times. Main-video windows were verified in the previous reference pass; new sources were checked in this pass.

| Scene | Existing official reference | New evidence / availability |
|---|---|---|
| Di María, 36′ — `final-36-counter-v2` | [FIFA full match, 36:45–37:00](https://www.youtube.com/watch?v=RgqKdplLIk4&t=2205s) | Cable feed roughly 46:08–46:26; personally checked 46:23, square ball reaching Di María. FIFA's [Scaloni interview](https://www.fifa.com/en/articles/lionel-scaloni-argentina-interview-world-cup-2022-final) also explains the central combination and far-side width. No exact continuous tracking obtained. |
| Mbappé, 81′ — `final-81-volley` | [FIFA full match, 1:30:39–1:31:00](https://www.youtube.com/watch?v=RgqKdplLIk4&t=5439s) | [Training Centre Example 3](https://www.fifatrainingcentre.com/en/game/individual-qualities/world-class-skills/mbappe-predator-in-the-box.php#example_3): verified 1080p, 40.811 seconds. Cable feed roughly 1:44:59–1:45:17. |
| Messi, 108′ — `final-108-rebound-v2` | [FIFA full match, 2:09:39–2:10:00](https://www.youtube.com/watch?v=RgqKdplLIk4&t=7779s); close replay 2:10:52–2:10:54 | Cable feed roughly 2:29:05–2:29:18. Checked 2:29:07 build-up and 2:29:15 rebound: Messi, grounded Lloris and goal-line cover are visible from behind the attack. |
| Haaland, 45+2′ — `city-45-overlap-header` | [FA full match, 46:26–46:48](https://www.youtube.com/watch?v=05ny1bmo-Kk&t=2786s); existing replay angles 47:21–47:30 and 47:33–47:49 | Official [City match gallery](https://beta.mancity.com/news/mens/city-v-liverpool-match-gallery-fac-qf-4-april-63910895) identifies photo 12 as the second-goal header. Its caption is verified, not a frame-by-frame pose measurement. No new independent playable angle or telemetry verified. |
| Haaland, 57′ — `city-57-underlap-cutback` | [FA full match, 59:34–59:51](https://www.youtube.com/watch?v=05ny1bmo-Kk&t=3574s); existing replay angles 1:00:24–1:00:38 and 1:00:39–1:00:49 | Exact event reconfirmed by the [FA report](https://www.thefa.com/news/2026/apr/04/emirates-fa-cup-quarter-final-wrap-20260404): O'Reilly cutback, Haaland finish via underside of bar. No new independent camera feed or continuous tracking verified. |

The City fixture is **4 April 2026, men's FA Cup quarter-final, City 4–0 Liverpool**. Search results for women's 4–0 wins, February 2026 at Anfield, 2023's 4–1, or May youth fixtures are not evidence for these scenes. Source-video maximum resolution for the existing YouTube references was not rechecked in this pass; do not label them 4K.

## Exact volley motion reference

[FIFA Training Centre: Kylian Mbappé — Predator in the box, Example 3](https://www.fifatrainingcentre.com/en/game/individual-qualities/world-class-skills/mbappe-predator-in-the-box.php#example_3).

Playback worked without login: native **1920×1080**, duration **40.811 s**. The video DOM exposes only a session `blob:` URL. Link the page; no reusable media URL was obtained.

Manual timeline sampling, rounded to seconds; not frame-accurate contact timings:

| Action | Clip-local estimate | Current authored contact time |
|---|---:|---:|
| Coman inward release | 7–8 s | 0 s |
| Rabiot loft | about 10 s | 1.1 s |
| Mbappé cushioned header | about 12 s | 2.6 s |
| Thuram return | about 13 s | 3.55 s |
| Mbappé volley | 14.5–15 s | 4.5 s |

Coman-to-shot takes roughly **7–8 seconds**, not 4.5. Use beat-based alignment.

Pose cues: half-turn, **right-foot plant during cushioned header**, inside acceleration past a wrong-facing marker, deceleration, sideways trunk tilt, **right-foot volley**. Not an airborne power header. These are visual cues, not recovered 3D poses.

## New cable-camera archive: useful but uncleared

[Argentina–France final, cable-camera archive](https://archive.org/details/07.9-catar-2022-argentina-francia-final-cable-6kkbps).

Verified playback: **1920×1080; 3:07:35**. Moving elevated camera, distinct from the main broadcast. More support players are visible, but this is not fixed all-22 coverage. Motion and occlusion still require calibration.

Uploader: **Anonymous Appleface**, added 1 February 2024. No rightsholder permission verified. Obtain FIFA's original isolated feed and permission before app ingestion. No download or embedding performed.

## Data and official archive leads

| Source | What is verified | Access / limit |
|---|---|---|
| [WorldPose, ETH/FIFA](https://eth-ait.github.io/WorldPoseDataset/) | WC2022 multicamera-derived SMPL poses and calibrated broadcast cameras; 80+ sequences. | [Request/terms](https://worldpose.ait.ethz.ch/) require institutional academic access. Footage needs a separate FIFA agreement. Terms prohibit commercial use/promotion, redistribution and re-identification. Exact coverage of our three goal windows is **unverified**. No form submitted. |
| [WorldPose official visualisation code](https://github.com/eth-ait/WorldPoseDataset/tree/visualization) | Public README expects camera `.npz`, pose `.npz`, and clip `.mp4` folders. | Public tree has no match/goal-window manifest. Third-party `ARG_FRA_*` filenames are not proof that these goals are included; their timestamps were not mapped. No restricted poses read or copied. |
| [PFF enhanced WC2022 dataset](https://www.blog.fc.pff.com/blog/enhanced-2022-world-cup-dataset) | Advertises broadcast tracking, events, metadata and grades for all 64 matches, with per-match tracking files. | Form-gated access. Actual final files, frame rate, off-camera inference, missingness and redistribution terms were not inspected. Not skeletal motion capture and not verified all-player ground truth. No form submitted. |
| [FIFA Audiovisual Archives guide](https://www.archives.fifa.com/user_guide) | Official archive includes match feeds, rushes and other original material. | Commercial portal, not public access. [Terms](https://www.archives.fifa.com/fifa_terms_and_conditions) require a separate written licence for content use. Ask about isolated cable/tactical cameras and high-resolution masters for the exact windows. No access request sent. |
| [FIFA final post-match report](https://www.fifatrainingcentre.com/media/native/world-cup-2022/report_128083.pdf) | Exact final; team/individual and formation context. | Aggregate analysis, not timestamped 22-player trajectories or joint rotations. Can constrain broad behaviour, not recover unseen actions. |
| [FIFA+ FACTS: Argentina v France](https://www.plus.fifa.com/fr/content/facts-argentine-vs-france-qatar-2022-2022/30bd93ec-5bf9-4b0f-9584-3c49ce76980a) | Public metadata identifies a 35-minute analysis programme about the final. | Playback/new-angle content not verified in this pass; later fetch returned unavailable. Candidate, not an obtained source. |

Previously assessed StatsBomb 360 remains sparse event snapshots, not continuous tracking. This pass did not read or copy its coordinates. Its rights restrictions still need review before incorporation.

## Recommended next steps

1. Calibrate volley timing and planted-header/body-turn poses against the official Training Centre clip. Keep the evidence-labelled authoring workflow; no claim of recovered motion capture.
2. Request FIFA permission for isolated cable/tactical feeds and high-resolution masters of match minutes 35–36, 80–81 and 108–109. Ask specifically for camera calibration and timecode if available.
3. If the project qualifies, the user/institution can request WorldPose access and ask whether the exact windows exist. Clarify identity use and whether a named-player MVP presentation is allowed **before** using data.
4. Request PFF access and check licence, frame rate and visible/inferred-player flags. Treat positions as constraints, not ground-truth limbs or gaze.
5. For City–Liverpool, ask the clubs/FA/rightsholder for original replay/isolated cameras for 45+2′ and 57′. Until then, retain explicitly inferred off-camera paths; no public tracking was verified.

These sources can improve a convincing reconstruction. They do not establish FIFA-game-level motion fidelity or exact unseen player actions.
