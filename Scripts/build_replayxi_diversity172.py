#!/usr/bin/env python3
"""Build source-bound Player A USDZ, motion, and contact assets from rigged GLBs.

Run with Blender's bundled Python. Inputs stay untouched. Output must be a new
directory in .codex-derived. The three GLBs must share the exact 52-joint rest
and base-color atlas; two LODs share one new motion contract.
"""
from __future__ import annotations

import argparse
from collections import Counter
import hashlib
import json
from pathlib import Path
import shutil
import subprocess
import tempfile

import numpy as np

import build_replayxi_tripo_athlete as core
from replayxi_usdz_archive import normalize_usdz_timestamps

REPO = Path(__file__).resolve().parents[1]
SOURCE = REPO / "Assets/ReplayXI/PlayerDiversity171/Source/player-a-hd-source.glb"
SOURCE_SHA = "2b25690666877f3e090d5ce4e5d8e30702d6d02f497e5511de4ba9d3df1dcfc3"
NAMES = {
    "near": ("ReplayXITripoPlayerA.usdz", "ReplayXITripoPlayerAContactSurface.json"),
    "low": ("ReplayXITripoPlayerALow.usdz", "ReplayXITripoPlayerALowContactSurface.json"),
}
MOTION_NAME = "ReplayXITripoPlayerAMotion.json"


def embedded_image(document, binary, image_index):
    image = document["images"][image_index]
    if image.get("mimeType") not in ("image/jpeg", "image/png") or "bufferView" not in image:
        raise ValueError("base-color image must be embedded JPEG/PNG")
    view = document["bufferViews"][image["bufferView"]]
    start = view.get("byteOffset", 0)
    data = binary[start:start + view["byteLength"]]
    if len(data) != view["byteLength"]:
        raise ValueError("truncated embedded image")
    return data


def basecolor_sha(document, binary):
    if len(document.get("materials", [])) != 1:
        raise ValueError("expected one source material")
    material = document["materials"][0]
    texture = material.get("pbrMetallicRoughness", {}).get("baseColorTexture", {}).get("index")
    if texture is None:
        raise ValueError("missing material base-color texture")
    image_index = document["textures"][texture]["source"]
    return hashlib.sha256(embedded_image(document, binary, image_index)).hexdigest()


