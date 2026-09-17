# Explicit football interactions — Loop 125

## Scope

Native player animation for authored match reconstructions. No new meshes,
textures, licences, skeletons, camera motion, authoritative player-root motion,
or concurrency-cap increase. This is procedural animation, not recovered mocap.

## Changes

- `ReplayAthleteInteractionCue` carries the recorded player, contact time,
  receive/pass/shot/dribble/header/save kind, leg, actual ball centre, outgoing
  direction and optional world-space supporting-foot point.
- A shared stateless solver places the striking boot at the sphere surface
  (`centre − normalizedDirection × 0.11m`) and plants the supporting sole.
  Fixed bone lengths are preserved; unreachable goals clamp rather than stretch.
- The short full-support interval is 55ms before to 70ms after contact. Quintic
  outer blends preserve deterministic scrubbing, repeat and reverse playback.
- Headers use an upper-body cue rather than foot-strike IK. Parries now have
  a 45–340mm local support crouch, both soles planted, and fixed-length hand
  reach to the actual sphere. Hand markers are rig conventions, not extracted
  skin vertices; an event label is not evidence of exact head/hand collision.
- Licensed near/low skins prepare two actual boot-vertex markers from their
  native imported weights and inverse binds on the cold path. Contact posing
  uses each rig's real lengths and neutral axes; toe descendants settle only
  during explicit contacts. Existing full weighted floor guards stay active.
- Optional `presentationPose` is distinct from `stationaryPose`. It allows
  ball-facing side/back steps and low-speed readiness without making a moving
  player stand still. Legacy callers supplying neither keep the old path.
- Directional footwork redirects ankle trajectories, keeps boots facing with
  the body, and uses forward knee poles. Nearby-ball readiness adds a small
  local crouch and relaxed arms, preserving the stationary sole goals.

No mesh scanning, asset loading or texture creation is added to replay updates.
Marker preparation is bounded by the existing 5,012-vertex source budget. The
extra per-frame work is a bounded set of two-bone solves and existing track
samples, not a new simulation history. Hardware frame rate is not measured here.

## Native evidence

First checkpoint: all seven `ReplayAthleteInteractionTests` passed in
`/private/tmp/replayxi-native125-integration-01.xcresult`.

Actual imported boot-marker report:
`/private/tmp/replayxi-native125-integration-01-attachments/2EB4C4D6-2AC6-4B30-B17F-C433C22A8F54.json`.

| Skin | Negative-X boot error | Positive-X boot error |
| --- | ---: | ---: |
| Near | 5.99983 mm | 6.00000 mm |
| Low | 5.00094 mm | 5.00034 mm |

These errors match the respective 6mm/5mm floor padding. After this measured
receipt, the provisional 12mm bound was tightened to each profile's padding
plus 0.1mm, with separate 0.1mm X/Z bounds. This tests a mesh-derived contact
marker, not full boot-triangle/sphere nonintersection through every motion.

The ten-case directional/readiness checkpoint passed. Eleven fixed-camera
native frames passed in `replayxi-native125-integration-04.xcresult`, with
Display P3/top-first calibration and maximum channel error 1. All eleven were
visually inspected. Pass foot placement is coherent across far/near/low;
wind-up/follow-through remain restrained. These are static audit frames.

### Defects caught, not hidden

1. The first low-parry frame kept the hands at chest height while the ball was
   at 0.65m. Native near/low palm markers were 757.5–781.8mm from its centre.
   The failing two-case receipt is `replayxi-native125-integration-05.xcresult`;
   the source JSON is
   `/private/tmp/replayxi-native125-integration-05-attachments/30FB1C4E-E032-480F-96CF-E45CC500420A.json`.
2. After planted-crouch/arm IK, both parry cases passed in integration-06.
   Native palm distances are 113.2–114.2mm from the 110mm-radius sphere centre,
   with existing floor guards and exact rewind retained. The corrected far
   frame visibly reaches the low ball. Source:
   `/private/tmp/replayxi-native125-integration-06-attachments/06766849-9EA2-4F65-AB5F-0D36737E4384.json`.
3. A high-save control then exposed a 14.97mm raw sole lift: zero crouch at
   high ball heights left the fixed leg too short. All saves now retain at
   least the 45mm support crouch. Exact sole bounds remain 30µm, tested over
   six heights from 0.65 to 2m; no floor assertion was loosened. The old
   unchanged-body assertion applies only to headers: saves intentionally
   bend locally, with unchanged X/Z and no authoritative root movement.
