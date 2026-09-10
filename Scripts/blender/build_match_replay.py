#!/usr/bin/env python3
"""Assemble an editable match scene from explicit, evidence-labelled tracks.

  blender --background --factory-startup --python Scripts/blender/build_match_replay.py -- \
    --manifest /path/replay-tracks.json --output /path/MatchReplay.blend \
    --player-library /path/ReplayXIFootballPlayers.blend

No video reconstruction or player tracking is performed here. Empty inputs build
an explicitly pending pitch, not a fabricated match. The script adds a NEW scene
and saves only that scene's dependencies; it never resets an existing Blender
document or overwrites an output. Evaluation/export temporarily selects the new
scene inside an isolated background process, then restores the startup scene.
It refuses live-GUI execution.
Run with ordinary Python and --validate-only for a Blender-free contract check.
"""
from __future__ import annotations

import argparse
from contextlib import contextmanager
import hashlib
import json
import math
from pathlib import Path
import re
import sys


COORDINATE_SYSTEM = "pitch-metres-x-width-z-length"
MAX_ANNOTATIONS = 128
MAX_KEYFRAMES = 7_201
MAX_ANIMATION_SCALARS = 2_500_000
ORIGINS = {"manual", "inferred", "measured"}
VISIBILITY = {"visible", "occluded", "off-camera", "unknown"}
PITCH_WIDTH, PITCH_LENGTH = 68.0, 105.0


class ContractError(ValueError):
    pass


def number(value, label, low=None, high=None):
    if isinstance(value, bool) or not isinstance(value, (int, float)) or not math.isfinite(value):
        raise ContractError(f"{label} must be finite")
    if low is not None and value < low or high is not None and value > high:
        raise ContractError(f"{label} is outside [{low}, {high}]")
    return float(value)


def identity(value, label):
    if not isinstance(value, str) or not re.fullmatch(r"[A-Za-z0-9_-]{1,80}", value):
        raise ContractError(f"{label} must be a stable identifier")
    return value


def point(value, label, width=34.0, length=52.5):
    if not isinstance(value, dict):
        raise ContractError(f"{label} needs x/z pitch coordinates")
    return (number(value.get("x"), f"{label}.x", -width, width),
            number(value.get("z"), f"{label}.z", -length, length))


def evidence(value, label):
    if not isinstance(value, dict) or value.get("origin") not in ORIGINS:
        raise ContractError(f"{label} needs explicit manual/inferred/measured evidence")
    number(value.get("confidence"), f"{label}.confidence", 0, 1)
    if value.get("sourceVisibility") not in VISIBILITY:
        raise ContractError(f"{label}.sourceVisibility is missing or invalid")
    if value.get("sourceFrameID") is not None:
        identity(value["sourceFrameID"], f"{label}.sourceFrameID")


def validate_keyframes(frames, duration, label, ball=False):
    if not isinstance(frames, list) or len(frames) > MAX_KEYFRAMES:
        raise ContractError(f"{label} must be a bounded list")
    previous = -1.0
    for index, frame in enumerate(frames):
        if not isinstance(frame, dict):
            raise ContractError(f"{label}[{index}] must be an object")
        prefix = f"{label}[{index}]"
        time = number(frame.get("time"), f"{prefix}.time", 0, duration)
        if time <= previous:
            raise ContractError(f"{label} timestamps must strictly increase")
        previous = time
        point(frame.get("position"), f"{prefix}.position")
        number(frame.get("height", 0.11), f"{prefix}.height", 0, 30) if ball else number(
            frame.get("facingDegrees"), f"{prefix}.facingDegrees", -3_600, 3_600
        )
        evidence(frame.get("evidence"), f"{prefix}.evidence")


