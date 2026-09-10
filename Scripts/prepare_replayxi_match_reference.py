#!/usr/bin/env python3
"""Prepare local video evidence, never generated/measured world tracks.

Requires ffmpeg/ffprobe on PATH. Source and output must remain outside this
repository. No network access, media download, package install, or source edit.
"""
from __future__ import annotations

import argparse
import csv
from datetime import datetime, timezone
from fractions import Fraction
import hashlib
import html
import json
import math
from pathlib import Path
import re
import shutil
import subprocess
import sys
import tempfile
from typing import Any


PROJECT_ROOT = Path(__file__).resolve().parents[1]
SCHEMA = "replayxi-match-reference-v1"
VIDEO_SUFFIXES = {".mp4", ".mov", ".m4v", ".mkv", ".webm", ".avi", ".mts", ".m2ts"}
MAX_FRAMES = 1_800


class ReferenceError(ValueError):
    pass


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def finite(value: Any, field: str) -> float:
    try:
        result = float(value)
    except (TypeError, ValueError) as error:
        raise ReferenceError(f"{field} must be a finite number") from error
    if isinstance(value, bool) or not math.isfinite(result):
        raise ReferenceError(f"{field} must be a finite number")
    return result


def inside(path: Path, root: Path) -> bool:
    try:
        path.resolve().relative_to(root.resolve())
        return True
    except ValueError:
        return False


def validate_options(source: Path, output: Path, start: float, duration: float,
                     fps: float, width: int, cut_threshold: float) -> None:
    for value, name in ((start, "start"), (duration, "duration"), (fps, "fps"),
                        (cut_threshold, "cut threshold")):
        finite(value, name)
    if start < 0 or not 0 < duration <= 60:
        raise ReferenceError("start must be ≥0 and duration must be >0 and ≤60 seconds")
    if not 0.1 <= fps <= 30 or math.ceil(duration * fps) > MAX_FRAMES:
        raise ReferenceError("fps must be 0.1…30, with at most 1800 sampled frames")
    if not 320 <= width <= 1920 or width % 2:
        raise ReferenceError("width must be an even integer from 320 to 1920")
    if not 0 < cut_threshold < 1:
        raise ReferenceError("cut threshold must be between 0 and 1")
    if not source.is_file() or source.suffix.lower() not in VIDEO_SUFFIXES:
        raise ReferenceError("source must be a local video file, not a URL or playlist")
    if inside(source, PROJECT_ROOT) or inside(output, PROJECT_ROOT):
        raise ReferenceError("source and output must be outside the Git repository/app bundle")
    if output.exists() or output.is_symlink():
        raise ReferenceError("output already exists; choose a new directory (nothing is overwritten)")
    if not output.parent.is_dir():
        raise ReferenceError("output parent must already exist")


def run(command: list[str], timeout: float = 600) -> subprocess.CompletedProcess[str]:
    try:
        result = subprocess.run(command, capture_output=True, text=True,
                                timeout=timeout, check=False)
    except (OSError, subprocess.TimeoutExpired) as error:
        raise ReferenceError(f"Unable to run {Path(command[0]).name}: {error}") from error
    if result.returncode:
        raise ReferenceError(f"{Path(command[0]).name} failed: {result.stderr[-3000:]}")
    return result


def probe_video(source: Path, ffprobe: str) -> dict[str, Any]:
    raw = run([ffprobe, "-v", "error", "-protocol_whitelist", "file,pipe",
               "-select_streams", "v:0", "-show_streams", "-show_format",
               "-of", "json", str(source)], timeout=60)
    try:
        data = json.loads(raw.stdout)
        stream = data["streams"][0]
        container = data["format"]
        if stream.get("disposition", {}).get("attached_pic"):
            raise ReferenceError("first video stream is cover art, not match video")
        duration = finite(container.get("duration", stream.get("duration")), "video duration")
        origin = finite(container.get("start_time", 0), "container start time")
        video_start = finite(stream.get("start_time", origin), "video start time") - origin
        video_duration = stream.get("duration")
        video_end = min(duration, video_start + finite(video_duration, "stream duration")) \
            if video_duration is not None else duration
        width, height = int(stream["width"]), int(stream["height"])
        if duration <= 0 or width <= 0 or height <= 0:
            raise ReferenceError("video duration/dimensions must be positive")
        return {"durationSeconds": duration, "containerStartSeconds": origin,
                "videoStartSeconds": video_start, "videoEndSeconds": video_end,
                "width": width, "height": height, "streamIndex": stream["index"],
                "codec": stream.get("codec_name"), "timeBase": stream.get("time_base"),
                "averageFrameRate": stream.get("avg_frame_rate"),
                "nominalFrameRate": stream.get("r_frame_rate"),
                "rotation": [item for item in stream.get("side_data_list", [])
                             if "rotation" in item]}
    except (KeyError, IndexError, TypeError, json.JSONDecodeError) as error:
        raise ReferenceError("ffprobe did not return a usable video stream") from error


