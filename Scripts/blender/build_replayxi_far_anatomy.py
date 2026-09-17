"""Original Replay XI anatomical far meshes, authored through local Blender MCP.

Keep seven runtime models: torso, shorts, licensed static face, two legs and two
arms. Each limb uses three joints rather than the full 80-joint near skeleton.
Coordinates are metres, Y-up, +Z forward, matching the existing joint contract.
Run in the isolated Players124 modelling scene; no source scene is overwritten.
"""
import bpy
import bmesh
import math
from mathutils import Matrix, Vector


def loft(profiles, segments=10, cap_start=True, cap_end=True, axis="y"):
    """Profile = axis position, cross radii, cross-plane vertical offset."""
    points, faces, uvs = [], [], []
    for ring, (value, radius_x, radius_b, centre_b) in enumerate(profiles):
        for step in range(segments + 1):
            angle = 2 * math.pi * step / segments
            x, b = math.sin(angle) * radius_x, math.cos(angle) * radius_b + centre_b
            points.append((x, value, b) if axis == "y" else (x, b, value))
            uvs.append((step / segments, ring / max(len(profiles) - 1, 1)))
    stride = segments + 1
    for ring in range(len(profiles) - 1):
        for step in range(segments):
            a = ring * stride + step
            faces.extend([(a, a + stride, a + 1), (a + 1, a + stride, a + stride + 1)])
    for ring, enabled in [(0, cap_start), (len(profiles) - 1, cap_end)]:
        if not enabled:
            continue
        value, _, _, centre_b = profiles[ring]
        center = len(points)
        points.append((0, value, centre_b) if axis == "y" else (0, centre_b, value))
        uvs.append((0.5, ring / max(len(profiles) - 1, 1)))
        for step in range(segments):
            a = ring * stride + step
            faces.append((center, a + 1, a) if ring == 0 else (center, a, a + 1))
    return points, faces, uvs


def joined(parts):
    points, faces, uvs = [], [], []
    for p, f, uv in parts:
        offset = len(points)
        points.extend(p)
        faces.extend(tuple(i + offset for i in face) for face in f)
        uvs.extend(uv)
    return points, faces, uvs


def smoothstep(value):
    t = min(max(value, 0), 1)
    return t * t * (3 - 2 * t)


def make_mesh(collection, name, geometry, limb=None):
    points, faces, uvs = geometry
    mesh = bpy.data.meshes.new("ReplayXI124_" + name + "_Mesh")
    mesh.from_pydata(points, [], faces)
    mesh.update()
    # Consistent outward normals are derived from geometry in Blender, not
    # copied from the old cylindrical far silhouette.
    obj = bpy.data.objects.new("ReplayXI124_" + name, mesh)
    collection.objects.link(obj)
    editable = bmesh.new()
    editable.from_mesh(mesh)
    bmesh.ops.recalc_face_normals(editable, faces=list(editable.faces))
    editable.to_mesh(mesh)
    editable.free()
    layer = mesh.uv_layers.new(name="UVMap")
    for loop in mesh.loops:
        point = points[loop.vertex_index]
        if limb:
            lower, upper = (-0.82, 0.02) if limb == "Leg" else (-0.58, 0.02)
            t = min(max((upper - point[1]) / (upper - lower), 0), 1)
            layer.data[loop.index].uv = (0.5, 1 - (0.5 + t * 63) / 64)
        else:
            layer.data[loop.index].uv = uvs[loop.vertex_index]
    for polygon in mesh.polygons:
        polygon.use_smooth = True
    mesh.update()
    # Texture seams duplicate positions, not physical hard edges. Average only
    # their normals so the radial seam does not become a visible dark stripe.
    coincident = {}
    for vertex in mesh.vertices:
        key = tuple(round(value, 6) for value in vertex.co)
        coincident.setdefault(key, []).append(vertex.index)
    normals = [vertex.normal.copy() for vertex in mesh.vertices]
    for indices in coincident.values():
        if len(indices) > 1:
            normal = sum((normals[index] for index in indices), Vector()).normalized()
            for index in indices:
                normals[index] = normal
    mesh.normals_split_custom_set_from_vertices(normals)
    obj["replayxi_part"] = name
    obj["replayxi_license"] = "Original Replay XI geometry; no purchased reference geometry or textures"
    obj["replayxi_axes"] = "Y-up, +Z forward, metres"
    if limb:
        first = 0.39 if limb == "Leg" else 0.31
        second = 0.35 if limb == "Leg" else 0.275
        rig_data = bpy.data.armatures.new("ReplayXI124_" + limb + "_Skeleton")
        rig = bpy.data.objects.new("ReplayXI124_" + limb + "_Rig", rig_data)
        collection.objects.link(rig)
        bpy.context.view_layer.objects.active = rig
        rig.select_set(True)
        bpy.ops.object.mode_set(mode="EDIT")
        bones = []
        for index, offset in enumerate([0, first, first + second]):
            bone = rig_data.edit_bones.new(["Root", "Bend", "Tip"][index])
            bone.length = 0.10
            bone.matrix = Matrix.Translation((0, -offset, 0))
            if index:
                bone.parent = bones[index - 1]
            bones.append(bone)
        bpy.ops.object.mode_set(mode="OBJECT")
        rig.select_set(False)
        groups = [obj.vertex_groups.new(name=name) for name in ["Root", "Bend", "Tip"]]
        for vertex in mesh.vertices:
            y = vertex.co.y
            if limb == "Leg" and vertex.index >= obj.get("replayxi_boot_start", len(mesh.vertices)):
                weights = [0, 0, 1]
            else:
                bend = smoothstep((-y - first + 0.055) / 0.11)
                tip = smoothstep((-y - first - second + 0.035) / 0.07)
                weights = [1 - bend, bend * (1 - tip), tip]
            total = sum(weights)
            for group, weight in zip(groups, weights):
                if weight > 0:
                    group.add([vertex.index], weight / total, "REPLACE")
        modifier = obj.modifiers.new("ReplayXI124_ThreeJointSkin", "ARMATURE")
        modifier.object = rig
        modifier.use_deform_preserve_volume = False
        obj.parent = rig
        obj["replayxi_joint_offsets"] = [0, -first, -second]
    return obj


