#!/usr/bin/env python3
"""Repair missing glTF joint rest transforms in a derived Tripo AutoRig GLB.

The source has nonidentity inverseBindMatrices but identity joint nodes. glTF
rest skinning therefore moves the mesh. This writes local joint matrices whose
global bind transforms invert the original inverse binds. No mesh/UV/skin data
is changed. Input is never modified; output must be a new derived GLB.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import math
from pathlib import Path
import struct
import sys

from mathutils import Matrix

REPO = Path(__file__).resolve().parents[2]


def sha(payload):
    return hashlib.sha256(payload).hexdigest()


def read_glb(payload):
    magic, version, length, json_size, json_kind = struct.unpack_from("<IIIII", payload)
    if (magic, version, length, json_kind) != (0x46546C67, 2, len(payload), 0x4E4F534A):
        raise ValueError("Invalid input GLB")
    binary_offset = 20 + json_size
    binary_size, binary_kind = struct.unpack_from("<II", payload, binary_offset)
    if binary_kind != 0x004E4942 or binary_offset + 8 + binary_size != len(payload):
        raise ValueError("Invalid GLB binary chunk")
    return json.loads(payload[20:binary_offset]), payload[binary_offset + 8:]


def inverse_binds(document, binary):
    if len(document.get("skins", [])) != 1:
        raise ValueError("Expected one source skin")
    skin = document["skins"][0]
    accessor = document["accessors"][skin["inverseBindMatrices"]]
    view = document["bufferViews"][accessor["bufferView"]]
    if accessor["type"] != "MAT4" or accessor["componentType"] != 5126 or accessor["count"] != len(skin["joints"]):
        raise ValueError("Unsupported source inverse-bind accessor")
    start = view.get("byteOffset", 0) + accessor.get("byteOffset", 0)
    stride = view.get("byteStride", 64)
    result = []
    for index in range(accessor["count"]):
        values = struct.unpack_from("<16f", binary, start + index * stride)
        if not all(math.isfinite(value) for value in values):
            raise ValueError("Nonfinite inverse bind")
        matrix = Matrix([values[offset:offset + 4] for offset in range(0, 16, 4)]).transposed()
        if abs(matrix.determinant()) < 1e-8:
            raise ValueError("Singular inverse bind")
        result.append(matrix)
    return result


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--input", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args(sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else [])
    input_path, output = args.input.resolve(), args.output.resolve()
    if not input_path.is_file() or output.exists() or not output.is_relative_to((REPO / ".codex-derived").resolve()):
        raise ValueError("Input must exist; output must be new and derived")
    payload = input_path.read_bytes()
    document, binary = read_glb(payload)
    skin = document["skins"][0]
    joints = skin["joints"]
    if len(joints) != 52 or len(set(joints)) != 52:
        raise ValueError("Expected distinct 52-joint Tripo source")
    if any(any(key in document["nodes"][node] for key in ("matrix", "translation", "rotation", "scale"))
           for node in joints):
        raise ValueError("Source already has joint transforms; no repair needed")
    inverse = inverse_binds(document, binary)
    global_bind = {node: matrix.inverted() for node, matrix in zip(joints, inverse)}
    parents = {child: index for index, node in enumerate(document["nodes"])
               for child in node.get("children", [])}
    max_error = 0.0
    for node in joints:
        parent = parents.get(node)
        while parent is not None and parent not in global_bind:
            # The source's nonjoint RootNode/Armature nodes have identity transforms.
            if any(key in document["nodes"][parent] for key in ("matrix", "translation", "rotation", "scale")):
                raise ValueError("Unexpected transformed nonjoint ancestor")
            parent = parents.get(parent)
        local = global_bind[parent].inverted() @ global_bind[node] if parent is not None else global_bind[node]
        document["nodes"][node]["matrix"] = [float(value) for column in local.transposed() for value in column]
        reconstructed = (global_bind[parent] @ local if parent is not None else local) @ inverse[joints.index(node)]
        max_error = max(max_error, max(abs(reconstructed[row][column] - (1 if row == column else 0))
                                       for row in range(4) for column in range(4)))
    if max_error > 1e-5:
        raise ValueError("Repaired bind is not identity at rest")
    json_chunk = json.dumps(document, separators=(",", ":"), ensure_ascii=False).encode()
    json_chunk += b" " * ((-len(json_chunk)) % 4)
    result = (struct.pack("<III", 0x46546C67, 2, 12 + 8 + len(json_chunk) + 8 + len(binary))
              + struct.pack("<II", len(json_chunk), 0x4E4F534A) + json_chunk
              + struct.pack("<II", len(binary), 0x004E4942) + binary)
    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_bytes(result)
    if sha(input_path.read_bytes()) != sha(payload):
        raise ValueError("Input changed during repair")
    report = {"input": str(input_path), "inputSHA256": sha(payload),
              "output": str(output), "outputSHA256": sha(result),
              "jointCount": len(joints), "meshBinaryUnchanged": True,
              "maximumRestSkinMatrixError": max_error, "candidateOnly": True}
    (output.parent / "bind-repair-report.json").write_text(json.dumps(report, indent=2) + "\n")
    print("REPLAYXI_TRIPO_BIND_REPAIR " + json.dumps(report))


if __name__ == "__main__":
    main()
