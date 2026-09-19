# Timestamp annotations

- Select a coach annotation → Timing.
- Set In and Out (seconds), or To end, then Apply.
- Under Saved positions, Add here saves the first position key.
- Seek, then Adjust shape. Endpoint, height and curve changes save a key at that time.
- Playback interpolates between keys. Before/after the keyed interval, the nearest pose holds.
- Tap a saved timestamp to preview it. Position time / Move retimes that pose without redrawing it.
- To playhead moves the selected key to the current replay time; trash deletes only that key.
- Freeze here removes all keys and holds the current sampled shape. Undo restores the animation.
- In/Out trims visibility only. Shift all timing moves visibility and all keys together.
- Enter decimal seconds or m:ss. Invalid or unchanged values cannot be applied.
- Apply commits the window; Reset discards unapplied field edits.
- Player tracking and position keys are separate modes. Switch to Fixed before adding keys.
- Up to 64 keys per annotation; explicit visibility windows retain the existing 0.5–30s limit.
- Undo/redo and local saved reviews include keys. Old reviews need no migration.

Arc controls: Curve adjusts amount/rotation; Offset adjusts bend/lift. Fine uses 5cm/1° steps.
Settings → Bar size scales the room-anchored console from 80–150%, with a percentage and reset.

Validation: 71 targeted tests passed, including timeline interpolation, reverse seeks without
entity rebuilds, undo, persistence, preview cancellation and the existing header-contact tests.
Device Release build passed. Full-suite attempt was not clean: three retired-UI assertions
were updated and passed on rerun; a RealityKit weak-reference crash during a header-contact
test also passed on rerun. Headset interaction/comfort still needs device testing.