def validate_manifest(document):
    if not isinstance(document, dict) or document.get("schemaVersion") != 1:
        raise ContractError("schemaVersion must be 1")
    identity(document.get("id"), "id")
    duration = number(document.get("duration"), "duration", 0.001, 60.001)
    if document.get("coordinateSystem") != COORDINATE_SYSTEM:
        raise ContractError(f"coordinateSystem must be {COORDINATE_SYSTEM}")
    source = document.get("source", {})
    if not isinstance(source, dict) or source.get("status") not in {"reference-pending", "reference-available"}:
        raise ContractError("source.status must explicitly describe reference availability")
    if source.get("status") == "reference-available" and not source.get("videoPath"):
        raise ContractError("reference-available requires videoPath")
    track_evidence = document.get("trackEvidence", {})
    if not isinstance(track_evidence, dict) or track_evidence.get("origin") not in ORIGINS | {"untracked"}:
        raise ContractError("trackEvidence.origin must disclose how tracks were obtained")
    if not isinstance(track_evidence.get("measured3D"), bool):
        raise ContractError("trackEvidence.measured3D must be an explicit Boolean")
    players = document.get("players")
    if not isinstance(players, list) or len(players) not in {0, 22}:
        raise ContractError("players must be an empty pending roster or all 22 identities")
    ids, jerseys, counts = set(), set(), {"home": 0, "away": 0}
    for player in players:
        if not isinstance(player, dict):
            raise ContractError("each player must be an object")
        player_id = identity(player.get("id"), "player.id")
        team = player.get("team")
        shirt = player.get("shirtNumber")
        if player_id in ids or team not in counts:
            raise ContractError("player IDs must be unique and teams home/away")
        if isinstance(shirt, bool) or not isinstance(shirt, int) or not 1 <= shirt <= 99:
            raise ContractError("shirtNumber must be 1–99")
        if (team, shirt) in jerseys:
            raise ContractError("shirt numbers must be unique within each team")
        if not isinstance(player.get("displayName"), str) or not 1 <= len(player["displayName"]) <= 96:
            raise ContractError("each player needs a bounded displayName")
        ids.add(player_id)
        jerseys.add((team, shirt))
        counts[team] += 1
        validate_keyframes(player.get("keyframes"), duration, player_id)
    if players and counts != {"home": 11, "away": 11}:
        raise ContractError("a match roster needs 11 players per team")
    ball = document.get("ball")
    if not isinstance(ball, dict):
        raise ContractError("ball must contain explicit keyframes")
    validate_keyframes(ball.get("keyframes"), duration, "ball", ball=True)
    has_tracks = any(player["keyframes"] for player in players) or bool(ball["keyframes"])
    if has_tracks and (source["status"] != "reference-available" or track_evidence["origin"] == "untracked"):
        raise ContractError("populated match tracks require an available reference and declared evidence")
    all_frames = [frame for player in players for frame in player["keyframes"]] + ball["keyframes"]
    if track_evidence["measured3D"] and (track_evidence["origin"] != "measured" or not all_frames
            or any(frame["evidence"]["origin"] != "measured" for frame in all_frames)):
        raise ContractError("measured3D requires consistently measured track evidence")
    marks = document.get("annotations", [])
    if not isinstance(marks, list) or len(marks) > MAX_ANNOTATIONS:
        raise ContractError("annotations must be a list of at most 128 marks")
    mark_ids = set()
    player_map = {player["id"]: player for player in players}
    for mark in marks:
        if not isinstance(mark, dict):
            raise ContractError("each annotation must be an object")
        mark_id = identity(mark.get("id"), "annotation.id")
        if mark_id in mark_ids:
            raise ContractError("annotation IDs must be unique")
        mark_ids.add(mark_id)
        kind = mark.get("kind")
        if kind not in {"run", "pass", "space", "danger", "playerLabel"}:
            raise ContractError("unsupported annotation kind")
        reveal = number(mark.get("revealTime", 0), "revealTime", 0, duration)
        hide = mark.get("hideTime")
        if hide is not None and number(hide, "hideTime", reveal, duration) <= reveal:
            raise ContractError("hideTime must follow revealTime")
        if not isinstance(mark.get("label"), str) or not 1 <= len(mark["label"]) <= 96:
            raise ContractError("annotations need a bounded label")
        for endpoint in ("start", "end"):
            point(mark.get(endpoint), f"annotation.{endpoint}")
            number(mark.get(endpoint + "Elevation") or 0, "annotation elevation", 0, 4)
            anchor = mark.get(endpoint + "TrackAnchor")
            if anchor is not None:
                if not isinstance(anchor, dict) or anchor.get("playerID") not in ids:
                    raise ContractError("annotation track anchor must identify a roster player")
                if not player_map[anchor["playerID"]]["keyframes"]:
                    raise ContractError("cannot attach annotations to untracked player positions")
                point(anchor.get("offset"), "anchor offset", width=68, length=105)
        if kind == "playerLabel" and (mark.get("playerID") not in ids or not player_map[mark["playerID"]]["keyframes"]):
            raise ContractError("playerLabel must identify a tracked player")
        if kind == "space" and abs((mark.get("startElevation") or 0) - (mark.get("endElevation") or 0)) > 0.001:
            raise ContractError("space annotation endpoints must share one elevation")
    return document


def read_manifest(path):
    path = Path(path).resolve()
    if path.stat().st_size > 32 * 1_024 * 1_024:
        raise ContractError("track manifest exceeds 32 MB")
    data = path.read_bytes()
    document = validate_manifest(json.loads(data))
    source = document["source"]
    if source["status"] == "reference-available":
        video = Path(source["videoPath"])
        if not video.is_absolute() or not video.is_file():
            raise ContractError("videoPath must identify an existing absolute reference file")
    reference = source.get("referenceManifestPath")
    if reference:
        reference = Path(reference)
        if not reference.is_absolute():
            reference = path.parent / reference
        expected = source.get("referenceManifestSHA256")
        if not isinstance(expected, str) or not re.fullmatch(r"[a-f0-9]{64}", expected):
            raise ContractError("referenceManifestSHA256 is required")
        if hashlib.sha256(reference.read_bytes()).hexdigest() != expected:
            raise ContractError("reference manifest hash mismatch")
        reference_document = json.loads(reference.read_bytes())
        reference_source = reference_document.get("source", {})
        if Path(reference_source.get("path", "")).resolve() != Path(source["videoPath"]).resolve():
            raise ContractError("videoPath differs from the bound reference source")
        digest = hashlib.sha256()
        with Path(source["videoPath"]).open("rb") as stream:
            for chunk in iter(lambda: stream.read(1_048_576), b""):
                digest.update(chunk)
        if digest.hexdigest() != reference_source.get("sha256"):
            raise ContractError("reference video hash mismatch")
        source_duration = reference_document.get("timeline", {}).get("durationSeconds")
        if number(source_duration, "reference duration", 0.001) + 0.001 < document["duration"]:
            raise ContractError("track duration exceeds the prepared reference interval")
        known_frames = {frame["id"] for frame in reference_document.get("frames", [])}
        for track in document["players"] + [document["ball"]]:
            for frame in track["keyframes"]:
                frame_id = frame["evidence"].get("sourceFrameID")
                if frame_id is not None and frame_id not in known_frames:
                    raise ContractError("track evidence names an unknown sourceFrameID")
    return document, hashlib.sha256(data).hexdigest()