4. Rabiot's grounded loft originally pitched the boot to the upward launch
   vector, burying the heel and forcing the floor guard to lift the toe.
   The actual-study error was roughly 14cm. Grounded contacts now keep the
   boot flat; elevated-foot pitch blends in above 0.22m ball-centre height.
   The actual sphere-surface goal and floor guards are unchanged.

Integration-07 passed all eleven motion cases and both parry cases. The same
native visual method has been extended by only two frames to inspect near/low
parry geometry as well (thirteen total). All thirteen passed in
`/private/tmp/replayxi-native125-full-01.xcresult`. The new near/low frames and
the matched far parry were visually inspected: the body crouches, both feet
remain supported, and the hands reach the low reference ball. Near/low agree
closely. The hands remain crowded near the midline; this is a simple block/parry,
not a detailed keeper catch. The generic outfield kit is a pose-audit fixture.

Final-frame evidence in `/private/tmp/replayxi-native125-full-01-attachments/`:

- Near parry: `2FF7EF0E-627B-4916-8267-DDBB3FABA5B6.png`.
- Low parry: `CD38A775-8841-48D1-8812-6228FA7F837D.png`.
- Far parry: `6B880751-1722-4CDC-8873-0FCE156290B3.png`.
- All thirteen frame bounds/poses: `F9B6D646-1C3D-432A-968C-FFCC9A999C4C.json`.
- Calibration: `DCEF993C-2182-4BE9-8CFA-AF0471AB7B51.json`, Display P3,
  top-first rows, maximum channel error 1.

The near/low parry frames contain 25,129/25,028 non-background pixels, with
bounds `[92,173,406,444]` in the fixed 512×512 frame. The retained strict
nonempty/clipping controls passed; those bounds include the ground plate and
are not a player-only silhouette measurement.

### Actual-study contact diagnostics

`ReplayReferenceContactReachTests` bakes each of the three studies, then measures
the admitted actual ball contact against the visible far marker and native
near/low boot vertices. The bound stays 3cm. Header/save events are excluded
from this **foot** test; missed contacts remain explicitly reported, not counted
as successes. The test never edits roots or changes contact admission.

The first receipt caught unreachable authored positions for Lautaro/Thuram and
the grounded-loft defect. Root/physics calibrated those scene positions and
contact conditions separately. In integration-06 the admitted-contact maxima
were 6.00mm for the counter, 23.63mm for the volley and 24.68mm for the rebound.
The counter then had only three of five contacts, so that receipt does not
prove a complete play. Integration-07 completed all three plays but exposed
two newly admitted counter contacts around 3.4–3.5cm. Physics admission is being
tightened; the 3cm visual test was not relaxed.

With the native physical contact gate tightened to 20mm, all three reach tests
passed in `replayxi-native125-full-01.xcresult`. Each test bakes its own fresh
recording, and every planned contact was admitted:

| Study | All contacts | Foot contacts measured | Maximum surface error, all LODs |
| --- | ---: | ---: | ---: |
| Counter | 5 / 5 | 5 | 12.848 mm |
| Volley | 5 / 5 | 4 | 10.231 mm |
| Rebound | 6 / 6 | 5 | 9.759 mm |

Minimum measured floor clearance was approximately 2mm in all three studies.
The header/save exclusions account for the two non-foot events; they are not
silently counted as foot-contact passes. Source JSONs in the same full-01
attachment directory are `D35DC383-8BD1-4A4C-8637-72A7D36063E8.json`,
`46A71FEA-629E-4F5F-9F83-7A584E52F579.json`, and
`226478F7-A203-4904-840D-A49D5AECB5AB.json`, respectively.

The first full run had 1,039 total tests, one optional skip and one unrelated
stale Move-control source assertion. All player motion/reach/visual cases
passed. That receipt was not clean; later full-suite results are recorded in
the final checkpoint below.

### Separate actual-header audit

The foot tests deliberately exclude headers. A follow-up actual-contact test
caught a real remote header in the volley study: the ball was at 1.9244m and
0.438m horizontally from the actor root. Native full-head triangles were still
332.4mm (far), 208.2mm (near) and 208.3mm (low) from the ball's sphere surface.
The bound is 30mm, unchanged. This uses every real head triangle, with actual
read-back skin transforms and inverse binds—not a convenient invented marker.

