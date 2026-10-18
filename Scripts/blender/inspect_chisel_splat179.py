#!/usr/bin/env python3
"""Bounded, inspection-only Gaussian PLY point cloud in isolated Blender.

No reconstruction, sphere instances, app assets, or live-scene changes. The
source remains unchanged. Preview orientation is an explicit assumption; no
metric calibration or native registration is inferred from Gaussian data.
"""
import argparse
import hashlib
import json
import math
from pathlib import Path
import sys
import time

import bpy
import numpy as np
from mathutils import Vector


def sha256(path):
    value = hashlib.sha256()
    with path.open("rb") as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b""):
            value.update(block)
    return value.hexdigest()


def read_ply(path):
    """Accept only the converter's explicit scalar-float binary vertex schema."""
    fields, count, lines = [], None, []
    with path.open("rb") as stream:
        for _ in range(128):
            raw = stream.readline(1024)
            if not raw or not raw.endswith(b"\n"):
                raise ValueError("Incomplete or oversized PLY header")
            line = raw.decode("ascii").strip()
            lines.append(line)
            if line == "end_header":
                break
            tokens = line.split()
            if tokens[:2] == ["element", "vertex"]:
                count = int(tokens[2])
            elif tokens[:1] == ["element"]:
                raise ValueError("Vertex-only PLY required; no mesh or other elements")
            elif tokens[:1] == ["property"]:
                if len(tokens) != 3 or tokens[1] != "float":
                    raise ValueError("Expected scalar float Gaussian properties")
                fields.append(tokens[2])
        else:
            raise ValueError("PLY header exceeds 128 lines")
        if (lines[:2] != ["ply", "format binary_little_endian 1.0"] or count is None
                or not 1 <= count <= 5_000_000 or len(fields) != len(set(fields))):
            raise ValueError("Unexpected PLY format, point count, or repeated fields")
        required = {"x", "y", "z", "f_dc_0", "f_dc_1", "f_dc_2", "opacity"}
        if not required.issubset(fields):
            raise ValueError("Missing positions, Gaussian SH DC colors, or opacity")
        data = np.fromfile(stream, dtype=np.dtype([(name, "<f4") for name in fields]), count=count)
        if len(data) != count or stream.read(1):
            raise ValueError("PLY payload size differs from header")
    return data, lines


def bounds(points):
    return {"min": points.min(axis=0).astype(float).tolist(),
            "max": points.max(axis=0).astype(float).tolist()}


