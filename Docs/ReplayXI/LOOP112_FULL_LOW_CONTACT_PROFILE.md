# Loop112 — full low-detail ground contact

The new lower-detail skin has its own explicitly selected contact profile. The
existing near-player profile and its limits are unchanged.

The low profile includes every **1,707 vertex / 2,823 positive influence**, rather
than assuming the old near mesh's sparse contacts still cover a different mesh.
It is tied to the low USDZ and original motion hashes, exact canonical joint
names, one external root lift, and 80 finite affine inverse-bind matrices.
The provider verifies the bytes before decoding or publishing this profile.

Schema 2 requires `profileKind: full-low-mesh`, exact source/contact counts,
unbaked root lift and a 512 KiB cap. Default schema 1 retains the near profile's
512-vertex / 256 KiB caps. Matrix values are bounded and compared to the motion
rest basis within 0.0002 per component. This allows the measured source/export
rounding difference (about 0.000139), not an arbitrary replacement bind basis.
The actual packaged USD inverse binds are used for contact calculation.

Four targeted native tests pass, including malformed profiles, wrong bind
bases, size limits, four-pose minimum-height parity and repeated floor raising.
The largest Float minimum-height difference against the independent full-mesh
fixture was **0.1602 µm**. This is a conversion check, not a visual or biological
precision claim. Mixed-rig runtime cost and integration are separate Loop113
gates; a full contact profile does more CPU work than the sparse near profile.

Receipts:

- `/private/tmp/replayxi-contact112-native-01/7184B6A9-83D8-496B-81AC-7CA3093567BC.json`
- `/private/tmp/replayxi-low109-contact112-palette110-after-01.xcresult`:
  all 26 selected tests passed, including the four new contact cases and five
  unchanged near-contact regressions.

No headset frame rate, real-match reconstruction or live physical ragdoll is
claimed. The licensed source and complete conversion chain are in Loop102.
