# Tripo player reference — 30 September 2026

Reference image: [footballer-a-pose-v1.png](AssetReferences/footballer-a-pose-v1.png).
Generated once with the built-in image-generation tool, inspected for a complete
body, separated limbs, blank kit and neutral A-pose. This is a 2D input for
Tripo, not a new mesh, rig, motion clip or production player replacement.

On 1 October the user completed login in Chrome. One Smart Mesh P2.0 free-trial
mesh, one 20-credit texture job and one 20-credit humanoid auto-rig completed.
Starting balance: 3,145; latest verified balance: 3,050. Our spend: 40; another
55-credit balance decrease is unattributed on this shared account. Maximum spend: 2,201;
minimum reserve: 944.
See [credit ledger](TRIPO_CREDIT_LEDGER.json). No credentials or codes are saved here.

The existing canonical 80-bone GLB was imported through Blender MCP into a
separate `ReplayXI Player Upgrade Reference` scene and placed in rest pose.
The prior pitch and startup scenes were preserved. This is the comparison rig
for checking the incoming generated mesh, not completed retargeting.

The exported textured GLB is backed up in
[authoring assets](../../Assets/ReplayXI/TripoFootballer/ReplayXI_Footballer_P2_Source.glb),
outside the app bundle. It has been inspected from front, back and side in Blender.
It is still an offline candidate, not a runtime replacement. Next: validate
skin deformation, make team colours,
build near/low detail and contact data, then verify native import and performance.
The auto-rig GLB failed movement QA. A Blender-specific FBX export is requested
from the user after Chrome blocked the ZIP download. See [run163](IMPROVEMENT_RUN_163.md).

## Exact image-generation prompt

Use case: stylized-concept. Asset type: single image reference for generating a realistic rigged football player for a native Apple Vision Pro match analysis app. Create one full-body, high-fidelity realistic 3D game character studio render of a generic adult male professional association football player. Natural lean athletic proportions, defined but not exaggerated leg muscles, realistic face and skin, short tidy dark hair. Neutral symmetric A-pose: standing straight, feet shoulder width, both arms extended diagonally down at 45 degrees, elbows straight, relaxed open hands with all five fingers separated and palms facing forward. Arms clearly separated from torso and hands from shorts. Face and torso directly towards camera, eyes level forward. Plain fitted white short-sleeve football jersey, plain dark charcoal football shorts ending above knees, white knee-high socks, low-cut matte black studded football boots. Subtle fabric weave, sleeve seams and believable small cloth folds; clear separate garment boundaries. Blank jersey front, no printed numbers, no club crests or sponsors, no logos. Complete anatomy visible from top of hair to soles and boot studs with generous margin all around. Orthographic front view, camera at mid-body, no foreshortening, feet on the same level, body centred. One person only against a uniform very light grey background, soft neutral flat studio lighting revealing form evenly, minimal soft ground shadow. Clean production character modelling reference, crisp accurate silhouettes, physically believable materials. No stadium, no pitch, no ball, no props, no platform, no text, no labels, no watermark, no extra views or figures. Portrait composition with enough width to fully include both hands. Not an action pose. This reference will be used for image-to-3D, mesh cleanup and skeletal skinning.
