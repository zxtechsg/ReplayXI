# Reference 128 — off-ball motion and video comparison

## Scope

Local-only Replay XI. Both teams receive the same presentation improvements.
No player path, ball recording, scenario ID, review schema, or source asset was
replaced. No claim of EAFC26/FM26 animation parity or recovered off-camera motion.

## Motion

- Off-ball players make individually timed checks of nearby opposing players,
  then return to the ball. These are explicitly authored attention cues, not
  eye tracking. Goalkeepers and close ball handlers retain ball attention.
- Threat checks blend continuously at neighbour boundaries and across rear
  bearings. Full recorded interaction windows retain the original target, with
  0.6-second eased margins. The target's horizontal range is preserved so the
  footwork solver does not mistake a glance for a closer ball.
- A bounded torso layer adds individual settling/breathing, shares a little
  existing gaze with the chest, and fills the native run's missing acceleration
  or braking lean. It does not replace source legs, stretch bones or move roots.
- A second visual pass replaces stiff idle arms with a relaxed, asymmetric
  football stance: roughly 17–23° elbow flexion and small forward/outward
  shoulder angles. It fades away by 2.8 m/s, preserving the running swing;
  braking adds only a small arm brace. Native source arm axes are cached once.
- Contact cores, impacts and stationary teaching poses exclude the new layer.
  Absolute-time sampling preserves deterministic forward, reverse and seeks.
- No extra skeleton, texture, scene traversal or full skeleton rebuild is
  introduced by the torso layer. This is a code-level work bound, not measured
  headset FPS. Tactical attention reuses the already prepared 22-player poses.

## Video → Replay concept demo

- Each featured study opens a movable split window: source video on the left,
  the real RealityKit scene on the right. It is not the dashboard's 2D canvas.
- The study, selected player and annotation snapshot are frozen for comparison.
  Changing the dashboard cannot silently pair a different play with the video.
- Separate video/3D timelines deliberately avoid a false frame-sync claim.
  The preview has play/pause, scrub, restart and speed controls.
- Play / Whole pitch framing uses fixed bounds, never a moving/head-following
  camera. The play bounds are prepared once, not reallocated each frame.
- Official YouTube loading is opt-in, uses the app's real client identity and
  handles blocked/unavailable sources. There is no proxy or media extraction.
- Local MP4/MOV references use AVPlayer and temporary file access. They are not
  uploaded, persisted in review JSON or treated as converted 3D worlds.
- Enter 3D uses the same room-admission path as the dashboard. Existing POV and
  annotation tools remain available. The miniature renderer is removed while
  the full room is presenting; repeated opening reuses one typed window.
- Clear labels identify this as an authored concept demo, not automatic video
  conversion. Imported footage does not alter the pre-authored reconstruction.

## Evidence and remaining limits

See [research notes](REFERENCE128_RESEARCH.md) for exact coverage of all five
scenes, the new 1080p cable-camera lead, FIFA's Mbappé breakdown and access gates.
No archive feed or restricted tracking was downloaded or incorporated. The
volley still uses its existing compressed authored timeline; changing that
requires a new scenario version so saved time-anchored annotations stay valid.

Higher-fidelity movement still needs a broader licensed football motion library,
retargeting/contact work and validated multi-view footage or tracking. This pass
improves secondary behaviour, not the underlying accuracy of unseen trajectories.

## Verification

- Focused motion run: 37 tests passed, including actual near/low/far foot,
  header and keeper-save contacts, head continuity and posture constraints.
  `/private/tmp/replayxi-reference128-motion-02.xcresult`
- Initial comparison run: 7 tests passed (snapshot isolation, clocks, safe
  source identity, layout bounds and invalid imports).
  `/private/tmp/replayxi-reference128-comparison-03.xcresult`
- Simulator inspection confirmed the true 3D scene and source consent panel
  together. Automated spatial clicks did not activate the source button;
  successful official video playback has not yet been visually verified.
- Final regression: **1,124 XCTest cases, two skipped, zero failures**, plus
  two passing Swift Testing asset checks. Includes ten comparison tests and
  ten off-ball pose tests. The network check is opt-in, not part of this total.
  `/private/tmp/replayxi-reference128-full-07.xcresult`
- The regression also produced 36 calibrated before/after close-ups across
  both teams, near/low/far detail and three motion fixtures. Final red idle,
  red braking and white idle/running images were inspected. These are static
  pose checks, not motion-capture validation or headset performance evidence.
  `.codex-derived/Reference128/offball-final/manifest.json`
- The separate live network check **failed** because the publisher rejected
  embedded playback of the World Cup source. Production surfaces that message
  with Open source / Choose clip alternatives. No restriction was bypassed.
  Local video loading passed with a generated MP4 in the regression, but the
  user must supply a usable local match clip for an in-window comparison of
  this blocked source. No actual official video playback is claimed.
  `/private/tmp/replayxi-reference128-network-08.xcresult`
- Fresh pre-test review backup: `.codex-derived/Reference128/reviews-before.json`
  SHA-256 `73f6b54e5c08cb5417c17ac8479ef0f1b7f2a570cc8577db6f70cb30eb14d646`.
  The installed app's review file matched this hash after both final test runs.

- Unsigned Release build for a physical visionOS device: **succeeded**.
  `/private/tmp/replayxi-reference128-device-09.log`
- `git diff --check` passed. An independent review found no actionable issues
  in the final arm-set patch. No physical-headset run was performed.

User signing and Info.plist edits remain unstaged. Normal simulator launch
uses the existing saved reviews; debug comparison routes are memory-only.