def parse_frame_times(log: str, start: float, duration: float) -> list[dict[str, Any]]:
    time_base_match = re.search(r"config in time_base:\s*(\d+/\d+)", log)
    if not time_base_match:
        raise ReferenceError("ffmpeg supplied no frame time base")
    time_base = Fraction(time_base_match.group(1))
    result = []
    for match in re.finditer(r"\bn:\s*(\d+)\s+pts:\s*(-?\d+)\s+pts_time:", log):
        index, pts = int(match.group(1)), int(match.group(2))
        source_time = float(pts * time_base)
        replay_time = source_time - start
        if index != len(result) or replay_time < -1e-6 or replay_time >= duration + 1e-6:
            raise ReferenceError("sampled frame order/timestamp lies outside requested window")
        if result and source_time <= result[-1]["sourceSeconds"]:
            raise ReferenceError("sampled timestamps must strictly increase")
        result.append({"id": f"frame-{index + 1:06d}",
                       "path": f"frames/frame-{index + 1:06d}.jpg",
                       "sourceSeconds": source_time, "replaySeconds": max(0.0, replay_time),
                       "normalizedPTS": pts, "timeBase": str(time_base),
                       "evidence": {"origin": "source-frame", "confidence": 1.0,
                                    "sourceVisibility": "frame-only", "measured3D": False}})
    if not result or len(result) > MAX_FRAMES:
        raise ReferenceError("requested window produced no frames or exceeded frame limit")
    return result


def parse_cut_candidates(log: str, start: float, duration: float,
                         threshold: float = 0.35) -> list[dict[str, Any]]:
    result = []
    timestamp = None
    for line in log.splitlines():
        if "Parsed_metadata_" not in line:
            continue
        match = re.search(r"pts_time:([-+\d.eE]+)", line)
        if match:
            timestamp = finite(match.group(1), "cut timestamp")
        score = re.search(r"lavfi.scene_score=([-+\d.eE]+)", line)
        if (score and timestamp is not None and start <= timestamp < start + duration
                and finite(score.group(1), "scene score") > threshold):
            result.append({"sourceSeconds": timestamp, "replaySeconds": timestamp - start,
                           "sceneScore": finite(score.group(1), "scene score"),
                           "classification": "unverified-cut-candidate",
                           "confidence": None, "requiresHumanReview": True})
            timestamp = None
    return result


def extraction_command(ffmpeg: str, source: Path, directory: Path, start: float,
                       duration: float, fps: float, width: int,
                       cut_threshold: float) -> list[str]:
    # Keep PTS, offset container origin to zero, then trim in source-playhead
    # seconds. select retains real decoded frames (unlike fps, no duplication).
    filters = (
        f"[0:v:0]trim=start={start:.9f}:end={start + duration:.9f},split[s][c];"
        f"[s]select='isnan(prev_selected_t)+gte(t-prev_selected_t,{1 / fps - 1e-9:.9f})',"
        f"scale=w='min(iw,{width})':h=-2,showinfo[frames];"
        # Emit the first frame as a seed so FFmpeg's null-output encoder can
        # initialise even when there are no cuts. Its zero score is discarded.
        f"[c]scale=320:-2,select='gt(scene,{cut_threshold:.6f})+eq(n,0)',"
        "metadata=mode=print[cuts]"
    )
    return [ffmpeg, "-hide_banner", "-nostdin", "-nostats", "-n",
            "-protocol_whitelist", "file,pipe", "-copyts", "-start_at_zero",
            "-ss", f"{start:.9f}", "-t", f"{duration:.9f}", "-i", str(source),
            "-filter_complex_threads", "1",
            "-filter_complex", filters, "-map", "[frames]", "-an", "-sn", "-dn",
            "-fps_mode", "passthrough", "-q:v", "2", "-threads", "1",
            str(directory / "frames/frame-%06d.jpg"),
            "-map", "[cuts]", "-an", "-fps_mode", "passthrough", "-f", "null", "-"]


