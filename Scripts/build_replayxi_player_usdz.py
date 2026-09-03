#!/usr/bin/env python3
"""Build one RealityKit-ready skinned USDZ clip from audited CC0 GLBs.

Requirements:
  * Python with numpy, Pillow, pygltflib and usd-core/OpenUSD bindings.
  * kcoley/gltf2usd checked out at the pinned commit below.
  * Apple's /usr/bin/usdzip and /usr/bin/usdchecker.

Example:
  PYTHONPATH=/private/tmp/replayxi-usdpy \
    python3 Scripts/build_replayxi_player_usdz.py \
      /private/tmp/replayxi-night-striker.glb \
      /private/tmp/replayxi-universal-animation-library.glb \
      /private/tmp/gltf2usd \
      /private/tmp/ReplayXIPlayerSprint.usdz \
      --clip Sprint_Loop
"""

import argparse
import hashlib
import math
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile

from pygltflib import GLTF2
from pxr import Gf, Sdf, Usd, UsdGeom, UsdShade, UsdSkel

from replayxi_glb_retarget import retarget
from replayxi_usdz_archive import normalize_usdz_timestamps


MODEL_SHA256 = "a466828c67a4acc9b2413212ce6d9cde235e3aed9b675680c14fd9673858f118"
ANIMATION_SHA256 = "4c748767741a3e495d89667b9a218b690ba9810b9517a12e960780e3ca72c4e9"
GLTF2USD_COMMIT = "c0752099313834a466acf04b89af33dfd5dc9a0b"


