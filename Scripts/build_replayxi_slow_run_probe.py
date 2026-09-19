#!/usr/bin/env python3
"""Build the source-verified slow-run TEST fixture; never modify app assets.

Requires numpy and OpenUSD (available in the installed Blender Python). Inputs
are the two pinned FBX files plus their Assimp 6.0 glTF2 exports. This script
does not download, convert, execute external code, or change the motion clock.

Example (export names: run.gltf/run.bin and slow.gltf/slow.bin):
  python3 -B Scripts/build_replayxi_slow_run_probe.py \
    --fast-dir /path/to/verified-fast --slow-dir /path/to/verified-slow \
    --output ReplayXITests/Fixtures/Generated/ReplayXIRocketboxSlowRun150.json

The production asset builder imports unrelated texture-authoring dependencies.
To avoid requiring Pillow for this motion-only probe, we compile only its exact
trusted sampling functions with AST; bodies are not copied or rewritten. The
original fast clip must reproduce byte-for-byte as decoded JSON before a slow
fixture is written. Original rest, idle, geometry and contact metadata remain
unchanged. Fast-specific procedural phase policies are NOT calibrated by this
fixture, even though both sources belong to the same upstream repo commit.
"""
from __future__ import annotations

import argparse
import ast
import copy
import hashlib
import json
import math
from pathlib import Path
import struct
import types

import numpy as np
from pxr import Gf


ROOT = Path(__file__).resolve().parent.parent
COMMIT = "0943055db6ec570bcef9f2c8b41c9e5467c808f9"
MOTION = ROOT / "ReplayXI/Resources/Players/ReplayXIRocketboxMotion.json"
MOTION_SHA256 = "d30a7379b81a4b0ea3fef5ebd20ad101911ab4fd521a5be1f6c00c0804f59ce4"
FIXTURE_SHA256 = "81633d787043a30cff0b86ef5272542522d619b7bc9186c7105d75a489bf3062"
SOURCES = {
    "fast": {
        "m_run_fast_01.max.fbx": (833040, "81d096f62465ae038149e7726485133264e4a47d105d236370b00dc18c650526"),
        "run.gltf": (None, "e2b8a1c822f65904ed6355c4e3a60a87ab7efe6f99ad66ec5756765e74ccdf17"),
        "run.bin": (None, "dd0aaa0e63a6c29ef4539d65f9bfbc701d27deb60bb0cd73fe85d8950d2869fc"),
    },
    "slow": {
        "m_run_slow_01.max.fbx": (877200, "56af7ac64b05653d40f64205b58b2bf915646ee70dd6e2a68bc4536d71f07c1c"),
        "slow.gltf": (None, "5315a48a05ec3fd344b7af5fb2669eb4e4060c3eeb609a0f90c0f8f523b9de49"),
        "slow.bin": (None, "c9bf8fc311a2205d37729350283cb9a52945435c6783825a345f1e2dab5a7700"),
    },
}


def verified_bytes(path: Path, expected_hash: str, size: int | None = None) -> bytes:
    data = path.read_bytes()
    if (size is not None and len(data) != size) or hashlib.sha256(data).hexdigest() != expected_hash:
        raise ValueError(f"Pinned input verification failed: {path}")
    return data


def trusted_sampler() -> types.SimpleNamespace:
    namespace = {"np": np, "Gf": Gf, "math": math, "struct": struct}
    for filename, selected in [
        ("build_replayxi_rocketbox_pilot.py", {"_accessor_layout", "read_accessor"}),
        ("build_replayxi_skinned_athlete.py", {
            "rounded", "local_matrix", "global_matrices", "metres", "usd_matrix",
            "decompose", "interpolate", "sample_clip",
        }),
    ]:
        path = ROOT / "Scripts" / filename
        tree = ast.parse(path.read_text(), filename=str(path))
        functions = [node for node in tree.body if isinstance(node, ast.FunctionDef) and node.name in selected]
        if len(functions) != len(selected) or {node.name for node in functions} != selected:
            raise ValueError(f"Trusted sampler contract changed: {filename}")
        module = ast.Module(body=[
            ast.ImportFrom(module="__future__", names=[ast.alias(name="annotations")], level=0),
            *functions,
        ], type_ignores=[])
        exec(compile(ast.fix_missing_locations(module), str(path), "exec"), namespace)
    return types.SimpleNamespace(**namespace)


