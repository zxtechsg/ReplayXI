import copy
import hashlib
import json
import math
from pathlib import Path
import sys
import tempfile
import unittest

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "blender"))
from build_match_replay import (  # noqa: E402
    ContractError, annotation_endpoint, annotation_frame_window, annotation_times, frame_at,
    read_manifest, sample_track, tracked_frame_window, validate_manifest,
)


def synthetic_test_manifest(video_path="/QA-ONLY/NOT-A-REAL-MATCH.mp4"):
    """Two-second geometry/rig QA fixture; never a match reconstruction."""
    evidence = {"origin": "manual", "confidence": 1, "sourceVisibility": "visible",
                "sourceFrameID": "synthetic-test-frame"}
    players = []
    for team, offset in [("home", -8), ("away", 8)]:
        for number in range(1, 12):
            x, z = (number - 6) * 3, offset
            players.append({
                "id": f"{team}-{number}", "displayName": f"QA ONLY {team} {number}",
                "shirtNumber": number, "team": team, "isGoalkeeper": number == 1,
                "keyframes": [{"time": time, "position": {"x": x + travel, "z": z},
                               "facingDegrees": 90, "evidence": dict(evidence)}
                              for time, travel in [(0, 0), (1, 2), (2, 4)]]})
    return {
        "schemaVersion": 1, "id": "SYNTHETIC-TEST-ONLY", "duration": 2,
        "coordinateSystem": "pitch-metres-x-width-z-length",
        "source": {"status": "reference-available", "videoPath": str(video_path),
                   "provenance": "synthetic-test-not-match-footage"},
        "trackEvidence": {"origin": "manual", "confidence": 1, "sourceVisibility": "visible", "measured3D": False},
        "players": players,
        "ball": {"keyframes": [{"time": time, "position": {"x": time * 2, "z": -8},
                                "height": 0.11, "evidence": dict(evidence)} for time in (0, 1, 2)]},
        "annotations": [{
            "id": "qa-pass", "kind": "pass", "label": "QA ONLY PASS",
            "start": {"x": 0, "z": -8}, "end": {"x": 3, "z": 8},
            "startElevation": 0.5, "endElevation": 1.5, "revealTime": 0.5, "hideTime": 1.5,
            "startTrackAnchor": {"playerID": "home-6", "offset": {"x": 0, "z": 0}},
            "endTrackAnchor": {"playerID": "away-7", "offset": {"x": 0, "z": 0}}
        }, {"id": "qa-space", "kind": "space", "label": "QA ONLY SPACE", "revealTime": 0,
            "start": {"x": -3, "z": -3}, "end": {"x": 3, "z": 3}}]
    }


