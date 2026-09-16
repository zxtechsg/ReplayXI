"""Keep UI gesture origins on the same presented players as the scene."""
import pathlib
import unittest


ROOT = pathlib.Path(__file__).resolve().parents[2]


class PresentedAnnotationInputTests(unittest.TestCase):
    def test_player_taps_short_drags_and_draw_origins_use_presented_positions(self):
        source = (ROOT / "ReplayXI/Immersive/FootballImmersiveView.swift").read_text()
        routing = source.split("private func nearestPlayer(", 1)[1].split(
            "private func cancelInterruptedSpatialInteraction()", 1
        )[0]
        self.assertNotIn(".presentationPose(at:", routing)
        self.assertNotIn("mark.resolvedGeometry(", routing)
        self.assertEqual(routing.count("store.presentedPlayerPose(for:"), 4)
        self.assertEqual(routing.count("store.presentedCoachMarkGeometry(mark,"), 2)
        self.assertIn("private func recoverTapIntentFromShortDrag(", routing)
        self.assertIn("private func handleAnnotationStrokeChanged(", routing)


if __name__ == "__main__":
    unittest.main()
