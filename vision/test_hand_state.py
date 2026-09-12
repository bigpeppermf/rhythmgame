"""Deterministic state transitions using capture times, without a camera."""

import unittest

from hand_state import HandStateTracker


class HandStateTests(unittest.TestCase):
    def test_startup_always_has_two_lost_slots(self):
        tracker = HandStateTracker()
        for hands in (tracker.hands, tracker.update([None, None], 0.0)):
            self.assertEqual([hand.slot for hand in hands], [0, 1])
            for hand in hands:
                self.assertEqual(hand.state, "LOST")
                self.assertEqual(hand.confidence, 0)
                self.assertIsNone(hand.last_seen)

    def test_hold_decay_and_exact_timeout_are_per_hand(self):
        tracker = HandStateTracker()
        original = tracker.update([(0.3, 0.4), (0.7, 0.5)], 0.0)
        for timestamp, expected_confidence in ((0.05, 0.75), (0.1, 0.5), (0.199, 0.005)):
            left, right = tracker.update([None, (0.7, 0.5)], timestamp)
            self.assertEqual(left.state, "COASTING")
            self.assertEqual(left.position, (0.3, 0.4))
            self.assertEqual(left.last_seen, 0.0)
            self.assertEqual(left.velocity, (0.0, 0.0))
            self.assertAlmostEqual(left.confidence, expected_confidence)
            self.assertEqual(right.state, "TRACKED")
            self.assertEqual(right.confidence, 1)
        left, right = tracker.update([None, (0.7, 0.5)], 0.2)
        self.assertEqual(left.state, "LOST")
        self.assertEqual(left.confidence, 0)
        self.assertEqual(left.position, (0.3, 0.4))
        self.assertEqual(right.state, "TRACKED")
        self.assertEqual(original[0].state, "TRACKED")  # Previous snapshots stay intact.

    def test_velocity_uses_elapsed_capture_time_and_stillness_is_tracked(self):
        tracker = HandStateTracker()
        first = tracker.update([(0.3, 0.4), None], 0.0)[0]
        self.assertEqual(first.velocity, (0, 0))
        moving = tracker.update([(0.35, 0.3), None], 0.1)[0]
        self.assertAlmostEqual(moving.velocity[0], 0.5)
        self.assertAlmostEqual(moving.velocity[1], -1.0)
        still = tracker.update([(0.35, 0.3), None], 0.15)[0]
        self.assertEqual(still.velocity, (0, 0))
        self.assertEqual(still.state, "TRACKED")

    def test_reacquisition_resets_velocity_after_coasting_or_loss(self):
        for absence in (0.05, 0.25):
            with self.subTest(absence=absence):
                tracker = HandStateTracker()
                tracker.update([(0.3, 0.4), None], 0.0)
                tracker.update([None, None], absence)
                hand = tracker.update([(0.8, 0.9), None], absence + 0.01)[0]
                self.assertEqual(hand.state, "TRACKED")
                self.assertEqual(hand.position, (0.8, 0.9))
                self.assertEqual(hand.velocity, (0, 0))
                self.assertEqual(hand.confidence, 1)
                self.assertEqual(hand.last_seen, absence + 0.01)

    def test_long_frame_gap_expires_without_intermediate_frames(self):
        tracker = HandStateTracker()
        tracker.update([(0.3, 0.4), None], 0.0)
        self.assertEqual(tracker.update([None, None], 2.0)[0].state, "LOST")
        tracker = HandStateTracker()
        tracker.update([(0.3, 0.4), None], 0.0)
        self.assertEqual(tracker.update([(0.8, 0.9), None], 2.0)[0].velocity, (0, 0))

    def test_invalid_timestamps_do_not_mutate_state(self):
        tracker = HandStateTracker()
        original = tracker.update([(0.3, 0.4), None], 1.0)
        for timestamp in (1.0, 0.5, float("nan"), float("inf")):
            with self.subTest(timestamp=timestamp), self.assertRaises(ValueError):
                tracker.update([None, None], timestamp)
            self.assertEqual(tracker.hands, original)

    def test_invalid_positions_do_not_partially_update_slots(self):
        tracker = HandStateTracker()
        original = tracker.hands
        for positions in ([], [None], [(0.3, 0.4), (float("nan"), 0.5)],
                          [(0.3, 0.4), (1.1, 0.5)]):
            with self.subTest(positions=positions), self.assertRaises(ValueError):
                tracker.update(positions, 0.0)
            self.assertEqual(tracker.hands, original)
        self.assertEqual(tracker.update([(0.3, 0.4), None], 0.0)[0].state, "TRACKED")


if __name__ == "__main__":
    unittest.main()
