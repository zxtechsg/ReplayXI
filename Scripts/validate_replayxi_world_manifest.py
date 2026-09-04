#!/usr/bin/env python3
"""Validate a rights-safe Replay XI reconstructed-world handoff.

The app never treats a generated video stream as tactical ground truth. This
manifest keeps the original/cleared source, navigable-video generation and 3D
reconstruction artifacts distinct, hash locked and auditable before anything
is admitted to the Xcode bundle.
"""

from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path, PurePosixPath
import re
import sys
from typing import Any


SCHEMA_VERSION = 1
WORLD_ID = re.compile(r"^[a-z0-9]+(?:-[a-z0-9]+)*$")
SHA256 = re.compile(r"^[0-9a-f]{64}$")
ALLOWED_SOURCE_KINDS = {
    "original-synthetic",
    "club-owned-capture",
    "licensed-capture",
    "open-data-reconstruction",
}
ALLOWED_ARTIFACT_ROLES = {
    "source-video",
    "reference-image",
    "navigable-video",
    "reconstruction-point-cloud",
    "gaussian-splat",
    "tracking-data",
}
REQUIRED_ARTIFACT_ROLES = {"source-video", "reconstruction-point-cloud"}
FORBIDDEN_REMOTE_HOSTS = {
    "youtube.com",
    "www.youtube.com",
    "youtu.be",
}


class ManifestError(ValueError):
    pass


def _require_mapping(value: Any, field: str) -> dict[str, Any]:
    if not isinstance(value, dict):
        raise ManifestError(f"{field} must be an object")
    return value


def _require_text(value: Any, field: str, maximum: int = 2_000) -> str:
    if not isinstance(value, str) or not value.strip():
        raise ManifestError(f"{field} must be non-empty text")
    if len(value) > maximum:
        raise ManifestError(f"{field} exceeds {maximum} characters")
    return value.strip()


def _local_artifact_path(manifest_dir: Path, raw_path: Any, field: str) -> Path:
    text = _require_text(raw_path, field, maximum=512)
    logical = PurePosixPath(text)
    if logical.is_absolute() or ".." in logical.parts or "\\" in text:
        raise ManifestError(f"{field} must be a safe relative POSIX path")
    candidate = manifest_dir.joinpath(*logical.parts)
    if candidate.is_symlink():
        raise ManifestError(f"{field} must not be a symlink")
    try:
        candidate.resolve().relative_to(manifest_dir.resolve())
    except ValueError as error:
        raise ManifestError(f"{field} escapes the manifest directory") from error
    return candidate


