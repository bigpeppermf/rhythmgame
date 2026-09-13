"""Run camera-free smoke coverage against the current MediaPipe pipeline.

    python3 -m vision.tests.smoke_test

The original color-tracker skeleton was retired. Keep this entry point for
existing callers, but exercise the maintained state, packet, and capture tests.
"""
from pathlib import Path
import sys
import unittest


def main():
    vision_dir = Path(__file__).resolve().parents[1]
    sys.path.insert(0, str(vision_dir))
    suite = unittest.TestSuite()
    for pattern in ("test_hand_state.py", "test_udp.py", "test_capture.py"):
        suite.addTests(unittest.defaultTestLoader.discover(str(vision_dir), pattern=pattern))
    result = unittest.TextTestRunner(verbosity=2).run(suite)
    return 0 if result.wasSuccessful() else 1


if __name__ == "__main__":
    sys.exit(main())
