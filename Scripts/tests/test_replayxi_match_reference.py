import csv
import json
import math
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch


PROJECT_ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(PROJECT_ROOT / "Scripts"))
import prepare_replayxi_match_reference as reference  # noqa: E402


class MatchReferenceTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory(prefix="replayxi-reference-test-")
        self.root = Path(self.temporary.name)
        self.source = self.root / "source.mp4"
        self.source.write_bytes(b"not decoded by pure tests")
        self.output = self.root / "prepared"

    def tearDown(self):
        self.temporary.cleanup()

    def validate(self, **overrides):
        options = dict(source=self.source, output=self.output, start=1, duration=60,
                       fps=2, width=1280, cut_threshold=0.35)
        options.update(overrides)
        reference.validate_options(**options)

    def test_explicit_valid_sixty_second_window(self):
        self.validate()
        self.validate(duration=0.1, fps=30)

    def test_invalid_or_unbounded_time_and_rate_fail(self):
        for values in ({"duration": 61}, {"duration": 0}, {"start": -1},
                       {"duration": math.nan}, {"start": math.inf}, {"fps": 0},
                       {"fps": 31}, {"cut_threshold": 0}, {"width": 1279}):
            with self.subTest(values=values), self.assertRaises(reference.ReferenceError):
                self.validate(**values)

    def test_refuses_existing_output_without_touching_it(self):
        self.output.mkdir()
        marker = self.output / "keep.txt"
        marker.write_text("keep")
        with self.assertRaisesRegex(reference.ReferenceError, "already exists"):
            self.validate()
        self.assertEqual(marker.read_text(), "keep")

    def test_repository_source_and_output_are_forbidden(self):
        with patch.object(reference, "PROJECT_ROOT", self.root):
            with self.assertRaisesRegex(reference.ReferenceError, "outside"):
                self.validate()
        with self.assertRaisesRegex(reference.ReferenceError, "outside"):
            self.validate(output=PROJECT_ROOT / "ReplayXI/Resources/new-evidence")

    def test_symlink_into_repository_is_forbidden(self):
        link = self.root / "linked-repo"
        link.symlink_to(PROJECT_ROOT, target_is_directory=True)
        with self.assertRaisesRegex(reference.ReferenceError, "outside"):
            self.validate(output=link / "new-evidence")

    def test_local_playlist_and_url_are_rejected(self):
        playlist = self.root / "external.m3u8"
        playlist.write_text("https://example.invalid/not-to-be-fetched")
        for source in (playlist, Path("https://example.invalid/match.mp4")):
            with self.subTest(source=source), self.assertRaises(reference.ReferenceError):
                self.validate(source=source)

    def test_pts_fraction_is_used_instead_of_rounded_display_time(self):
        log = ("[Parsed_showinfo_4] config in time_base: 1/30000, frame_rate: 30000/1001\n"
               "[Parsed_showinfo_4] n: 0 pts: 3033030 pts_time:101.101\n"
               "[Parsed_showinfo_4] n: 1 pts: 3048045 pts_time:101.602\n")
        frames = reference.parse_frame_times(log, start=101, duration=2)
        self.assertAlmostEqual(frames[1]["sourceSeconds"], 101.6015)
        self.assertAlmostEqual(frames[0]["replaySeconds"], 0.101)
        self.assertEqual(frames[0]["normalizedPTS"], 3033030)
        self.assertFalse(frames[0]["evidence"]["measured3D"])

    def test_missing_or_decreasing_frame_times_fail_closed(self):
        prefix = "config in time_base: 1/10, frame_rate: 10/1\n"
        for log in ("", prefix, prefix + "n: 0 pts: 9 pts_time:0.9\n",
                    prefix + "n: 1 pts: 12 pts_time:1.2\n",
                    prefix + "n: 0 pts: 12 pts_time:1.2\nn: 1 pts: 11 pts_time:1.1\n"):
            with self.subTest(log=log), self.assertRaises(reference.ReferenceError):
                reference.parse_frame_times(log, 1, 2)

    def test_cut_candidates_are_explicitly_unverified(self):
        log = ("[Parsed_metadata_8] frame:0 pts:20 pts_time:2\n"
               "[Parsed_metadata_8] lavfi.scene_score=0.8\n"
               "[Parsed_metadata_8] frame:1 pts:50 pts_time:5\n"
               "[Parsed_metadata_8] lavfi.scene_score=0.9\n")
        candidates = reference.parse_cut_candidates(log, 1, 3)
        self.assertEqual(len(candidates), 1)
        self.assertEqual(candidates[0]["replaySeconds"], 1)
        self.assertTrue(candidates[0]["requiresHumanReview"])
        self.assertIsNone(candidates[0]["confidence"])

    def test_decoder_is_time_bounded_and_network_protocols_disabled(self):
        command = reference.extraction_command("ffmpeg", self.source, self.output,
                                              100, 60, 2, 1280, 0.35)
        self.assertLess(command.index("-t"), command.index("-i"))
        self.assertEqual(command[command.index("-t") + 1], "60.000000000")
        self.assertEqual(command[command.index("-protocol_whitelist") + 1], "file,pipe")
        self.assertIn("-n", command)
        self.assertNotIn("-y", command)

    def test_unknown_duration_and_shorter_video_fail_before_decode(self):
        with patch.object(reference, "probe_video", return_value={"videoEndSeconds": 20}), \
                patch.object(reference, "run") as decode:
            with self.assertRaisesRegex(reference.ReferenceError, "shorten explicitly"):
                reference.prepare(self.source, self.output, start=5, duration=60,
                                  provenance="test fixture")
            decode.assert_not_called()
        self.assertFalse(self.output.exists())


