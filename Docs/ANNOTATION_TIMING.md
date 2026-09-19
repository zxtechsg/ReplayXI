# Timestamp annotations

- Select a coach annotation → Timing.
- Set In and Out (seconds), or To end, then Apply In/Out.
- Under Saved positions, Add here saves the first position key.
- Seek, then Adjust shape. Endpoint, height and curve changes save a key at that time.
- Playback interpolates between keys. Before/after the keyed interval, the nearest pose holds.
- Tap a saved timestamp to preview it. Position time / Move retimes that pose without redrawing it.
- Nearby timestamps show extra decimals so position chips stay distinct. Cyan diamonds on the
  main timeline show the selected annotation's keys; dense keys share a marker. Scrubbing works
  through these markers as before.
- To playhead moves the selected key to the current replay time; trash deletes only that key.
- Freeze here removes all keys and holds the current sampled shape. Undo restores the animation.
- In/Out trims visibility only. Shift all timing moves visibility and all keys together.
- Enter decimal seconds or m:ss. Invalid or unchanged values cannot be applied.
- Apply In/Out commits the window; Reset In/Out discards only its pending edits.
- Position time has its own Reset and Move. Finish or reset that draft before selecting another key.
- Return/Done applies the field's own edit. Invalid text stays editable.
- Outside In/Out means outside the visible interval. The selected annotation stays shown for editing;
  close it to preview normal visibility.
- Player tracking and position keys are separate modes. Switch to Fixed before adding keys.
- Up to 64 keys per annotation; explicit visibility windows retain the existing 0.5–30s limit.
- Undo/redo and local saved reviews include keys. Old reviews need no migration.

Arc controls: Curve adjusts amount/rotation; Offset adjusts bend/lift. Fine uses 5cm/1° steps.
Settings → Bar size scales the room-anchored console from 80–150%, with a percentage and reset.

Validation: full simulator suite passed (1,243 XCTest tests, two intentional skips, and two
Swift Testing tests). Device Release build passed. Regular, largest-text, close-key and
outside-window screenshots inspected. Headset interaction/comfort still needs device testing.
See ReplayXI/IMPROVEMENT_RUN_135.md for current evidence and next performance work;
ReplayXI/IMPROVEMENT_RUN_132.md records the earlier intermittent renderer teardown issue.
