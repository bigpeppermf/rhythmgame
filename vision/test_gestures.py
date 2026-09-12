"""Gesture decisions, temporal confirmation, and optional wire fields."""

import socket
from types import SimpleNamespace
import unittest

from gestures import Gesture, GestureDebouncer, classify_gesture, pinch_gesture
from hand_detector import PalmSlots, extract_palms
from hand_state import HandStateTracker
from udp_protocol import UdpHandSender, build_packet, decode_packet, validate_packet


def category(name, score=0.95):
    return SimpleNamespace(category_name=name, score=score)


def pinch_points(scale=1.0, gap=0.01):
    points = [[0.0, 0.0, 0.0] for _ in range(21)]
    points[17] = [1, 0, 0]
    points[8] = [0.5, 1, 0]
    points[4] = [0.5 + gap, 1, 0]
    points[2] = [0, 0.1, 0]
    # Supply actual curled middle/ring/little chains, not absent zero landmarks.
    points[0] = [0, -1, 0]
    for base, x in ((9, 0.3), (13, 0.6), (17, 1.0)):
        for offset, y in enumerate((0, 0.25, -0.02, -0.18)):
            points[base + offset] = [x, y, 0]
    return [SimpleNamespace(x=x * scale, y=y * scale, z=z * scale) for x, y, z in points]


class GestureTests(unittest.TestCase):
    def test_model_gestures_are_distinct(self):
        for model, expected in (("Open_Palm", "OPEN_PALM"), ("Closed_Fist", "FIST"),
                                ("Thumb_Up", "THUMBS_UP")):
            with self.subTest(model=model):
                self.assertEqual(classify_gesture([category(model)]), Gesture(expected, 0.95))

    def test_unknown_and_low_confidence_are_not_forced_to_open_palm(self):
        for categories in ([], [category("None")], [category("Closed_Fist", 0.6)],
                           [category("Victory", 0.99), category("Open_Palm", 0.75)]):
            self.assertEqual(classify_gesture(categories), Gesture())

    def test_pinch_is_relative_to_hand_size_and_opens_when_separated(self):
        for scale in (0.03, 0.06, 1):
            self.assertEqual(pinch_gesture(pinch_points(scale)).label, "PINCH")
            self.assertEqual(pinch_gesture(pinch_points(scale, gap=0.5)), Gesture())
        self.assertEqual(classify_gesture([category("Open_Palm")], pinch_points()).label, "PINCH")

    def test_clenched_and_degenerate_landmarks_do_not_become_pinch(self):
        points = pinch_points()
        points[8] = SimpleNamespace(x=0.01, y=0.01, z=0)
        points[4] = SimpleNamespace(x=0.01, y=0.01, z=0)
        self.assertEqual(pinch_gesture(points), Gesture())
        self.assertEqual(pinch_gesture([]), Gesture())
        self.assertEqual(pinch_gesture([SimpleNamespace(x=0, y=0, z=0)] * 21), Gesture())

    def test_fist_label_can_be_refined_to_closed_hand_pinch(self):
        self.assertEqual(classify_gesture([category("Closed_Fist")], pinch_points()).label, "PINCH")

    def test_gestures_follow_slot_assignment(self):
        result = SimpleNamespace(
            hand_landmarks=[[SimpleNamespace(x=0.3, y=0.4)] * 21,
                            [SimpleNamespace(x=0.7, y=0.6)] * 21],
            handedness=[[category("Right")], [category("Left")]],
            gestures=[[category("Closed_Fist")], [category("Open_Palm")]],
        )
        left, right = PalmSlots().update(extract_palms(result), 0)
        self.assertEqual(left.gesture.label, "FIST")
        self.assertEqual(right.gesture.label, "OPEN_PALM")

    def test_confirmation_and_loss_are_independent_per_slot(self):
        debouncer = GestureDebouncer()
        poses = [Gesture("FIST", 0.9), Gesture("OPEN_PALM", 0.8)]
        self.assertEqual(debouncer.update(poses, 0), [Gesture(), Gesture()])
        self.assertEqual(debouncer.update(poses, 0.03), [Gesture(), Gesture()])
        self.assertEqual(debouncer.update(poses, 0.06), poses)
        self.assertEqual(debouncer.update([Gesture(), poses[1]], 0.07), [Gesture(), poses[1]])
        self.assertEqual(debouncer.update(poses, 0.08), [Gesture(), poses[1]])
        self.assertEqual(debouncer.update(poses, 0.5), [Gesture(), Gesture()])

    def test_gesture_clears_on_coasting_and_loss(self):
        tracker = HandStateTracker()
        tracker.update([(0.3, 0.4), None], 0, [Gesture("FIST", 0.9), Gesture()])
        for timestamp in (0.1, 0.2):
            hand = tracker.update([None, None], timestamp)[0]
            self.assertEqual(hand.gesture, Gesture())

    def test_default_packet_unchanged_optional_gestures_cross_real_udp(self):
        hands = HandStateTracker().update([(0.3, 0.4), (0.7, 0.6)], 0,
                                         [Gesture("FIST", 0.9), Gesture("PINCH", 0.8)])
        self.assertNotIn("gesture", build_packet(0, 0, 0, hands)["hands"][0])
        with socket.socket(socket.AF_INET, socket.SOCK_DGRAM) as receiver:
            receiver.bind(("127.0.0.1", 0))
            receiver.settimeout(2)
            sender = UdpHandSender(port=receiver.getsockname()[1], include_gestures=True)
            self.addCleanup(sender.close)
            self.assertTrue(sender.send(hands, 0, 0))
            packet = decode_packet(receiver.recvfrom(65535)[0])
            self.assertEqual(packet["hands"][0]["gesture"], "FIST")
            self.assertEqual(packet["hands"][1]["gesture"], "PINCH")

    def test_missing_hand_cannot_publish_fist(self):
        packet = build_packet(0, 0, 0, HandStateTracker().hands, include_gestures=True)
        packet["hands"][0].update(gesture="FIST", gesture_conf=0.9)
        with self.assertRaises(ValueError):
            validate_packet(packet)


if __name__ == "__main__":
    unittest.main()
