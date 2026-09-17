# Native ball physics

## Design

The new strategy sequences can run a real, offscreen RealityKit rigid-body
simulation before opening the pitch. `RealityRenderer.update(_:)` is called
with fixed 1/120 s intervals, and poses are recorded at those requested times.
RealityKit owns the internal integration cadence; 120 Hz is not a claim about
its solver's internal substeps. Its world contains a dynamic sphere, static pitch and kinematic
player torso, head, shin and boot collision proxies, plus goal frames and net panels.
It is **not** the old constrained
path repair under a new name.

The simulated sphere uses a 0.11 m radius, 0.43 kg mass, gravity, friction,
restitution, continuous collision detection, linear/angular damping, kick
impulses and a bounded opposing rolling-resistance force. The world is simulated
at metre scale, independent of the displayed tabletop scale. Nearby limb
colliders follow the articulated pose. Bodies collide only with the ball, not
with one another.

Launch planning now uses at most three short native sphere/pitch previews per
admitted touch. They measure the initial velocity required to approach the
target at the requested time. They contain no other players or goal panels,
cannot move the actual world, and never add a steering force to the actual
ball. A real blocker can still intercept the shot. The angular impulse uses
the native body's own inertia, not an assumed inertia coefficient.

Authored ball waypoints are intentions. Explicit planned touches name a player,
time, foot, action and target. A touch can apply a native impulse only while the
ball is within the player's bounded reach; a missed receiver cannot remotely
pull it back. The initial carrier/root knot may be resolved to a boot-side ball
position once. After initialisation, no ball position is assigned by the bake.
Touches may occur up to 0.12 s early/late when the native ball reaches the player;
recorded animation cues use the actual admitted time and centre.
Foot impulses also require the shared fixed-length IK toe to reach the sphere
surface within 20 mm. This leaves padding beneath the 30 mm rendered-rig test
limit. Body distance alone cannot authorise an air kick.

Standing headers have a separate 1.55–1.95 m centre-height/reach gate; the
horizontal limit is 0.65 m. The torso capsule ends at shoulder height (1.62 m),
with a separate 0.11 m-radius head sphere following the articulated chain near
the ball. This avoids a shoulder-width cap above the skull. There is no
invented jump. Save impulses require a goalkeeper, horizontal reach at most
0.50 m and a ball centre 0.08–2.10 m high. They are not mislabelled foot
kicks. The original Blender goal has post centres at ±3.72 m, 0.06 m post radius,
bar centre at 2.50 m and a rear net at ±54.7 m. Low-cost native frame boxes and
three side/rear net panels plus a top panel use those dimensions. They prevent
shots passing through the goal structure; the net does not deform. The legacy
procedural fallback goal has slightly different outer dimensions.

Each requested update records position, quaternion and velocities. The
published recording is immutable and sampled with binary search. Changing the
playback speed or seeking does not resume/reverse the solver; it displays the
same recorded result. The result is stable within that recording. Cross-device
or cross-OS bit-identical solver output is not claimed.

## Bounds and integration

- Maximum 90 seconds, 32 players, 4,096 source knots, 512 planned touches.
- Work yields and checks cancellation every 60 steps. A cancelled/invalid bake
  is never cached. Each aim preview is synchronous but bounded to three
  rollouts of at most 3 s; cancellation resumes at the primary bake boundary.
- Four exact source/player/plan recordings in a least-recently-used cache.
  The cache retains numeric recordings, not renderers, scenes or entities.
- An explicit plan with missed touches is returned for diagnostics but never
  cached as a successful study. Retry must perform another bake.
- No meshes, textures or render output are needed for the solver.
- Far player bodies remain active; limb pose/collision work is limited to
  players within 3 m of a low ball.
- After initial placement, player proxies follow the pose using native
  kinematic velocities, not per-frame transform teleports. Linear speed is
  bounded to 12 m/s world travel for torsos/heads; angular speed to 720°/s.
  The head shares the torso budget so it cannot lag behind an accepted fast run.
  Limbs retain the original 8 m/s world-space approach at root speeds up to
  8 m/s. Across 8–9 m/s they smoothly inherit root travel. Full sprint mode
  separately caps local articulation/error correction at 8 m/s, bounding total
  speed at 20 m/s. The blended transition does not claim an 8 m/s relative cap.
  A dormant limb can be placed when reactivated outside ball-contact range.
- `prewarm(track:players:plannedTouches:)` completes before a scene consumes
  `cached(track:players:plannedTouches:)`.
- Use `Recording.pose(at:)` and `orientation(at:)` for displayed ball/gaze
  inputs. The dense `ballTrack` is an export, not an input to legacy sparse
  contact inference. `touches` supplies actual contact centres,
  outgoing velocity, foot and action for the explicit player-animation cues.
- Existing source tracks and saved reviews are unchanged. A failed preparation
  of a new study shows Retry/Exit and never opens a silently substituted path.
  Older demonstrations retain their authored playback.

