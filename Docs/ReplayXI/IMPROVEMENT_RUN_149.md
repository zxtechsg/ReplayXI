# Run 149 — native cleanup provenance and off-ball support

Status: diagnostics in progress. No production animation or physics change.

Run 148 shipped the optional local Full squad detail setting in `dd04e95`, with focused checks and Release build passing, but retained two full-suite RealityKit cleanup crashes. Six-method mixed cohorts, three repeats each, passed on both installed runtimes (26.5 and 27). That does not distinguish the cause.

## First-warning diagnostic

- Same prebuilt 148 binary, same six-method cohort, ten repeats. Result/log: `/private/tmp/replayxi-cycle149-weak-provenance.{xcresult,log}`.
- Root verified exact PID 77496 and its executable under the selected visionOS 27 simulator's app container before attaching LLDB. `objc_weak_error` resolved to one libobjc breakpoint.
- Capture the first breakpoint/stop with all-thread backtraces and registers, then detach/resume. No memory edits, security changes or guessed object addresses. Log: `/private/tmp/replayxi-cycle149-first-weak-lldb.log`.
- LLDB reports reading libobjc from process memory rather than the host shared cache. Debugger runs are not timing benchmarks. Any absence of app frames during queued teardown must remain an unresolved provenance limit.
- Production primary/aim worlds already detach while owned. Successful capture helpers await GPU completion. Inconsistent older test cleanup exists, but neither that nor the capture currently starting explains both warnings. Do not label a renderer's origin from the later crash stack.

## Independent motion diagnostic

An agent is preparing a test-only off-ball foot-support probe for rebound Argentina 13/19 and an away-team control. Use fixed native boot surface points, independently derived source support phases, actual near/low scene admission and exact reverse sampling. Low foot height alone is not proof of a planted foot; toe flex and legitimate swing motion are not automatically sliding. No rig correction is approved from unverified numbers.