def write_json(path: Path, data: dict[str, Any]) -> None:
    path.write_text(json.dumps(data, indent=2, ensure_ascii=False, allow_nan=False) + "\n")


def make_contact_sheets(ffmpeg: str, directory: Path,
                        frames: list[dict[str, Any]]) -> list[dict[str, Any]]:
    sheets = []
    for offset in range(0, len(frames), 20):
        selected = frames[offset:offset + 20]
        relative = f"contact-{offset // 20 + 1:03d}.jpg"
        run([ffmpeg, "-hide_banner", "-loglevel", "error", "-nostdin", "-n",
             "-protocol_whitelist", "file,pipe", "-start_number", str(offset + 1),
             "-i", str(directory / "frames/frame-%06d.jpg"), "-vf",
             "scale=240:140:force_original_aspect_ratio=decrease,"
             "pad=240:140:(ow-iw)/2:(oh-ih)/2,"
             f"tile=5x4:nb_frames={len(selected)}:padding=4:margin=4",
             "-frames:v", "1", "-threads", "1", "-q:v", "3", str(directory / relative)])
        sheets.append({"path": relative, "sha256": sha256(directory / relative),
                       "frameIDsInRowOrder": [item["id"] for item in selected]})
    return sheets


def write_contact_html(directory: Path, frames: list[dict[str, Any]], label: str) -> None:
    cards = "\n".join(
        f'<figure><a href="{frame["path"]}"><img loading="lazy" src="{frame["path"]}" '
        f'alt="{frame["id"]}"></a><figcaption>{frame["id"]}<br>'
        f'Replay {frame["replaySeconds"]:.3f}s · Source {frame["sourceSeconds"]:.3f}s'
        '</figcaption></figure>' for frame in frames)
    (directory / "contact-sheet.html").write_text(
        '<!doctype html><html lang="en"><meta charset="utf-8">'
        '<meta name="viewport" content="width=device-width,initial-scale=1">'
        '<title>Replay XI source frames</title><style>body{font:16px system-ui;'
        'background:#101820;color:#eee;margin:24px}main{display:grid;'
        'grid-template-columns:repeat(auto-fit,minmax(260px,1fr));gap:16px}'
        'figure{margin:0}img{width:100%;height:auto}figcaption{padding:8px 0}</style>'
        f'<h1>{html.escape(label)}</h1><p>Source-frame evidence only. No 3D tracks inferred. '
        'Times are video-playhead seconds, not the broadcast match clock.</p>'
        f'<main>{cards}</main></html>')


