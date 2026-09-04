# Replay XI — MVP Runbook

Replay XI is a stationary visionOS prototype for collaborative football review. It demonstrates how a coach and squad could inspect one reconstructed move from player-level viewpoints, lock everyone to one perspective, compare positioning, reveal passing channels, and annotate the pitch in shared spatial context.

This build is an experience prototype, not a match-reconstruction or performance-analysis product. Its job is to make the proposed workflow tangible while keeping every data, tracking, safety, and multi-device claim explicit.

## MVP contract

The demo uses one deterministic, synthetic 32-second sequence with 22 procedurally animated players, a procedural ball track, generic Northbridge Athletic and Eastport United teams, and five different teaching treatments. Each player can use an original articulated RealityKit transform rig with hips, knees, shoulders, elbows, grounded boots, head stabilization, front/rear shirt numbers, kit/appearance variation, and seek-stable idle, walk, jog, sprint, and planted-cut motion derived from telemetry. Match Playback keeps the selected player detailed, gives the rest of the tactical squad an animated low-draw football silhouette, and caps first-person detail to the two nearest visible players while retaining at most four identity tags between 2.25 and 32 metres. Closer players rely on the readable shirt number instead of covering the wearer's view with a redundant tag. Tactical presentation adds one-draw number glyphs for non-selected players, an expanded number/position plate for the selected player, a thin coaching-board rim, team-readable low-detail limbs, and a panelled original ball. Pitch markings and space rings are batched, and dense simultaneous marks pass through a deterministic selected-first draw budget. This bounds scene cost without losing formation, shirt number, role, or facing information. The original procedural athlete is the default in every configuration. A hash-locked CC0 skinned-player conversion remains available only through an explicit diagnostic override for one selected or nearby non-wearer; visual QA rejected its shoulder and kit silhouette for the normal demo. Idle, walk, cut, release builds, impact/ragdoll moments, failed asset admission, and the rest of the squad always retain the original procedural rig. All positions, orientations, passing lanes, cue times, and coach marks are authored fixtures in `ReplayXI/Domain/DemoScenarios.swift`.

There is no downloaded match footage, club data, AI reconstruction, photogrammetry, or opponent model in this build. Player POV follows the selected track's horizontal translation at human scale, placing the stationary wearer at that player's head position as the play advances. Pitch orientation never follows telemetry yaw or pitch, so the wearer retains head-tracked free look. Compact green brackets show recorded facing direction without steering the view, claiming eye gaze, or presenting recovered video from that player.

### The five experiences

1. **Eleven Eyes — squad replay.** One shared clock drives the move while every Northbridge and Eastport role can retain its own selected Player POV. The tactical board opens first for stable annotation; tapping any visible body or shirt-number tag pauses and enters that player's translation-following, free-look POV. The roster controls expose all 22 positions and wrap continuously across both teams. This demonstrates synchronized review without pretending every player saw the same picture.
2. **Everyone With Seven — coach focus.** The coach selects the right winger and broadcasts that perspective, then reveals the defender, overlap, and passing instruction marks. This demonstrates the “everybody with seven” coaching moment.
3. **Triangle Lock — shape lab.** The default Visualise mode compares the tracked problem shape with a fixed ideal triangle in a compact, stationary model. Optional Place mode requires a nearby SharePlay room, coach clear-area preflight, successfully shared anchor, local acknowledgement on every headset, and live tracking before fixed physical station markers appear. Place hides moving players, ball, marks, and broad replay controls. Each acknowledged wearer gets only local headset-relative distance feedback; exact physical spacing remains a device-validation task.
4. **Lane Lens — passing channels.** The replay compares a screened inside pass, a time-limited outside overlap, and a cut-back using pitch-locked authored marks. The visual treatment explains why a route is open; it is not an AI recommendation.
5. **Four Minds — perspective matrix.** The right winger, right-back, right midfielder, and defending left-back are compared at the same replay time. Rapid, time-locked switching demonstrates how a player can inspect what was visible or hidden to each role.

## What the prototype does