@unittest.skipUnless(shutil.which("ffmpeg") and shutil.which("ffprobe"), "ffmpeg/ffprobe required")
class MatchReferenceFFmpegTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory(prefix="replayxi-reference-media-test-")
        self.root = Path(self.temporary.name)

    def tearDown(self):
        self.temporary.cleanup()

    def generate(self, name, arguments):
        source = self.root / name
        subprocess.run(["ffmpeg", "-hide_banner", "-loglevel", "error", "-nostdin", "-n",
                        *arguments, "-c:v", "libx264", "-threads", "1", str(source)],
                       check=True, timeout=30, capture_output=True)
        return source

    def test_nonzero_container_origin_keeps_exact_segment_times_and_cut(self):
        source = self.generate("two cuts offset.mp4", [
            "-f", "lavfi", "-i", "color=black:size=320x180:rate=10:duration=2",
            "-f", "lavfi", "-i", "color=white:size=320x180:rate=10:duration=2",
            "-filter_complex", "[0:v][1:v]concat=n=2:v=1:a=0", "-output_ts_offset", "7"])
        original = reference.sha256(source)
        output = self.root / "review"
        manifest_path = reference.prepare(source, output, start=1.15, duration=2,
                                          fps=2, width=320, provenance="Original synthetic test")
        manifest = json.loads(manifest_path.read_text())
        frames = manifest["frames"]
        self.assertEqual(len(frames), 4)
        self.assertAlmostEqual(frames[0]["sourceSeconds"], 1.2)
        self.assertAlmostEqual(frames[0]["replaySeconds"], 0.05)
        self.assertAlmostEqual(frames[0]["containerPTSSeconds"], 8.2)
        self.assertEqual(manifest["source"]["containerStartSeconds"], 7)
        self.assertEqual(reference.sha256(source), original)
        self.assertEqual(manifest["source"]["sha256"], original)
        self.assertFalse(manifest["source"]["copiedToOutput"])
        self.assertTrue(any(abs(cut["sourceSeconds"] - 2) < 0.01
                            for cut in manifest["cameraCuts"]["candidates"]))
        self.assertTrue((output / "contact-001.jpg").is_file())
        self.assertIn("Replay 0.050s", (output / "contact-sheet.html").read_text())
        with (output / "timestamps.csv").open() as handle:
            self.assertEqual(len(list(csv.DictReader(handle))), 4)
        for frame in frames:
            self.assertEqual(reference.sha256(output / frame["path"]), frame["sha256"])
        tracks = json.loads((output / "replay-tracks.template.json").read_text())
        self.assertEqual(tracks["source"]["referenceManifestSHA256"], reference.sha256(manifest_path))
        self.assertEqual(tracks["players"], [])
        self.assertEqual(tracks["ball"]["keyframes"], [])

    def test_full_sixty_second_window_and_source_change_aborts_publication(self):
        source = self.generate("long-test.mp4", ["-f", "lavfi", "-i",
                               "testsrc2=size=320x180:rate=5:duration=61"])
        output = self.root / "full-minute"
        manifest = json.loads(reference.prepare(
            source, output, start=0.15, duration=60, fps=0.25, width=320,
            provenance="Original synthetic timing fixture").read_text())
        self.assertEqual(manifest["timeline"]["durationSeconds"], 60)
        self.assertEqual(len(manifest["frames"]), 15)
        self.assertLess(manifest["frames"][-1]["replaySeconds"], 60)
        self.assertEqual(manifest["cameraCuts"]["candidates"], [])
        real_hash = reference.sha256
        count = 0

        def change_source_hash(path):
            nonlocal count
            if path == source.resolve():
                count += 1
                if count > 1:
                    return "0" * 64
            return real_hash(path)

        aborted = self.root / "changed"
        with patch.object(reference, "sha256", side_effect=change_source_hash):
            with self.assertRaisesRegex(reference.ReferenceError, "source changed"):
                reference.prepare(source, aborted, start=0, duration=0.5,
                                  fps=2, width=320, provenance="test")
        self.assertFalse(aborted.exists())
        self.assertEqual(list(self.root.glob(".replayxi-reference-*")), [])


if __name__ == "__main__":
    unittest.main()