def prepare(source: Path, output: Path, *, start: float, duration: float, fps: float = 2,
            width: int = 1280, cut_threshold: float = 0.35, provenance: str,
            source_kind: str = "user-supplied-reference", ffmpeg: str = "ffmpeg",
            ffprobe: str = "ffprobe") -> Path:
    source, output = source.expanduser().resolve(), output.expanduser().absolute()
    validate_options(source, output, start, duration, fps, width, cut_threshold)
    if not provenance.strip() or len(provenance) > 4000:
        raise ReferenceError("provenance must describe the source/permission in 1…4000 characters")
    original_hash = sha256(source)
    info = probe_video(source, ffprobe)
    if start + duration > info["videoEndSeconds"] + 1e-6:
        raise ReferenceError("requested end exceeds video duration; shorten explicitly (no silent trim)")
    with tempfile.TemporaryDirectory(prefix=".replayxi-reference-", dir=output.parent) as temporary:
        staging = Path(temporary) / "package"
        (staging / "frames").mkdir(parents=True)
        log = run(extraction_command(ffmpeg, source, staging, start, duration,
                                     fps, width, cut_threshold)).stderr
        frames = parse_frame_times(log, start, duration)
        if len(list((staging / "frames").glob("*.jpg"))) != len(frames):
            raise ReferenceError("decoded timestamp/frame count mismatch")
        for frame in frames:
            frame["sha256"] = sha256(staging / frame["path"])
            frame["containerPTSSeconds"] = frame["sourceSeconds"] + info["containerStartSeconds"]
        sheets = make_contact_sheets(ffmpeg, staging, frames)
        write_contact_html(staging, frames, source.name)
        with (staging / "timestamps.csv").open("w", newline="") as handle:
            fields = ["id", "path", "replaySeconds", "sourceSeconds", "containerPTSSeconds",
                      "normalizedPTS", "timeBase", "sha256"]
            writer = csv.DictWriter(handle, fieldnames=fields, extrasaction="ignore")
            writer.writeheader()
            writer.writerows(frames)
        if sha256(source) != original_hash:
            raise ReferenceError("source changed during extraction; output discarded")
        manifest = {
            "schema": SCHEMA, "schemaVersion": 1,
            "createdAt": datetime.now(timezone.utc).isoformat(),
            "source": {"path": str(source), "sha256": original_hash,
                       "byteCount": source.stat().st_size, "kind": source_kind,
                       "provenance": provenance, "rightsIndependentlyVerified": False,
                       "copiedToOutput": False, **info},
            "timeline": {"sourceStartSeconds": start, "durationSeconds": duration,
                         "requestedSampleFPS": fps, "sampling": "real-decoded-frame-selection",
                         "sourceSecondsEquals": "sourceStartSeconds + replaySeconds",
                         "containerPTSSecondsEquals": "sourceSeconds + containerStartSeconds",
                         "matchClockMapping": None, "endExclusive": True},
            "frames": frames, "contactSheets": sheets,
            "cameraCuts": {"method": "ffmpeg-select-scene-at-320px-width",
                           "threshold": cut_threshold, "verified": False,
                           "warning": "Candidates only; flashes, replays and graphics can trigger; cuts can be missed.",
                           "candidates": parse_cut_candidates(log, start, duration, cut_threshold)},
            "tacticalTruth": {"sourcePixelsAre3DMeasurements": False,
                              "playerWorldTracks": "not-produced", "ballWorldTrack": "not-produced",
                              "visibilityMeaning": "Frames exist; individual player visibility is unlabelled."},
            "tools": {"ffmpeg": run([ffmpeg, "-version"]).stdout.splitlines()[0],
                      "ffprobe": run([ffprobe, "-version"]).stdout.splitlines()[0],
                      "scriptSHA256": sha256(Path(__file__))},
            "assets": [{"path": name, "sha256": sha256(staging / name)}
                       for name in ("timestamps.csv", "contact-sheet.html")],
        }
        write_json(staging / "reference.json", manifest)
        write_json(staging / "replay-tracks.template.json", {
            "schemaVersion": 1, "id": "match-reference", "duration": duration,
            "source": {"status": "reference-available", "videoPath": str(source),
                       "provenance": source_kind, "referenceManifestPath": "reference.json",
                       "referenceManifestSHA256": sha256(staging / "reference.json")},
            "coordinateSystem": "pitch-metres-x-width-z-length", "players": [],
            "ball": {"keyframes": []}, "annotations": [],
            "trackEvidence": {"origin": "untracked", "confidence": None,
                              "sourceVisibility": "unknown", "measured3D": False},
        })
        # Refuse existing destinations even if one appeared during extraction.
        # mkdir reserves the final directory without replacing other work.
        output.mkdir()
        for asset in staging.iterdir():
            if asset.name != "reference.json":
                shutil.move(str(asset), str(output / asset.name))
        # The complete reference manifest is the last file published. An I/O
        # failure before this leaves an obvious incomplete directory, not a
        # seemingly valid package with missing assets.
        shutil.move(str(staging / "reference.json"), str(output / "reference.json"))
    return output / "reference.json"


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--source", required=True, type=Path)
    parser.add_argument("--output", required=True, type=Path)
    parser.add_argument("--start", required=True, type=float, help="source playhead seconds")
    parser.add_argument("--duration", required=True, type=float, help="seconds, at most 60")
    parser.add_argument("--fps", type=float, default=2, help="maximum sampled frame rate (default 2)")
    parser.add_argument("--width", type=int, default=1280)
    parser.add_argument("--cut-threshold", type=float, default=0.35)
    parser.add_argument("--provenance", required=True, help="source ownership/permission note, recorded verbatim")
    parser.add_argument("--source-kind", default="user-supplied-reference",
                        choices=["user-supplied-reference", "club-owned-capture", "licensed-capture",
                                 "original-synthetic"])
    args = parser.parse_args(argv)
    try:
        result = prepare(**vars(args))
    except (ReferenceError, OSError) as error:
        print(f"Reference preparation failed: {error}", file=sys.stderr)
        return 1
    print(f"Prepared source evidence: {result}")
    print("No 3D tracks produced. Review cut candidates and fill explicit track evidence separately.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