def frame_at(time, fps):
    return 1 + time * fps


def sample_track(frames, time, ball=False):
    """Piecewise linear interpolation: no invented accelerations or overshoot."""
    if not frames:
        return None
    lower, upper = 0, len(frames)
    while lower < upper:
        middle = (lower + upper) // 2
        if frames[middle]["time"] <= time:
            lower = middle + 1
        else:
            upper = middle
    index = lower
    if index == 0:
        left = right = frames[0]
    elif index == len(frames):
        left = right = frames[-1]
    else:
        left, right = frames[index - 1], frames[index]
    fraction = 0 if left is right else (time - left["time"]) / (right["time"] - left["time"])
    x = left["position"]["x"] + (right["position"]["x"] - left["position"]["x"]) * fraction
    y = left["position"]["z"] + (right["position"]["z"] - left["position"]["z"]) * fraction
    if ball:
        z = left.get("height", 0.11) + (right.get("height", 0.11) - left.get("height", 0.11)) * fraction
        return (x, y, z)
    facing = left["facingDegrees"]
    delta = (right["facingDegrees"] - facing + 180) % 360 - 180
    return (x, y, facing + delta * fraction)


def annotation_endpoint(mark, endpoint, time, players):
    anchor = mark.get(endpoint + "TrackAnchor")
    if anchor:
        pose = sample_track(players[anchor["playerID"]]["keyframes"], time)
        x, y = pose[0] + anchor["offset"]["x"], pose[1] + anchor["offset"]["z"]
    else:
        x, y = point(mark[endpoint], endpoint)
    # Resolved geometry is bounded just like the app's pitch-relative marks.
    return (min(max(x, -34), 34), min(max(y, -52.5), 52.5),
            (mark.get(endpoint + "Elevation") or 0) + 0.055)


def annotation_times(mark, players, duration):
    times = {0.0, duration, mark.get("revealTime", 0)}
    if mark.get("hideTime") is not None:
        times.add(mark["hideTime"])
    for endpoint in ("start", "end"):
        anchor = mark.get(endpoint + "TrackAnchor")
        if anchor:
            times.update(frame["time"] for frame in players[anchor["playerID"]]["keyframes"])
    if mark["kind"] == "playerLabel":
        times.update(frame["time"] for frame in players[mark["playerID"]]["keyframes"])
    return sorted(times)


def tracked_frame_window(frames, fps):
    """Do not present a held pose outside the interval actually supplied."""
    if not frames:
        return None
    return frame_at(frames[0]["time"], fps), math.floor(frame_at(frames[-1]["time"], fps)) + 1


def annotation_frame_window(mark, players, fps, duration):
    start = frame_at(mark.get("revealTime", 0), fps)
    end = frame_at(mark["hideTime"], fps) if mark.get("hideTime") is not None else math.ceil(duration * fps) + 1
    ids = {mark[endpoint + "TrackAnchor"]["playerID"] for endpoint in ("start", "end")
           if mark.get(endpoint + "TrackAnchor")}
    if mark["kind"] == "playerLabel":
        ids.add(mark["playerID"])
    for player_id in ids:
        window = tracked_frame_window(players[player_id]["keyframes"], fps)
        if window is None:
            return None
        start, end = max(start, window[0]), min(end, window[1])
    return (start, end) if start < end else None


def set_linear(data):
    animation = getattr(data, "animation_data", None)
    action = animation.action if animation else None
    if not action:
        return
    # Blender 4.4+ actions are slotted. Keep compatibility with legacy actions.
    if hasattr(action, "fcurves"):
        curves = action.fcurves
    else:
        slot = animation.action_slot
        curves = [curve for layer in action.layers for strip in layer.strips
                  for curve in strip.channelbag(slot).fcurves] if slot else []
    for curve in curves:
        for key in curve.keyframe_points:
            key.interpolation = "CONSTANT" if "hide_" in curve.data_path else "LINEAR"


@contextmanager
def scene_context(bpy, scene):
    # Blender's glTF exporter resolves its dependency graph through window.scene
    # even under temp_override. Only run this in an isolated background process,
    # and restore the startup scene afterwards. The live GUI is never touched.
    if not bpy.app.background:
        raise ContractError("Match assembly runs only in isolated background Blender")
    window = bpy.context.window
    previous = window.scene if window else None
    try:
        if window:
            window.scene = scene
        with bpy.context.temp_override(scene=scene, view_layer=scene.view_layers[0]):
            scene.view_layers[0].update()
            yield
    finally:
        if window and previous:
            window.scene = previous


