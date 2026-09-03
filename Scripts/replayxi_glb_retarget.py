#!/usr/bin/env python3
"""Retarget selected Quaternius GLB clips onto a compatible character GLB.

This is deliberately a narrow build-time tool, not a general humanoid
retargeter. It requires unique, matching joint names and keeps the target
character's bind pose and bone lengths. Only rotations plus root/pelvis
translations are copied, preventing mannequin proportions from stretching the
target mesh.
"""

import argparse
import json

import numpy as np
from pygltflib import (
    GLTF2,
    Accessor,
    Animation,
    AnimationChannel,
    AnimationChannelTarget,
    AnimationSampler,
    BufferView,
)


COMPONENT_FORMAT = {
    5120: "b",
    5121: "B",
    5122: "h",
    5123: "H",
    5125: "I",
    5126: "f",
}
TYPE_WIDTH = {"SCALAR": 1, "VEC2": 2, "VEC3": 3, "VEC4": 4, "MAT4": 16}


def accessor_array(gltf, blob, index):
    accessor = gltf.accessors[index]
    sparse = getattr(accessor, "sparse", None)
    if sparse is not None and getattr(sparse, "count", 0):
        raise ValueError(
            f"Sparse accessor {index} is unsupported by the locked retargeter; "
            "expand it before conversion"
        )
    if accessor.componentType not in COMPONENT_FORMAT or accessor.type not in TYPE_WIDTH:
        raise ValueError(f"Unsupported accessor encoding at index {index}")
    width = TYPE_WIDTH[accessor.type]
    dtype = np.dtype("<" + COMPONENT_FORMAT[accessor.componentType])
    if accessor.bufferView is None:
        return np.zeros((accessor.count, width), dtype=dtype)
    view = gltf.bufferViews[accessor.bufferView]
    offset = (view.byteOffset or 0) + (accessor.byteOffset or 0)
    packed = width * dtype.itemsize
    stride = view.byteStride or packed
    if stride < packed:
        raise ValueError(f"Accessor {index} byte stride is smaller than one element")
    required = offset + ((accessor.count - 1) * stride if accessor.count else 0) + packed
    if required > len(blob):
        raise ValueError(f"Accessor {index} reads beyond the GLB binary chunk")
    if stride == packed:
        return np.frombuffer(
            blob,
            dtype=dtype,
            count=accessor.count * width,
            offset=offset,
        ).reshape(accessor.count, width).copy()
    result = np.empty((accessor.count, width), dtype=dtype)
    for row in range(accessor.count):
        start = offset + row * stride
        result[row] = np.frombuffer(blob, dtype=dtype, count=width, offset=start)
    return result


def quat_normalize(quaternion):
    norm = np.linalg.norm(quaternion, axis=-1, keepdims=True)
    return quaternion / np.where(norm > 1e-8, norm, 1.0)


def quat_inverse(quaternion):
    result = quaternion.copy()
    result[..., :3] *= -1
    denominator = np.sum(quaternion * quaternion, axis=-1, keepdims=True)
    return result / np.where(denominator > 1e-8, denominator, 1.0)


def quat_multiply(lhs, rhs):
    lx, ly, lz, lw = np.moveaxis(lhs, -1, 0)
    rx, ry, rz, rw = np.moveaxis(rhs, -1, 0)
    return np.stack(
        (
            lw * rx + lx * rw + ly * rz - lz * ry,
            lw * ry - lx * rz + ly * rw + lz * rx,
            lw * rz + lx * ry - ly * rx + lz * rw,
            lw * rw - lx * rx - ly * ry - lz * rz,
        ),
        axis=-1,
    )


def node_rotation(node):
    return np.asarray(node.rotation or [0.0, 0.0, 0.0, 1.0], dtype=np.float32)


def node_translation(node):
    return np.asarray(node.translation or [0.0, 0.0, 0.0], dtype=np.float32)


def joint_parent_names(gltf, joint_indices):
    parents = {}
    for parent_index, node in enumerate(gltf.nodes):
        for child_index in node.children or []:
            if child_index in parents:
                raise ValueError(f"Node {child_index} has more than one parent")
            parents[child_index] = parent_index
    joint_set = set(joint_indices)
    return {
        gltf.nodes[index].name: (
            gltf.nodes[parents[index]].name if parents.get(index) in joint_set else None
        )
        for index in joint_indices
    }


