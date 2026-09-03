import hashlib
import os
from pathlib import Path
import sys
import tempfile
import unittest


PROJECT_ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(PROJECT_ROOT / "Scripts"))

from fetch_replayxi_rocketbox_pilot import (  # noqa: E402
    AssetRecord,
    PILOT_ASSETS,
    ROCKETBOX_COMMIT,
    audit_directory,
    source_url,
    validated_target,
)


class RocketboxAcquisitionTests(unittest.TestCase):
    def test_manifest_is_commit_pinned_unique_and_hash_locked(self):
        self.assertRegex(ROCKETBOX_COMMIT, r"^[0-9a-f]{40}$")
        paths = [record.path for record in PILOT_ASSETS]
        self.assertEqual(len(paths), len(set(paths)))
        self.assertGreater(sum(record.byte_count for record in PILOT_ASSETS), 75_000_000)
        for record in PILOT_ASSETS:
            with self.subTest(path=record.path):
                self.assertGreater(record.byte_count, 0)
                self.assertRegex(record.sha256, r"^[0-9a-f]{64}$")
                self.assertIn(ROCKETBOX_COMMIT, source_url(record))

    def test_audit_accepts_exact_payload_and_rejects_corruption(self):
        payload = b"rights-safe football athlete"
        record = AssetRecord(
            "nested/player.bin",
            len(payload),
            hashlib.sha256(payload).hexdigest(),
            "fixture",
        )
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            target = validated_target(root, record.path)
            target.parent.mkdir(parents=True)
            target.write_bytes(payload)
            self.assertEqual(audit_directory(root, (record,)), [])

            target.write_bytes(payload + b"!")
            errors = audit_directory(root, (record,))
            self.assertEqual(len(errors), 1)
            self.assertIn("size", errors[0])

    def test_path_traversal_and_symlink_escape_are_rejected(self):
        with tempfile.TemporaryDirectory() as temporary, tempfile.TemporaryDirectory() as outside:
            root = Path(temporary)
            for unsafe in ("../escaped", "/absolute", "nested/../../escaped"):
                with self.subTest(path=unsafe), self.assertRaises(ValueError):
                    validated_target(root, unsafe)

            link = root / "redirect"
            os.symlink(outside, link)
            with self.assertRaisesRegex(ValueError, "escapes destination"):
                validated_target(root, "redirect/player.fbx")


if __name__ == "__main__":
    unittest.main()
