# Verified batch — loops 74–77

Verified at approximately 04:31 SGT on 17 September 2026.

## Scope

- Shape players aim at the grounded ball instead of hidden replay loft.
- Clear confirmation cannot report success during an owned timeline scrub.
- Continuous turn estimates remove a reproduced near-stationary head snap.
- Procedural mesh visibility updates only on a skin/fallback transition.

At the same 5 ms keeper replay interval, actual native skin head rotation changed
from **10.246923° to 0.193827°**; neck rotation changed from 4.324045° to 0.104678°.
This is one verified sample, not a claim about captured human motion or every frame.
Eight offline before/after Blender renders use the same existing library and
actual final native poses. Derived images are not included in the Git backup.

Stable Shape updates previously visited 168 rig entities and rewrote 96 model
enable flags; the targeted checks now record zero of both. Initial admission and
visibility changes still perform the work. This is not a measured headset FPS gain.

## Results

- Full native Debug suite: **676 total; 675 passed, 1 optional skip, 0 failed**.
  `/private/tmp/replayxi-parallel77-full-01.xcresult`
- Unsigned physical-device Release: **BUILD SUCCEEDED**.
  `/private/tmp/replayxi-parallel77-release-01.log`
- Python checks: **126 total; 114 passed, 12 optional skips, 0 failed**.
  `/private/tmp/replayxi-parallel77-python-01.log`
- `git diff --check`: **passed**.

Pre-fix native evidence and two corrected test assumptions are documented in the
individual loop notes. Exact rewind, normal turns, mesh visibility, and Store
ownership controls remain covered. The optional native skip is a transient
legacy imported-asset check, not a required bundled-asset test.

## Limits and preservation

Local-only operation, saves, assets, telemetry and free-look camera behavior are
preserved. The demo remains synthetic. The locked desktop prevents interactive
Simulator/headset QA; build success and offline renders do not replace it.
User signing/project and Info.plist edits and unrelated workspace files remain
outside the scoped Git backup.
