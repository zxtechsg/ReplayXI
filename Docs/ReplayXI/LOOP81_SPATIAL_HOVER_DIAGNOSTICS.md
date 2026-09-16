# Loop 81 — spatial hover wiring diagnostics

Scope: read-only API research and test-only diagnostics. **No production hover
change or observed headset hover result.** Local replay, hit ownership, scene
assets and saved-review schema are unchanged.

## Verified current hierarchy

- Player `interaction-target` has input, collision and hover components, but no
  model descendants. `full-rig`, `table-marker` and an admitted skin are siblings
  under the player root (`PitchSceneFactory.swift`, `makePlayer` and its lazy
  visual attachment paths).
- Annotation body targets and card targets have the same separation. Space
  annotations use 12 collision-only ring segments
  (`AnnotationSceneAffordance.swift`, `makeBodyTarget` / `configureLabelTarget`).
- Decision-slot hit targets are siblings of their rendered rails and arrows
  (`DecisionOptionSceneOverlay.swift`, `makeSlot`).
- Jersey tags and selected endpoint handles are positive controls: their input,
  collision and hover owner contains the visible model descendants.

These are component-tree facts. A missing connection is not an observed headset
failure; the tests cannot activate the system's privacy-preserving hover effect.

## Apple / installed SDK evidence

- [HoverEffectComponent](https://developer.apple.com/documentation/realitykit/hovereffectcomponent/)
  documents descendant inheritance and requires input/collision components for
  receiving hover. A component on an empty child does not describe feedback on
  a sibling mesh.
- [groupID](https://developer.apple.com/documentation/realitykit/hovereffectcomponent/hovereffect-swift.struct/groupid)
  documents shared activation independent of hierarchy.
  [WWDC25, What's new in RealityKit](https://developer.apple.com/videos/play/wwdc2025/287/)
  also explains that grouped effects do not propagate to child entities.
- The installed XROS26.5 `RealityFoundation.swiftinterface` exposes `groupID`
  around lines 5098–5108 and `GroupID` around 5162, available on visionOS 26.
  Replay XI's existing deployment target is 26.0; no target change is needed.
- No public hover-only redirection API was found in the inspected RealityKit,
  RealityFoundation or `_RealityKit_SwiftUI` interfaces.
  [ManipulationComponent.HitTarget](https://developer.apple.com/documentation/realitykit/manipulationcomponent/hittarget)
  redirects to a manipulation component, not our existing semantic tap/drag
  handler. It is not adopted.

Apple's examples put collision/input components on every hover-group member.
They do not explicitly demonstrate a render-only group recipient. Grouping our
existing targets with render-only meshes is therefore a candidate for a small
runtime qualification, **not a verified production fix**.

## Diagnostic coverage

`ReplaySpatialHoverDiagnosticsTests` has five cases: player/body and jersey
control; all five annotation kinds including ring segments/cards; decision
receiver identity; endpoint-handle controls; and a small group API fixture.
JSON attachments report each target's inherited and group-linked visible models.
They explicitly record that no runtime hover activation was performed.

The group fixture changes only hover components on one existing hit target and
one existing mesh. It checks unchanged entity identities, parents, transforms,
input/collision components and mesh resources. It proves SDK component storage,
not that a render-only recipient glows. Missing links are recorded rather than
made a permanent zero-link expectation.

Exported evidence: `/private/tmp/replayxi-hover81-diagnostics-01`. The native
graphs recorded zero linked visible models for 22 player-body targets, 16
annotation-body targets, five annotation cards and four decision targets. The
22 jersey controls linked 25 models; two endpoint controls linked eight. The
component-only group fixture linked one existing mesh. Every sample records
`runtimeHoverWasActivated: false`.

Native receipt: all five diagnostics passed in
`/private/tmp/replayxi-parallel80-84-mixed-01.xcresult`. That mixed batch ran 19
tests: 15 passed and four expected pre-fix failures belonged to the separate
Loop84 label-bounds tests. It is not a clean full-suite receipt.

No Release or physical-device claim for this diagnostic batch. Production
integration remains deferred until the API qualification and actual hover
appearance are verified.
