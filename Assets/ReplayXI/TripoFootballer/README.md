# Tripo footballer — authoring source, not bundled

Generated on 1 October 2026 from our [A-pose reference](../../../Docs/ReplayXI/AssetReferences/footballer-a-pose-v1.png),
using the user's authorized shared Tripo account. No third-party game mesh or
real person's scan was used. Applicable account/service terms still govern use;
this record does not claim unrestricted redistribution or commercial rights.

- Asset ID: `7b99bd29-c5db-4c97-8bf4-067618bdeb27` (Private).
- Smart Mesh P2.0; one free trial; requested quad / 8,000 faces.
- Texture: 20 credits. Humanoid / Mixamo auto-rig: 20 credits.
- [Credit ledger](../../../Docs/ReplayXI/TRIPO_CREDIT_LEDGER.json): 40 spent;
  3,105 remaining from 3,145. No purchase, upgrade or subscription.
- Both GLBs retain the source 4K texture. Rigged export includes the skeleton.

| File | SHA-256 |
| --- | --- |
| `ReplayXI_Footballer_P2_Source.glb` | `e4fbdbcf98c631d283733ff9f339dd2bf01877bf8ab81756b6fe274a25c10eb5` |
| `ReplayXI_Footballer_P2_Rigged.glb` | `132f0c84715f9337ef98366fe7edbb00db9c72fd6d2530bff8ea863d712a4b34` |

The source imports as 17,082 triangles / 16,702 vertices including UV seams.
Inspect skinning rather than relying on Tripo's displayed polygon count.
White/red kits use identical geometry and scale. New 2K colour atlases are
generated locally by `Scripts/blender/prepare_tripo_kit_candidate.py`.

Do not copy these straight into runtime resources. The existing app validates
an 80-joint skeleton, two material sections, exact vertex/contact data and
asset hashes. The first nearest-surface weight transfer failed visual QA
(arms/sleeves). Its finite normalized weights did **not** establish good motion.
Auto-rig retargeting is a separate offline candidate and needs its own review.

Before adoption: retarget idle/run/kick/head poses, inspect sleeve and hip
deformation, build near/far detail, regenerate number/contact surfaces, verify
USDZ/RealityKit import, and measure performance. Keep the working app unchanged
until those checks pass.