def build():
    if bpy.context.scene.name != "ReplayXI Players124 - Local modelling":
        raise RuntimeError("Only the isolated124 workspace may be edited")
    if bpy.data.collections.get("ReplayXI124_CanonicalParts"):
        raise RuntimeError("Candidate already exists; inspect before creating a new revision")
    collection = bpy.data.collections.new("ReplayXI124_CanonicalParts")
    bpy.context.scene.collection.children.link(collection)

    torso = loft([
        (-0.025, .165, .102, -.003), (.015, .174, .106, -.004),
        (.090, .180, .113, -.005), (.210, .193, .127, -.007),
        (.335, .214, .140, -.004), (.435, .229, .141, -.002),
        (.485, .218, .132, -.004), (.525, .160, .099, -.006),
        (.554, .082, .065, .003), (.572, .080, .064, .005),
    ], segments=14, cap_end=False)
    make_mesh(collection, "Torso", torso)

    # A compact pelvic bridge; the top of each articulated leg supplies its
    # moving shorts cuff, avoiding a single skirt-shaped lower silhouette.
    shorts = loft([
        (-.140, .136, .083, .012), (-.092, .170, .117, -.004),
        (-.015, .200, .142, -.010), (.055, .191, .132, -.005),
        (.100, .176, .114, -.001),
    ], segments=12)
    make_mesh(collection, "Shorts", shorts)

    upper_leg = loft([
        (.030, .087, .097, .000), (-.045, .103, .113, -.004),
        (-.130, .103, .109, -.009), (-.215, .089, .097, -.012),
        (-.315, .069, .076, -.005), (-.372, .061, .068, .006),
        (-.408, .061, .069, .009), (-.465, .069, .081, -.004),
        (-.545, .074, .089, -.018), (-.630, .062, .074, -.020),
        (-.705, .045, .051, -.005), (-.750, .043, .047, .003),
    ], segments=10)
    boot = loft([
        (-.087, .034, .035, -.779), (-.065, .048, .048, -.780),
        (-.010, .060, .047, -.783), (.060, .068, .037, -.792),
        (.125, .065, .027, -.802), (.180, .047, .023, -.807),
        (.200, .021, .013, -.811),
    ], segments=10, axis="z")
    # Flatten only the physical sole; the upper retains a rounded instep/toe.
    boot = ([(x, max(y, -.832), z) for x, y, z in boot[0]], boot[1], boot[2])
    leg = make_mesh(collection, "Leg", joined([upper_leg, boot]), limb="Leg")
    leg["replayxi_boot_start"] = len(upper_leg[0])
    # All boot vertices follow the ankle exactly rather than blending to shin.
    for vertex in leg.data.vertices[len(upper_leg[0]):]:
        for group in leg.vertex_groups:
            group.remove([vertex.index])
        leg.vertex_groups["Tip"].add([vertex.index], 1, "REPLACE")

    arm = loft([
        (.068, .032, .039, .002), (.039, .067, .078, .000),
        (-.018, .083, .091, -.003), (-.090, .075, .078, -.003),
        (-.157, .063, .066, .000), (-.230, .056, .060, .005),
        (-.290, .045, .050, .008), (-.326, .044, .047, .006),
        (-.382, .051, .055, -.001), (-.462, .043, .047, .001),
        (-.548, .030, .034, .007), (-.583, .029, .031, .008),
        (-.614, .039, .025, .011), (-.670, .040, .021, .013),
        (-.710, .025, .013, .014),
    ], segments=10)
    make_mesh(collection, "Arm", arm, limb="Arm")
    result = []
    for obj in collection.objects:
        if obj.type != "MESH":
            continue
        obj.data.calc_loop_triangles()
        result.append({"part": obj["replayxi_part"], "vertices": len(obj.data.vertices),
                       "triangles": len(obj.data.loop_triangles),
                       "bones": len(obj.vertex_groups), "uvs": len(obj.data.uv_layers)})
    bpy.context.view_layer.update()
    return result


print(build())
