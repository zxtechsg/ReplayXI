import copy
import hashlib
import io
import json
import os
import shutil
import struct
import sys
import tempfile
import unittest
from contextlib import redirect_stderr
from pathlib import Path
from unittest import mock


PROJECT_ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(PROJECT_ROOT / "Scripts"))

import build_replayxi_rocketbox_pilot as pilot_builder  # noqa: E402
from build_replayxi_rocketbox_pilot import (  # noqa: E402
    EXPECTED_GLTF2USD_SOURCE_HASH,
    EXPECTED_MICROSOFT_MIT_NOTICE_SHA256,
    EXPECTED_PATCHED_GLTF2USD_SOURCE_HASH,
    MICROSOFT_MIT_NOTICE,
    MOTION_EXTRACTION_NODES,
    PELVIS_NODE,
    ROOT_TRANSLATION_NODE,
    audit_usd_skinning,
    build_textures,
    canonical_json,
    canonicalize_materials,
    finite_positive_float,
    gltf2usd_source_hash,
    hierarchical_joint_order,
    is_skin_pixel,
    load_microsoft_mit_notice,
    merge_run_animation,
    neutralize_body_texture_arrays,
    patch_converter,
    publish_asset_and_report,
    publish_bytes_exclusive,
    snapshot_verified_files,
    unique_node_map,
    validate_publication_paths,
    validate_skinning_arrays,
)
from fetch_replayxi_rocketbox_pilot import AssetRecord  # noqa: E402


PINNED_INPUT_ROOT = Path("/private/tmp/replayxi-rocketbox-pilot-check")
PINNED_GLTF2USD_ROOT = Path(
    "/private/tmp/replayxi-loop12-asset-audit.IktoEi/"
    "gltf2usd-c0752099313834a466acf04b89af33dfd5dc9a0b"
)
try:
    import numpy as np
    from PIL import Image

    HAS_TEXTURE_RUNTIME = True
except ImportError:
    np = None
    Image = None
    HAS_TEXTURE_RUNTIME = False


def animation_fixture(unmatched=None):
    unmatched = set(MOTION_EXTRACTION_NODES if unmatched is None else unmatched)
    weighted = [PELVIS_NODE] + [f"joint-{index}" for index in range(1, 80)]
    shared = [ROOT_TRANSLATION_NODE, "Bip01_$AssimpFbx$_Rotation", "Bip01_$AssimpFbx$_Scaling", "Bip01 Footsteps"]
    model_names = weighted + shared
    run_names = list(reversed(model_names)) + sorted(unmatched)
    model = {
        "nodes": [{"name": name} for name in model_names],
        "skins": [{"joints": list(range(80))}],
        "animations": [{"name": "discard"}],
        "accessors": [],
        "bufferViews": [],
        "buffers": [{"uri": "model.bin", "byteLength": 0}],
    }
    run = {
        "nodes": [{"name": name} for name in run_names],
        "accessors": [],
        "bufferViews": [],
        "buffers": [{"uri": "run.bin", "byteLength": 0}],
    }
    payload = bytearray()
    channels = []
    samplers = []

    def add(values, kind):
        width = {"SCALAR": 1, "VEC3": 3, "VEC4": 4}[kind]
        while len(payload) % 4:
            payload.append(0)
        start = len(payload)
        for row in values:
            payload.extend(struct.pack("<" + "f" * width, *row))
        view = len(run["bufferViews"])
        run["bufferViews"].append({"buffer": 0, "byteOffset": start, "byteLength": len(payload) - start})
        accessor = len(run["accessors"])
        run["accessors"].append(
            {"bufferView": view, "componentType": 5126, "count": len(values), "type": kind}
        )
        return accessor

    for name in run_names:
        for path in ("translation", "rotation", "scale"):
            if name == ROOT_TRANSLATION_NODE and path == "translation":
                times = [(index / 30.0,) for index in range(19)]
                values = [(0.0, 76.0 + 7.0 * (index % 2), 350.0 * index / 18.0) for index in range(19)]
                output_kind = "VEC3"
            elif name == PELVIS_NODE and path == "translation":
                times = [(index / 30.0,) for index in range(19)]
                values = [(0.0, 0.0, 0.0) for _ in range(19)]
                output_kind = "VEC3"
            else:
                times = [(0.0,)]
                values = [(0.0, 0.0, 0.0, 1.0)] if path == "rotation" else [
                    (1.0, 1.0, 1.0) if path == "scale" else (0.0, 0.0, 0.0)
                ]
                output_kind = "VEC4" if path == "rotation" else "VEC3"
            sampler = {"input": add(times, "SCALAR"), "output": add(values, output_kind), "interpolation": "LINEAR"}
            channels.append({"sampler": len(samplers), "target": {"node": run_names.index(name), "path": path}})
            samplers.append(sampler)
    run["animations"] = [{"name": "Take 001", "channels": channels, "samplers": samplers}]
    run["buffers"][0]["byteLength"] = len(payload)
    return model, run, bytes(payload)


