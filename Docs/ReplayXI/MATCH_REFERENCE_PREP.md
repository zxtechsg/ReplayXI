# Local match-reference prep

This prepares video evidence for the Blender match scene workflow. It does **not**
reconstruct 3D players, identify players, estimate gaze, or generate a Gaussian
splat. Video frames and authored/inferred world tracks stay separate.

## Prepare the chosen minute

Requires existing `ffmpeg`, `ffprobe`, and Python 3.9+. No extra Python packages.
Use a local clip you are authorised to process. The tool does not download URLs,
choose a segment, upload media, or independently verify rights.

Keep both the source and output outside the repository and app bundle. The output
parent must exist; the output directory must not exist. Example paths below are
placeholders; substitute the actual user-selected file and start time.

```sh
python3 Scripts/prepare_replayxi_match_reference.py \
  --source '/absolute/external-media/match.mp4' \
  --start 120 --duration 60 --fps 2 \
  --output '/absolute/external-media/prepared-match-minute' \
  --source-kind user-supplied-reference \
  --provenance 'Describe the actual source and permission here.'
```

`--start` is the **video playhead** time in seconds, not the scoreboard clock.
`--duration` is explicit, greater than zero and at most 60 seconds. The Blender
minute-demo contract uses exactly 60. The tool refuses a segment extending beyond
the video instead of shortening it silently. Default sampling is 2 FPS, up to
1280 px wide. `--fps` accepts 0.1–30 and `--width` accepts even values 320–1920.
Sampling keeps decoded source frames; it does not invent intermediate frames or
force constant-rate duplicates. Actual selected times are authoritative.

Outputs:

- `reference.json`: source hash, byte count, permission note, tool versions,
  timestamps, frame hashes, contact-sheet hashes, and unverified cut candidates.
- `frames/frame-000001.jpg`, etc.: clean, sampled source images.
- `contact-sheet.html`: local, responsive frame grid with source/replay timestamps.
  Click a frame to inspect its full-sized image. No remote scripts or resources.
- `contact-001.jpg`, etc.: compact 5 × 4 overviews. Row-order frame IDs are listed
  in `reference.json`; use HTML for printed timestamps.
- `timestamps.csv`: exact mapping and frame hashes for annotation tools.
- `replay-tracks.template.json`: separate, **empty** player/ball tracking input for
  `Scripts/blender/build_match_replay.py`. The reference manifest is hash-bound.

The source is never copied or edited. Its SHA-256 is checked before and after prep;
a changed source aborts publication. Existing outputs are never overwritten.
`reference.json` is published last. A directory without it is incomplete and must
not be used. Keep this evidence manifest unchanged; edit a copy of the tracks
template, not the source evidence. Hashes detect changes; they do not prove who
captured the clip or whether its content is accurate.

## Time and evidence contract

The source manifest schema is `replayxi-match-reference-v1`, `schemaVersion: 1`.

```text
sourceSeconds       = timeline.sourceStartSeconds + replaySeconds
containerPTSSeconds = sourceSeconds + source.containerStartSeconds
```

The requested interval is end-exclusive. `normalizedPTS × timeBase` gives each
frame's `sourceSeconds`. FFmpeg preserves decoded timestamps while subtracting
the container origin; seeking between frames can leave the first sample slightly
after replay time zero. Variable frame-rate clips are not mapped using frame
index ÷ FPS. Match-clock mapping stays `null` until someone explicitly records it.

Each source-frame evidence entry says `origin: source-frame`, `confidence: 1`,
`sourceVisibility: frame-only`, `measured3D: false`. That confidence means the
image's direct source/timestamp association—not a player's position, identity,
visibility, or a camera calibration.

The separate replay input starts with `players: []`, `ball.keyframes: []`, and
`trackEvidence.origin: untracked`. An empty template is not a completed match.
For each subsequently authored player/ball keyframe, the Blender assembler expects:

```json
{
  "time": 2.5,
  "position": {"x": 12.0, "z": -8.0},
  "evidence": {
    "origin": "manual",
    "confidence": 0.6,
    "sourceVisibility": "visible",
    "sourceFrameID": "frame-000006"
  }
}
```

The sample numbers illustrate the format only; they are not match data.
Coordinates use pitch-centred metres: x = width, z = length; Blender maps these to
X/Y with height on Z. Origin must be `manual`, `inferred`, or `measured`;
visibility must be `visible`, `occluded`, `off-camera`, or `unknown`; confidence
must be 0–1. Do not label hand-authored/inferred trajectories as measured.
Record player identities, jersey numbers, heading, passes and visibility only
when evidence supports them. Occluded players must not silently become visible.

## Camera-cut review

FFmpeg compares successive frames at 320 px width and records scene-score
candidates above `--cut-threshold` (default 0.35). These are **not verified cuts**.
Flashes, graphics and replays can trigger detections; subtle cuts can be missed.
Review the source and contact grid before reconstructing a continuous shot. Do not
interpolate a broadcast pan/cut into player movement or infer geometry continuity.
The scene score is not a probability; candidate confidence is deliberately `null`.

Implementation references: [FFmpeg timestamp/seek options](https://ffmpeg.org/ffmpeg.html),
[select filter](https://ffmpeg.org/ffmpeg-filters.html#select_002c-aselect),
[showinfo timestamps](https://ffmpeg.org/ffmpeg-filters.html#showinfo).

## Tests

```sh
python3 -m unittest Scripts.tests.test_replayxi_match_reference -v
```

Pure checks cover limits, paths, timestamps, no-overwrite policy and honest cut
labels. With FFmpeg available, synthetic-media integration checks exercise the
full minute, fractional seeks, non-zero container start, a known hard cut,
contact sheets, manifest hashes, empty tracks and source-change abort. Test media
is temporary and is not representative football reconstruction quality.
