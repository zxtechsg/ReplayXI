# Reference 129 — motion fidelity and usable data

Checked 18 September 2026. Research only. No media or motion assets downloaded;
no accounts, access forms, purchases or licence agreements submitted.

## Main finding

The next useful gain is **better motion choice, contact support and timing**, not
more idle movement. The existing native code already has separate travel/facing
intent, fixed-length leg IK, bounded neck/head motion, contact cues, source-skin
retargeting and upper-body variation. Build on those rather than replacing the
engine or adding unrestricted joint motion.

The proposals below are engineering choices informed by the linked sources.
They are **not recovered motion capture** or a claim of EAFC/FM parity.

## Implement now

| Priority | Change | Evidence and fit with this app |
|---|---|---|
| 1 | Preserve a planted support foot during a directional step; match stride distance to actual travel. | Current `ReplayAthleteMotion.groundingReference` resolves sole height, not a general horizontal stance anchor. `ReplayAthleteMovementIntent` rotates the step toward travel, but that alone is not world-space foot locking. Ubisoft identifies foot locking/IK as a final motion-quality step; Epic describes stride scaling against root speed. |
| 2 | Use distinct forward-run, side-step and backward-recovery intent. Keep the chest only partly toward the ball while recovering at speed. | Epic separates locomotion direction from facing, distributes the correction through the spine and limits excessive rotation. A forward run twisted through 180 degrees is not a substitute for a backward gait. Retain smooth speed/angle bands and the existing seek-stable clock. |
| 3 | Author the volley's particular preparation and recovery. | FIFA's exact final-goal analysis shows a right-foot plant during the cushioned header, inside acceleration, a check of pace, sideways trunk tilt and a right-foot volley. A generic jumping header or upright kick loses the defining movement. |
| 4 | Make defenders' posture depend on their tactical job. | FIFA coaching describes low, side-on, adjustable containment, with the decision to press or hold informed by the pass and first touch. Near-ball contain, recovering run and runner-tracking should not share one ball-facing pose. |
| 5 | Replace purely periodic scans with bounded pre-receive / runner-check cues where supported. | FIFA teaches an over-shoulder scan before receiving, then an open receiving shape. Keep direct ball attention at contact. Do not treat a head direction inferred from video as measured eye gaze. |
| 6 | Audit skin deformation and both LODs at real action poses. | Existing Biped hierarchy is unusual: thighs are under Spine, not Pelvis. Retarget in actual model/parent space; preserve measured segment lengths and skin scale. Inspect shoulders, groin, knees, neck and boot soles in exported native rendering, not only a Blender viewport. |

Primary implementation references:

- [Ubisoft: learned motion matching](https://www.ubisoft.com/en-us/studio/laforge/news/6xXL85Q3bF2vEj76xmnmIu/introducing-learned-motion-matching)
  explains matching foot positions/velocities, hip velocity and future trajectory;
  transition blending and contact cleanup remain important. It also explicitly
  cautions that motion matching only plays the data supplied: it does not create
  missing action combinations. A large new controller is unnecessary for five
  fixed demonstrations; offline-authored clips are the smaller first step.
- [Epic: pose warping](https://dev.epicgames.com/documentation/unreal-engine/pose-warping-in-unreal-engine)
  documents orientation compensation, distributed spine twist, rotation bounds,
  stride scaling from locomotion/source-motion speed and limb-extension limits.
  These are transferable design ideas, not a request to import Unreal code.
- [Blender: IK constraint](https://docs.blender.org/manual/id/5.0/animation/constraints/tracking/ik_solver.html)
  documents pole targets, affected chain length and optional stretching. For our
  athlete rig, keep limb lengths fixed, control knee/elbow bend direction and
  inspect the evaluated pose. Adding a constraint is not proof of anatomy or
  proof it survives export.
- [FIFA: exact Mbappé volley, Example 3](https://www.fifatrainingcentre.com/en/game/individual-qualities/world-class-skills/mbappe-predator-in-the-box.php#example_3)
  provides the scene-specific body cues above. Earlier manual timing in
  `REFERENCE128_RESEARCH.md` places Coman-to-shot at about 7–8 seconds versus
  the current 4.5-second authored beat. Those are rounded observations, not
  frame-accurate measurements. Re-time only in a versioned scene so saved
  time-linked annotations do not silently change meaning.
- [FIFA: defending outnumbered](https://www.fifatrainingcentre.com/en/practice/talent-coach-programme/block-and-prevent/1v2-attack-v-defence-defending-outnumbered.php)
  and [defending as a unit](https://www.fifatrainingcentre.com/en/practice/elite-sessions/out-of-possession/defending-as-a-unit.php)
  support adjustable containment and coordinated pressing.
- [FIFA: receiving between opponents](https://www.fifatrainingcentre.com/en/practice/talent-coach-programme/build-and-progress/passing-activation-playing-and-receiving-in-between-opponents.php)
  supports a pre-receive scan, open body shape and back-foot receiving.

### Deterministic contact implementation

These are proposed app-specific constraints, not clinical joint limits:

1. Derive stance entry/exit from the absolute gait clock or authored contact
   interval. Evaluate the support anchor from that event, not the previous frame.
2. Correct only within reachable limb space. Fade at heel strike/toe-off; allow
   explicit heel/toe roll. Do not freeze both feet through a moving sprint.
3. Keep current foot/head/keeper contact solvers authoritative. No secondary
   layer should displace the admitted strike or turn the head away at contact.
4. Keep extreme side/backward locomotion conservative: transition to a turn and
   forward recovery when the intended pace cannot be represented convincingly.
5. Test random seeks, reversed playback and speed changes against the same pose
   at the same match time. Retain both-team scale, bone-length and floor checks.

## Plausible out-of-frame behaviour

Game knowledge can constrain missing movement, but cannot establish what an
unseen player actually did. Keep **observed**, **estimated**, and **inferred**
separate. Use observations as fixed anchors and make the smallest plausible
change between them. Do not improve the defenders into a counterfactual perfect
defence: their late turns and wrong-footed reactions are part of these goals.

| Scene | Useful prior for unseen players — not a claim of actual tracking |
|---|---|
| Di María counter | Recover toward goal while checking the central combination; the far-side runner remains a separate threat. Cover defenders should not all chase the current ball holder. |
| Mbappé volley | The displaced marker has to turn and recover after the give-and-go. Nearby cover reacts to the return pass; it should not anticipate the eventual shot before a visible cue. |
| Messi rebound | Follow the first shot, goalkeeper parry and rebound as separate beats. A covering defender protects the goal line; the scorer follows through for a second ball rather than stopping at the first shot. |
| City overlap/header | Distinguish the wide defender facing the crosser from central defenders tracking the striker and far-side cover. On crossing flight, footwork prepares for the aerial contest. |
| City underlap/cutback | Near-post protection, runner tracking and cutback cover have different facing directions. The finisher's check of run should not be copied by every nearby player. |

The exact World Cup alternative-angle and City replay references remain in
`REFERENCE128_RESEARCH.md`. No newly verified camera or telemetry covering the
five exact windows was obtained in this pass. These coaching priors should not
be labelled as reconstruction ground truth.

## New practical motion/data leads

| Source | Verified utility | Access and limits |
|---|---|---|
| [CMU motion catalogue](https://mocap.cs.cmu.edu/search.php?maincat=4&subcat=7) | Football kicks `10_01`, `10_02`, `10_03`, `10_05`, `10_06`, `11_01`; official full index lists 120 Hz. `09_12` is forward/backward/sideways navigation. Useful source candidates for a small, audited Blender clip library. | [CMU terms](https://mocap.cs.cmu.edu/) allow incorporation in commercial products, not direct resale of raw/converted data, and request attribution. CMU warns early captures can be lower quality, toes/hands noisy, and fingers/thumbs not actually captured. Catalogue/terms were visible through indexed official pages; direct page fetches intermittently failed. No asset files fetched or motion quality inspected. Not elite or match-specific capture. |
| [Mixamo](https://www.mixamo.com/) | Humanoid rigging and a broad animation library are available. Could fill ordinary locomotion gaps after clip-specific inspection. | [Adobe FAQ](https://helpx.adobe.com/creative-cloud/faq/mixamo-faq.html) confirms free Adobe-ID access and royalty-free personal/commercial project use. Specific football clips and current download access were not verified. Adobe's [staff licensing FAQ](https://community.adobe.com/questions-696/mixamo-faq-licensing-royalties-ownership-eula-and-tos-589400) bars raw-file distribution: do not push downloaded source animations to a public asset repository. No sign-in or download performed. |
| [Ego-Exo4D](https://docs.ego-exo4d-data.org/) | A new useful training-reference lead: synchronized first-/third-person sports footage, body pose and coaching annotations. The [paper](https://ego-exo4d-data.org/paper/ego-exo4d.pdf) describes calibrated Aria plus 4–5 static GoPros; the [pose tutorial](https://docs.ego-exo4d-data.org/tutorials/pose/) demonstrates reprojection for checking 3D joints in multiple views. | [Access agreement required](https://docs.ego-exo4d-data.org/getting-started/), normally about 48 hours. Published [model agreement](https://ego4d-data.org/pdfs/Ego-Exo4D-Model-License.pdf) is marked draft for review and allows specified research/product-development uses while restricting data appearing in products or being redistributed. User/institution must review actual terms; not a drop-in animation pack. These are skill demonstrations, not our matches. No access requested. |
| [WorldPose](https://eth-ait.github.io/WorldPoseDataset/) | The strongest exact-tournament pose lead remains multicamera-derived World Cup SMPL poses and camera parameters. | Public page reconfirms application-based academic access and a separate FIFA footage agreement. Exact five-window coverage still unverified. Detailed restrictions recorded in Reference 128 remain unresolved; this pass's request-page fetch timed out. No poses obtained. |
| [SoccerNet Game State Reconstruction](https://www.soccer-net.org/tasks/game-state-reconstruction) | Useful architecture for eventual video-to-replay: recover field positions, roles, teams and jersey numbers. That is a trajectory/identity layer, not a full skeletal motion solution. | Public project now lists [GSR data on Hugging Face](https://github.com/SoccerNet/SoccerNet), but its [FAQ](https://www.soccer-net.org/faq) says dataset use is research-only; public availability does not grant commercial footage rights. No coverage of our five windows verified or data imported. |

Do not import Ubisoft LaFAN1 as a freely distributable animation library: its
[official README](https://github.com/ubisoft/ubisoft-laforge-animation-dataset/blob/master/README.md)
specifies **CC BY-NC-ND 4.0**. Learn from the method; obtain appropriate permission
before distributing adapted motion.

## Validation and next acquisition

- Render source-camera overlays at the same visible contacts and body-pose beats.
  Inspect torso direction, planted foot, ball-contact gap and silhouette; a clean
  unit test is not visual approval.
- Measure planted-foot world displacement, knee/elbow continuity, skin-floor
  clearance, fixed bone lengths and joint-angle velocity. Set explicit project
  thresholds after viewing an approved clip, not by claiming universal human
  limits.
- Use the same fixture for white/red and native/far rigs. Compare full-speed
  motion, not only still frames; test the real headset before claiming its frame
  rate or comfort.
- First acquisition: a few **rights-cleared football clips** covering side-step,
  backward recovery, turn-and-sprint, deceleration, pass/receive and the specific
  volley. Inspect and retarget offline; keep source provenance with each clip.
- Best long-term match accuracy input: authorised tactical/cable feeds plus
  calibrated player tracks. Best long-term animation input: licensed football
  mocap or an approved multi-view pose set. More geometry alone supplies neither.