- Renders a synthetic football sequence with SwiftUI and RealityKit.
- Provides first-person, tactical, touchline, and positional presentation modes.
- Plays, pauses, cue-jumps, jogs by ±1 second, and gaze-pinch-drags across the timeline. Pinching anywhere on the rail first jumps to that time; horizontal motion scrubs while moving upward continuously reduces gain from coarse through fine to true 30 fps frame control. Playback rate runs from 0.5× through 4×, and all 22 players share one scenario clock.
- Keeps one compact transport on a continuously tracked head anchor below the neutral sightline, with 48–56 point targets, a direct 22-player selector, and secondary speed, view, room, and annotation actions in menus. The replayed player's translation moves the world; it never steers the headset or the control deck. Starting a mark collapses transport into a one-row drawing shelf so the chosen pitch point remains visible.
- Lets a coach place timestamped run, pass, press, zone, and player-label annotations. Run, pass, press, and zone tools accept one continuous gaze-and-pinch or direct-pinch drag across the pitch: the complete pitch-locked 3D arrow or radius previews live and release commits once. Short hand drift recovers the intended tap instead of discarding a player, label, or pitch selection. A short pinch remains the first point of the accessible two-tap fallback. Two-point tools retain a segmented, tool-coloured start reticle and explicit state; selected marks expose pitch-clamped endpoint handles. Saving returns to the uncluttered drawing shelf, while Events is the explicit route to edit. One main timeline controls review time; an editable mark uses a single **Move** action to adopt that time. Undo, per-mark Erase, and confirmed Clear affect coach-created marks only and preserve authored teaching overlays.
- Makes every tactical player body and floating jersey-number tag a gaze-and-pinch target with enlarged collision footprints and accessibility identity. The selected player's tag also shows position.
- Models coach focus and follow/release state. A tapped coach POV remains local across periodic heartbeats and later state publications until the coach explicitly chooses **Share # POV**.
- Uses a `GroupActivity`, `GroupSessionMessenger`, reliable messages, sequence gates, and periodic coach snapshots to replicate playback state through SharePlay.
- Supports both direct in-app activity activation and system Share menu donation.
- Requests a group immersive space from the SharePlay system coordinator when one is available.
- Gives players a true local comfort pause: incoming coach state is cached and applied only when they resume following.
- Remains usable as a clearly labelled solo simulation when no group session is active.

The synchronized payload contains scenario, playhead, playing state, playback rate, view mode, coach-focused player, coach lock state, coach marks, player-seat assignments, Lane Lens state, Triangle Lock mode, and the coach-selected shared pitch-anchor ID. Remote payloads are bounded to 128 marks and validated for finite geometry/time, display windows, text length, UTF-8 size, and unique annotation IDs before scene use. A playing snapshot projects its playhead from send time to receive time within bounded age/rate tolerances, while paused snapshots remain exact. Heartbeats project the deliberately published shared clock from a monotonic reference while retaining the published squad POV; they do not serialize a coach's private Player POV. Per-headset placement acknowledgement is intentionally local and is never synchronized. This is prototype state replication, not a deterministic real-time networking engine. Latency, drift, packet recovery, reconnects, and scale must be measured on hardware.

## Platform and evidence limits

### Procedural data only

All five experiences reuse the same authored 32-second source sequence. The five cards demonstrate different review interactions, not five independent matches. Player paths are illustrative and must not be described as Premier League, club, telemetry, optical-tracking, or AI-derived data.

Future imported video or tracking data should be preprocessed outside the headset into a versioned scenario package. Apple's Vision body-pose APIs are not a turnkey 22-player reconstruction pipeline.

### No passthrough or main-camera frames

Replay XI does not request or receive Vision Pro passthrough pixels. Ordinary visionOS apps cannot use the user's view of the room as a camera feed. Apple Vision Pro main-camera access requires Apple's managed enterprise entitlement and licence, plus the corresponding usage description. This prototype has neither and must not imply otherwise.

### Headset position, not feet or a full-body skeleton

The nearby-positioning prototype uses `WorldTrackingProvider` to sample the Vision Pro headset's horizontal position and heading relative to a shared pitch `WorldAnchor`. It does not perform camera, raw hand-joint, foot, leg, or full-body tracking. Playback annotation uses SwiftUI's public targeted `SpatialTapGesture` and `DragGesture`, backed by RealityKit collision and input-target components. The system resolves gaze and pinch while Replay XI converts each native 3D drag sample into match space and keeps the result on the pitch; the app does not infer eye gaze or retain hand pose. Apple recommends system gesture recognizers for this class of interaction and reserving raw hand-position access for cases the system cannot express. Public visionOS APIs can separately provide detailed hand/finger tracking, including limited wrist/forearm joints, but they require authorization and still do not expose the wearer's feet, legs, or a full-body skeleton. Nearby Interaction is also unavailable on visionOS.

