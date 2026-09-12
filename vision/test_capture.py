"""Controlled fake camera tests exercise actual capture-thread synchronization."""

from queue import Queue
from threading import Event, get_ident
import unittest
from unittest.mock import patch

import numpy as np

from capture import LatestFrameCapture


class FakeCamera:
    def __init__(self):
        self.frames = Queue()
        self.read_started = Event()
        self.released = Event()
        self.release_count = 0
        self.read_thread = None
        self.release_thread = None

    def read(self):
        self.read_thread = get_ident()
        self.read_started.set()
        item = self.frames.get(timeout=3)
        if isinstance(item, Exception):
            raise item
        return item

    def release(self):
        self.release_thread = get_ident()
        self.release_count += 1
        self.released.set()


class CaptureTests(unittest.TestCase):
    def make_capture(self, camera):
        capture = LatestFrameCapture(camera)
        def cleanup():
            camera.frames.put((False, None))
            capture.close(timeout=2)
        self.addCleanup(cleanup)
        return capture

    def test_slow_consumer_gets_latest_not_a_queue_and_no_duplicate(self):
        camera = FakeCamera()
        for value in (1, 2, 3):
            camera.frames.put((True, np.full((2, 2, 3), value, dtype=np.uint8)))
        capture = self.make_capture(camera)
        # Wait for the third capture without consuming the first two.
        sample = capture.get_latest(after_sequence=2, timeout=2)
        self.assertIsNotNone(sample)
        self.assertEqual(sample.sequence, 3)
        self.assertTrue(np.all(sample.image == 3))
        self.assertIsNone(capture.get_latest(after_sequence=3, timeout=0))

    def test_timestamp_and_fps_are_measured_by_capture_worker(self):
        camera = FakeCamera()
        with patch("capture.perf_counter", side_effect=[10.0, 10.5, 11.0, 11.5]):
            camera.frames.put((True, np.zeros((2, 2, 3))))
            camera.frames.put((True, np.zeros((2, 2, 3))))
            capture = self.make_capture(camera)
            sample = capture.get_latest(after_sequence=1, timeout=2)
            self.assertEqual(sample.t_capture, 11.0)
            self.assertEqual(sample.fps, 2.0)
            camera.frames.put((False, None))
            self.assertTrue(capture.close(timeout=2))

    def test_held_frame_is_not_modified_when_camera_buffer_is_reused(self):
        camera = FakeCamera()
        buffer = np.ones((2, 2, 3), dtype=np.uint8)
        camera.frames.put((True, buffer))
        capture = self.make_capture(camera)
        first = capture.get_latest(timeout=2)
        buffer[:] = 2
        camera.frames.put((True, buffer))
        second = capture.get_latest(first.sequence, timeout=2)
        self.assertTrue(np.all(first.image == 1))
        self.assertTrue(np.all(second.image == 2))
        self.assertGreater(second.t_capture, first.t_capture)

    def test_read_failure_and_exception_reach_consumer_and_release(self):
        for outcome in ((False, None), RuntimeError("device disconnected")):
            with self.subTest(outcome=outcome):
                camera = FakeCamera()
                camera.frames.put(outcome)
                capture = self.make_capture(camera)
                with self.assertRaisesRegex(RuntimeError, "Capture failed"):
                    capture.get_latest(timeout=2)
                self.assertTrue(camera.released.wait(timeout=2))
                self.assertTrue(capture.close())
                self.assertEqual(camera.release_count, 1)

    def test_wait_and_shutdown_are_bounded_for_blocked_driver(self):
        camera = FakeCamera()
        capture = self.make_capture(camera)
        self.assertTrue(camera.read_started.wait(timeout=2))
        self.assertIsNone(capture.get_latest(timeout=0.01))
        self.assertFalse(capture.close(timeout=0.01))
        self.assertFalse(camera.released.is_set())  # No concurrent read/release.
        camera.frames.put((False, None))  # Native read finally returns.
        self.assertTrue(capture.close(timeout=2))
        self.assertEqual(camera.read_thread, camera.release_thread)
        self.assertNotEqual(camera.read_thread, get_ident())
        self.assertEqual(camera.release_count, 1)
        self.assertIsNone(capture.get_latest(timeout=0))
        self.assertTrue(capture.close())


if __name__ == "__main__":
    unittest.main()
