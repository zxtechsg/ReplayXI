# Improvement run 138

Local-only Match Replay and Strategy Analysis. Goal remains active.

## Rotation defaults

Native baseline proves `simd_quatf()` is zero, not identity. Eight remaining
production defaults/reset sites used it: seven annotation/draft/guide locations
and the procedural model builder's default parameter. The imported far-body branch
already repairs zero rotations, but procedural fallback meshes did not.

The native fallback test covers both teams and three LODs. It failed 42 assertions:
six lists of non-unit model rotations plus 18 invalid rotated-forward vectors and
18 zero matrix columns. Importantly, all Entity.convert parent/world span checks
passed. Native conversion can mask the bad raw rotation math; this is not evidence
that every affected visual or collider actually collapsed.

Five annotation baseline tests failed 125 unit/axis assertions. They cover labels,
space circumference targets, crossing-keyframe rails and selected paths, elevation
guides and draft zones under a rotated, nonuniformly scaled parent. Existing world
position and hit-size checks are retained. The old crossing regression explicitly
expected a zero quaternion; it now expects a real unit identity.

The candidate uses explicit identity rotations, preserving all authored positions,
scales, selection rules and hit bounds. Procedural animation/rewind and real
head/neck changes from rest are also tested. The combined native candidate passed
all 61 tests, including both teams/three procedural LODs, annotation transforms,
existing stroke/selection/keyframe tests and all five fresh native ball studies.
Evidence: /private/tmp/replayxi-cycle138-identity-candidate.xcresult.

Baselines: /private/tmp/replayxi-cycle138-rig-baseline.xcresult and
/private/tmp/replayxi-cycle138-annotation-baseline.xcresult.

## Direct annotation handle ownership

Native Store probe confirms mark ID alone cannot distinguish A-preview → cancel →
B-preview → stale A-commit/cancel on the same mark. A token-owned handle API and
controller are being added. Authoritative lifecycle cancellation remains distinct
from gesture callbacks; curve/joystick previews retain their separate ownership.

SwiftUI DragGesture exposes time and starting position, but no native stable
gesture identifier. Source/target/start/time checks and a per-gesture token can
reject old events; indistinguishable reassigned native events are not claimed to
be solved. Reset-before-end and deferred old cleanup need explicit coverage.

## Foot contact investigation

Cycle137's 10.61 m/s near-floor peak is not proven planted skating. At fra-22's
6.875-second right-boot sample, the source run clip is in forward swing while the
authored procedural gait treats that foot as loaded. The cut overlay is fading.
Floor proximity alone mixes incompatible support/swing phases. Exact continuous
footfall and blend metadata are being collected before changing the phase policy;
no blanket world-space foot lock or new tracking-data claim is intended.
