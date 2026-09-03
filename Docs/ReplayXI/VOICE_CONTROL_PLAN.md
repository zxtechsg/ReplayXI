# Replay XI voice control plan

Status: future Playback extension; interaction and authority contract defined in Loop 15.

## Product outcome

A coach should be able to keep their hands relaxed and issue a small set of
high-value commands during review:

- “Replay XI, jump back five seconds.”
- “Replay XI, show number seven.”
- “Replay XI, play at half speed.”
- “Replay XI, undo that annotation.”
- “Replay XI, delete the selected annotation.”
- “Replay XI, clear my annotations.”

Use Apple’s App Intents framework for Siri, Shortcuts, Spotlight, and future
Apple Intelligence exposure. Keep the first release to two-to-five discoverable
App Shortcuts; the richer parameterized intents remain available without
turning the shortcut list into another settings screen.

Primary references:

- [App Intents](https://developer.apple.com/documentation/appintents)
- [Creating your first app intent](https://developer.apple.com/documentation/appintents/creating-your-first-app-intent)
- [Accelerating app interactions with App Intents](https://developer.apple.com/documentation/appintents/acceleratingappinteractionswithappintents)
- [visionOS privacy guidance](https://developer.apple.com/documentation/visionos/adopting-best-practices-for-privacy)

## Important gaze boundary

Replay XI must not claim access to raw eye direction. visionOS performs eye
focus and hover feedback outside the app process; the app learns which element
was activated only after an interaction. Therefore “delete that” means the
annotation the coach explicitly selected most recently, not whatever their eyes
happen to be resting on when they speak.

The safe flow is:

1. Look-and-pinch an annotation or player to establish an explicit selection.
2. Speak “delete the selected annotation” or “show this player.”
3. Resolve the stable annotation/player ID from the active Playback selection.
4. Revalidate coach authority and object existence at execution time.
5. Perform one store transaction and publish one collaboration snapshot.

“Move that” should enter endpoint-edit mode for the selected mark. Voice can
choose `start`, `end`, `left`, `right`, `forward`, or a metre offset, but spatial
placement remains a direct gesture with touchline clamping. This avoids
pretending speech alone identifies an arbitrary 3D coordinate.

## Intent surface

| Intent | Parameters | Foreground | Collaboration rule |
| --- | --- | --- | --- |
| `SeekReplayIntent` | relative seconds or absolute timestamp | Optional | Player enters local review; coach can explicitly share |
| `SetPlaybackRateIntent` | 0.25–4× | Optional | Same transport authority as visible controls |
| `SelectPlayerIntent` | match and `PlayerEntity` | Required for immersive POV | Local by default; coach shares separately |
| `SelectGameIntent` | `ReplayEntity` | Required | Coach-only during a joined room |
| `UndoAnnotationIntent` | none | Required | Coach-created marks only |
| `DeleteAnnotationIntent` | explicit mark entity or active selection | Required | Coach-created marks only; authored marks immutable |
| `ClearAnnotationsIntent` | replay | Required | Confirmation required; authored marks preserved |
| `BeginAnnotationIntent` | run/pass/pressure/space/label | Required | Arms the existing two-point spatial workflow |

Represent matches, players, and annotations as `AppEntity` values backed by
stable IDs. Never pass a display name or jersey number as the authoritative
identifier because numbers can repeat across teams and squads.

## Implementation gates

1. Introduce a main-actor `PlaybackCommandRouter` used by both SwiftUI controls
   and App Intents so permissions, local-review transitions, validation, undo,
   and collaboration broadcasts cannot drift into two implementations.
2. Persist only replay/player/annotation identifiers needed for entity queries;
   do not persist a headset pose or inferred gaze history.
3. Add an active-selection bridge whose lifetime is the current immersive room.
   Clear it on scenario change, deletion, collaboration reset, and room exit.
4. Require confirmation for clear-all and for deleting more than one mark.
5. Return spoken, concise results such as “Back five seconds” or “Annotation
   already removed,” while the spatial UI shows the same state.
6. Test coach/player authority, stale entities, duplicated shirt numbers,
   follow-coach transitions, and exactly-once shared snapshots.
7. Validate Siri/App Shortcut discovery on physical Vision Pro; simulator tests
   cover intent logic but not microphone recognition or real headset focus.

