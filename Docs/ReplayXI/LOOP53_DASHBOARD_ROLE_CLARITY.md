# Loop 53 — Dashboard role and POV clarity

## Changes

- Room entry now distinguishes Closed, Opening, Open and Closing. An open room no longer shows a disabled “Enter” action; its hint points to the room’s Exit control. Request-owned opening/dismissal is unchanged.
- Home quick-POV rows actually enter first person, pause playback and keep the replay time. A row is marked selected only when its POV is active. The existing home/away picker remains available.
- Shape Focus reuses that rail for role stations, derived from the scenario’s three formation targets. It retains the positional view and comparison stage. Other players cannot be selected as invalid stations.
- Successful role changes report `Role station: #n · target label`, not `Player POV`. Rejected, stale or gesture-blocked choices cannot replace rejection text with a success message, including reselecting the current role.
- Rows have a 44-point minimum height, larger shirt digits, wrapping role labels, explicit action hints and accessibility selection traits. Status text wraps rather than truncating after three lines.
- Playback, cue, view and POV controls respect active drawing, annotation adjustment and timeline ownership. A short edit hint explains the lock. The timeline slider remains enabled during its own drag, but is blocked by unfinished annotation edits.

## Checks

- All 16 `ReplayDashboardClarityTests` passed: real station filtering/actions, camera versus role selection, time preservation, blocked/stale choices, opponent POV route and source wiring.
- Combined Simulator suite: **525 passed, 1 optional skip, 0 failed** (526 total). Receipt: `/private/tmp/replayxi-alignment52-full-01.xcresult`.
- Combined Python checks: **111 passed, 12 optional skips**. Swift parsing and scoped diff checks passed.
- Unsigned physical-device Release: **BUILD SUCCEEDED**. Receipt: `/private/tmp/replayxi-alignment52-release-01.log`.

The desktop was locked. This pass checked code, interaction state and declared layout sizes, not an interactive visual or headset comfort pass. No claims of measured hit accuracy, rendering quality or hardware performance are made.
