"""Pure-stdlib audit of staged seed exports; no Blender import or app build.

Staged-only: build fresh Build04/Build05 with build_chisel_stadium179.py, then:
  python3 Scripts/tests/test_chisel_stadium179.py -v
Use --seed-dir / --repro-dir for other fresh directories. Export tests skip
without both generated fixtures; only the two clipping unit tests then run.
"""
import argparse
import hashlib
import json
import math
from pathlib import Path
import struct
import sys
import unittest

ROOT = Path(__file__).resolve().parents[2]
STAGING = ROOT / ".replayxi-world-staging/Chisel179/Seed"
SEED, REPRO = STAGING / "Build04", STAGING / "Build05"


def read_glb(path):
    blob = path.read_bytes()
    if struct.unpack_from("<4sII", blob) != (b"glTF", 2, len(blob)):
        raise ValueError("Invalid GLB header")
    size, kind = struct.unpack_from("<I4s", blob, 12)
    if kind != b"JSON":
        raise ValueError("Missing GLB JSON")
    document = json.loads(blob[20:20 + size])
    length, kind = struct.unpack_from("<I4s", blob, 20 + size)
    if kind != b"BIN\0":
        raise ValueError("Missing embedded geometry")
    return document, blob[28 + size:28 + size + length]


def accessor(document, binary, index):
    info = document["accessors"][index]
    view = document["bufferViews"][info["bufferView"]]
    code = {5123: "H", 5125: "I", 5126: "f"}[info["componentType"]]
    width = {"SCALAR": 1, "VEC2": 2, "VEC3": 3}[info["type"]]
    fmt = "<" + code * width
    offset = view.get("byteOffset", 0) + info.get("byteOffset", 0)
    stride = view.get("byteStride", struct.calcsize(fmt))
    return [struct.unpack_from(fmt, binary, offset + i * stride) for i in range(info["count"])]


def touches_pitch(points):
    """Independent clipping check, including projected walls and bridge faces."""
    polygon = [(p[0], p[2]) for p in points]
    for axis, sign, limit in ((0, 1, 35.9999), (0, -1, 35.9999),
                              (1, 1, 55.9999), (1, -1, 55.9999)):
        if not polygon:
            return False
        clipped = []
        for start, end in zip(polygon, polygon[1:] + polygon[:1]):
            a, b = sign * start[axis] - limit, sign * end[axis] - limit
            if a <= 0:
                clipped.append(start)
            if (a <= 0) != (b <= 0):
                t = a / (a - b)
                clipped.append(tuple(start[i] + t * (end[i] - start[i]) for i in range(2)))
        polygon = clipped
    return bool(polygon)


class PitchClipTests(unittest.TestCase):
    def test_overhead_bridge_is_rejected_even_with_all_vertices_outside(self):
        self.assertTrue(touches_pitch([(-60, 20, 0), (60, 20, 0), (0, 20, 80)]))
        self.assertTrue(touches_pitch([(0, 0, 0), (0, 5, 0), (0, 10, 0)]))

    def test_boundary_wall_and_diagonal_corner_are_clear(self):
        self.assertFalse(touches_pitch([(36, 0, -60), (36, 20, 60), (40, 0, 0)]))
        self.assertFalse(touches_pitch([(35, 0, 59), (39, 10, 55), (45, 0, 65)]))


class ExportTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        if not (SEED / "OriginalStadium179.glb").is_file() or not (REPRO / "OriginalStadium179.glb").is_file():
            raise unittest.SkipTest("Two staged seed exports are required; see --seed-dir / --repro-dir")
        cls.document, cls.binary = read_glb(SEED / "OriginalStadium179.glb")

    def test_exact_container_scope_and_embedded_dependencies(self):
        d = self.document
        self.assertEqual(len(d["meshes"]), 1)
        self.assertEqual(len(d["materials"]), 4)
        self.assertEqual(len(d["cameras"]), 5)
        self.assertEqual(len(d["meshes"][0]["primitives"]), 4)
        self.assertEqual(len(d["nodes"]), 6, "No startup cube, pitch helper, or lights")
        self.assertFalse(d.get("skins") or d.get("animations"))
        self.assertTrue(all(mat.get("doubleSided", False) for mat in d["materials"]))
        self.assertFalse(any(item.get("uri") for item in d.get("buffers", []) + d.get("images", [])))
        mesh_nodes = [n for n in d["nodes"] if "mesh" in n]
        self.assertEqual(len(mesh_nodes), 1)
        self.assertFalse(any(key in mesh_nodes[0] for key in ("matrix", "translation", "rotation", "scale")))

    def test_actual_exported_triangles_leave_the_pitch_clear(self):
        positions, triangles, used_materials = [], 0, set()
        for part in self.document["meshes"][0]["primitives"]:
            self.assertEqual(part.get("mode", 4), 4)
            self.assertIn("TEXCOORD_0", part["attributes"])
            points = accessor(self.document, self.binary, part["attributes"]["POSITION"])
            indices = [x[0] for x in accessor(self.document, self.binary, part["indices"])]
            self.assertEqual(len(indices) % 3, 0)
            self.assertTrue(all(all(math.isfinite(v) for v in p) for p in points))
            for offset in range(0, len(indices), 3):
                face = [points[i] for i in indices[offset:offset + 3]]
                self.assertFalse(touches_pitch(face), f"Pitch intrusion at part {part['material']}, triangle {offset // 3}")
            triangles += len(indices) // 3
            positions.extend(points)
            used_materials.add(part["material"])
        self.assertEqual(triangles, 20_432)
        self.assertEqual(used_materials, {0, 1, 2, 3})
        report = json.loads((SEED / "stats.json").read_text())
        self.assertEqual(report["triangles"], triangles)
        for axis in range(3):
            self.assertAlmostEqual(min(p[axis] for p in positions), report["nativeBounds"]["min"][axis], places=4)
            self.assertAlmostEqual(max(p[axis] for p in positions), report["nativeBounds"]["max"][axis], places=4)

    def test_five_native_camera_placements(self):
        cameras = {n["name"]: n for n in self.document["nodes"] if "camera" in n}
        targets = {"Pitch North native -Z": (0, 3.8, -70), "Pitch East native +X": (60, 3.8, 0),
                   "Pitch South native +Z": (0, 3.8, 70), "Pitch West native -X": (-60, 3.8, 0)}
        for name, direction in targets.items():
            self.assertEqual(len(cameras[name]["rotation"]), 4)
            for actual, expected in zip(cameras[name]["translation"], (0, 1.7, 0)):
                self.assertAlmostEqual(actual, expected, places=5)
            x, y, z, w = cameras[name]["rotation"]
            forward = (-2 * (x * z + w * y), -2 * (y * z - w * x), -(1 - 2 * (x * x + y * y)))
            magnitude = math.sqrt(sum(v * v for v in direction))
            self.assertGreater(sum(a * b / magnitude for a, b in zip(forward, direction)), 0.99999)
        self.assertEqual(cameras["Elevated overview"]["translation"], [122, 125, 154])

    def test_closed_steel_beams_have_outward_winding(self):
        # Signed volume is positive for closed outward-facing geometry.
        volume = 0
        for part in self.document["meshes"][0]["primitives"]:
            if part["material"] != 3:
                continue
            points = accessor(self.document, self.binary, part["attributes"]["POSITION"])
            indices = [x[0] for x in accessor(self.document, self.binary, part["indices"])]
            for offset in range(0, len(indices), 3):
                a, b, c = [points[i] for i in indices[offset:offset + 3]]
                volume += (a[0] * (b[1] * c[2] - b[2] * c[1])
                           + a[1] * (b[2] * c[0] - b[0] * c[2])
                           + a[2] * (b[0] * c[1] - b[1] * c[0])) / 6
        self.assertGreater(volume, 200, "Inward beam faces can be hidden by double-sided shading")

    def test_fresh_export_is_byte_exact_and_stats_match(self):
        first, second = (SEED / "OriginalStadium179.glb").read_bytes(), (REPRO / "OriginalStadium179.glb").read_bytes()
        self.assertEqual(first, second)
        a, b = json.loads((SEED / "stats.json").read_text()), json.loads((REPRO / "stats.json").read_text())
        a.pop("glb")
        b.pop("glb")
        self.assertEqual(a, b)
        self.assertEqual(a["sha256"], hashlib.sha256(first).hexdigest())
        self.assertLess(len(first), 12_000_000)


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--seed-dir", type=Path, default=SEED)
    parser.add_argument("--repro-dir", type=Path, default=REPRO)
    args, remaining = parser.parse_known_args()
    SEED, REPRO = args.seed_dir, args.repro_dir
    unittest.main(argv=[sys.argv[0]] + remaining)
