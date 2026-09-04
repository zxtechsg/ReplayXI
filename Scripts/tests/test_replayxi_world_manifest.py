import hashlib
import json
import os
import struct
import subprocess
import sys
import tempfile
import unittest
import zipfile
import zlib
from pathlib import Path


PROJECT_ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(PROJECT_ROOT / "Scripts"))

from validate_replayxi_world_manifest import ManifestError, validate_manifest  # noqa: E402


LINGBOT_MAP_AUDITED_REVISION = "bfcd0f20383d3a35cc9757a36ab1d5b6e5064df4"


def digest(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def iso_box(kind: bytes, payload: bytes = b"") -> bytes:
    return struct.pack(">I4s", 8 + len(payload), kind) + payload


def minimal_iso_bmff(major_brand: bytes) -> bytes:
    return b"".join(
        (
            iso_box(b"ftyp", major_brand + b"\x00\x00\x02\x00" + major_brand),
            iso_box(b"moov"),
            iso_box(b"mdat", b"\x00\x00\x00\x00"),
        )
    )


def png_chunk(kind: bytes, payload: bytes) -> bytes:
    checksum = zlib.crc32(kind + payload) & 0xFFFF_FFFF
    return struct.pack(">I", len(payload)) + kind + payload + struct.pack(">I", checksum)


def minimal_png() -> bytes:
    header = struct.pack(">IIBBBBB", 1, 1, 8, 2, 0, 0, 0)
    pixels = zlib.compress(b"\x00\x00\x00\x00")
    return b"\x89PNG\r\n\x1a\n" + png_chunk(b"IHDR", header) + png_chunk(
        b"IDAT", pixels
    ) + png_chunk(b"IEND", b"")


def minimal_ply() -> bytes:
    return (
        b"ply\n"
        b"format ascii 1.0\n"
        b"element vertex 1\n"
        b"property float x\n"
        b"property float y\n"
        b"property float z\n"
        b"end_header\n"
        b"0 0 0\n"
    )


def minimal_gaussian_ply() -> bytes:
    properties = (
        "x",
        "y",
        "z",
        "f_dc_0",
        "f_dc_1",
        "f_dc_2",
        "opacity",
        "scale_0",
        "scale_1",
        "scale_2",
        "rot_0",
        "rot_1",
        "rot_2",
        "rot_3",
    )
    header = ["ply", "format ascii 1.0", "element vertex 1"]
    header.extend(f"property float {name}" for name in properties)
    header.append("end_header")
    values = (0, 0, 0, 0.5, 0.5, 0.5, 1, 0, 0, 0, 1, 0, 0, 0)
    return ("\n".join(header) + "\n" + " ".join(map(str, values)) + "\n").encode()


def minimal_interleaved_splat() -> bytes:
    return struct.pack(
        "<6f8B",
        0,
        0,
        0,
        1,
        1,
        1,
        128,
        160,
        192,
        255,
        128,
        128,
        128,
        255,
    )


def minimal_spz_v4() -> bytes:
    streams = [b"\x28\xb5\x2f\xfd" + bytes((index, 0, 0, 0)) for index in range(6)]
    decoded_sizes = (9, 1, 3, 3, 4, 9)
    header = struct.pack(
        "<4sIIBBBBI12s",
        b"NGSP",
        4,
        1,
        1,
        12,
        0,
        len(streams),
        32,
        b"\x00" * 12,
    )
    toc = b"".join(
        struct.pack("<QQ", len(stream), decoded_size)
        for stream, decoded_size in zip(streams, decoded_sizes)
    )
    return header + toc + b"".join(streams)


def write_minimal_usdz(path: Path) -> None:
    with zipfile.ZipFile(path, "w", compression=zipfile.ZIP_STORED) as archive:
        archive.writestr("scene.usda", "#usda 1.0\n")


def encode_point_cloud_glb(document: dict, binary_payload: bytes = b"\x00" * 12) -> bytes:
    json_payload = json.dumps(document, separators=(",", ":")).encode("utf-8")
    json_payload += b" " * (-len(json_payload) % 4)
    binary_payload += b"\x00" * (-len(binary_payload) % 4)
    json_chunk = struct.pack("<I4s", len(json_payload), b"JSON") + json_payload
    binary_chunk = struct.pack("<I4s", len(binary_payload), b"BIN\x00") + binary_payload
    total_size = 12 + len(json_chunk) + len(binary_chunk)
    return struct.pack("<4sII", b"glTF", 2, total_size) + json_chunk + binary_chunk


def minimal_point_cloud_document(
    *,
    primitive_mode: int = 0,
    include_position: bool = True,
) -> dict:
    attributes = {"POSITION": 0} if include_position else {}
    return {
        "asset": {"version": "2.0"},
        "buffers": [{"byteLength": 12}],
        "bufferViews": [{"buffer": 0, "byteLength": 12, "target": 34962}],
        "accessors": [
            {
                "bufferView": 0,
                "componentType": 5126,
                "count": 1,
                "type": "VEC3",
            }
        ],
        "meshes": [
            {"primitives": [{"attributes": attributes, "mode": primitive_mode}]}
        ],
    }


def minimal_point_cloud_glb(*, primitive_mode: int = 0, include_position: bool = True) -> bytes:
    document = minimal_point_cloud_document(
        primitive_mode=primitive_mode,
        include_position=include_position,
    )
    binary_payload = struct.pack("<fff", 0, 0, 0)
    return encode_point_cloud_glb(document, binary_payload)


class ReplayWorldManifestTests(unittest.TestCase):
    def fixture(self, root: Path) -> Path:
        source = root / "source.mp4"
        reference = root / "reference.png"
        navigable = root / "navigable.mov"
        reconstruction = root / "world.ply"
        runtime_world = root / "ReplayXIAdmittedWorld.usdz"
        source.write_bytes(minimal_iso_bmff(b"isom"))
        reference.write_bytes(minimal_png())
        navigable.write_bytes(minimal_iso_bmff(b"qt  "))
        reconstruction.write_bytes(minimal_ply())
        write_minimal_usdz(runtime_world)

        payload = {
            "schemaVersion": 1,
            "worldID": "right-wing-overlap",
            "displayName": "Real World Match Replay",
            "source": {
                "kind": "original-synthetic",
                "owner": "Replay XI prototype",
                "rightsBasis": "Original synthetic generation with no imported footage.",
                "promptOrCaptureNote": "Generic teams perform one right-wing overlap.",
                "containsRealPlayerLikenesses": False,
            },
            "coordinates": {
                "upAxis": "Y",
                "metresPerUnit": 1,
                "pitchLengthMetres": 105,
                "pitchWidthMetres": 68,
                "origin": "pitch-centre",
                "positiveZ": "home-attacking-direction",
                "positiveX": "home-right",
            },
            "tacticalTruth": {
                "generatedPixelsAreAuthoritative": False,
                "trackingAuthority": "Replay XI deterministic authored tracking fixture",
            },
            "pipeline": [
                {
                    "name": "generate-video",
                    "provider": "Reactor",
                    "modelOrVersion": "MiniMax FastH3",
                },
                {
                    "name": "generate-navigable-video",
                    "provider": "Reactor",
                    "modelOrVersion": "LingBot World 2",
                },
                {
                    "name": "reconstruct-3d",
                    "provider": "LingBot-Map",
                    "modelOrVersion": LINGBOT_MAP_AUDITED_REVISION,
                },
                {
                    "name": "prepare-realitykit",
                    "provider": "Replay XI offline conversion",
                    "modelOrVersion": "world-admission-v1",
                },
            ],
            "artifacts": [
                {
                    "role": "source-video",
                    "path": source.name,
                    "sha256": digest(source),
                },
                {
                    "role": "reference-image",
                    "path": reference.name,
                    "sha256": digest(reference),
                },
                {
                    "role": "navigable-video",
                    "path": navigable.name,
                    "sha256": digest(navigable),
                },
                {
                    "role": "reconstruction-point-cloud",
                    "path": reconstruction.name,
                    "sha256": digest(reconstruction),
                },
                {
                    "role": "realitykit-world",
                    "path": runtime_world.name,
                    "sha256": digest(runtime_world),
                },
            ],
        }
        manifest = root / "replay-world.json"
        manifest.write_text(json.dumps(payload), encoding="utf-8")
        return manifest

    def test_valid_hash_locked_original_generation_passes(self):
        with tempfile.TemporaryDirectory() as temporary:
            manifest = self.fixture(Path(temporary))
            report = validate_manifest(manifest)

        self.assertTrue(report["passed"])
        self.assertEqual(report["worldID"], "right-wing-overlap")
        self.assertEqual(
            {artifact["role"] for artifact in report["artifacts"]},
            {
                "source-video",
                "reference-image",
                "navigable-video",
                "reconstruction-point-cloud",
                "realitykit-world",
            },
        )

    def test_artifact_roles_cannot_resolve_to_the_same_file(self):
        with tempfile.TemporaryDirectory() as temporary:
            manifest = self.fixture(Path(temporary))
            payload = json.loads(manifest.read_text())
            source = next(
                artifact
                for artifact in payload["artifacts"]
                if artifact["role"] == "source-video"
            )
            navigable = next(
                artifact
                for artifact in payload["artifacts"]
                if artifact["role"] == "navigable-video"
            )
            navigable["path"] = source["path"]
            navigable["sha256"] = source["sha256"]
            manifest.write_text(json.dumps(payload))

            with self.assertRaisesRegex(ManifestError, "resolve to the same file"):
                validate_manifest(manifest)

    def test_lingbot_map_revision_must_be_an_exact_lowercase_git_sha(self):
        invalid_revisions = (
            "pinned-repository-revision",
            LINGBOT_MAP_AUDITED_REVISION.upper(),
            LINGBOT_MAP_AUDITED_REVISION[:-1],
            f" {LINGBOT_MAP_AUDITED_REVISION}",
        )
        for revision in invalid_revisions:
            with self.subTest(revision=revision), tempfile.TemporaryDirectory() as temporary:
                manifest = self.fixture(Path(temporary))
                payload = json.loads(manifest.read_text())
                reconstruction = next(
                    stage
                    for stage in payload["pipeline"]
                    if stage["name"] == "reconstruct-3d"
                )
                reconstruction["modelOrVersion"] = revision
                manifest.write_text(json.dumps(payload))

                with self.assertRaisesRegex(ManifestError, "40-character lowercase"):
                    validate_manifest(manifest)

    def test_valid_glb_points_reconstruction_passes(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            manifest = self.fixture(root)
            point_cloud = root / "world.glb"
            point_cloud.write_bytes(minimal_point_cloud_glb())
            payload = json.loads(manifest.read_text())
            reconstruction = next(
                artifact
                for artifact in payload["artifacts"]
                if artifact["role"] == "reconstruction-point-cloud"
            )
            reconstruction["path"] = point_cloud.name
            reconstruction["sha256"] = digest(point_cloud)
            manifest.write_text(json.dumps(payload))

            report = validate_manifest(manifest)

        reconstruction_path = next(
            artifact["path"]
            for artifact in report["artifacts"]
            if artifact["role"] == "reconstruction-point-cloud"
        )
        self.assertTrue(report["passed"])
        self.assertTrue(reconstruction_path.endswith("world.glb"))

    def test_glb_reconstruction_requires_points_with_position(self):
        invalid_glbs = (
            minimal_point_cloud_glb(primitive_mode=4),
            minimal_point_cloud_glb(include_position=False),
        )
        for glb in invalid_glbs:
            with self.subTest(), tempfile.TemporaryDirectory() as temporary:
                root = Path(temporary)
                manifest = self.fixture(root)
                point_cloud = root / "world.glb"
                point_cloud.write_bytes(glb)
                payload = json.loads(manifest.read_text())
                reconstruction = next(
                    artifact
                    for artifact in payload["artifacts"]
                    if artifact["role"] == "reconstruction-point-cloud"
                )
                reconstruction["path"] = point_cloud.name
                reconstruction["sha256"] = digest(point_cloud)
                manifest.write_text(json.dumps(payload))

                with self.assertRaisesRegex(ManifestError, "POINTS"):
                    validate_manifest(manifest)

    def test_glb_position_accessor_requires_embedded_float_storage(self):
        mutations = (
            (
                "malformed accessor",
                lambda document: document["accessors"].__setitem__(0, "not an accessor"),
            ),
            (
                "missing component type",
                lambda document: document["accessors"][0].pop("componentType"),
            ),
            (
                "missing buffer view",
                lambda document: document["accessors"][0].pop("bufferView"),
            ),
            (
                "invalid buffer view index",
                lambda document: document["accessors"][0].__setitem__("bufferView", 4),
            ),
        )
        for label, mutate in mutations:
            with self.subTest(label=label), tempfile.TemporaryDirectory() as temporary:
                root = Path(temporary)
                manifest = self.fixture(root)
                document = minimal_point_cloud_document()
                mutate(document)
                point_cloud = root / "world.glb"
                point_cloud.write_bytes(encode_point_cloud_glb(document))
                payload = json.loads(manifest.read_text())
                reconstruction = next(
                    artifact
                    for artifact in payload["artifacts"]
                    if artifact["role"] == "reconstruction-point-cloud"
                )
                reconstruction["path"] = point_cloud.name
                reconstruction["sha256"] = digest(point_cloud)
                manifest.write_text(json.dumps(payload))

                with self.assertRaisesRegex(ManifestError, "GLB POINTS"):
                    validate_manifest(manifest)

    def test_glb_position_storage_must_stay_within_declared_bounds(self):
        mutations = (
            (
                "accessor exceeds view",
                lambda document: document["accessors"][0].__setitem__("count", 2),
            ),
            (
                "view exceeds buffer",
                lambda document: document["bufferViews"][0].__setitem__("byteLength", 16),
            ),
            (
                "buffer exceeds BIN",
                lambda document: document["buffers"][0].__setitem__("byteLength", 16),
            ),
            (
                "misaligned accessor offset",
                lambda document: document["accessors"][0].__setitem__("byteOffset", 2),
            ),
        )
        for label, mutate in mutations:
            with self.subTest(label=label), tempfile.TemporaryDirectory() as temporary:
                root = Path(temporary)
                manifest = self.fixture(root)
                document = minimal_point_cloud_document()
                mutate(document)
                point_cloud = root / "world.glb"
                point_cloud.write_bytes(encode_point_cloud_glb(document))
                payload = json.loads(manifest.read_text())
                reconstruction = next(
                    artifact
                    for artifact in payload["artifacts"]
                    if artifact["role"] == "reconstruction-point-cloud"
                )
                reconstruction["path"] = point_cloud.name
                reconstruction["sha256"] = digest(point_cloud)
                manifest.write_text(json.dumps(payload))

                with self.assertRaisesRegex(ManifestError, "GLB"):
                    validate_manifest(manifest)

    def test_mislabeled_glb_reconstruction_is_rejected(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            manifest = self.fixture(root)
            point_cloud = root / "world.glb"
            point_cloud.write_bytes(b"not a GLB")
            payload = json.loads(manifest.read_text())
            reconstruction = next(
                artifact
                for artifact in payload["artifacts"]
                if artifact["role"] == "reconstruction-point-cloud"
            )
            reconstruction["path"] = point_cloud.name
            reconstruction["sha256"] = digest(point_cloud)
            manifest.write_text(json.dumps(payload))

            with self.assertRaisesRegex(ManifestError, "GLB"):
                validate_manifest(manifest)

    def test_mislabeled_artifact_containers_are_rejected(self):
        corruptions = (
            ("source-video", "source.mp4", b"not an ISO-BMFF video", "ISO-BMFF"),
            ("reference-image", "reference.png", b"not a PNG", "PNG"),
            ("reconstruction-point-cloud", "world.ply", b"not a PLY", "PLY"),
            ("realitykit-world", "ReplayXIAdmittedWorld.usdz", b"not a ZIP", "USDZ"),
        )
        for role, filename, content, expected_error in corruptions:
            with self.subTest(role=role), tempfile.TemporaryDirectory() as temporary:
                root = Path(temporary)
                manifest = self.fixture(root)
                artifact_path = root / filename
                artifact_path.write_bytes(content)
                payload = json.loads(manifest.read_text())
                artifact = next(
                    item for item in payload["artifacts"] if item["role"] == role
                )
                artifact["sha256"] = digest(artifact_path)
                manifest.write_text(json.dumps(payload))

                with self.assertRaisesRegex(ManifestError, expected_error):
                    validate_manifest(manifest)

    def test_mislabeled_jpeg_reference_is_rejected(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            manifest = self.fixture(root)
            reference = root / "reference.jpg"
            reference.write_bytes(b"not a JPEG")
            payload = json.loads(manifest.read_text())
            reference_artifact = next(
                artifact
                for artifact in payload["artifacts"]
                if artifact["role"] == "reference-image"
            )
            reference_artifact["path"] = reference.name
            reference_artifact["sha256"] = digest(reference)
            manifest.write_text(json.dumps(payload))

            with self.assertRaisesRegex(ManifestError, "JPEG"):
                validate_manifest(manifest)

    def test_lingbot_stage_and_hash_locked_input_output_are_required(self):
        mutations = (
            (
                lambda payload: payload.__setitem__(
                    "pipeline",
                    [
                        stage
                        for stage in payload["pipeline"]
                        if stage["name"] != "generate-navigable-video"
                    ],
                ),
                "generate-navigable-video",
            ),
            (
                lambda payload: payload.__setitem__(
                    "artifacts",
                    [
                        artifact
                        for artifact in payload["artifacts"]
                        if artifact["role"] != "reference-image"
                    ],
                ),
                "reference-image",
            ),
            (
                lambda payload: payload.__setitem__(
                    "artifacts",
                    [
                        artifact
                        for artifact in payload["artifacts"]
                        if artifact["role"] != "navigable-video"
                    ],
                ),
                "navigable-video",
            ),
        )
        for mutate, expected_error in mutations:
            with self.subTest(expected_error=expected_error), tempfile.TemporaryDirectory() as temporary:
                manifest = self.fixture(Path(temporary))
                payload = json.loads(manifest.read_text())
                mutate(payload)
                manifest.write_text(json.dumps(payload))

                with self.assertRaisesRegex(ManifestError, expected_error):
                    validate_manifest(manifest)

    def test_gaussian_stage_and_artifact_must_appear_together(self):
        with self.subTest("stage without artifact"), tempfile.TemporaryDirectory() as temporary:
            manifest = self.fixture(Path(temporary))
            payload = json.loads(manifest.read_text())
            payload["pipeline"].insert(
                -1,
                {
                    "name": "optimize-gaussian",
                    "provider": "Replay XI offline conversion",
                    "modelOrVersion": "pinned-3dgs-revision",
                },
            )
            manifest.write_text(json.dumps(payload))

            with self.assertRaisesRegex(ManifestError, "gaussian-splat"):
                validate_manifest(manifest)

        with self.subTest("artifact without stage"), tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            manifest = self.fixture(root)
            gaussian = root / "world.spz"
            gaussian.write_bytes(minimal_spz_v4())
            payload = json.loads(manifest.read_text())
            payload["artifacts"].append(
                {
                    "role": "gaussian-splat",
                    "path": gaussian.name,
                    "sha256": hashlib.sha256(gaussian.read_bytes()).hexdigest(),
                }
            )
            manifest.write_text(json.dumps(payload))

            with self.assertRaisesRegex(ManifestError, "optimize-gaussian"):
                validate_manifest(manifest)

    def test_supported_gaussian_containers_pass_conservative_smoke_checks(self):
        fixtures = (
            ("world-gaussian.ply", minimal_gaussian_ply()),
            ("world.splat", minimal_interleaved_splat()),
            ("world.spz", minimal_spz_v4()),
        )
        for filename, content in fixtures:
            with self.subTest(filename=filename), tempfile.TemporaryDirectory() as temporary:
                root = Path(temporary)
                manifest = self.fixture(root)
                gaussian = root / filename
                gaussian.write_bytes(content)
                payload = json.loads(manifest.read_text())
                payload["pipeline"].insert(
                    -1,
                    {
                        "name": "optimize-gaussian",
                        "provider": "Replay XI offline conversion",
                        "modelOrVersion": "pinned-3dgs-revision",
                    },
                )
                payload["artifacts"].append(
                    {
                        "role": "gaussian-splat",
                        "path": gaussian.name,
                        "sha256": digest(gaussian),
                    }
                )
                manifest.write_text(json.dumps(payload))

                report = validate_manifest(manifest)

                self.assertIn("gaussian-splat", {item["role"] for item in report["artifacts"]})

    def test_malformed_gaussian_payloads_fail_closed(self):
        nonfinite_splat = bytearray(minimal_interleaved_splat())
        nonfinite_splat[12:16] = struct.pack("<f", float("inf"))
        bad_spz_toc = bytearray(minimal_spz_v4())
        bad_spz_toc[32:40] = struct.pack("<Q", 1_000_000)
        fixtures = (
            ("ordinary point PLY", "world-gaussian.ply", minimal_ply(), "Gaussian PLY"),
            ("truncated SPLAT", "world.splat", b"x" * 31, "32-byte"),
            ("nonfinite SPLAT", "world.splat", bytes(nonfinite_splat), "finite"),
            ("legacy SPZ", "world.spz", b"\x1f\x8b" + b"x" * 30, "legacy gzip"),
            ("invalid SPZ TOC", "world.spz", bytes(bad_spz_toc), "stream sizes"),
        )
        for label, filename, content, expected_error in fixtures:
            with self.subTest(label=label), tempfile.TemporaryDirectory() as temporary:
                root = Path(temporary)
                manifest = self.fixture(root)
                gaussian = root / filename
                gaussian.write_bytes(content)
                payload = json.loads(manifest.read_text())
                payload["pipeline"].insert(
                    -1,
                    {
                        "name": "optimize-gaussian",
                        "provider": "Replay XI offline conversion",
                        "modelOrVersion": "pinned-3dgs-revision",
                    },
                )
                payload["artifacts"].append(
                    {
                        "role": "gaussian-splat",
                        "path": gaussian.name,
                        "sha256": digest(gaussian),
                    }
                )
                manifest.write_text(json.dumps(payload))

                with self.assertRaisesRegex(ManifestError, expected_error):
                    validate_manifest(manifest)

    def test_runtime_world_identity_is_fixed_before_receipt_generation(self):
        mutations = (
            ("worldID", "another-world", "worldID must match the runtime scenario"),
            ("displayName", "Another Replay", "displayName must match the runtime scenario"),
        )
        for field, value, expected_error in mutations:
            with self.subTest(field=field), tempfile.TemporaryDirectory() as temporary:
                manifest = self.fixture(Path(temporary))
                payload = json.loads(manifest.read_text())
                payload[field] = value
                manifest.write_text(json.dumps(payload))

                with self.assertRaisesRegex(ManifestError, expected_error):
                    validate_manifest(manifest)

    def test_hash_mismatch_is_rejected(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            manifest = self.fixture(root)
            (root / "world.ply").write_bytes(b"mutated")

            with self.assertRaisesRegex(ManifestError, "hash mismatch"):
                validate_manifest(manifest)

    def test_artifact_hash_must_use_canonical_lowercase_without_whitespace(self):
        with tempfile.TemporaryDirectory() as temporary:
            manifest = self.fixture(Path(temporary))
            payload = json.loads(manifest.read_text())
            canonical_hash = payload["artifacts"][0]["sha256"]

        invalid_hashes = (
            canonical_hash.upper(),
            f" {canonical_hash}",
            f"{canonical_hash}\n",
        )
        for invalid_hash in invalid_hashes:
            with self.subTest(
                invalid_hash=invalid_hash
            ), tempfile.TemporaryDirectory() as temporary:
                manifest = self.fixture(Path(temporary))
                payload = json.loads(manifest.read_text())
                payload["artifacts"][0]["sha256"] = invalid_hash
                manifest.write_text(json.dumps(payload))

                with self.assertRaises(ManifestError):
                    validate_manifest(manifest)

    def test_path_traversal_and_symlinks_are_rejected(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            manifest = self.fixture(root)
            payload = json.loads(manifest.read_text())
            payload["artifacts"][0]["path"] = "../source.mp4"
            manifest.write_text(json.dumps(payload))

            with self.assertRaisesRegex(ManifestError, "safe relative"):
                validate_manifest(manifest, verify_files=False)

    def test_symlinked_artifact_is_rejected(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            manifest = self.fixture(root)
            source = root / "source.mp4"
            symlink = root / "source-link.mp4"
            try:
                symlink.symlink_to(source.name)
            except (NotImplementedError, OSError) as error:
                self.skipTest(f"temporary filesystem does not support symlinks: {error}")
            payload = json.loads(manifest.read_text())
            source_artifact = next(
                artifact
                for artifact in payload["artifacts"]
                if artifact["role"] == "source-video"
            )
            source_artifact["path"] = symlink.name
            manifest.write_text(json.dumps(payload))

            with self.assertRaisesRegex(ManifestError, "must not be a symlink"):
                validate_manifest(manifest)

    def test_youtube_reconstruction_source_is_rejected(self):
        with tempfile.TemporaryDirectory() as temporary:
            manifest = self.fixture(Path(temporary))
            payload = json.loads(manifest.read_text())
            payload["source"]["remoteURL"] = "https://www.youtube.com/watch?v=example"
            manifest.write_text(json.dumps(payload))

            with self.assertRaisesRegex(ManifestError, "YouTube"):
                validate_manifest(manifest)

    def test_generated_pixels_cannot_be_declared_as_tactical_truth(self):
        with tempfile.TemporaryDirectory() as temporary:
            manifest = self.fixture(Path(temporary))
            payload = json.loads(manifest.read_text())
            payload["tacticalTruth"]["generatedPixelsAreAuthoritative"] = True
            manifest.write_text(json.dumps(payload))

            with self.assertRaisesRegex(ManifestError, "must be false"):
                validate_manifest(manifest)

    def test_pitch_registration_axes_are_explicit_and_canonical(self):
        with tempfile.TemporaryDirectory() as temporary:
            manifest = self.fixture(Path(temporary))
            payload = json.loads(manifest.read_text())
            payload["coordinates"]["positiveZ"] = "away-attacking-direction"
            manifest.write_text(json.dumps(payload))

            with self.assertRaisesRegex(ManifestError, "positiveZ"):
                validate_manifest(manifest)

    def test_reconstruction_stage_must_name_lingbot_map(self):
        with tempfile.TemporaryDirectory() as temporary:
            manifest = self.fixture(Path(temporary))
            payload = json.loads(manifest.read_text())
            payload["pipeline"][2]["provider"] = "LingBot World 2"
            manifest.write_text(json.dumps(payload))

            with self.assertRaisesRegex(ManifestError, "LingBot-Map"):
                validate_manifest(manifest)

    def test_realitykit_artifact_and_prepare_stage_are_required(self):
        with tempfile.TemporaryDirectory() as temporary:
            manifest = self.fixture(Path(temporary))
            payload = json.loads(manifest.read_text())
            payload["artifacts"] = [
                artifact
                for artifact in payload["artifacts"]
                if artifact["role"] != "realitykit-world"
            ]
            payload["pipeline"] = [
                stage
                for stage in payload["pipeline"]
                if stage["name"] != "prepare-realitykit"
            ]
            manifest.write_text(json.dumps(payload))

            with self.assertRaisesRegex(ManifestError, "prepare-realitykit"):
                validate_manifest(manifest)

    def test_pipeline_stage_order_is_enforced(self):
        with tempfile.TemporaryDirectory() as temporary:
            manifest = self.fixture(Path(temporary))
            payload = json.loads(manifest.read_text())
            payload["pipeline"][2], payload["pipeline"][3] = (
                payload["pipeline"][3],
                payload["pipeline"][2],
            )
            manifest.write_text(json.dumps(payload))

            with self.assertRaisesRegex(ManifestError, "reconstruct-3d must precede"):
                validate_manifest(manifest)

    def test_non_synthetic_capture_requires_hash_locked_rights_record(self):
        with tempfile.TemporaryDirectory() as temporary:
            manifest = self.fixture(Path(temporary))
            payload = json.loads(manifest.read_text())
            payload["source"]["kind"] = "licensed-capture"
            payload["pipeline"] = [
                stage for stage in payload["pipeline"] if stage["name"] != "generate-video"
            ]
            manifest.write_text(json.dumps(payload))

            with self.assertRaisesRegex(ManifestError, "rights-record"):
                validate_manifest(manifest)

    def test_artifact_role_rejects_incompatible_file_extension(self):
        with tempfile.TemporaryDirectory() as temporary:
            manifest = self.fixture(Path(temporary))
            payload = json.loads(manifest.read_text())
            runtime = next(
                artifact
                for artifact in payload["artifacts"]
                if artifact["role"] == "realitykit-world"
            )
            runtime["path"] = "ReplayXIAdmittedWorld.exe"
            manifest.write_text(json.dumps(payload))

            with self.assertRaisesRegex(ManifestError, "realitykit-world"):
                validate_manifest(manifest, verify_files=False)

    def test_admission_receipt_contains_runtime_hash_and_safety_labels(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            manifest = self.fixture(root)
            report = validate_manifest(manifest)
            from validate_replayxi_world_manifest import _admission_receipt

            receipt = _admission_receipt(manifest, report)

        self.assertEqual(receipt["admissionVersion"], 1)
        self.assertEqual(receipt["source"]["kind"], "original-synthetic")
        self.assertFalse(receipt["source"]["containsRealPlayerLikenesses"])
        self.assertFalse(receipt["tacticalTruth"]["generatedPixelsAreAuthoritative"])
        self.assertEqual(receipt["runtimeAsset"]["resourceName"], "ReplayXIAdmittedWorld.usdz")
        self.assertEqual(len(receipt["runtimeAsset"]["sha256"]), 64)
        self.assertGreater(receipt["runtimeAsset"]["byteCount"], 0)

    def test_cli_writes_a_runtime_admission_receipt_only_after_full_validation(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            manifest = self.fixture(root)
            receipt_path = root / "ReplayXIWorldAdmission.json"
            result = subprocess.run(
                [
                    sys.executable,
                    str(PROJECT_ROOT / "Scripts" / "validate_replayxi_world_manifest.py"),
                    str(manifest),
                    "--write-admission-receipt",
                    str(receipt_path),
                ],
                check=False,
                capture_output=True,
                text=True,
            )
            receipt = json.loads(receipt_path.read_text())

        self.assertEqual(result.returncode, 0, result.stderr or result.stdout)
        self.assertEqual(receipt["displayName"], "Real World Match Replay")
        self.assertEqual(receipt["runtimeAsset"]["resourceName"], "ReplayXIAdmittedWorld.usdz")
        self.assertEqual(len(receipt["manifestSHA256"]), 64)

    def test_cli_refuses_receipt_path_that_aliases_manifest_or_artifact(self):
        targets = ("manifest", "source-video", "realitykit-world")
        for target in targets:
            with self.subTest(target=target), tempfile.TemporaryDirectory() as temporary:
                root = Path(temporary)
                manifest = self.fixture(root)
                payload = json.loads(manifest.read_text())
                if target == "manifest":
                    receipt_path = manifest
                else:
                    receipt_path = root / next(
                        artifact["path"]
                        for artifact in payload["artifacts"]
                        if artifact["role"] == target
                    )
                original_bytes = receipt_path.read_bytes()

                result = subprocess.run(
                    [
                        sys.executable,
                        str(PROJECT_ROOT / "Scripts" / "validate_replayxi_world_manifest.py"),
                        str(manifest),
                        "--write-admission-receipt",
                        str(receipt_path),
                    ],
                    check=False,
                    capture_output=True,
                    text=True,
                )

                self.assertEqual(result.returncode, 1, result.stderr or result.stdout)
                self.assertIn("must not alias validated input", result.stdout)
                self.assertEqual(receipt_path.read_bytes(), original_bytes)

    def test_cli_refuses_receipt_hard_link_to_validated_artifact(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            manifest = self.fixture(root)
            source = root / "source.mp4"
            receipt_path = root / "ReplayXIWorldAdmission.json"
            os.link(source, receipt_path)
            original_bytes = source.read_bytes()

            result = subprocess.run(
                [
                    sys.executable,
                    str(PROJECT_ROOT / "Scripts" / "validate_replayxi_world_manifest.py"),
                    str(manifest),
                    "--write-admission-receipt",
                    str(receipt_path),
                ],
                check=False,
                capture_output=True,
                text=True,
            )

            self.assertEqual(result.returncode, 1, result.stderr or result.stdout)
            self.assertIn("must not hard-link validated input", result.stdout)
            self.assertEqual(source.read_bytes(), original_bytes)
            self.assertEqual(receipt_path.read_bytes(), original_bytes)

    def test_licensed_likeness_capture_passes_with_hash_locked_rights_record(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            manifest = self.fixture(root)
            rights = root / "rights.json"
            rights.write_text('{"permission":"prototype reconstruction"}')
            payload = json.loads(manifest.read_text())
            payload["source"]["kind"] = "licensed-capture"
            payload["source"]["containsRealPlayerLikenesses"] = True
            payload["source"]["likenessRightsBasis"] = "Recorded prototype consent."
            payload["pipeline"] = [
                stage for stage in payload["pipeline"] if stage["name"] != "generate-video"
            ]
            payload["artifacts"].append(
                {
                    "role": "rights-record",
                    "path": rights.name,
                    "sha256": hashlib.sha256(rights.read_bytes()).hexdigest(),
                }
            )
            manifest.write_text(json.dumps(payload))

            report = validate_manifest(manifest)

        self.assertEqual(report["sourceKind"], "licensed-capture")
        self.assertTrue(report["source"]["containsRealPlayerLikenesses"])


if __name__ == "__main__":
    unittest.main()
