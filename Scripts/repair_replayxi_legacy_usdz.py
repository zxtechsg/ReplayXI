#!/usr/bin/env python3
"""Repair the known joint-topology defect in Replay XI's legacy USDZ fixture.

This is intentionally not a general USD editor.  It accepts only the audited
Quaternius model hash and only the exact flattened joint order emitted by the
pinned kcoley/gltf2usd converter.  The repair restores hierarchical joint
paths, gives each separately skinned mesh a unique root namespace, and removes
the converter's redundant animated Xform copy of the joint graph.

The long-term production path remains a modern DCC export with one shared
skeleton and authored LODs.  This narrow repair exists so the current CC0
technical fixture can be validated visually without installing Blender or
another converter.
"""

from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path
import re
import shutil
import struct
import subprocess
import tempfile
import zipfile

from replayxi_usdz_archive import normalize_usdz_timestamps, validated_archive_names


MODEL_SHA256 = "a466828c67a4acc9b2413212ce6d9cde235e3aed9b675680c14fd9673858f118"
USDCAT = Path("/usr/bin/usdcat")
USDZIP = Path("/usr/bin/usdzip")
USDCHECKER = Path("/usr/bin/usdchecker")


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def load_glb_json(path: Path) -> dict[str, object]:
    payload = path.read_bytes()
    if len(payload) < 20:
        raise ValueError(f"truncated GLB: {path}")
    magic, version, declared_length = struct.unpack_from("<4sII", payload, 0)
    if magic != b"glTF" or version != 2 or declared_length != len(payload):
        raise ValueError(f"invalid GLB 2.0 header: {path}")
    offset = 12
    while offset < len(payload):
        length, chunk_type = struct.unpack_from("<II", payload, offset)
        offset += 8
        chunk = payload[offset : offset + length]
        offset += length
        if chunk_type == 0x4E4F534A:
            return json.loads(chunk.rstrip(b"\x00 \t\r\n"))
    raise ValueError(f"GLB has no JSON chunk: {path}")


def _converter_node_name(node: dict[str, object], index: int) -> str:
    source = str(node.get("name") or f"node_{index}")
    candidate = f"{source}_{index}"
    # The locked fixture uses ASCII identifiers already.  Refuse to guess how
    # Tf.MakeValidIdentifier would rewrite a different source model.
    if not re.fullmatch(r"[A-Za-z_][A-Za-z0-9_]*", candidate):
        raise ValueError(f"unsupported source joint identifier: {candidate!r}")
    return candidate


def derive_joint_paths(gltf: dict[str, object]) -> list[str]:
    nodes = gltf.get("nodes")
    skins = gltf.get("skins")
    if not isinstance(nodes, list) or not isinstance(skins, list) or len(skins) != 1:
        raise ValueError("expected one GLB skin and a node array")
    skin = skins[0]
    if not isinstance(skin, dict) or not isinstance(skin.get("joints"), list):
        raise ValueError("GLB skin has no joint order")
    joint_indices = [int(index) for index in skin["joints"]]
    joint_set = set(joint_indices)
    if len(joint_indices) != len(joint_set):
        raise ValueError("GLB skin joint order contains duplicates")

    parents: dict[int, int] = {}
    for parent_index, node in enumerate(nodes):
        if not isinstance(node, dict):
            raise ValueError("GLB node entry is not an object")
        for child in node.get("children", []):
            child_index = int(child)
            if child_index in parents:
                raise ValueError(f"GLB node {child_index} has more than one parent")
            parents[child_index] = parent_index

    roots = [index for index in joint_indices if parents.get(index) not in joint_set]
    if len(roots) != 1:
        raise ValueError(f"expected one skin root, found {len(roots)}")

    result: list[str] = []
    for joint_index in joint_indices:
        chain: list[str] = []
        cursor = joint_index
        visited: set[int] = set()
        while cursor in joint_set:
            if cursor in visited:
                raise ValueError("cycle in GLB joint hierarchy")
            visited.add(cursor)
            chain.append(_converter_node_name(nodes[cursor], cursor))
            parent = parents.get(cursor)
            if parent not in joint_set:
                break
            cursor = parent
        result.append("/".join(reversed(chain)))
    positions = {path: index for index, path in enumerate(result)}
    for index, path in enumerate(result):
        parent = path.rsplit("/", 1)[0] if "/" in path else ""
        while parent and parent not in positions:
            parent = parent.rsplit("/", 1)[0] if "/" in parent else ""
        if parent and positions[parent] >= index:
            raise ValueError(f"GLB skin parent {parent!r} does not precede child {path!r}")
    return result


def _joint_array_matches(text: str) -> list[re.Match[str]]:
    return list(
        re.finditer(
            r"uniform\s+token\[\]\s+joints\s*=\s*\[(.*?)\]",
            text,
            flags=re.DOTALL,
        )
    )


def _mesh_branch_before(text: str, offset: int) -> str:
    candidates = list(
        re.finditer(r'^ {8}def\s+Xform\s+"([A-Za-z_][A-Za-z0-9_]*)"', text[:offset], re.MULTILINE)
    )
    if not candidates:
        raise ValueError("could not associate joint order with a source mesh branch")
    return candidates[-1].group(1)