def validate_compatible_rigs(base, library):
    if len(base.skins or []) != 1 or len(library.skins or []) != 1:
        raise ValueError("Retargeting requires exactly one skin in each GLB")
    model_joints = list(base.skins[0].joints or [])
    source_joints = list(library.skins[0].joints or [])
    if not model_joints or not source_joints:
        raise ValueError("Retargeting requires non-empty skin joint orders")
    model_names = [base.nodes[index].name for index in model_joints]
    source_names = [library.nodes[index].name for index in source_joints]
    if len(model_names) != len(set(model_names)) or len(source_names) != len(set(source_names)):
        raise ValueError("Retargeting requires unique joint names")
    if set(model_names) != set(source_names):
        missing = sorted(set(model_names) - set(source_names))
        extra = sorted(set(source_names) - set(model_names))
        raise ValueError(f"Skin joint sets differ; missing={missing}, extra={extra}")
    model_parents = joint_parent_names(base, model_joints)
    source_parents = joint_parent_names(library, source_joints)
    if model_parents != source_parents:
        raise ValueError("Skin joint hierarchies differ by name")


def validate_clip(library, blob, animation, joint_names):
    channels = {}
    for channel in animation.channels:
        node = library.nodes[channel.target.node]
        key = (node.name, channel.target.path)
        if key in channels:
            raise ValueError(f"Animation has duplicate channel {key}")
        channels[key] = channel
        sampler = animation.samplers[channel.sampler]
        interpolation = sampler.interpolation or "LINEAR"
        if interpolation not in ("LINEAR", "STEP"):
            raise ValueError(
                f"Animation channel {key} uses unsupported {interpolation} interpolation"
            )
        times = accessor_array(library, blob, sampler.input).reshape(-1)
        values = accessor_array(library, blob, sampler.output)
        if len(times) != len(values):
            raise ValueError(f"Animation channel {key} has mismatched key/value counts")
        if len(times) == 0 or not np.all(np.isfinite(times)) or not np.all(np.isfinite(values)):
            raise ValueError(f"Animation channel {key} contains empty or non-finite samples")
        if np.any(np.diff(times) <= 0):
            raise ValueError(f"Animation channel {key} times are not strictly increasing")
        expected_width = {"translation": 3, "rotation": 4, "scale": 3}.get(
            channel.target.path
        )
        if expected_width is None or values.shape[1] != expected_width:
            raise ValueError(f"Animation channel {key} has an invalid value shape")
        if channel.target.path == "rotation":
            norms = np.linalg.norm(values, axis=1)
            if np.any(norms < 0.98) or np.any(norms > 1.02):
                raise ValueError(f"Animation channel {key} has non-unit quaternions")

    missing_rotations = sorted(name for name in joint_names if (name, "rotation") not in channels)
    if missing_rotations:
        raise ValueError(f"Animation is missing joint rotations: {missing_rotations}")
    for required_translation in ("root", "pelvis"):
        if (required_translation, "translation") not in channels:
            raise ValueError(f"Animation is missing {required_translation} translation")


def align4(data):
    padding = (-len(data)) % 4
    if padding:
        data.extend(b"\0" * padding)


def append_accessor(base, output_blob, values, accessor_type, *, minmax=False):
    values = np.asarray(values, dtype=np.float32)
    align4(output_blob)
    offset = len(output_blob)
    payload = values.astype("<f4", copy=False).tobytes(order="C")
    output_blob.extend(payload)
    view_index = len(base.bufferViews)
    base.bufferViews.append(
        BufferView(buffer=0, byteOffset=offset, byteLength=len(payload))
    )
    arguments = {
        "bufferView": view_index,
        "byteOffset": 0,
        "componentType": 5126,
        "count": len(values),
        "type": accessor_type,
    }
    if minmax:
        flattened = values.reshape(len(values), -1)
        arguments["min"] = flattened.min(axis=0).tolist()
        arguments["max"] = flattened.max(axis=0).tolist()
    accessor_index = len(base.accessors)
    base.accessors.append(Accessor(**arguments))
    return accessor_index


