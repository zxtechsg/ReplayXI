# Spatial analysis UI notes — 12 September 2026

Scope: local football replay and tactical demonstration, not active VR football.
Sources below are official public pages. This is a relevant reference shortlist,
not a measured ranking of the best apps. Paid products were not installed or tested.
Marketing claims are not evidence of Replay XI's capabilities or training efficacy.

## Sources and transfer decisions

| Reference | Documented workflow | Apply to Replay XI |
| --- | --- | --- |
| [Apple spatial layout](https://developer.apple.com/design/human-interface-guidelines/spatial-layout/) and [Design great visionOS apps](https://developer.apple.com/videos/play/wwdc2024/10086/) | Room anchoring rather than head locking; cohesive interfaces; few windows; comfortable indirect input and separated targets. | One fixed workspace, large gaze/pinch targets, distinct transport and View panel, deliberate recenter. Do not scatter buttons around the wearer. |
| [Hudl Studio](https://business.hudl.com/products/studio) | Drawings across video angles, tracked player graphics, and analyst/coach workflows. | Keep time, player selection and annotation binding connected. Open a selected mark's inspector in context. Our track binding uses authored data, not Hudl-style automatic video tracking. |
| [Tactic3D Football](https://www.tactic3d.com/football/football-software-playbook-en.php) | Animated tactical board, player viewpoints, precisely timed passes, dynamic arrows and zones. | Separate Strategy Analysis from video-reference Match Replay; retain the same play while changing views. Runs and passes should be actions on a timeline, not decorative lines. |
| [Be Your Best](https://www.beyourbest.com/en-us) | Separate scenario and matchplay modes, recreated professional situations, and replay/session review. | Start with a clear mode and exercise choice. Keep immersion focused on one decision; move details behind tools. Do not import scores or promise cognitive improvement without validation. |
| [Motion Soccer PRO](https://store.steampowered.com/app/3137350/Motion_Soccer_PRO/) | First-person player, sideline coach and tactical views of a match. | Name POV, Tactical and Touchline explicitly. Preserve the selected time across view changes. Do not copy hand-as-foot locomotion into a stationary review app. |
| [Rezzil Index](https://rezzil.com/rezzil-index/) | Discrete drills plus a separate reporting portal. | Distinguish doing/reviewing from metrics and settings. Keep the 3D scene visible while deeper options are collapsed. Do not copy proprietary scores or ranking claims. |

The right-hand column is our design inference, not a claim that those products
use these exact button placements. Public workflow evidence does not establish
target sizes, headset comfort, latency or accessibility quality in those apps.
Tactic3D's detailed viewer help returned HTTP 429; no interaction claims rely on it.

## Workspace organisation

- **Home:** Match Replay / Strategy Analysis; Saved reviews; one clear entry action.
- **Transport:** previous cue, play/pause, next cue, timeline, Player POV, Draw, Tools.
- **View panel:** POV / Tactical / Touchline, marks/ball/lanes visibility, place controls here.
- **Tools:** timeline events, decision options, annotation list, saves and settings.
- **Selected mark:** label, time window, player binding and geometry. Geometry owns
  the gesture until release; recentering cannot interrupt a scrub or joystick drag.
- **Settings:** separate Time and Workspace rows, not one overfull command strip.

Implemented this pass: captured room origin for all five attachment types;
explicit recenter in View and Settings; stable mode/save IDs; Settings rows.
Still to validate: manual spatial relocation/recovery, large-text panel overlap,
and physical comfort. No claim of a complete UI redesign or finished reconstruction.