def _sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def validate_manifest(path: Path, *, verify_files: bool = True) -> dict[str, Any]:
    if not path.is_file() or path.is_symlink():
        raise ManifestError(f"manifest is not a regular file: {path}")
    try:
        payload = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, UnicodeError, json.JSONDecodeError) as error:
        raise ManifestError(f"manifest is not valid UTF-8 JSON: {error}") from error
    root = _require_mapping(payload, "manifest")

    if root.get("schemaVersion") != SCHEMA_VERSION:
        raise ManifestError(f"schemaVersion must be {SCHEMA_VERSION}")
    world_id = _require_text(root.get("worldID"), "worldID", maximum=80)
    if not WORLD_ID.fullmatch(world_id):
        raise ManifestError("worldID must be a lowercase kebab-case identifier")
    _require_text(root.get("displayName"), "displayName", maximum=120)

    source = _require_mapping(root.get("source"), "source")
    source_kind = _require_text(source.get("kind"), "source.kind", maximum=40)
    if source_kind not in ALLOWED_SOURCE_KINDS:
        raise ManifestError(f"source.kind is not admitted: {source_kind}")
    _require_text(source.get("owner"), "source.owner", maximum=160)
    _require_text(source.get("rightsBasis"), "source.rightsBasis", maximum=500)
    _require_text(source.get("promptOrCaptureNote"), "source.promptOrCaptureNote")
    if source.get("containsRealPlayerLikenesses") is not False:
        raise ManifestError("prototype worlds must declare containsRealPlayerLikenesses=false")
    remote_url = source.get("remoteURL")
    if remote_url is not None:
        url = _require_text(remote_url, "source.remoteURL", maximum=1_000).lower()
        if any(f"//{host}" in url for host in FORBIDDEN_REMOTE_HOSTS):
            raise ManifestError("YouTube/broadcast URLs are not admitted as reconstruction inputs")

    coordinates = _require_mapping(root.get("coordinates"), "coordinates")
    if coordinates.get("upAxis") != "Y" or coordinates.get("metresPerUnit") != 1:
        raise ManifestError("coordinates must be Y-up with metresPerUnit=1")
    if coordinates.get("pitchLengthMetres") != 105 or coordinates.get("pitchWidthMetres") != 68:
        raise ManifestError("coordinates must use the canonical 105 x 68 metre pitch")

    truth = _require_mapping(root.get("tacticalTruth"), "tacticalTruth")
    if truth.get("generatedPixelsAreAuthoritative") is not False:
        raise ManifestError("generatedPixelsAreAuthoritative must be false")
    _require_text(truth.get("trackingAuthority"), "tacticalTruth.trackingAuthority", maximum=160)

    stages = root.get("pipeline")
    if not isinstance(stages, list) or not stages:
        raise ManifestError("pipeline must be a non-empty array")
    stage_names: list[str] = []
    for index, raw_stage in enumerate(stages):
        stage = _require_mapping(raw_stage, f"pipeline[{index}]")
        name = _require_text(stage.get("name"), f"pipeline[{index}].name", maximum=80)
        provider = _require_text(
            stage.get("provider"), f"pipeline[{index}].provider", maximum=160
        )
        _require_text(stage.get("modelOrVersion"), f"pipeline[{index}].modelOrVersion", 160)
        if name in stage_names:
            raise ManifestError(f"duplicate pipeline stage: {name}")
        stage_names.append(name)
        if name == "reconstruct-3d" and "lingbot-map" not in provider.lower():
            raise ManifestError("reconstruct-3d must identify LingBot-Map as the provider")
    if "generate-video" not in stage_names or "reconstruct-3d" not in stage_names:
        raise ManifestError("pipeline requires generate-video and reconstruct-3d stages")

    artifacts = root.get("artifacts")
    if not isinstance(artifacts, list) or not artifacts:
        raise ManifestError("artifacts must be a non-empty array")
    roles: set[str] = set()
    verified_artifacts: list[dict[str, Any]] = []
    for index, raw_artifact in enumerate(artifacts):
        artifact = _require_mapping(raw_artifact, f"artifacts[{index}]")
        role = _require_text(artifact.get("role"), f"artifacts[{index}].role", maximum=64)
        if role not in ALLOWED_ARTIFACT_ROLES:
            raise ManifestError(f"unsupported artifact role: {role}")
        if role in roles:
            raise ManifestError(f"duplicate artifact role: {role}")
        roles.add(role)
        local_path = _local_artifact_path(
            path.parent, artifact.get("path"), f"artifacts[{index}].path"
        )
        expected_hash = _require_text(
            artifact.get("sha256"), f"artifacts[{index}].sha256", maximum=64
        ).lower()
        if not SHA256.fullmatch(expected_hash):
            raise ManifestError(f"artifacts[{index}].sha256 must be lowercase SHA-256")
        if verify_files:
            if not local_path.is_file() or local_path.is_symlink():
                raise ManifestError(f"artifact is not a regular file: {local_path}")
            actual_hash = _sha256(local_path)
            if actual_hash != expected_hash:
                raise ManifestError(
                    f"artifact hash mismatch for {role}: expected {expected_hash}, got {actual_hash}"
                )
        verified_artifacts.append(
            {"role": role, "path": str(local_path.resolve()), "sha256": expected_hash}
        )

    missing_roles = REQUIRED_ARTIFACT_ROLES - roles
    if missing_roles:
        raise ManifestError(f"missing required artifact roles: {sorted(missing_roles)}")

    return {
        "passed": True,
        "schemaVersion": SCHEMA_VERSION,
        "worldID": world_id,
        "sourceKind": source_kind,
        "pipelineStages": stage_names,
        "artifacts": verified_artifacts,
    }


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("manifest", type=Path)
    parser.add_argument(
        "--schema-only",
        action="store_true",
        help="validate structure and paths without requiring artifact files",
    )
    arguments = parser.parse_args()
    try:
        report = validate_manifest(
            arguments.manifest.resolve(), verify_files=not arguments.schema_only
        )
    except ManifestError as error:
        print(json.dumps({"passed": False, "error": str(error)}, indent=2))
        return 1
    print(json.dumps(report, indent=2, sort_keys=True))
    return 0


if __name__ == "__main__":
    sys.exit(main())
