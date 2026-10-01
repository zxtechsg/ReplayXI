"""Bounded fail-closed checks for the offline Tripo native asset build."""
from __future__ import annotations

import copy
import hashlib
import json
from pathlib import Path
import struct
import sys
import tempfile
import unittest

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
try:
    import numpy as np
    from build_replayxi_rocketbox_pilot import read_accessor
    from build_replayxi_tripo_athlete import glb, inspect_skin, mesh_data, sha
    AVAILABLE = True
except ImportError:
    AVAILABLE = False

REPO = Path(__file__).resolve().parents[2]
SOURCE = REPO / "Assets/ReplayXI/TripoFootballer/ReplayXI_Footballer_P2_Source.glb"
FBX_SOURCE = REPO / ".codex-derived/replayxi-tripo164/fbx-player-v2/ReplayXITripoFBXCandidate.glb"
NEAR = REPO / ".codex-derived/replayxi-tripo164/fbx-lods-v2/ReplayXITripoFBX_Near_1m.glb"
NATIVE = REPO / ".codex-derived/replayxi-tripo164/native-v4"
KITS = REPO / ".codex-derived/replayxi-tripo164/kits-v1"
EXPECTED_NATIVE_SHA256 = {
    "ReplayXITripoAthlete.usdz": "af01e0ea9e8e4ae6d9dae068f87fe03f1550732583a553eb64660ce1bd6afe90",
    "ReplayXITripoLow.usdz": "48712cb85bc92c798fd7c6dc53ef721f43a0797db7739facd61f30449e80b390",
    "ReplayXITripoMotion.json": "877857959a46e2ea1c47de3fbbf5822ff8e774d20c973f1e9eade55ff578a84f",
    "ReplayXITripoContactSurface.json": "ae384cf32679b5f57851a5b10032ba0fc41892605c98c81030ba77104ba8007e",
    "ReplayXITripoLowContactSurface.json": "f12a6d033535790654af6c75b80c8afb5decf4c2125cc12a0a1dd2a18bc1aa92",
}
JPEG = REPO / (".codex-derived/replayxi-tripo164/fbx-source/"
               "tripo_convert_e7d9fe2a-ac2d-497b-a733-92e3003ca9bb.fbm/"
               "tripo_rgb_fc71fa8e-e587-43f5-9823-bc929ad4bac6.jpg")


def image_bytes(document, binary):
    image = document["images"][0]
    view = document["bufferViews"][image["bufferView"]]
    start = view.get("byteOffset", 0)
    return binary[start:start + view["byteLength"]]


def uv_positions(document, binary):
    primitive = document["meshes"][0]["primitives"][0]
    attributes = primitive["attributes"]
    positions = np.asarray(read_accessor(document, binary, attributes["POSITION"]))
    uvs = np.asarray(read_accessor(document, binary, attributes["TEXCOORD_0"]))
    return positions, uvs


