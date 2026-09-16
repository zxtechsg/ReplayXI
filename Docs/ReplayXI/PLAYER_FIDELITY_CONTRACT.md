# Replay XI player-fidelity contract

## Outcome

The app now also contains `ReplaySkinnedAthleteProvider`: a licensed Rocketbox
80-joint skin with deterministic idle/run sampling and head look. It uses its
own bone-array contract, not the procedural child-entity hierarchy below. See
the [asset ledger](THIRD_PARTY_ASSETS.md#bundled-single-skeleton-rocketbox-body--2026-09-10).
It reserves two material sections plus two jersey draws per near subject;
5,012 skin vertices and 8,146 skin triangles are shared before instance skinning.
The existing procedural budget is **not** the skinned body's geometry budget.
The admitted near skin now remains visible through walks, cuts, touches and
reviewed impacts, using deterministic football/impact retargeting. The
procedural hierarchy remains its interaction and fail-soft fallback, not the
normal visible body for every action. Headset frame-time qualification and
football-specific mocap remain pending.

The original procedural athlete renderer can replace
the close procedural mannequin without importing proprietary football-game
content. It uses cached `MeshDescriptor` geometry with authored anatomical
profiles: shoulder-to-waist taper, separate pelvis, quadriceps, calf, jaw,
hairline and forward boot. It retains the existing absolute-time locomotion and
physics-assisted ragdoll semantics through one stable named-joint contract.

No EA Sports/FIFA/FC model, texture, animation, logo, likeness or extracted game
data is used. The repaired Quaternius USDZ is now also a hash-locked,
development-only near-field pilot. It has three skeleton copies, seven textures
and no production LODs, so it is capped at one imported player and is never the
22-player runtime path. The original procedural rig remains authoritative for
interaction, deterministic ragdoll and every fallback.

## Integration surface

Before opening the immersive space, build the finite geometry cache:

```swift
try ReplayAthleteFactory.prewarm(
    for: scenario.players,
    lods: [.near, .far]
)
```

Create a rig whose root and joint names are compatible with the existing scene:

```swift
let athlete = try ReplayAthleteFactory.make(for: player, lod: .near)
playerEntity.addChild(athlete.root) // root name: "full-rig"

ReplayAthleteMotion.update(
    athlete,
    from: player,
    at: playhead,
    ragdollCue: activeCue
)
```

The required hierarchy is:

```text
full-rig
└── body-root
    └── hips
        ├── spine
        │   ├── neck → head-root
        │   ├── left-shoulder → left-elbow → left-wrist
        │   └── right-shoulder → right-elbow → right-wrist
        ├── left-hip → left-knee → left-ankle
        └── right-hip → right-knee → right-ankle
```

`ReplayAthleteJointBinding` validates both presence and immediate parentage, so
a future licensed one-skeleton USDZ can conform to the same semantic contract.
The near LOD maps all deterministic gait and `PlayerRagdollPose` channels. Far
LOD retains the joint graph but intentionally animates only proximal limb
silhouettes; an impact subject must be promoted to near before ragdoll display.

## Jersey numbers

Front and back near-field digits are original extruded seven-segment meshes.
They use deterministic ordered geometry, one single-material model per number,
and a bounded 0...99 cache. They do not call `MeshResource.generateText`, load a
font or invoke CoreText. This removes the simulator's repeated font-name warning
and keeps two-digit shirts crisp under scale.

At far LOD, a physical 25 cm shirt digit is below useful angular size and costs
one draw per player. It is intentionally omitted; the existing gaze-sized
tactical identity tag remains the accessible number. Mid and near retain the
back number, and near also retains the chest number.

## Measurable LOD envelope

All geometry is opaque and uses simple materials. Immutable mesh resources are
shared across players; team/appearance variation is material and root scale.
`ReplayAthleteBuildMetrics` accounts for every model, generated vertex and
triangle in an instance and fails construction if its LOD budget is exceeded.

| LOD | Maximum single-material models | Vertex ceiling | Triangle ceiling | Contract |
| --- | ---: | ---: | ---: | --- |
| Near | 29 | 4,800 | 6,400 | face, kit trim, front/back number, distal articulation, ragdoll |
| Mid | 19 | 2,700 | 3,800 | smooth body, back number, distal gait |
| Far | 7 | 1,800 | 2,500 | seven-draw silhouette, proximal gait, tactical tag supplies number |

Apple recommends keeping a whole Shared Space below roughly 250 draw
calls and 250,000 vertices/triangles, and a Full Space below roughly 500 draw
calls and 500,000 vertices/triangles.
The conservative athlete-only plans are therefore:

| Space | Near | Mid | Far | Athlete draw upper bound | Remaining Apple draw envelope |
| --- | ---: | ---: | ---: | ---: | ---: |
| Shared | 1 | 0 | 21 | 176 | 74 |
| Full | 4 | 0 | 18 | 242 | 258 |

These are **athlete-only** figures, not claims that the complete scene fits.
Pitch markings, goals, ball, labels, selection affordances and coach annotations
consume the remaining envelope. Hide redundant tactical labels where geometric
numbers are readable, keep annotation visibility sparse, and verify the whole
frame in RealityKit Trace on physical Vision Pro hardware. Renderer batching is
an optimisation, not something these conservative figures assume.

Primary guidance:

- [Reducing the rendering cost of RealityKit content on visionOS](https://developer.apple.com/documentation/visionos/reducing-the-rendering-cost-of-realitykit-content-on-visionos)
- [Reducing CPU utilization in your RealityKit app](https://developer.apple.com/documentation/realitykit/reducing-cpu-utilization-in-your-realitykit-app)
- [MeshDescriptor](https://developer.apple.com/documentation/realitykit/meshdescriptor)
- [Improving the performance of a RealityKit app](https://developer.apple.com/documentation/realitykit/improving-the-performance-of-a-realitykit-app)

## Honest fidelity boundary

The procedural fallback is still a simplified prototype, not a
photogrammetric player, cloth simulation or licensed broadcast/game model.
The separate admitted Rocketbox near body does provide a licensed continuous
weighted skin, kit textures and a single 80-joint skeleton. These are different
rendering paths; neither makes the seven-model far silhouette realistic.
Football-specific mocap, stronger original player art, authored skin LODs and
physical-device profiling remain unfinished. Reviewed impacts are
deterministic playback, not evidence of a live physically simulated ragdoll.

## Validation

`ReplayXITests/ReplayAthleteRigTests.swift` covers:

- all required joints and exact parentage at every LOD;
- actual ModelEntity counts against the explicit budgets;
- human-scale visual bounds;
- font-free front/back number placement and cache reuse;
- shared mesh reuse across team appearances;
- LOD hysteresis and invalid-distance handling;
- Shared/Full Space athlete-only envelopes;
- deterministic seek, gait and ragdoll mapping;
- real boot visual bounds across the complete 32-second gait; and
- the unique 76 kg kinematic ragdoll proxy profile.
