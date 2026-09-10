"""Transform and sampling regressions for the deterministic skinned athlete."""
import sys
from pathlib import Path
import unittest

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
try:
    import numpy as np
    from build_replayxi_skinned_athlete import decompose, interpolate, local_matrix, metres
    AVAILABLE = True
except ImportError:
    AVAILABLE = False


@unittest.skipUnless(AVAILABLE, "asset builder needs numpy, Pillow and usd-core")
class SkinnedAthleteTransformTests(unittest.TestCase):
    def test_centimetre_conversion_keeps_rotation_and_scales_only_translation(self):
        matrix = local_matrix({"translation": [15, 90, -20], "rotation": [0, 0.7071067812, 0, 0.7071067812]})
        converted = metres(matrix)
        np.testing.assert_allclose(converted[:3, :3], matrix[:3, :3])
        np.testing.assert_allclose(converted[:3, 3], [0.15, 0.9, -0.2])
        translation, rotation, scale = decompose(converted)
        reconstructed = local_matrix({"translation": translation, "rotation": rotation, "scale": scale})
        np.testing.assert_allclose(reconstructed, converted, atol=1e-6)

    def test_opposite_quaternion_signs_do_not_spin_or_collapse_between_frames(self):
        q = np.array([0, 0.7071067812, 0, 0.7071067812])
        result = interpolate(np.array([0, 1]), np.array([q, -q]), 0.5, rotation=True)
        np.testing.assert_allclose(result, q, atol=1e-7)
        self.assertAlmostEqual(float(np.linalg.norm(result)), 1)

    def test_sampling_preserves_clip_endpoints_and_uses_linear_translation(self):
        times = np.array([0.0, 0.25, 0.6])
        values = np.array([[0, 0.7, 0], [0, 0.8, 0], [0, 0.7, 0]])
        np.testing.assert_array_equal(interpolate(times, values, -1), values[0])
        np.testing.assert_array_equal(interpolate(times, values, 1), values[-1])
        np.testing.assert_allclose(interpolate(times, values, 0.125), [0, 0.75, 0])


if __name__ == "__main__":
    unittest.main()
