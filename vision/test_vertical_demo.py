"""Camera-free checks: python -m unittest discover -s vision -v"""
import unittest
from types import SimpleNamespace
from hand_detector import PALM_LANDMARKS, Palm, PalmSlots, extract_palms
from vertical_demo import draw_panel
from hand_state import HandStateTracker


def palm(name, x, y, score=0.95):
    return Palm((x, y), name, score, ((x, y),) * 21)


class PalmDetectionTests(unittest.TestCase):
    def test_palm_center_ignores_fingertips(self):
        landmarks = [SimpleNamespace(x=0.9, y=0.9) for _ in range(21)]
        for index in PALM_LANDMARKS:
            landmarks[index] = SimpleNamespace(x=0.3, y=0.4)
        result = SimpleNamespace(hand_landmarks=[landmarks], handedness=[[
            SimpleNamespace(category_name="Left", score=0.99)]])
        detected = extract_palms(result)
        self.assertAlmostEqual(detected[0].position[0], 0.3)
        self.assertAlmostEqual(detected[0].position[1], 0.4)

    def test_anatomical_slots_not_screen_order(self):
        hands = PalmSlots().update([palm("Right", 0.2, 0.6), palm("Left", 0.8, 0.3)], 0)
        self.assertEqual(hands[0].position, (0.8, 0.3))
        self.assertEqual(hands[1].position, (0.2, 0.6))

    def test_mirrored_model_labels_are_corrected_before_slot_assignment(self):
        result = SimpleNamespace(
            hand_landmarks=[
                [SimpleNamespace(x=0.3, y=0.2) for _ in range(21)],
                [SimpleNamespace(x=0.7, y=0.8) for _ in range(21)],
            ],
            handedness=[
                [SimpleNamespace(category_name="Left", score=0.99)],
                [SimpleNamespace(category_name="Right", score=0.99)],
            ],
        )
        hands = PalmSlots().update(extract_palms(result), 0.0)
        self.assertEqual(hands[0].handedness, "Left")
        self.assertAlmostEqual(hands[0].position[1], 0.8)
        self.assertEqual(hands[1].handedness, "Right")
        self.assertAlmostEqual(hands[1].position[1], 0.2)

    def test_independent_motion_and_temporary_label_flip(self):
        slots = PalmSlots()
        slots.update([palm("Left", 0.3, 0.4), palm("Right", 0.7, 0.6)], 0)
        hands = slots.update([palm("Left", 0.7, 0.65), palm("Right", 0.3, 0.35)], 0.05)
        self.assertEqual(hands[0].position, (0.3, 0.35))
        self.assertEqual(hands[1].position, (0.7, 0.65))

    def test_single_right_hand_does_not_fill_left_slot(self):
        hands = PalmSlots().update([palm("Right", 0.2, 0.3)], 0)
        self.assertIsNone(hands[0])
        self.assertIsNotNone(hands[1])

    def test_missing_hand_is_not_stale(self):
        slots = PalmSlots()
        slots.update([palm("Left", 0.3, 0.4)], 0)
        self.assertEqual(slots.update([], 0.05), [None, None])
        self.assertEqual(draw_panel(HandStateTracker().hands, 0, 0).shape, (480, 640, 3))

    def test_impossible_jump_then_reacquisition(self):
        slots = PalmSlots()
        slots.update([palm("Left", 0.1, 0.1)], 0)
        self.assertEqual(slots.update([palm("Left", 0.9, 0.9)], 0.01), [None, None])
        self.assertIsNotNone(slots.update([palm("Left", 0.9, 0.9)], 0.3)[0])

    def test_uncertain_initial_handedness_is_rejected(self):
        hands = PalmSlots().update([palm("Left", 0.3, 0.4, score=0.55)], 0)
        self.assertEqual(hands, [None, None])

    def test_one_detection_never_drives_both_slots(self):
        slots = PalmSlots()
        slots.update([palm("Left", 0.45, 0.5), palm("Right", 0.55, 0.5)], 0)
        hands = slots.update([palm("Left", 0.5, 0.5)], 0.05)
        self.assertEqual(sum(hand is not None for hand in hands), 1)

    def test_empty_model_result(self):
        self.assertEqual(extract_palms(SimpleNamespace(hand_landmarks=[], handedness=[])), [])


if __name__ == "__main__":
    unittest.main()
