import hashlib
from pathlib import Path
import unittest


PROJECT_ROOT = Path(__file__).resolve().parents[2]
GOLDEN_ASSET = PROJECT_ROOT / "ReplayXITests/Fixtures/Generated/ReplayXIPlayerKit.usdz"
RUNTIME_ASSET = PROJECT_ROOT / "ReplayXI/Resources/Players/ReplayXIPlayerKitPilot.usdz"
RUNTIME_LICENSE = (
    PROJECT_ROOT
    / "ReplayXI/Resources/Players/LICENSE-QUATERNIUS-CC0-1.0.txt"
)
PROVIDER = PROJECT_ROOT / "ReplayXI/Immersive/ReplayImportedAthleteProvider.swift"
EXPECTED_SHA256 = "afeec6489a68c2ac121dad713021c7a5a6ff65ae3f031d3758ccdabfa4574cc1"
EXPECTED_BYTES = 4_833_314


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for block in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


class RuntimePlayerPilotTests(unittest.TestCase):
    def test_runtime_asset_is_byte_identical_to_audited_golden_fixture(self):
        self.assertTrue(GOLDEN_ASSET.is_file())
        self.assertTrue(RUNTIME_ASSET.is_file())
        self.assertEqual(RUNTIME_ASSET.stat().st_size, EXPECTED_BYTES)
        self.assertEqual(sha256(GOLDEN_ASSET), EXPECTED_SHA256)
        self.assertEqual(sha256(RUNTIME_ASSET), EXPECTED_SHA256)

    def test_runtime_notice_and_provider_guardrails_are_checked_in(self):
        notice = RUNTIME_LICENSE.read_text()
        self.assertIn("CC0", notice)
        self.assertIn("Quaternius", notice)

        provider = PROVIDER.read_text()
        self.assertIn(f'static let expectedSHA256 = "{EXPECTED_SHA256}"', provider)
        self.assertIn(f"static let expectedBytes = {EXPECTED_BYTES:_}", provider)
        self.assertIn("static let maximumConcurrentNearFieldInstances = 1", provider)
        self.assertIn('static let environmentKey = "REPLAYXI_IMPORTED_PLAYER_PILOT"', provider)
        self.assertIn(
            'static let userDefaultsKey = "ReplayXI.ImportedPlayerPilotEnabled"',
            provider,
        )
        self.assertIn("debugDefault: false", provider)
        self.assertNotIn("_isDebugAssertConfiguration()", provider)


if __name__ == "__main__":
    unittest.main()