The floor-projected position inferred from the headset is an approximation of the wearer, not measured foot placement. Triangle Lock compares that approximation with authored formation targets only after the shared frame is tracked and that wearer has acknowledged the clear area. If consent, anchor, transform, or tracking is missing, physical stations remain hidden and the app falls back to the compact Visualise model. It does not assess stance or biomechanics and does not prove that three physical players are standing at exact football distances.

### No running interaction

Use Replay XI while seated or standing in one inspected, clear area. Gaze, pinch, playback controls, and small comfortable head turns are the intended interactions. Do not run, sprint, tackle, kick a real ball, make sharp changes of direction, or perform contact drills while wearing Vision Pro. The replay comes to the player.

### SharePlay and group immersive expectations

The app configures SharePlay for a group immersive space and uses a side-by-side spatial template. For physically nearby participants, visionOS can supply a shared group-immersive coordinate system and preserve awareness of nearby wearers through passthrough. That platform capability does not establish that this particular build is aligned, comfortable, low-latency, or robust at squad scale.

The “11 seats” and 11 Northbridge roles are simulated scene content. They are not evidence of an 11-headset test. Apple publishes no 11- or 20-nearby-headset capacity guarantee. Spatial Personas are a separate remote-participation feature and Apple currently limits those sessions to five people; that limit must not be presented as proof of nearby group capacity in either direction.

Treat two-device connection, shared-origin alignment, latency, thermal behaviour, battery life, participant visibility, interruption handling, reconnects, and every increase toward 11 devices as physical validation milestones. Until those tests are completed, describe the build as “SharePlay-enabled with 11 simulated roles,” not “validated for an 11-player headset session.”

## Architecture

| Layer | Current responsibility |
| --- | --- |
| `ReplayXI/Domain/FootballModels.swift` | Scenario, trajectory, ball, formation-target, cue, and coach-mark value types plus geometry helpers |
| `ReplayXI/Domain/DemoScenarios.swift` | The common synthetic 32-second sequence and five teaching configurations |
| `ReplayXI/Domain/PlaybackStore.swift` | Main-actor playback state, perspective selection, coach focus, annotation operations, and shared snapshots |
| `ReplayXI/Domain/SharedSessionModels.swift` | Codable SharePlay commands and per-author monotonic sequence rejection |
| `ReplayXI/Collaboration/ReplayXIActivity.swift` | SharePlay activity metadata and room/scenario identity |
| `ReplayXI/Collaboration/SquadSessionCoordinator.swift` | Session discovery, activation, group-immersive configuration, participant counts, messaging, heartbeat, and cleanup |
| `ReplayXI/Collaboration/SharedSpaceAnchorCoordinator.swift` | Shared pitch-origin `WorldAnchor` lifecycle and horizontal headset pose relative to that origin; never foot/full-body tracking |
| `ReplayXI/UI/` | Window controls, tactical previews, visual system, and scenario navigation |
| `ReplayXI/Immersive/` | RealityKit pitch, articulated/animated-LOD players, tappable spatial identity, translation-following free-look Player POV, ball, annotation drafts/marks, Triangle Lock geometry, and spatial panels |
| `ReplayXITests/` | Deterministic geometry, scenario, store, and synchronization-model checks |

`ReplayStore` is the local presentation model. A coach action produces a `SharedPlaybackSnapshot`; the session coordinator wraps it in a sequenced command and sends it reliably. Remote stores validate scenario identifiers, clamp time/rate values, reject invalid annotation geometry/windows and stale per-author sequences, and apply the replicated state. The coordinator caches the last deliberately published snapshot and projects only its timeline fields for periodic heartbeats, rather than serializing a transient local POV or an in-progress scrub. Periodic snapshots are recovery aids, not frame-by-frame transport.

## Requirements

- Xcode 26.6 or a compatible Xcode containing the visionOS SDK.
- The visionOS Simulator runtime for simulator execution.
- Apple Vision Pro hardware for passthrough, nearby SharePlay, comfort, alignment, and performance validation.
- A development team and provisioning profile containing the Group Activities entitlement for installation on hardware.

The project deployment target is visionOS 26.0 because nearby-participant classification and shared nearby anchors used by this MVP require visionOS 26. The repository's current reference toolchain is Xcode 26.6 with the visionOS 26.5 SDK.

## Build

From the repository root:

```sh
Scripts/build-replay-xi.sh
```

That command builds:

- Simulator Debug into `.codex-derived/ReplayXI-Simulator`
- Generic visionOS device Release into `.codex-derived/ReplayXI-Device`

