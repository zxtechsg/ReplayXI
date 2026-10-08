# Player, POV and Mac controls — 174

## Use

1. Build Replay XI for Vision Pro. In its dashboard, choose **Start Mac link**.
2. Open `ReplayXICoachMac.xcodeproj`, run `ReplayXICoachMac` on the Mac.
3. Use the same trusted local network. Pick the headset and enter its six-digit PIN.
4. Pause to edit. On Mac, click two pitch points to add a run, pass, arc, space or pressure mark. Drag its ends; use the height controls for Y.
5. For an arc, drag the third control handle across the map and set its height. This is a quadratic Bézier control point, not a circular arc or a point the path must pass through.
6. Set Show/Hide times; capture positions at the playhead, seek to another time and edit/capture again. Undo/Redo and saves use the headset's existing review store.
7. Player labels, label text, delete and confirmed Clear are available on Mac. Clear preserves authored overlays and can be undone. Spatial tools remain available.

The link is off by default. One Mac may pair at a time. Stop the link when done; New PIN is available while unpaired. This is local TCP with PIN pairing, **not an encrypted transport**. Use only a trusted LAN. There is no Group Activities capability, cloud relay or account requirement. Mac playback controls wrap into two rows in narrow windows.

## Player fixes

- Tags now sit close above the head envelope, not several metres above the pitch. First-person tag spacing no longer adds team/parity height tiers.
- Shirt digits use copies of the original shirt triangles and their exact skin weights, with a cached transparent number mask. Both sides follow the final body FK. Meshes/textures are prepared once and shared; no per-frame rebuild or upload is added. The old chest-anchor placement remains a fallback for older assets.
- Native A/B captures found stippled strokes with alpha cutout, even without mip filtering. The production material now uses alpha blending with the same mask and cloth geometry. The existing seven-segment number design is unchanged.
- Player A receives a skin-coloured neck bridge driven by final neck/head FK. It masks the disconnected source island; it does not weld or repair source topology.
- Cold far heads and table-marker head/neck gaps are closed.
- The existing second Tripo body is used more broadly on both teams, independently of its colour palette. There are still **two imported Tripo body identities**, not 22 unique people.
- Neck/head source interpolation is smoother between 24 Hz keys. Contact and lower-body channels retain their original sampling; seeking stays deterministic.

Blender MCP was used to inspect Player A in an isolated temporary scene. The existing source GLB/UV/rig/contact hashes remain unchanged. No paid Tripo generation was started.

## POV and pitch

- Entering/swapping a player captures that instant's evaluated rig head direction when prepared assets are available. Otherwise it uses the authored gaze estimate.
- The initial horizontal forward direction aligns once. The pitch stays level; later frames move with the player's position but do not force the viewer's head rotation.
- Two hand pinches move the pitch and stadium together in Table/Touchline. Spread/close the hands to scale. Motion and scale are bounded and resettable.
- World movement is disabled during annotation/timeline gestures, physical drills and active surface placement/scanning. An inactive Room Table anchor does not block Stadium/Touchline movement. Returning to the anchored Room Table clears temporary movement. Touchline height stays above the room floor.
- Arc start/end controls remain. A third **CURVE** handle can be pinched and moved in XYZ. Its spatial drag and pad use cancellable transactions, with one Undo per drag. Placing an arc opens this editor directly.

## Evidence and limits

- `replayxi174-focused04.xcresult`: **132 passed, 0 failed**, including native close-up renders and default/largest-text third-point editor captures.
- `replayxi174-mac-current11.xcresult`: **5 passed, 0 failed**. Covers real local TCP pair/command/state/disconnect, exact mark bytes, canonical encoding, bounded/versioned parsing and paired/disconnected layout captures.
- The first run passed 70/72; two invalid test/source fixtures were corrected. Earlier build attempts exposed and fixed a missing RealityKit import and a guard fallthrough.
- `replayxi174-runtime05.xcresult`: **62 passed, 0 failed**. Runtime head FK, native-ball inputs/contacts, saves and annotation controls.
- `replayxi174-final16.xcresult`: **61 passed, 0 failed**, after exact-cloth digits and the final hand/surface/floor fixes. The later material A/B exposed the cutout issue above; the final blended-material run is tracked separately below.
- `replayxi174-final19.xcresult`: **63 passed, 0 failed**, including CPU mask interiors, exact-cloth depth witnesses, native front/back/near/low renders, cache sharing, motion, tags, POV, pitch placement, arcs and local coach store gates.
- `replayxi174-alpha20.xcresult`: **1 passed, 0 failed**. A second keeper-back A/B confirmed the production blend is clearer than either single-mask alternative; production code did not change after the final19 pass.
- Unsigned **visionOS device Release build passed again after the blended-material fix**. Nothing was installed over the current headset demo.

The first close-up suggested a clipped front digit. A weighted-vertex depth diagnostic corrected that: it was hovering **13.7 mm near / 48.3 mm low** in the idle sample, not occluded. A footprint-only placement passed its probe check, but an independent imported-triangle check found **20–29 mm** of float over shirt folds. Interpolated glyph weights also introduced pose-dependent gaps, so that approach was replaced rather than loosening the checks. `replayxi174-number15.xcresult` passed all three native tests: 96 independent visible-ink cases measured **4.81–5.00 mm** clearance across both bodies, both detail levels, front/back, idle/run/rewind and four shirt numbers. Player A's shoulder folds are also present in its unanimated source pose, not solely caused by retargeting.

The five studies retain the video sources and uncertainty described in `FOOTBALL_REFERENCE_STUDIES.md`. A fresh paused review of the official Argentina–France clip at 1:30:54 confirms the combination context, not motion capture. Full-body poses, gaze and off-camera actions remain authored estimates. These changes are **not EA-level motion capture or exact video reconstruction**.

The existing seven-segment digits remain thin at long viewing distances, especially on the heavily folded Player A kit. This pass fixes cloth attachment and stippled rendering; it does not claim high-fidelity jersey typography or new source-body topology.

The actual Mac window was visually checked using an in-process TCP sample fixture. The controls render correctly; the fixture is labelled QA sample data and rejects edits. This verifies the native UI, not Bonjour or a physical headset link.

Material API reference: Apple's [UnlitMaterial blending](https://developer.apple.com/documentation/realitykit/unlitmaterial/blending-swift.property) and [opacity threshold](https://developer.apple.com/documentation/realitykit/unlitmaterial/opacitythreshold). The visual choice is based on this app's native A/B renders, not a claimed performance gain from the docs.

No physical headset gesture test or Mac↔Vision Pro live pairing test has been completed in this pass. Native fixed-camera captures do not establish headset FPS or comfort. The complete legacy test suite was not rerun; historical unrelated failures are not relabelled as passing.