@unittest.skipUnless(AVAILABLE and NEAR.is_file(), "Tripo GLB and Blender Python required")
class ConverterRejectsInvalidInputs(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.document, cls.binary = glb(NEAR)

    def test_wrong_joint_count_is_rejected(self):
        document = copy.deepcopy(self.document)
        document["skins"][0]["joints"].pop()
        with self.assertRaisesRegex(ValueError, "52-joint"):
            inspect_skin(document, self.binary)

    def test_non_normalized_weight_is_rejected(self):
        document = self.document
        primitive = document["meshes"][0]["primitives"][0]
        accessor = document["accessors"][primitive["attributes"]["WEIGHTS_0"]]
        view = document["bufferViews"][accessor["bufferView"]]
        self.assertEqual(accessor["componentType"], 5126)
        binary = bytearray(self.binary)
        struct.pack_into("<f", binary, view.get("byteOffset", 0) + accessor.get("byteOffset", 0), 3.0)
        with self.assertRaisesRegex(ValueError, "unnormalized skin weights"):
            mesh_data(document, binary, inspect_skin(document, binary), 1)

    def test_mismatched_inverse_bind_is_rejected(self):
        document = self.document
        accessor = document["accessors"][document["skins"][0]["inverseBindMatrices"]]
        view = document["bufferViews"][accessor["bufferView"]]
        binary = bytearray(self.binary)
        start = view.get("byteOffset", 0) + accessor.get("byteOffset", 0)
        old = struct.unpack_from("<f", binary, start + 48)[0]
        struct.pack_into("<f", binary, start + 48, old + 0.1)
        with self.assertRaisesRegex(ValueError, "inverse binds differ"):
            inspect_skin(document, binary)

    def test_unsupported_two_material_source_is_rejected(self):
        document = copy.deepcopy(self.document)
        document["materials"].append(copy.deepcopy(document["materials"][0]))
        with self.assertRaisesRegex(ValueError, "one PBR material"):
            inspect_skin(document, self.binary)

    def test_corrupt_glb_header_is_rejected(self):
        with tempfile.TemporaryDirectory(prefix="replayxi-tripo-test-") as directory:
            path = Path(directory) / "bad.glb"
            path.write_bytes(b"bad GLB")
            with self.assertRaisesRegex(ValueError, "invalid GLB"):
                glb(path)


@unittest.skipUnless(AVAILABLE and NATIVE.is_dir(), "native-v4 artifacts required")
class NativeOutputContract(unittest.TestCase):
    def test_report_hashes_counts_and_contact_bindings(self):
        report = json.loads((NATIVE / "ReplayXITripoBuildReport.json").read_text())
        self.assertEqual(report["assets"]["near"]["vertices"], 9075)
        self.assertEqual(report["assets"]["near"]["triangles"], 7685)
        self.assertEqual(report["assets"]["low"]["vertices"], 3269)
        self.assertEqual(report["assets"]["low"]["triangles"], 1964)
        self.assertEqual(report["assets"]["near"]["drawCalls"], 1)
        self.assertEqual(report["assets"]["low"]["drawCalls"], 1)
        self.assertEqual(report["sourceHashes"]["sourceArchive"],
                         "32f79b8f58897d98e486e29890c279b14c90e5b39e8b9ced44134ff23a7166ba")
        self.assertEqual(set(report["files"]), set(EXPECTED_NATIVE_SHA256))
        for name, recorded in report["files"].items():
            path = NATIVE / name
            self.assertTrue(path.is_file(), name)
            self.assertEqual(path.stat().st_size, recorded["bytes"])
            self.assertEqual(sha(path), recorded["sha256"])
            self.assertEqual(sha(path), EXPECTED_NATIVE_SHA256[name])
        motion = json.loads((NATIVE / "ReplayXITripoMotion.json").read_text())
        names = [joint["name"] for joint in motion["joints"]]
        self.assertEqual(len(names), 52)
        self.assertAlmostEqual(motion["geometry"]["nominalHeight"], 1.82, places=7)
        for label, filename, asset in (
            ("near", "ReplayXITripoContactSurface.json", "ReplayXITripoAthlete.usdz"),
            ("low", "ReplayXITripoLowContactSurface.json", "ReplayXITripoLow.usdz"),
        ):
            contact = json.loads((NATIVE / filename).read_text())
            self.assertEqual(contact["schemaVersion"], 1)
            self.assertEqual(contact["sourceVertexCount"], report["assets"][label]["vertices"])
            self.assertEqual(contact["jointCount"], 52)
            self.assertEqual(len(contact["vertices"]), 512)
            self.assertEqual(contact["assetSHA256"], sha(NATIVE / asset))
            self.assertEqual(contact["motionSHA256"], sha(NATIVE / "ReplayXITripoMotion.json"))
        self.assertLessEqual(max(row["scaledBlenderMaximumErrorMetres"]
                                 for row in report["poseBounds"]), 8e-6)
        self.assertEqual(report["normalMode"], "area-weighted")
        self.assertEqual(report["atlasProvenance"]["matchedUniqueUVCoordinates"], 16699)
        self.assertEqual(report["atlasProvenance"]["sourceJPEG_SHA256"], sha(JPEG))
        self.assertLessEqual(max(report["numberPanel"]["outwardOffsetsMetres"].values()), .04)
        for side in ("front", "back"):
            self.assertLessEqual(report["numberPanel"]["after"][side]["maximumClothDepthMetres"], -.00999)
        self.assertEqual(report["contactSummary"]["near"]["weightedHeadProbes"], 96)
        self.assertEqual(report["contactSummary"]["low"]["weightedHeadProbes"], 96)
        self.assertGreaterEqual(report["contactSummary"]["near"]["weightedHeadSourceCandidates"], 96)
        self.assertGreaterEqual(report["contactSummary"]["low"]["weightedHeadSourceCandidates"], 96)
        for side in ("near", "low"):
            low = report["contactSummary"][side]["headProbeBoundsMin"]
            high = report["contactSummary"][side]["headProbeBoundsMax"]
            self.assertGreater(high[0] - low[0], .18)
            self.assertGreater(high[1] - low[1], .18)
            self.assertGreater(high[2] - low[2], .20)


@unittest.skipUnless(AVAILABLE and all(path.is_file() for path in (SOURCE, FBX_SOURCE, JPEG, KITS / "report.json")),
                     "source atlas and kit artifacts required")
class KitAtlasContract(unittest.TestCase):
    def test_glb_and_fbx_atlas_bytes_and_uv_locations_agree(self):
        original, original_binary = glb(SOURCE)
        fbx, fbx_binary = glb(FBX_SOURCE)
        self.assertEqual(image_bytes(original, original_binary), JPEG.read_bytes())
        self.assertEqual(image_bytes(fbx, fbx_binary), JPEG.read_bytes())
        original_points, original_uv = uv_positions(original, original_binary)
        fbx_points, fbx_uv = uv_positions(fbx, fbx_binary)
        self.assertEqual(len(original_points), len(fbx_points))
        original_map = {tuple(np.round(uv, 6)): point for point, uv in zip(original_points, original_uv)}
        fbx_map = {tuple(np.round(uv, 6)): point for point, uv in zip(fbx_points, fbx_uv)}
        self.assertEqual(set(original_map), set(fbx_map))
        maximum_error = max(np.max(abs(original_map[uv] - fbx_map[uv])) for uv in original_map)
        self.assertLessEqual(maximum_error, 2e-6)

    def test_three_baked_kits_share_source_uv_and_match_report_hashes(self):
        report = json.loads((KITS / "report.json").read_text())
        self.assertEqual(report["sourceSHA256"], sha(SOURCE))
        self.assertTrue(report["sameGeometryForBothTeams"])
        self.assertEqual({row["kit"] for row in report["textures"]}, {"home", "away", "keeper"})
        for row in report["textures"]:
            image = KITS / row["texture"]
            payload = image.read_bytes()
            self.assertEqual(hashlib.sha256(payload).hexdigest(), row["sha256"])
            self.assertEqual(payload[:8], b"\x89PNG\r\n\x1a\n")
            self.assertEqual(struct.unpack_from(">II", payload, 16), (2048, 2048))


if __name__ == "__main__":
    unittest.main()