Before evidence:
`/private/tmp/replayxi-native125-header-02.xcresult`, with JSON
`/private/tmp/replayxi-native125-header-02-attachments/8F7A6D68-0BC6-48CE-A7E5-101152426A1F.json`.
Near/far PNGs `A20302C4-E3E3-4C44-A6C1-843F449CFFB4.png` and
`EADC4C98-E237-475C-B74A-96E11EB1A2FB.png` in that directory were inspected.
They visibly show the ball above/away from the head. The first diagnostic
build stopped at a test-only compiler expression timeout; the tuple-map was
split into an explicit loop before this successful failing-test receipt.

The bounded correction replaces the fixed backward header lean
with a ball-directed torso rotation (maximum 0.45rad). The procedural path
uses its spine/neck/head-root chain; each licensed skin uses its actual
model-space chest/head pivots. No joint translations, bone lengths, actor root,
mesh or normal run cadence are changed. A small preload/follow-through remains.
Only an active skinned header adds one bounded 80-joint model-space rebuild;
ordinary playback keeps its existing update path.
Authored header route/height calibration is separate from animation, not an
automatic root teleport. A distance pass alone does not prove exact forehead
anatomy.

`replayxi-native125-header-03.xcresult` passed the new direction/length/bend-cap
control, all eleven existing interaction tests, both synthetic parry tests and
the three admitted-foot-contact tests. It did not admit the revised header,
so its early unwrap failure is not a mesh-contact pass or a measurement of the
corrected head pose. Physics/path calibration continues separately. A new
actual-save audit also exposed an unreachable authored keeper contact; the
synthetic parry receipt alone does not validate that match event.

### Final actual-contact correction

`/private/tmp/replayxi-native125-contact-final-01.xcresult` passes all 24 selected
physics, scenario, foot, header and save tests. Every study completes all planned
actions and reaches the goal. The current foot maxima are 12.85 mm (counter),
19.90 mm (volley) and 9.76 mm (rebound), against the unchanged 30 mm limit.

The far rig's taller head needed a bounded contact stop. Its hash-verified
head bounds define a skull sphere, excluding the neck. A fixed search of at
most eight probes and ten refinements stops the torso lean before penetration.
There are no mesh scans or asset loads in this operation. Native skins still
use their own chest/head pivots. No actor root, joint translation or bone
length is changed.

Actual full-head triangle gaps are 17.30 mm (far), 6.17 mm (near) and 7.77 mm
(low), with no measured penetration. The near/far contact frames were inspected;
they show a restrained glancing/crown contact, not a recovered forehead header.
The head/body native collision proxies are now separate, avoiding an oversized
shoulder-width cap above the skull.

The keeper now faces the incoming shot, not the future rebound receiver. The
authored keeper route and rebound target were adjusted, and admission waits
until the ball is within 0.50 m horizontally. Both near/low palm markers reach
the actual native save within 2.72–3.67 mm of the sphere surface. The test also
checks planted soles and exact pose restoration after seeking. Palm markers
remain rig conventions, not measured hand-skin triangles. The complete rebound
still finishes in goal without disabling any collision proxy.

Final focused evidence directory:
`/private/tmp/replayxi-native125-contact-final-01-attachments/`.

- Header mesh contact: `88E72A72-B8F8-47E9-B789-4E0C3752764F.json`.
- Actual save: `922936B6-E525-41CF-AE41-85ED7256A86D.json`.
- Near/far frames: `0CD1A713-1C90-4EBF-BE66-748D2BBF2B70.png` and
  `47E9A00F-99DF-4983-BD53-4864674A5551.png`.

Earlier failure receipts above are retained as history, not current status.
See the [final checkpoint](NATIVE125_CHECKPOINT.md) for full regression and
Release build results.

## Limits

- No promise that an unreachable recorded contact can be hit while keeping the
  actor root fixed. The solver exposes/clamps the geometric limit.
- The old procedural fallback and licensed full skin have different anatomy;
  each skin's own lengths and anchors are used, but this is not uniform mocap.
- Normal source-run cadence is unchanged. These explicit contact plants and
  directional/readiness blends do not promise to eliminate every instance of
  sliding in the original run cycle.
- Native ball colliders are coarse proxies. Ball solving/recording, action
  selection and scene trajectory work are owned by the parallel physics/root
  tasks, not this player module.
- The render fixture's ball is a fixed contact reference. It is not the native
  physics trajectory, SwiftUI, or a headset comfort/readability test.