def make_fixture(fast_dir: Path, slow_dir: Path, output: Path) -> dict:
    # Keep this diagnostic out of shipping resources, including via symlinks.
    output = output.resolve()
    if output.is_relative_to((ROOT / "ReplayXI").resolve()) or output.suffix != ".json":
        raise ValueError("Output must be a test-only JSON, outside ReplayXI app sources")
    sources = {}
    for group, directory in [("fast", fast_dir), ("slow", slow_dir)]:
        sources[group] = {
            name: verified_bytes(directory / name, digest, size)
            for name, (size, digest) in SOURCES[group].items()
        }
    current = json.loads(verified_bytes(MOTION, MOTION_SHA256))
    if current["sourceCommit"] != COMMIT or len(current["joints"]) != 80:
        raise ValueError("Current 80-joint source contract changed")
    fast = json.loads(sources["fast"]["run.gltf"])
    slow = json.loads(sources["slow"]["slow.gltf"])
    names = [node["name"] for node in fast["nodes"]]
    if len(names) != len(set(names)):
        raise ValueError("Ambiguous source joint names")
    order = [names.index(joint["sourceName"]) for joint in current["joints"]]
    contract = {"order": order, "nodeParents": {
        order[index]: None if joint["parentIndex"] < 0 else order[joint["parentIndex"]]
        for index, joint in enumerate(current["joints"])
    }}
    sampler = trusted_sampler()
    rebuilt_fast = sampler.sample_clip(fast, fast, sources["fast"]["run.bin"], contract, "run")
    actual_fast = next(clip for clip in current["clips"] if clip["id"] == "run")
    if rebuilt_fast != actual_fast or len(rebuilt_fast["frames"]) != 19:
        raise ValueError("Exact full fast-clip reconstruction failed; no fixture written")
    slow_clip = sampler.sample_clip(fast, slow, sources["slow"]["slow.bin"], contract, "run")
    if len(slow_clip["frames"]) != 24 or slow_clip["frames"][0]["time"] != 0:
        raise ValueError("Unexpected slow source sampling grid")
    candidate = copy.deepcopy(current)
    candidate["clips"] = [slow_clip if clip["id"] == "run" else clip for clip in current["clips"]]
    # Explicitly verify all non-run data, rather than relying on the assignment.
    candidate_control = copy.deepcopy(candidate)
    candidate_control["clips"] = [actual_fast if clip["id"] == "run" else clip for clip in candidate["clips"]]
    if candidate_control != current:
        raise ValueError("Probe modified data outside the run clip")
    payload = (json.dumps(candidate, separators=(",", ":"), allow_nan=False) + "\n").encode()
    digest = hashlib.sha256(payload).hexdigest()
    if digest != FIXTURE_SHA256:
        raise ValueError("Fixture differs from the independently measured source audit")
    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_bytes(payload)
    return {
        "output": str(output), "sha256": digest, "bytes": len(payload),
        "sourceCommit": COMMIT, "fastReproductionExact": True,
        "jointCount": len(candidate["joints"]), "runFrames": len(slow_clip["frames"]),
        "runDurationSeconds": slow_clip["durationSeconds"], "phaseOffsetDegrees": 0,
        "scope": "Test only; original rest/idle/geometry/contact metadata and track clock preserved",
    }


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--fast-dir", type=Path, required=True)
    parser.add_argument("--slow-dir", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    print(json.dumps(make_fixture(args.fast_dir, args.slow_dir, args.output), indent=2))


if __name__ == "__main__":
    main()
