"""HSV colored-object tracker. The v1 recommendation.

Why HSV and not RGB: HSV separates *what color* from *how bright*, so a
threshold survives someone opening a door. RGB thresholds do not.

Choosing your colors:
  - Two hues at least 60 degrees apart in OpenCV's 0-179 H scale
  - Far from skin tone and from your clothes and walls
  - Saturated cyan and magenta are excellent
  - AVOID RED. Skin is full of red, and red wraps around H=0 which means two
    ranges instead of one.

With two distinct colors, slots.assign() becomes trivial - each color is its
own single-blob tracker and there is no association problem at all.

TODO(vision): implement detect().
"""
import cv2
import numpy as np

from .base import Tracker

# (H, S, V) lower/upper in OpenCV ranges: H 0-179, S 0-255, V 0-255.
# Tune these with the debug window's sliders, in the room you will demo in.
DEFAULT_RANGES = {
    "cyan":    ((80, 120, 80), (100, 255, 255)),
    "magenta": ((140, 100, 80), (170, 255, 255)),
}

MIN_AREA_FRAC = 0.0008   # smaller than this is sensor speckle
MAX_AREA_FRAC = 0.12     # larger means the lighting shifted, not a hand
MIN_CIRCULARITY = 0.45   # a held ball is roughly round; a shadow is not


class ColorTracker(Tracker):
    def __init__(self, ranges=None):
        self.ranges = ranges or DEFAULT_RANGES

    def detect(self, frame):
        """Return [(x, y, conf), ...] normalized.

        Pipeline:
          1. cv2.cvtColor -> HSV
          2. cv2.inRange per color
          3. morphological OPEN then CLOSE
             (open kills speckle, close fills holes - in that order)
          4. cv2.findContours, take the largest by area
          5. reject on MIN/MAX_AREA_FRAC and MIN_CIRCULARITY
          6. centroid from cv2.moments, NOT the bounding box center
             (moments are sub-pixel and noticeably steadier)
        """
        raise NotImplementedError("see PROJECT_BRIEF.md 'What to look for'")
