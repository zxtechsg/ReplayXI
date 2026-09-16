# Loop 49 — predictable room open/exit

## Fixed

- Independent open/opening Booleans allowed late callbacks to overwrite newer
  presentation state. A compact, device-local request state now owns opening,
  appearance, explicit closing and system dismissal.
- Each opening passes its UUID through SwiftUI's typed immersive-space value.
  The scene and its local view state use that exact identity. An old appearance,
  disappearance or result cannot claim the new request.
- Exit becomes exclusive synchronously, before its task starts. Repeated taps
  cannot enqueue several dismiss calls.
- Enter remains disabled until both the dismiss call and view disappearance
  finish, regardless of their ordering. The dashboard says “Closing room…” while
  that transition is pending.
- A system dismissal clears visible ownership before rolling back a timeline or
  geometry preview and pausing playback. A late opening result cannot mark the
  absent room open again or dismiss the returned dashboard.
- Closing/retired scenes reject gesture and accessibility activation. Old scene
  clocks and pitch-anchor selection updates cannot affect a new room.
- Existing review saving, stationary controls, local-only tracking and first-person
  free look are unchanged. Presentation state is transient, not saved to disk.

## Verification

- Added **16 presentation tests** covering both open event orders, both close
  event orders, duplicate actions, wrong/stale request IDs, retry after failure,
  system dismissal, visible input ownership, and Store scrub/pause integration.
- Full Simulator suite: **487 passed, 1 optional skip, 0 failed (488 total)**.
  `/private/tmp/replayxi-presentation49-full-01.xcresult`.
- Unsigned physical visionOS Release: **BUILD SUCCEEDED**.
  `/private/tmp/replayxi-presentation49-release-01.log`.
- Python checks: **110 passed, 12 optional skips**, no failures.
  `/private/tmp/replayxi-presentation49-python-01.log`.
- Source guards verify typed scene IDs, guarded callbacks and input/Enter gates.
  `git diff --check` passed. No user signing or saved-review changes included.

## Reference and limits

Apple documents that [opening is asynchronous and only one immersive space may be open](https://developer.apple.com/documentation/swiftui/openimmersivespaceaction).
The [dismiss action returns after the system finishes dismissal](https://developer.apple.com/documentation/swiftui/dismissimmersivespaceaction).
The typed UUID scene initializer was also checked against the installed visionOS
SDK and compiled for both Simulator and physical-device Release.

These tests validate ordering, request identity and compiled wiring. Native
appearance timing, repeated physical taps and the changed scene entry path still
need interactive testing on an unlocked Simulator/headset. The desktop remains
locked; no interactive UI pass or measured device performance is claimed.

The timed improvement goal remains active. This is a local verified backup,
not the final 9am handoff.