def evaluate_scene_frame(bpy, scene, frame):
    with scene_context(bpy, scene):
        integer_frame = math.floor(frame)
        scene.frame_set(integer_frame, subframe=frame - integer_frame)
        bpy.context.evaluated_depsgraph_get().update()


class SceneBuilder:
    def __init__(self, bpy, document, fps, player_library=None):
        self.bpy, self.doc, self.fps = bpy, document, fps
        self.scene = bpy.data.scenes.new("ReplayXI_Match_" + document["id"])
        self.scene.unit_settings.system = "METRIC"
        self.scene.unit_settings.scale_length = 1
        self.scene.render.fps = fps
        self.scene.frame_start = 1
        self.scene.frame_end = max(1, math.ceil(document["duration"] * fps))
        self.scene.render.resolution_x, self.scene.render.resolution_y = 1920, 1080
        self.scene.render.resolution_percentage = 100
        engines = self.scene.render.bl_rna.properties["engine"].enum_items.keys()
        self.scene.render.engine = "BLENDER_EEVEE" if "BLENDER_EEVEE" in engines else "BLENDER_EEVEE_NEXT"
        self.materials = {}
        self.players = {player["id"]: player for player in document["players"]}
        self.roots = {}
        self.library = player_library
        self.actions = {}
        self.related_texts = []
        self.collections = {}
        for name in ("Pitch", "Players", "Cameras", "Annotations", "Reference"):
            collection = bpy.data.collections.new("ReplayXI_" + name)
            self.scene.collection.children.link(collection)
            self.collections[name] = collection

    def material(self, name, color, emission=0):
        if name in self.materials:
            return self.materials[name]
        material = self.bpy.data.materials.new("ReplayXI_" + name)
        material.diffuse_color = (*color, 1)
        material.use_nodes = True
        shader = material.node_tree.nodes.get("Principled BSDF")
        shader.inputs["Base Color"].default_value = (*color, 1)
        shader.inputs["Roughness"].default_value = 0.72
        if emission:
            shader.inputs["Emission Color"].default_value = (*color, 1)
            shader.inputs["Emission Strength"].default_value = emission
        self.materials[name] = material
        return material

    def empty(self, name, collection, parent=None):
        obj = self.bpy.data.objects.new(name, None)
        self.collections[collection].objects.link(obj)
        obj.empty_display_type = "PLAIN_AXES"
        obj.empty_display_size = 0.25
        obj.parent = parent
        return obj

    def mesh(self, name, vertices, faces, material, collection="Pitch"):
        data = self.bpy.data.meshes.new(name)
        data.from_pydata(vertices, [], faces)
        data.update()
        obj = self.bpy.data.objects.new(name, data)
        self.collections[collection].objects.link(obj)
        data.materials.append(material)
        return obj

    def line(self, name, points, material, radius=0.035, collection="Pitch", closed=False):
        curve = self.bpy.data.curves.new(name, "CURVE")
        curve.dimensions = "3D"
        curve.resolution_u = 1
        curve.bevel_depth = radius
        curve.bevel_resolution = 2
        spline = curve.splines.new("POLY")
        spline.points.add(len(points) - 1)
        for vertex, value in zip(spline.points, points):
            vertex.co = (*value, 1)
        spline.use_cyclic_u = closed
        obj = self.bpy.data.objects.new(name, curve)
        self.collections[collection].objects.link(obj)
        curve.materials.append(material)
        return obj

    def text(self, name, body, location, size=0.35, collection="Reference", parent=None):
        data = self.bpy.data.curves.new(name, "FONT")
        data.body, data.size = body, size
        data.align_x = "CENTER"
        data.extrude = 0.003
        data.materials.append(self.material("White", (0.94, 0.96, 0.97)))
        obj = self.bpy.data.objects.new(name, data)
        self.collections[collection].objects.link(obj)
        obj.parent, obj.location = parent, location
        return obj

    def pitch(self):
        dark = self.material("Turf", (0.027, 0.17, 0.062))
        light = self.material("TurfStripe", (0.038, 0.21, 0.078))
        for index in range(14):
            y = -52.5 + index * 7.5
            self.mesh(f"PitchStripe_{index:02}", [(-34, y, 0), (34, y, 0), (34, y + 7.5, 0), (-34, y + 7.5, 0)],
                      [(0, 1, 2, 3)], dark if index % 2 else light)
        white = self.material("PitchLines", (0.8, 0.87, 0.81))
        self.line("Touchlines_105x68m", [(-34, -52.5, 0.025), (34, -52.5, 0.025),
                  (34, 52.5, 0.025), (-34, 52.5, 0.025)], white, 0.045, closed=True)
        self.line("Halfway", [(-34, 0, 0.025), (34, 0, 0.025)], white, 0.045)
        self.line("CentreCircle_9.15m", [(math.cos(i * math.tau / 96) * 9.15,
                  math.sin(i * math.tau / 96) * 9.15, 0.025) for i in range(96)], white, 0.045, closed=True)
        for side in (-1, 1):
            for width, depth, name in [(40.32, 16.5, "PenaltyArea"), (18.32, 5.5, "GoalArea")]:
                self.line(f"{name}_{side}", [(-width / 2, side * 52.5, 0.025),
                    (-width / 2, side * (52.5 - depth), 0.025),
                    (width / 2, side * (52.5 - depth), 0.025),
                    (width / 2, side * 52.5, 0.025)], white, 0.045)
            self.line(f"Goal_7.32x2.44m_{side}", [(-3.66, side * 52.5, 0),
                (-3.66, side * 52.5, 2.44), (3.66, side * 52.5, 2.44),
                (3.66, side * 52.5, 0)], white, 0.06)
            self.line(f"PenaltySpot_{side}", [(0, side * 41.5, 0.03), (0.02, side * 41.5, 0.03)], white, 0.1)

    def import_templates(self):
        if not self.doc["players"]:
            return {}
        if not self.library or not Path(self.library).is_file():
            raise ContractError("22-player assembly requires the licensed .blend player library")
        wanted = ("ReplayXI_Home", "ReplayXI_Away", "ReplayXI_Keeper")
        with self.bpy.data.libraries.load(str(self.library), link=False) as (source, target):
            missing = set(wanted) - set(source.collections)
            if missing:
                raise ContractError(f"player library is missing collections: {sorted(missing)}")
            target.collections = list(wanted)
            action_names = ("ReplayXI_Idle", "ReplayXI_Run_InPlace")
            if set(action_names) - set(source.actions):
                raise ContractError("player library needs Idle and Run_InPlace actions")
            target.actions = list(action_names)
            if "LICENSE-ROCKETBOX-MIT.txt" not in source.texts:
                raise ContractError("player library must include its Microsoft MIT license notice")
            target.texts = ["LICENSE-ROCKETBOX-MIT.txt"]
        self.actions = dict(zip(action_names, target.actions))
        self.related_texts = list(target.texts)
        return dict(zip(wanted, target.collections))

    def animate_location(self, obj, frames, ball=False):
        for frame in frames:
            obj.location = (frame["position"]["x"], frame["position"]["z"], frame.get("height", 0.11) if ball else 0)
            obj.keyframe_insert(data_path="location", frame=frame_at(frame["time"], self.fps))
        set_linear(obj)

    def clone_player(self, player, template, root):
        objects = list(template.all_objects)
        copies = {}
        for original in objects:
            clone = original.copy()
            if original.type == "ARMATURE":
                clone.data = original.data.copy()
            clone.name = f"{player['id']}_{original.name}"
            self.collections["Players"].objects.link(clone)
            copies[original] = clone
        for original, clone in copies.items():
            clone.parent = copies.get(original.parent, root)
            clone.matrix_parent_inverse = original.matrix_parent_inverse.copy()
            clone.matrix_basis = original.matrix_basis.copy()
            for modifier in clone.modifiers:
                if modifier.type == "ARMATURE" and modifier.object in copies:
                    modifier.object = copies[modifier.object]
            for constraint in clone.constraints:
                if hasattr(constraint, "target") and constraint.target in copies:
                    constraint.target = copies[constraint.target]
            if clone.type == "FONT":
                clone.data = original.data.copy()
                if "number" in original.name.lower() or "jersey" in original.name.lower():
                    clone.data.body = str(player["shirtNumber"])
            if clone.type == "ARMATURE":
                self.apply_run_cycles(clone, player)
        return copies

    def apply_run_cycles(self, armature, player):
        """Animation is demonstrative rig motion, never claimed as tracked limbs."""
        action = self.actions.get("ReplayXI_Run_InPlace")
        idle = self.actions.get("ReplayXI_Idle")
        armature.animation_data_clear()
        if not action or len(player["keyframes"]) < 2:
            if idle:
                armature.animation_data_create().action = idle
            armature["limbAnimationStatus"] = "idle-or-library-pose; limb motion not measured"
            return
        armature.animation_data_create()
        track = armature.animation_data.nla_tracks.new()
        track.name = "Demonstration gait from track speed"
        distance_before = 0.0
        for index, (left, right) in enumerate(zip(player["keyframes"], player["keyframes"][1:])):
            delta = right["time"] - left["time"]
            speed = math.hypot(right["position"]["x"] - left["position"]["x"],
                               right["position"]["z"] - left["position"]["z"]) / delta
            selected = action if speed >= 0.65 else idle
            if not selected:
                continue
            # NLA creation accepts integer start frames. Round UP so a .5-frame
            # boundary cannot be inserted inside the preceding strip first.
            strip = track.strips.new(f"Segment_{index:04}", math.ceil(frame_at(left["time"], self.fps)), selected)
            strip.action_frame_start, strip.action_frame_end = selected.frame_range
            strip.use_animated_time = True
            strip.extrapolation = "NOTHING"
            # Set scene bounds LAST: changing the source action range otherwise
            # expands a fractional strip back across the next telemetry sample.
            strip.frame_start = frame_at(left["time"], self.fps)
            strip.frame_end = frame_at(right["time"], self.fps)
            cycle = max(float(selected.frame_range[1] - selected.frame_range[0]), 1)
            for frame in range(math.ceil(strip.frame_start), math.floor(strip.frame_end) + 1):
                seconds = (frame - strip.frame_start) / self.fps
                phase = (distance_before + seconds * speed) / 2.4 if selected is action else (left["time"] + seconds) * 0.5
                strip.strip_time = selected.frame_range[0] + (phase % 1) * cycle
                strip.keyframe_insert("strip_time", frame=frame)
            for curve in strip.fcurves:
                for keyframe in curve.keyframe_points:
                    keyframe.interpolation = "LINEAR"
            distance_before += speed * delta
        armature["limbAnimationStatus"] = "procedural gait timing; limb motion not measured"

    def cameras_and_players(self):
        templates = self.import_templates()
        for player in self.doc["players"]:
            root = self.empty("Track_" + player["id"], "Players")
            self.roots[player["id"]] = root
            root["playerID"], root["shirtNumber"], root["team"] = player["id"], player["shirtNumber"], player["team"]
            root["trackEvidenceJSON"] = json.dumps([f["evidence"] for f in player["keyframes"]])
            body = self.empty("BodyFacing_" + player["id"], "Players", root)
            key = "ReplayXI_Keeper" if player.get("isGoalkeeper", False) else (
                "ReplayXI_Home" if player["team"] == "home" else "ReplayXI_Away")
            copies = self.clone_player(player, templates[key], body)
            if not player["keyframes"]:
                for obj in [root, body] + list(copies.values()):
                    obj.hide_render = True
                    obj.hide_viewport = True
                root["trackingStatus"] = "untracked; no position inferred"
                continue
            self.animate_location(root, player["keyframes"])
            previous = None
            for frame in player["keyframes"]:
                angle = math.pi - math.radians(frame["facingDegrees"])
                if previous is not None:
                    angle = previous + (angle - previous + math.pi) % math.tau - math.pi
                previous = angle
                body.rotation_euler.z = angle
                body.keyframe_insert("rotation_euler", index=2, frame=frame_at(frame["time"], self.fps))
            set_linear(body)
            label = self.text("Identity_" + player["id"], f"{player['team'].upper()} {player['shirtNumber']}",
                              (0, 0, 2.1), size=0.28, collection="Players", parent=root)
            for item in list(copies.values()) + [label]:
                self.track_visibility(item, player["keyframes"])
            camera = self.camera("POV_" + player["id"], (0, 0, 1.68), root)
            camera.rotation_euler = (math.pi / 2, 0, -math.radians(player["keyframes"][0]["facingDegrees"]))
            camera["freeLook"] = True
            camera["orientationPolicy"] = "translation follows player; camera rotation has no keyframes"
            camera.data.lens = 22
        tactical = self.camera("Tactical", (0, -135, 125))
        from mathutils import Vector
        tactical.rotation_euler = (Vector((0, 0, 0)) - tactical.location).to_track_quat("-Z", "Y").to_euler()
        tactical.data.lens = 30
        self.scene.camera = tactical

    def camera(self, name, position, parent=None):
        data = self.bpy.data.cameras.new(name)
        data.clip_start = 0.22 if parent else 0.1
        data.clip_end = 500
        obj = self.bpy.data.objects.new(name, data)
        self.collections["Cameras"].objects.link(obj)
        obj.location, obj.parent = position, parent
        return obj

    def ball(self):
        material = self.material("Ball", (0.95, 0.96, 0.95))
        vertices, faces = [], []
        rows, columns = 12, 24
        for row in range(rows + 1):
            phi = math.pi * row / rows
            for column in range(columns):
                theta = math.tau * column / columns
                vertices.append((0.11 * math.sin(phi) * math.cos(theta),
                                 0.11 * math.sin(phi) * math.sin(theta), 0.11 * math.cos(phi)))
        for row in range(rows):
            for column in range(columns):
                a, b = row * columns + column, row * columns + (column + 1) % columns
                faces.append((a, b, b + columns, a + columns))
        obj = self.mesh("Ball_0.22m", vertices, faces, material, "Players")
        for polygon in obj.data.polygons:
            polygon.use_smooth = True
        frames = self.doc["ball"]["keyframes"]
        if frames:
            self.animate_location(obj, frames, ball=True)
            self.track_visibility(obj, frames)
        else:
            obj.hide_render = obj.hide_viewport = True
            obj["trackingStatus"] = "untracked; ball deliberately hidden"

    def track_visibility(self, obj, frames):
        window = tracked_frame_window(frames, self.fps)
        if not window:
            obj.hide_render = obj.hide_viewport = True
            return
        for frame, hidden in [(0, True), (window[0], False), (window[1], True)]:
            obj.hide_render = obj.hide_viewport = hidden
            obj.keyframe_insert("hide_render", frame=frame)
            obj.keyframe_insert("hide_viewport", frame=frame)
        set_linear(obj)

    def visibility(self, obj, mark):
        window = annotation_frame_window(mark, self.players, self.fps, self.doc["duration"])
        if window is None:
            obj.hide_render = obj.hide_viewport = True
            obj["visibilityStatus"] = "no supplied tracking coverage during this annotation"
            return
        reveal, hide = window
        for frame, hidden in [(0, True), (reveal, False), (hide, True)]:
            obj.hide_render = obj.hide_viewport = hidden
            obj.keyframe_insert("hide_render", frame=frame)
            obj.keyframe_insert("hide_viewport", frame=frame)
        set_linear(obj)

    def annotations(self):
        colors = {"run": (0.7, 1, 0.02), "pass": (0.05, 0.75, 1),
                  "space": (0.05, 0.8, 0.6), "danger": (1, 0.25, 0.1), "playerLabel": (1, 1, 1)}
        for mark in self.doc.get("annotations", []):
            name = "Mark_" + mark["id"]
            kind = mark["kind"]
            material = self.material("Annotation_" + kind, colors[kind], emission=0.5)
            count = 48 if kind == "space" else 2
            obj = self.line(name, [(0, 0, 0)] * count, material, 0.065, "Annotations", kind == "space")
            arrow = None if kind in {"space", "playerLabel"} else self.line(
                name + "_Arrow", [(0, 0, 0)] * 3, material, 0.08, "Annotations")
            label = self.text(name + "_Label", mark["label"], (0, 0, 0), size=0.35, collection="Annotations")
            obj["annotationJSON"] = json.dumps(mark, sort_keys=True)
            for time in annotation_times(mark, self.players, self.doc["duration"]):
                start = annotation_endpoint(mark, "start", time, self.players)
                end = annotation_endpoint(mark, "end", time, self.players)
                if kind == "playerLabel":
                    pose = sample_track(self.players[mark["playerID"]]["keyframes"], time)
                    start, end = (pose[0], pose[1], 0.08), (pose[0], pose[1], 2.15)
                if kind == "space":
                    centre = tuple((a + b) / 2 for a, b in zip(start, end))
                    radius = max(math.dist(start[:2], end[:2]) / 2, 0.3)
                    values = [(centre[0] + math.cos(i * math.tau / count) * radius,
                               centre[1] + math.sin(i * math.tau / count) * radius, centre[2]) for i in range(count)]
                else:
                    values = [start, end]
                for vertex, value in zip(obj.data.splines[0].points, values):
                    vertex.co = (*value, 1)
                    vertex.keyframe_insert("co", frame=frame_at(time, self.fps))
                label.location = (end[0], end[1], end[2] + 0.35)
                label.keyframe_insert("location", frame=frame_at(time, self.fps))
                if arrow:
                    length = max(math.dist(start, end), 0.001)
                    direction = tuple((b - a) / length for a, b in zip(start, end))
                    side = (-direction[1] * 0.35, direction[0] * 0.35, 0)
                    base = tuple(b - d * 0.8 for b, d in zip(end, direction))
                    values = [tuple(a + s for a, s in zip(base, side)), end, tuple(a - s for a, s in zip(base, side))]
                    for vertex, value in zip(arrow.data.splines[0].points, values):
                        vertex.co = (*value, 1)
                        vertex.keyframe_insert("co", frame=frame_at(time, self.fps))
            for item in [obj, label] + ([arrow] if arrow else []):
                self.visibility(item, mark)
                set_linear(item)
                if item.type == "CURVE":
                    set_linear(item.data)

    def finish(self, manifest_hash):
        self.pitch()
        self.cameras_and_players()
        self.ball()
        self.annotations()
        has_tracks = any(player["keyframes"] for player in self.doc["players"])
        origins = sorted({frame["evidence"]["origin"] for player in self.doc["players"]
                          for frame in player["keyframes"]})
        status = "REFERENCE TRACKS: " + " / ".join(origins).upper() if has_tracks else "REFERENCE / PLAYER TRACKS PENDING"
        if self.doc["source"].get("provenance") == "synthetic-test-not-match-footage":
            status = "SYNTHETIC ASSEMBLY TEST / NOT A MATCH RECONSTRUCTION"
        self.text("EvidenceStatus", status, (0, -58, 0.05), size=1.2)
        self.scene["replayStatus"] = status
        self.scene["manifestSHA256"] = manifest_hash
        self.scene["referenceSourceJSON"] = json.dumps(self.doc["source"], sort_keys=True)
        self.scene["measured3D"] = self.doc["trackEvidence"]["measured3D"]
        self.scene["motionPolicy"] = "linear interpolation between supplied tracks; rig gait is illustrative"
        text = self.bpy.data.texts.new("ReplayXI_TrackManifest_" + self.doc["id"])
        text.write(json.dumps(self.doc, indent=2))
        text.use_fake_user = True
        self.scene["manifestText"] = text.name
        world = self.bpy.data.worlds.new("ReplayXI_Daylight")
        world.use_nodes = True
        world.node_tree.nodes["Background"].inputs[0].default_value = (0.35, 0.45, 0.6, 1)
        world.node_tree.nodes["Background"].inputs[1].default_value = 0.5
        self.scene.world = world
        light_data = self.bpy.data.lights.new("ReplayXI_Sun", "SUN")
        light_data.energy, light_data.angle = 3, math.radians(12)
        light = self.bpy.data.objects.new("ReplayXI_Sun", light_data)
        self.collections["Pitch"].objects.link(light)
        light.rotation_euler = (0.6, -0.4, -0.4)
        evaluate_scene_frame(self.bpy, self.scene, 1)
        return text


