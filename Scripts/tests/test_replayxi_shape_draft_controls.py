"""Keep every Shape comparison surface behind the drawing-aware Store gate."""
import pathlib
import unittest


ROOT = pathlib.Path(__file__).resolve().parents[2]


class ShapeDraftControlTests(unittest.TestCase):
    def test_store_comparison_uses_the_drawing_aware_gate(self):
        source = (ROOT / "ReplayXI/Domain/PlaybackStore.swift").read_text()
        action = source.split("func setShapeFocusStage(", 1)[1].split(
            "func setFollowingCoach(", 1
        )[0]
        self.assertIn("guard allowsPlaybackViewChange() else { return }", action)
        self.assertLess(action.index("guard allowsPlaybackViewChange()"),
                        action.index("shapeFocusStage = stage"))

    def test_immersive_stage_and_compare_buttons_share_the_gate(self):
        source = (ROOT / "ReplayXI/Immersive/FootballImmersiveView.swift").read_text()
        panel = source.split("private struct PositioningPanel: View", 1)[1]
        gate = panel.split("private func stageIsEnabled(", 1)[1].split(
            "private func color(", 1
        )[0]
        self.assertIn("store.triangleLockMode != .place && store.canChangePlaybackView", gate)
        progress = panel.split("private var shapeProgress:", 1)[1].split(
            "private var shapeReviewContent:", 1
        )[0]
        self.assertIn(".disabled(!stageIsEnabled(item))", progress)
        review = panel.split("private var shapeReviewContent:", 1)[1].split(
            "private var placementPreflight:", 1
        )[0]
        self.assertIn(".disabled(!stageIsEnabled(.ideal))", review)
        self.assertIn(".disabled(!stageIsEnabled(.problem))", review)

    def test_dashboard_gates_comparisons_without_locking_room_entry(self):
        source = (ROOT / "ReplayXI/UI/ReplayDashboardView.swift").read_text()
        panel = source.split("private struct ShapeFocusDashboard: View", 1)[1].split(
            "private struct ", 1
        )[0]
        gate = panel.split("private var canCompareShapes:", 1)[1].split(
            "var body:", 1
        )[0]
        self.assertIn("store.triangleLockMode != .place && store.canChangePlaybackView", gate)
        self.assertIn("enabled: item == .physical ? canEnterSpatialSetup : canCompareShapes", panel)
        self.assertEqual(panel.count(".disabled(!canCompareShapes)"), 2)
        entry = panel.split("private var canEnterSpatialSetup:", 1)[1].split(
            "private var canCompareShapes:", 1
        )[0]
        self.assertNotIn("canChangePlaybackView", entry)
        self.assertNotIn("isDrawing", entry)


if __name__ == "__main__":
    unittest.main()