## Scope

This adds a real ball solver to authored local football demonstrations, not a
complete autonomous football game. Player routes remain authored. Collision
proxies are not exact deforming skin meshes. Intended passes can miss. Animation
IK aligns a foot to an admitted actual ball contact; it does not turn the
players into dynamic ragdolls. No FM/EA-level animation or headset performance
claim is made.
The torso remains a conservative upright capsule during a keeper's local
crouch; it is not an exact chest/head collision skin. Contact `outgoingVelocity`
is the velocity requested by the impulse, while recorded sample velocities
are the actual solver result after subsequent collisions.
Deliberate touches are reach-gated game-action impulses, not impulses inferred
from collision callbacks or a dynamically powered foot. Header/save gates do
not measure exact forehead/palm contact. There are no separate hand colliders.
Separate actual-study tests verify the visible full-head triangles and existing
rig palm markers against the native ball. Those checks cover the authored
header/save, not arbitrary imported trajectories or exact hand-skin collision.
Launch planning clamps flight time to 0.18–3 s and launch speed to 28 m/s. It
is a bounded planner, not a guarantee for arbitrary authored targets.

## API evidence

Checked against the installed visionOS 26.5 RealityFoundation Swift interface
and Apple's documentation:

- [RealityRenderer.update(_:)](https://developer.apple.com/documentation/realitykit/realityrenderer/update(_:))
  ticks simulation by the supplied interval.
- [PhysicsSimulationComponent](https://developer.apple.com/documentation/realitykit/physicssimulationcomponent)
  supplies world gravity and solver iterations.
- [PhysicsBodyComponent](https://developer.apple.com/documentation/realitykit/physicsbodycomponent)
  supplies body mode, material, mass, damping and CCD.
- [applyLinearImpulse(_:relativeTo:)](https://developer.apple.com/documentation/realitykit/hasphysicsbody/applylinearimpulse(_:relativeto:))
  applies the kick to the native dynamic body.

## Verification

Latest focused receipt: `/private/tmp/replayxi-native125-contact-final-01.xcresult`
(17 September 2026, visionOS simulator). **13/13 native physics fixtures
passed**, including native inverse aim for 8 m and 20 m ground passes, a 15 m
loft, independent-world isolation, head-height versus overhead collision and
the open space beside the narrower head. All 24 selected tests passed.

All three authored studies executed every planned action, recorded no misses
and passed the goal-entry assertion:

| Study | Admitted/planned | Samples | Debug cold bake | Max boot-surface error |
| --- | ---: | ---: | ---: | ---: |
| Counterattack, 10.5 s | 5/5 | 1,261 | 554 ms | 12.85 mm |
| Volley, 8.5 s | 5/5 | 1,021 | 353 ms | 19.90 mm |
| Rebound, 7 s | 6/6 | 841 | 369 ms | 9.76 mm |

Preparation times include the native aim previews. These are single Debug
samples, not FPS or headset performance measurements. Foot errors are measured
against actual recorded sphere surfaces across procedural far and skinned
near/low rigs. All 14 foot contacts passed the unchanged 30 mm limit after
the native foot-admission gate was tightened to 20 mm.

The actual volley header now meets the real full-head triangles within
17.30 mm (far), 6.17 mm (near) and 7.77 mm (low), inside the unchanged 30 mm
bound, with no measured sphere penetration. This is crown/head contact, not a
claim of recovered forehead anatomy. The actual rebound save reaches both
near/low palm markers within 2.72–3.67 mm of the sphere surface, keeps the
soles above the floor, and restores the same pose after seeking.
Receipts are exported in `/private/tmp/replayxi-native125-contact-final-01-attachments/`.
Full regression and release-build status are recorded in the
[final checkpoint](NATIVE125_CHECKPOINT.md).
The later [motion refinement](MOTION126_CHECKPOINT.md) records the sprint
controller, complete chest-relative head limits and current full-suite result.

Earlier integration receipts exposed real off-ball player blocks in authored
passing lanes. Those routes were corrected without disabling collisions or
relabeling missed touches as successes.

Issues discovered and fixed during the native loop: initial boot proxies were
constructed against the default origin instead of the final initial sphere;
capsule heights originally omitted their spherical-cap length; early-contact
cue changes could teleport a kinematic foot and add an excessive impulse;
standing header admission was too high; and guessed rolling pace missed long
receives. Native fixtures now cover these paths. Rejected explicit studies
never enter the successful replay cache.

The test suite exercises unforced free fall,
pitch rebound/ground clearance, native rolling/pace loss, torso collision,
near-player impulse versus missed remote impulse, immutable seek results,
exact cache keys, goal-frame/net response, header/save admission and invalid-input rejection. These tests must execute the
actual RealityKit solver; source-path sampling alone cannot satisfy them.
