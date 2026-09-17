# Loop 123 — saved annotations at the supported limit

Test-only extension of the existing 16/64-mark scene diagnostic to 128 marks,
the Store's current limit. No application behaviour or limit was changed.

The same real Store path creates, labels, saves and restores all marks. The
new case also rejects a 129th drawing attempt without changing history. It
checks the normal annotation render budget during selection and endpoint edits,
preserved scene/mesh identities, exact cancellation and the unchanged save.

## Harness correction

The first run failed only its distinct-glyph count: 68 instead of 128. The
probe stored bare ObjectIdentifiers from short-lived native mesh wrappers.
Once outside the shared 64-entry text cache, wrapper addresses could be reused.
The corrected probe retains each MeshResource while counting. No expected
count, product validator or geometry assertion was relaxed.

Before: `/private/tmp/replayxi-annotations123-capacity-01.xcresult` — the new
case failed that one assertion; existing 16/64 cases passed.

After: `/private/tmp/replayxi-annotations123-capacity-02.xcresult` — all three
cases passed. Attachment:
`/private/tmp/replayxi-annotations123-capacity-data-01/508C5AF6-4F9E-4DE6-A2F8-C4D8CFCF596A.json`.

## Observed work, not a frame-rate claim

- Restored history retains all 128 mark roots and 128 glyph resources; the
  shared text cache stays at 64 entries.
- Sixty unchanged playback updates build no mark trees and rewrite no geometry.
- Sixty samples of one selected endpoint build no trees and update only that
  endpoint's geometry once per sample; no unchanged marks are rewritten.
- The selected phase enables two mark roots / seven model entities inside the
  marks subtree. Selection handles elsewhere are not included in that count.
- Cancel restores the exact baseline. Saved history is unchanged.

Cold construction of this maximum-size history is not free: this instrumented
Debug run took about 528 ms to apply it, including 125 newly created mark trees.
Its 60 unchanged updates totalled about 58 ms, and 60 Store/scene edit samples
about 92 ms. These wall-clock diagnostics include their existing instrumentation,
exclude rendering and do not measure headset CPU, GPU, input latency or FPS.
The initial build cost remains a known limit, not a claimed optimisation.

The final integrated suite also passed: 920 passed, one optional skip, zero
failures. See the [final batch receipt](VERIFIED_BATCH_122_124_2026-09-17.md).
