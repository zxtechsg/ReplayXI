# Reference 129 — source-informed motion and full-team authoring

18 September 2026. Local-only native RealityKit. This pass improves the existing
licensed rig; it does not introduce EA assets, match motion capture or automatic
video reconstruction.

## Implemented in the app

- Directional footwork reaches its blended ankle goal once, retains bone twist,
  and keeps faster lateral steps in separate foot lanes. Readiness crouches
  preserve their sole positions. White and red use the same solver.
- Existing validated contact poses remain authoritative during each touch.
  A 0.12-second eased preparation/recovery margin transitions to the revised
  directional solve. The native physics admission window is unchanged.
- `final-81-volley-v2` replaces the featured volley, not its saved predecessor.
  Its turnover-to-shot interval is 7.4 seconds, informed by rounded observations
  in FIFA's Example 3. This is not a frame-calibrated reproduction.
- All 22 players in that revised study have separate authored routes. Recovery,
  central cover, far-side attack, rest defence and trailing outlets remain
  distinct. One marker turns after the give-and-go instead of all defenders
  facing and following the ball together. Unseen paths remain inferred.
- The receiving header now has an explicit anatomical right-foot plant and a
  raised trailing foot. Its contact-height envelope waits for the dropping ball.
  Cached real skull probes bound the native chest aim without stretching bones.
- The side audit found that the legacy procedural gait labels X lanes, whereas
  the source model names anatomical limbs. The new header maps anatomy to the
  correct lane. The new volley's shot also uses the source's anatomical R_Foot.
  Older kick conventions and saved scenes are deliberately not globally flipped.
- The original `final-81-volley` retains its roster, paths, 8.5-second duration,
  ball contacts and reference metadata. Old and new time-linked annotations
  load into their respective versions.

## Native verification

- Full simulator run: `/private/tmp/replayxi-reference129-full-08.xcresult`.
  1,141 XCTest cases: 2 skipped, 0 failures; 2 additional Swift Testing tests pass.
- All five current studies complete all 27 planned touches with zero misses and
  five goals. Actual near/low/far header-surface tests pass at both header scenes.
- Nine new directional-motion tests cover both teams, all detail levels, exact
  rewind, blend continuity, bone dimensions, foot lanes and protected contacts.
- Four grounded-header tests cover explicit/legacy behavior, anatomy, seeking
  and native support-foot stability. The native R_Foot stays within the existing
  2 mm horizontal test bounds through the fully weighted plant on near/low skins.
- Four versioned-volley tests cover timing, 22-player routes, frozen legacy data
  and saved-annotation isolation.
- Unsigned visionOS Release/device compilation passes:
  `/private/tmp/replayxi-reference129-device-09.log`.
- Actual native header images and triangle measurements:
  `.codex-derived/Reference129/header-08/`. Sphere-to-head gaps are approximately
  -15.8 mm near, +7.1 mm low, -2.9 mm far, inside the unchanged 30 mm contact test.
  This is not zero penetration or proof of exact forehead technique.
- Native red-team running, braking and backward-motion stills inspected in
  `.codex-derived/Reference129/movement-06/`. Stills do not prove motion quality
  over the entire clip or headset comfort/frame rate.

An initial new native-foot test caught the anatomical-side mismatch. It was
fixed in the new header's mapping, not by widening the acceptance thresholds.
The earlier failing receipts are retained; `full-08` is the final native run.

## Blender authoring

The optional exporter now accepts one selected study with all 22 native rigs at
20 Hz plus exact contact instants, and the same tactical attention selection as
the renderer. Root samples include every rig instant. The ball uses the native
physics recording; Blender does not resimulate or attract it toward players.

- Native export test passes: `/private/tmp/replayxi-reference129-export-09.xcresult`.
- Source JSON: 26,901,016 bytes, below the unchanged 40 MiB parser limit.
- Source SHA-256: `685267b1c47d17fb260374d57c8b328e39fcf34af914cf50e0bd545cbbfe2b98`.
- 22 native rigs, 4,708 sampled poses, five contacts. Transform rows are stored
  losslessly as Float32 bit-pattern tables; this is not quantization.
- 27 Python parser/export tests pass, including exact Float32 round-trips,
  malformed payload rejection, timestamp coverage and generated-code syntax.
- Safe mode remains enabled. Data transfer was split into guarded chunks below
  the addon's 200,000-byte script cap. No external scripts, `.blend` libraries,
  handlers or drivers are executed.

Blender's new volley scene verifies all 376,640 exported bone matrices across
214 pose instants, 9,328 root samples and 1,261 ball samples. Root/ball position
error at the supplied timestamps is zero; the largest matrix-element error is
`3.82e-6`. All 22 characters use the exported native poses. Verification covers
transform fidelity, not recovered motion or a perceptual realism score.

The all-near offline export is an editable authoring/audit artifact, not a claim
that all 22 high-detail characters run concurrently on the headset. Runtime LOD
and frame-budget policies are unchanged.

Saved artifacts under `.codex-derived/Reference129/`:

- `ReplayXI-Volley-Native22-01.blend` — 91,410,009 bytes; a new copy containing
  the revised study and all previous scenes. The user's untitled Blender file
  path remains untouched.
- `blender-verification.json` — full transform/contact receipts.
- `Volley-Native-Motion-01.mp4` — 145 frames, 1280 × 720, 30 fps, 4.83 seconds,
  covering match time 3.8–8.6 seconds with a player-following review camera.
- `Volley-Context-01.png` and `motion-frames-01/` — actual Blender renders, not
  concept images. Sampled approach, header, turn, return and finish frames were
  inspected for pose/contact/context. Interactive full-speed playback remained
  unavailable while the Mac was locked.

Visual limits remain visible: the keeper needs a more specific set/reaction
animation, and the volley still lacks the source player's full trunk/arm style.
Passing transform/contact checks is not approval of EAFC-level motion fidelity.

## Saved work and scope

Saved reviews were backed up before testing. After the full suite their SHA-256
still matches `b6ca5f189aeda0cb9b0fa2ecd8ed47f7c435ddb0969bb9e4dc87ff1fd3ccadfb`.
User signing/project and Info.plist edits are preserved and excluded from commits.
Large Blender/test outputs remain ignored under `.codex-derived/Reference129/`.

Interactive simulator UI inspection was blocked by the locked Mac. No unlock or
security workaround was attempted. Native render/tests and device compilation
do not replace that live UI or physical-headset check.
The latest native build was launched normally in the simulator (no test/debug
arguments); its visible window still needs an unlocked-Mac check.

No new player mesh, texture, rig asset, downloaded motion or footage was imported
in this pass. No measured off-camera tracks or eye gaze were obtained. Other
four studies retain their authored routes while benefiting from shared rig fixes.

## Research next steps

See [the research notes](REFERENCE129_RESEARCH.md) for primary sources and access
limits. A small rights-cleared football motion library is the next practical
animation input. Authorised multicamera footage and calibrated player tracks
would improve match accuracy; neither is replaced by more geometry or more
procedural idle motion. CMU is a candidate to inspect, not an imported or
visually approved clip library. WorldPose exact-window access remains unverified.
