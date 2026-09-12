"""Assign detections to hand slots by positional continuity.

This is Rule 2, and it is the one that will bite you if you skip it.

MediaPipe returns a Left/Right handedness label. It gets them wrong - when
hands cross, when one is partly occluded, when a hand is rotated. A single
label flip teleports both cursors mid-song.

Do not trust the label. The model reasons about one frame in isolation; you
know the hand did not teleport since 16ms ago. Your prior is stronger than its
posterior.

TODO(vision): implement assign().
"""

# A hand cannot move more than roughly this far in a second, in normalized
# units. A candidate that would require more is a different object - a
# same-colored thing elsewhere in the room, or a reflection. Reject and coast.
MAX_SPEED = 2.0


def assign(detections, prev_positions, dt):
    """Match detections to slots 0 and 1.

    Args:
        detections:     list of (x, y, conf), normalized, this frame.
                        May be empty, may be longer than 2.
        prev_positions: [(x, y) or None, (x, y) or None] - last known position
                        per slot, None if that slot is currently LOST.
        dt:             seconds since the previous frame.

    Returns:
        [det_or_None, det_or_None] indexed by slot.

    Requirements:
      - Nearest-neighbour to each slot's last position.
      - Never bind both slots to the same detection.
      - Reject any match implying speed > MAX_SPEED (the velocity gate).
      - On cold start (both prev None), leftmost detection takes slot 0.
    """
    raise NotImplementedError("see PROJECT_BRIEF.md Rule 2")
