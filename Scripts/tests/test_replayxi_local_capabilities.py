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
        # The movable child, not the captured room anchor, owns drag offsets.
        self.assertIn("PlaybackAttachmentPlacement.contentRoot(in: controlsAnchor)", immersive)
        self.assertIn("entity.parent !== workspace", immersive)
        self.assertIn("workspace.addChild(entity)", immersive)
        self.assertIn("anchor.addChild(root)", placement)
        self.assertIn("workspace.position = workspaceMove.offset", immersive)
        self.assertNotIn("playback-controls-head-anchor", immersive)
        self.assertIn("Demo match · no video loaded", immersive)

    def test_positioning_panel_owns_and_cancels_its_placement_attempt(self):
        source = (APP / "Immersive/FootballImmersiveView.swift").read_text()
        panel = source.split("private struct PositioningPanel: View {", 1)[1].split("\nprivate struct ", 1)[0]
        self.assertIn("@State private var placementTask: Task<Void, Never>?", panel)
        self.assertIn("let requestID = placementAttempt.begin()", panel)
        self.assertEqual(panel.count("placementAttempt.owns(requestID)"), 3)
        rejected = panel.split("guard store.activateLocalTrianglePreview(anchorID: anchorID) else {", 1)[1].split(
            "sharedSpace.selectSharedPitchAnchor(id: anchorID)", 1
        )[0]
        self.assertLess(
            rejected.index("await sharedSpace.removeLocallyPlacedPitchAnchor(ifMatching: anchorID)"),
            rejected.index("guard placementAttempt.owns(requestID)"),
        )
        self.assertIn("!Task.isCancelled", rejected)
        self.assertIn("store.trianglePlacementInputBlockReason", rejected)
        self.assertIn("placementAttempt.finish(requestID)", panel)
        self.assertIn("placementAttempt.cancel()", panel)
        self.assertIn("placementTask?.cancel()", panel)
        self.assertIn("!sharedSpace.isRemovingPitchAnchor", panel)
        self.assertIn(".onChange(of: hasConfirmedClearArea)", panel)
        self.assertIn(".onDisappear { resetPlacementPreflight() }", panel)
        self.assertIn(".onChange(of: store.selectedScenarioID) { _, _ in resetPlacementPreflight() }", panel)
        self.assertIn("removeLocallyPlacedPitchAnchor(ifMatching: anchorID)", panel)

    def test_room_teardown_and_store_callbacks_use_exact_ownership(self):
        entry = (APP / "ReplayXIApp.swift").read_text()
        immersive = (APP / "Immersive/FootballImmersiveView.swift").read_text()
        coordinator = (APP / "Immersive/LocalPitchAnchorCoordinator.swift").read_text()
        self.assertIn("retireLocallyPlacedPitchAnchor(ifMatching: anchorID)", entry)
        self.assertNotIn("Task { await sharedSpace?", entry)
        self.assertIn("@State private var pitchTrackingOwner = UUID()", immersive)
        self.assertIn("sharedSpace.start(for: pitchTrackingOwner)", immersive)
        self.assertIn("sharedSpace.stopTracking(for: pitchTrackingOwner)", immersive)
        self.assertNotIn("sharedSpace.stop()", immersive)
        self.assertNotIn("removeLocallyPlacedPitchAnchor()", immersive)
        self.assertIn("await sessionStartTask?.value", coordinator)

    def test_room_presentation_uses_request_tokens_not_independent_flags(self):
        dashboard = (APP / "UI/ReplayDashboardView.swift").read_text()
        immersive = (APP / "Immersive/FootballImmersiveView.swift").read_text()
        store = (APP / "Domain/PlaybackStore.swift").read_text()
        self.assertIn("store.beginImmersiveOpen()", dashboard)
        entry = (APP / "ReplayXIApp.swift").read_text()
        self.assertIn('ImmersiveSpace(id: "ReplayRoom", for: UUID.self)', entry)
        self.assertIn('openImmersiveSpace(id: "ReplayRoom", value: requestID)', dashboard)
        self.assertIn("store.completeImmersiveOpen(requestID", dashboard)
        self.assertIn(".disabled(store.isRoomPresentationBusy)", dashboard)
        self.assertIn("Closing room…", dashboard)
        self.assertIn("store.beginImmersiveClose(requestID)", immersive)
        self.assertIn("store.immersiveRoomDidDisappear(requestID)", immersive)
        self.assertIn(".allowsHitTesting(acceptsRoomInteraction)", immersive)
        self.assertIn(".disabled(!acceptsRoomInteraction)", immersive)
        self.assertIn("guard acceptsRoomInteraction else { return }", immersive)
        for source in (dashboard, immersive, store):
            self.assertNotRegex(source, r"is(?:OpeningImmersive|ImmersiveOpen)\s*=")


if __name__ == "__main__":
    unittest.main()
