#!/usr/bin/env python3
"""Validate native study exports and emit safe-mode-compatible Blender MCP steps.

This does not extract tracking from video. It imports the app's licensed USD skin
and original pitch/ball, retaining authored-vs-observed evidence in every scene.
Generated steps are sent directly to Blender MCP; never exec/eval them in Blender.
They use allowed USD import/save/render operators, not external .blend loading.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import math
from pathlib import Path
import re

COORDINATES = "pitch-metres-x-width-z-length"
KINDS = {"receive", "pass", "shot", "dribbleTouch", "header", "save"}
REPO = Path(__file__).resolve().parents[2]
MAX_EXPORT_BYTES = 40 * 1024 * 1024
RIG_FIELDS = (("translations", 3), ("rotations", 4), ("scales", 3))
MAX_SCENE_SUFFIX_LENGTH = 16
# Blender ID names have a 63-byte compatibility budget. Keep even the longest
# study-scoped collection name intact; never truncate an identity into another.
MAX_REVISION_STUDY_ID_LENGTH = 63 - len('_ContactDiagnostics_optional')


class ContractError(ValueError):
    pass


def finite(value, label, low, high):
    if isinstance(value, bool) or not isinstance(value, (int, float)) or not math.isfinite(value):
        raise ContractError(f"{label} must be finite")
    if not low <= value <= high:
        raise ContractError(f"{label} outside [{low},{high}]")
    return float(value)


def identity(value, label):
    if not isinstance(value, str) or not re.fullmatch(r"[a-zA-Z0-9_-]{1,96}", value):
        raise ContractError(f"{label} must be a safe stable ID")
    return value


def text(value, label, maximum=2048):
    if not isinstance(value, str) or not 1 <= len(value) <= maximum:
        raise ContractError(f"{label} must be bounded text")
    return value


def validate_frames(frames, duration, ball=False):
    if not isinstance(frames, list) or not 2 <= len(frames) <= 12001:
        raise ContractError("tracks need 2–12001 samples")
    previous = -1
    for frame in frames:
        if not isinstance(frame, dict) or not isinstance(frame.get("position"), dict):
            raise ContractError("sample needs position")
        time = finite(frame.get("time"), "time", 0, duration)
        if time <= previous:
            raise ContractError("timestamps must strictly increase")
        previous = time
        finite(frame["position"].get("x"), "position.x", -45, 45)
        finite(frame["position"].get("z"), "position.z", -70, 70)
        finite(frame.get("height"), "height", 0.05, 20) if ball else finite(
            frame.get("facingDegrees"), "facingDegrees", -100000, 100000)
        if ball and "rotation" in frame:
            rotation = frame["rotation"]
            if not isinstance(rotation, list) or len(rotation) != 4:
                raise ContractError("ball rotation needs xyzw quaternion")
            for value in rotation:
                finite(value, "ball rotation", -1.01, 1.01)
            if abs(sum(v*v for v in rotation) - 1) > 0.02:
                raise ContractError("ball quaternion must be normalized")
    if abs(frames[0]["time"]) > 0.00001 or abs(frames[-1]["time"] - duration) > 0.02:
        raise ContractError("tracks must cover the full study")


def float32_vector(encoded):
    """Decode Swift Float bit patterns exactly using bounded arithmetic."""
    if not isinstance(encoded, str) or len(encoded) not in (24, 32) or not re.fullmatch('[0-9a-f]+', encoded):
        raise ContractError("Float32 vector needs 3 or 4 lowercase hex words")
    values = []
    for start in range(0, len(encoded), 8):
        bits = int(encoded[start:start + 8], 16)
        exponent, mantissa = (bits >> 23) & 255, bits & 0x7fffff
        if exponent == 255:
            raise ContractError("Float32 vector must be finite")
        value = math.ldexp(mantissa, -149) if exponent == 0 else math.ldexp(1 + mantissa / 8388608, exponent - 127)
        values.append(-value if bits >> 31 else value)
    return values


def native_pose_frames(rig):
    """Expand exact numeric row references, never executable data or quantization.

    Expansion is per frame so a valid compact file cannot materialize a second
    full, much larger 22-player pose document merely for contract validation.
    """
    if "_decodedVectors" in rig:
        raise ContractError("native payload cannot supply a runtime decoder cache")
    encoding = rig.get("transformEncoding")
    if encoding is None:
        if "vectorTable" in rig:
            raise ContractError("vector table needs its explicit encoding")
        yield from rig["frames"]
        return
    if encoding not in {"vector-table-v1", "float32-vector-table-v1"}:
        raise ContractError("unsupported native pose encoding")
    table = rig.get("vectorTable")
    if not isinstance(table, list) or not 1 <= len(table) <= 120000:
        raise ContractError("native vector table must be bounded")
    if encoding == "float32-vector-table-v1":
        table = [float32_vector(row) for row in table]
    for row in table:
        if not isinstance(row, list) or len(row) not in (3, 4):
            raise ContractError("native vector table rows need 3 or 4 values")
        for value in row:
            finite(value, "native vector", -10, 10)
    for frame in rig["frames"]:
        if not isinstance(frame, dict):
            raise ContractError("rig sample must be an object")
        expanded = {"time": frame.get("time")}
        for field, width in RIG_FIELDS:
            indices = frame.get(field)
            if not isinstance(indices, list) or len(indices) != 80:
                raise ContractError("native vector indices must match 80 joints")
            rows = []
            for index in indices:
                if isinstance(index, bool) or not isinstance(index, int) or not 0 <= index < len(table):
                    raise ContractError("native vector index is out of range or not an integer")
                if len(table[index]) != width:
                    raise ContractError("native vector index has the wrong transform width")
                rows.append(table[index])
            expanded[field] = rows
        yield expanded


def validate_document(doc):
    if not isinstance(doc, dict) or doc.get("schemaVersion") != 1 or doc.get("coordinateSystem") != COORDINATES:
        raise ContractError("unsupported schema or coordinate system")
    studies = doc.get("studies")
    if not isinstance(studies, list) or not 1 <= len(studies) <= 5:
        raise ContractError("expected 1–5 explicitly labelled short studies")
    ids = set()
    for study in studies:
        if not isinstance(study, dict):
            raise ContractError("study must be an object")
        sid = identity(study.get("id"), "study.id")
        if sid in ids:
            raise ContractError("duplicate study ID")
        ids.add(sid)
        text(study.get("title"), "title", 160)
        duration = finite(study.get("duration"), "duration", 0.1, 90)
        source = study.get("source")
        if not isinstance(source, dict) or not str(source.get("url", "")).startswith("https://"):
            raise ContractError("source needs an HTTPS reference URL")
        # A URL is a reference citation, not proof that a local video is present.
        for key in ("windowStartSeconds", "windowEndSeconds"):
            if source.get(key) is not None:
                finite(source[key], key, 0, 18000)
        if source.get("windowStartSeconds") is not None and source.get("windowEndSeconds") is not None:
            if source["windowEndSeconds"] <= source["windowStartSeconds"]:
                raise ContractError("source window is reversed")
        players = study.get("players")
        if not isinstance(players, list) or len(players) != 22:
            raise ContractError("each study needs exactly 22 players")
        player_ids, jerseys, counts = set(), set(), {"home": 0, "away": 0}
        for player in players:
            pid = identity(player.get("id"), "player.id")
            team, shirt = player.get("team"), player.get("shirtNumber")
            if team not in counts or pid in player_ids:
                raise ContractError("invalid team or duplicate player ID")
            if isinstance(shirt, bool) or not isinstance(shirt, int) or not 1 <= shirt <= 99 or (team, shirt) in jerseys:
                raise ContractError("shirt numbers must be unique within each team")
            player_ids.add(pid)
            jerseys.add((team, shirt))
            counts[team] += 1
            text(player.get("displayName"), "displayName", 96)
            evidence = player.get("evidence")
            if not isinstance(evidence, dict) or evidence.get("origin") not in {"authored", "inferred", "observed", "measured"}:
                raise ContractError("player needs declared evidence origin")
            if evidence.get("sourceVisibility") not in {"visible", "occluded", "off-camera", "unknown", "mixed"}:
                raise ContractError("player needs source visibility")
            if evidence.get("confidence") is not None:
                finite(evidence["confidence"], "confidence", 0, 1)
            validate_frames(player.get("keyframes"), duration)
        if counts != {"home": 11, "away": 11}:
            raise ContractError("each team needs 11 players")
        ball = study.get("ball")
        if not isinstance(ball, dict) or ball.get("source") != "native-physics-recording":
            raise ContractError("ball must be a declared native physics recording")
        validate_frames(ball.get("keyframes"), duration, ball=True)
        contacts = study.get("contacts", [])
        if not isinstance(contacts, list) or len(contacts) > 256:
            raise ContractError("contacts must be bounded")
        for contact in contacts:
            if contact.get("playerID") not in player_ids or contact.get("kind") not in KINDS:
                raise ContractError("contact must identify a known player and kind")
            finite(contact.get("time"), "contact.time", 0, duration)
            position = contact.get("position", {})
            for axis, bound in (("x", 45), ("y", 20), ("z", 70)):
                finite(position.get(axis), f"contact.position.{axis}", -bound, bound)
            if "headerSupportLeg" in contact and (contact["kind"] != "header"
                                                    or contact["headerSupportLeg"] not in {"left", "right"}):
                raise ContractError("only a header may name a support leg")
        posed_players = set()
        rigs = study.get("rigPoses", [])
        if not isinstance(rigs, list) or len(rigs) > 22:
            raise ContractError("rig poses must be a bounded list")
        for rig in rigs:
            if not isinstance(rig, dict):
                raise ContractError("rig pose must be an object")
            if rig.get("playerID") not in player_ids or rig["playerID"] in posed_players:
                raise ContractError("rig poses need distinct roster players")
            posed_players.add(rig["playerID"])
            if rig.get("source") != "native-rig-pose-samples":
                raise ContractError("rig pose source must be explicit")
            names = rig.get("jointNames")
            if (not isinstance(names, list) or len(names) != 80
                    or not all(isinstance(name, str) and 1 <= len(name) <= 256 for name in names)
                    or len(set(names)) != 80):
                raise ContractError("native rig must have 80 unique joints")
            finite(rig.get("groundOffset"), "rig.groundOffset", -0.5, 0.5)
            frames = rig.get("frames")
            if not isinstance(frames, list) or not 2 <= len(frames) <= 2000:
                raise ContractError("rig pose samples must be bounded")
            previous = -1
            for frame in native_pose_frames(rig):
                if not isinstance(frame, dict):
                    raise ContractError("rig sample must be an object")
                time = finite(frame.get("time"), "rig.time", 0, duration)
                if time <= previous:
                    raise ContractError("rig timestamps must strictly increase")
                previous = time
                for field, width in RIG_FIELDS:
                    rows = frame.get(field)
                    if not isinstance(rows, list) or len(rows) != 80:
                        raise ContractError("rig pose does not match joint count")
                    for row in rows:
                        if not isinstance(row, list) or len(row) != width:
                            raise ContractError("rig pose transform width invalid")
                        for value in row:
                            finite(value, "rig transform", 0.01 if field == "scales" else -10, 10)
                if any(abs(sum(v*v for v in q)-1) > 0.01 for q in frame["rotations"]):
                    raise ContractError("rig quaternions must be normalized")
            if abs(frames[0]["time"]) > 0.00001 or abs(frames[-1]["time"] - duration) > 0.02:
                raise ContractError("rig samples must cover the full study")
        sampling = study.get("rigSampling")
        if sampling is not None:
            if not isinstance(sampling, dict) or sampling.get("scope") not in {"all-players", "contact-players"}:
                raise ContractError("rig sampling scope must be explicit")
            finite(sampling.get("frequencyHz"), "rig sample frequency", 1, 30)
            if sampling.get("includesExactContacts") is not True or not isinstance(sampling.get("tacticalAttention"), bool):
                raise ContractError("rig sampling needs contact and attention declarations")
            if sampling["scope"] == "all-players":
                if posed_players != player_ids or sampling["tacticalAttention"] is not True:
                    raise ContractError("all-player native export requires every rig and tactical attention")
                for rig in rigs:
                    player = next(p for p in players if p["id"] == rig["playerID"])
                    root_times = {frame["time"] for frame in player["keyframes"]}
                    rig_times = {frame["time"] for frame in rig["frames"]}
                    if not rig_times <= root_times:
                        raise ContractError("every native rig instant must have its exact root pose")
                    contact_times = {c["time"] for c in contacts if c["playerID"] == rig["playerID"]}
                    if not contact_times <= rig_times:
                        raise ContractError("native rig export must include exact contact instants")
    return doc


def read_document(path):
    path = Path(path)
    if path.stat().st_size > MAX_EXPORT_BYTES:
        raise ContractError("export exceeds 40 MB")
    raw = path.read_bytes()
    return validate_document(json.loads(raw)), hashlib.sha256(raw).hexdigest()


def authoring_document(document, scene_suffix=None, exclude_studies=()):
    """Clone validated source data; a revision never changes app/save identity.

    The returned ``id`` is an authoring namespace only. Source JSON bytes, their
    digest, player IDs, numerical samples and evidence are untouched.
    """
    if scene_suffix is not None and (not isinstance(scene_suffix, str)
            or not 1 <= len(scene_suffix) <= MAX_SCENE_SUFFIX_LENGTH
            or not re.fullmatch(r'[a-z][a-z0-9_-]*', scene_suffix)):
        raise ContractError('scene suffix must be 1–16 lowercase ASCII letters, digits, _ or -; start with a letter')
    source = validate_document(document)
    available = {study['id'] for study in source['studies']}
    excluded = set(exclude_studies)
    if excluded - available:
        raise ContractError('excluded study does not exist')
    selected = [study for study in source['studies'] if study['id'] not in excluded]
    if not selected:
        raise ContractError('selection contains no studies')
    if any('scenarioID' in study or 'authoringRevision' in study for study in selected):
        raise ContractError('source study already has authoring revision metadata; use the original native export')
    if scene_suffix is not None:
        revised = set()
        for study in selected:
            sid = study['id'] + '--' + scene_suffix
            if len(sid) > MAX_REVISION_STUDY_ID_LENGTH:
                raise ContractError(f'revised study ID exceeds {MAX_REVISION_STUDY_ID_LENGTH} ASCII characters')
            if sid in revised or sid in available:
                raise ContractError('authoring revision collides with a source study ID')
            revised.add(sid)
    result = json.loads(json.dumps(source))
    result['studies'] = [study for study in result['studies'] if study['id'] not in excluded]
    if scene_suffix is not None:
        for study in result['studies']:
            study['scenarioID'] = study['id']
            study['authoringRevision'] = scene_suffix
            study['id'] += '--' + scene_suffix
    return result


def world_point(x, y, z):
    """Right-handed native Y-up -> Blender Z-up; preserves every rotation."""
    return -x, z, y


def heading_angles(frames):
    result, previous = [], None
    for frame in frames:
        angle = math.pi + math.radians(frame["facingDegrees"])
        if previous is not None:
            angle = previous + (angle - previous + math.pi) % math.tau - math.pi
        result.append(angle)
        previous = angle
    return result


def gait_keys(frames, fps):
    """Distance-clocked illustrative source gait, not recovered limb motion."""
    result, distance = [], 0.0
    for index, frame in enumerate(frames):
        if index:
            previous = frames[index - 1]
            distance += math.hypot(frame["position"]["x"] - previous["position"]["x"],
                                   frame["position"]["z"] - previous["position"]["z"])
        left, right = frames[max(index - 1, 0)], frames[min(index + 1, len(frames) - 1)]
        speed = math.hypot(right["position"]["x"] - left["position"]["x"],
                           right["position"]["z"] - left["position"]["z"]) / max(right["time"] - left["time"], 0.00001)
        weight = min(max((speed - 0.12) / 1.5, 0), 1)
        weight = weight * weight * (3 - 2 * weight)
        result.append([1 + frame["time"] * fps, distance / 2.4, weight])
    return result


# Shared safe-mode code: no filesystem IO, arbitrary module loads, exec, handlers,
# drivers, timers or external Blender library links. JSON is non-executable scene
# metadata: safe mode deliberately forbids script-capable Text datablocks.
RUNTIME = r'''
import bpy, json, math
from mathutils import Matrix, Quaternion, Vector

def rx_assert_revision_namespace_available(study_ids, allow_staged_data=False):
    assets=bpy.data.scenes.get('ReplayXI_Reference127_Assets')
    for sid in study_ids:
        if bpy.data.scenes.get('ReplayXI_Study_'+sid):
            raise ValueError('Study scene already exists; never overwrite: '+sid)
        if not allow_staged_data and assets is not None and 'RX127_Study_'+sid in assets:
            raise ValueError('Reference data already exists: '+sid)
        for kind,items in (('objects',bpy.data.objects),('collections',bpy.data.collections),
                           ('meshes',bpy.data.meshes),('armatures',bpy.data.armatures),
                           ('curves',bpy.data.curves),('cameras',bpy.data.cameras),
                           ('lights',bpy.data.lights),('worlds',bpy.data.worlds),('actions',bpy.data.actions)):
            if any(item.name==sid or item.name.startswith(sid+'_') for item in items):
                raise ValueError('Authoring namespace already exists in '+kind+': '+sid)

def rx_link(scene, name, data=None, parent=None):
    obj = bpy.data.objects.new(name, data)
    scene.collection.objects.link(obj)
    obj.parent = parent
    return obj

def rx_linear(data):
    animation = data.animation_data
    if not animation or not animation.action:
        return
    action = animation.action
    if hasattr(action, 'fcurves'):
        curves = action.fcurves
    else:
        curves = [c for layer in action.layers for strip in layer.strips
                  for c in strip.channelbag(animation.action_slot).fcurves]
    for curve in curves:
        for key in curve.keyframe_points:
            key.interpolation = 'LINEAR'

def rx_matrix(translation, rotation, scale):
    q = Quaternion((rotation[3], rotation[0], rotation[1], rotation[2]))
    return Matrix.LocRotScale(Vector(translation), q, Vector(scale))

def rx_pose_frame(payload, frame):
    encoding=payload.get('transformEncoding')
    if encoding is None:
        if 'vectorTable' in payload:raise ValueError('Vector table needs explicit encoding')
        return frame
    if encoding not in ('vector-table-v1','float32-vector-table-v1'):raise ValueError('Unknown native pose encoding')
    table=payload.get('_decodedVectors',payload.get('vectorTable'))
    if not isinstance(table,list) or not 1<=len(table)<=120000:raise ValueError('Invalid native vector table')
    if encoding=='float32-vector-table-v1' and '_decodedVectors' not in payload:
        decoded=[]
        for encoded in table:
            if not isinstance(encoded,str) or len(encoded) not in (24,32) or any(c not in '0123456789abcdef' for c in encoded):
                raise ValueError('Invalid Float32 vector')
            row=[]
            for start in range(0,len(encoded),8):
                bits=int(encoded[start:start+8],16)
                exponent,mantissa=(bits>>23)&255,bits&0x7fffff
                if exponent==255:raise ValueError('Non-finite Float32 vector')
                value=math.ldexp(mantissa,-149) if exponent==0 else math.ldexp(1+mantissa/8388608,exponent-127)
                row.append(-value if bits>>31 else value)
            decoded.append(row)
        table=decoded
        payload['_decodedVectors']=decoded
    expanded={'time':frame['time']}
    for field,width in (('translations',3),('rotations',4),('scales',3)):
        indices=frame.get(field)
        if not isinstance(indices,list) or len(indices)!=80:raise ValueError('Invalid native vector indices')
        rows=[]
        for index in indices:
            if isinstance(index,bool) or not isinstance(index,int) or not 0<=index<len(table):
                raise ValueError('Invalid native vector index')
            row=table[index]
            if not isinstance(row,list) or len(row)!=width:raise ValueError('Invalid native vector width')
            rows.append(row)
        expanded[field]=rows
    return expanded

def rx_text(scene, name, body, location, size=0.3, parent=None):
    curve = bpy.data.curves.new(name, 'FONT')
    curve.body, curve.size, curve.align_x = body, size, 'CENTER'
    curve.extrude = 0.001
    obj = rx_link(scene, name, curve, parent)
    obj.location = location
    return obj

def rx_line(scene, name, points, colour, width=0.025):
    curve = bpy.data.curves.new(name, 'CURVE')
    curve.dimensions, curve.bevel_depth, curve.bevel_resolution = '3D', width, 1
    spline = curve.splines.new('POLY')
    spline.points.add(len(points)-1)
    for vertex, point in zip(spline.points, points):
        vertex.co = (*point, 1)
    material = bpy.data.materials.get('RX127_'+colour)
    if not material:
        material = bpy.data.materials.new('RX127_'+colour)
        material.diffuse_color = {'cyan':(0.02,0.65,1,1),'orange':(1,0.35,0.03,1),'white':(1,1,1,1)}[colour]
    curve.materials.append(material)
    return rx_link(scene, name, curve)

def rx_clone(scene, templates, prefix, parent=None):
    copies = {}
    for original in templates:
        clone = original.copy()
        if original.type == 'ARMATURE':
            clone.data = original.data.copy()
        clone.animation_data_clear()
        clone.name = prefix+'_'+original.name
        scene.collection.objects.link(clone)
        copies[original] = clone
    for original, clone in copies.items():
        clone.parent = copies.get(original.parent, parent)
        clone.matrix_parent_inverse = original.matrix_parent_inverse.copy()
        clone.matrix_basis = original.matrix_basis.copy()
        for modifier in clone.modifiers:
            if modifier.type == 'ARMATURE' and modifier.object in copies:
                modifier.object = copies[modifier.object]
    return list(copies.values())

def rx_camera(scene, name, location, target=None, parent=None):
    obj = rx_link(scene,name,bpy.data.cameras.new(name),parent)
    obj.location = location
    obj.data.lens, obj.data.clip_end = 42, 500
    if target is not None:
        obj.rotation_euler = (Vector(target)-obj.location).to_track_quat('-Z','Y').to_euler()
    return obj

def rx_caption_backing(scene,camera,name,title):
    width=max(0.78,min(1.50,max(len(title),42)*0.025*0.58+0.09))
    height,radius=0.105,0.020
    vertices=[]
    for cx,cy,start in ((width/2-radius,height/2-radius,0),(-width/2+radius,height/2-radius,90),
                        (-width/2+radius,-height/2+radius,180),(width/2-radius,-height/2+radius,270)):
        for step in range(7):
            angle=math.radians(start+step*15)
            vertices.append((cx+radius*math.cos(angle),cy+radius*math.sin(angle),0))
    mesh=bpy.data.meshes.new(name)
    mesh.from_pydata(vertices,[],[tuple(range(len(vertices)))])
    obj=rx_link(scene,name,mesh,camera);obj.location=(0,-0.39,-2.006)
    material=bpy.data.materials.get('RX127_CaptionBacking')
    if not material:
        material=bpy.data.materials.new('RX127_CaptionBacking');material.use_nodes=True
        nodes=material.node_tree.nodes;nodes.clear()
        emission=nodes.new('ShaderNodeEmission');emission.inputs[0].default_value=(0.006,0.010,0.016,1)
        output=nodes.new('ShaderNodeOutputMaterial')
        material.node_tree.links.new(emission.outputs[0],output.inputs[0])
    mesh.materials.append(material)
    return obj

def rx_prepare_actions():
    motion=json.loads(bpy.data.scenes['ReplayXI_Reference127_Assets']['RX127_Motion'])
    rig=next(o for o in bpy.data.scenes['ReplayXI_Reference127_Assets'].objects if o.type=='ARMATURE')
    joints=motion['joints']
    for clip in motion['clips']:
        if bpy.data.actions.get('RX127_'+clip['id']):
            continue
        rig.animation_data_clear()
        for frame in clip['frames']:
            for index,joint in enumerate(joints):
                bone=rig.pose.bones[joint['name'].split('/')[-1]]
                rest=bone.bone.matrix_local
                if bone.parent:
                    rest=bone.parent.bone.matrix_local.inverted()@rest
                target=rx_matrix(frame['translations'][index],frame['rotations'][index],frame['scales'][index])
                bone.rotation_mode='QUATERNION'
                bone.matrix_basis=rest.inverted()@target
                for field in ('location','rotation_quaternion','scale'):
                    bone.keyframe_insert(field,frame=1+frame['time']*30)
        rig.animation_data.action.name='RX127_'+clip['id']
        rig.animation_data.action.use_fake_user=True
        rx_linear(rig)
    rig.animation_data_clear()

def rx_gait(rig, player, duration, fps):
    rig.animation_data_clear()
    rig.animation_data_create()
    keys=player['_gaitKeys']
    for clip in ('idle','run'):
        action=bpy.data.actions['RX127_'+clip]
        track=rig.animation_data.nla_tracks.new()
        track.name='Illustrative '+clip+'; not tracked limbs'
        strip=track.strips.new(clip,1,action)
        strip.action_frame_start,strip.action_frame_end=action.frame_range
        strip.use_animated_time=True
        strip.use_animated_time_cyclic=True
        strip.use_animated_influence=True
        strip.extrapolation='NOTHING'
        strip.frame_start,strip.frame_end=1,1+duration*fps
        start,end=action.frame_range
        for frame,cycles,weight in keys:
            strip.strip_time=start+(cycles if clip=='run' else (frame-1)/fps*0.5)*(end-start)
            strip.influence=weight if clip=='run' else 1
            strip.keyframe_insert('strip_time',frame=frame)
            strip.keyframe_insert('influence',frame=frame)
        for curve in strip.fcurves:
            for point in curve.keyframe_points:point.interpolation='LINEAR'
    rig['limbAnimation']='Distance-timed source idle/run; NOT captured match body motion'

def rx_native_pose(rig, payload, fps):
    rig.animation_data_clear()
    previous={}
    for encoded_frame in payload['frames']:
        frame=rx_pose_frame(payload,encoded_frame)
        for index,name in enumerate(payload['jointNames']):
            bone=rig.pose.bones.get(name.split('/')[-1])
            if bone is None:raise ValueError('Imported rig is missing joint '+name)
            rest=bone.bone.matrix_local
            if bone.parent:rest=bone.parent.bone.matrix_local.inverted()@rest
            target=rx_matrix(frame['translations'][index],frame['rotations'][index],frame['scales'][index])
            bone.rotation_mode='QUATERNION'
            bone.matrix_basis=rest.inverted()@target
            q=bone.rotation_quaternion.copy()
            if name in previous and q.dot(previous[name])<0:q.negate()
            bone.rotation_quaternion=q
            previous[name]=q.copy()
            for field in ('location','rotation_quaternion','scale'):
                bone.keyframe_insert(field,frame=1+frame['time']*fps)
    rx_linear(rig)
    rig['limbAnimation']='Native app rig samples, including exact admitted contact times; not captured match body motion'

def rx_build(study, fps, manifest_hash):
    sid=study['id']
    if study.get('authoringRevision'):
        rx_assert_revision_namespace_available([sid],allow_staged_data=True)
    scene_name='ReplayXI_Study_'+sid
    if bpy.data.scenes.get(scene_name):
        raise ValueError('Study scene already exists; never overwrite: '+sid)
    scene=bpy.data.scenes.new(scene_name)
    scene.unit_settings.system='METRIC'
    scene.render.fps=fps
    scene.frame_start,scene.frame_end=1,math.ceil(study['duration']*fps)+1
    scene.render.engine='BLENDER_EEVEE'
    scene.render.resolution_x,scene.render.resolution_y=1280,720
    scene.render.resolution_percentage=100
    scene['studyID'],scene['title']=sid,study['title']
    if study.get('authoringRevision'):
        scene['scenarioID']=study['scenarioID']
        scene['authoringRevision']=study['authoringRevision']
    scene['manifestSHA256']=manifest_hash
    scene['provenanceJSON']=json.dumps(study.get('provenance',{}))
    scene['sourceJSON']=json.dumps(study['source'])
    scene['rigSamplingJSON']=json.dumps(study.get('rigSampling',{}))
    scene['evidence']='Authored reconstruction, NOT recovered tracking; unknown off-camera positions'
    scene['coordinateMapping']='native (x,y,z) -> Blender (-x,z,y); right handed'
    assets=bpy.data.scenes['ReplayXI_Reference127_Assets']
    skin=[o for o in assets.objects if o.get('reference127Template')=='skin']
    pitch=[o for o in assets.objects if o.get('reference127Template')=='pitch']
    ball_templates=[o for o in assets.objects if o.get('reference127Template')=='ball']
    rx_clone(scene,pitch,sid+'_pitch')
    motion=json.loads(bpy.data.scenes['ReplayXI_Reference127_Assets']['RX127_Motion'])
    poses={p['playerID']:p for p in study.get('rigPoses',[])}
    if study.get('rigSampling',{}).get('scope')=='all-players' and len(poses)!=22:
        raise ValueError('All-player study cannot fall back to illustrative gait')
    scene['nativePosePlayerCount']=len(poses)
    rest_models=[]
    for joint in motion['joints']:
        local=rx_matrix(joint['translation'],joint['rotation'],joint['scale'])
        parent=joint['parentIndex']
        rest_models.append(rest_models[parent]@local if parent>=0 else local)
    chest_index=next(i for i,j in enumerate(motion['joints']) if j['name']==motion['numberAnchors']['joint'])
    rest_chest_rotation=rest_models[chest_index].to_quaternion()
    identity_labels=bpy.data.collections.new(sid+'_Identity_labels_optional')
    scene.collection.children.link(identity_labels)
    identity_labels.hide_render=True
    for player in study['players']:
        root=rx_link(scene,sid+'_'+player['id'])
        root['playerID'],root['shirtNumber'],root['team']=player['id'],player['shirtNumber'],player['team']
        root['displayName']=player['displayName']
        root['evidenceJSON']=json.dumps(player['evidence'])
        facing=rx_link(scene,root.name+'_Facing',parent=root)
        copies=rx_clone(scene,skin,root.name,facing)
        for clone in copies:
            if clone.parent==facing:
                clone.location.z+=poses[player['id']]['groundOffset'] if player['id'] in poses else -motion['geometry']['restMinY']
            if clone.type=='ARMATURE':
                if player['id'] in poses:rx_native_pose(clone,poses[player['id']],fps)
                else:rx_gait(clone,player,study['duration'],fps)
            if clone.type=='MESH' and 'Body' in clone.name:
                key='Keeper' if player.get('isGoalkeeper') else ('Home' if player['team']=='home' else 'Away')
                for index,slot in enumerate(clone.material_slots):
                    if slot.material:
                        source_material=slot.material
                        slot.link='OBJECT'
                        material=bpy.data.materials.get('RX127_Kit_'+key)
                        if not material:
                            material=source_material.copy()
                            material.name='RX127_Kit_'+key
                            image=bpy.data.images.get('RX127_'+key)
                            if image and material.use_nodes:
                                principled=next((n for n in material.node_tree.nodes if n.type=='BSDF_PRINCIPLED'),None)
                                if principled:
                                    node=material.node_tree.nodes.new('ShaderNodeTexImage')
                                    node.image=image
                                    uv=next((n for n in material.node_tree.nodes if n.type=='UVMAP'),None)
                                    if uv:material.node_tree.links.new(uv.outputs['UV'],node.inputs['Vector'])
                                    material.node_tree.links.new(node.outputs['Color'],principled.inputs['Base Color'])
                        slot.material=material
        for frame,angle in zip(player['keyframes'],player['_headingAngles']):
            root.location=(-frame['position']['x'],frame['position']['z'],0)
            root.keyframe_insert('location',frame=1+frame['time']*fps)
            facing.rotation_euler.z=angle
            facing.keyframe_insert('rotation_euler',index=2,frame=1+frame['time']*fps)
        rx_linear(root);rx_linear(facing)
        label=rx_text(scene,root.name+'_Identity',str(player['shirtNumber']),(0,0,2.12),0.32,root)
        label['displayName']=player['displayName']
        label['role']=player.get('role','')
        scene.collection.objects.unlink(label);identity_labels.objects.link(label)
        # Same source-joint anchors as the app: numbers follow chest motion,
        # not a rigid billboard floating where the torso used to be.
        rig=next(o for o in copies if o.type=='ARMATURE')
        anchor=rx_link(scene,root.name+'_ChestAnchor',parent=root)
        constraint=anchor.constraints.new('COPY_TRANSFORMS')
        constraint.target=rig
        constraint.subtarget=motion['numberAnchors']['joint'].split('/')[-1]
        constraint.target_space=constraint.owner_space='WORLD'
        for side,size in (('front',0.115),('back',0.23)):
            jersey=rx_text(scene,root.name+'_Jersey_'+side,str(player['shirtNumber']),
                           motion['numberAnchors'][side],size,anchor)
            jersey.data.align_y='CENTER'
            jersey.rotation_mode='QUATERNION'
            jersey.rotation_quaternion=rest_chest_rotation.inverted()@Quaternion(Vector((0,1,0)),math.pi if side=='back' else 0)
            ink_key='white' if player['team']=='away' else 'dark'
            ink=bpy.data.materials.get('RX127_Number_'+ink_key)
            if not ink:
                ink=bpy.data.materials.new('RX127_Number_'+ink_key)
            ink.diffuse_color=(0.95,0.97,1,1) if ink_key=='white' else (0.004,0.012,0.025,1)
            ink.use_nodes=True
            ink.node_tree.nodes['Principled BSDF'].inputs['Base Color'].default_value=ink.diffuse_color
            ink.node_tree.nodes['Principled BSDF'].inputs['Roughness'].default_value=0.8
            jersey.data.materials.append(ink)
        camera=rx_camera(scene,root.name+'_POV',(0,0,1.68),parent=root)
        camera.rotation_euler=(math.pi/2,0,player['_headingAngles'][0]-math.pi)
        camera['freeLook']='Translation follows player; camera rotation deliberately unkeyed'
        camera.data.lens,camera.data.clip_start=22,0.28
    ball_root=rx_link(scene,sid+'_BallRecording')
    rx_clone(scene,ball_templates,sid+'_ball',ball_root)
    ball_root['source']='Native RealityKit recording; Blender does not resimulate or attract it'
    ball_root.rotation_mode='QUATERNION'
    previous_rotation=None
    for frame in study['ball']['keyframes']:
        ball_root.location=(-frame['position']['x'],frame['position']['z'],frame['height'])
        ball_root.keyframe_insert('location',frame=1+frame['time']*fps)
        if 'rotation' in frame:
            x,y,z,w=frame['rotation']
            # C*q*C^-1 rotates in Blender's basis; Rz(pi) supplies the missing
            # half turn on the USD import's existing Rx(pi/2) model basis.
            rotation=Quaternion((w,-x,z,y))@Quaternion(Vector((0,0,1)),math.pi)
            if previous_rotation is not None and rotation.dot(previous_rotation)<0:rotation.negate()
            ball_root.rotation_quaternion=rotation
            previous_rotation=rotation.copy()
            ball_root.keyframe_insert('rotation_quaternion',frame=1+frame['time']*fps)
    rx_linear(ball_root)
    routes=bpy.data.collections.new(sid+'_Routes_optional')
    scene.collection.children.link(routes)
    for player in study['players']:
        points=[(-f['position']['x'],f['position']['z'],0.045) for f in player['keyframes']]
        obj=rx_line(scene,sid+'_Route_'+player['id'],points,'cyan' if player['team']=='home' else 'orange',0.018)
        scene.collection.objects.unlink(obj);routes.objects.link(obj)
        obj['evidenceJSON']=json.dumps(player['evidence'])
    routes.hide_render=True
    routes.hide_viewport=True
    diagnostics=bpy.data.collections.new(sid+'_ContactDiagnostics_optional')
    scene.collection.children.link(diagnostics)
    diagnostics.hide_render=True
    diagnostics.hide_viewport=True
    for index,contact in enumerate(study.get('contacts',[])):
        frame=1+contact['time']*fps
        player=next(p for p in study['players'] if p['id']==contact['playerID'])
        scene.timeline_markers.new(str(player['shirtNumber'])+' '+contact['kind'],frame=round(frame))
        position=contact['position']
        centre=(-position['x'],position['z'],max(position['y'],0.05))
        points=[(centre[0]+math.cos(i*math.tau/32)*0.18,centre[1]+math.sin(i*math.tau/32)*0.18,centre[2]) for i in range(33)]
        obj=rx_line(scene,sid+'_Contact_'+str(index),points,'white',0.008)
        scene.collection.objects.unlink(obj);diagnostics.objects.link(obj)
        obj['contactJSON']=json.dumps(contact)
        for stamp,hidden in ((0,True),(max(1,frame-fps*0.10),False),(frame+fps*0.10,True)):
            obj.hide_render=obj.hide_viewport=hidden
            obj.keyframe_insert('hide_render',frame=stamp);obj.keyframe_insert('hide_viewport',frame=stamp)
    all_points=[(-f['position']['x'],f['position']['z'],f['height']) for f in study['ball']['keyframes']]
    centre=Vector(tuple(sum(p[i] for p in all_points)/len(all_points) for i in range(3)))
    centre.z=0
    camera=rx_camera(scene,sid+'_Review',centre+Vector((38,-48,42)),centre+Vector((0,0,1)))
    camera.data.lens=40
    scene.camera=camera
    for label in identity_labels.objects:
        billboard=label.constraints.new('COPY_ROTATION');billboard.target=camera
    caption_title=study['title']+(' | '+study['authoringRevision'] if study.get('authoringRevision') else '')
    hud=rx_text(scene,sid+'_EvidenceHUD',caption_title+'\nAUTHORED REPLAY | OFF-CAMERA PATHS UNKNOWN',
                (0,-0.39,-2),0.025,camera)
    hud.data.align_y='CENTER'
    hud_material=bpy.data.materials.get('RX127_EvidenceText')
    if not hud_material:
        hud_material=bpy.data.materials.new('RX127_EvidenceText');hud_material.use_nodes=True
        nodes=hud_material.node_tree.nodes
        nodes.clear()
        emission=nodes.new('ShaderNodeEmission');emission.inputs[0].default_value=(1,1,1,1)
        output=nodes.new('ShaderNodeOutputMaterial')
        hud_material.node_tree.links.new(emission.outputs[0],output.inputs[0])
    hud.data.materials.append(hud_material)
    rx_caption_backing(scene,camera,sid+'_EvidenceBacking',caption_title)
    rx_camera(scene,sid+'_Tactical',(0,-70,105),(0,0,0)).data.lens=35
    rx_text(scene,sid+'_SourceLabel',study['title']+' | AUTHORED RECONSTRUCTION',(-0, -58,0.04),0.85)
    world=bpy.data.worlds.new(sid+'_Daylight');world.use_nodes=True
    world.node_tree.nodes['Background'].inputs[0].default_value=(0.35,0.45,0.65,1)
    world.node_tree.nodes['Background'].inputs[1].default_value=0.6
    scene.world=world
    sun=rx_link(scene,sid+'_Sun',bpy.data.lights.new(sid+'_Sun','SUN'))
    sun.data.energy,sun.data.angle=2.5,math.radians(12)
    sun.rotation_euler=(0.5,-0.5,-0.4)
    scene.frame_set(1)
    print(json.dumps({'built':sid,'players':22,'contacts':len(study.get('contacts',[])),
                      'frames':scene.frame_end,'objects':len(scene.objects)}))
    return scene

def rx_verify(study,fps):
    from mathutils.bvhtree import BVHTree
    scene=bpy.data.scenes['ReplayXI_Study_'+study['id']]
    bpy.context.window.scene=scene
    root_map={o.get('playerID'):o for o in scene.objects if o.get('playerID')}
    C=Matrix.Rotation(math.pi,4,'Z')@Matrix.Rotation(math.pi/2,4,'X')
    motion=json.loads(bpy.data.scenes['ReplayXI_Reference127_Assets']['RX127_Motion'])
    parents={j['name']:j['parentIndex'] for j in motion['joints']}
    samples={}
    for player in study['players']:
        for frame in player['keyframes']:
            samples.setdefault(frame['time'],[]).append((player['id'],frame))
    root_worst=0.0;heading_worst=0.0;root_checked=0
    for time,entries in samples.items():
        stamp=1+time*fps
        scene.frame_set(math.floor(stamp),subframe=stamp-math.floor(stamp))
        for player_id,frame in entries:
            root=root_map[player_id]
            target=Vector((-frame['position']['x'],frame['position']['z'],0))
            root_worst=max(root_worst,(root.location-target).length)
            facing=next(o for o in root.children if o.name.endswith('_Facing'))
            angle=facing.rotation_euler.z-math.pi-math.radians(frame['facingDegrees'])
            heading_worst=max(heading_worst,abs((angle+math.pi)%math.tau-math.pi))
            root_checked+=1
    ball=scene.objects[study['id']+'_BallRecording']
    ball_worst=0.0
    for frame in study['ball']['keyframes']:
        stamp=1+frame['time']*fps
        scene.frame_set(math.floor(stamp),subframe=stamp-math.floor(stamp))
        target=Vector((-frame['position']['x'],frame['position']['z'],frame['height']))
        ball_worst=max(ball_worst,(ball.location-target).length)
    worst=0.0;checked=0
    pose_samples={};rigs={};facings={}
    for payload in study.get('rigPoses',[]):
        root=root_map[payload['playerID']]
        rigs[payload['playerID']]=next(o for o in root.children_recursive if o.type=='ARMATURE')
        facings[payload['playerID']]=next(o for o in root.children if o.name.endswith('_Facing'))
        for frame in payload['frames']:
            pose_samples.setdefault(frame['time'],[]).append((payload,frame))
    # All-player exports share most timestamps. Evaluate Blender once per
    # instant, not once per player at that instant (22 repeated scene updates).
    for time,entries in pose_samples.items():
        stamp=1+time*fps
        scene.frame_set(math.floor(stamp),subframe=stamp-math.floor(stamp))
        bpy.context.view_layer.update()
        for payload,encoded_frame in entries:
            frame=rx_pose_frame(payload,encoded_frame)
            root=root_map[payload['playerID']]
            rig=rigs[payload['playerID']]
            facing=facings[payload['playerID']]
            native_heading=facing.rotation_euler.z-math.pi
            world=Matrix.Translation(root.location+Vector((0,0,payload['groundOffset'])))@C@Matrix.Rotation(native_heading,4,'Y')
            models=[]
            for index,name in enumerate(payload['jointNames']):
                local=rx_matrix(frame['translations'][index],frame['rotations'][index],frame['scales'][index])
                parent=parents[name]
                models.append(models[parent]@local if parent>=0 else local)
                actual=rig.matrix_world@rig.pose.bones[name.split('/')[-1]].matrix
                expected=world@models[index]
                worst=max(worst,max(abs(actual[row][col]-expected[row][col]) for row in range(4) for col in range(4)))
                checked+=1
    surfaces=[]
    for contact in study.get('contacts',[]):
        stamp=1+contact['time']*fps
        scene.frame_set(math.floor(stamp),subframe=stamp-math.floor(stamp))
        bpy.context.view_layer.update()
        graph=bpy.context.evaluated_depsgraph_get()
        position=contact['position'];centre=Vector((-position['x'],position['z'],position['y']))
        root=root_map[contact['playerID']]
        section='_Head' if contact['kind']=='header' else '_Body'
        meshes=[o for o in root.children_recursive if o.type=='MESH' and section in o.name]
        distances=[]
        for obj in meshes:
            evaluated=obj.evaluated_get(graph);mesh=evaluated.to_mesh()
            mesh.calc_loop_triangles()
            vertices=[evaluated.matrix_world@v.co for v in mesh.vertices]
            triangles=[tuple(t.vertices) for t in mesh.loop_triangles]
            tree=BVHTree.FromPolygons(vertices,triangles,all_triangles=True)
            nearest=tree.find_nearest(centre)
            if nearest and nearest[3] is not None:distances.append(nearest[3])
            evaluated.to_mesh_clear()
        surfaces.append({'playerID':contact['playerID'],'kind':contact['kind'],'time':contact['time'],
                         'sphereSurfaceClearanceMetres':min(distances)-0.11 if distances else None,
                         'note':'Whole head/body nearest triangle; save palm marker is a different contract'})
    report={'study':study['id'],'players':len(root_map),'nativeBoneMatricesChecked':checked,
            'nativePosePlayersChecked':len(rigs),'nativePoseInstantsEvaluated':len(pose_samples),
            'rootPathSamplesChecked':root_checked,'maximumRootPositionErrorMetres':root_worst,
            'maximumRootHeadingErrorRadians':heading_worst,'ballSamplesChecked':len(study['ball']['keyframes']),
            'maximumBallPositionErrorMetres':ball_worst,'maximumMatrixElementError':worst,
            'transformMappingPassed':len(root_map)==22 and max(worst,root_worst,heading_worst,ball_worst)<0.0001,
            'scope':'Transform mapping only. Contact mesh distances are diagnostics, not a passed contact/animation test.'}
    report['contactSurfaces']=surfaces
    if study.get('authoringRevision'):
        report['scenarioID']=study['scenarioID']
        report['authoringRevision']=study['authoringRevision']
    scene['verificationJSON']=json.dumps(report)
    print(json.dumps(report))
    return report
'''


def emit_steps(document, digest, output_dir, blend_output, fps=30, repository=REPO,
               shared_assets_loaded=False, exclude_studies=(), scene_suffix=None):
    output_dir, blend_output = Path(output_dir).resolve(), Path(blend_output).resolve()
    if output_dir.exists() or blend_output.exists() or blend_output.suffix != ".blend":
        raise ContractError("choose a new steps folder and a new .blend filename")
    if blend_output.is_relative_to(repository.resolve()) and not blend_output.is_relative_to((repository / ".codex-derived").resolve()):
        raise ContractError("large artifacts belong outside source control or under .codex-derived")
    if fps not in (24, 30, 60):
        raise ContractError("fps must be 24,30,60")
    document = authoring_document(document, scene_suffix, exclude_studies)
    for study in document["studies"]:
        posed_ids = {rig['playerID'] for rig in study.get('rigPoses', [])}
        for player in study["players"]:
            player['_headingAngles'] = heading_angles(player['keyframes'])
            if player['id'] not in posed_ids:
                player['_gaitKeys'] = gait_keys(player['keyframes'], fps)
    motion_path = repository / "ReplayXI/Resources/Players/ReplayXIRocketboxMotion.json"
    motion = json.loads(motion_path.read_text())
    expected_names = [joint['name'] for joint in motion['joints']]
    for study in document['studies']:
        for rig in study.get('rigPoses', []):
            if rig['jointNames'] != expected_names:
                raise ContractError("exported joint order differs from the audited source rig")
    licence = (repository / "ReplayXI/Resources/Players/LICENSE-ROCKETBOX-MIT.txt").read_text()
    output_dir.mkdir(parents=True)
    blend_output.parent.mkdir(parents=True, exist_ok=True)
    steps = []

    def step(label, code):
        name = f"{len(steps):03d}-{label}.py"
        (output_dir / name).write_text(code + "\n")
        steps.append(name)

    if scene_suffix is not None:
        # Run before any asset import, embedded data write or scene creation.
        # rx_build repeats the namespace check after staging data, so stale
        # object/data names cannot silently acquire Blender's .001 suffix.
        step('check-revision-namespace', RUNTIME +
             f"\nrx_assert_revision_namespace_available({[study['id'] for study in document['studies']]!r})\n"
             "print('Revision namespaces available; prior studies preserved')")

    base = str(repository.resolve())
    prepare_assets = "import bpy,json\n" + (
         "previous=bpy.context.scene\n"
         "assets=bpy.data.scenes.get('ReplayXI_Reference127_Assets') or bpy.data.scenes.new('ReplayXI_Reference127_Assets')\n"
         "bpy.context.window.scene=assets\n"
         f"paths={json.dumps({'skin':base+'/ReplayXI/Resources/Players/ReplayXIRocketboxAthlete.usdz','pitch':base+'/ReplayXI/Resources/Strategy/ReplayXIStrategyPitch.usdz','ball':base+'/ReplayXI/Resources/Strategy/ReplayXIStrategyBall.usdz'})}\n"
         "for kind,path in paths.items():\n"
         " existing=[o for o in assets.objects if o.get('reference127Template')==kind]\n"
         " if kind=='skin' and not existing:\n"
         "  existing=[o for o in assets.objects if o.get('reference127Template') is True]\n"
         "  for obj in existing:obj['reference127Template']=kind\n"
         " if not existing:\n"
         "  before=set(bpy.data.objects)\n"
         "  bpy.ops.wm.usd_import(filepath=path,set_frame_range=False,import_cameras=False,import_lights=False,import_textures_mode='IMPORT_PACK')\n"
         "  for obj in bpy.data.objects:\n"
         "   if obj not in before:obj['reference127Template']=kind\n"
         f"base={base!r}\n"
         "for kit in ('Home','Away','Keeper'):\n"
         " image=bpy.data.images.load(base+'/ReplayXI/Resources/Players/ReplayXIRocketbox'+kit+'Skin0.png',check_existing=True)\n"
         " image.name='RX127_'+kit\n"
         " image.pack()\n"
         "bpy.context.window.scene=previous\n"
         "print('Reference assets imported; previous scene restored')")
    if not shared_assets_loaded:
        step('prepare-assets', prepare_assets)
    else:
        step('check-shared-assets', "import bpy,json\n"
             "assets=bpy.data.scenes['ReplayXI_Reference127_Assets']\n"
             "if any(not any(o.get('reference127Template')==kind for o in assets.objects) for kind in ('skin','pitch','ball')):raise ValueError('Shared assets missing')\n"
             "if 'RX127_Motion' not in assets or 'LICENSE-ROCKETBOX-MIT.txt' not in assets:raise ValueError('Source data missing')\n"
             "if any(name not in bpy.data.actions for name in ('RX127_idle','RX127_run')):raise ValueError('Source actions missing')\n"
             "print('Shared assets available; existing scenes preserved')")
    payloads = [] if shared_assets_loaded else [('RX127_Motion', json.dumps(motion, separators=(',', ':'))),
                                               ('LICENSE-ROCKETBOX-MIT.txt', licence)]
    payloads += [('RX127_Study_' + study['id'], json.dumps(study, separators=(',', ':')))
                 for study in document['studies']]
    payload_bytes = sum(len(content.encode('utf-8')) for _, content in payloads)
    for name, content in payloads:
        for start in range(0, len(content), 90000):
            chunk = content[start:start + 90000]
            init = f"if {name!r} in data:raise ValueError('Reference data already exists: {name}')\n" if start == 0 else ""
            step("data", "import bpy\ndata=bpy.data.scenes['ReplayXI_Reference127_Assets']\n" + init
                 + f"data[{name!r}]=data.get({name!r},'')+{chunk!r}")
    if not shared_assets_loaded:
        step("source-actions", RUNTIME + "\nrx_prepare_actions()\nprint('Shared illustrative source actions ready')")
    for study in document['studies']:
        lookup = f"\nstudy=json.loads(bpy.data.scenes['ReplayXI_Reference127_Assets'][{'RX127_Study_'+study['id']!r}])\n"
        step(study['id'], RUNTIME + lookup + f"rx_build(study,{fps},{digest!r})")
        step(study['id']+"-verify", RUNTIME + lookup + f"report=rx_verify(study,{fps})\nif not report['transformMappingPassed']:raise ValueError('Native rig transform check failed')")
    step("save-copy", "import bpy,json\n"
         f"output={str(blend_output)!r}\n"
         "if bpy.data.filepath==output:raise ValueError('Never replace the current document')\n"
         f"expected={json.dumps(['ReplayXI_Study_'+s['id'] for s in document['studies']])}\n"
         "if any(name not in bpy.data.scenes for name in expected):raise ValueError('Study missing; refusing incomplete save')\n"
         "bpy.context.window.scene=bpy.data.scenes[expected[0]]\n"
         "bpy.ops.wm.save_as_mainfile(filepath=output,copy=True,compress=True,check_existing=True)\n"
         "print(json.dumps({'savedCopy':output,'studies':expected,'originalFileStill':bpy.data.filepath}))")
    report = {"schemaVersion": 1, "manifestSHA256": digest, "steps": steps,
              "stepCount": len(steps), "metadataBytes": payload_bytes,
              "nativePoseFrames": sum(len(rig['frames']) for study in document['studies']
                                      for rig in study.get('rigPoses', [])),
              "blendOutput": str(blend_output), "studies": [s['id'] for s in document['studies']],
              "safety": "MCP safe mode stays enabled. No .blend loading, exec/eval, drivers, handlers or timers.",
              "limitations": "Authored trajectories and native rig samples are not captured match motion. Any player without native samples uses an illustrative gait. Off-camera positions remain inferred."}
    if scene_suffix is not None:
        report['sceneSuffix'] = scene_suffix
        report['scenarioIDs'] = [study['scenarioID'] for study in document['studies']]
    (output_dir / "steps.json").write_text(json.dumps(report, indent=2) + "\n")
    return report


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--manifest', type=Path, required=True)
    parser.add_argument('--steps-output', type=Path)
    parser.add_argument('--blend-output', type=Path)
    parser.add_argument('--fps', type=int, choices=(24,30,60), default=30)
    parser.add_argument('--validate-only', action='store_true')
    parser.add_argument('--shared-assets-loaded', action='store_true',
                        help='Verify and reuse assets already staged in this Blender session')
    parser.add_argument('--exclude-study', action='append', default=[])
    parser.add_argument('--scene-suffix', help='Optional authoring-only revision, e.g. motion130; app scenario IDs stay unchanged')
    args = parser.parse_args()
    document, digest = read_document(args.manifest)
    if args.validate_only:
        selected = authoring_document(document, args.scene_suffix, args.exclude_study)
        report = {'valid':True,'studies':len(selected['studies']),'sha256':digest}
        if args.scene_suffix is not None:
            report.update(sceneSuffix=args.scene_suffix,
                          scenarioIDs=[study['scenarioID'] for study in selected['studies']],
                          authoringStudyIDs=[study['id'] for study in selected['studies']])
        print(json.dumps(report))
        return
    if not args.steps_output or not args.blend_output:
        parser.error('--steps-output and --blend-output required')
    print(json.dumps(emit_steps(document,digest,args.steps_output,args.blend_output,args.fps,
                               shared_assets_loaded=args.shared_assets_loaded,exclude_studies=args.exclude_study,
                               scene_suffix=args.scene_suffix)))


if __name__ == '__main__':
    main()
