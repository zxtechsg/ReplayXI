# Real World Match Replay pipeline

Replay XI separates visual generation, navigable video and spatial
reconstruction. They are different artifacts with different guarantees:

1. **Generate an original source clip.** Reactor FastH3 creates a generic,
   logo-free football sequence. Do not upload or derive this demo from a ripped
   broadcast, club footage, or real-player likeness.
2. **Generate reconstruction coverage.** A cleared still from that clip can seed
   Reactor LingBot World 2. Record a slow, continuous camera orbit/translation.
   LingBot World 2 returns a navigable video stream; it does not return a mesh,
   point cloud, USD, GLB, calibrated camera set, or Gaussian splat.
3. **Reconstruct spatial geometry.** Feed the generated coverage video to the
   official LingBot-Map pipeline on a compatible CUDA machine. LingBot-Map is
   the LingBot component that reconstructs a spatial point cloud from video.
4. **Optionally optimize a Gaussian splat.** This is a distinct conversion or
   training stage. Its output must remain a visual background only unless it is
   registered and measured against authoritative tracking data.
5. **Prepare a RealityKit artifact.** Convert the registered visual result to a
   Y-up, metre-scale `.usdz` or `.reality` asset without changing the canonical
   105 × 68 metre pitch registration. This is the file the app can actually
   render; a raw LingBot-Map point cloud is retained as provenance but is not a
   RealityKit import format.
6. **Import through the manifest gate.** Run
   `Scripts/validate_replayxi_world_manifest.py`. The validator checks rights
   provenance, required stages, safe relative paths, SHA-256 hashes, canonical
   pitch coordinates and the explicit rule that generated pixels are not
   tactical truth. Full validation can emit `ReplayXIWorldAdmission.json`, the
   runtime receipt that binds the admitted RealityKit asset to its exact hash
   and byte count.

## Tactical authority

The reconstructed world supplies atmosphere and visual context. Player IDs,
positions, heading, ball state, replay time, POV translation and coach
annotations continue to use Replay XI's deterministic tracking model. This is
what keeps all headsets on one review state and prevents a generative frame from
moving an offside line, swapping a shirt number, or changing the receiver of a
pass.

The intended composition is:

```text
generated/cleared visual capture ──> LingBot coverage ──> 3D visual world
                                                          │
authoritative player + ball tracks ───────────────────────┼──> Replay XI scene
                                                          │
shared time-linked annotations ───────────────────────────┘
```

## Required manifest shape

```json
{
  "schemaVersion": 1,
  "worldID": "right-wing-overlap",
  "displayName": "Real World Match Replay",
  "source": {
    "kind": "original-synthetic",
    "owner": "Replay XI prototype",
    "rightsBasis": "Original synthetic generation with no imported footage.",
    "promptOrCaptureNote": "Generic teams perform one right-wing overlap.",
    "containsRealPlayerLikenesses": false
  },
  "coordinates": {
    "upAxis": "Y",
    "metresPerUnit": 1,
    "pitchLengthMetres": 105,
    "pitchWidthMetres": 68,
    "origin": "pitch-centre",
    "positiveZ": "home-attacking-direction",
    "positiveX": "home-right"
  },
  "tacticalTruth": {
    "generatedPixelsAreAuthoritative": false,
    "trackingAuthority": "Replay XI deterministic authored tracking fixture"
  },
  "pipeline": [
    {
      "name": "generate-video",
      "provider": "Reactor",
      "modelOrVersion": "MiniMax FastH3"
    },
    {
      "name": "generate-navigable-video",
      "provider": "Reactor",
      "modelOrVersion": "LingBot World 2"
    },
    {
      "name": "reconstruct-3d",
      "provider": "LingBot-Map",
      "modelOrVersion": "pinned-repository-revision"
    },
    {
      "name": "prepare-realitykit",
      "provider": "Replay XI offline conversion",
      "modelOrVersion": "world-admission-v1"
    }
  ],
  "artifacts": [
    {
      "role": "source-video",
      "path": "source.mp4",
      "sha256": "<64 lowercase hex characters>"
    },
    {
      "role": "reconstruction-point-cloud",
      "path": "world.ply",
      "sha256": "<64 lowercase hex characters>"
    },
    {
      "role": "realitykit-world",
      "path": "ReplayXIAdmittedWorld.usdz",
      "sha256": "<64 lowercase hex characters>"
    }
  ]
}
```

Validate a completed handoff and generate its runtime receipt:

```sh
python3 Scripts/validate_replayxi_world_manifest.py \
  path/to/replay-world.json \
  --write-admission-receipt path/to/ReplayXIWorldAdmission.json
```

Use `--schema-only` only while staging the handoff. It is not an admission gate
for a bundled build and cannot emit a receipt. Copy the generated receipt and
the exact hash-matched `.usdz`/`.reality` artifact into
`ReplayXI/Resources/Worlds/`. The Xcode synchronized group copies them into the
application bundle. `ReplayWorldPreviewFactory` then verifies receipt schema,
safety labels, coordinate contract, runtime byte count and SHA-256 before
calling RealityKit's entity loader. Imported context has input, collision and
physics components removed recursively so it cannot steal annotation gestures
or disturb the tracked scene. Any missing, stale, malformed, symlinked or
hash-mismatched handoff fails closed to the original procedural preview.

For `club-owned-capture`, `licensed-capture` or `open-data-reconstruction`, add
a hash-locked `rights-record` artifact. Real-player likenesses must also carry a
non-empty `source.likenessRightsBasis`. Original synthetic inputs are rejected
if they claim to contain real-player likenesses. A remote provenance URL must
be absolute HTTPS, and YouTube/broadcast URLs remain inadmissible inputs. The
validator accepts those rights-cleared source classes for offline staging, but
the current app loader deliberately admits only `original-synthetic` receipts:
the dashboard's source tile is visibly fixed to `SYNTH`. A captured/licensed
world must not ship until that tile and accessibility label read provenance
from the admitted receipt.

## Current prototype status

The application scenario remains a clearly labelled synthetic preview until a
generated clip, LingBot-Map reconstruction, hashes and licence/rights record all
pass the manifest gate, a RealityKit artifact has been produced, and the
receipt/asset pair is bundled. The UI must not claim that the demo is
reconstructed from the Manchester United–Tottenham broadcast or any other
third-party match. No generated clip, point cloud, Gaussian splat, admission
receipt or admitted world asset is currently bundled; therefore the factory's
deterministic four-mesh procedural shell is the active visual fallback.

Useful primary references:

- [Reactor LingBot World 2 API](https://www.reactor.inc/models/lingbot-world-2/api)
- [LingBot World 2 repository](https://github.com/Robbyant/lingbot-world-v2)
- [LingBot-Map repository](https://github.com/robbyant/lingbot-map)
- [Reactor terms](https://www.reactor.inc/legal/terms)
