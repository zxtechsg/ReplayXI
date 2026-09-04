import hashlib
import json
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
        source.write_bytes(b"original synthetic video fixture")
        reconstruction.write_bytes(b"ply\nformat ascii 1.0\nend_header\n")

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
            {"source-video", "reconstruction-point-cloud"},
        )

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

    def test_reconstruction_stage_must_name_lingbot_map(self):
        with tempfile.TemporaryDirectory() as temporary:
            manifest = self.fixture(Path(temporary))
            payload = json.loads(manifest.read_text())
            payload["pipeline"][2]["provider"] = "LingBot World 2"
            manifest.write_text(json.dumps(payload))

            with self.assertRaisesRegex(ManifestError, "LingBot-Map"):
                validate_manifest(manifest)


if __name__ == "__main__":
    unittest.main()
