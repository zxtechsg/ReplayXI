"""Transform and sampling regressions for the deterministic skinned athlete."""
import sys
from pathlib import Path
import tempfile
import unittest

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
try:
    import numpy as np
    from PIL import Image
    from pxr import Gf, Sdf, Usd, UsdGeom, UsdShade, UsdSkel, Vt
    from build_replayxi_skinned_athlete import (
        ROOT_PATH, audit_surface_contract, decompose, interpolate, local_matrix, metres, write_usd,
    )
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


@unittest.skipUnless(AVAILABLE, "asset builder needs numpy, Pillow and usd-core")
class SkinnedAthleteSurfaceContractTests(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory(prefix="replayxi-surface-test-")
        self.addCleanup(self.directory.cleanup)
        self.path = Path(self.directory.name) / "athlete.usda"
        self.joints = ["Pelvis", "Pelvis/Spine"]
        for name in ("body_colour", "body_normal", "head_colour", "head_normal"):
            Image.new("RGB", (2, 2), (128, 128, 255)).save(self.path.parent / f"{name}.png")
        contract = {"paths": self.joints, "bind": [np.eye(4)] * 2, "rest": [np.eye(4)] * 2}
        mesh = {"points": np.array([[0., 0., 0.], [1., 0., 0.], [0., 1., 0.]]),
                "normals": np.array([[0., 0.6, 0.8]] * 3), "indices": np.array([0, 1, 2]),
                "uv": np.array([[0., 0.], [1., 0.], [0., 1.]]),
                "joints": np.array([[0, 1, 0, 0]] * 3),
                "weights": np.array([[0.5, 0.5, 0, 0]] * 3)}
        frame = {"time": 0, "translations": [[0, 0, 0]] * 2,
                 "rotations": [[0, 0, 0, 1]] * 2, "scales": [[1, 1, 1]] * 2}
        write_usd(self.path, contract, [mesh, mesh], [{"id": "idle", "frames": [frame]}], "MIT test fixture")

    def test_written_usd_preserves_smooth_normals_normal_maps_and_shared_skin(self):
        report = audit_surface_contract(self.path, self.joints)
        self.assertEqual(report["jointCount"], 2)
        for name in ("Body", "Head"):
            self.assertEqual(report["meshes"][name]["normalCount"], 3)
            self.assertEqual(report["meshes"][name]["normalInterpolation"], "vertex")
            self.assertEqual(report["meshes"][name]["smoothCornerFraction"], 1)
            self.assertEqual(report["meshes"][name]["skeletonPath"], ROOT_PATH + "/Skeleton")

    def test_missing_and_flat_normals_are_rejected(self):
        stage = Usd.Stage.Open(str(self.path))
        mesh = UsdGeom.Mesh(stage.GetPrimAtPath(ROOT_PATH + "/Body"))
        mesh.GetNormalsAttr().Clear()
        stage.GetRootLayer().Save()
        with self.assertRaisesRegex(RuntimeError, "per-vertex normals"):
            audit_surface_contract(self.path, self.joints)
        mesh.GetNormalsAttr().Set(Vt.Vec3fArray([Gf.Vec3f(0, 0, 1)] * 3))
        stage.GetRootLayer().Save()
        with self.assertRaisesRegex(RuntimeError, "look flat"):
            audit_surface_contract(self.path, self.joints)

    def test_lost_head_skin_binding_is_rejected(self):
        stage = Usd.Stage.Open(str(self.path))
        binding = UsdSkel.BindingAPI(stage.GetPrimAtPath(ROOT_PATH + "/Head"))
        binding.GetSkeletonRel().SetTargets([])
        stage.GetRootLayer().Save()
        with self.assertRaisesRegex(RuntimeError, "shared-skeleton binding"):
            audit_surface_contract(self.path, self.joints)

    def test_invalid_normal_map_colour_space_is_rejected(self):
        stage = Usd.Stage.Open(str(self.path))
        shader = UsdShade.Shader(stage.GetPrimAtPath(ROOT_PATH + "/BodyMaterial/Normal"))
        shader.GetInput("sourceColorSpace").Set("sRGB")
        stage.GetRootLayer().Save()
        with self.assertRaisesRegex(RuntimeError, "colour space changed"):
            audit_surface_contract(self.path, self.joints)

    def test_motion_joint_order_must_match_skeleton(self):
        with self.assertRaisesRegex(RuntimeError, "joint order differs"):
            audit_surface_contract(self.path, self.joints[::-1])


if __name__ == "__main__":
    unittest.main()
