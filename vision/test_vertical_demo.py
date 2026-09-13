"""Camera-free checks: python -m unittest discover -s vision -v"""
import unittest
from types import SimpleNamespace
from hand_detector import PALM_LANDMARKS, Palm, PalmSlots, extract_palms
from vertical_demo import draw_panel
from hand_state import HandStateTracker


def palm(name, x, y, score=0.95):
    return Palm((x, y), name, score, ((x, y),) * 21)


def confirmed(slots, hands):
    for t in (-.08, -.04, 0):
        result = slots.update(hands, t)
    return result


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
        hands = confirmed(PalmSlots(), [palm("Right", 0.2, 0.6), palm("Left", 0.8, 0.3)])
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
        hands = confirmed(PalmSlots(), extract_palms(result))
        self.assertEqual(hands[0].handedness, "Left")
        self.assertAlmostEqual(hands[0].position[1], 0.8)
        self.assertEqual(hands[1].handedness, "Right")
        self.assertAlmostEqual(hands[1].position[1], 0.2)

    def test_temporary_label_flip_drops_input_instead_of_overriding_anatomy(self):
        slots = PalmSlots()
        confirmed(slots, [palm("Left", .3, .4), palm("Right", .7, .6)])
        self.assertEqual(slots.update([palm("Left", .7, .65), palm("Right", .3, .35)], .05), [None,None])
        restored = [palm("Left", .3, .35), palm("Right", .7, .65)]
        self.assertEqual(slots.update(restored, .08), [None,None])
        hands = slots.update(restored, .15)
        self.assertEqual([p.handedness for p in hands], ["Left", "Right"])

    def test_single_right_hand_does_not_fill_left_slot(self):
        hands = confirmed(PalmSlots(), [palm("Right", 0.2, 0.3)])
        self.assertIsNone(hands[0])
        self.assertIsNotNone(hands[1])

    def test_missing_hand_is_not_stale(self):
        slots = PalmSlots()
        confirmed(slots, [palm("Left", 0.3, 0.4)])
        self.assertEqual(slots.update([], 0.05), [None, None])
        self.assertEqual(draw_panel(HandStateTracker().hands, 0, 0).shape, (480, 640, 3))

    def test_impossible_jump_then_reacquisition(self):
        slots = PalmSlots()
        confirmed(slots, [palm("Left", 0.1, 0.1)])
        self.assertEqual(slots.update([palm("Left", 0.9, 0.9)], 0.01), [None, None])
        self.assertEqual(slots.update([palm("Left", 0.9, 0.9)], .3), [None,None])
        self.assertIsNotNone(slots.update([palm("Left", .9, .9)], .37)[0])

    def test_uncertain_initial_handedness_is_rejected(self):
        hands = PalmSlots().update([palm("Left", 0.3, 0.4, score=0.55)], 0)
        self.assertEqual(hands, [None, None])

    def test_one_detection_never_drives_both_slots(self):
        slots = PalmSlots()
        confirmed(slots, [palm("Left", 0.45, 0.5), palm("Right", 0.55, 0.5)])
        hands = slots.update([palm("Left", 0.5, 0.5)], 0.05)
        self.assertEqual(sum(hand is not None for hand in hands), 1)

    def test_right_hand_cannot_fill_recent_left_slot(self):
        slots = PalmSlots()
        confirmed(slots, [palm("Left", .3, .4)])
        self.assertEqual(slots.update([palm("Right", .3, .4)], .05), [None,None])
        self.assertEqual(slots.reasons[1], "opposite_track_conflict")

    def test_uncertain_handedness_is_rejected_even_during_continuity(self):
        slots = PalmSlots()
        confirmed(slots, [palm("Left", .3, .4)])
        self.assertEqual(slots.update([palm("Left", .3, .4, .79)], .05), [None,None])
        self.assertEqual(slots.reasons[0], "low_handedness")

    def test_duplicate_left_hands_are_ambiguous_and_never_fill_right(self):
        slots = PalmSlots()
        hands = [palm("Left", .3, .4), palm("Left", .7, .4)]
        self.assertEqual(confirmed(slots, hands), [None,None])
        self.assertEqual(slots.reasons, ["ambiguous_same_side", "no_matching_hand"])

    def test_seated_startup_and_long_absence_need_no_calibration(self):
        slots = PalmSlots()
        hand = palm("Left", .3, .4)
        self.assertEqual(slots.update([hand], 0), [None,None])
        self.assertEqual(slots.update([hand], .04), [None,None])
        self.assertIsNotNone(slots.update([hand], .08)[0])
        self.assertEqual(slots.update([], 5), [None,None])
        hand = palm("Left", .8, .6)
        self.assertEqual(slots.update([hand], 6), [None,None])
        self.assertIsNotNone(slots.update([hand], 6.07)[0])
        # Already confirmed hands are published on each fresh frame.
        self.assertIsNotNone(slots.update([hand], 6.08)[0])

    def test_confirmation_restarts_after_uncertainty(self):
        slots = PalmSlots()
        hand = palm("Left", .3, .4)
        slots.update([hand], 0)
        slots.update([palm("Left", .3, .4, .6)], .04)
        self.assertEqual(slots.update([hand], .08), [None,None])
        self.assertIsNotNone(slots.update([hand], .15)[0])

    def test_invalid_scores_and_timestamps_are_rejected(self):
        for score in (float("nan"), float("inf"), 1.1):
            self.assertEqual(confirmed(PalmSlots(), [palm("Left", .3, .4, score)]), [None,None])
        slots = PalmSlots()
        slots.update([], 0)
        for timestamp in (0, -.1, float("nan")):
            with self.assertRaises(ValueError):
                slots.update([], timestamp)

    def test_empty_model_result(self):
        self.assertEqual(extract_palms(SimpleNamespace(hand_landmarks=[], handedness=[])), [])


if __name__ == "__main__":
    unittest.main()
