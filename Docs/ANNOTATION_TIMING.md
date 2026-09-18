# Timestamp annotations

- Select a coach annotation → Timing.
- Set In and Out (seconds), or To end, then Apply.
- Add at playhead saves the first position key.
- Seek, then Adjust pose. Endpoint, height and curve changes now save a key at that time.
- Playback interpolates between keys. Before/after the keyed interval, the nearest pose holds.
- Key chips seek to a pose; × removes it. Removing the last key freezes the current pose.
- In/Out trims visibility only. Move window shifts visibility and all keys together.
- Player tracking and position keys are separate modes. Switch to Fixed before adding keys.
- Up to 64 keys per annotation; explicit visibility windows retain the existing 0.5–30s limit.
- Undo/redo and local saved reviews include keys. Old reviews need no migration.

Arc controls: Curve adjusts amount/rotation; Offset adjusts bend/lift. Fine uses 5cm/1° steps.
Settings → Workspace → Bar size scales the room-anchored console from 80–150%.

Validation: 71 targeted tests passed, including timeline interpolation, reverse seeks without
entity rebuilds, undo, persistence, preview cancellation and the existing header-contact tests.
Device Release build passed. Full-suite attempt was not clean: three retired-UI assertions
were updated and passed on rerun; a RealityKit weak-reference crash during a header-contact
test also passed on rerun. Headset interaction/comfort still needs device testing.
