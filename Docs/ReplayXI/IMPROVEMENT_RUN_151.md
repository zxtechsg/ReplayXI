# Run 151 — bounded slow-run integration plan

Status: planned; no production slow-run change yet. Run 150's native A/B is promising for two gently accelerating outfield players, not a global contact or speed-transition validation.

## Scope

- First candidate: native-recording outfield players with no recorded touch or impact anywhere in that scenario. Keep contact actors, keepers, impacts, stationary practice and overridden motion exactly on the existing path. No new UI setting.
- Add an optional compact slow clip bound to the verified base-motion hash and pinned source. Approximately 180 KB JSON / 92 KB raw decoded TRS before overhead, shared once. Do not duplicate idle/rest/skeleton or change the existing base asset/hash/contact profiles.
- Cold prewarm validates the entire optional package before publication. Missing or invalid optional data must leave the existing skinned fast package working, not force a procedural fallback.
- Preserve absolute gait phase, actor routes, ball recordings, head/POV controls and deterministic reverse seeks. Blend the whole body, not legs alone.

## Transition hypothesis — not yet approved for shipping

- Quintic speed rise 1.0–1.9 m/s, full weight 1.9–2.2, fall 2.2–2.9. Turn-rate fade 20–38°/s. Slow is zero before the existing fast-specific cut phase above 3 m/s.
- Permit three clip interpolations only where idle, fast and slow all contribute; otherwise one or two. One reusable output pose, no additional hierarchy passes or per-frame decode.
- A strict two-clip limit would force a narrow onset near the existing full-run threshold (~1.95 m/s). Reject that shortcut: same-phase knee differences reach 49.9°. A 0.087 m/s fade crossed at 2 m/s² lasts ~43 ms; the broader ramps last 350–450 ms. These accelerations are illustrative, not measured match data.
- Current A/B covers only about +0.046 to +0.125 m/s² and no complete onset/exit. Directional suitability and real rise/fall/turn boundaries still need evidence. The gates above are hypotheses to test, not proof of smoothness.

## Required evidence

1. Decoder/hash/layout failures, optional-load fallback and atomic publication.
2. Exact old poses and no added slow sampling for excluded actors and zero-weight endpoints.
3. All five actual demos, both teams and LODs: gate entry/exit, deceleration, turns, exact rewind and unchanged ball/contact data.
4. Native moving comparisons; bone/floor bounds and normalized per-joint step measurements. Do not convert low boot height into an asserted ground contact.
5. Measured clip-sample counts and factory CPU cost; no simulator result presented as headset FPS.

Reference evidence and known limits: `IMPROVEMENT_RUN_150.md`. The intermittent native cleanup crash remains separate and unresolved until directly evidenced.