Build one destination only:

```sh
Scripts/build-replay-xi.sh --sim-only
Scripts/build-replay-xi.sh --device-only
```

Both command-line builds disable code signing. A successful generic-device build proves compilation for the device SDK; it does not produce an installable, provisioned app.

The current Match Playback refinement was verified on an Apple Vision Pro visionOS 27.0 simulator with the complete 227-test app run and zero failures or skips: 225 XCTest cases plus two serialized Swift Testing import-fixture smoke tests. The separate rights-safe asset pipeline passes all 45 Python tests with its complete dependency runtime. A normally signed simulator build succeeds and carries the simulated Group Activities entitlement. Verification covers adaptive head-following controls, compact in-deck settings and annotation editors that avoid unsupported immersive presentations, explicit local-versus-squad POV state, all 22 player perspectives, translation-following free-look Player POV, dense whole-match event clustering, continuous gaze-pinch timeline scrubbing, transactional annotation preview/commit/cancel, selected 3D endpoint handles, precise accessible endpoint nudging, undo/erase/clear, and seek-stable procedural gait. The app was rebuilt and captured at simulator resolution with no clipped playback controls or launch blocker. The launchable simulator artifact is `.codex-derived/ReplayXI-Loop18-FinalDemo/Build/Products/Debug-xrsimulator/ReplayXI.app`. These checks do not substitute for physical-device pinch recognition, comfort, accessibility, animated imported-player deformation, thermal behaviour, or multi-headset validation. The included three-layer visionOS icon can be regenerated with `swift Scripts/generate-replayxi-icon.swift`.

To build tests without launching them:

```sh
xcodebuild build-for-testing \
  -project ReplayXI.xcodeproj \
  -scheme ReplayXI \
  -destination 'generic/platform=visionOS Simulator' \
  CODE_SIGNING_ALLOWED=NO \
  -derivedDataPath .codex-derived/ReplayXI-Tests
```

To run tests, select an installed simulator in Xcode or supply a concrete simulator destination to `xcodebuild test`.

## Run

### Simulator

1. Open `ReplayXI.xcodeproj`.
2. Select the shared `ReplayXI` scheme and an Apple Vision Pro simulator.
3. Run the app and enter the review room from the window.
4. Exercise all five scenario cards, playback controls, view modes, player selection, focus/release, and annotation controls.
5. Treat simulator participant counts, passthrough, spatial alignment, and comfort as non-evidence. The simulator is for UI, scene, and deterministic-state checks.

### Physical Vision Pro

1. In the Replay XI target, select a development team that can sign the Group Activities entitlement.
2. Build and install from Xcode on each test device; the signing-disabled script is not an installation workflow.
3. Start with one device, then two physically nearby devices. Do not jump directly to a full-squad test.
4. Use a nearby SharePlay session or FaceTime SharePlay as appropriate, join the same activity, and confirm that the app reports a live room.
5. Keep every wearer stationary in a separately inspected area throughout the test.

## Device test checklist

Record hardware model, visionOS build, app commit/archive identifier, room dimensions, participant count, session type, network conditions, and a screen recording or written observation for every run.

### Single-device baseline

- [ ] App launches without requesting camera, body, foot, hand, microphone, or location access.
- [ ] All five scenarios appear in the documented order and share the expected 32-second clock.
- [ ] Synthetic teams and prototype/data labels are visible; no screen implies real club or match provenance.
- [ ] Mixed immersion opens and closes repeatedly without a stuck opening state.
- [ ] Play, pause, cue jumps, ±1-second jogs, 0.1-second scrubbing, 0.5×–4× replay rate, and reset remain bounded and responsive.
- [ ] Player POV, tactical, touchline, and positional views remain comfortable and keep the pitch at a useful scale.
- [ ] In tactical playback, gazing and pinching either a player body or its jersey-number tag pauses at the same timestamp and enters that player's free-look POV; the selected tag expands to include position.
- [ ] Player POV follows only the selected player's horizontal track; headset movement controls view direction and recorded facing appears only as the green authored-facing brackets.
- [ ] Previous, next, and the 22-player menu preserve the replay timestamp and expose both teams with readable number and position identity.
- [ ] Coach focus pauses as expected, selects the intended role, and player devices release back to their own local perspectives.
- [ ] A coach's tapped POV remains private until **Share # POV** is chosen; periodic heartbeats and later timeline updates do not leak the local selection to the squad.
- [ ] Run, pass, press, and zone tools collapse transport into the one-row drawing shelf. Pinch-drag previews the complete tool-coloured 3D instruction and release commits it exactly once; a stationary/short pinch leaves a visible start that a second tap or drag can finish. Label commits in one player tap.
- [ ] Coach-added run, pass, zone, and player-label marks appear at the intended pitch positions and timestamps, expire after eight replay seconds, create timeline ticks, and are reachable through the annotation jump/delete menu; authored marks never expose Delete.
- [ ] Undo removes only the latest coach-added annotation and does not mutate authored scenario marks.
- [ ] Triangle targets are clearly labelled as simulated targets/ghosts, not measured feet.
- [ ] Triangle Place cannot show physical stations without clear-area confirmation, a tracked shared anchor, and acknowledgement on that headset.
- [ ] Triangle Place keeps every pair of station centres at least 1.50 m apart and uses non-overlapping 0.25 m guide zones.
- [ ] Text remains legible and controls remain reachable with the supported system accessibility settings.
- [ ] No interaction invites running, kicking, lunging, or contact.