def _remove_balanced_prim(text: str, match: re.Match[str]) -> str:
    opening = text.find("{", match.end())
    if opening < 0:
        raise ValueError("legacy animated joint graph has no body")
    depth = 0
    in_string = False
    escaped = False
    closing = None
    for index in range(opening, len(text)):
        character = text[index]
        if in_string:
            if escaped:
                escaped = False
            elif character == "\\":
                escaped = True
            elif character == '"':
                in_string = False
            continue
        if character == '"':
            in_string = True
        elif character == "{":
            depth += 1
        elif character == "}":
            depth -= 1
            if depth == 0:
                closing = index + 1
                break
    if closing is None:
        raise ValueError("legacy animated joint graph has unbalanced braces")
    while closing < len(text) and text[closing] in " \t\r\n":
        closing += 1
    return text[: match.start()] + text[closing:]


def repair_usda(text: str, hierarchical_joints: list[str]) -> tuple[str, dict[str, object]]:
    flat_joints = [joint.replace("/", "_") for joint in hierarchical_joints]
    matches = _joint_array_matches(text)
    if not matches or len(matches) % 2:
        raise ValueError(f"expected paired Skeleton/SkelAnimation joint arrays, found {len(matches)}")

    replacements: list[tuple[int, int, str]] = []
    namespaces: list[str] = []
    for match in matches:
        existing = re.findall(r'"((?:[^"\\]|\\.)*)"', match.group(1))
        if existing != flat_joints:
            raise ValueError("USD joint order is not the exact known flattened converter output")
        branch = _mesh_branch_before(text, match.start())
        namespace = f"{branch}_{hierarchical_joints[0]}"
        namespaced = [namespace + joint[len(hierarchical_joints[0]) :] for joint in hierarchical_joints]
        replacement = "uniform token[] joints = [" + ", ".join(json.dumps(joint) for joint in namespaced) + "]"
        replacements.append((match.start(), match.end(), replacement))
        namespaces.append(namespace)

    for start, end, replacement in reversed(replacements):
        text = text[:start] + replacement + text[end:]

    # The converter emits an additional animated Xform hierarchy for the same
    # glTF joints.  The skinned meshes do not reference it.  Leaving it in the
    # package creates an extra global animation resource and name collisions.
    legacy = list(
        re.finditer(
            rf'^ {{8}}def\s+Xform\s+"{re.escape(hierarchical_joints[0])}"\s*$',
            text,
            re.MULTILINE,
        )
    )
    if len(legacy) != 1:
        raise ValueError(f"expected one redundant animated joint graph, found {len(legacy)}")
    text = _remove_balanced_prim(text, legacy[0])
    if "xformOp:transform:transform.timeSamples" in text:
        raise ValueError("animated Xform data remains after legacy graph removal")

    skeleton_namespaces = namespaces[0::2]
    animation_namespaces = namespaces[1::2]
    if skeleton_namespaces != animation_namespaces:
        raise ValueError("Skeleton and SkelAnimation namespaces do not match")
    if len(skeleton_namespaces) != len(set(skeleton_namespaces)):
        raise ValueError("mesh skeleton namespaces are not unique")
    return text, {
        "jointArrays": len(matches),
        "jointsPerArray": len(hierarchical_joints),
        "skeletonNamespaces": skeleton_namespaces,
        "removedLegacyAnimatedJointGraph": True,
    }


def repair(input_usdz: Path, model_glb: Path, output_usdz: Path) -> dict[str, object]:
    if sha256(model_glb) != MODEL_SHA256:
        raise ValueError("model GLB does not match the audited Replay XI source hash")
    if input_usdz.resolve() == output_usdz.resolve():
        raise ValueError("input and output USDZ paths must differ")
    output_usdz.parent.mkdir(parents=True, exist_ok=True)
    joints = derive_joint_paths(load_glb_json(model_glb))

    with tempfile.TemporaryDirectory(prefix="replayxi-usdz-repair-") as temporary:
        work = Path(temporary)
        with zipfile.ZipFile(input_usdz) as archive:
            members = validated_archive_names(archive.infolist())
            archive.extractall(work)
        roots = [name for name in members if Path(name).suffix.lower() in (".usd", ".usda", ".usdc")]
        if len(roots) != 1:
            raise ValueError(f"expected one root USD layer, found {len(roots)}")
        root = work / roots[0]
        source_usda = work / "source.usda"
        repaired_usda = work / "repaired.usda"
        repaired_usdc = work / "repaired.usdc"
        subprocess.run([str(USDCAT), str(root), "-o", str(source_usda)], check=True)
        repaired_text, report = repair_usda(source_usda.read_text(), joints)
        repaired_usda.write_text(repaired_text)
        subprocess.run([str(USDCAT), str(repaired_usda), "-o", str(repaired_usdc)], check=True)
        repaired_usdc.replace(root)
        candidate = work / "repaired.usdz"
        subprocess.run(
            [str(USDZIP), "--arkitAsset", root.name, candidate.name],
            check=True,
            cwd=work,
        )
        normalize_usdz_timestamps(candidate)
        subprocess.run(
            [str(USDCHECKER), "--arkit", "-t", str(candidate)],
            check=True,
        )
        shutil.copy2(candidate, output_usdz)

    report.update(
        {
            "input": str(input_usdz.resolve()),
            "output": str(output_usdz.resolve()),
            "bytes": output_usdz.stat().st_size,
            "sha256": sha256(output_usdz),
        }
    )
    return report


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("input_usdz", type=Path)
    parser.add_argument("model_glb", type=Path)
    parser.add_argument("output_usdz", type=Path)
    arguments = parser.parse_args()
    print(json.dumps(repair(arguments.input_usdz, arguments.model_glb, arguments.output_usdz), indent=2))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
