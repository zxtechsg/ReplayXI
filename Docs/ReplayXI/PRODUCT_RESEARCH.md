# Replay XI product research and implementation direction

Product sources reviewed: 3 September 2026. Scope aligned with the local-only
app on 17 September; the UI follow-up below rechecked Apple, Hudl Studio and
Tactic3D, not every older product link.

Current scope is **local Match Replay and Strategy Analysis**. Replay XI uses
an event-and-annotation workflow to inspect a football moment from selectable,
freely lookable player viewpoints. Room sharing and Group Activities are out of
scope. Source-video reconstruction remains pending a usable authorised clip;
the bundled match is explicitly synthetic. See [spatial UI notes](SPATIAL_UI_RESEARCH.md)
for the current room-fixed controls and [Loop 52](LOOP52_PRESENTED_ANNOTATION_ALIGNMENT.md)
for player-bound annotation alignment.

The core review loop is:

1. **Find the moment** — choose a tagged event or decision checkpoint.
2. **Freeze the decision** — pause the local replay on one authoritative match clock.
3. **Inspect every role** — select a body or number to enter its translation-following, free-look POV without forcing recorded head rotation.
4. **Draw the correction** — add a pitch-locked run, pass, space, danger area, or player label with an explicit time window.
5. **Rehearse the next action** — compare the observed state with a coach-authored alternative, then return to playback.

## What existing products validate

### Event-first review is the familiar entry point