def sha256(path):
    digest = hashlib.sha256()
    with open(path, "rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def verify_inputs(model_path, animation_path, converter_root, allow_unverified):
    model_hash = sha256(model_path)
    animation_hash = sha256(animation_path)
    errors = []
    if model_hash != MODEL_SHA256:
        errors.append(f"unexpected character SHA-256: {model_hash}")
    if animation_hash != ANIMATION_SHA256:
        errors.append(f"unexpected animation SHA-256: {animation_hash}")

    converter_script = converter_root / "Source" / "gltf2usd.py"
    if not converter_script.is_file():
        errors.append(f"missing converter: {converter_script}")
    try:
        converter_commit = subprocess.check_output(
            ["git", "-C", str(converter_root), "rev-parse", "HEAD"],
            text=True,
        ).strip()
        if converter_commit != GLTF2USD_COMMIT:
            errors.append(f"unexpected gltf2usd commit: {converter_commit}")
    except (OSError, subprocess.CalledProcessError):
        errors.append("gltf2usd checkout has no readable Git commit")

    if errors and not allow_unverified:
        raise RuntimeError("\n".join(errors))
    for error in errors:
        print(f"warning: {error}", file=sys.stderr)
    return model_hash, animation_hash


def copy_and_patch_converter(source_root, destination_root):
    shutil.copytree(
        source_root,
        destination_root,
        ignore=shutil.ignore_patterns(".git", "__pycache__", "tests"),
    )
    script = destination_root / "Source" / "gltf2usd.py"
    content = script.read_text()
    replacements = {
        "skeleton.CreateJointsAttr().Set(usd_joint_names)": (
            "skeleton.CreateJointsAttr().Set("
            "Vt.TokenArray([str(path) for path in usd_joint_names]))"
        ),
        "skeleton.CreateBindTransformsAttr(gltf_bind_transforms)": (
            "skeleton.CreateBindTransformsAttr().Set("
            "Vt.Matrix4dArray(gltf_bind_transforms))"
        ),
        "skeleton.CreateRestTransformsAttr(gltf_rest_transforms)": (
            "skeleton.CreateRestTransformsAttr().Set("
            "Vt.Matrix4dArray(gltf_rest_transforms))"
        ),
        "skelAnim.CreateJointsAttr().Set(joint_names)": (
            "skelAnim.CreateJointsAttr().Set("
            "Vt.TokenArray([str(path) for path in joint_names]))"
        ),
        "translate_attr.Set(entries, Usd.TimeCode(input_key * self.fps))": (
            "translate_attr.Set(Vt.Vec3fArray([Gf.Vec3f(*entry) for entry in entries]), "
            "Usd.TimeCode(input_key * self.fps))"
        ),
        "scale_attr.Set(entries, Usd.TimeCode(input_key * self.fps))": (
            "scale_attr.Set(Vt.Vec3hArray([Gf.Vec3h(*entry) for entry in entries]), "
            "Usd.TimeCode(input_key * self.fps))"
        ),
        # The legacy converter sanitizes the completed slash-delimited path,
        # flattening every bone into a root joint. Preserve separators and
        # sanitize each path component instead. Patch both the cache hit and
        # cache miss paths; a shared skin is converted once per mesh branch.
        "return GLTF2USDUtils.convert_to_usd_friendly_node_name("
        "self._joint_hierarchy_name_map[gltf_joint])": (
            "return '/'.join([GLTF2USDUtils.convert_to_usd_friendly_node_name(segment) "
            "for segment in self._joint_hierarchy_name_map[gltf_joint].split('/')])"
        ),
        "return GLTF2USDUtils.convert_to_usd_friendly_node_name(joint_name)": (
            "return '/'.join([GLTF2USDUtils.convert_to_usd_friendly_node_name(segment) "
            "for segment in joint_name.split('/')])"
        ),
        # The input has three separately skinned mesh nodes. Give their joint
        # graphs distinct root names so importers cannot cross-attach the three
        # otherwise-identical SkelAnimation resources by joint name.
        "usd_joint_names = [Sdf.Path(self._get_usd_joint_hierarchy_name(joint, "
        "gltf_skin.root_joints)) for joint in gltf_skin.get_joints()]": (
            "joint_namespace = GLTF2USDUtils.convert_to_usd_friendly_node_name("
            "str(usd_node.GetPath().GetParentPath()).rsplit('/', 1)[-1])\n"
            "            raw_joint_names = [self._get_usd_joint_hierarchy_name(joint, "
            "gltf_skin.root_joints) for joint in gltf_skin.get_joints()]\n"
            "            usd_joint_names = [Sdf.Path('{0}_{1}'.format(joint_namespace, "
            "path)) for path in raw_joint_names]"
        ),
    }
    for old, new in replacements.items():
        if old in content:
            content = content.replace(old, new)
        elif new not in content:
            raise RuntimeError(f"gltf2usd compatibility patch no longer matches: {old}")
    script.write_text(content)
    return script


def make_retargeted_glb(model_path, animation_path, clip_name, output_path):
    model = GLTF2.load_binary(str(model_path))
    animation_library = GLTF2.load_binary(str(animation_path))
    retargeted = retarget(model, animation_library, [clip_name])
    retargeted.save_binary(str(output_path))


def extract_clip_gltf(glb_path, clip_name, output_directory):
    gltf = GLTF2.load_binary(str(glb_path))
    blob = gltf.binary_blob()
    gltf.animations = [animation for animation in gltf.animations if animation.name == clip_name]
    if len(gltf.animations) != 1:
        raise RuntimeError(f"expected one clip named {clip_name}")

    for index, image in enumerate(gltf.images):
        if image.bufferView is None:
            continue
        view = gltf.bufferViews[image.bufferView]
        start = view.byteOffset or 0
        payload = blob[start : start + view.byteLength]
        extension = {"image/png": "png", "image/jpeg": "jpg"}.get(
            image.mimeType,
            "bin",
        )
        filename = f"image-{index}.{extension}"
        (output_directory / filename).write_bytes(payload)
        image.uri = filename
        image.bufferView = None
        image.mimeType = None

    binary_name = "player.bin"
    (output_directory / binary_name).write_bytes(blob)
    gltf.buffers[0].uri = binary_name
    output_path = output_directory / "player.gltf"
    gltf.save(str(output_path))
    return output_path


def run_converter(converter_script, gltf_path, usdc_path, fps):
    source = converter_script.parent
    internal = source / "_gltf2usd"
    gltf_types = internal / "gltf2"
    environment = dict(os.environ)
    python_paths = [str(source), str(internal), str(gltf_types)]
    if environment.get("PYTHONPATH"):
        python_paths.append(environment["PYTHONPATH"])
    environment["PYTHONPATH"] = os.pathsep.join(python_paths)
    subprocess.run(
        [
            sys.executable,
            str(converter_script),
            "-g",
            str(gltf_path),
            "-o",
            str(usdc_path),
            "-s",
            "1",
            "--fps",
            str(fps),
        ],
        check=True,
        env=environment,
    )


def postprocess_usd(usdc_path, clip_name, model_hash, animation_hash):
    stage = Usd.Stage.Open(str(usdc_path))
    if not stage:
        raise RuntimeError(f"OpenUSD could not open {usdc_path}")
    UsdGeom.SetStageMetersPerUnit(stage, 1.0)
    UsdGeom.SetStageUpAxis(stage, UsdGeom.Tokens.y)
    root = stage.GetPrimAtPath("/root")
    if not root:
        raise RuntimeError("converted stage has no /root prim")
    stage.SetDefaultPrim(root)
    # gltf2usd also emits the animated source joint nodes as a second Xform
    # graph. The skinned meshes bind to their generated UsdSkel.Skeletons and
    # never reference this branch. Keeping it creates an extra global animation
    # resource and colliding joint names in SceneKit/RealityKit importers.
    legacy_joint_graph_path = Sdf.Path("/root/Armature_68/root_64")
    legacy_joint_graph = stage.GetPrimAtPath(legacy_joint_graph_path)
    if not legacy_joint_graph or not legacy_joint_graph.IsA(UsdGeom.Xform):
        raise RuntimeError(
            f"locked converter output lost expected joint graph {legacy_joint_graph_path}"
        )
    if not any(
        attribute.ValueMightBeTimeVarying()
        for prim in Usd.PrimRange(legacy_joint_graph)
        for attribute in prim.GetAttributes()
    ):
        raise RuntimeError("expected legacy joint graph is not animated")
    stage.RemovePrim(legacy_joint_graph_path)
    metadata = dict(stage.GetRootLayer().customLayerData)
    metadata.update(
        {
            "replayxi_clip": clip_name,
            "replayxi_model_sha256": model_hash,
            "replayxi_animation_sha256": animation_hash,
            "replayxi_source": (
                "Quaternius Universal Base Characters + Universal Animation "
                "Library (CC0 1.0)"
            ),
            "replayxi_topology": (
                "hierarchical namespaced joints; redundant animated Xform graph removed"
            ),
        }
    )
    stage.GetRootLayer().customLayerData = metadata

    for prim in stage.Traverse():
        if prim.IsA(UsdSkel.Skeleton) or (
            prim.IsA(UsdGeom.Mesh) and prim.HasProperty("skel:skeleton")
        ):
            UsdSkel.BindingAPI.Apply(prim)
        if prim.IsA(UsdGeom.Mesh):
            UsdShade.MaterialBindingAPI.Apply(prim)
        if prim.IsA(UsdShade.Shader):
            varname = prim.GetAttribute("inputs:varname")
            if varname and varname.GetTypeName() == Sdf.ValueTypeNames.Token:
                value = varname.Get()
                prim.RemoveProperty("inputs:varname")
                prim.CreateAttribute(
                    "inputs:varname",
                    Sdf.ValueTypeNames.String,
                ).Set(str(value))
            if prim.GetName() == "normalTexture":
                shader = UsdShade.Shader(prim)
                shader.CreateInput(
                    "sourceColorSpace",
                    Sdf.ValueTypeNames.Token,
                ).Set("raw")
                shader.CreateInput("scale", Sdf.ValueTypeNames.Float4).Set(
                    Gf.Vec4f(2, 2, 2, 1)
                )
                shader.CreateInput("bias", Sdf.ValueTypeNames.Float4).Set(
                    Gf.Vec4f(-1, -1, -1, 0)
                )
    stage.GetRootLayer().Save()


def validate_skinning(usdc_path):
    stage = Usd.Stage.Open(str(usdc_path))
    skeletons = [
        UsdSkel.Skeleton(prim)
        for prim in stage.Traverse()
        if prim.IsA(UsdSkel.Skeleton)
    ]
    meshes = [prim for prim in stage.Traverse() if prim.IsA(UsdGeom.Mesh)]
    if not skeletons or not meshes:
        raise RuntimeError("converted stage lost its skinned geometry")

    maximum_delta = 0.0
    skeleton_root_names = []
    for skeleton in skeletons:
        joints = [str(path) for path in skeleton.GetJointsAttr().Get()]
        if not joints:
            raise RuntimeError(f"empty joint order on {skeleton.GetPath()}")
        if len(joints) != len(set(joints)):
            raise RuntimeError(f"duplicate joint paths on {skeleton.GetPath()}")
        joint_set = set(joints)
        joint_positions = {joint: index for index, joint in enumerate(joints)}
        roots = []
        for index, joint in enumerate(joints):
            parent = joint.rsplit("/", 1)[0] if "/" in joint else ""
            while parent and parent not in joint_set:
                parent = parent.rsplit("/", 1)[0] if "/" in parent else ""
            if not parent:
                roots.append(joint)
            elif joint_positions[parent] >= index:
                raise RuntimeError(
                    f"joint parent {parent} follows child {joint} on {skeleton.GetPath()}"
                )
        if len(joints) > 1 and all("/" not in joint for joint in joints):
            raise RuntimeError(
                f"flattened joint paths on {skeleton.GetPath()}; hierarchy was lost"
            )
        if len(roots) != 1:
            raise RuntimeError(
                f"expected one root joint on {skeleton.GetPath()}, found {len(roots)}"
            )
        skeleton_root_names.append(roots[0])
        bind_transforms = skeleton.GetBindTransformsAttr().Get()
        rest_transforms = skeleton.GetRestTransformsAttr().Get()
        if len(bind_transforms) != len(joints) or len(rest_transforms) != len(joints):
            raise RuntimeError(f"joint/rest/bind cardinality mismatch on {skeleton.GetPath()}")
        for label, transforms in (("bind", bind_transforms), ("rest", rest_transforms)):
            if any(
                not math.isfinite(float(transform[row][column]))
                for transform in transforms
                for row in range(4)
                for column in range(4)
            ):
                raise RuntimeError(f"non-finite {label} transform on {skeleton.GetPath()}")

        skel_root = UsdSkel.Root(skeleton.GetPrim().GetParent())
        cache = UsdSkel.Cache()
        cache.Populate(skel_root, Usd.PrimDefaultPredicate)
        query = cache.GetSkelQuery(skeleton)
        if not query or not query.GetAnimQuery():
            raise RuntimeError(f"animation is not bound to {skeleton.GetPath()}")
        start = query.ComputeSkinningTransforms(Usd.TimeCode(stage.GetStartTimeCode()))
        midpoint = query.ComputeSkinningTransforms(
            Usd.TimeCode((stage.GetStartTimeCode() + stage.GetEndTimeCode()) / 2)
        )
        for initial, animated in zip(start, midpoint):
            maximum_delta = max(
                maximum_delta,
                max(
                    abs(float(initial[row][column] - animated[row][column]))
                    for row in range(4)
                    for column in range(4)
                ),
            )
        skinned_meshes = [
            prim
            for prim in skel_root.GetPrim().GetChildren()
            if prim.IsA(UsdGeom.Mesh)
        ]
        if not skinned_meshes:
            raise RuntimeError(f"no mesh under {skel_root.GetPath()}")
        for mesh in skinned_meshes:
            skin_query = cache.GetSkinningQuery(mesh)
            if not skin_query or not skin_query.HasJointInfluences():
                raise RuntimeError(f"missing skin weights on {mesh.GetPath()}")
            binding = UsdSkel.BindingAPI(mesh)
            indices_primvar = binding.GetJointIndicesPrimvar()
            weights_primvar = binding.GetJointWeightsPrimvar()
            element_size = indices_primvar.GetElementSize()
            indices = indices_primvar.ComputeFlattened()
            weights = weights_primvar.ComputeFlattened()
            point_count = len(UsdGeom.Mesh(mesh).GetPointsAttr().Get())
            if element_size <= 0 or len(indices) != point_count * element_size:
                raise RuntimeError(f"joint-index cardinality mismatch on {mesh.GetPath()}")
            if len(weights) != len(indices):
                raise RuntimeError(f"joint-weight cardinality mismatch on {mesh.GetPath()}")
            for offset in range(0, len(indices), element_size):
                vertex_indices = indices[offset : offset + element_size]
                vertex_weights = weights[offset : offset + element_size]
                if any(index < 0 or index >= len(joints) for index in vertex_indices):
                    raise RuntimeError(f"out-of-range joint index on {mesh.GetPath()}")
                if any(not math.isfinite(float(weight)) or weight < 0 for weight in vertex_weights):
                    raise RuntimeError(f"invalid joint weight on {mesh.GetPath()}")
                if abs(sum(float(weight) for weight in vertex_weights) - 1.0) > 2e-3:
                    raise RuntimeError(f"non-normalized joint weights on {mesh.GetPath()}")
    if len(skeleton_root_names) != len(set(skeleton_root_names)):
        raise RuntimeError("separate skeletons reuse a root joint namespace")
    redundant_xforms = [
        prim.GetPath()
        for prim in stage.Traverse()
        if prim.IsA(UsdGeom.Xform)
        and any(attribute.ValueMightBeTimeVarying() for attribute in prim.GetAttributes())
    ]
    if redundant_xforms:
        raise RuntimeError(
            "redundant animated Xform graph remains: "
            + ", ".join(str(path) for path in redundant_xforms[:3])
        )
    if maximum_delta < 1e-5:
        raise RuntimeError("animation samples do not move the skeleton")
    return len(skeletons), len(meshes), maximum_delta


def package_usdz(usdc_path, output_path):
    if output_path.exists():
        output_path.unlink()
    subprocess.run(
        [
            "/usr/bin/usdzip",
            "--arkitAsset",
            usdc_path.name,
            str(output_path),
        ],
        check=True,
        cwd=usdc_path.parent,
    )
    normalize_usdz_timestamps(output_path)
    result = subprocess.run(
        ["/usr/bin/usdchecker", "--arkit", "-t", str(output_path)],
        check=False,
        capture_output=True,
        text=True,
    )
    validation_output = result.stdout + result.stderr
    if result.returncode != 0 or "Success!" not in validation_output:
        raise RuntimeError(f"USD validation failed:\n{validation_output}")


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("model", type=Path)
    parser.add_argument("animation_library", type=Path)
    parser.add_argument("gltf2usd_checkout", type=Path)
    parser.add_argument("output", type=Path)
    parser.add_argument("--clip", default="Sprint_Loop")
    parser.add_argument("--fps", type=float, default=30.0)
    parser.add_argument("--allow-unverified-source", action="store_true")
    arguments = parser.parse_args()
    arguments.output = arguments.output.resolve()
    if arguments.output.suffix.lower() != ".usdz":
        parser.error("output must end in .usdz")
    arguments.output.parent.mkdir(parents=True, exist_ok=True)

    model_hash, animation_hash = verify_inputs(
        arguments.model,
        arguments.animation_library,
        arguments.gltf2usd_checkout,
        arguments.allow_unverified_source,
    )
    with tempfile.TemporaryDirectory(prefix="replayxi-usdz-") as temporary:
        temporary_root = Path(temporary)
        converter_script = copy_and_patch_converter(
            arguments.gltf2usd_checkout,
            temporary_root / "gltf2usd",
        )
        retargeted_glb = temporary_root / "retargeted.glb"
        make_retargeted_glb(
            arguments.model,
            arguments.animation_library,
            arguments.clip,
            retargeted_glb,
        )
        gltf_directory = temporary_root / "gltf"
        gltf_directory.mkdir()
        gltf_path = extract_clip_gltf(
            retargeted_glb,
            arguments.clip,
            gltf_directory,
        )
        usd_directory = temporary_root / "usd"
        usd_directory.mkdir()
        usdc_path = usd_directory / "player.usdc"
        run_converter(converter_script, gltf_path, usdc_path, arguments.fps)
        postprocess_usd(
            usdc_path,
            arguments.clip,
            model_hash,
            animation_hash,
        )
        skeletons, meshes, delta = validate_skinning(usdc_path)
        candidate = temporary_root / arguments.output.name
        package_usdz(usdc_path, candidate)
        audit_script = Path(__file__).with_name("audit_replayxi_player_usdz.py")
        subprocess.run(
            [sys.executable, str(audit_script), str(candidate)],
            check=True,
        )
        shutil.copy2(candidate, arguments.output)

    print(
        f"created {arguments.output} ({arguments.output.stat().st_size} bytes); "
        f"clip={arguments.clip}, skeletons={skeletons}, meshes={meshes}, "
        f"animatedDelta={delta:.6f}, sha256={sha256(arguments.output)}"
    )


if __name__ == "__main__":
    main()
