"""Tracker interface.

A tracker's only job is to answer: where are the hand-like things in this
frame? It does not smooth, does not assign slots, does not emit packets, and
above all does not know what a note is.

Keeping it this narrow is what makes colored-blob -> MediaPipe a one-file swap.
"""


class Tracker:
    def detect(self, frame):
        """Return a list of (x, y, conf) in normalized [0,1] frame coordinates.

        x=0 is frame-left, y=0 is frame-top. Mirroring is handled downstream -
        do not un-mirror here.

        May return zero, one, two, or more detections. Filtering down to two
        hands is slots.assign()'s job, not yours.
        """
        raise NotImplementedError

    def debug_overlay(self, frame):
        """Optional: return an annotated frame for the debug window."""
        return frame
