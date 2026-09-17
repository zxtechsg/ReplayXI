# Native football checkpoint — 17 September 2026

## Delivered

- Three local strategy studies based on the supplied Argentina–France final:
  the 36′ counterattack, 81′ one-two volley and 108′ rebound.
- Real RealityKit ball gravity, rolling resistance, bounce, player collision
  proxies, goal posts and net panels. Kicks apply impulses, not path teleports.
- A prepared recording shared by timeline seeking, playback speed and POVs.
  Failed preparation offers Retry/Exit instead of showing an old trajectory.
- Explicit kick/receive/header/save rig cues, planted support, ball-facing
  side/back steps and low-speed readiness. No new proprietary player assets.
- Parametric 3D arcs: two fixed endpoints, adjustable curve amount and angle
  around the endpoint axis, with Undo and saved-review compatibility.
- Icon-first Draw/Tools controls, smaller submenus and accessible tool names.
  The existing movable controls remain world-fixed, not head-locked.

## Try it

1. Open **Strategy Analysis** and select one of the three new studies.
2. Enter spatial replay. Preparation runs once; the recording is cached.
3. Play, change speed or scrub. Select a player to inspect their POV.
4. Draw → curved-arrow icon, then choose the two endpoints.
5. Select the arc → Adjust → Curve. Drag sideways for amount, vertically
   for angle. Bend/Lift remains available in the secondary controls.

Old demonstrations and saved reviews retain their IDs and geometry. New scenes
are clearly marked as reconstructions, not recovered video tracking. This
work does not add online sessions or Group Activities.

## Verification

| Check | Result | Local receipt |
| --- | --- | --- |
| Full native suite | 1,046 XCTest cases, one optional skip, zero failures; both separate asset tests pass | `/private/tmp/replayxi-native125-full-04.xcresult` |
| Actual contacts and complete plays | All 24 selected tests pass; 16/16 planned actions and all three goals | `/private/tmp/replayxi-native125-contact-final-01.xcresult` |
| Python regression | 138 cases, 12 skips, zero failures | `/private/tmp/replayxi-native125-python-final.log` |
| Unsigned device Release | Build succeeds after the final fix | `/private/tmp/replayxi-native125-device-release-03.log` |

A final review found an 8 m/s head-proxy cap below the 12 m/s torso cap.
Both now share the same world-space budget. The added native 10 m/s alignment
test passes in full-04, alongside all previous coverage. The final post-fix
device build also passes. Signing/provisioning and hardware runtime were not
tested by that unsigned build.

### Visual/contact checks

The three real Factory scenes, near/far header contact frames, player parries
and arc controls were inspected. Foot contacts across all detail levels remain
within 30 mm; the measured maxima in the focused receipt are 12.85, 19.90 and
9.76 mm for the counter, volley and rebound respectively.

The actual header uses whole rendered-head triangles, not a fabricated marker:
17.30/6.17/7.77 mm gaps for far/near/low. Both near/low palms meet the actual
rebound save within 2.72–3.67 mm using existing rig palm markers. Soles remain
above the floor and seeking restores the same pose.

The user's local review file still matches its pre-test backup, SHA-256
`9d628840389c4f325d3498885b663b32a49c9c6600ee2c299649eedc20fbdf80`.
Test hosts and scripted demo routes use an in-memory library; normal launch
restores persistent local saves.

The latest Debug app was launched normally, without test/demo flags, in the
visionOS simulator; its process was confirmed running. The Mac was locked at
the final screen check, so the last launch has not been visually confirmed.
Unlock the Mac to view it, then select Strategy Analysis for the new studies.

## Limits

- These are short manually authored tactical reconstructions, not automatic
  video-to-3D tracking or a complete FM/EA-style autonomous football engine.
- Routes are authored. Player bodies are kinematic proxies, not dynamic
  ragdolls. No new high-fidelity assets or recovered mocap are claimed.
- Header testing proves head/crown contact, not exact forehead anatomy.
  Keeper tests use palm markers, not full hand meshes; there are no hand
  collision shapes. Nets are damped panels, not deforming cloth.
- Procedural contact and directional motion improved; the source run cycle
  can still slide. No headset frame-rate or motion-comfort claim is made.
- Simulator audit captures are 512 px without antialiasing. Its graphics
  logs include unsupported shader variants; passing captures are not a device
  GPU certification.
- Hand tracking, spatial dragging and sustained headset performance still
  require testing on a Vision Pro. Simulator UI automation could view the app
  but could not reliably operate its content window.

## Details

- [Physics](NATIVE_BALL_PHYSICS.md)
- [Rig/contact evidence](LOOP125_EXPLICIT_PLAYER_INTERACTIONS.md)
- [Verified broadcast windows and reconstruction limits](FOOTBALL_REFERENCE_STUDIES.md)
- [Arc controls](PARAMETRIC_ARCS_AND_ICON_TOOLS.md)