### Two nearby devices

- [ ] Both signed builds discover/join the same activity and report accurate active and nearby participant counts.
- [ ] The group immersive coordinate system is stable enough that both users agree on pitch and mark locations.
- [ ] Nearby wearers remain visible/understandable through the system presentation, with no unsafe visual occlusion.
- [ ] Coach scenario selection, play/pause, seek, rate, view mode, focus lock, release, and marks arrive on the player device.
- [ ] Player-local perspective remains local until coach lock is enabled.
- [ ] A player can stop following the coach for comfort without corrupting the coach's state.
- [ ] Late join receives current state through request/snapshot recovery.
- [ ] Duplicate or out-of-order commands do not move state backwards.
- [ ] Drift is measured during continuous playback and after the periodic heartbeat; record median and worst observed error.
- [ ] Background/foreground, headset removal, SharePlay cancellation, network interruption, leave, end, and rejoin recover predictably.
- [ ] Audio, thermal state, battery drain, frame pacing, input latency, and comfort are recorded for a representative session.

### Scale progression

- [ ] Repeat the two-device matrix with 3, 4, and 5 nearby devices before attempting larger groups.
- [ ] Add one device at a time thereafter; record join failures, alignment error, message latency, dropped state, heat, and frame rate.
- [ ] Inspect the physical room and assign a stationary zone for every wearer before each increase.
- [ ] Stop immediately for discomfort, tracking instability, spatial misalignment, participant occlusion, cable hazards, or unexpected system boundaries.
- [ ] Do not claim 11-device support until the complete checklist passes with 11 physical Vision Pro devices across repeated sessions.

## References

- Apple: [Configure your app for sharing with people nearby](https://developer.apple.com/documentation/groupactivities/configure-your-app-for-sharing-with-people-nearby)
- Apple: [`supportsGroupImmersiveSpace`](https://developer.apple.com/documentation/groupactivities/systemcoordinator/configuration-swift.struct/supportsgroupimmersivespace)
- Apple Support: [Use Spatial Persona on Apple Vision Pro](https://support.apple.com/guide/apple-vision-pro/use-spatial-persona-tana1ea03f18/visionos)
- Apple: [ARKit in visionOS](https://developer.apple.com/documentation/arkit/arkit-in-visionos)
- Apple: [Adopting best practices for privacy and user preferences](https://developer.apple.com/documentation/visionos/adopting-best-practices-for-privacy)
- Apple: [Using a reference object with RealityKit — gesture input components](https://developer.apple.com/documentation/visionos/using-a-reference-object-with-realitykit)
- Apple: [`DragGesture`](https://developer.apple.com/documentation/swiftui/draggesture)
- Apple: [Bringing your ARKit app to visionOS](https://developer.apple.com/documentation/visionos/bringing-your-arkit-app-to-visionos)
- Apple: [`HandTrackingProvider`](https://developer.apple.com/documentation/arkit/handtrackingprovider)
- Apple: [Accessing the main camera](https://developer.apple.com/documentation/visionos/accessing-the-main-camera)
- Apple: [Enterprise APIs for spatial business apps](https://developer.apple.com/documentation/visionos/building-spatial-experiences-for-business-apps-with-enterprise-apis)
- Apple: [Identifying 3D human body poses in images](https://developer.apple.com/documentation/vision/identifying-3d-human-body-poses-in-images)
- Apple: [Nearby Interaction](https://developer.apple.com/documentation/nearbyinteraction)