def source_provenance(specs, motion_document, motion_binary, kits_report):
    if core.sha(SOURCE) != SOURCE_SHA:
        raise ValueError("pinned Player A source changed")
    original, binary = core.glb(SOURCE)
    if len(original.get("images", [])) != 3 or len(original.get("skins", [])):
        raise ValueError("Player A source topology or three-image material changed")
    source_images = {}
    for index, image in enumerate(original["images"]):
        payload = embedded_image(original, binary, index)
        source_images[image["name"]] = {"sha256": hashlib.sha256(payload).hexdigest(),
                                        "bytes": len(payload), "mimeType": image["mimeType"]}
    source_atlas = basecolor_sha(original, binary)
    original_image_set = Counter((row["sha256"], row["mimeType"])
                                 for row in source_images.values())
    rig_atlases = {}
    for label, document, payload, _, _ in [*specs, ("motion", motion_document, motion_binary, None, None)]:
        rig_image_set = Counter((hashlib.sha256(embedded_image(document, payload, index)).hexdigest(),
                                 image["mimeType"])
                                for index, image in enumerate(document.get("images", [])))
        if rig_image_set != original_image_set:
            raise ValueError(f"{label} no longer embeds the three exact source PBR images")
        atlas = basecolor_sha(document, payload)
        rig_atlases[label] = atlas
        if atlas != source_atlas:
            raise ValueError(f"{label} base-color atlas bytes differ from source")
    report = json.loads(kits_report.read_text())
    if (report.get("sourceSHA256") != SOURCE_SHA
            or report.get("nearGLBSHA256") != core.sha(specs[0][1]["_path"])
            or not report.get("sameGeometryForBothTeams")):
        raise ValueError("kit report is not bound to source and near GLB")
    kits = {}
    for entry in report.get("textures", []):
        kit = entry.get("kit")
        path = kits_report.parent / entry.get("texture", "")
        if (kit not in ("home", "away", "keeper") or not path.is_file()
                or entry.get("size") != [1024, 1024] or path.stat().st_size > 12 * 1024 * 1024
                or core.sha(path) != entry.get("sha256")):
            raise ValueError("kit atlas missing, oversized, or hash mismatch")
        kits[kit] = {"file": path.name, "sha256": core.sha(path), "size": [1024, 1024]}
    if set(kits) != {"home", "away", "keeper"}:
        raise ValueError("requires home, away, and keeper atlases")
    with tempfile.TemporaryDirectory(prefix="replayxi-player-a-pixels-") as temporary:
        binary_path = Path(temporary) / "audit-pixels"
        subprocess.run(["swiftc", str(REPO / "ReplayXI/Immersive/ReplayTexturePixels.swift"),
                        str(REPO / "Scripts/audit_replayxi_diversity172_pixels.swift"),
                        "-o", str(binary_path)], check=True, capture_output=True)
        audited = subprocess.run([str(binary_path), *(str(kits_report.parent / kits[kit]["file"])
                                                   for kit in ("home", "away", "keeper"))],
                                 check=True, capture_output=True, text=True)
    pixel_rows = [json.loads(line) for line in audited.stdout.splitlines() if line.strip()]
    if len(pixel_rows) != 3:
        raise ValueError("native pixel audit did not return three atlases")
    for kit, row in zip(("home", "away", "keeper"), pixel_rows):
        if row["fileSHA256"] != kits[kit]["sha256"] or row["dimensions"] != [1024, 1024]:
            raise ValueError("native pixel audit disagrees with atlas report")
        kits[kit]["pixelSHA256"] = row["opaqueSRGBRGBA8SHA256"]
    skin_audit_path = kits_report.parent / "PlayerASkinPixelsAudit.json"
    skin_audit_sha = None
    if report.get("visualQA", "").startswith("passed"):
        if not skin_audit_path.is_file():
            raise ValueError("visually accepted kit lacks mesh-UV skin pixel audit")
        skin_audit = json.loads(skin_audit_path.read_text())
        if skin_audit.get("nearGLBSHA256") != core.sha(specs[0][1]["_path"]):
            raise ValueError("skin audit is not bound to near GLB")
        for kit in ("home", "away", "keeper"):
            if skin_audit.get("kitFileSHA256", {}).get(kit.title()) != kits[kit]["sha256"]:
                raise ValueError(f"skin audit is not bound to {kit} atlas")
        skin_audit_sha = core.sha(skin_audit_path)
    return {"sourceGLBSHA256": SOURCE_SHA, "sourceImages": source_images,
            "sourceBasecolorSHA256": source_atlas, "rigBasecolorSHA256": rig_atlases,
            "kitsReportSHA256": core.sha(kits_report), "kits": kits,
            "kitVisualQA": report.get("visualQA", "unknown"),
            "skinPixelAuditSHA256": skin_audit_sha}


