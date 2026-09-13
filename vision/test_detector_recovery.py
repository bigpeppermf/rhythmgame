"""Inject the reported graph failure without a camera or native model."""

from types import SimpleNamespace
import unittest
from unittest.mock import Mock, patch

import numpy as np

from gestures import Gesture, GestureDebouncer
from hand_detector import HandDetector, PalmSlots
from hand_state import HandStateTracker
from udp_protocol import build_packet
from vertical_demo import poll_keys


ERROR = "CalculatorGraph::Run() failed: ConcatenateTensorVectorCalculator: Packet isn't the sole owner of the holder."
EMPTY = SimpleNamespace(hand_landmarks=[], handedness=[])


def task(error=None):
    instance = Mock()
    instance.recognize_for_video = Mock(return_value=EMPTY, side_effect=error)
    return instance


def detector(current, factory):
    instance = HandDetector.__new__(HandDetector)
    instance.mp = SimpleNamespace(Image=lambda **kwargs: kwargs, ImageFormat=SimpleNamespace(SRGB=1))
    instance.gestures_enabled = True
    instance.landmarker = current
    instance._task_factory = factory
    instance.recovery_failures = 0
    instance.paused = False
    instance.health_message = ""
    instance.slots = PalmSlots()
    instance.candidates = []
    instance.gesture_debouncer = GestureDebouncer()
    instance.last_timestamp_ms = -1
    return instance


class DetectorRecoveryTests(unittest.TestCase):
    def setUp(self):
        self.frame = np.zeros((48, 64, 3), dtype=np.uint8)
        printer = patch("builtins.print")
        printer.start()
        self.addCleanup(printer.stop)

    def test_failed_frame_clears_actions_then_recreates_task(self):
        broken, healthy = task(RuntimeError(ERROR)), task()
        factory = Mock(return_value=healthy)
        instance = detector(broken, factory)
        pose = [Gesture("PINCH", .9), Gesture("FIST", .9)]
        instance.gesture_debouncer.update(pose, 0)
        instance.gesture_debouncer.update(pose, .05)
        tracker = HandStateTracker()
        tracker.update([(.3, .4), (.7, .6)], .05, pose)
        hands = instance.detect(self.frame, .10)
        self.assertEqual(hands, [None, None])
        self.assertEqual(instance.gesture_debouncer.stable, [Gesture(), Gesture()])
        states = tracker.update([None, None], .10)
        packet = build_packet(1, .10, 30, states, include_gestures=True)
        self.assertTrue(all(hand["gesture"] == "UNKNOWN" for hand in packet["hands"]))
        broken.close.assert_called_once()
        factory.assert_not_called()  # Publish unavailable input before restart.
        self.assertEqual(instance.detect(self.frame, .15), [None, None])
        factory.assert_called_once()
        self.assertEqual(instance.health_message, "")
        self.assertEqual(instance.recovery_failures, 0)
        self.assertGreater(healthy.recognize_for_video.call_args.args[1], broken.recognize_for_video.call_args.args[1])

    def test_three_consecutive_failures_pause_until_r_retry(self):
        broken = [task(RuntimeError(ERROR)) for _ in range(3)]
        healthy = task()
        factory = Mock(side_effect=[broken[1], broken[2], healthy])
        instance = detector(broken[0], factory)
        for timestamp in (.1, .2, .3):
            self.assertEqual(instance.detect(self.frame, timestamp), [None, None])
        self.assertTrue(instance.paused)
        self.assertIn("paused", instance.health_message)
        self.assertEqual(instance.detect(self.frame, .4), [None, None])
        self.assertEqual(factory.call_count, 2)
        with patch("vertical_demo.cv2.waitKey", return_value=ord("r")), \
             patch("vertical_demo.cv2.getWindowProperty", return_value=1):
            self.assertEqual(poll_keys(True, retry=instance.retry), (True, False))
        instance.detect(self.frame, .5)
        self.assertFalse(instance.paused)
        self.assertIs(instance.landmarker, healthy)

    def test_factory_failure_stays_paused_without_repeated_creation(self):
        factory = Mock(side_effect=RuntimeError("Cannot recreate model"))
        instance = detector(task(RuntimeError(ERROR)), factory)
        instance.detect(self.frame, .1)
        self.assertEqual(instance.detect(self.frame, .2), [None, None])
        self.assertTrue(instance.paused)
        self.assertIn("restart failed", instance.health_message)
        instance.detect(self.frame, .3)
        factory.assert_called_once()

    def test_unrelated_inference_errors_are_not_swallowed(self):
        instance = detector(task(RuntimeError("Invalid inference timestamp")), Mock())
        with self.assertRaisesRegex(RuntimeError, "Invalid inference timestamp"):
            instance.detect(self.frame, .1)
        instance._task_factory.assert_not_called()

    def test_failed_graph_close_is_idempotent_and_preserves_other_errors(self):
        broken = task()
        broken.close.side_effect = RuntimeError(ERROR)
        instance = detector(broken, Mock())
        instance.close()
        instance.close()
        broken.close.assert_called_once()
        other = task()
        other.close.side_effect = RuntimeError("Other shutdown error")
        instance = detector(other, Mock())
        with self.assertRaisesRegex(RuntimeError, "Other shutdown error"):
            instance.close()

    def test_reset_clears_position_and_gesture_history(self):
        instance = detector(task(), Mock())
        instance.slots.previous = [(.3,.4), (.7,.6)]
        instance.gesture_debouncer.stable = [Gesture("FIST", .9)] * 2
        instance.reset_slots()
        self.assertEqual(instance.slots.previous, [None, None])
        self.assertEqual(instance.gesture_debouncer.stable, [Gesture(), Gesture()])
        with patch("vertical_demo.cv2.waitKey", return_value=ord("c")), \
             patch("vertical_demo.cv2.getWindowProperty", return_value=1):
            reset = Mock()
            poll_keys(False, reset=reset)
            reset.assert_called_once()


if __name__ == "__main__":
    unittest.main()