def voxel_reduce(points, colors, opacity, maximum):
    """Deterministic voxel means. Stop only after the strict point cap is met."""
    origin, span = points.min(axis=0), float(np.ptp(points, axis=0).max())
    if not math.isfinite(span) or span <= 0:
        raise ValueError("Point cloud has no finite spatial extent")
    width, attempts = span / 512, []
    for _ in range(20):
        cells = np.floor((points - origin) / width).astype(np.int64)
        dimensions = cells.max(axis=0) + 1
        keys = (cells[:, 0] * dimensions[1] + cells[:, 1]) * dimensions[2] + cells[:, 2]
        unique, inverse, counts = np.unique(keys, return_inverse=True, return_counts=True)
        attempts.append({"voxelWidthSourceUnits": width, "occupiedVoxels": len(unique)})
        if len(unique) <= maximum:
            break
        width *= max(1.05, (len(unique) / maximum) ** 0.5)
    else:
        raise ValueError("Voxel downsampling did not meet the point budget")
    count = len(unique)
    reduced = np.column_stack([np.bincount(inverse, weights=points[:, axis], minlength=count) / counts
                               for axis in range(3)]).astype(np.float32)
    alpha_weight = np.bincount(inverse, weights=opacity, minlength=count)
    rgb = np.column_stack([np.bincount(inverse, weights=colors[:, axis] * opacity, minlength=count)
                           / np.maximum(alpha_weight, 1e-20) for axis in range(3)]).astype(np.float32)
    alpha = (alpha_weight / counts).astype(np.float32)
    return reduced, rgb, alpha, width, attempts


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--input", required=True, type=Path)
    parser.add_argument("--expected-input-sha256", required=True)
    parser.add_argument("--output-dir", required=True, type=Path)
    parser.add_argument("--max-points", type=int, default=100_000)
    parser.add_argument("--minimum-opacity", type=float, default=0.05)
    args = parser.parse_args(sys.argv[sys.argv.index("--") + 1:])
    repo = Path(__file__).resolve().parents[2]
    source, output = args.input.resolve(), args.output_dir.resolve()
    staging = repo / ".replayxi-world-staging/Chisel179"
    if not bpy.app.background or "--factory-startup" not in sys.argv or bpy.data.filepath:
        raise RuntimeError("Use fresh --factory-startup --background Blender")
    if (output.exists() or not output.is_relative_to(staging)
            or not output.name.startswith("Inspection")):
        raise ValueError("Output must be a new Inspection... directory inside Chisel179 staging")
    if not 1 <= args.max_points <= 100_000 or not 0 <= args.minimum_opacity < 1:
        raise ValueError("Point cap must be 1..100000 and opacity threshold 0..<1")
    if not source.is_file() or source.suffix.lower() != ".ply" or source.stat().st_size > 512 * 1024 * 1024:
        raise ValueError("Expected an existing local PLY under 512MiB")
    source_hash = sha256(source)
    if source_hash != args.expected_input_sha256.lower():
        raise ValueError("Source hash differs from expected PLY")
    output.mkdir(parents=True)
    started = time.perf_counter()
    data, header = read_ply(source)
    read_seconds = time.perf_counter() - started
    positions = np.column_stack([data[name] for name in ("x", "y", "z")])
    dc = np.column_stack([data[name] for name in ("f_dc_0", "f_dc_1", "f_dc_2")])
    finite_xyz = np.isfinite(positions).all(axis=1)
    raw_bounds = bounds(positions[finite_xyz])
    # Infinite logits are valid converter endpoints: +inf -> alpha1, -inf -> alpha0.
    finite = finite_xyz & np.isfinite(dc).all(axis=1) & ~np.isnan(data["opacity"])
    alpha = (1 / (1 + np.exp(-np.clip(data["opacity"], -80, 80)))).astype(np.float32)
    alpha[np.isposinf(data["opacity"])] = 1
    alpha[np.isneginf(data["opacity"])] = 0
    keep = finite & (alpha >= args.minimum_opacity)
    if not keep.any():
        raise ValueError("No points survived explicit finite/opacity checks")
    positions, alpha = positions[keep], alpha[keep]
    dc_rgb = 0.5 + 0.28209479177387814 * dc[keep]
    clipped_colors = int(np.any((dc_rgb < 0) | (dc_rgb > 1), axis=1).sum())
    rgb = np.clip(dc_rgb, 0, 1)
    before_voxels = len(positions)
    retained_bounds = bounds(positions)
    reduced, rgb, alpha, voxel_width, attempts = voxel_reduce(positions, rgb, alpha, args.max_points)
    reduction_seconds = time.perf_counter() - started - read_seconds

    # Explicit display assumption only: raw X right, raw Y down, raw Z forward.
    # Mapping (X,Z,-Y) is a rotation, with no rescaling or pitch registration.
    preview = np.column_stack((reduced[:, 0], reduced[:, 2], -reduced[:, 1])).astype(np.float32)
    scene = bpy.data.scenes.new("Rejected Chisel179 inspection ONLY")
    bpy.context.window.scene = scene
    scene.unit_settings.system = "NONE"
    mesh = bpy.data.meshes.new("Voxel point positions; zero faces")
    mesh.vertices.add(len(preview))
    mesh.vertices.foreach_set("co", preview.ravel())
    colors = mesh.attributes.new("splat_rgb", "FLOAT_COLOR", "POINT")
    # Standard PLY SH DC colours are display RGB; emission consumes linear RGB.
    linear_rgb = np.where(rgb <= 0.04045, rgb / 12.92, ((rgb + 0.055) / 1.055) ** 2.4)
    rgba = np.column_stack((linear_rgb, np.ones(len(rgb), dtype=np.float32))).astype(np.float32)
    colors.data.foreach_set("color", rgba.ravel())
    alpha_attribute = mesh.attributes.new("source_mean_opacity", "FLOAT", "POINT")
    alpha_attribute.data.foreach_set("value", alpha)
    mesh.update()
    cloud = bpy.data.objects.new("INSPECTION ONLY points; NOT reconstructed mesh", mesh)
    scene.collection.objects.link(cloud)
    cloud["calibration"] = "Uncalibrated source units; Y-down is a preview assumption only"
    cloud["sourceSHA256"] = source_hash
    material = bpy.data.materials.new("SH DC color only; opaque point inspection")
    material.use_nodes = True
    nodes = material.node_tree.nodes
    nodes.clear()
    attribute = nodes.new("ShaderNodeAttribute")
    attribute.attribute_name = "splat_rgb"
    emission = nodes.new("ShaderNodeEmission")
    shader_output = nodes.new("ShaderNodeOutputMaterial")
    material.node_tree.links.new(attribute.outputs["Color"], emission.inputs["Color"])
    material.node_tree.links.new(emission.outputs[0], shader_output.inputs["Surface"])
    mesh.materials.append(material)
    group = bpy.data.node_groups.new("Native Cycles point cloud; no instances", "GeometryNodeTree")
    group.interface.new_socket(name="Geometry", in_out="INPUT", socket_type="NodeSocketGeometry")
    group.interface.new_socket(name="Geometry", in_out="OUTPUT", socket_type="NodeSocketGeometry")
    group_input = group.nodes.new("NodeGroupInput")
    to_points = group.nodes.new("GeometryNodeMeshToPoints")
    to_points.mode = "VERTICES"
    radius = voxel_width * 0.45
    to_points.inputs["Radius"].default_value = radius
    set_material = group.nodes.new("GeometryNodeSetMaterial")
    set_material.inputs["Material"].default_value = material
    group_output = group.nodes.new("NodeGroupOutput")
    group.links.new(group_input.outputs["Geometry"], to_points.inputs["Mesh"])
    group.links.new(to_points.outputs["Points"], set_material.inputs["Geometry"])
    group.links.new(set_material.outputs["Geometry"], group_output.inputs["Geometry"])
    modifier = cloud.modifiers.new("Native points, no surface reconstruction", "NODES")
    modifier.node_group = group
    group_input.location, to_points.location = (-420, 0), (-200, 0)
    set_material.location, group_output.location = (20, 0), (240, 0)
    assert len(mesh.polygons) == 0 and len(mesh.edges) == 0

    minimum, maximum = preview.min(axis=0), preview.max(axis=0)
    centre, span = (minimum + maximum) / 2, maximum - minimum
    longest = float(span.max())

    def camera(name, location, target, lens):
        data = bpy.data.cameras.new(name)
        data.lens = lens
        data.clip_start, data.clip_end = max(longest * 1e-6, 0.001), longest * 20
        obj = bpy.data.objects.new(name, data)
        scene.collection.objects.link(obj)
        obj.location = location
        obj.rotation_euler = (Vector(target) - obj.location).to_track_quat("-Z", "Y").to_euler()
        return obj

    wide = camera("Wide; uncalibrated inspection", centre + np.array((longest * 0.92, -longest * 1.10, longest * 0.66)), centre, 32)
    interior_location = np.array((centre[0], centre[1], minimum[2] + span[2] * 0.06))
    interior_target = np.array((centre[0], maximum[1], minimum[2] + span[2] * 0.25))
    interior = camera("Interior relative height; NOT registered POV", interior_location, interior_target, 22)
    world = bpy.data.worlds.new("Neutral diagnostic background")
    world.use_nodes = True
    world.node_tree.nodes["Background"].inputs[0].default_value = (0.055, 0.065, 0.08, 1)
    world.node_tree.nodes["Background"].inputs[1].default_value = 1
    scene.world = world
    scene.render.engine = "CYCLES"
    scene.cycles.device = "CPU"
    scene.cycles.samples = 8
    scene.cycles.use_denoising = False
    scene.render.threads_mode, scene.render.threads = "FIXED", 8
    scene.render.resolution_x, scene.render.resolution_y = 1280, 800
    scene.render.resolution_percentage = 100
    scene.render.image_settings.file_format = "PNG"
    scene.view_settings.view_transform = "Standard"
    scene.view_settings.look = "None"
    scene.view_settings.exposure, scene.view_settings.gamma = 0, 1
    scene.render.use_stamp = True
    for setting in ("use_stamp_time", "use_stamp_date", "use_stamp_render_time", "use_stamp_frame",
                    "use_stamp_scene", "use_stamp_camera", "use_stamp_filename", "use_stamp_hostname",
                    "use_stamp_frame_range", "use_stamp_marker", "use_stamp_lens", "use_stamp_memory"):
        if hasattr(scene.render, setting):
            setattr(scene.render, setting, False)
    scene.render.use_stamp_note = True
    scene.render.stamp_note_text = "ISOTROPIC POINT PROXY | DC COLOR ONLY | NO MESH | UNCALIBRATED"
    scene.render.stamp_font_size = 16
    scene.camera = wide
    bpy.context.view_layer.objects.active = cloud
    cloud.select_set(True)
    blend = output / "Chisel179Inspection.blend"
    bpy.ops.wm.save_as_mainfile(filepath=str(blend))
    import_seconds = time.perf_counter() - started
    report = {"inspectionOnly": True, "candidateAcceptedForApp": False,
              "priorBrowserAssessment": "Rejected: huge gaps and missing roof; no reconstruction attempted",
              "source": str(source), "sourceSHA256": source_hash, "sourceBytes": source.stat().st_size,
              "sourceHeader": header, "sourcePoints": len(data), "finiteXYZPoints": int(finite_xyz.sum()),
              "sourceBoundsXYZ": raw_bounds, "validRequiredFieldsPoints": int(finite.sum()),
              "invalidPointsRemoved": int((~finite).sum()), "minimumOpacity": args.minimum_opacity,
              "positiveInfinityOpacityLogits": int(np.isposinf(data["opacity"]).sum()),
              "negativeInfinityOpacityLogits": int(np.isneginf(data["opacity"]).sum()),
              "opacityTreatment": "Sigmoid(logit); +Infinity treated as alpha1, -Infinity as alpha0. Alpha filters/weights voxel averaging but is not Gaussian-composited in previews.",
              "opacityPointsRemoved": int((finite & ~keep).sum()), "pointsBeforeVoxels": before_voxels,
              "retainedBoundsXYZBeforeVoxels": retained_bounds, "inspectionPoints": len(reduced),
              "voxelMergedPoints": before_voxels - len(reduced), "totalPointsRemovedOrMerged": len(data) - len(reduced),
              "voxelWidthSourceUnits": voxel_width, "voxelAttempts": attempts,
              "inspectionSourceBoundsXYZ": bounds(reduced), "previewBoundsBlenderXYZ": bounds(preview),
              "previewCoordinateTransform": "Blender (X,Y,Z) = source (X,Z,-Y); rotation only; no scale/translation",
              "coordinateLimits": "Y-down is an explicit visual assumption; source units, handedness and pitch alignment remain uncalibrated. No metre/native registration claim.",
              "colorMethod": "RGB=clamp(0.5+SH_C0*f_dc); opacity-weighted voxel means; display RGB converted to linear for unlit emission",
              "colorClippedSourcePoints": clipped_colors,
              "representationLimits": "Opaque isotropic point proxy at fixed radius 0.45*voxel width; NOT a faithful Gaussian renderer or reconstructed mesh. Source anisotropic covariance/scales, rotations and Gaussian opacity compositing are NOT reproduced. Only SH DC exists in this PLY; no higher-order SH. Mean opacity retained as an attribute only.",
              "sourceGaussianFieldsNotRendered": [n for n in data.dtype.names if n not in {"x", "y", "z", "f_dc_0", "f_dc_1", "f_dc_2"}],
              "meshFaces": 0, "meshEdges": 0, "sphereInstances": 0, "pointRadiusSourceUnits": radius,
              "localPLYReadSeconds": read_seconds, "filterAndVoxelSeconds": reduction_seconds,
              "localImportAndBlendSaveSecondsExcludingStartupAndHash": import_seconds,
              "previewCPUThreads": 8, "previewSamples": 8, "previewResolution": [1280, 800],
              "blend": str(blend), "previews": ["wide-overview.png", "interior-relative.png"],
              "sourceUnchanged": sha256(source) == source_hash, "generationSpend": 0,
              "appOrSeedFilesChanged": False}
    if not report["sourceUnchanged"]:
        raise ValueError("Source changed during inspection")
    (output / "inspection.json").write_text(json.dumps(report, indent=2, allow_nan=False) + "\n")
    print("POINT_INSPECTION_READY " + json.dumps(report), flush=True)
    render_start = time.perf_counter()
    for filename, selected in (("wide-overview.png", wide), ("interior-relative.png", interior)):
        scene.camera = selected
        scene.render.filepath = str(output / filename)
        bpy.ops.render.render(write_still=True)
    report["previewRenderSeconds"] = time.perf_counter() - render_start
    report["sourceUnchanged"] = sha256(source) == source_hash
    if not report["sourceUnchanged"]:
        raise ValueError("Source changed during preview rendering")
    (output / "inspection.json").write_text(json.dumps(report, indent=2, allow_nan=False) + "\n")
    print("POINT_PREVIEWS_READY " + str(output), flush=True)


if __name__ == "__main__":
    main()
