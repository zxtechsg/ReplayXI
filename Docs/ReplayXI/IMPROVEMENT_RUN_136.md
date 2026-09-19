# Improvement run 136

Local-only Match Replay and Strategy Analysis. Goal remains active.

## Timing drafts and navigation

- The control deck owns timing drafts, so retracting/replacing a drawer cannot silently lose text.
- Leaving a dirty editor offers inline Apply changes, Discard or Keep editing. No immersive modal.
- Apply resolves In/Out and position-time changes atomically, with one Undo and no playhead jump.
- Reset/load/delete/history/drawing/placement cannot remove an unresolved draft's source.
  Those domain actions remain explicit retries; resolving text never secretly replays deletion.
- Ownership is synchronous with text input, not delayed to SwiftUI's next observation pass.
  Lifecycle cleanup detaches stale bindings. Partial window/key commits preserve the other draft.
- Normal snapshots retain annotation array copy-on-write storage. Active geometry previews still
  mask uncommitted positions, and timeline previews still publish committed time.

52 focused timing/session/keyframe/snapshot/gesture-autosave tests passed. The initial baseline
batch passed 26 tests, including persistence measurements and native stationary-turn captures.
Largest-text inline decision capture inspected. Production review SHA-256 unchanged:
952e501de62f36e391a5b471175c883d0deb9e981a5c6cfc04f607c6dc5ded65.

## Measured save baseline

Near-capacity fixture: 8,046,227 bytes, seven named reviews, current review with 128 annotations
and 64 position keys each. DEBUG simulator synchronous elapsed time, not device/FPS results:

| Operation | Total | JSON encoding | Validation |
| --- | ---: | ---: | ---: |
| Five unchanged autosaves | 6.08 ms | none | 5.88 ms |
| Playhead-only change | 231.76 ms | 226.47 ms | 1.23 ms |
| One position-key change | 245.54 ms | 233.38 ms | 1.18 ms |

These are single instrumented runs without timing thresholds. Atomic backup precedes primary
write; state adoption follows successful writes.

## Save optimization

- Unchanged autosaves compare against the previously validated private state before validation.
  Nonfinite dates still reject; changed states still receive full validation.
- Unchanged named reviews reuse a known byte range of the last good document. Dynamic content
  remains JSONEncoder-generated; no arbitrary loaded-JSON scanner or second retained fragment.
- Cache adoption follows successful primary write only. Rename, delete, order or state changes
  invalidate reuse; failed backup/primary writes retain both prior state and prior cache.
- 32 persistence/capacity/scheduling/read-failure tests passed, including independent schema-v1
  encoder byte equivalence, escaping, equal dates, newer-schema protection and actual I/O failures.

Same near-capacity simulator fixture, one instrumented comparison run:

| Operation | Total | JSON encoding | Named-review bytes reused |
| --- | ---: | ---: | ---: |
| Five unchanged autosaves | 0.19 ms | none | none |
| First changed save after load, uncached | 242.80 ms | 238.15 ms | none |
| One position-key change, cache warm | 37.23 ms | 32.71 ms | 6,920,638 |
| Playhead-only change, cache warm | 37.84 ms | 33.00 ms | 6,920,638 |

Warm-save improvement is not a first-load fix or headset frame-rate measurement. Primary and
backup payload sizes are unchanged. Committed/pushed as 17edb7d.

## Arc precision parity

VoiceOver's eight custom arc actions previously ignored Fine and used 25 cm / 5° steps.
Joystick, buttons and VoiceOver now share 5 cm / 1° fine steps and matching spoken hints.
20 controller/precision/native-visual tests passed; largest-text capture inspected.
All 16 mode/precision/axis/sign combinations match one joystick notch and one-step Undo.
Committed/pushed as b613f95.

## Stationary-turn baseline

Underlap keeper liv-25, 3.30–3.80s: 52.015° heading change with near-zero root travel and constant
distance-based gait phase. Both grounded soles slide about 19.2 cm. Native near/low captures and
120 Hz sole measurements reproduce the defect; no trajectory or motion-capture claim is made.

The first turn-step attempt passed the actual keeper/outfield windows, contact guards and
near/low floor/bone checks, but failed 96 assertions in one synthetic onset/reversal test
(maximum 9.65° joint step at 120 Hz, limit 8°). A wider presentation-only blend window smooths
admission/release without changing the actor's heading or foot phase. Visual review then found
converging knees; bounded knee-plane yaw now preserves a slightly outward lane.

Final focused motion run: 33 tests passed. Six native frames captured; near/low stepping and
knee alignment inspected. The keeper's full-weight support drift is below 0.001 mm in this
specific stationary window, while the swing sole rises about 7 cm. The moving outfield window
retains 1.73 mm support drift. Fades are not claimed to lock perfectly. Maximum actual keeper
joint step is 3.28° at 120 Hz; synthetic start/stop/reversal cases peak at 7.24°, below the unchanged
8° regression threshold. Near/low, both teams, 180°/360° boundaries, exact rewind, bone lengths,
floor clearance, touch protection and stationary teaching poses pass. No authored trajectory,
ball physics, procedural fallback or match-data interpretation changes.

Evidence: /private/tmp/replayxi-cycle136-baseline-v2.xcresult,
/private/tmp/replayxi-cycle136-timing.xcresult, /private/tmp/replayxi-cycle136-perf-motion.xcresult
(includes the documented first-attempt motion failure), /private/tmp/replayxi-cycle136-arc.xcresult,
and /private/tmp/replayxi-cycle136-turn-v3.xcresult. Full-suite/device validation follows integration.

Further persistence work should start with Release/device profiling: separate active-review
encoding from assembly, and measure playback during cold/warm saves. A background writer must
serialize Save/Rename/Delete/Flush as well as autosave; no detached autosave-only writes were added.