- [Hudl Sportscode](https://sportscode.hudl.com/sports/soccer) centres analysis on captured moments, custom coding workflows, multiple angles, presentations, and team sharing.
- [Veo Editor](https://support.veo.com/hc/en-us/articles/4454946199057-Veo-Editor-overview-features-and-available-tools) exposes clips and events on a timeline, then layers drawings, player moments, lineups, playback controls, and sharing on top.
- [Catapult Pro Video](https://www.catapult.com/sports/soccer/video-analysis) connects event, athlete, tracking, and video data and carries selected moments into presentations and collaboration.

**Replay XI consequence:** the initial surface should be a legible event strip and one large playback deck, not a feature catalogue. An annotation is a time-bounded review object attached to an event, not decoration that lives forever.

### First-person value comes from perception and decisions

- [Be Your Best](https://www.beyourbest.com/en-us/vr-training-1) uses recreated 11-v-11 situations for position-specific scanning, awareness, and decision practice, then lets a player review performance from multiple angles.
- [Rezzil](https://rezzil.com/home-page-correct/) focuses its football simulations on scanning, timing, movement, and decision-making and describes ingest from optical systems such as Second Spectrum, Hawk-Eye, and TRACAB for post-match analysis.

**Replay XI consequence:** Player POV should answer “what information was available?” It follows the selected player's translation, leaves head orientation under the wearer’s control, and renders recorded facing as a separate authored indicator. Future checkpoints should capture a scan prompt, viable options, chosen action, and coach explanation. Any scan-rate, timing, awareness, or decision score needs a declared measurement rule and validation study; Replay XI must not infer gaze from ordinary Vision Pro focus.

### Context is more valuable than raw event counts

- [Hudl StatsBomb 360](https://statsbomb.com/what-we-do/soccer-data/360-2/) attaches a visible-player freeze frame to events and supports filtering by event, location, team, player, play scenario, pass type, and game state. Its derived questions include line-breaking passes, available space, defensive weakness, and open lanes.
- [Google DeepMind's TacticAI](https://deepmind.google/blog/tacticai-ai-assistant-for-football-tactics/) models players as graph nodes, retrieves similar corner situations, predicts receivers/outcomes, and generates alternative positions for expert review.

**Replay XI consequence:** each decision checkpoint needs a common clock, player/ball state, football phase, and explicit comparison between observed and coach-authored alternatives. Counterfactuals should be labelled “coach authored” or “model suggestion,” include provenance/confidence, and remain inspectable rather than being framed as the correct answer.

### An annotation is an editable timed object

- [Nacsport KlipDraw](https://www.nacsport.com/klipdraw.php?lc=en-gb) combines arrows, movement lines, text, surface areas, and tracked spotlights with explicit controls for when each drawing appears and how long it remains visible.
- [Nacsport's timeline workflow](https://www.nacsport.com/basicplus.php?lc=en-us) treats clips, notes, drawings, and presentations as one review flow rather than separate modes.
- [Pixellot Coaching](https://www.pixellot.tv/products/coaching/) pairs full-pitch capture with event tagging, player tracking, live clip editing, and multiple angles.

**Replay XI consequence:** a 3D mark needs direct selection, visible start/end handles, player attachment, a draggable reveal time and duration, and one-tap deletion for coach-created marks. Player identity and source time remain stable when geometry or timing changes. Imported angles are evidence aligned to the replay clock; they do not define the wearer's head orientation.

### Reconstruction quality and provenance must stay visible

- [FIFA's Electronic Performance and Tracking Systems overview](https://inside.fifa.com/innovation/standards/epts/epts-1) distinguishes optical, local-positioning, and GPS/GNSS sources and their different accuracy/occlusion trade-offs.
- [FIFA's EPTS standard data format](https://football-technology.fifa.com/innovation/standards/epts/research-development-epts-standard-data-format) aims to make tracking feeds from different providers comparable through a common interchange format.
- [SkillCorner XY Tracking](https://skillcorner.com/products/football/xy-tracking-data) describes automated player/ball XY extraction from a single broadcast or tactical camera and identifies off-screen positions as model extrapolations.
- [Opta Vision](https://www.statsperform.com/products/opta-vision/) combines event data with uninterrupted XY locations for all 22 players and uses that context for shape, off-ball-run, and pressure analysis.

**Replay XI consequence:** a production scenario package should preserve source timecode and classify samples as `observed`, `interpolated`, or `inferred`, with provider/version and uncertainty metadata. The UI should expose reconstruction confidence at the current moment. Synthetic demo data stays visibly labelled as synthetic.

## visionOS implementation decisions

- Use one deterministic, absolute replay clock for trajectories, gait phase, ball motion, annotation visibility, and optional replay effects. Seeking to the same time must recreate the same frame.
- Keep normal football movement authored/telemetry-driven. Use physics only for a selected, bounded impact replay, with a deterministic reset path. A 22-body continuously dynamic ragdoll simulation would weaken seeking, cross-device agreement, and frame pacing.
- Use shared materials, mesh reuse/instancing where practical, distance-based detail, bounded labels, and bounded annotation hierarchies. Profile on device with RealityKit Trace before claiming a stable player count.
- Keep playback, annotations and saves on this device. Do not add a Group Activities entitlement or transport. Legacy snapshot tests are offline compatibility fixtures, not a shipped sharing feature.
- Treat free look and recorded facing as two independent transforms. Playback moves the POV origin with the player's track; Vision Pro controls view orientation; a reticle or frustum communicates the recorded facing direction.
- Keep the control deck and its submenus in one room-fixed workspace, with a deliberate recenter action. A one-time head-origin capture places the workspace; it does not keep following the wearer's head. Pitch labels stay with the pitch. Maintain large targets and test text wrapping, overlap and reach on an unlocked Simulator/headset. These comfort checks are still pending.
- Keep all interaction stationary. Physical-position rehearsal must remain consent-gated, small-scale, headset-position-based, and clearly distinct from foot or full-body tracking.

Relevant Apple guidance: [RealityKit](https://developer.apple.com/documentation/RealityKit), [physics joints and pins](https://developer.apple.com/documentation/realitykit/physics-joints-and-pins), [visionOS accessibility](https://developer.apple.com/design/human-interface-guidelines/accessibility), [spatial layout](https://developer.apple.com/design/human-interface-guidelines/spatial-layout), and [visionOS performance analysis](https://developer.apple.com/documentation/visionos/analyzing-the-performance-of-your-visionos-app).

## Ordered product slices

### Slice A — credible local playback

- Large transport with play/pause, precise scrub, jog, speed, current event, and reset.
- All 22 players selectable directly by body/number and through a compact roster fallback.
- Tactical, touchline, and freely lookable Player POV views on one timestamp.
- Clear selected-player versus active-POV semantics; room-role selection must not claim to change the camera.
- Local autosave and named reviews, paused restoration, safe open/close ownership and clear room status.

### Slice B — spatial coaching authoring

- One-tap player label plus continuous system-pinch drawing for run/pass/press/zone creation, with the two-tap workflow retained as a motor-accessible fallback.
- Draft reticle, world-space start/end handles, cancel/undo/delete, selected annotation inspector, and draggable reveal/duration editing.
- Auto-follow labels for player-attached marks while preserving the source track identity.
- Event ticks and jump-to-annotation navigation.
- Coach-authored alternative state that can be compared against the observed state without mutating source telemetry.

### Slice C — decision review

- Timestamped scan cue with two to four plausible actions.
- Per-option lane clearance and visible-player context, described as descriptive metrics rather than a recommendation.
- Recorded choice, coach preferred choice, short explanation, and reconstruction-confidence indicator.
- Perspective comparison at exactly the same time.

### Slice D — ingest contract

- Versioned, rights-cleared scenario bundle containing player/ball tracks, team/kit metadata, source timecode, events, and coordinate calibration.
- Explicit observed/interpolated/inferred sample quality and source provenance.
- Offline validation for finite coordinates, monotonically ordered samples, stable player identity, pitch orientation, missing intervals, and sensible velocity bounds.
- Precomputed LOD/animation assets and compact runtime payloads; reconstruction occurs off-headset.

## Claims deliberately withheld

- No FIFA game assets, code, animation, branding, or reverse-engineered content.
- No claim that synthetic figures are photorealistic athletes or that procedural impact poses are biomechanically accurate.
- No claim that reconstructed Player POV reproduces gaze, perception, or memory unless eye/head telemetry and a validated calibration method are actually supplied.
- No claim of automated tactical correctness, player grading, cognitive transfer, or injury benefit.
- No claim of multi-headset operation: this build is local only.