def retarget(base, library, clip_names):
    base_blob = bytearray(base.binary_blob())
    library_blob = library.binary_blob()
    validate_compatible_rigs(base, library)
    model_nodes = {node.name: index for index, node in enumerate(base.nodes)}
    source_nodes = {node.name: index for index, node in enumerate(library.nodes)}
    if len(model_nodes) != len(base.nodes) or len(source_nodes) != len(library.nodes):
        raise ValueError("Retargeting requires unique node names")
    if "Head" not in model_nodes or "Head" not in source_nodes:
        raise ValueError("Expected a shared Quaternius humanoid Head joint")

    model_head = abs(node_translation(base.nodes[model_nodes["Head"]])[1])
    source_head = abs(node_translation(library.nodes[source_nodes["Head"]])[1])
    translation_scale = model_head / source_head if source_head > 1e-6 else 1.0
    animations = []

    for clip_name in clip_names:
        source_animation = next(
            (animation for animation in library.animations if animation.name == clip_name),
            None,
        )
        if source_animation is None:
            raise ValueError(f"Animation not found: {clip_name}")
        validate_clip(
            library,
            library_blob,
            source_animation,
            [base.nodes[index].name for index in base.skins[0].joints],
        )
        output_animation = Animation(name=clip_name, channels=[], samplers=[])
        input_cache = {}

        for channel in source_animation.channels:
            source_node = library.nodes[channel.target.node]
            target_node_index = model_nodes.get(source_node.name)
            if target_node_index is None:
                continue
            path = channel.target.path
            if path not in ("rotation", "translation"):
                continue
            if path == "translation" and source_node.name not in ("root", "pelvis"):
                continue

            source_sampler = source_animation.samplers[channel.sampler]
            input_index = input_cache.get(source_sampler.input)
            if input_index is None:
                times = accessor_array(library, library_blob, source_sampler.input)
                input_index = append_accessor(
                    base,
                    base_blob,
                    times,
                    "SCALAR",
                    minmax=True,
                )
                input_cache[source_sampler.input] = input_index

            values = accessor_array(
                library,
                library_blob,
                source_sampler.output,
            ).astype(np.float32)
            if path == "rotation":
                source_rest = node_rotation(source_node)
                target_rest = node_rotation(base.nodes[target_node_index])
                source_rest_batch = np.broadcast_to(source_rest, values.shape)
                target_rest_batch = np.broadcast_to(target_rest, values.shape)
                delta = quat_multiply(quat_inverse(source_rest_batch), values)
                values = quat_normalize(quat_multiply(target_rest_batch, delta))
                # q and -q encode the same orientation. Keep adjacent samples
                # in one hemisphere so downstream SLERP never takes a long arc.
                for sample in range(1, len(values)):
                    if float(np.dot(values[sample - 1], values[sample])) < 0:
                        values[sample] *= -1
                output_type = "VEC4"
            else:
                source_rest = node_translation(source_node)
                target_rest = node_translation(base.nodes[target_node_index])
                values = target_rest + (values - source_rest) * translation_scale
                output_type = "VEC3"

            output_index = append_accessor(base, base_blob, values, output_type)
            sampler_index = len(output_animation.samplers)
            output_animation.samplers.append(
                AnimationSampler(
                    input=input_index,
                    output=output_index,
                    interpolation=source_sampler.interpolation or "LINEAR",
                )
            )
            output_animation.channels.append(
                AnimationChannel(
                    sampler=sampler_index,
                    target=AnimationChannelTarget(
                        node=target_node_index,
                        path=path,
                    ),
                )
            )
        animations.append(output_animation)

    base.animations = animations
    base.buffers[0].byteLength = len(base_blob)
    base.set_binary_blob(bytes(base_blob))
    return base


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("model")
    parser.add_argument("animation_library")
    parser.add_argument("output")
    parser.add_argument(
        "--clips",
        nargs="+",
        default=["Idle_Loop", "Sprint_Loop"],
    )
    arguments = parser.parse_args()
    base = GLTF2.load_binary(arguments.model)
    library = GLTF2.load_binary(arguments.animation_library)
    result = retarget(base, library, arguments.clips)
    result.save_binary(arguments.output)
    print(
        json.dumps(
            {
                "output": arguments.output,
                "animations": [animation.name for animation in result.animations],
                "nodes": len(result.nodes),
                "meshes": len(result.meshes),
            }
        )
    )


if __name__ == "__main__":
    main()
