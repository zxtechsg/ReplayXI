import ast
import io
import shutil
import sys
import tempfile
import unittest
import zipfile
from pathlib import Path


PROJECT_ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(PROJECT_ROOT / "Scripts"))

from audit_replayxi_player_usdz import _topology_errors, audit  # noqa: E402
from replayxi_usdz_archive import (  # noqa: E402
    FIXED_ZIP_DATETIME,
    normalize_usdz_timestamps,
    validated_archive_names,
)
from repair_replayxi_legacy_usdz import (  # noqa: E402
    derive_joint_paths,
    repair_usda,
)


def load_converter_patcher():
    build_script = PROJECT_ROOT / "Scripts/build_replayxi_player_usdz.py"
    tree = ast.parse(build_script.read_text())
    function = next(
        node
        for node in tree.body
        if isinstance(node, ast.FunctionDef) and node.name == "copy_and_patch_converter"
    )
    namespace = {"shutil": shutil}
    exec(
        compile(ast.Module(body=[function], type_ignores=[]), str(build_script), "exec"),
        namespace,
    )
    return namespace["copy_and_patch_converter"]


class JointTopologyTests(unittest.TestCase):
    def test_converter_patch_preserves_paths_on_cache_hits_and_misses(self):
        legacy_source = '''def fixture():
            skeleton.CreateJointsAttr().Set(usd_joint_names)
            skeleton.CreateBindTransformsAttr(gltf_bind_transforms)
            skeleton.CreateRestTransformsAttr(gltf_rest_transforms)
            skelAnim.CreateJointsAttr().Set(joint_names)
            translate_attr.Set(entries, Usd.TimeCode(input_key * self.fps))
            scale_attr.Set(entries, Usd.TimeCode(input_key * self.fps))
            return GLTF2USDUtils.convert_to_usd_friendly_node_name(self._joint_hierarchy_name_map[gltf_joint])
            return GLTF2USDUtils.convert_to_usd_friendly_node_name(joint_name)
            usd_joint_names = [Sdf.Path(self._get_usd_joint_hierarchy_name(joint, gltf_skin.root_joints)) for joint in gltf_skin.get_joints()]
'''
        with tempfile.TemporaryDirectory() as temporary:
            temporary_root = Path(temporary)
            source = temporary_root / "source"
            destination = temporary_root / "patched"
            (source / "Source").mkdir(parents=True)
            (source / "Source/gltf2usd.py").write_text(legacy_source)

            script = load_converter_patcher()(source, destination)
            patched = script.read_text()

        self.assertEqual(patched.count("for segment in "), 2)
        self.assertIn("self._joint_hierarchy_name_map[gltf_joint].split('/')", patched)
        self.assertIn("joint_name.split('/')", patched)
        self.assertIn("joint_namespace =", patched)
        self.assertIn("Sdf.Path('{0}_{1}'.format(joint_namespace, path))", patched)

    def test_derives_hierarchical_joint_paths_in_skin_order(self):
        gltf = {
            "nodes": [
                {"name": "Head"},
                {"name": "pelvis", "children": [0]},
                {"name": "root", "children": [1]},
            ],
            "skins": [{"joints": [2, 1, 0]}],
        }

        self.assertEqual(
            derive_joint_paths(gltf),
            ["root_2", "root_2/pelvis_1", "root_2/pelvis_1/Head_0"],
        )

    def test_repair_restores_hierarchy_namespaces_and_removes_xform_copy(self):
        usda = '''#usda 1.0
def Xform "root"
{
        def Xform "Body_3"
        {
            def SkelRoot "skeleton_root"
            {
                def Skeleton "root_2"
                {
                    uniform token[] joints = ["root_2", "root_2_pelvis_1", "root_2_pelvis_1_Head_0"]
                    def SkelAnimation "anim"
                    {
                        uniform token[] joints = ["root_2", "root_2_pelvis_1", "root_2_pelvis_1_Head_0"]
                    }
                }
            }
        }
        def Xform "Eyes_4"
        {
            def SkelRoot "skeleton_root"
            {
                def Skeleton "root_2"
                {
                    uniform token[] joints = ["root_2", "root_2_pelvis_1", "root_2_pelvis_1_Head_0"]
                    def SkelAnimation "anim"
                    {
                        uniform token[] joints = ["root_2", "root_2_pelvis_1", "root_2_pelvis_1_Head_0"]
                    }
                }
            }
        }
        def Xform "root_2"
        {
            matrix4d xformOp:transform:transform.timeSamples = {
                0: ((1, 0, 0, 0), (0, 1, 0, 0), (0, 0, 1, 0), (0, 0, 0, 1)),
            }
        }
}
'''
        joints = ["root_2", "root_2/pelvis_1", "root_2/pelvis_1/Head_0"]

        repaired, report = repair_usda(usda, joints)

        self.assertNotIn("xformOp:transform:transform.timeSamples", repaired)
        self.assertNotIn('def Xform "root_2"', repaired)
        self.assertIn('"Body_3_root_2/pelvis_1/Head_0"', repaired)
        self.assertIn('"Eyes_4_root_2/pelvis_1/Head_0"', repaired)
        self.assertEqual(report["jointArrays"], 4)
        self.assertEqual(report["skeletonNamespaces"], ["Body_3_root_2", "Eyes_4_root_2"])

    def test_flat_joint_tokens_are_rejected(self):
        errors = _topology_errors(["root_0", "root_0_pelvis_1"], "fixture")
        self.assertTrue(any("hierarchy separators were lost" in error for error in errors))

    def test_hierarchical_joint_tokens_have_one_root(self):
        self.assertEqual(
            _topology_errors(["body_root", "body_root/pelvis", "body_root/pelvis/head"], "fixture"),
            [],
        )

    def test_joint_parent_must_precede_child(self):
        errors = _topology_errors(["root/pelvis", "root"], "fixture")
        self.assertTrue(any("must precede child" in error for error in errors))

    def test_repair_rejects_out_of_order_glb_joint_array(self):
        gltf = {
            "nodes": [
                {"name": "pelvis"},
                {"name": "root", "children": [0]},
            ],
            "skins": [{"joints": [0, 1]}],
        }

        with self.assertRaisesRegex(ValueError, "does not precede child"):
            derive_joint_paths(gltf)

    def test_repair_rejects_archive_path_traversal(self):
        buffer = io.BytesIO()
        with zipfile.ZipFile(buffer, "w") as archive:
            archive.writestr("../escaped.usdc", b"not usd")
        buffer.seek(0)
        with zipfile.ZipFile(buffer) as archive:
            with self.assertRaisesRegex(ValueError, "unsafe USDZ archive member"):
                validated_archive_names(archive.infolist())

    def test_timestamp_normalization_is_idempotent(self):
        with tempfile.TemporaryDirectory() as temporary:
            archive_path = Path(temporary) / "fixture.usdz"
            with zipfile.ZipFile(archive_path, "w", compression=zipfile.ZIP_STORED) as archive:
                archive.writestr("scene.usda", b"#usda 1.0\n")
                archive.writestr("texture.png", b"payload")

            normalize_usdz_timestamps(archive_path)
            first = archive_path.read_bytes()
            normalize_usdz_timestamps(archive_path)
            second = archive_path.read_bytes()

            self.assertEqual(first, second)
            with zipfile.ZipFile(archive_path) as archive:
                self.assertTrue(
                    all(
                        info.date_time == FIXED_ZIP_DATETIME
                        for info in archive.infolist()
                    )
                )


class CheckedInAssetTests(unittest.TestCase):
    def test_checked_in_player_assets_pass_strict_structure_audit(self):
        assets = [
            PROJECT_ROOT
            / "ReplayXITests/Fixtures/ThirdParty/Quaternius/ReplayXIPlayerSprint.usdz",
            PROJECT_ROOT / "ReplayXITests/Fixtures/Generated/ReplayXIPlayerKit.usdz",
        ]
        for asset in assets:
            with self.subTest(asset=asset.name):
                report = audit(asset)
                self.assertTrue(report["passed"], report["errors"])
                self.assertEqual(report["joints"], 65)
                self.assertEqual(report["legacyAnimatedXforms"], 0)


if __name__ == "__main__":
    unittest.main()
