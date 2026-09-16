# Loop 90 — Shape timeline and scene eligibility

## Confirmed mismatch

The shared annotation timeline offered every authored Shape mark. The actual
positional scene only shows the preset pressure mark in Problem, and no preset
marks in Ideal. Three Problem entries and all four Ideal entries therefore
opened inspectors for hidden geometry. Switching a selected Problem pressure
mark to Ideal also kept its inspector because the mark was still time-visible.

## Change

`PlaybackAnnotationPresentation` is the single view/stage rule for scene
admission and the event index. Non-positional views keep every mark. Positional
physical placement hides all marks, including while tracking is not ready.
Visual comparison keeps every coach-created mark and only Problem's authored
pressure mark. The per-frame scene predicate makes no filtered arrays.

The UI rebuilds its cached index on context changes, not on each replay frame.
The filter applies to mark entries and timing bands only. Cue events, stable
ordering, future timestamps, user marks and all stored data remain unchanged.
Normal match views retain the complete event list.

An ineligible selection closes only when the existing input-ownership gate is
open. The same policy is checked again after a held scrub or endpoint gesture
ends. Cleanup never cancels a transaction, seeks, edits a mark or opens a hidden
preset again. Existing time-window cleanup remains separate.

## Verification

Pre-fix native receipt: `/private/tmp/replayxi-parallel88-91-repro-01.xcresult`.
The initial eight `ReplayAnnotationPresentationEligibilityTests` had four
expected failures with 15 assertions; all four controls passed. Scene eligibility
was unchanged in this baseline; only the old index and retained selection failed.

The final class has nine cases covering actual scene/index parity, stage and
view switches, tracked-origin fallback, every user-mark kind, future timestamps,
normal match order/cues, held input, direct deferred cleanup/recheck and source
wiring. All nine passed in the targeted mixed receipt
`/private/tmp/replayxi-parallel88-91-mixed-02.xcresult`; this is not a clean
full-suite receipt. Full native and Release checks remain pending the parent.

Loop85's expiry/held-scrub fixture now selects the visible Problem pressure
preset instead of the first, hidden pass preset. Its ownership and expiry
assertions are unchanged; the choice is reachable under the new policy.

No headset interaction validation is claimed. Local-only, save schema and POV
behaviour are unchanged.
