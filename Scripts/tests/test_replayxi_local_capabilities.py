"""Prevent accidental reintroduction of paid-team group capabilities."""
import pathlib
import plistlib
import re
import unittest

ROOT = pathlib.Path(__file__).resolve().parents[2]
APP = ROOT / "ReplayXI"


class LocalCapabilityTests(unittest.TestCase):
    def test_group_entitlement_is_absent(self):
        entitlements = plistlib.loads((APP / "ReplayXI.entitlements").read_bytes())
        self.assertNotIn("com.apple.developer.group-session", entitlements)
        project = (ROOT / "ReplayXI.xcodeproj/project.pbxproj").read_text()
        self.assertNotIn("com.apple.GroupActivities", project)

    def test_app_has_no_group_transport_or_invites(self):
        forbidden = re.compile(
            r"import\s+GroupActivities|GroupSessionMessenger|groupActivityAssociation"
            r"|worldAnchorSharingAvailability|sharedWithNearbyParticipants"
            r"|startSharePlay\(|ReplayXIActivity|SquadSessionCoordinator"
        )
        for source in APP.rglob("*.swift"):
            with self.subTest(source=source.relative_to(ROOT)):
                self.assertIsNone(forbidden.search(source.read_text()))

    def test_local_launch_and_local_anchor_route_are_present(self):
        entry = (APP / "ReplayXIApp.swift").read_text()
        self.assertIn("store.prepareForLocalExperience()", entry)
        anchors = (APP / "Immersive/LocalPitchAnchorCoordinator.swift").read_text()
        self.assertIn("func placeLocalPitchAnchorAtCurrentHeadset()", anchors)
        self.assertIn("guard anchor.id == locallyPlacedPitchAnchorID", anchors)

    def test_legacy_harness_is_test_only_and_offline(self):
        self.assertFalse((APP / "Collaboration/SquadSessionCoordinator.swift").exists())
        fixture = (ROOT / "ReplayXITests/LegacySnapshotCoordinator.swift").read_text()
        self.assertIn("final class LegacySnapshotCoordinator", fixture)
        self.assertNotRegex(fixture, r"import\s+GroupActivities|messenger\.send|activity\.activate")

    def test_spatial_workspace_is_once_anchored_and_recenter_is_explicit(self):
        placement = (APP / "Immersive/PlaybackAttachmentPlacement.swift").read_text()
        immersive = (APP / "Immersive/FootballImmersiveView.swift").read_text()
        self.assertIn("AnchorEntity(.head, trackingMode: .once)", placement)
        self.assertNotIn(".continuous", placement)
        self.assertIn("PlaybackAttachmentPlacement.needsRecenter", immersive)
        self.assertIn("entity.parent !== controlsAnchor", immersive)
        self.assertNotIn("playback-controls-head-anchor", immersive)
        self.assertIn("Demo match · no video loaded", immersive)


if __name__ == "__main__":
    unittest.main()