def build(args):
    output = args.output.resolve()
    if output.exists() or not output.is_relative_to((REPO / ".codex-derived").resolve()):
        raise ValueError("output must be a NEW .codex-derived directory")
    for path in (SOURCE, args.near_glb, args.low_glb, args.motion_glb, args.kits_report):
        if not path.is_file():
            raise ValueError(f"missing input: {path}")
    hashes = {"sourceGLB": SOURCE_SHA, "nearGLB": core.sha(args.near_glb),
              "lowGLB": core.sha(args.low_glb), "motionGLB": core.sha(args.motion_glb),
              "kitsReport": core.sha(args.kits_report)}
    specs = []
    for label, path, triangle_cap in (("near", args.near_glb, 12000), ("low", args.low_glb, 3000)):
        document, binary = core.glb(path)
        document["_path"] = path
        skin = core.inspect_skin(document, binary)
        body = core.mesh_data(document, binary, skin, 1)
        if not 8 <= body["triangles"] <= triangle_cap or not 8 <= body["vertices"] <= 12000:
            raise ValueError(f"{label} exceeds native triangle/vertex budget")
        specs.append((label, document, binary, skin, body))
    near_height = float(np.ptp(specs[0][4]["points"][:, 1]))
    if not .5 <= near_height <= 2.5:
        raise ValueError("near GLB height implausible")
    scale = args.height / near_height
    motion_document, motion_binary = core.glb(args.motion_glb)
    motion_skin = core.inspect_skin(motion_document, motion_binary)
    provenance = source_provenance(specs, motion_document, motion_binary, args.kits_report)
    near_names = [specs[0][1]["nodes"][n]["name"] for n in specs[0][3]["order"]]
    for label, document, _, skin, _ in [*specs[1:], ("motion", motion_document, motion_binary, motion_skin, None)]:
        names = [document["nodes"][n]["name"] for n in skin["order"]]
        if names != near_names:
            raise ValueError(f"{label} joint names/order differ from near")
    near_joints, near_rest, near_bind = core.skeleton(specs[0][1], specs[0][3], scale)
    motion_joints, motion_rest, _ = core.skeleton(motion_document, motion_skin, scale)
    if any(np.max(abs(a - b)) > 2e-4 for a, b in zip(near_rest, motion_rest)):
        raise ValueError("motion rest differs from near rest")
    motion_skin["rootRestXZ"] = [0.0, 0.0]
    clips, root_offsets = core.motion_clips(motion_document, motion_binary, motion_skin, scale)
    output.mkdir(parents=True)
    shutil.copyfile(args.kits_report, output / args.kits_report.name)
    if core.sha(output / args.kits_report.name) != hashes["kitsReport"]:
        raise ValueError("kit report changed while copying")
    for kit in ("home", "away", "keeper"):
        source_texture = args.kits_report.parent / provenance["kits"][kit]["file"]
        target_texture = output / source_texture.name
        shutil.copyfile(source_texture, target_texture)
        if core.sha(target_texture) != provenance["kits"][kit]["sha256"]:
            raise ValueError(f"{kit} atlas changed while copying")
    if provenance["skinPixelAuditSHA256"]:
        audit_name = "PlayerASkinPixelsAudit.json"
        shutil.copyfile(args.kits_report.parent / audit_name, output / audit_name)
        if core.sha(output / audit_name) != provenance["skinPixelAuditSHA256"]:
            raise ValueError("skin pixel audit changed while copying")
    with tempfile.TemporaryDirectory(prefix="replayxi-player-a-native-") as temporary:
        work = Path(temporary)
        bodies = {}
        skeletons = {}
        for label, document, binary, skin, _ in specs:
            body = core.mesh_data(document, binary, skin, scale, args.normal_mode)
            joints, rests, binds = core.skeleton(document, skin, scale)
            if [joint["name"] for joint in joints] != [joint["name"] for joint in near_joints]:
                raise ValueError(f"{label} joint path mismatch")
            if any(np.max(abs(a - b)) > 2e-4 for a, b in zip(rests, near_rest)):
                raise ValueError(f"{label} rest differs from near")
            layer = work / f"{label}.usdc"
            core.write_usd(layer, near_joints, rests, binds, body, clips, SOURCE_SHA,
                           args.weld_uv_topology, source_prefix="player-a-glb-",
                           runtime_motion_name=MOTION_NAME)
            asset_name = NAMES[label][0]
            package = work / asset_name
            subprocess.run(["usdzip", "--arkitAsset", str(layer), str(package)],
                           check=True, capture_output=True)
            normalize_usdz_timestamps(package)
            subprocess.run(["usdchecker", "--arkit", str(package)],
                           check=True, capture_output=True)
            shutil.copyfile(package, output / asset_name)
            bodies[label] = body
            skeletons[label] = (rests, binds)
        near = bodies["near"]
        minimum, maximum = near["points"].min(axis=0), near["points"].max(axis=0)
        semantic = specs[0][3]["semantic"]
        number, feet = core.anchors_and_contacts(near, near_joints, near_bind, semantic, minimum, maximum)
        number_audit = core.lift_number_anchors(near, near_joints, near_bind, clips, number)
        geometry = {"vertices": near["vertices"], "triangles": near["triangles"],
                    "jointCount": 52, "materialCount": 1,
                    "boundsMin": core.rounded(minimum), "boundsMax": core.rounded(maximum),
                    "nominalHeight": float(maximum[1] - minimum[1]),
                    "restMinY": float(minimum[1]), "pelvisRestHeight": float(near_bind[0][1, 3])}
        pose_audit = []
        for clip in clips:
            frames = clip["frames"]
            for index in sorted({0, len(frames) // 2, len(frames) - 1}):
                small, large = core.posed_bounds(near, near_joints, near_bind, frames[index])
                pose_audit.append({"clip": clip["id"], "frame": index,
                                   "boundsMin": core.rounded(small),
                                   "boundsMax": core.rounded(large)})
        motion = {"schemaVersion": 1, "sourceCommit": "player-a-glb-" + SOURCE_SHA[:32],
                  "joints": near_joints, "semanticJoints": semantic, "clips": clips,
                  "geometry": geometry, "footContacts": feet, "numberAnchors": number,
                  "bodyMaterialSlot": 0, "headMaterialSlot": 0,
                  "rootMotion": "X/Z removed; vertical motion retained; metres/Y-up/+Z forward"}
        motion_path = output / MOTION_NAME
        motion_path.write_text(json.dumps(motion, separators=(",", ":"), allow_nan=False) + "\n")
        if motion_path.stat().st_size > 4 * 1024 * 1024:
            raise ValueError("motion exceeds runtime 4 MB limit")
        motion_hash = core.sha(motion_path)
        paths = [joint["name"] for joint in near_joints]
        contacts = {}
        boot_audit = {}
        for label, (asset_name, contact_name) in NAMES.items():
            body = bodies[label]
            small, large = body["points"].min(axis=0), body["points"].max(axis=0)
            _, lod_feet = core.anchors_and_contacts(body, near_joints, skeletons[label][1],
                                                    semantic, small, large)
            boot_audit[label] = lod_feet
            header_floor = geometry["restMinY"] + geometry["nominalHeight"] - .19
            contact = core.contact_vertices(body, paths, semantic, small, large,
                                            core.sha(output / asset_name), motion_hash, header_floor)
            # Native pose validation found 5.2 mm near / 6.6 mm low sole
            # penetration with 6 mm padding. The 512 probes can miss a small
            # triangle tip, so reserve 12 mm within the runtime's 20 mm cap.
            contact["paddingMetres"] = .012
            contact_path = output / contact_name
            contact_path.write_text(json.dumps(contact, separators=(",", ":"), allow_nan=False) + "\n")
            if contact_path.stat().st_size > 256 * 1024:
                raise ValueError("contact surface exceeds 256 KB")
            head_path = semantic["head"]
            head_joints = {index for index, path in enumerate(paths)
                           if path == head_path or path.startswith(head_path + "/")}
            probes = [v for v in contact["vertices"] if v["position"][1] >= header_floor and
                      sum(w for j, w in zip(v["joints"], v["weights"]) if j in head_joints) >= .8]
            if not 64 <= len(probes) <= 96:
                raise ValueError(f"{label} has {len(probes)} runtime header probes; need 64-96")
            contacts[label] = {"totalVertices": len(contact["vertices"]),
                               "weightedHeaderProbes": len(probes),
                               "headProbeBoundsMin": core.rounded(np.min([v["position"] for v in probes], axis=0)),
                               "headProbeBoundsMax": core.rounded(np.max([v["position"] for v in probes], axis=0))}
        assets = {}
        for label, (asset_name, _) in NAMES.items():
            rests, binds = skeletons[label]
            assets[label] = core.audit_usd(output / asset_name, paths, rests, binds,
                                           bodies[label], core.sha(output / asset_name),
                                           args.weld_uv_topology)
        runtime_manifest = {
            "motion": {"resource": MOTION_NAME, "sha256": motion_hash},
            "near": {"resource": NAMES["near"][0], "sha256": core.sha(output / NAMES["near"][0]),
                     "sourceVertices": bodies["near"]["vertices"],
                     "triangles": bodies["near"]["triangles"],
                     "contactResource": NAMES["near"][1],
                     "contactSHA256": core.sha(output / NAMES["near"][1])},
            "low": {"resource": NAMES["low"][0], "sha256": core.sha(output / NAMES["low"][0]),
                    "sourceVertices": bodies["low"]["vertices"],
                    "triangles": bodies["low"]["triangles"],
                    "contactResource": NAMES["low"][1],
                    "contactSHA256": core.sha(output / NAMES["low"][1])},
            "kits": provenance["kits"],
        }
        report = {"sourceHashes": hashes, "sourceCommit": motion["sourceCommit"],
                  "provenance": provenance, "heightScale": scale, "geometry": geometry,
                  "normalMode": args.normal_mode,
                  "contactPaddingMetres": .012,
                  "contactPaddingRationale": "Native weighted-pose test: 5.2 mm near and 6.6 mm low penetration at 6 mm padding; 12 mm covers the observed probe gap within the runtime 20 mm cap.",
                  "usdTopologyMode": "welded" if args.weld_uv_topology else "source-vertex",
                  "numberPanel": number_audit, "poseBounds": pose_audit,
                  "contacts": contacts, "boots": boot_audit,
                  "clips": [{"id": c["id"], "frames": len(c["frames"]),
                             "durationSeconds": c["durationSeconds"]} for c in clips],
                  "assets": assets, "runtimeManifest": runtime_manifest,
                  "files": {p.name: {"bytes": p.stat().st_size, "sha256": core.sha(p)}
                            for p in sorted(output.iterdir())}}
        report_path = output / "ReplayXITripoPlayerABuildReport.json"
        report_path.write_text(json.dumps(report, indent=2, sort_keys=True) + "\n")
        return report


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--near-glb", type=Path, required=True)
    parser.add_argument("--low-glb", type=Path, required=True)
    parser.add_argument("--motion-glb", type=Path, required=True)
    parser.add_argument("--kits-report", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--height", type=float, default=1.82)
    parser.add_argument("--normal-mode", choices=("source", "area-weighted"), default="source")
    parser.add_argument("--weld-uv-topology", action="store_true")
    print(json.dumps(build(parser.parse_args()), indent=2, sort_keys=True))
