# Loop 40 — original Blender pitch

## Delivered geometry

Original 105 x 68 m playing field with mown stripes, repeating fine turf grain,
painted goal areas, penalty arcs/spots, centre/corner markings and netted goals.
The surrounding grass apron supports the goals. The tactical board now fits
the complete asset. Dimensions reference IFAB Law 1 (linked in asset provenance).

The final reviewed asset is 7,234 triangles, two static meshes, four materials
and two 512-pixel textures. Runtime USDZ size is 1.13 MB. These are resource counts,
not a headset frame-rate measurement or a claim of FIFA-level rendering.

## Runtime integration

- Hash, model count, material count, triangle budget and upright dimensions
  are checked before the asset is admitted.
- Imports occur before immersive entry. Replay clones cached resources.
- Flattening originally discarded the USD root's up-axis conversion; the
  import regression caught this and the normalized model now includes it.
- Semantic surface/marking names preserve pitch hiding in local drills.
- First-person contrast changes keep the net's second material intact.
- Simulator inspection showed the turf became too dark under warm/dim room
  lighting. Its two imported texture tiles now use lighting-independent
  materials; goal/frame shading remains separate.
- Failed admission retains the procedural pitch; no playback-frame importing.

## Evidence

- Blender overview and goal close-up inspected in v1 and v2. v2 adds the apron.
- Initial import regression failed on orientation, then passed after correction.
- Full simulator suite after the final lighting change: **399 passed, one optional
  fixture skipped, zero failures**
  (`/private/tmp/replayxi-pitch39-verified-full-tests.xcresult`).
- Final texture/import/view-visibility regressions: 3 passed
  (`/private/tmp/replayxi-pitch39-contrast-r3-tests.xcresult`).
- Local-only capability/source checks: 5 passed.
- Final simulator table/player POV screenshots inspected:
  `/private/tmp/replayxi-pitch39-table-final.png` and
  `/private/tmp/replayxi-pitch39-pov-final.png`. Pitch markings, goals and turf
  remain visible in a dim, warm passthrough scene. These are visual checks, not
  proof of physical comfort, live gesture performance or device FPS.
- Updated unsigned Release compilation passed
  (`/private/tmp/replayxi-pitch39-verified-release.log`).

## Next visual issue

The synthetic Match Replay preview still draws colourful placeholder surfels
around the pitch. They appear as floating triangles in player POV and distract
from the tactical scene. They should not be presented as real reconstruction;
revisit their default visibility and keep any admitted real-world asset path.

This is original strategy/replay scene art. It is not a reconstruction of an
actual match. Reference footage remains unstaged, and the replay is labelled
synthetic. Original human-player asset work is still incomplete.
