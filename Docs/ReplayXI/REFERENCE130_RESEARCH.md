# Reference130 — usable motion sources and specific body cues

Checked 18 September 2026. Research/acquisition only: **no downloaded motion has been retargeted, integrated, visually approved or run in the app** by this task. No Blender calls, app changes, builds, accounts or licence acceptance.

## Acquired: three public CMU clips

The official [CMU home](https://mocap.cs.cmu.edu/) permits research use and inclusion in commercially sold products, but prohibits directly reselling the data, including converted data. Its [FAQ](https://mocap.cs.cmu.edu/faqs.php) permits copying, modification and redistribution without permission. These are existing CMU website terms, **not an assumed fair-use exemption or a Creative Commons licence**. Keep the direct-data resale restriction. CMU requests acknowledgement of its database and NSF EIA-0196217, plus publication citations.

Selected public links returned HTTP 200 without authentication or agreements. Only three motions and their two matching skeletons were fetched; no database crawl. Homepage, FAQ and catalogue snapshots are retained with hashes. Raw downloads remain ignored and unstaged:

`.codex-derived/Reference130/MotionSources/`

| Clip | Official description | Frames at 120 Hz | Sample span | Raw size |
| --- | --- | ---: | ---: | ---: |
| [10_01.amc](https://mocap.cs.cmu.edu/subjects/10/10_01.amc) | Football kick | 801 | 6.667 s | 638,446 B |
| [10_05.amc](https://mocap.cs.cmu.edu/subjects/10/10_05.amc) | Football kick | 436 | 3.625 s | 347,982 B |
| [09_12.amc](https://mocap.cs.cmu.edu/subjects/09/09_12.amc) | Forward/backward/sideways navigation | 1,918 | 15.975 s | 1,532,758 B |

Descriptions and rates: [subject10 catalogue](https://mocap.cs.cmu.edu/search.php?subjectnumber=10), [subject09 catalogue](https://mocap.cs.cmu.edu/search.php?subjectnumber=09). Sample span is `(frames − 1) / 120`; do not confuse it with sample-count duration. Required skeletons: [10.asf](https://mocap.cs.cmu.edu/subjects/10/10.asf), [09.asf](https://mocap.cs.cmu.edu/subjects/09/09.asf). Total raw motion+skeleton data: 2,533,706 B.

### Receipts and reproducible inspection

Within the ignored folder:

- `provenance.json`: exact source URLs, byte counts, full SHA-256 values and permission notes.
- `inspection.json`: frame/channel validation, raw joint ranges, root motion and forward-kinematics measurements.
- `inspect_cmu_motion.py`: standard-library-only offline inspection; run with Python 3. It generates only the local report.

All three motions parsed as finite, contiguous, fully specified frames: 30 bones plus root; 29 animated channel groups; 62 numbers/frame. The two calibrated skeletons are not identical. Use the correct subject pairing.

Lengths/root translations use **0.0254 / 0.45 = 0.056444444 m per stored unit**, following CMU's [unit FAQ](https://mocap.cs.cmu.edu/faqs.php). ASF bone axes and listed motion DOFs must be composed correctly; raw Euler values cannot be pasted onto the app rig. The inspector follows the [Vicon/Acclaim format explanation](https://graphics.cs.cmu.edu/nsp/course/cs229/info/ACCLAIMdef.html): fixed-axis root rotations and each bone's local basis.

### What the numbers support

| Clip | Root path / max speed | Pelvis heading span | Useful candidate / limitation |
| --- | --- | --- | --- |
| 10_01 | 2.145 m / 2.170 m/s | 79.2° | Isolated right-leg swing around 4.967 s; long still lead-in. Best first retarget test. |
| 10_05 | 3.496 m / 3.156 m/s | 65.5° | Faster approach, right-foot speed peak at 2.475 s. More whole-body translation to preserve. |
| 09_12 | 15.645 m / 1.486 m/s | 234.6° | Forward, backward and side travel with turns; walking pace, not football sprint/change-of-direction capture. |

These are measurements from the downloaded files, not match tracking. Root speed uses a central difference over up to six sample intervals. Heading is the horizontal projection of the root's +Z axis, **not recorded gaze**.

For 09_12, 1,889 samples exceed 0.2 m/s: 921 travel within 45° of pelvis facing, 193 are 45–135° sideways, and 775 exceed 135° (backwards). This directly supports separating facing from travel. It does **not** provide a ready-made defensive shuffle loop.

At 10_01's right-foot speed peak, the left foot endpoint lies in a low/slow interval from 4.833–6.467 s. Maximum horizontal drift within its detected low/slow intervals is about 3.0 cm. These are **contact candidates**, not labelled contacts: the test is endpoint height within 5 cm of its fifth-percentile height, horizontal speed below 0.2 m/s and vertical speed below 0.15 m/s for at least eight samples. It is not a sole-plane, force-plate or ball-contact test.

Observed raw toe-angle single-frame changes reach 23.4° in 10_01, 34.4° in 10_05 and 30.3° in 09_12. Do not directly ship these channels. CMU itself warns that early low-number subjects can have lower quality, toes/hands may need smoothing, and finger/thumb motion is not captured. Source: [CMU quality notes](https://mocap.cs.cmu.edu/).

### Recommended first retarget experiment

1. Start with **10_01, roughly 4.25–5.55 s**, keeping both support placement and right-leg swing. Its 4.967 s speed peak is only an inspection cue, **not a known ball impact time**. No ball channel exists in this AMC.
2. Validate the original skeleton first. Map its 30-bone structure into the native rig with explicit rest-pose corrections and leg-length ratios. Leave uncaptured fingers/face neutral; do not invent mocap for them.
3. Retain whole-body weight shift. Extract root travel separately before adapting to an authored match trajectory; avoid adding captured root displacement twice.
4. Filter noisy extremities conservatively, then solve planted soles and authored ball contact after retargeting. Check drift, knee direction, foot/ball distance and body collision. Do not smooth the sharp swing into slow motion.
5. Use 10_05 for a moving approach test; segment 09_12 into short forward/back/side transitions. None is a seamless loop: start-to-end root offsets are 1.66 m, 3.12 m and 1.09 m respectively.

These generic lab motions can improve weight shift and phase timing. They cannot establish Mbappé's volley, Martínez's save or the exact positions of off-camera match players. The final volley still needs source-specific authoring/validation; acquired clips do not establish EAFC-level quality.

## Keeper cues usable now

FIFA's 2026 session supports a ball-facing shoulder line, bent knees, balanced feet, rapid reorientation and retreat into a set stance. Arm height is contextual, not a fixed pose for the entire scene. Implement a small **adjust → plant/set → shot-cued response** sequence; keep the existing authored root path. [FIFA: managing transitions](https://www.fifatrainingcentre.com/en/environment/fifa-goalkeeper-training/sessions/managing-defensive-offensive-defensive-transitions.php)

FIFA's goalkeeping expert distinguishes set-and-react at greater shot distances from a close-range X-block. He uses roughly 6 m as a coaching discriminator and warns against deploying the block too early. For a distant volley, do not animate an anticipatory star-shaped block. This is a coaching prior, not an exact universal threshold or measured Martínez timing. [FIFA: understanding the X-block](https://www.fifatrainingcentre.com/en/game/individual-qualities/goalkeeping/understanding-the-x-block-with-pascal-zuberbuhler.php)

## Exact volley cues usable now

The final's FIFA Example3 describes a half-turn receipt, a cushioned header with a **right-foot plant**, then an inside acceleration that leaves the defender facing the wrong way. Mbappé slows to judge the return flight before tilting laterally to bring his right foot over a low ball. Preserve that change of pace and posture; avoid a generic jumping header or uniform running cycle. The article supplies no joint angles or calibrated pose timestamps. [FIFA: Mbappé, Example3](https://www.fifatrainingcentre.com/en/game/individual-qualities/world-class-skills/mbappe-predator-in-the-box.php)

## Acquisition priority

For **body-motion quality**, a small licensed football mocap set with documented support contacts, turns, passes, volleys and keeper actions is more useful next than more generic idle motion. CMU is an accessible retargeting test, not a complete football library.

For **this match's accuracy**, rights-cleared multi-angle footage and player/ball tracking matter more. Those establish actual timing and spatial constraints; generic mocap cannot recover them. Keep visible source facts, reconstructed estimates and off-camera tactical guesses separate in metadata and UI.