def export_inspection_glb(builder, output, time):
    """Bake one evaluated snapshot; never mislabel a GLB as the full timeline."""
    bpy, scene = builder.bpy, builder.scene
    output = Path(output).resolve()
    license_path = output.with_suffix(".license.txt")
    if output.exists() or builder.related_texts and license_path.exists():
        raise ContractError("inspection output already exists")
    evaluate_scene_frame(bpy, scene, frame_at(time, builder.fps))
    snapshot = bpy.data.scenes.new(scene.name + "_Inspection")
    snapshot.world = scene.world
    with scene_context(bpy, scene):
        graph = bpy.context.evaluated_depsgraph_get()
        graph.update()
        for original in scene.objects:
            if original.hide_render or original.hide_viewport:
                continue
            evaluated = original.evaluated_get(graph)
            if original.type in {"MESH", "CURVE", "FONT"}:
                data = bpy.data.meshes.new_from_object(evaluated, depsgraph=graph)
                for index, slot in enumerate(original.material_slots):
                    if index < len(data.materials):
                        data.materials[index] = slot.material
            elif original.type in {"CAMERA", "LIGHT"}:
                data = original.data.copy()
            else:
                continue
            clone = bpy.data.objects.new(original.name, data)
            snapshot.collection.objects.link(clone)
            clone.matrix_world = evaluated.matrix_world.copy()
            if original is scene.camera:
                snapshot.camera = clone
    output.parent.mkdir(parents=True, exist_ok=True)
    with scene_context(bpy, snapshot):
        bpy.ops.export_scene.gltf(
            filepath=str(output), export_format="GLB", use_active_scene=True,
            export_cameras=True, export_lights=True, export_animations=False,
            export_apply=True, use_visible=True, use_renderable=True,
            export_copyright="Copyright (c) 2020 Microsoft, MIT; see companion license" if builder.related_texts else ""
        )
    if builder.related_texts:
        with license_path.open("x") as stream:
            stream.write("\n\n".join(text.as_string() for text in builder.related_texts))


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--manifest", type=Path, required=True)
    parser.add_argument("--output", type=Path)
    parser.add_argument("--player-library", type=Path)
    parser.add_argument("--glb-output", type=Path, help="Optional static inspection GLB; editable .blend retains timeline")
    parser.add_argument("--preview-time", type=float, default=0, help="Timestamp shown in the static GLB snapshot")
    parser.add_argument("--fps", type=int, choices=(24, 25, 30, 60), default=30)
    parser.add_argument("--validate-only", action="store_true")
    args = parser.parse_args(argv)
    document, digest = read_manifest(args.manifest)
    number(args.preview_time, "preview-time", 0, document["duration"])
    players = {player["id"]: player for player in document["players"]}
    estimated_scalars = sum(len(player["keyframes"]) * 4 for player in players.values())
    estimated_scalars += sum(len(annotation_times(mark, players, document["duration"]))
                             * (195 if mark["kind"] == "space" else 23)
                             for mark in document.get("annotations", []))
    if estimated_scalars > MAX_ANIMATION_SCALARS:
        raise ContractError("animation budget exceeded; reduce annotation density or input sampling frequency")
    if args.validate_only:
        print(json.dumps({"valid": True, "id": document["id"], "manifestSHA256": digest,
                          "players": len(document["players"]), "sourceStatus": document["source"]["status"]}))
        return 0
    if not args.output or args.output.suffix != ".blend":
        raise ContractError("--output must name a new .blend file")
    output = args.output.resolve()
    report_path = output.with_suffix(".report.json")
    if output.exists() or report_path.exists():
        raise ContractError("output already exists; choose a new filename")
    if args.glb_output and (args.glb_output.suffix != ".glb" or args.glb_output.exists()):
        raise ContractError("--glb-output must name a new .glb file")
    if output == args.manifest.resolve() or args.player_library and output == args.player_library.resolve():
        raise ContractError("output must be separate from inputs")
    import bpy
    builder = SceneBuilder(bpy, document, args.fps, args.player_library)
    manifest_text = builder.finish(digest)
    output.parent.mkdir(parents=True, exist_ok=True)
    bpy.data.libraries.write(str(output), {builder.scene, manifest_text, *builder.related_texts},
                             path_remap="RELATIVE", fake_user=True)
    if args.glb_output:
        export_inspection_glb(builder, args.glb_output, args.preview_time)
    report = {"schemaVersion": 1, "scene": builder.scene.name, "blendPath": str(output),
              "manifestSHA256": digest, "status": builder.scene["replayStatus"],
              "playerIdentityCount": len(document["players"]),
              "trackedPlayerCount": sum(bool(p["keyframes"]) for p in document["players"]),
              "annotationCount": len(document.get("annotations", [])), "fps": args.fps,
              "duration": document["duration"], "measured3D": document["trackEvidence"]["measured3D"],
              "cameraPolicy": "player translation follows tracks; POV rotation is editable and unkeyed",
              "videoReconstructionPerformed": False}
    if args.glb_output:
        report["inspectionGLB"] = str(args.glb_output.resolve())
        report["inspectionSnapshotTime"] = args.preview_time
        report["inspectionGLBLimitation"] = "Static snapshot only; the complete animated scene and annotation timing remain in .blend"
    with report_path.open("x") as stream:
        json.dump(report, stream, indent=2)
    print(json.dumps(report))
    return 0


if __name__ == "__main__":
    try:
        cli = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else sys.argv[1:]
        raise SystemExit(main(cli))
    except (ContractError, OSError, json.JSONDecodeError) as error:
        print(f"Match assembly stopped: {error}", file=sys.stderr)
        raise SystemExit(2)
