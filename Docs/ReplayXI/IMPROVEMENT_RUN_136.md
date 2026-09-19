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
write; state adoption follows successful writes. Optimization and turn correction are in progress.

## Stationary-turn baseline

Underlap keeper liv-25, 3.30–3.80s: 52.015° heading change with near-zero root travel and constant
distance-based gait phase. Both grounded soles slide about 19.2 cm. Native near/low captures and
120 Hz sole measurements reproduce the defect; no trajectory or motion-capture claim is made.

Evidence: /private/tmp/replayxi-cycle136-baseline-v2.xcresult and
/private/tmp/replayxi-cycle136-timing.xcresult. Full-suite/device validation follows integration.