class RocketboxPilotPipelineTests(unittest.TestCase):
    def test_node_matching_rejects_duplicate_names(self):
        with self.assertRaisesRegex(RuntimeError, "duplicate node name"):
            unique_node_map({"nodes": [{"name": "pelvis"}, {"name": "pelvis"}]}, "fixture")

    def test_merge_uses_names_and_strips_horizontal_root_travel(self):
        model, run, run_binary = animation_fixture()
        merged, merged_binary, report = merge_run_animation(model, b"", run, run_binary)
        self.assertEqual(report["keptChannels"], 252)
        self.assertEqual(report["droppedMotionExtractionChannels"], 6)
        self.assertAlmostEqual(report["sourceTravelCentimetres"], 350.0, places=4)
        self.assertAlmostEqual(report["verticalGaitRangeCentimetres"], 7.0, places=4)
        root_index = unique_node_map(merged, "merged")[ROOT_TRANSLATION_NODE]
        channel = next(
            channel
            for channel in merged["animations"][0]["channels"]
            if channel["target"] == {"node": root_index, "path": "translation"}
        )
        sampler = merged["animations"][0]["samplers"][channel["sampler"]]
        from build_replayxi_rocketbox_pilot import read_accessor

        values = read_accessor(merged, merged_binary, sampler["output"])
        self.assertTrue(all(value[0] == 0.0 and value[2] == 0.0 for value in values))
        self.assertGreater(max(value[1] for value in values), min(value[1] for value in values))

    def test_merge_fails_on_any_unexpected_unmatched_node(self):
        expected = sorted(MOTION_EXTRACTION_NODES)
        model, run, payload = animation_fixture({expected[0], "surprise-helper"})
        with self.assertRaisesRegex(RuntimeError, "unexpected unmatched animation nodes"):
            merge_run_animation(model, b"", run, payload)

    def test_merge_is_byte_deterministic(self):
        model, run, payload = animation_fixture()
        first = merge_run_animation(model, b"", run, payload)
        second = merge_run_animation(copy.deepcopy(model), b"", copy.deepcopy(run), payload)
        self.assertEqual(canonical_json(first[0]), canonical_json(second[0]))
        self.assertEqual(first[1], second[1])

    def test_material_rewrite_removes_source_extensions_and_specular_maps(self):
        document = {
            "materials": [
                {"name": "m301_body", "extensions": {"KHR_materials_specular": {}}},
                {"name": "m301_head", "extensions": {"KHR_materials_specular": {}}},
            ],
            "images": [{}] * 6,
            "textures": [{}] * 6,
            "samplers": [{}] * 6,
        }
        canonicalize_materials(document)
        rendered = canonical_json(document).decode()
        self.assertNotIn("KHR_materials", rendered)
        self.assertNotIn("specular", rendered.lower())
        self.assertEqual(len(document["images"]), 4)
        self.assertEqual(document["materials"][0]["name"], "ReplayXI_NeutralKit")

    def test_skin_gate_preserves_skin_but_rejects_branding_colours(self):
        self.assertTrue(is_skin_pixel(190, 125, 92))
        self.assertTrue(is_skin_pixel(225, 164, 126))
        self.assertFalse(is_skin_pixel(230, 45, 8))
        self.assertFalse(is_skin_pixel(220, 220, 220))
        self.assertFalse(is_skin_pixel(17, 43, 72))

    @unittest.skipUnless(HAS_TEXTURE_RUNTIME, "numpy/Pillow texture runtime unavailable")
    def test_neutral_texture_uses_skin_gate_and_has_locked_output_hash(self):
        body = np.full((4, 4, 3), (230, 45, 8), dtype=np.uint8)
        normal = np.full((4, 4, 3), (3, 4, 5), dtype=np.uint8)
        body[1, 2] = (190, 125, 92)
        normal[1, 2] = (111, 122, 233)
        atlas = np.ones((4, 4), dtype=bool)
        with mock.patch.object(
            pilot_builder, "is_skin_pixel", wraps=pilot_builder.is_skin_pixel
        ) as skin_gate:
            styled, styled_normal, skin = neutralize_body_texture_arrays(
                body, normal, atlas
            )
        self.assertGreaterEqual(skin_gate.call_count, 2)
        self.assertEqual(styled[1, 2].tolist(), [190, 125, 92])
        self.assertEqual(styled_normal[1, 2].tolist(), [111, 122, 233])
        self.assertEqual(styled[0, 0].tolist(), [17, 42, 71])
        self.assertFalse(bool(skin[0, 0]))
        digest = hashlib.sha256(
            styled.tobytes() + styled_normal.tobytes() + skin.tobytes()
        ).hexdigest()
        self.assertEqual(
            digest,
            "cc97b760e04b69ad00be3f354da351f0a91492dc606349b467bbfa1730b6dc89",
        )

    @unittest.skipUnless(
        HAS_TEXTURE_RUNTIME and PINNED_INPUT_ROOT.is_dir(),
        "pinned Rocketbox texture fixture unavailable",
    )
    def test_full_neutral_texture_build_is_hash_deterministic(self):
        expected = {
            "replayxi_body_color.png": "321354ca0ff29429462f892f0503afd2d2120daa20bac6747a8cbc4b675bc084",
            "replayxi_body_normal.png": "08af60ab7b7ccbc4be07ee97b7b0600aba8a60b1ad9270be7a516b9eac09a577",
            "replayxi_head_color.png": "79b71d65c407c9fb6b973ef811bb166cb10c3e4b9c6087b3e056004e9e9a8515",
            "replayxi_head_normal.png": "6048bf94a6ff72132608beef40731f14d941b26b9857c8f963f88b4523332d14",
        }
        with tempfile.TemporaryDirectory() as temporary:
            first = Path(temporary) / "first"
            second = Path(temporary) / "second"
            first.mkdir()
            second.mkdir()
            first_report = build_textures(PINNED_INPUT_ROOT, first, 1024)
            second_report = build_textures(PINNED_INPUT_ROOT, second, 1024)
            self.assertEqual(first_report["textureSHA256"], expected)
            self.assertEqual(second_report["textureSHA256"], expected)
            with Image.open(first / "replayxi_body_color.png") as image:
                # Central shirt texel was source artwork and must now be kit navy.
                red, green, blue = image.convert("RGB").getpixel((512, 650))
                self.assertLess(red, 30)
                self.assertLess(green, 60)
                self.assertLess(blue, 90)

    def test_joint_order_moves_parent_before_children_stably(self):
        joints = ["root/spine", "root/spine/head", "root", "root/leftLeg", "root/rightLeg"]
        order = hierarchical_joint_order(joints)
        self.assertEqual([joints[index] for index in order], ["root", "root/spine", "root/leftLeg", "root/rightLeg", "root/spine/head"])

    def test_joint_order_rejects_multiple_roots(self):
        with self.assertRaisesRegex(RuntimeError, "one effective joint root"):
            hierarchical_joint_order(["pelvis/spine", "orphan/head"])

    def test_canonical_json_is_order_independent(self):
        self.assertEqual(canonical_json({"b": 2, "a": 1}), canonical_json({"a": 1, "b": 2}))

    def test_fps_parser_rejects_nonfinite_and_nonpositive_values(self):
        self.assertEqual(finite_positive_float("29.97"), 29.97)
        for value in ("nan", "inf", "+inf", "-inf", "0", "-1"):
            with self.subTest(value=value):
                with self.assertRaisesRegex(
                    pilot_builder.argparse.ArgumentTypeError, "finite positive"
                ):
                    finite_positive_float(value)

    def test_cli_rejects_nonfinite_fps_before_snapshot_or_publication(self):
        with tempfile.TemporaryDirectory() as temporary:
            for value in ("nan", "inf", "-inf"):
                output = Path(temporary) / f"{value}.usdz"
                with self.subTest(value=value), mock.patch.object(
                    pilot_builder,
                    "snapshot_verified_files",
                    side_effect=AssertionError("snapshot must not run"),
                ), redirect_stderr(io.StringIO()):
                    with self.assertRaises(SystemExit) as raised:
                        pilot_builder.main(
                            ["missing-input", "missing-converter", str(output), "--fps", value]
                        )
                self.assertEqual(raised.exception.code, 2)
                self.assertFalse(output.exists())

    def test_run_converter_defensively_rejects_nonfinite_fps(self):
        for value in (float("nan"), float("inf"), -float("inf")):
            with self.subTest(value=value):
                with self.assertRaisesRegex(RuntimeError, "finite and positive"):
                    pilot_builder.run_converter(
                        Path("unread.py"), Path("unread.gltf"), Path("unwritten.usdc"), value
                    )

    def test_verified_snapshot_is_immutable_after_live_tree_mutation(self):
        payload = b"locked Rocketbox fixture bytes"
        record = AssetRecord(
            "nested/payload.bin",
            len(payload),
            hashlib.sha256(payload).hexdigest(),
            "TOCTOU fixture",
        )
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            live = root / "live"
            source = live / record.path
            source.parent.mkdir(parents=True)
            source.write_bytes(payload)
            snapshot = snapshot_verified_files(live, root / "snapshot", [record])
            source.write_bytes(b"mutated after verified snapshot")
            self.assertEqual((snapshot / record.path).read_bytes(), payload)

    def test_verified_snapshot_rejects_unverified_source_bytes(self):
        payload = b"expected"
        record = AssetRecord(
            "payload.bin",
            len(payload),
            hashlib.sha256(payload).hexdigest(),
            "mutation fixture",
        )
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            live = root / "live"
            live.mkdir()
            (live / record.path).write_bytes(b"tampered")
            with self.assertRaisesRegex(RuntimeError, "SHA-256 changed"):
                snapshot_verified_files(live, root / "snapshot", [record])

    @unittest.skipUnless(hasattr(os, "mkfifo"), "FIFO fixtures unsupported")
    def test_verified_snapshot_rejects_fifo_without_blocking(self):
        record = AssetRecord(
            "payload.bin",
            1,
            hashlib.sha256(b"x").hexdigest(),
            "FIFO fixture",
        )
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            live = root / "live"
            live.mkdir()
            os.mkfifo(live / record.path)
            with self.assertRaisesRegex(RuntimeError, "not a regular file"):
                snapshot_verified_files(live, root / "snapshot", [record])

    @unittest.skipUnless(Path("/dev/zero").exists(), "/dev/zero unavailable")
    def test_verified_snapshot_rejects_symlink_to_unbounded_device(self):
        record = AssetRecord(
            "payload.bin",
            1,
            hashlib.sha256(b"x").hexdigest(),
            "device fixture",
        )
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            live = root / "live"
            live.mkdir()
            (live / record.path).symlink_to("/dev/zero")
            with self.assertRaisesRegex(RuntimeError, "safely open|not a regular file"):
                snapshot_verified_files(live, root / "snapshot", [record])

    def test_verified_snapshot_bounds_oversized_source_read(self):
        payload = b"expected"
        record = AssetRecord(
            "payload.bin",
            len(payload),
            hashlib.sha256(payload).hexdigest(),
            "oversized fixture",
        )
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            live = root / "live"
            live.mkdir()
            source = live / record.path
            with source.open("wb") as handle:
                handle.write(payload)
                handle.seek(64 * 1024 * 1024)
                handle.write(b"x")

            real_read = os.read
            bytes_returned: list[int] = []

            def tracked_read(descriptor, count):
                chunk = real_read(descriptor, count)
                bytes_returned.append(len(chunk))
                return chunk

            with mock.patch.object(pilot_builder.os, "read", side_effect=tracked_read):
                with self.assertRaisesRegex(RuntimeError, "size changed"):
                    snapshot_verified_files(live, root / "snapshot", [record])
            self.assertLessEqual(sum(bytes_returned), record.byte_count + 1)
            self.assertFalse((root / "snapshot" / record.path).exists())
            self.assertEqual(list((root / "snapshot").glob(".*.snapshot")), [])

    def test_exact_microsoft_mit_notice_is_locked_and_loaded(self):
        self.assertEqual(
            hashlib.sha256(MICROSOFT_MIT_NOTICE.encode()).hexdigest(),
            EXPECTED_MICROSOFT_MIT_NOTICE_SHA256,
        )
        self.assertIn("Copyright (c) 2020 Microsoft", MICROSOFT_MIT_NOTICE)
        self.assertIn("THE SOFTWARE IS PROVIDED \"AS IS\"", MICROSOFT_MIT_NOTICE)
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            (root / "LICENSE.md").write_text(MICROSOFT_MIT_NOTICE)
            self.assertEqual(load_microsoft_mit_notice(root), MICROSOFT_MIT_NOTICE)
            (root / "LICENSE.md").write_text(MICROSOFT_MIT_NOTICE + "tampered\n")
            with self.assertRaisesRegex(RuntimeError, "notice hash changed"):
                load_microsoft_mit_notice(root)

    def test_publication_rejects_report_path_aliases_and_hardlinks(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            output = root / "pilot.usdz"
            output.write_bytes(b"asset")
            with self.assertRaisesRegex(RuntimeError, "aliases"):
                validate_publication_paths(output, output)
            with self.assertRaisesRegex(RuntimeError, "aliases"):
                validate_publication_paths(output, root / "folder" / ".." / "pilot.usdz")
            report = root / "report.json"
            os.link(output, report)
            with self.assertRaisesRegex(RuntimeError, "hardlink"):
                validate_publication_paths(output, report)

    def test_main_rejects_report_collision_before_input_or_publication(self):
        with tempfile.TemporaryDirectory() as temporary:
            output = Path(temporary) / "pilot.usdz"
            with mock.patch.object(
                pilot_builder,
                "snapshot_verified_files",
                side_effect=AssertionError("input snapshot must not run"),
            ):
                with self.assertRaisesRegex(RuntimeError, "aliases"):
                    pilot_builder.main(
                        ["missing-input", "missing-converter", str(output), "--report", str(output)]
                    )
            self.assertFalse(output.exists())

    def test_publication_refuses_symlink_destination_and_preserves_target(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            target = root / "target.bin"
            target.write_bytes(b"untouched")
            destination = root / "pilot.usdz"
            destination.symlink_to(target)
            with self.assertRaisesRegex(RuntimeError, "must not be a symlink"):
                publish_bytes_exclusive(b"replacement", destination)
            self.assertEqual(target.read_bytes(), b"untouched")

    def test_publication_uses_and_cleans_exclusive_random_temporary(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            destination = root / "pilot.usdz"
            publish_bytes_exclusive(b"first", destination)
            publish_bytes_exclusive(b"second", destination)
            self.assertEqual(destination.read_bytes(), b"second")
            self.assertEqual(list(root.glob(".pilot.usdz.*.tmp")), [])

    def test_case_variant_report_cannot_replace_published_usdz_when_supported(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            probe = root / "CaseProbe"
            probe.write_bytes(b"probe")
            case_insensitive = (root / "caseprobe").exists()
            probe.unlink()
            if not case_insensitive:
                self.skipTest("temporary filesystem is case-sensitive")

            output = root / "ReplayPilot.usdz"
            report = root / "replaypilot.usdz"
            candidate = root / "candidate.usdz"
            candidate.write_bytes(b"validated USDZ bytes")
            try:
                validate_publication_paths(output, report)
            except RuntimeError:
                self.skipTest("platform detects missing case aliases before publication")
            with self.assertRaises(RuntimeError):
                publish_asset_and_report(candidate, output, report, b'{"report":true}\n')
            self.assertEqual(output.read_bytes(), b"validated USDZ bytes")

    def test_converter_execution_hash_rejects_bytecode_and_cache(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            source = root / "Source"
            source.mkdir()
            (source / "gltf2usd.py").write_text("print('safe')\n")
            first = gltf2usd_source_hash(root)
            self.assertEqual(first, gltf2usd_source_hash(root))
            cache = source / "__pycache__"
            cache.mkdir()
            (cache / "gltf2usd.cpython-312.pyc").write_bytes(b"unchecked executable")
            with self.assertRaisesRegex(RuntimeError, "bytecode/cache"):
                gltf2usd_source_hash(root)

    @unittest.skipUnless(
        PINNED_GLTF2USD_ROOT.is_dir(), "pinned gltf2usd fixture unavailable"
    )
    def test_converter_copy_is_minimal_hashed_and_rechecked_before_run(self):
        self.assertEqual(
            gltf2usd_source_hash(PINNED_GLTF2USD_ROOT),
            EXPECTED_GLTF2USD_SOURCE_HASH,
        )
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            live = root / "live-converter"
            shutil.copytree(PINNED_GLTF2USD_ROOT / "Source", live / "Source")
            isolated = root / "private-converter"
            entry = patch_converter(live, isolated)
            self.assertEqual(
                gltf2usd_source_hash(isolated),
                EXPECTED_PATCHED_GLTF2USD_SOURCE_HASH,
            )
            self.assertFalse((isolated / "Source/tests").exists())
            self.assertEqual(list((isolated / "Source").rglob("*.pyc")), [])
            live_entry = live / "Source/gltf2usd.py"
            live_entry.write_text(live_entry.read_text() + "\n# live tree mutated\n")
            self.assertEqual(
                gltf2usd_source_hash(isolated),
                EXPECTED_PATCHED_GLTF2USD_SOURCE_HASH,
            )
            with mock.patch.object(pilot_builder, "_run") as converter_process:
                pilot_builder.run_converter(
                    entry,
                    root / "fixture.gltf",
                    root / "fixture.usdc",
                    30.0,
                )
            converter_process.assert_called_once()

            entry.write_text(entry.read_text() + "\n# tampered after copy\n")
            with self.assertRaisesRegex(RuntimeError, "changed before launch"):
                pilot_builder.run_converter(
                    entry,
                    root / "never-read.gltf",
                    root / "never-written.usdc",
                    30.0,
                )

    def test_skinning_array_audit_accepts_normalized_fixture(self):
        report = validate_skinning_arrays(
            label="fixture",
            point_count=2,
            joint_count=3,
            influences_per_point=2,
            indices=[0, 1, 1, 2],
            weights=[0.75, 0.25, 0.4, 0.6],
        )
        self.assertEqual(report["jointIndices"], 4)
        self.assertLess(report["maximumWeightSumError"], 1e-9)

    def test_skinning_array_audit_rejects_bad_cardinality_indices_and_weights(self):
        base = dict(
            label="fixture",
            point_count=1,
            joint_count=2,
            influences_per_point=2,
        )
        with self.assertRaisesRegex(RuntimeError, "cardinality"):
            validate_skinning_arrays(**base, indices=[0], weights=[1.0])
        with self.assertRaisesRegex(RuntimeError, "joint index"):
            validate_skinning_arrays(**base, indices=[0, 2], weights=[0.5, 0.5])
        with self.assertRaisesRegex(RuntimeError, "joint index"):
            validate_skinning_arrays(
                **base, indices=[0, float("inf")], weights=[0.5, 0.5]
            )
        with self.assertRaisesRegex(RuntimeError, "joint weight"):
            validate_skinning_arrays(**base, indices=[0, 1], weights=[float("nan"), 1.0])
        with self.assertRaisesRegex(RuntimeError, "not normalized"):
            validate_skinning_arrays(**base, indices=[0, 1], weights=[0.2, 0.2])

    @unittest.skipUnless(
        os.environ.get("REPLAYXI_ROCKETBOX_INTEGRATION_ASSET"),
        "set REPLAYXI_ROCKETBOX_INTEGRATION_ASSET to audit a built package",
    )
    def test_packaged_asset_has_two_valid_mesh_skinning_queries(self):
        report = audit_usd_skinning(
            Path(os.environ["REPLAYXI_ROCKETBOX_INTEGRATION_ASSET"]),
            MICROSOFT_MIT_NOTICE,
        )
        self.assertEqual(report["joints"], 80)
        self.assertEqual(report["boundMeshes"], 2)
        self.assertEqual(
            {mesh["points"] for mesh in report["meshes"].values()}, {1724, 3288}
        )


if __name__ == "__main__":
    unittest.main()
    finite_positive_float,