class MatchAssemblyTests(unittest.TestCase):
    def test_pending_fixture_contains_no_invented_match(self):
        path = Path(__file__).resolve().parents[1] / "blender" / "reference-pending.json"
        document, digest = read_manifest(path)
        self.assertEqual(len(digest), 64)
        self.assertEqual(document["duration"], 60)
        self.assertEqual(document["players"], [])
        self.assertEqual(document["ball"]["keyframes"], [])
        self.assertFalse(document["trackEvidence"]["measured3D"])

    def test_complete_qa_roster_has_unique_22_identities(self):
        document = synthetic_test_manifest()
        validate_manifest(document)
        self.assertEqual(len(document["players"]), 22)
        self.assertEqual(document["duration"], 2)
        document["players"][1]["shirtNumber"] = 1
        with self.assertRaisesRegex(ContractError, "shirt numbers"):
            validate_manifest(document)

    def test_partial_roster_does_not_invent_missing_players(self):
        document = synthetic_test_manifest()
        document["players"].pop()
        with self.assertRaisesRegex(ContractError, "22 identities"):
            validate_manifest(document)

    def test_tracks_require_explicit_evidence_and_reference(self):
        document = synthetic_test_manifest()
        del document["players"][0]["keyframes"][0]["evidence"]
        with self.assertRaisesRegex(ContractError, "explicit"):
            validate_manifest(document)
        document = synthetic_test_manifest()
        document["source"]["status"] = "reference-pending"
        with self.assertRaisesRegex(ContractError, "available reference"):
            validate_manifest(document)

    def test_nonfinite_coordinates_bad_time_order_and_confidence_rejected(self):
        for key, value in [("time", -1), ("time", 3), ("facingDegrees", math.inf)]:
            document = synthetic_test_manifest()
            document["players"][0]["keyframes"][0][key] = value
            with self.assertRaises(ContractError):
                validate_manifest(document)
        document = synthetic_test_manifest()
        document["players"][0]["keyframes"][1]["time"] = 0
        with self.assertRaisesRegex(ContractError, "strictly"):
            validate_manifest(document)
        document = synthetic_test_manifest()
        document["players"][0]["keyframes"][0]["evidence"]["confidence"] = 1.01
        with self.assertRaises(ContractError):
            validate_manifest(document)

    def test_interpolation_does_not_overshoot_and_facing_uses_shortest_angle(self):
        frames = synthetic_test_manifest()["players"][0]["keyframes"][:2]
        frames[0]["facingDegrees"], frames[1]["facingDegrees"] = 350, 10
        pose = sample_track(frames, 0.5)
        self.assertEqual(pose[:2], (-14, -8))
        self.assertEqual(pose[2], 360)
        self.assertIsNone(sample_track([], 0))

    def test_frame_origin_and_known_tracking_window(self):
        frames = synthetic_test_manifest()["players"][0]["keyframes"][1:]
        self.assertEqual(frame_at(0, 30), 1)
        self.assertEqual(tracked_frame_window(frames, 30), (31, 62))
        self.assertIsNone(tracked_frame_window([], 30))

    def test_annotations_follow_their_players_at_scrubbed_times(self):
        document = synthetic_test_manifest()
        players = {p["id"]: p for p in document["players"]}
        mark = document["annotations"][0]
        self.assertEqual(annotation_endpoint(mark, "start", 1, players), (2, -8, 0.555))
        self.assertEqual(annotation_endpoint(mark, "end", 1, players), (5, 8, 1.555))
        self.assertEqual(annotation_times(mark, players, 2), [0, 0.5, 1, 1.5, 2])

    def test_unknown_annotation_target_and_sloped_zone_rejected(self):
        document = synthetic_test_manifest()
        document["annotations"][0]["startTrackAnchor"]["playerID"] = "missing"
        with self.assertRaisesRegex(ContractError, "roster player"):
            validate_manifest(document)

    def test_annotation_visibility_uses_intersection_of_supplied_track_windows(self):
        document = synthetic_test_manifest()
        players = {p["id"]: p for p in document["players"]}
        mark = copy.deepcopy(document["annotations"][0])
        mark["revealTime"], mark["hideTime"] = 0, 2
        players["home-6"]["keyframes"] = players["home-6"]["keyframes"][1:]
        players["away-7"]["keyframes"] = players["away-7"]["keyframes"][:2]
        self.assertEqual(annotation_frame_window(mark, players, 30, 2), (31, 32))
        players["away-7"]["keyframes"] = []
        self.assertIsNone(annotation_frame_window(mark, players, 30, 2))
        document = synthetic_test_manifest()
        document["annotations"][1]["endElevation"] = 2
        with self.assertRaisesRegex(ContractError, "one elevation"):
            validate_manifest(document)

    def test_reference_manifest_hash_is_checked(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            movie = root / "QA-ONLY-reference.mp4"
            movie.write_bytes(b"TEST ONLY")
            document = synthetic_test_manifest(movie)
            reference = root / "reference.json"
            reference.write_text("{}")
            document["source"].update(referenceManifestPath="reference.json", referenceManifestSHA256="0" * 64)
            path = root / "tracks.json"
            path.write_text(json.dumps(document))
            with self.assertRaisesRegex(ContractError, "hash mismatch"):
                read_manifest(path)

    def test_bound_video_bytes_and_source_frame_ids_are_verified(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            movie = root / "QA-ONLY-reference.mp4"
            movie.write_bytes(b"TEST ONLY")
            document = synthetic_test_manifest(movie)
            reference = root / "reference.json"
            reference_document = {"source": {"path": str(movie), "sha256": hashlib.sha256(movie.read_bytes()).hexdigest()},
                                  "timeline": {"durationSeconds": 2}, "frames": [{"id": "synthetic-test-frame"}]}
            reference.write_text(json.dumps(reference_document))
            document["source"].update(referenceManifestPath="reference.json",
                                      referenceManifestSHA256=hashlib.sha256(reference.read_bytes()).hexdigest())
            path = root / "tracks.json"
            path.write_text(json.dumps(document))
            read_manifest(path)
            movie.write_bytes(b"CHANGED VIDEO")
            with self.assertRaisesRegex(ContractError, "video hash mismatch"):
                read_manifest(path)
            movie.write_bytes(b"TEST ONLY")
            document["players"][0]["keyframes"][0]["evidence"]["sourceFrameID"] = "unknown"
            path.write_text(json.dumps(document))
            with self.assertRaisesRegex(ContractError, "unknown sourceFrameID"):
                read_manifest(path)


if __name__ == "__main__":
    unittest.main()
