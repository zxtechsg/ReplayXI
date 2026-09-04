import hashlib
import json
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path


PROJECT_ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(PROJECT_ROOT / "Scripts"))

from validate_replayxi_world_manifest import ManifestError, validate_manifest  # noqa: E402


class ReplayWorldManifestTests(unittest.TestCase):
    def fixture(self, root: Path) -> Path:
        source = root / "source.mp4"
        reconstruction = root / "world.ply"
        runtime_world = root / "ReplayXIAdmittedWorld.usdz"
        source.write_bytes(b"original synthetic video fixture")
        reconstruction.write_bytes(b"ply\nformat ascii 1.0\nend_header\n")
        runtime_world.write_bytes(b"hash-locked RealityKit world fixture")

        def digest(path: Path) -> str:
            return hashlib.sha256(path.read_bytes()).hexdigest()

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
                    "modelOrVersion": "pinned-repository-revision",
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
            {"source-video", "reconstruction-point-cloud", "realitykit-world"},
        )

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

    def test_path_traversal_and_symlinks_are_rejected(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            manifest = self.fixture(root)
            payload = json.loads(manifest.read_text())
            payload["artifacts"][0]["path"] = "../source.mp4"
            manifest.write_text(json.dumps(payload))

            with self.assertRaisesRegex(ManifestError, "safe relative"):
                validate_manifest(manifest, verify_files=False)

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
