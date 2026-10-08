# Player, POV and Mac controls — 174

## Use

1. Build Replay XI for Vision Pro. In its dashboard, choose **Start Mac link**.
2. Open `ReplayXICoachMac.xcodeproj`, run `ReplayXICoachMac` on the Mac.
3. Use the same trusted local network. Pick the headset and enter its six-digit PIN.
4. Pause to edit. On Mac, click two pitch points to add a run, pass, arc, space or pressure mark. Drag its ends; use the height controls for Y.
5. For an arc, drag the third control handle across the map and set its height. This is a quadratic Bézier control point, not a circular arc or a point the path must pass through.
6. Set Show/Hide times; capture positions at the playhead, seek to another time and edit/capture again. Undo/Redo and saves use the headset's existing review store.
7. Player labels, label text, delete and confirmed Clear are available on Mac. Clear preserves authored overlays and can be undone. Spatial tools remain available.

The link is off by default. One Mac may pair at a time. Stop the link when done; New PIN disconnects the existing client. This is local TCP with PIN pairing, **not an encrypted transport**. Use only a trusted LAN. There is no Group Activities capability, cloud relay or account requirement.

## Player fixes

- Tags now sit close above the head envelope, not several metres above the pitch. First-person tag spacing no longer adds team/parity height tiers.
- Shirt digits use a small set of weighted shirt-surface probes, following the same final skin FK. The old fixed clearance remains a fallback.
- Player A receives a skin-coloured neck bridge driven by final neck/head FK. It masks the disconnected source island; it does not weld or repair source topology.
- Cold far heads and table-marker head/neck gaps are closed.
- The existing second Tripo body is used more broadly on both teams, independently of its colour palette. There are still **two imported Tripo body identities**, not 22 unique people.
- Neck/head source interpolation is smoother between 24 Hz keys. Contact and lower-body channels retain their original sampling; seeking stays deterministic.

Blender MCP was used to inspect Player A in an isolated temporary scene. The existing source GLB/UV/rig/contact hashes remain unchanged. No paid Tripo generation was started.

## POV and pitch

- Entering/swapping a player captures that instant's evaluated rig head direction when prepared assets are available. Otherwise it uses the authored gaze estimate.
- The initial horizontal forward direction aligns once. The pitch stays level; later frames move with the player's position but do not force the viewer's head rotation.
- Two hand pinches move the pitch and stadium together in Table/Touchline. Spread/close the hands to scale. Motion and scale are bounded and resettable.
- World movement is disabled during annotation/timeline gestures, physical drills and surface placement/scanning. Reset a surface placement before free movement.
- Arc start/end controls remain. A third **CURVE** handle can be pinched and moved in XYZ. Its spatial drag and pad use cancellable transactions, with one Undo per drag. Placing an arc opens this editor directly.

## Evidence and limits

- `replayxi174-focused04.xcresult`: **132 passed, 0 failed**, including native close-up renders and default/largest-text third-point editor captures.
- `replayxi174-mac-final.xcresult`: **3 passed, 0 failed**. Covers real local TCP pair/command/state/disconnect, exact mark bytes, canonical encoding and bounded/versioned parsing.
- The first run passed 70/72; two invalid test/source fixtures were corrected. Earlier build attempts exposed and fixed a missing RealityKit import and a guard fallthrough.
- `replayxi174-runtime05.xcresult`: runtime, native-ball, save and annotation checks passed; totals are recorded in the final receipt.
- Unsigned **visionOS device Release build passed**. Nothing was installed over the current headset demo.

Visual inspection found the base body's front digit still clipping and Player A's wrinkled shoulder shape still needing work. The weighted-number change is not yet labelled a complete fix at this checkpoint.

The five studies retain the video sources and uncertainty described in `FOOTBALL_REFERENCE_STUDIES.md`. A fresh paused review of the official Argentina–France clip at 1:30:54 confirms the combination context, not motion capture. Full-body poses, gaze and off-camera actions remain authored estimates. These changes are **not EA-level motion capture or exact video reconstruction**.

No physical headset gesture test or Mac↔Vision Pro live pairing test has been completed in this pass. Native fixed-camera captures do not establish headset FPS or comfort. The complete legacy test suite was not rerun; historical unrelated failures are not relabelled as passing.
