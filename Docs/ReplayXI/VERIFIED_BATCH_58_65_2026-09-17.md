# Verified batch — loops 58–65

Verified at approximately 03:38 SGT on 17 September 2026.

## Scope

- Physical-drill admission, hidden annotation safety and stale callback handling.
- Decision lanes and current metrics aligned with displayed player positions.
- Stationary Ideal-shape animation and gaze; normal replay preserved.
- Cheap Decisions-button eligibility check.
- Enlarged-ball ground clearance and grounded positional shadow.
- Accurate saved-review blocking feedback.

This run also includes the previously backed-up authored arm counter-swing and
rear-facing head-attention corrections (loops 54 and 61).

## Results

- Native Debug suite: **607 total; 606 passed, 1 optional skip, 0 failed**.
  `/private/tmp/replayxi-parallel65-full-01.xcresult`
- Unsigned physical-device Release build: **passed**.
  `/private/tmp/replayxi-parallel65-release-01.log`
- Python checks: **123 total; 111 passed, 12 optional skips, 0 failed**.
  `/private/tmp/replayxi-parallel65-python-01.log`
- `git diff --check`: **passed**.

Native totals come from the result-bundle summary, including the two Swift
Testing cases. Build success is not a physical-device runtime or frame-rate test.

## Limits and preservation

The desktop is locked; no interactive Simulator or headset QA was claimed.
Loop 62 documents six inspected offline renders from actual scene joint poses.
The demo remains synthetic, not reconstructed video. Local-only operation and
existing save formats remain intact. User signing/project and Info.plist edits
are excluded from this Git backup, as are unrelated workspace files.
